import 'dart:convert';

import '../models/custom_rule.dart';
import 'settings_storage.dart';

const _chatgptAutoTag = 'chatgpt-auto';
const _chatgptPackage = 'com.openai.chatgpt';
const _geminiPackage = 'com.google.android.apps.bard';
const _chatgptPackageRuleName = 'ChatGPT app → ChatGPT Auto';
const _geminiPackageRuleName = 'Gemini app → ChatGPT Auto';
const _legacyAiRuleName = 'AI services → VPN';
const _autoAiRuleName = 'AI services → ChatGPT Auto';

/// Keeps the locally-added ChatGPT Auto direction wired into real routing.
///
/// The Home "Direction" dropdown only selects which group is displayed; it
/// does not change route rules. This migration is intentionally idempotent:
/// every startup repairs the two rules only when the `chatgpt-auto` direction
/// exists.
Future<bool> ensureChatGptAutoRouting() async {
  final directions = await SettingsStorage.getDirections();
  if (!directions.any((d) => d.tag == _chatgptAutoTag && d.enabled)) {
    return false;
  }

  final rules = await SettingsStorage.getCustomRules();
  var changed = false;
  var hasPackageRule = false;
  var hasGeminiPackageRule = false;
  final next = <CustomRule>[];

  for (final rule in rules) {
    if (rule is CustomRuleInline) {
      final isChatGptPackageRule =
          rule.name == _chatgptPackageRuleName ||
          (rule.packages.contains(_chatgptPackage) &&
              rule.domains.isEmpty &&
              rule.domainSuffixes.isEmpty &&
              rule.domainKeywords.isEmpty &&
              rule.ipCidrs.isEmpty);
      if (isChatGptPackageRule) {
        hasPackageRule = true;
        final repaired = rule.copyWith(
          name: _chatgptPackageRuleName,
          enabled: true,
          packages: const [_chatgptPackage],
          outbound: _chatgptAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isGeminiPackageRule =
          rule.name == _geminiPackageRuleName ||
          (rule.packages.contains(_geminiPackage) &&
              rule.domains.isEmpty &&
              rule.domainSuffixes.isEmpty &&
              rule.domainKeywords.isEmpty &&
              rule.ipCidrs.isEmpty);
      if (isGeminiPackageRule) {
        hasGeminiPackageRule = true;
        final repaired = rule.copyWith(
          name: _geminiPackageRuleName,
          enabled: true,
          packages: const [_geminiPackage],
          outbound: _chatgptAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isAiDomainRule =
          (rule.name == _legacyAiRuleName || rule.name == _autoAiRuleName) &&
          rule.domainSuffixes.contains('chatgpt.com') &&
          rule.domainSuffixes.contains('openai.com');
      if (isAiDomainRule) {
        final repaired = rule.copyWith(
          name: _autoAiRuleName,
          enabled: true,
          outbound: _chatgptAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }
    }
    next.add(rule);
  }

  if (!hasPackageRule) {
    next.add(CustomRuleInline(
      name: _chatgptPackageRuleName,
      enabled: true,
      orderNum: 992,
      packages: const [_chatgptPackage],
      outbound: _chatgptAutoTag,
    ));
    changed = true;
  }


  if (!hasGeminiPackageRule) {
    next.add(CustomRuleInline(
      name: _geminiPackageRuleName,
      enabled: true,
      orderNum: 991,
      packages: const [_geminiPackage],
      outbound: _chatgptAutoTag,
    ));
    changed = true;
  }

  if (changed) await SettingsStorage.saveCustomRules(next);
  return changed;
}

const _geminiManualOverridesVar = 'service_health_gemini_overrides_v1';
const _geminiManualSeedVar = 'service_health_gemini_manual_seed_v1';
const _confirmedGeminiBlockedNode = '🐟 🇩🇪 Белые списки 🧶';

/// One-shot seed from an owner-confirmed real Gemini Apps block.
///
/// This writes a normal settings override once, then never forces it again. If
/// the owner later clears or changes the verdict, subsequent starts preserve
/// that decision because [_geminiManualSeedVar] remains true.
Future<bool> ensureGeminiManualVerdictSeed() async {
  if (await SettingsStorage.getVar(_geminiManualSeedVar, 'false') == 'true') {
    return false;
  }
  final raw = await SettingsStorage.getVar(_geminiManualOverridesVar, '{}');
  final overrides = <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        overrides[entry.key.toString()] = entry.value.toString();
      }
    }
  } catch (_) {
    // Invalid optional map: replace it with the known-good seed below.
  }
  overrides.putIfAbsent(_confirmedGeminiBlockedNode, () => 'blocked');
  await SettingsStorage.setVar(_geminiManualOverridesVar, jsonEncode(overrides));
  await SettingsStorage.setVar(_geminiManualSeedVar, 'true');
  return true;
}
