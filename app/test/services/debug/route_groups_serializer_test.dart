import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/home_state.dart';
import 'package:lxbox/services/debug/serializers/home_state.dart';
import 'package:lxbox/vpn/cc_channel.dart';

void main() {
  test('Monitor sees live group selection and URLTest timestamp', () {
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
    expect((json['group_selected'] as Map)['chatgpt-auto'], 'Finland');
    expect(json.toString(), isNot(contains('vless://')));
    expect(json.toString(), isNot(contains('debug_token')));
  });
}
