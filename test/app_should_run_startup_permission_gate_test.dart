/// Test confirming [shouldRunStartupPermissionGate] is a pure decision
/// function extracted from `_AppShellState._runStartupPermissionGate`
/// (onboarding-redesign ticket 02): the gate must never run while
/// first-run onboarding — which owns both permissions with its own richer
/// UI — is still in progress, nor before settings have loaded at all.
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
}
