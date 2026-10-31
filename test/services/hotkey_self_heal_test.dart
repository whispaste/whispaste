/// Unit tests for the pure self-heal rules of the global hotkey: the guards
/// that decide when a re-registration may run, the throttle, the failure
/// streak behind the user toast, and the capture guard that keeps the
/// registration untouched while a hotkey is being recorded.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/hotkey_self_heal.dart';

void main() {
  const idle = HotkeyHealState(
    hotkeyEnabled: true,
    dictationBusy: false,
    keyHeld: false,
    captureActive: false,
    modifierOnlyActive: false,
  );

  group('hotkeyHealBlocker', () {
    test('lets a heal run when the hotkey is enabled and idle', () {
      expect(hotkeyHealBlocker(idle), isNull);
    });

    test('blocks while the hotkey is disabled', () {
      expect(
        hotkeyHealBlocker(
          const HotkeyHealState(
            hotkeyEnabled: false,
            dictationBusy: false,
            keyHeld: false,
            captureActive: false,
            modifierOnlyActive: false,
          ),
        ),
        isNotNull,
      );
    });

    test('blocks during a dictation (recording or transcribing)', () {
      expect(
        hotkeyHealBlocker(
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: true,
            keyHeld: false,
            captureActive: false,
            modifierOnlyActive: false,
          ),
        ),
        isNotNull,
      );
    });

    test('blocks while the hotkey is held (hold mode keeps its release)', () {
      expect(
        hotkeyHealBlocker(
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: false,
            keyHeld: true,
            captureActive: false,
            modifierOnlyActive: false,
          ),
        ),
        isNotNull,
      );
    });

    test('blocks while the hotkey recorder or onboarding step captures', () {
      expect(
        hotkeyHealBlocker(
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: false,
            keyHeld: false,
            captureActive: true,
            modifierOnlyActive: false,
          ),
        ),
        isNotNull,
      );
    });

    test('blocks while a modifier-only trigger owns the observer', () {
      expect(
        hotkeyHealBlocker(
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: false,
            keyHeld: false,
            captureActive: false,
            modifierOnlyActive: true,
          ),
        ),
        isNotNull,
      );
    });

    test('gives a distinct reason per blocker', () {
      final reasons = <String>{
        for (final state in [
          const HotkeyHealState(
            hotkeyEnabled: false,
            dictationBusy: false,
            keyHeld: false,
            captureActive: false,
            modifierOnlyActive: false,
          ),
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: true,
            keyHeld: false,
            captureActive: false,
            modifierOnlyActive: false,
          ),
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: false,
            keyHeld: true,
            captureActive: false,
            modifierOnlyActive: false,
          ),
          const HotkeyHealState(
            hotkeyEnabled: true,
            dictationBusy: false,
            keyHeld: false,
            captureActive: true,
            modifierOnlyActive: false,
          ),
        ])
          ?hotkeyHealBlocker(state),
      };
      expect(reasons, hasLength(4));
    });
  });

  group('HotkeyHealGate', () {
    test('throttles a second heal within the minimum interval', () {
      final gate = HotkeyHealGate();
      final t0 = DateTime(2026, 10, 29, 19, 30);

      expect(gate.isThrottled(t0), isFalse);
      gate.markRun(t0);

      expect(
        gate.isThrottled(t0.add(const Duration(seconds: 5))),
        isTrue,
        reason: 'a stall right after a wake must not heal twice',
      );
      expect(
        gate.isThrottled(
          t0.add(kHotkeyHealMinInterval + const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test(
      'reports the toast exactly once, when the failure streak reaches the threshold',
      () {
        final gate = HotkeyHealGate();

        expect(gate.recordFailure(), isFalse, reason: 'first failure');
        expect(gate.recordFailure(), isFalse, reason: 'second failure');
        expect(gate.recordFailure(), isTrue, reason: 'third failure: toast');
        expect(gate.recordFailure(), isFalse, reason: 'no toast storm');
        expect(gate.consecutiveFailures, 4);
      },
    );

    test('a successful heal resets the failure streak', () {
      final gate = HotkeyHealGate();
      gate
        ..recordFailure()
        ..recordFailure()
        ..recordSuccess();

      expect(gate.consecutiveFailures, 0);
      expect(gate.recordFailure(), isFalse);
      expect(gate.recordFailure(), isFalse);
      expect(gate.recordFailure(), isTrue);
    });

    test('the threshold is three consecutive failures', () {
      expect(kHotkeyHealFailureToastThreshold, 3);
    });

    test('the minimum interval is 30 seconds and the timer is 5 minutes', () {
      expect(kHotkeyHealMinInterval, const Duration(seconds: 30));
      expect(kHotkeyHealInterval, const Duration(minutes: 5));
    });
  });

  group('HotkeyCaptureGuard', () {
    tearDown(HotkeyCaptureGuard.reset);

    test('is active while at least one capture is open', () {
      expect(HotkeyCaptureGuard.active, isFalse);

      HotkeyCaptureGuard.begin();
      HotkeyCaptureGuard.begin();
      expect(HotkeyCaptureGuard.active, isTrue);

      HotkeyCaptureGuard.end();
      expect(HotkeyCaptureGuard.active, isTrue, reason: 'still one open');

      HotkeyCaptureGuard.end();
      expect(HotkeyCaptureGuard.active, isFalse);
    });

    test('an unbalanced end never drives the count negative', () {
      HotkeyCaptureGuard.end();
      expect(HotkeyCaptureGuard.active, isFalse);

      HotkeyCaptureGuard.begin();
      expect(HotkeyCaptureGuard.active, isTrue);
    });
  });
}
