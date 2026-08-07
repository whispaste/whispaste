/// Tests confirming two pure decision functions extracted from `app.dart`'s
/// `_AppShellState` so they are unit-testable without the surrounding
/// widget tree / window_manager channel:
///  - [shouldRunStartupPermissionGate] (onboarding-redesign ticket 02): the
///    gate must never run while first-run onboarding — which owns both
///    permissions with its own richer UI — is still in progress, nor before
///    settings have loaded at all.
///  - [shouldHideToTrayOnClose] (onboarding-redesign ticket 05): closing the
///    window during first-run onboarding must always quit, regardless of the
///    `closeToTray` setting — a half-onboarded background process has no
///    configured hotkey and no discoverable UI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  group('shouldRunStartupPermissionGate', () {
    test('does not run while settings have not loaded yet', () {
      expect(shouldRunStartupPermissionGate(null), isFalse);
    });

    test('does not run while onboarding is unfinished', () {
      final settings = AppSettings.defaults.copyWith(
        onboardingCompleted: false,
      );
      expect(shouldRunStartupPermissionGate(settings), isFalse);
    });

    test('runs once onboarding has completed', () {
      final settings = AppSettings.defaults.copyWith(onboardingCompleted: true);
      expect(shouldRunStartupPermissionGate(settings), isTrue);
    });
  });

  group('shouldHideToTrayOnClose', () {
    test('quits (does not hide) while settings have not loaded yet', () {
      expect(shouldHideToTrayOnClose(null), isFalse);
    });

    test(
      'quits during first-run onboarding even when closeToTray is enabled',
      () {
        final settings = AppSettings.defaults.copyWith(
          closeToTray: true,
          onboardingCompleted: false,
        );
        expect(shouldHideToTrayOnClose(settings), isFalse);
      },
    );

    test(
      'hides to tray once onboarding is completed and closeToTray is on',
      () {
        final settings = AppSettings.defaults.copyWith(
          closeToTray: true,
          onboardingCompleted: true,
        );
        expect(shouldHideToTrayOnClose(settings), isTrue);
      },
    );

    test('quits when onboarding is completed but closeToTray is off', () {
      final settings = AppSettings.defaults.copyWith(
        closeToTray: false,
        onboardingCompleted: true,
      );
      expect(shouldHideToTrayOnClose(settings), isFalse);
    });
  });
}
