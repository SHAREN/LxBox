import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/service_health.dart';

void main() {
  group('ServiceHealthResult.fromExchange', () {
    test('NET accepts a real non-5xx HTTP response', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.net,
        status: 204,
        elapsedMs: 120,
        body: '',
        error: '',
      );
      expect(result.state, ServiceHealthState.available);
    });

    test('transport error is technical failure', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.net,
        status: 0,
        elapsedMs: 5000,
        body: '',
        error: 'timeout',
      );
      expect(result.state, ServiceHealthState.failed);
      expect(result.detail, 'timeout');
    });

    test('YouTube explicit deny is blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.youtube,
        status: 451,
        elapsedMs: 250,
        body: '',
        error: '',
      );
      expect(result.state, ServiceHealthState.blocked);
    });

    test('OpenAI 401 means the service is reachable', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.chatgpt,
        status: 401,
        elapsedMs: 300,
        body: '{"error":{"code":"invalid_api_key"}}',
        error: '',
      );
      expect(result.state, ServiceHealthState.available);
    });

    test('OpenAI unsupported-country 403 is region blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.chatgpt,
        status: 403,
        elapsedMs: 300,
        body:
            '{"error":{"code":"unsupported_country_region_territory","message":"Country, region, or territory not supported"}}',
        error: '',
      );
      expect(result.state, ServiceHealthState.blocked);
      expect(result.detail, 'unsupported_country_region_territory');
    });

    test('generic OpenAI 403 is not mislabeled as region blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.chatgpt,
        status: 403,
        elapsedMs: 300,
        body: '{"error":{"code":"waf_denied"}}',
        error: '',
      );
      expect(result.state, ServiceHealthState.failed);
      expect(result.detail, 'HTTP 403');
    });
  });
}
