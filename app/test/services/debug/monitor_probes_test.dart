// Real Debug API action/state routing with a mocked LBox CommandClient.
// No network requests and no VPN are started by this test.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/controllers/home_controller.dart';
import 'package:lxbox/services/debug/context.dart';
import 'package:lxbox/services/debug/contract/errors.dart';
import 'package:lxbox/services/debug/debug_registry.dart';
import 'package:lxbox/services/debug/handlers/action.dart';
import 'package:lxbox/services/debug/handlers/state.dart';
import 'package:lxbox/services/debug/transport/request.dart';
import 'package:lxbox/services/debug/transport/response.dart';
import 'package:lxbox/services/debug/monitor_probes.dart';
import 'package:lxbox/vpn/cc_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.leadaxe.lxbox/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late HomeController home;
  final seen = <String>[];

  DebugContext ctx() => DebugContext(
    registry: DebugRegistry.I,
    appStartedAt: DateTime.utc(2026),
  );
  DebugRequest req(String method, String path) => DebugRequest(
    method: method,
    uri: Uri.parse('http://127.0.0.1:9269$path'),
    headers: const {},
    body: Uint8List(0),
    receivedAt: DateTime.utc(2026),
  );
  Map<String,dynamic> body(DebugResponse response) =>
      (response as JsonResponse).body as Map<String,dynamic>;

  setUp(() {
    seen.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      seen.add(call.method);
      if (call.method == 'ccGetGroups') return [
        {
          'tag':'chatgpt-auto','type':'selector','selectable':true,
          'selected':'🇫🇮 Helsinki','isExpand':false,'items':<Object>[],
        },
        {
          'tag':'gemini-auto','type':'selector','selectable':true,
          'selected':'vpn-1-auto','isExpand':false,'items':<Object>[],
        },
        {
          'tag':'vpn-1-auto','type':'urltest','selectable':true,
          'selected':'🇩🇪 Frankfurt','isExpand':false,'items':<Object>[],
        },
      ];
      if (call.method == 'ccUrlTestOutbound') {
        expect(['🇫🇮 Helsinki','telegram-auto'],
          contains((call.arguments as Map)['tag']));
        return {'delay': 132, 'error':''};
      }
      if (call.method == 'ccGetUrlViaOutbound') {
        expect((call.arguments as Map)['tag'],'🇫🇮 Helsinki');
        return {
          'status':403, 'content':'unsupported_country_region_territory',
          'truncated':false, 'contentType':'application/json',
          'remoteAddr':'', 'elapsedMs':204, 'error':''
        };
      }
      return null;
    });
    home = HomeController();
    DebugRegistry.I.home = home;
    home.debugSeedNodeState(group:'vpn-1', activeNode:'🇫🇮 Helsinki');
  });

  tearDown(() {
    DebugRegistry.I.home = null;
    home.dispose();
    messenger.setMockMethodCallHandler(methods,null);
  });

  test('POST action invokes kernel URLTest; GET returns measured time', () async {
    final accepted=body(await actionHandler(
      req('POST','/action/monitor-probe?direction=chatgpt-auto&kind=ping'),ctx()));
    expect(accepted['accepted'],true);
    expect(accepted['selected_tag'],'🇫🇮 Helsinki');
    await Future<void>.delayed(const Duration(milliseconds:80));
    final status=body(await stateHandler(req('GET','/state/monitor-probes'),ctx()));
    final checks=status['checks'] as Map;
    final ping=(checks['chatgpt-auto'] as Map)['ping'] as Map;
    expect(ping['state'],'available');
    expect(ping['latency_ms'],132);
    expect(ping['checked_at_unix_s'],greaterThan(0));
    expect(seen,contains('ccUrlTestOutbound'));
    expect(jsonEncode(status),isNot(contains('vless://')));
  });

  test('ChatGPT region block classified by LBox response body', () async {
    final accepted=body(await actionHandler(
      req('POST','/action/monitor-probe?direction=chatgpt-auto&kind=service'),ctx()));
    expect(accepted['accepted'],true);
    await Future<void>.delayed(const Duration(milliseconds:80));
    final checks=MonitorProbes.instance.snapshot['checks'] as Map;
    final service=(checks['chatgpt-auto'] as Map)['service'] as Map;
    expect(service['state'],'blocked');
    expect(service['http_status'],403);
    expect(service['selected_tag'],'🇫🇮 Helsinki');
    expect(service['message'],'unsupported_country_region_territory');
    expect(seen,contains('ccGetUrlViaOutbound'));
  });

  test('unknown direction is rejected before kernel call', () async {
    await expectLater(
      actionHandler(req('POST','/action/monitor-probe?direction=evil&kind=ping'),ctx()),
      throwsA(isA<BadRequest>()),
    );
    expect(seen, isNot(contains('ccGetGroups')));
  });

  test('missing live selector uses LBox logical direction, with honest label', () async {
    final accepted=body(await actionHandler(
      req('POST','/action/monitor-probe?direction=telegram-auto&kind=ping'),ctx()));
    expect(accepted['accepted'],true);
    expect(accepted['selected_tag'],'telegram-auto');
    expect(accepted['selection_source'],'logical_direction');
    await Future<void>.delayed(const Duration(milliseconds:80));
    final checks=MonitorProbes.instance.snapshot['checks'] as Map;
    final ping=(checks['telegram-auto'] as Map)['ping'] as Map;
    expect(ping['state'],'available');
    expect(ping['selection_source'],'logical_direction');
  });

  test('nested selector resolves to physical outbound without switching it', () {
    const groupA = CcGroup(
      tag:'gemini-auto',type:'selector',selectable:true,
      selected:'vpn-1-auto',isExpand:false,items:[],
    );
    const groupB = CcGroup(
      tag:'vpn-1-auto',type:'urltest',selectable:true,
      selected:'🇩🇪 Frankfurt',isExpand:false,items:[],
    );
    expect(MonitorProbes.resolvePhysical([groupA,groupB],'gemini-auto'),
      '🇩🇪 Frankfurt');
    expect(MonitorProbes.resolvePhysical([groupA],'gemini-auto'),
      'vpn-1-auto');
    expect(MonitorProbes.resolvePhysical([groupA,groupB],'unknown'),isNull);
    expect(MonitorProbes.errorCategory('dial timeout'),'timeout');
    expect(seen,isNot(contains('ccSelectOutbound')));
  });
}
