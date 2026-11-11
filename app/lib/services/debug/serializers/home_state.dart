import '../../../models/home_state.dart';
import '../../tailscale_network.dart';

/// [HomeState] → JSON-map для `GET /state`. Ключи в snake_case,
/// timestamps в ISO-8601 UTC. Чувствительных полей нет —
/// всё что в HomeState уже прошло через UI.
Map<String, Object?> serializeHomeState(HomeState s) {
  return {
    'tunnel': s.tunnel.name,
    'tunnel_up': s.tunnelUp,
    'busy': s.busy,
    'config_length': s.configRaw.length,
    // §311 — длина снапшота работающего ядра (GET /config/running); null =
    // недоступен (туннель down / старое ядро / ещё не подтянут). Вместе с
    // config_length показывает сам факт расхождения running vs saved.
    'running_config_length': s.runningConfigRaw?.length,
    'active_in_group': s.activeInGroup,
    'selected_group': s.selectedGroup,
    'highlighted_node': s.highlightedNode,
    'groups': s.groups,
    // Companion monitor: live selector choices and kernel URLTest timestamps.
    // Read-only and credential-free: never include subscription/server URIs.
    // Note: urlTestTime is UNIX seconds; zero means "never measured".
    'route_groups': [
      for (final group in s.ccGroups)
        {
          'tag': group.tag,
          'type': group.type,
          'selected': group.selected,
          'selectable': group.selectable,
          'items': [
            for (final node in group.items)
              {
                'tag': node.tag,
                'type': node.type,
                'delay_ms': node.urlTestDelay,
                'checked_at_unix_s': node.urlTestTime,
              },
          ],
        },
    ],
    // NET/YT/GPT/GEM are explicit checks, not equivalent to URLTest ping.
    // They are session-only; unavailable timestamps must not be fabricated.
    'service_health': {
      for (final entry in s.serviceHealth.entries)
        entry.key: {
          'net': {
            'state': entry.value.net.state.name,
            'elapsed_ms': entry.value.net.elapsedMs,
            'http_status': entry.value.net.httpStatus,
          },
          'youtube': {
            'state': entry.value.youtube.state.name,
            'elapsed_ms': entry.value.youtube.elapsedMs,
            'http_status': entry.value.youtube.httpStatus,
          },
          'chatgpt': {
            'state': entry.value.chatgpt.state.name,
            'elapsed_ms': entry.value.chatgpt.elapsedMs,
            'http_status': entry.value.chatgpt.httpStatus,
          },
          'gemini': {
            'state': entry.value.gemini.state.name,
            'elapsed_ms': entry.value.gemini.elapsedMs,
            'http_status': entry.value.gemini.httpStatus,
          },
        },
    },
    'nodes_count': s.nodes.length,
    // §325 — замеры разложены по Направлениям (`Направление → тег → ms`); ключ
    // `' scratch'` = замеры вне выбранного Направления. `last_delay` — плоский срез
    // ТЕКУЩЕГО Направления с фоллбэком, ровно то, что видно в списке.
    // §393 A2 — было `delay_by_channel`; dev-only JSON, алиас не заводим.
    'delay_by_direction': s.delayByDirection,
    'last_delay': {
      for (final tag in s.nodes)
        if (s.delayOf(tag) != null) tag: s.delayOf(tag),
    },
    'ping_busy': s.pingBusy,
    // §535 (ядро SPEC 097) — состояние WG/AWG-endpoint'ов по тегу
    // (never_built/building/up/asleep/torn_down/down), снятое pull'ом
    // `GetOutbounds` на heartbeat-тике. Пусто = состояний нет (туннель down,
    // ядро не отдало, либо endpoint'ов в конфиге нет).
    'endpoint_states': s.endpointStates,
    // §581 раздел 9 — узлы Tailscale: только состояние и число устройств;
    // имён, адресов, имени сети и ссылки входа здесь нет.
    'tailscale': {
      for (final e in s.tailscaleStatus.entries)
        e.key: tailscaleDebugSummary(e.value),
    },
    'traffic': {
      'up_total': s.traffic.uploadTotal,
      'down_total': s.traffic.downloadTotal,
      'active_connections': s.traffic.activeConnections,
    },
    'connected_since': s.connectedSince?.toUtc().toIso8601String(),
    'last_error': s.lastError?.renderEn() ?? '',
    // §250 — причина последнего аварийного стопа/revoke; в отличие от
    // last_error не расходуется UI, чистится только успешным стартом.
    // In-memory — пусто после рестарта процесса.
    'last_start_error': s.lastStartError,
    'last_start_error_at': s.lastStartErrorAt?.toUtc().toIso8601String(),
    // §076 renamed from `config_stale_since_start`.
    'config_changed_need_restart': s.configChangedNeedRestart,
    'sort_mode': s.sortMode.name,
    // §070 / §071 — sort options + manual mode state. Non-breaking add.
    'pin_direct': s.pinDirect,
    'pin_auto': s.pinAuto,
    'resort_on_manual_ping': s.resortOnManualPing,
    'ping_batch_gen': s.pingBatchGen,
    'manual_order': s.manualOrder,
  };
}
