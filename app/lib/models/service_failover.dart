import 'dart:convert';

enum ManagedService { telegram, chatgpt, gemini }

extension ManagedServiceMeta on ManagedService {
  String get id => name;

  String get label => switch (this) {
        ManagedService.telegram => 'Telegram',
        ManagedService.chatgpt => 'ChatGPT',
        ManagedService.gemini => 'Gemini',
      };

  String get groupTag => switch (this) {
        ManagedService.telegram => 'telegram-auto',
        ManagedService.chatgpt => 'chatgpt-auto',
        ManagedService.gemini => 'gemini-auto',
      };

  List<String> get packages => switch (this) {
        ManagedService.telegram => const [
            'org.telegram.messenger.web',
            'org.telegram.messenger',
          ],
        ManagedService.chatgpt => const ['com.openai.chatgpt'],
        ManagedService.gemini => const ['com.google.android.apps.bard'],
      };

  String get probeUrl => switch (this) {
        ManagedService.telegram => 'https://telegram.org',
        ManagedService.chatgpt => 'https://api.openai.com/v1/models',
        ManagedService.gemini => 'https://gemini.google.com/app',
      };

  List<String> get preferredNodes => switch (this) {
        ManagedService.telegram => const ['✨ Messengers'],
        ManagedService.chatgpt => const [],
        ManagedService.gemini => const ['✨ AI🤖'],
      };
}

class ServiceFailoverConfig {
  const ServiceFailoverConfig({
    required this.enabled,
    required this.activeIntervalSec,
    required this.backgroundIntervalSec,
    required this.cooldownSec,
    required this.failureThreshold,
    required this.maxCandidates,
    required this.passiveMonitor,
  });

  final bool enabled;
  final int activeIntervalSec;
  final int backgroundIntervalSec;
  final int cooldownSec;
  final int failureThreshold;
  final int maxCandidates;
  final bool passiveMonitor;

  factory ServiceFailoverConfig.defaults(ManagedService service) =>
      ServiceFailoverConfig(
        enabled: true,
        activeIntervalSec: switch (service) {
          ManagedService.telegram => 120,
          ManagedService.chatgpt => 90,
          ManagedService.gemini => 90,
        },
        backgroundIntervalSec: 15 * 60,
        cooldownSec: 90,
        failureThreshold: 3,
        maxCandidates: 4,
        passiveMonitor: true,
      );

  ServiceFailoverConfig copyWith({
    bool? enabled,
    int? activeIntervalSec,
    int? backgroundIntervalSec,
    int? cooldownSec,
    int? failureThreshold,
    int? maxCandidates,
    bool? passiveMonitor,
  }) =>
      ServiceFailoverConfig(
        enabled: enabled ?? this.enabled,
        activeIntervalSec: activeIntervalSec ?? this.activeIntervalSec,
        backgroundIntervalSec:
            backgroundIntervalSec ?? this.backgroundIntervalSec,
        cooldownSec: cooldownSec ?? this.cooldownSec,
        failureThreshold: failureThreshold ?? this.failureThreshold,
        maxCandidates: maxCandidates ?? this.maxCandidates,
        passiveMonitor: passiveMonitor ?? this.passiveMonitor,
      );

  factory ServiceFailoverConfig.fromJson(
    ManagedService service,
    Map<String, dynamic> json,
  ) {
    final d = ServiceFailoverConfig.defaults(service);
    int clampInt(Object? raw, int fallback, int min, int max) {
      final v = raw is num ? raw.toInt() : int.tryParse('$raw');
      return (v ?? fallback).clamp(min, max);
    }

    return ServiceFailoverConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : d.enabled,
      activeIntervalSec: clampInt(
          json['active_interval_sec'], d.activeIntervalSec, 15, 3600),
      backgroundIntervalSec: clampInt(
          json['background_interval_sec'], d.backgroundIntervalSec, 60, 86400),
      cooldownSec:
          clampInt(json['cooldown_sec'], d.cooldownSec, 15, 3600),
      failureThreshold:
          clampInt(json['failure_threshold'], d.failureThreshold, 1, 10),
      maxCandidates:
          clampInt(json['max_candidates'], d.maxCandidates, 1, 12),
      passiveMonitor: json['passive_monitor'] is bool
          ? json['passive_monitor'] as bool
          : d.passiveMonitor,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'active_interval_sec': activeIntervalSec,
        'background_interval_sec': backgroundIntervalSec,
        'cooldown_sec': cooldownSec,
        'failure_threshold': failureThreshold,
        'max_candidates': maxCandidates,
        'passive_monitor': passiveMonitor,
      };
}

class ServiceFailoverSettings {
  ServiceFailoverSettings(Map<ManagedService, ServiceFailoverConfig> values)
      : values = Map.unmodifiable(values);

  final Map<ManagedService, ServiceFailoverConfig> values;

  factory ServiceFailoverSettings.defaults() => ServiceFailoverSettings({
        for (final service in ManagedService.values)
          service: ServiceFailoverConfig.defaults(service),
      });

  factory ServiceFailoverSettings.fromRaw(String raw) {
    final defaults = ServiceFailoverSettings.defaults();
    if (raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      return ServiceFailoverSettings({
        for (final service in ManagedService.values)
          service: ServiceFailoverConfig.fromJson(
            service,
            decoded[service.id] is Map
                ? Map<String, dynamic>.from(decoded[service.id] as Map)
                : const <String, dynamic>{},
          ),
      });
    } catch (_) {
      return defaults;
    }
  }

  ServiceFailoverConfig operator [](ManagedService service) =>
      values[service] ?? ServiceFailoverConfig.defaults(service);

  ServiceFailoverSettings replace(
    ManagedService service,
    ServiceFailoverConfig config,
  ) =>
      ServiceFailoverSettings({...values, service: config});

  String encode() => jsonEncode({
        for (final entry in values.entries) entry.key.id: entry.value.toJson(),
      });
}

enum ServiceFailoverPhase {
  disabled,
  idle,
  healthy,
  uncertain,
  degraded,
  probing,
  switching,
  cooldown,
}

class ServiceFailoverStatus {
  const ServiceFailoverStatus({
    this.phase = ServiceFailoverPhase.idle,
    this.currentNode = '',
    this.lastReason = '',
    this.lastProbeAt,
    this.lastSwitchAt,
    this.consecutiveFailures = 0,
    this.lastProbeDetail = '',
  });

  final ServiceFailoverPhase phase;
  final String currentNode;
  final String lastReason;
  final DateTime? lastProbeAt;
  final DateTime? lastSwitchAt;
  final int consecutiveFailures;
  final String lastProbeDetail;

  ServiceFailoverStatus copyWith({
    ServiceFailoverPhase? phase,
    String? currentNode,
    String? lastReason,
    DateTime? lastProbeAt,
    DateTime? lastSwitchAt,
    int? consecutiveFailures,
    String? lastProbeDetail,
  }) =>
      ServiceFailoverStatus(
        phase: phase ?? this.phase,
        currentNode: currentNode ?? this.currentNode,
        lastReason: lastReason ?? this.lastReason,
        lastProbeAt: lastProbeAt ?? this.lastProbeAt,
        lastSwitchAt: lastSwitchAt ?? this.lastSwitchAt,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        lastProbeDetail: lastProbeDetail ?? this.lastProbeDetail,
      );
}
