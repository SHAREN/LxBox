import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/services/debug/context.dart';
import 'package:lxbox/services/debug/contract/errors.dart';
import 'package:lxbox/services/debug/debug_registry.dart';
import 'package:lxbox/services/debug/handlers/action.dart';
import 'package:lxbox/services/debug/transport/request.dart';
import 'package:lxbox/services/debug/transport/response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.leadaxe.lxbox/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late HomeController home;
  final calls = <String>[];
  var verdict = 'api_available';

  Future<Map> check(String kind, String tag, {bool extra = false}) async {
    final payload = <String, Object?>{'tag': tag, 'kind': kind};
    if (kind == 'api') payload['api_key'] = '[REDACTED_SECRET]';
    if (extra) payload['url'] = 'https://example.invalid';
    final response = await actionHandler(
      DebugRequest.forTest(
        method: 'POST',
        path: '/action/gemini-node-probe',
        body: utf8.encode(jsonEncode(payload)),
      ),
      DebugContext(registry: DebugRegistry.I, appStartedAt: DateTime.utc(2026)),
    );
    return (response as JsonResponse).body as Map;
  }

  setUp(() {
    calls.clear();
    verdict = 'api_available';
    messenger.setMockMethodCallHandler(channel, (method) async {
      calls.add(method.method);
      if (method.method == 'ccGetOutbounds') {
        return [
          {'tag': 'node-A', 'type': 'vless'},
          {'tag': 'node-B', 'type': 'trojan'},
          {'tag': 'selector', 'type': 'selector'},
        ];
      }
      if (method.method == 'ccGetGroups') {
        return [
          {
            'tag': 'gemini-auto', 'selected': 'node-A', 'type': 'selector',
            'selectable': true, 'isExpand': false,
            'items': [
              {'tag': 'node-A', 'type': 'vless'},
              {'tag': 'node-B', 'type': 'trojan'},
            ],
          }
        ];
      }
      if (method.method == 'ccUrlTestOutbound') {
        expect((method.arguments as Map)['tag'], 'node-A');
        return {'delay': 115, 'error': ''};
      }
      if (method.method == 'ccGeminiApiOutbound') {
        expect((method.arguments as Map)['tag'], 'node-A');
        expect((method.arguments as Map)['apiKey'], '[REDACTED_SECRET]');
        return {
          'verified_tag': 'node-A', 'verdict': verdict,
          'http_status': verdict == 'api_available' ? 200 : 400,
          'elapsed_ms': 150,
        };
      }
      return null;
    });
    home = HomeController();
    DebugRegistry.I.home = home;
    home.debugSeedNodeState(group: 'vpn-1', activeNode: 'node-A');
  });
  tearDown(() {
    DebugRegistry.I.home = null;
    home.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('ping through physical node never selects a new VPN route', () async {
    final response = await check('ping', 'node-A');
    expect(response['verdict'], 'ping_ok');
    expect(response['latency_ms'], 115);
    expect(calls, isNot(contains('ccSelectOutbound')));
  });

  test('Google API outcomes are distinct and secrets not returned', () async {
    final good = await check('api', 'node-A');
    expect(good['verdict'], 'api_available');
    expect(good['http_status'], 200);
    expect(jsonEncode(good), isNot(contains('[REDACTED_SECRET]')));
    verdict = 'region_blocked_api';
    final blocked = await check('api', 'node-A');
    expect(blocked['verdict'], 'region_blocked_api');
    expect(blocked['http_status'], 400);
    expect(calls, isNot(contains('ccSelectOutbound')));
  });

  test('selectors, unknown tags and untrusted request keys rejected', () async {
    for (final kindAndTag in [
      ['ping', 'selector'], ['ping', 'unknown'],
    ]) {
      await expectLater(check(kindAndTag[0], kindAndTag[1]),
          throwsA(isA<BadRequest>()));
    }
    await expectLater(check('api', 'node-A', extra: true),
        throwsA(isA<BadRequest>()));
    expect(calls, isNot(contains('ccGeminiApiOutbound')));
  });
}
