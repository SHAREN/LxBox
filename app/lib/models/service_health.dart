/// Per-node service reachability shown on the Home node list (§693).
///
/// The values are intentionally session-only. A service check is real traffic
/// through an outbound, so it must only be populated by an explicit user action.
enum ServiceHealthState {
  untested,
  checking,
  available,
  blocked,
  failed,
}

enum ServiceHealthService {
  net,
  youtube,
  chatgpt,
}

class ServiceHealthResult {
  const ServiceHealthResult({
    this.state = ServiceHealthState.untested,
    this.httpStatus = 0,
    this.elapsedMs = 0,
    this.detail = '',
  });

  final ServiceHealthState state;
  final int httpStatus;
  final int elapsedMs;
  final String detail;

  static const untested = ServiceHealthResult();
  static const checking = ServiceHealthResult(state: ServiceHealthState.checking);

  /// Classifies one completed HTTP exchange without depending on the VPN channel
  /// model. [error] means no HTTP response was obtained.
  factory ServiceHealthResult.fromExchange({
    required ServiceHealthService service,
    required int status,
    required int elapsedMs,
    required String body,
    required String error,
  }) {
    if (error.isNotEmpty) {
      return ServiceHealthResult(
        state: ServiceHealthState.failed,
        httpStatus: status,
        elapsedMs: elapsedMs,
        detail: error,
      );
    }

    switch (service) {
      case ServiceHealthService.net:
        return ServiceHealthResult(
          state: status > 0 && status < 500
              ? ServiceHealthState.available
              : ServiceHealthState.failed,
          httpStatus: status,
          elapsedMs: elapsedMs,
          detail: status >= 500 ? 'HTTP $status' : '',
        );

      case ServiceHealthService.youtube:
        if (status == 403 || status == 451) {
          return ServiceHealthResult(
            state: ServiceHealthState.blocked,
            httpStatus: status,
            elapsedMs: elapsedMs,
            detail: 'HTTP $status',
          );
        }
        return ServiceHealthResult(
          state: status > 0 && status < 500
              ? ServiceHealthState.available
              : ServiceHealthState.failed,
          httpStatus: status,
          elapsedMs: elapsedMs,
          detail: status >= 500 ? 'HTTP $status' : '',
        );

      case ServiceHealthService.chatgpt:
        final regionBlocked = status == 403 &&
            (body.contains('unsupported_country_region_territory') ||
                body.contains('Country, region, or territory not supported'));
        if (regionBlocked) {
          return ServiceHealthResult(
            state: ServiceHealthState.blocked,
            httpStatus: status,
            elapsedMs: elapsedMs,
            detail: 'unsupported_country_region_territory',
          );
        }
        final available = (status >= 200 && status < 400) ||
            status == 401 ||
            status == 429;
        return ServiceHealthResult(
          state: available
              ? ServiceHealthState.available
              : ServiceHealthState.failed,
          httpStatus: status,
          elapsedMs: elapsedMs,
          detail: available || status <= 0 ? '' : 'HTTP $status',
        );
    }
  }
}

class NodeServiceHealth {
  const NodeServiceHealth({
    this.net = ServiceHealthResult.untested,
    this.youtube = ServiceHealthResult.untested,
    this.chatgpt = ServiceHealthResult.untested,
  });

  final ServiceHealthResult net;
  final ServiceHealthResult youtube;
  final ServiceHealthResult chatgpt;

  static const untested = NodeServiceHealth();
  static const checking = NodeServiceHealth(
    net: ServiceHealthResult.checking,
    youtube: ServiceHealthResult.checking,
    chatgpt: ServiceHealthResult.checking,
  );
}
