/// Pure-logic tests for onboarding-vs-regular window geometry (ticket 03:
/// fixed onboarding start size without ever overwriting the user's regular
/// geometry). No `window_manager` platform channel involved — everything
/// here is checked through `AppSettings`' own write paths.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart';

void main() {
  group('resolveDesktopWindowGeometry — onboarding unfinished', () {
    test('uses the fixed onboarding size, centered, never maximized', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: false,
        windowX: 400,
        windowY: 200,
        windowWidth: 1600,
        windowHeight: 1000,
        windowMaximized: true,
      );

      final geometry = resolveDesktopWindowGeometry(settings);

      // Pins the literal decided in the PRD triage (1100×720, three demo
      // beats side by side) — asserting against `kOnboardingWindowSize`
      // itself would just check the constant equals itself.
      expect(geometry.size, const Size(1100, 720));
      expect(geometry.size, kOnboardingWindowSize);
      expect(
        geometry.position,
        isNull,
        reason: 'onboarding never reads the persisted regular position',
      );
      expect(geometry.maximized, isFalse);
    });
  });

  group('resolveDesktopWindowGeometry — onboarding completed', () {
    test('uses the persisted regular geometry, including position', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: true,
        windowX: 120,
        windowY: 80,
        windowWidth: 1300,
        windowHeight: 900,
        windowMaximized: false,
      );

      final geometry = resolveDesktopWindowGeometry(settings);

      expect(geometry.size, const Size(1300, 900));
      expect(geometry.position, const Offset(120, 80));
      expect(geometry.maximized, isFalse);
    });

    test('falls back to centering when no position was ever persisted', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: true,
        windowX: -1,
        windowY: -1,
      );

      final geometry = resolveDesktopWindowGeometry(settings);

      expect(geometry.position, isNull);
    });

    test('carries the maximized flag through', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: true,
        windowMaximized: true,
      );

      final geometry = resolveDesktopWindowGeometry(settings);

      expect(geometry.maximized, isTrue);
    });
  });

  group('shouldPersistWindowGeometry', () {
    test('is false while onboarding is unfinished', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: false,
      );
      expect(shouldPersistWindowGeometry(settings), isFalse);
    });

    test('is true once onboarding is completed', () {
      final settings = AppSettings.defaults.copyWith(onboardingCompleted: true);
      expect(shouldPersistWindowGeometry(settings), isTrue);
    });
  });

  group('regression: a full onboarding run must not mutate the persisted '
      'regular geometry', () {
    test('the geometry read before onboarding starts is untouched after it '
        'completes, given the save-path guard is honoured', () {
      final before = AppSettings.defaults.copyWith(
        onboardingCompleted: false,
        windowX: 300,
        windowY: 150,
        windowWidth: 1400,
        windowHeight: 950,
        windowMaximized: false,
      );

      // The onboarding window resizes freely during the run — the guard
      // (`shouldPersistWindowGeometry`) is what `_debounceSaveWindowState`
      // checks before writing, so simulating "onboarding still running"
      // must report `false` here, i.e. no write would have happened.
      expect(shouldPersistWindowGeometry(before), isFalse);

      final after = before.copyWith(onboardingCompleted: true);

      expect(after.windowPosition, before.windowPosition);
      expect(resolveDesktopWindowGeometry(after).size, const Size(1400, 950));
    });
  });
}
