import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/home_state.dart';
import 'package:lxbox/models/service_health.dart';
import 'package:lxbox/services/debug/serializers/home_state.dart';
import 'package:lxbox/vpn/cc_channel.dart';

void main() {
  test('LBox monitor exposes live service selection and exact URLTest timestamp', () {
    final state = HomeState(
      ccGroups: const [
        CcGroup(
          tag: 'chatgpt-auto',
          type: 'selector',
          selectable: true,
          selected: 'Finland',
          isExpand: false,
          items: [
            CcOutbound(
              tag: 'Finland',
              type: 'vless',
              urlTestDelay: 136,
              urlTestTime: 1794281280,
            ),
          ],
        ),
      ],
      serviceHealth: const {
        'Finland': NodeServiceHealth(
          chatgpt: ServiceHealthResult(
            state: ServiceHealthState.available,
            elapsedMs: 280,
            httpStatus: 401,
          ),
        ),
      },
    );
    final json = serializeHomeState(state);
    final groups = json['route_groups'] as List;
    final selector = groups.first as Map;
    expect(selector['tag'], 'chatgpt-auto');
    expect(selector['selected'], 'Finland');
    final node = (selector['items'] as List).first as Map;
    expect(node['tag'], 'Finland');
    expect(node['delay_ms'], 136);
    expect(node['checked_at_unix_s'], 1794281280);
    final health = json['service_health'] as Map;
    final chat = (health['Finland'] as Map)['chatgpt'] as Map;
    expect(chat['state'], 'available');
    expect(chat['http_status'], 401);
    // Node/server connection URIs, proxy passwords and tokens must never leak.
    expect(json.toString(), isNot(contains('vless://')));
    expect(json.toString(), isNot(contains('debug_token')));
  });
}
