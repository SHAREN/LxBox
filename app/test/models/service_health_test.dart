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
    test('Gemini credential-free 200 is region-indeterminate', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.gemini,
        status: 200,
        elapsedMs: 280,
        body: '<html><base href="https://aistudio.google.com/"></html>',
        error: '',
      );
      expect(result.state, ServiceHealthState.indeterminate);
      expect(result.detail, 'gemini_region_not_verified');
    });

    test('Gemini Available Regions redirect page is region blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.gemini,
        status: 200,
        elapsedMs: 320,
        body:
            '<title>Available regions for Google AI Studio and Gemini API</title><a href="/gemini-api/docs/available-regions">regions</a>',
        error: '',
      );
      expect(result.state, ServiceHealthState.blocked);
      expect(result.detail, 'gemini_region_blocked');
    });

    test('Gemini signed-in country block text is region blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.gemini,
        status: 200,
        elapsedMs: 290,
        body: 'Gemini пока не поддерживается в вашей стране. Мы сообщим, когда это изменится.',
        error: '',
      );
      expect(result.state, ServiceHealthState.blocked);
    });

    test('Gemini generic 403 is technical failure, not region blocked', () {
      final result = ServiceHealthResult.fromExchange(
        service: ServiceHealthService.gemini,
        status: 403,
        elapsedMs: 300,
        body: 'permission denied',
        error: '',
      );
      expect(result.state, ServiceHealthState.failed);
      expect(result.detail, 'HTTP 403');
    });

  });
}
