import 'package:flutter/material.dart';

import '../services/l10n/locale_controller.dart';
import '../models/service_failover.dart';
import '../services/service_failover_manager.dart';

class ServiceFailoverScreen extends StatelessWidget {
  const ServiceFailoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ServiceFailoverManager.I;
    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s('Service failover'))),
      body: AnimatedBuilder(
        animation: manager,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.alt_route),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            getLocalText.s('Smart routing for blocked services'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getLocalText.s(
                        'Each service has its own VPN selector and health logic. '
                        'While a service is active it is checked more often; while idle '
                        'it falls back to a slow background check. Reconnect loops can '
                        'trigger an immediate probe and failover.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final service in ManagedService.values)
              _ServiceCard(
                service: service,
                config: manager.settings[service],
                status: manager.statusOf(service),
                lastActivity: manager.lastActivityOf(service),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.config,
    required this.status,
    required this.lastActivity,
  });

  final ManagedService service;
  final ServiceFailoverConfig config;
  final ServiceFailoverStatus status;
  final DateTime? lastActivity;

  IconData get _icon => switch (service) {
        ManagedService.telegram => Icons.send_rounded,
        ManagedService.chatgpt => Icons.auto_awesome,
        ManagedService.gemini => Icons.diamond_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final manager = ServiceFailoverManager.I;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(_icon),
            title: Text(service.label),
            subtitle: Text(_serviceDescription(service)),
            value: config.enabled,
            onChanged: (enabled) => manager.updateConfig(
              service,
              config.copyWith(enabled: enabled),
            ),
          ),
          if (config.enabled) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: _StatusDot(phase: status.phase),
              title: Text(_phaseLabel(status.phase)),
              subtitle: Text(
                status.currentNode.isEmpty
                    ? getLocalText.s('Server: waiting for VPN state')
                    : '${getLocalText.s('Server')}: ${status.currentNode}',
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: status.phase == ServiceFailoverPhase.probing ||
                        status.phase == ServiceFailoverPhase.switching
                    ? null
                    : () => manager.testNow(service),
                icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                label: Text(getLocalText.s('Check now')),
              ),
            ),
            if (status.lastProbeDetail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    status.lastProbeDetail,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.flash_on_outlined,
                    text:
                        '${getLocalText.s('Active')}: ${_duration(config.activeIntervalSec)}',
                  ),
                  _InfoChip(
                    icon: Icons.bedtime_outlined,
                    text:
                        '${getLocalText.s('Idle')}: ${_duration(config.backgroundIntervalSec)}',
                  ),
                  _InfoChip(
                    icon: Icons.warning_amber_rounded,
                    text:
                        '${getLocalText.s('Failures')}: ${status.consecutiveFailures}/${config.failureThreshold}',
                  ),
                  if (lastActivity != null)
                    _InfoChip(
                      icon: Icons.schedule,
                      text:
                          '${getLocalText.s('Activity')}: ${_time(lastActivity!)}',
                    ),
                ],
              ),
            ),
            ExpansionTile(
              title: Text(getLocalText.s('Advanced failover settings')),
              leading: const Icon(Icons.tune),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(getLocalText.s('Watch real app connections')),
                  subtitle: Text(getLocalText.s(
                    'Detect reconnect loops and one-way traffic without polling the service.',
                  )),
                  value: config.passiveMonitor,
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(passiveMonitor: v),
                  ),
                ),
                _ChoiceRow(
                  label: getLocalText.s('Check while active'),
                  value: config.activeIntervalSec,
                  values: const [30, 60, 90, 120, 180, 300],
                  labelOf: _duration,
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(activeIntervalSec: v),
                  ),
                ),
                _ChoiceRow(
                  label: getLocalText.s('Background check'),
                  value: config.backgroundIntervalSec,
                  values: const [300, 600, 900, 1800, 3600],
                  labelOf: _duration,
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(backgroundIntervalSec: v),
                  ),
                ),
                _ChoiceRow(
                  label: getLocalText.s('Failures before urgent probe'),
                  value: config.failureThreshold,
                  values: const [1, 2, 3, 4, 5],
                  labelOf: (v) => '$v',
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(failureThreshold: v),
                  ),
                ),
                _ChoiceRow(
                  label: getLocalText.s('Cooldown after switch'),
                  value: config.cooldownSec,
                  values: const [30, 60, 90, 120, 300],
                  labelOf: _duration,
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(cooldownSec: v),
                  ),
                ),
                _ChoiceRow(
                  label: getLocalText.s('Backup servers to probe'),
                  value: config.maxCandidates,
                  values: const [2, 3, 4, 5, 6, 8],
                  labelOf: (v) => '$v',
                  onChanged: (v) => manager.updateConfig(
                    service,
                    config.copyWith(maxCandidates: v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.phase});
  final ServiceFailoverPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (phase) {
      ServiceFailoverPhase.healthy => scheme.primary,
      ServiceFailoverPhase.uncertain => scheme.secondary,
      ServiceFailoverPhase.probing || ServiceFailoverPhase.switching =>
        scheme.tertiary,
      ServiceFailoverPhase.degraded => scheme.error,
      ServiceFailoverPhase.cooldown => scheme.secondary,
      ServiceFailoverPhase.disabled => scheme.outline,
      ServiceFailoverPhase.idle => scheme.outlineVariant,
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 15),
        label: Text(text),
      );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> values;
  final String Function(int) labelOf;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: DropdownButton<int>(
          value: values.contains(value) ? value : values.first,
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(labelOf(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}

String _phaseLabel(ServiceFailoverPhase phase) => switch (phase) {
      ServiceFailoverPhase.disabled => getLocalText.s('Disabled'),
      ServiceFailoverPhase.idle => getLocalText.s('Waiting'),
      ServiceFailoverPhase.healthy => getLocalText.s('Healthy'),
      ServiceFailoverPhase.uncertain =>
        getLocalText.s('Reachable · region unverified'),
      ServiceFailoverPhase.degraded => getLocalText.s('Connection degraded'),
      ServiceFailoverPhase.probing => getLocalText.s('Checking service…'),
      ServiceFailoverPhase.switching => getLocalText.s('Switching server…'),
      ServiceFailoverPhase.cooldown => getLocalText.s('Switched · observing'),
    };

String _serviceDescription(ManagedService service) => switch (service) {
      ManagedService.telegram => getLocalText.s(
          'MTProto reconnects and one-way traffic + Telegram endpoint check.'),
      ManagedService.chatgpt => getLocalText.s(
          'OpenAI API check including unsupported-country/region responses.'),
      ManagedService.gemini => getLocalText.s(
          'Gemini reachability, known region verdicts and real app failures.'),
    };

String _duration(int seconds) {
  if (seconds >= 3600 && seconds % 3600 == 0) return '${seconds ~/ 3600} h';
  if (seconds >= 60 && seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '$seconds s';
}

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
