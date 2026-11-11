import 'dart:async';

import '../../models/service_health.dart';
import '../../vpn/cc_channel.dart';
import '../subscription/user_agent.dart';
import 'context.dart';
import 'contract/errors.dart';

/// On-demand diagnostics executed ONLY inside the already running LBox core.
class MonitorProbes {
  MonitorProbes._();
  static final MonitorProbes instance = MonitorProbes._();
  static const allowedDirections = <String>{
    'chatgpt-auto', 'gemini-auto', 'telegram-auto',
  };
  static const allowedKinds = <String>{'ping', 'service'};
  static const _timeoutMs = 5000;
  static const _pingUrl = 'https://cp.cloudflare.com/generate_204';

  final Map<String, Map<String, Object?>> _checks = {};
  int _generation = 0;

  Map<String, Object?> get snapshot => {
        'ok': true,
        'source': 'lbox-core',
        'checks': {
          for (final direction in allowedDirections)
            direction: {
              for (final kind in allowedKinds)
                if (_checks.containsKey('$direction/$kind'))
                  kind: Map<String, Object?>.from(_checks['$direction/$kind']!),
            },
        },
      };

  /// Resolve a currently selected physical outbound from live kernel groups.
  static String? resolvePhysical(List<CcGroup> groups, String direction) {
    final byTag = {for (final group in groups) group.tag: group};
    if (!byTag.containsKey(direction)) return null;
    final visited = <String>{};
    var tag = direction;
    for (var i = 0; i < 12; i++) {
      if (!visited.add(tag)) return null;
      final group = byTag[tag];
      if (group == null) return tag;
      if (group.selected.isEmpty) return null;
      tag = group.selected;
    }
    return null;
  }

  Future<Map<String, Object?>> start({
    required DebugContext context,
    required String direction,
    required String kind,
  }) async {
    if (!allowedDirections.contains(direction)) {
      throw const BadRequest('direction must be chatgpt-auto|gemini-auto|telegram-auto');
    }
    if (!allowedKinds.contains(kind)) {
      throw const BadRequest('kind must be ping|service');
    }
    if (!context.requireHome().state.tunnelUp) {
      throw const Conflict('VPN tunnel not connected');
    }
    final key = '$direction/$kind';
    final old = _checks[key];
    if (old?['state'] == 'running') {
      throw const Conflict('the same test is already running');
    }
    final finishedAt = old?['checked_at_unix_s'];
    if (finishedAt is int &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - finishedAt < 4) {
      throw const Conflict('test cooldown: retry in a few seconds');
    }
    final generation = ++_generation;
    _checks[key] = {
      'direction': direction,
      'kind': kind,
      'state': 'running',
      'selected_tag': null,
      'started_at_unix_s': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'generation': generation,
    };

    String tag;
    try {
      final groups = await CcChannel.instance
          .getGroups()
          .timeout(const Duration(seconds: 2));
      if (groups == null || groups.isEmpty) {
        throw const Conflict('live LBox kernel groups unavailable');
      }
      tag = resolvePhysical(groups, direction) ?? '';
      if (tag.isEmpty || tag == 'block' || tag == 'block-out') {
        throw const Conflict('no active outbound for direction');
      }
      if (!context.requireHome().state.tunnelUp) {
        throw const Conflict('VPN tunnel disconnected during selection');
      }
    } catch (_) {
      if (_checks[key]?['generation'] == generation) _checks.remove(key);
      rethrow;
    }

    _checks[key] = {
      ..._checks[key]!,
      'selected_tag': tag,
    };
    unawaited(_run(
      key: key,
      tag: tag,
      direction: direction,
      kind: kind,
      generation: generation,
    ));
    return {
      'ok': true,
      'accepted': true,
      'direction': direction,
      'kind': kind,
      'selected_tag': tag,
    };
  }

  Future<void> _run({
    required String key,
    required String tag,
    required String direction,
    required String kind,
    required int generation,
  }) async {
    final core = CcChannel.instance;
    var state = 'failed';
    var latencyMs = 0;
    var httpStatus = 0;
    var message = 'technical_error';
    try {
      if (kind == 'ping') {
        final probe = await core
            .urlTestOutbound(tag, link: _pingUrl, timeoutMs: _timeoutMs)
            .timeout(const Duration(seconds: 8));
        state = probe.ok ? 'available' : 'failed';
        latencyMs = probe.ok ? probe.delay : 0;
        message = probe.ok ? 'urltest_reachable' : errorCategory(probe.error);
      } else {
        final isChatGPT = direction == 'chatgpt-auto';
        final isGemini = direction == 'gemini-auto';
        final url = isChatGPT
            ? 'https://api.openai.com/v1/models'
            : isGemini
                ? 'https://gemini.google.com/app'
                : 'https://web.telegram.org/a/';
        final result = await core
            .getUrlViaOutbound(
              tag,
              link: url,
              timeoutMs: _timeoutMs,
              maxBytes: isGemini ? 8192 : 4096,
              userAgent: resolveAppUserAgent(),
            )
            .timeout(const Duration(seconds: 8));
        latencyMs = result.elapsedMs;
        httpStatus = result.status;
        if (isChatGPT || isGemini) {
          final judgement = ServiceHealthResult.fromExchange(
            service: isChatGPT
                ? ServiceHealthService.chatgpt
                : ServiceHealthService.gemini,
            status: result.status,
            elapsedMs: result.elapsedMs,
            body: result.content,
            error: result.error,
          );
          state = judgement.state.name;
          message = result.error.isNotEmpty
              ? errorCategory(result.error)
              : judgement.detail.isEmpty
                  ? (state == 'available' ? 'api_reachable' : state)
                  : judgement.detail;
          // Generic 403 is NOT evidence of a regional block.
          if (result.status == 403 && state != 'blocked') {
            state = 'indeterminate';
            message = 'generic_403_not_region_proof';
          }
          // Gemini fallback proves transport only, never region clearance.
          if (isGemini && state == 'failed') {
            try {
              final fallback = await core.urlTestOutbound(
                tag, link: url, timeoutMs: _timeoutMs,
              ).timeout(const Duration(seconds: 7));
              if (fallback.ok) {
                state = 'indeterminate';
                message = 'gemini_transport_only';
                latencyMs = fallback.delay;
              }
            } catch (_) {
              // Retain technical failure.
            }
          }
        } else {
          state = result.error.isNotEmpty
              ? 'failed'
              : result.status >= 200 && result.status < 400
                  ? 'available'
                  : result.status == 451
                      ? 'blocked'
                      : result.status == 401 || result.status == 403
                          ? 'indeterminate'
                          : 'failed';
          message = result.error.isNotEmpty
              ? errorCategory(result.error)
              : state == 'available'
                  ? 'web_transport_reachable'
                  : state == 'blocked'
                      ? 'http_451'
                      : 'http_status_ambiguous';
        }
      }
    } on TimeoutException {
      state = 'failed';
      message = 'timeout';
    } catch (_) {
      state = 'failed';
      message = 'core_probe_failed';
    }
    if (_checks[key]?['generation'] != generation) return;
    _checks[key] = {
      'direction': direction,
      'kind': kind,
      'selected_tag': tag,
      'state': state,
      'latency_ms': latencyMs,
      'http_status': httpStatus,
      'message': message,
      'started_at_unix_s': _checks[key]?['started_at_unix_s'],
      'checked_at_unix_s': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'generation': generation,
    };
  }

  /// Never export arbitrary native exception text to the companion.
  static String errorCategory(String source) {
    final s = source.toLowerCase();
    if (s.contains('timeout') || s.contains('deadline')) return 'timeout';
    if (s.contains('dns') || s.contains('lookup')) return 'dns_error';
    if (s.contains('refused')) return 'connection_refused';
    if (s.contains('tls') || s.contains('certificate')) return 'tls_error';
    return 'transport_error';
  }
}
