import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/service_failover.dart';
import '../models/service_health.dart';
import '../vpn/box_vpn_client.dart';
import '../vpn/cc_channel.dart';
import 'app_log.dart';
import 'settings_storage.dart';
import 'subscription/user_agent.dart';

/// Service-aware failover on top of L×Box routing.
///
/// Native urltest remains the cheap "is the node alive at all?" layer. This
/// manager adds the missing service semantics:
/// - observes real per-package connections through CommandClient;
/// - probes more often only while the service is actually active;
/// - immediately probes/fails over after repeated suspicious reconnects;
/// - classifies OpenAI region blocks semantically;
/// - keeps Telegram/ChatGPT/Gemini on independent selectors.
///
/// It deliberately owns a profilerClient ref directly instead of turning on
/// the user-facing TrafficProfiler recording. No global traffic log is written.
class ServiceFailoverManager extends ChangeNotifier {
  ServiceFailoverManager._();
  static final ServiceFailoverManager I = ServiceFailoverManager._();

  static const String settingsVar = 'service_failover_v1';
  static const String _geminiOverridesVar =
      'service_health_gemini_overrides_v1';
  static const Duration _tickInterval = Duration(seconds: 15);
  static const Duration _activeWindow = Duration(minutes: 3);
  static const Duration _failureWindow = Duration(seconds: 60);
  static const Duration _closedSeenTtl = Duration(minutes: 10);
  static const int _probeTimeoutMs = 5000;

  final CcChannel _cc = CcChannel.instance;
  final BoxVpnClient _vpn = BoxVpnClient.I;

  ServiceFailoverSettings _settings = ServiceFailoverSettings.defaults();
  final Map<ManagedService, ServiceFailoverStatus> _status = {
    for (final service in ManagedService.values)
      service: const ServiceFailoverStatus(),
  };
  final Map<ManagedService, DateTime> _lastActivity = {};
  final Map<ManagedService, DateTime> _lastHealthyTraffic = {};
  final Map<ManagedService, ListQueue<DateTime>> _failureSignals = {
    for (final service in ManagedService.values) service: ListQueue<DateTime>(),
  };
  final Map<ManagedService, bool> _probeBusy = {
    for (final service in ManagedService.values) service: false,
  };
  final Map<String, DateTime> _closedSeen = {};

  StreamSubscription<List<CcConnection>>? _connSub;
  Timer? _timer;
  bool _profilerHeld = false;
  DateTime? _nextProfilerRetryAt;
  bool _initialized = false;
  List<CcConnection> _latestConnections = const [];

  ServiceFailoverSettings get settings => _settings;
  ServiceFailoverStatus statusOf(ManagedService service) =>
      _status[service] ?? const ServiceFailoverStatus();
  DateTime? lastActivityOf(ManagedService service) => _lastActivity[service];

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _settings = ServiceFailoverSettings.fromRaw(
      await SettingsStorage.getVar(settingsVar, ''),
    );
    for (final service in ManagedService.values) {
      if (!_settings[service].enabled) {
        _status[service] = const ServiceFailoverStatus(
          phase: ServiceFailoverPhase.disabled,
        );
      }
    }
    await _syncMonitoring();
    notifyListeners();
  }

  Future<void> reload() async {
    _settings = ServiceFailoverSettings.fromRaw(
      await SettingsStorage.getVar(settingsVar, ''),
    );
    await _syncMonitoring();
    notifyListeners();
  }

  Future<void> updateConfig(
    ManagedService service,
    ServiceFailoverConfig config,
  ) async {
    _settings = _settings.replace(service, config);
    await SettingsStorage.setVar(settingsVar, _settings.encode());
    if (!config.enabled) {
      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.disabled,
        consecutiveFailures: 0,
        lastReason: 'disabled',
      );
    } else if (statusOf(service).phase == ServiceFailoverPhase.disabled) {
      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.idle,
        lastReason: 'enabled',
      );
    }
    await _syncMonitoring();
    notifyListeners();
  }

  /// User-visible "Test now". Unlike scheduled checks this may fail over
  /// immediately when the current node is demonstrably unsuitable.
  Future<void> testNow(ManagedService service) =>
      _evaluate(service, reason: 'manual_test', force: true);

  Future<void> _syncMonitoring() async {
    final need = ManagedService.values.any((s) => _settings[s].enabled);
    if (!need) {
      _timer?.cancel();
      _timer = null;
      await _connSub?.cancel();
      _connSub = null;
      if (_profilerHeld) {
        _profilerHeld = false;
        try {
          await _cc.releaseProfiler();
        } catch (_) {}
      }
      return;
    }

    _connSub ??= _cc.connections.listen(
      _onConnections,
      onError: (Object e, StackTrace _) {
        AppLog.I.warning('ServiceFailover: connections stream error: $e');
        // Keep our ref: CcChannel.restartProfiler() reconnects the native
        // profiler after tunnel restarts while refs > 0. Re-acquiring here
        // would double-count the same consumer.
      },
    );
    _timer ??= Timer.periodic(_tickInterval, (_) => unawaited(_tick()));
    await _ensureProfiler();
  }

  Future<void> _ensureProfiler() async {
    if (_profilerHeld) return;
    final now = DateTime.now();
    final retryAt = _nextProfilerRetryAt;
    if (retryAt != null && now.isBefore(retryAt)) return;
    try {
      await _cc.acquireProfiler();
      _profilerHeld = true;
      _nextProfilerRetryAt = null;
      AppLog.I.info('ServiceFailover: profiler observer attached');
    } catch (e) {
      // VPN/core can legitimately be down during app startup. The periodic
      // tick retries without surfacing this as a service failure.
      _nextProfilerRetryAt = now.add(const Duration(minutes: 1));
      AppLog.I.warning('ServiceFailover: profiler attach deferred: $e');
    }
  }

  void _onConnections(List<CcConnection> conns) {
    _latestConnections = conns;
    final now = DateTime.now();
    _trimClosedSeen(now);

    for (final service in ManagedService.values) {
      final config = _settings[service];
      if (!config.enabled || !config.passiveMonitor) continue;
      final packages = service.packages;
      var sawMeaningfulTraffic = false;
      var sawHealthyDownlink = false;

      for (final c in conns) {
        if (!packages.contains(c.packageName)) continue;
        if (!c.isClosed) {
          final delta = c.uplinkDelta + c.downlinkDelta;
          // Persistent Telegram/notification sockets are not user activity.
          // Only meaningful fresh traffic moves the service into the fast
          // schedule; keepalive-sized deltas remain on the background cadence.
          if (delta >= 4096) sawMeaningfulTraffic = true;
          if (c.downlinkDelta > 0) sawHealthyDownlink = true;
          continue;
        }
        if (_closedSeen.containsKey(c.id)) continue;
        _closedSeen[c.id] = now;
        if (isSuspiciousServiceClose(
          service,
          uplink: c.uplink,
          downlink: c.downlink,
        )) {
          _addFailureSignal(service, now);
        } else if (c.downlink > 0) {
          _clearFailureSignals(service);
        }
      }

      if (sawMeaningfulTraffic) _lastActivity[service] = now;
      if (sawHealthyDownlink) {
        _lastHealthyTraffic[service] = now;
        _clearFailureSignals(service);
        final st = statusOf(service);
        if (st.phase != ServiceFailoverPhase.probing &&
            st.phase != ServiceFailoverPhase.switching) {
          _status[service] = st.copyWith(
            phase: ServiceFailoverPhase.healthy,
            consecutiveFailures: 0,
            lastReason: 'live_traffic_ok',
          );
          notifyListeners();
        }
      }
    }
  }


  void _addFailureSignal(ManagedService service, DateTime now) {
    final q = _failureSignals[service]!;
    q.addLast(now);
    final cutoff = now.subtract(_failureWindow);
    while (q.isNotEmpty && q.first.isBefore(cutoff)) {
      q.removeFirst();
    }
    final st = statusOf(service);
    _status[service] = st.copyWith(
      phase: ServiceFailoverPhase.degraded,
      consecutiveFailures: q.length,
      lastReason: 'passive_reconnect_asymmetry',
    );
    notifyListeners();

    if (q.length >= _settings[service].failureThreshold) {
      unawaited(_evaluate(
        service,
        reason: 'passive_failure',
        force: false,
      ));
    }
  }

  void _clearFailureSignals(ManagedService service) {
    final q = _failureSignals[service]!;
    if (q.isEmpty) return;
    q.clear();
    _status[service] = statusOf(service).copyWith(consecutiveFailures: 0);
  }

  void _trimClosedSeen(DateTime now) {
    final cutoff = now.subtract(_closedSeenTtl);
    _closedSeen.removeWhere((_, ts) => ts.isBefore(cutoff));
  }

  Future<void> _tick() async {
    await _ensureProfiler();
    final now = DateTime.now();
    // The screen state is only a cadence gate. Passive failure detection is
    // event-driven and remains armed with the screen off; we merely suppress
    // frequent scheduled HTTP probes while the user is not interacting.
    final interactive = await _vpn.isScreenInteractive();
    for (final service in ManagedService.values) {
      final config = _settings[service];
      if (!config.enabled || _probeBusy[service] == true) continue;
      final st = statusOf(service);
      final activeAt = _lastActivity[service];
      final active = interactive &&
          activeAt != null &&
          now.difference(activeAt) <= _activeWindow;
      final seconds =
          active ? config.activeIntervalSec : config.backgroundIntervalSec;
      final last = st.lastProbeAt;
      if (last != null && now.difference(last).inSeconds < seconds) continue;
      unawaited(_evaluate(
        service,
        reason: active ? 'active_interval' : 'background_interval',
        force: false,
      ));
    }
  }

  Future<void> _evaluate(
    ManagedService service, {
    required String reason,
    required bool force,
  }) async {
    final config = _settings[service];
    if (!config.enabled || _probeBusy[service] == true) return;

    final now = DateTime.now();
    final lastSwitch = statusOf(service).lastSwitchAt;
    if (!force &&
        lastSwitch != null &&
        now.difference(lastSwitch).inSeconds < config.cooldownSec) {
      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.cooldown,
        lastReason: 'cooldown',
      );
      notifyListeners();
      return;
    }

    _probeBusy[service] = true;
    _status[service] = statusOf(service).copyWith(
      phase: ServiceFailoverPhase.probing,
      lastReason: reason,
      lastProbeAt: now,
    );
    notifyListeners();

    try {
      final groups = await _cc.getGroups();
      if (groups == null || groups.isEmpty) {
        _setProbeUnavailable(service, 'vpn_not_ready');
        return;
      }
      final group = _groupByTag(groups, service.groupTag);
      if (group == null) {
        _setProbeUnavailable(service, 'service_group_missing');
        return;
      }
      final current = _resolvePhysicalSelection(groups, service.groupTag);
      if (current.isEmpty || current == 'direct-out' || current == 'block') {
        // A service selector should never intentionally resolve to DIRECT. If
        // config restore left it there, treat it as a failed current node and
        // immediately choose a service-capable candidate.
        await _failover(
          service,
          groups,
          currentNode: current,
          reason: 'invalid_current:$current',
          allowIndeterminate: service == ManagedService.gemini,
        );
        return;
      }

      _status[service] = statusOf(service).copyWith(currentNode: current);
      notifyListeners();

      final outcome = await _probeNode(service, current);
      final passiveForced = reason == 'passive_failure';
      final currentBad = outcome.verdict == _ProbeVerdict.failed ||
          outcome.verdict == _ProbeVerdict.blocked ||
          passiveForced;

      if (!currentBad) {
        _clearFailureSignals(service);
        _status[service] = statusOf(service).copyWith(
          phase: outcome.verdict == _ProbeVerdict.indeterminate
              ? ServiceFailoverPhase.uncertain
              : ServiceFailoverPhase.healthy,
          consecutiveFailures: 0,
          lastReason: reason,
          lastProbeAt: DateTime.now(),
          lastProbeDetail: outcome.detail,
        );
        notifyListeners();
        return;
      }

      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.degraded,
        lastProbeAt: DateTime.now(),
        lastProbeDetail: outcome.detail,
      );
      notifyListeners();

      await _failover(
        service,
        groups,
        currentNode: current,
        reason: outcome.verdict == _ProbeVerdict.blocked
            ? 'region_blocked'
            : reason,
        allowIndeterminate: service == ManagedService.gemini,
      );
    } catch (e, st) {
      AppLog.I.warning('ServiceFailover ${service.id}: evaluation failed: $e\n$st');
      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.degraded,
        lastReason: 'probe_error',
        lastProbeAt: DateTime.now(),
        lastProbeDetail: e.toString(),
      );
      notifyListeners();
    } finally {
      _probeBusy[service] = false;
    }
  }

  Future<void> _failover(
    ManagedService service,
    List<CcGroup> groups, {
    required String currentNode,
    required String reason,
    required bool allowIndeterminate,
  }) async {
    final config = _settings[service];
    final group = _groupByTag(groups, service.groupTag);
    if (group == null) {
      _setProbeUnavailable(service, 'service_group_missing');
      return;
    }

    final candidates = _candidateNodes(service, group, currentNode)
        .take(config.maxCandidates)
        .toList(growable: false);
    _status[service] = statusOf(service).copyWith(
      phase: ServiceFailoverPhase.switching,
      lastReason: reason,
    );
    notifyListeners();

    for (final candidate in candidates) {
      final outcome = await _probeNode(service, candidate.tag);
      final acceptable = outcome.verdict == _ProbeVerdict.available ||
          (allowIndeterminate &&
              outcome.verdict == _ProbeVerdict.indeterminate);
      if (!acceptable) continue;

      final ok = await _cc.selectOutbound(service.groupTag, candidate.tag);
      if (!ok) continue;
      await _closeServiceConnections(service);
      _clearFailureSignals(service);
      final switchedAt = DateTime.now();
      _status[service] = statusOf(service).copyWith(
        phase: ServiceFailoverPhase.cooldown,
        currentNode: candidate.tag,
        lastSwitchAt: switchedAt,
        lastProbeAt: switchedAt,
        consecutiveFailures: 0,
        lastReason: reason,
        lastProbeDetail: outcome.detail,
      );
      AppLog.I.info(
        'ServiceFailover ${service.id}: $currentNode → ${candidate.tag} ($reason)',
      );
      notifyListeners();
      return;
    }

    _status[service] = statusOf(service).copyWith(
      phase: ServiceFailoverPhase.degraded,
      lastReason: 'no_healthy_candidate:$reason',
      lastProbeAt: DateTime.now(),
    );
    AppLog.I.warning(
      'ServiceFailover ${service.id}: no healthy candidate after $reason',
    );
    notifyListeners();
  }

  List<CcOutbound> _candidateNodes(
    ManagedService service,
    CcGroup group,
    String current,
  ) {
    final physical = group.items.where((o) {
      final type = o.type.toLowerCase();
      return o.tag != current &&
          o.tag != 'direct-out' &&
          o.tag != 'block' &&
          type != 'selector' &&
          type != 'urltest';
    }).toList();
    final preferred = service.preferredNodes;
    int prefRank(String tag) {
      final i = preferred.indexOf(tag);
      return i < 0 ? 999 : i;
    }

    physical.sort((a, b) {
      final pa = prefRank(a.tag);
      final pb = prefRank(b.tag);
      if (pa != pb) return pa.compareTo(pb);
      final ad = a.urlTestDelay > 0 ? a.urlTestDelay : 1 << 30;
      final bd = b.urlTestDelay > 0 ? b.urlTestDelay : 1 << 30;
      final dc = ad.compareTo(bd);
      if (dc != 0) return dc;
      return a.tag.compareTo(b.tag);
    });
    return physical;
  }

  Future<_ProbeOutcome> _probeNode(
    ManagedService service,
    String node,
  ) async {
    try {
      final result = await _cc.getUrlViaOutbound(
        node,
        link: service.probeUrl,
        timeoutMs: _probeTimeoutMs,
        maxBytes: service == ManagedService.gemini ? 8192 : 4096,
        userAgent: resolveAppUserAgent(),
      );

      switch (service) {
        case ManagedService.chatgpt:
          final h = ServiceHealthResult.fromExchange(
            service: ServiceHealthService.chatgpt,
            status: result.status,
            elapsedMs: result.elapsedMs,
            body: result.content,
            error: result.error,
          );
          return switch (h.state) {
            ServiceHealthState.available => _ProbeOutcome.available(
                'OpenAI ${result.status} ${result.elapsedMs}ms'),
            ServiceHealthState.blocked => _ProbeOutcome.blocked(h.detail),
            _ => _ProbeOutcome.failed(
                h.detail.isEmpty ? result.error : h.detail),
          };

        case ManagedService.gemini:
          final override = await _geminiOverride(node);
          if (override == 'blocked') {
            return const _ProbeOutcome.blocked('gemini_region_blocked_manual');
          }
          if (override == 'available') {
            return _ProbeOutcome.available(
                'Gemini owner-verified ${result.elapsedMs}ms');
          }
          final h = ServiceHealthResult.fromExchange(
            service: ServiceHealthService.gemini,
            status: result.status,
            elapsedMs: result.elapsedMs,
            body: result.content,
            error: result.error,
          );
          return switch (h.state) {
            ServiceHealthState.blocked => _ProbeOutcome.blocked(h.detail),
            ServiceHealthState.failed => _ProbeOutcome.failed(
                h.detail.isEmpty ? result.error : h.detail),
            ServiceHealthState.available => _ProbeOutcome.available(h.detail),
            _ => _ProbeOutcome.indeterminate(
                'Gemini web reachable; signed-in region unverified'),
          };

        case ManagedService.telegram:
          if (result.error.isNotEmpty) {
            return _ProbeOutcome.failed(result.error);
          }
          // Telegram's public web endpoint is only a candidate reachability
          // pre-check. Actual MTProto health comes from passive byte/reconnect
          // observations after selection.
          if (result.status > 0 && result.status < 500) {
            return _ProbeOutcome.available(
                'Telegram web ${result.status} ${result.elapsedMs}ms');
          }
          return _ProbeOutcome.failed('HTTP ${result.status}');
      }
    } catch (e) {
      return _ProbeOutcome.failed(e.toString());
    }
  }

  Future<String?> _geminiOverride(String node) async {
    try {
      final raw = await SettingsStorage.getVar(_geminiOverridesVar, '{}');
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded[node]?.toString().toLowerCase();
    } catch (_) {}
    return null;
  }

  Future<void> _closeServiceConnections(ManagedService service) async {
    final packages = service.packages;
    final ids = <String>{
      for (final c in _latestConnections)
        if (!c.isClosed && packages.contains(c.packageName) && c.id.isNotEmpty)
          c.id,
    };
    for (final id in ids) {
      try {
        await _cc.closeConnection(id);
      } catch (_) {}
    }
  }

  CcGroup? _groupByTag(List<CcGroup> groups, String tag) {
    for (final g in groups) {
      if (g.tag == tag) return g;
    }
    return null;
  }

  String _resolvePhysicalSelection(List<CcGroup> groups, String groupTag) {
    var current = groupTag;
    final seen = <String>{};
    for (var i = 0; i < 5; i++) {
      if (!seen.add(current)) return '';
      final group = _groupByTag(groups, current);
      if (group == null) return current == groupTag ? '' : current;
      final selected = group.selected;
      if (selected.isEmpty) return '';
      current = selected;
    }
    return current;
  }

  void _setProbeUnavailable(ManagedService service, String detail) {
    _status[service] = statusOf(service).copyWith(
      phase: ServiceFailoverPhase.idle,
      lastReason: detail,
      lastProbeAt: DateTime.now(),
      lastProbeDetail: detail,
    );
    notifyListeners();
  }
}

enum _ProbeVerdict { available, indeterminate, blocked, failed }

class _ProbeOutcome {
  const _ProbeOutcome(this.verdict, this.detail);
  const _ProbeOutcome.available(String detail)
      : this(_ProbeVerdict.available, detail);
  const _ProbeOutcome.indeterminate(String detail)
      : this(_ProbeVerdict.indeterminate, detail);
  const _ProbeOutcome.blocked(String detail)
      : this(_ProbeVerdict.blocked, detail);
  const _ProbeOutcome.failed(String detail)
      : this(_ProbeVerdict.failed, detail);

  final _ProbeVerdict verdict;
  final String detail;
}

@visibleForTesting
bool isSuspiciousServiceClose(
  ManagedService service, {
  required int uplink,
  required int downlink,
}) {
  if (service == ManagedService.telegram) {
    // Production regression guard: the broken node observed on 2026-11-02
    // uploaded tens/hundreds of KiB to a Telegram DC, received only a few
    // hundred bytes, then reconnected. Tiny control connections are ignored.
    return uplink >= 16 * 1024 &&
        downlink < 1024 &&
        downlink * 20 < uplink;
  }
  // For TLS apps a single zero-response close is weak evidence. The manager
  // requires several such signals in the rolling failure window and then runs
  // a semantic service probe before switching.
  return uplink >= 1024 && downlink == 0;
}

