part of '../home_controller.dart';

/// Explicit per-node service checks for the Home list (§693).
///
/// This mixin deliberately has no timer/resume/connect hook. Every run is
/// initiated by a user gesture because each check sends real HTTP traffic
/// through the selected outbound tag.
mixin _ServiceHealthMixin on ChangeNotifier {
  HomeState get _state;
  CcChannel get _cc;
  void _emit(HomeState next);
  void _addDebug(DebugSource source, String message);

  static const int _serviceHealthConcurrency = 4;
  static const int _serviceHealthTimeoutMs = 5000;
  static const int _serviceHealthSmallBody = 1024;
  static const int _serviceHealthOpenAiBody = 4096;

  static const String _netUrl = 'https://cp.cloudflare.com/generate_204';
  static const String _youtubeUrl = 'https://www.youtube.com/generate_204';
  static const String _chatgptUrl = 'https://api.openai.com/v1/models';

  bool _serviceHealthRunning = false;
  bool get serviceHealthRunning => _serviceHealthRunning;
  int _serviceHealthEpoch = 0;

  /// Tunnel teardown invalidates every in-flight result without recursively
  /// emitting state from inside HomeController._emit.
  void _invalidateServiceHealthRun() {
    if (_serviceHealthRunning) {
      _serviceHealthRunning = false;
      _serviceHealthEpoch++;
    }
  }


  bool _serviceHealthIsUntested(NodeServiceHealth value) =>
      value.net.state == ServiceHealthState.untested &&
      value.youtube.state == ServiceHealthState.untested &&
      value.chatgpt.state == ServiceHealthState.untested;

  /// Cheap automatic check for the currently selected real node. Unlike the
  /// list-wide sweep this sends only three requests and runs at most once per
  /// node per tunnel session, so opening/switching a group immediately gives
  /// the badges useful meaning without a 63-node background benchmark.
  Future<void> runActiveNodeServiceHealth(String tag) async {
    if (!_state.tunnelUp || _serviceHealthRunning) return;
    final type = (_state.activeModel[tag]?.type ?? '').toLowerCase();
    if (type == 'block' || type == 'selector' || type == 'urltest') return;
    final existing = _state.serviceHealth[tag] ?? NodeServiceHealth.untested;
    if (!_serviceHealthIsUntested(existing)) return;

    final checking = Map<String, NodeServiceHealth>.from(_state.serviceHealth)
      ..[tag] = NodeServiceHealth.checking;
    _emit(_state.copyWith(serviceHealth: checking));
    final result = await _checkNodeServices(tag);
    if (!_state.tunnelUp || _serviceHealthRunning) return;
    final updated = Map<String, NodeServiceHealth>.from(_state.serviceHealth)
      ..[tag] = result;
    _emit(_state.copyWith(serviceHealth: updated));
  }

  /// Starts a bounded list-wide service check. A second call while active
  /// cancels scheduling and invalidates late results from the old generation.
  Future<void> runMassServiceHealth({List<String>? order}) async {
    if (!_state.tunnelUp) return;
    if (_serviceHealthRunning) {
      cancelServiceHealth();
      return;
    }

    final nodes = List<String>.from(order ?? _state.nodes).where((tag) {
      final type = (_state.activeModel[tag]?.type ?? '').toLowerCase();
      return type != 'block' && type != 'selector' && type != 'urltest';
    }).toList(growable: false);
    if (nodes.isEmpty) return;

    _serviceHealthRunning = true;
    final epoch = ++_serviceHealthEpoch;
    final initial = Map<String, NodeServiceHealth>.from(_state.serviceHealth);
    for (final tag in nodes) {
      initial[tag] = NodeServiceHealth.checking;
    }
    _emit(_state.copyWith(serviceHealth: initial));

    var nextIndex = 0;
    Future<void> worker() async {
      while (_serviceHealthRunning && epoch == _serviceHealthEpoch) {
        final index = nextIndex++;
        if (index >= nodes.length) return;
        final tag = nodes[index];
        final result = await _checkNodeServices(tag);
        if (!_serviceHealthRunning || epoch != _serviceHealthEpoch) return;
        final updated = Map<String, NodeServiceHealth>.from(_state.serviceHealth)
          ..[tag] = result;
        _emit(_state.copyWith(serviceHealth: updated));
      }
    }

    final workerCount = nodes.length < _serviceHealthConcurrency
        ? nodes.length
        : _serviceHealthConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    if (epoch == _serviceHealthEpoch) {
      _serviceHealthRunning = false;
      // The running flag lives on the controller, so emit once to repaint the
      // header action even when the last node result already painted the list.
      _emit(_state.copyWith());
      _addDebug(DebugSource.app,
          'Service health check finished: ${nodes.length} node(s)');
    }
  }

  void cancelServiceHealth() {
    if (!_serviceHealthRunning) return;
    _serviceHealthRunning = false;
    _serviceHealthEpoch++;

    // Keep finished results, but do not leave cancelled nodes looking as if a
    // check were still running. In-flight unary calls may finish in the core;
    // their generation is stale and their result is ignored above.
    final updated = <String, NodeServiceHealth>{};
    var changed = false;
    for (final entry in _state.serviceHealth.entries) {
      final h = entry.value;
      final checking = h.net.state == ServiceHealthState.checking ||
          h.youtube.state == ServiceHealthState.checking ||
          h.chatgpt.state == ServiceHealthState.checking;
      if (checking) {
        updated[entry.key] = NodeServiceHealth.untested;
        changed = true;
      } else {
        updated[entry.key] = h;
      }
    }
    _emit(changed
        ? _state.copyWith(serviceHealth: updated)
        : _state.copyWith());
    _addDebug(DebugSource.app, 'Service health check cancelled');
  }

  Future<NodeServiceHealth> _checkNodeServices(String tag) async {
    final net = await _checkService(
      tag,
      service: ServiceHealthService.net,
      url: _netUrl,
      maxBytes: _serviceHealthSmallBody,
    );
    final youtube = await _checkService(
      tag,
      service: ServiceHealthService.youtube,
      url: _youtubeUrl,
      maxBytes: _serviceHealthSmallBody,
    );
    final chatgpt = await _checkService(
      tag,
      service: ServiceHealthService.chatgpt,
      url: _chatgptUrl,
      maxBytes: _serviceHealthOpenAiBody,
    );
    return NodeServiceHealth(net: net, youtube: youtube, chatgpt: chatgpt);
  }

  Future<ServiceHealthResult> _checkService(
    String tag, {
    required ServiceHealthService service,
    required String url,
    required int maxBytes,
  }) async {
    try {
      final result = await _cc.getUrlViaOutbound(
        tag,
        link: url,
        timeoutMs: _serviceHealthTimeoutMs,
        maxBytes: maxBytes,
        userAgent: resolveAppUserAgent(),
      );
      return ServiceHealthResult.fromExchange(
        service: service,
        status: result.status,
        elapsedMs: result.elapsedMs,
        body: result.content,
        error: result.error,
      );
    } catch (error) {
      return ServiceHealthResult.fromExchange(
        service: service,
        status: 0,
        elapsedMs: 0,
        body: '',
        error: error.toString(),
      );
    }
  }
}
