import '../../../models/background_mode.dart';
import '../../../vpn/cc_channel.dart';
import '../../../vpn/box_vpn_client.dart';
import '../../settings_storage.dart';
import '../context.dart';
import '../monitor_probes.dart';
import '../contract/errors.dart';
import '../serializers/home_state.dart';
import '../serializers/rules.dart';
import '../serializers/storage.dart';
import '../serializers/subs.dart';
import '../transport/request.dart';
import '../transport/response.dart';

/// Диспатчер `/state/*`. Подмаршруты читают разные части домена —
/// home controller, subs, rules (из storage), storage cache, native VPN.
Future<DebugResponse> stateHandler(DebugRequest req, DebugContext ctx) async {
  return switch (req.path) {
    '/state' => _root(req, ctx),
    '/state/route-status' => _routeStatus(req, ctx),
    '/state/monitor-probes' => JsonResponse(MonitorProbes.instance.snapshot),
    '/state/subs' => _subs(req, ctx),
    '/state/rules' => _rules(req, ctx),
    '/state/storage' => _storage(req, ctx),
    '/state/vpn' => _vpn(req, ctx),
    '/state/config_locked' => _configLocked(req, ctx),
    _ => throw NotFound('state path: ${req.path}'),
  };
}

/// §037: Текущее состояние lock'а auto-rebuild. Когда `locked: true` —
/// `SubscriptionController.generateConfig()` возвращает null silently,
/// pinned config через `PUT /config` не перетирается UI-действиями.
Future<DebugResponse> _configLocked(DebugRequest req, DebugContext ctx) async {
  final locked = await SettingsStorage.getConfigLockedForDebug();
  return JsonResponse({'locked': locked});
}

Future<DebugResponse> _root(DebugRequest req, DebugContext ctx) async {
  final home = ctx.requireHome();
  final json = serializeHomeState(home.state);
  // §076: добавляем config_dirty из SubscriptionController (in-memory флаг,
  // не в HomeState). Computed read-only для диагностики lazy rebuild flow.
  json['config_dirty'] = ctx.requireSub().configDirty;
  return JsonResponse(json);
}

/// Read-only live route snapshot for the companion APK. Unlike /state,
/// query the kernel's CommandClient on demand so a backgrounded LBox UI
/// cannot report a stale selector choice after automatic failover.
Future<DebugResponse> _routeStatus(DebugRequest req, DebugContext ctx) async {
  final home = ctx.requireHome();
  final state = home.state;
  var groups = state.ccGroups;
  var source = 'cached_home';
  if (state.tunnelUp) {
    try {
      final fresh = await CcChannel.instance
          .getGroups()
          .timeout(const Duration(seconds: 2));
      if (fresh != null && fresh.isNotEmpty) {
        groups = fresh;
        source = 'kernel_unary';
      }
    } catch (_) {
      // The kernel is temporarily unavailable (or old); keep a labelled
      // cached snapshot rather than claiming the selector is live.
    }
  }
  return JsonResponse({
    'ok': true,
    'source': source,
    'tunnel': state.tunnel.name,
    'observed_at': DateTime.now().toUtc().toIso8601String(),
    'route_groups': serializeRouteGroups(groups),
    'service_health': serializeHomeState(state)['service_health'],
  });
}

Future<DebugResponse> _subs(DebugRequest req, DebugContext ctx) async {
  final sub = ctx.requireSub();
  final reveal = req.qBool('reveal');
  final entries = sub.entries
      .map((e) => serializeSubEntry(e, reveal: reveal))
      .toList();
  return JsonResponse(entries);
}

Future<DebugResponse> _rules(DebugRequest req, DebugContext ctx) async {
  final rules = await SettingsStorage.getCustomRules();
  final serialized = await Future.wait(rules.map(serializeCustomRule));
  return JsonResponse(serialized);
}

Future<DebugResponse> _storage(DebugRequest req, DebugContext ctx) async {
  final cache = await SettingsStorage.dumpCache();
  return JsonResponse(serializeStorageCache(cache));
}

Future<DebugResponse> _vpn(DebugRequest req, DebugContext ctx) async {
  final vpn = BoxVpnClient();
  // §189 — persisted-настройки из JSON-зеркала native_prefs (истина).
  final autoStart =
      await SettingsStorage.getNativeBool(NativePrefsKeys.autoStart);
  final keepOnExit =
      await SettingsStorage.getNativeBool(NativePrefsKeys.keepOnExit);
  final allowBypass =
      await SettingsStorage.getNativeBool(NativePrefsKeys.allowBypass);
  // §069 — runtime applied value, может отличаться от persisted allowBypass
  // если юзер поменял toggle но не reload'нул VPN (это НЕ настройка — сессия).
  final currentSessionAllowBypass = await vpn.getCurrentSessionAllowBypass();
  final backgroundMode = BackgroundMode.fromNative(
      await SettingsStorage.getNativeBackgroundMode());
  final battery = await vpn.isIgnoringBatteryOptimizations();
  return JsonResponse({
    'auto_start': autoStart,
    'keep_on_exit': keepOnExit,
    'allow_bypass': allowBypass,
    'current_session_allow_bypass': currentSessionAllowBypass,
    'background_mode': backgroundMode.wireValue,
    'is_ignoring_battery_optimizations': battery,
  });
}
