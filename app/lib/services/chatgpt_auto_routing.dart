import 'dart:convert';

import '../models/custom_rule.dart';
import '../models/direction.dart';
import 'direction_mutations.dart';
import 'settings_storage.dart';

const _chatgptAutoTag = 'chatgpt-auto';
const _telegramAutoTag = 'telegram-auto';
const _geminiAutoTag = 'gemini-auto';
const _chatgptPackage = 'com.openai.chatgpt';
const _geminiPackage = 'com.google.android.apps.bard';
const _chromePackage = 'com.android.chrome';
const _telegramPackages = <String>[
  'org.telegram.messenger.web',
  'org.telegram.messenger',
];
const _chatgptPackageRuleName = 'ChatGPT app → ChatGPT Auto';
const _telegramPackageRuleName = 'Telegram app → Telegram Auto';
const _geminiPackageRuleName = 'Gemini app → Gemini Auto';
const _geminiWebChromeRuleName = 'Gemini web Chrome → Gemini Auto';
const _geminiDomainsRuleName = 'Gemini service domains → Gemini Auto';
const _geminiWebChromeDomains = <String>[
  'accounts.google.com',
  'content.googleapis.com',
  'gemini.app.google',
  'gemini.google.com',
  'gemini.gstatic.com',
  'geminiweb-pa.clients6.google.com',
  'lh3.googleusercontent.com',
  'ogads-pa.clients6.google.com',
  'ogs.google.com',
  'push.clients6.google.com',
  'ssl.gstatic.com',
  'waa-pa.clients6.google.com',
  'www.gstatic.com',
  'www.google.com',
];
const _geminiDomainSuffixes = <String>[
  'gemini.google.com',
  'bard.google.com',
  'aistudio.google.com',
  'generativelanguage.googleapis.com',
  'ai.google.dev',
  'makersuite.google.com',
];
const _legacyAiRuleName = 'AI services → VPN';
const _autoAiRuleName = 'AI services → ChatGPT Auto';

/// Local service-routing migration.
///
/// The Home "Direction" dropdown only chooses which group is displayed; it
/// does not route apps. Keep each blocked/geo-sensitive service on its own
/// selector so service-aware failover can switch Telegram, ChatGPT and Gemini
/// independently without rebuilding the whole VPN.
Future<bool> ensureChatGptAutoRouting() async {
  var changed = await _ensureServiceDirections();

  final rules = await SettingsStorage.getCustomRules();
  var hasChatGptPackageRule = false;
  var hasTelegramPackageRule = false;
  var hasGeminiPackageRule = false;
  var hasGeminiWebChromeRule = false;
  var hasGeminiDomainsRule = false;
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
        hasChatGptPackageRule = true;
        final repaired = rule.copyWith(
          name: _chatgptPackageRuleName,
          enabled: true,
          orderNum: 992,
          packages: const [_chatgptPackage],
          outbound: _chatgptAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isTelegramPackageRule =
          rule.name == _telegramPackageRuleName ||
          rule.name == 'Telegram app → VPN ①' ||
          rule.name == 'Telegram app → ✨ Messengers' ||
          (rule.packages.any(_telegramPackages.contains) &&
              rule.domains.isEmpty &&
              rule.domainSuffixes.isEmpty &&
              rule.domainKeywords.isEmpty &&
              rule.ipCidrs.isEmpty);
      if (isTelegramPackageRule) {
        hasTelegramPackageRule = true;
        final repaired = rule.copyWith(
          name: _telegramPackageRuleName,
          enabled: true,
          orderNum: 993,
          packages: _telegramPackages,
          outbound: _telegramAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isGeminiPackageRule =
          rule.name == _geminiPackageRuleName ||
          rule.name == 'Gemini app → ChatGPT Auto' ||
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
          orderNum: 991,
          packages: const [_geminiPackage],
          outbound: _geminiAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isGeminiWebChromeRule =
          rule.name == _geminiWebChromeRuleName ||
          rule.name == 'Gemini web Chrome → ChatGPT Auto';
      if (isGeminiWebChromeRule) {
        hasGeminiWebChromeRule = true;
        final repaired = rule.copyWith(
          name: _geminiWebChromeRuleName,
          enabled: true,
          orderNum: 994,
          domains: _geminiWebChromeDomains,
          packages: const [_chromePackage],
          outbound: _geminiAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }

      final isGeminiDomainsRule = rule.name == _geminiDomainsRuleName;
      if (isGeminiDomainsRule) {
        hasGeminiDomainsRule = true;
        final repaired = rule.copyWith(
          name: _geminiDomainsRuleName,
          enabled: true,
          orderNum: 995,
          domainSuffixes: _geminiDomainSuffixes,
          outbound: _geminiAutoTag,
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
        // Gemini now has its own selector. Remove its suffixes from the catch-all
        // AI rule so the earlier service-specific route owns them unambiguously.
        final suffixes = rule.domainSuffixes
            .where((s) => !_geminiDomainSuffixes.contains(s))
            .toList(growable: false);
        final repaired = rule.copyWith(
          name: _autoAiRuleName,
          enabled: true,
          domainSuffixes: suffixes,
          outbound: _chatgptAutoTag,
        );
        changed = changed || repaired != rule;
        next.add(repaired);
        continue;
      }
    }
    next.add(rule);
  }

  if (!hasGeminiPackageRule) {
    next.add(CustomRuleInline(
      name: _geminiPackageRuleName,
      enabled: true,
      orderNum: 991,
      packages: const [_geminiPackage],
      outbound: _geminiAutoTag,
    ));
    changed = true;
  }
  if (!hasChatGptPackageRule) {
    next.add(CustomRuleInline(
      name: _chatgptPackageRuleName,
      enabled: true,
      orderNum: 992,
      packages: const [_chatgptPackage],
      outbound: _chatgptAutoTag,
    ));
    changed = true;
  }
  if (!hasTelegramPackageRule) {
    next.add(CustomRuleInline(
      name: _telegramPackageRuleName,
      enabled: true,
      orderNum: 993,
      packages: _telegramPackages,
      outbound: _telegramAutoTag,
    ));
    changed = true;
  }
  if (!hasGeminiWebChromeRule) {
    next.add(CustomRuleInline(
      name: _geminiWebChromeRuleName,
      enabled: true,
      orderNum: 994,
      domains: _geminiWebChromeDomains,
      packages: const [_chromePackage],
      outbound: _geminiAutoTag,
    ));
    changed = true;
  }
  if (!hasGeminiDomainsRule) {
    next.add(CustomRuleInline(
      name: _geminiDomainsRuleName,
      enabled: true,
      orderNum: 995,
      domainSuffixes: _geminiDomainSuffixes,
      outbound: _geminiAutoTag,
    ));
    changed = true;
  }

  if (changed) await SettingsStorage.saveCustomRules(next);
  return changed;
}

Future<bool> _ensureServiceDirections() async {
  final directions = await SettingsStorage.getDirections();
  final next = List<Direction>.from(directions);
  var changed = false;

  Direction serviceDirection({
    required String tag,
    required String label,
    required String url,
    String defaultFilter = '',
  }) =>
      Direction(
        tag: tag,
        label: label,
        enabled: true,
        includeDirect: false,
        includeBlock: false,
        defaultFilter: defaultFilter,
        interruptExistConnections: true,
        auto: DirectionAuto(
          url: url,
          interval: '15m',
          tolerance: 50,
          idleTimeout: '30m',
          interruptExistConnections: true,
          mode: UrltestMode.failover,
          pool: 3,
          poolTolerance: 0,
        ),
      );

  void ensure(Direction desired) {
    final index = next.indexWhere((d) => d.tag == desired.tag);
    if (index < 0) {
      next.add(desired);
      changed = true;
      return;
    }
    final current = next[index];
    // Preserve user filters/labels on existing directions. Only guarantee that
    // service selectors stay enabled and have a native failover twin as a
    // low-level liveness fallback.
    final repaired = current.copyWith(
      enabled: true,
      auto: current.auto ?? desired.auto,
    );
    if (repaired != current) {
      next[index] = repaired;
      changed = true;
    }
  }

  ensure(serviceDirection(
    tag: _chatgptAutoTag,
    label: '✨ Авто · ChatGPT',
    url: DirectionAuto.defaultUrl,
  ));
  ensure(serviceDirection(
    tag: _telegramAutoTag,
    label: '📨 Авто · Telegram',
    url: 'https://telegram.org',
    defaultFilter: r'^✨ Messengers$',
  ));
  ensure(serviceDirection(
    tag: _geminiAutoTag,
    label: '✨ Авто · Gemini',
    url: 'https://gemini.google.com/app',
    defaultFilter: r'^✨ AI🤖$',
  ));

  if (changed) await DirectionMutations.bulkReplace(next);
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
