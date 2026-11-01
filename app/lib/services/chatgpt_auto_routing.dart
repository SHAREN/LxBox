import '../models/custom_rule.dart';
import 'settings_storage.dart';

const _chatgptAutoTag = 'chatgpt-auto';
const _chatgptPackage = 'com.openai.chatgpt';
const _chatgptPackageRuleName = 'ChatGPT app → ChatGPT Auto';
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

  if (changed) await SettingsStorage.saveCustomRules(next);
  return changed;
}
