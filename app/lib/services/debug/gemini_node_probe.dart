import 'dart:async';

import '../../vpn/cc_channel.dart';
import 'context.dart';
import 'contract/errors.dart';
import 'transport/request.dart';

/// Narrow, authenticated localhost diagnostic: a fixed URL and a live
/// physical outbound, NEVER a route switch or general-purpose HTTP proxy.
/// The Google key is ephemeral in the POST body and native MethodChannel.
class GeminiNodeProbe {
  GeminiNodeProbe._();

  static bool _busy = false;
  static const _excludedTypes = <String>{
    'selector', 'urltest', 'direct', 'block', 'dns', 'reject',
  };
  static const _excludedTags = <String>{'direct-out', 'block', 'block-out'};
  static const _pingUrl = 'https://cp.cloudflare.com/generate_204';

  static Future<Map<String, Object?>> run(
    DebugRequest request,
    DebugContext context,
  ) async {
    if (!context.requireHome().state.tunnelUp) {
      throw const Conflict('VPN tunnel disconnected');
    }
    final payload = request.jsonBodyAsMap();
    if (payload.keys.any((k) =>
        k != 'tag' && k != 'kind' && k != 'api_key')) {
      throw const BadRequest('unsupported probe parameter');
    }
    final tag = payload['tag'];
    final kind = payload['kind'];
    if (tag is! String || tag.isEmpty || tag.length > 256 ||
        kind != 'ping' && kind != 'api' || _excludedTags.contains(tag)) {
      throw const BadRequest('invalid physical outbound or kind');
    }
    if (_busy) throw const Conflict('another Gemini node probe is running');
    _busy = true;
    try {
      final cc = CcChannel.instance;
      final outbounds = await cc.getOutbounds()
          .timeout(const Duration(seconds: 3));
      if (outbounds == null || !outbounds.any((e) =>
          e.tag == tag && !_excludedTypes.contains(e.type.toLowerCase()))) {
        throw const BadRequest('unknown or non-physical outbound');
      }
      // Require membership in an actual live group. A forged tag that merely
      // resembles a server must never initiate a credential-bearing request.
      final groups = await cc.getGroups()
          .timeout(const Duration(seconds: 3));
      if (groups == null || !groups.any((g) =>
          g.items.any((e) => e.tag == tag &&
              !_excludedTypes.contains(e.type.toLowerCase())))) {
        throw const Conflict('outbound absent from live groups');
      }
      if (!context.requireHome().state.tunnelUp) {
        throw const Conflict('VPN tunnel disconnected');
      }
      if (kind == 'ping') {
        final result = await cc.urlTestOutbound(
          tag, link: _pingUrl, timeoutMs: 3500,
        ).timeout(const Duration(seconds: 6));
        return {
          'ok': true,
          'tag': tag,
          'kind': 'ping',
          'verdict': result.ok ? 'ping_ok' : 'ping_failed',
          'latency_ms': result.ok ? result.delay : 0,
          'checked_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
        };
      }
      final apiKey = payload['api_key'];
      if (apiKey is! String || apiKey.length < 8 || apiKey.length > 512 ||
          apiKey.codeUnits.any((c) => c < 33 || c > 126)) {
        throw const BadRequest('invalid transient API key');
      }
      final result = await cc.geminiApiOutbound(tag, apiKey)
          .timeout(const Duration(seconds: 9));
      final verified = result['verified_tag'];
      if (verified != tag) {
        throw const Conflict('physical outbound not verified');
      }
      const outcomes = <String>{
        'api_available', 'region_blocked_api', 'key_or_project_error',
        'rate_limited', 'api_indeterminate', 'network_error',
      };
      final verdict = result['verdict']?.toString() ?? 'api_indeterminate';
      return {
        'ok': true,
        'tag': tag,
        'kind': 'api',
        'verdict': outcomes.contains(verdict) ? verdict : 'api_indeterminate',
        'http_status': result['http_status'] is int ? result['http_status'] : 0,
        'elapsed_ms': result['elapsed_ms'] is int ? result['elapsed_ms'] : 0,
        'proof': 'gemini_api_only',
        'checked_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
      };
    } on TimeoutException {
      return {
        'ok': true, 'tag': tag, 'kind': kind,
        'verdict': kind == 'ping' ? 'ping_failed' : 'network_error',
        'checked_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
      };
    } finally {
      _busy = false;
    }
  }
}
