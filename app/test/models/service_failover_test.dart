import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/service_failover.dart';
import 'package:lxbox/services/service_failover_manager.dart';

void main() {
  group('ServiceFailoverSettings', () {
    test('defaults are adaptive and enabled for built-in services', () {
      final settings = ServiceFailoverSettings.defaults();
      for (final service in ManagedService.values) {
        expect(settings[service].enabled, isTrue);
        expect(settings[service].backgroundIntervalSec,
            greaterThan(settings[service].activeIntervalSec));
        expect(settings[service].passiveMonitor, isTrue);
      }
    });

    test('JSON round-trip preserves per-service overrides', () {
      final original = ServiceFailoverSettings.defaults().replace(
        ManagedService.telegram,
        ServiceFailoverConfig.defaults(ManagedService.telegram).copyWith(
          activeIntervalSec: 30,
          backgroundIntervalSec: 1800,
          failureThreshold: 2,
          maxCandidates: 6,
        ),
      );
      final parsed = ServiceFailoverSettings.fromRaw(original.encode());
      expect(parsed[ManagedService.telegram].activeIntervalSec, 30);
      expect(parsed[ManagedService.telegram].backgroundIntervalSec, 1800);
      expect(parsed[ManagedService.telegram].failureThreshold, 2);
      expect(parsed[ManagedService.telegram].maxCandidates, 6);
    });

    test('malformed JSON falls back to safe defaults', () {
      final parsed = ServiceFailoverSettings.fromRaw('{broken');
      expect(parsed[ManagedService.chatgpt].enabled, isTrue);
      expect(parsed[ManagedService.chatgpt].backgroundIntervalSec, 900);
    });
  });

  group('passive failure classifier', () {
    test('detects observed Telegram one-way MTProto failure', () {
      expect(
        isSuspiciousServiceClose(
          ManagedService.telegram,
          uplink: 252218,
          downlink: 331,
        ),
        isTrue,
      );
    });

    test('does not flag healthy Telegram download', () {
      expect(
        isSuspiciousServiceClose(
          ManagedService.telegram,
          uplink: 17000,
          downlink: 230000,
        ),
        isFalse,
      );
    });

    test('ignores tiny Telegram control connections', () {
      expect(
        isSuspiciousServiceClose(
          ManagedService.telegram,
          uplink: 600,
          downlink: 153,
        ),
        isFalse,
      );
    });

    test('TLS services require a meaningful zero-response close', () {
      expect(
        isSuspiciousServiceClose(
          ManagedService.chatgpt,
          uplink: 4096,
          downlink: 0,
        ),
        isTrue,
      );
      expect(
        isSuspiciousServiceClose(
          ManagedService.chatgpt,
          uplink: 400,
          downlink: 0,
        ),
        isFalse,
      );
    });
  });
}
