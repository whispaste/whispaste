/// Tests for the two pure functions behind the onboarding revision registry
/// — `.scratch/onboarding-revisions/issues/01`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';

/// A registry entry never actually needs its localized text resolved in
/// these tests — only the version/platform shape drives the pure functions.
OnboardingRevisionEntry _entry(
  int version, {
  Set<OnboardingPlatform>? platforms,
}) => OnboardingRevisionEntry(
  version: version,
  reason: (l10n) => 'reason $version',
  platforms: platforms,
);

void main() {
  group('targetOnboardingContentVersion', () {
    test('an empty registry yields 0', () {
      expect(
        targetOnboardingContentVersion(const [], OnboardingPlatform.macos),
        0,
      );
    });

    test('the highest applicable version wins', () {
      final registry = [_entry(1), _entry(3), _entry(2)];
      expect(
        targetOnboardingContentVersion(registry, OnboardingPlatform.macos),
        3,
      );
    });

    test('a platform-scoped entry does not raise the target on an excluded '
        'platform', () {
      final registry = [
        _entry(1),
        _entry(5, platforms: {OnboardingPlatform.windows}),
      ];
      expect(
        targetOnboardingContentVersion(registry, OnboardingPlatform.macos),
        1,
        reason: 'the v5 entry only applies to Windows',
      );
      expect(
        targetOnboardingContentVersion(registry, OnboardingPlatform.windows),
        5,
        reason: 'on Windows the scoped entry does apply',
      );
    });

    test('an entry with no platform scope applies everywhere', () {
      final registry = [_entry(4)];
      for (final platform in OnboardingPlatform.values) {
        expect(targetOnboardingContentVersion(registry, platform), 4);
      }
    });
  });

  group('onboardingRevisionDue', () {
    test('an empty-registry target (0) never triggers', () {
      expect(
        onboardingRevisionDue(
          onboardingCompleted: true,
          seenContentVersion: 0,
          targetContentVersion: 0,
        ),
        isFalse,
      );
    });

    test('a tie between seen and target does not trigger', () {
      expect(
        onboardingRevisionDue(
          onboardingCompleted: true,
          seenContentVersion: 2,
          targetContentVersion: 2,
        ),
        isFalse,
      );
    });

    test('a stamped version above the target (downgrade to an older build) '
        'does not trigger', () {
      expect(
        onboardingRevisionDue(
          onboardingCompleted: true,
          seenContentVersion: 3,
          targetContentVersion: 2,
        ),
        isFalse,
      );
    });

    test('incomplete onboarding never triggers, even far below target', () {
      expect(
        onboardingRevisionDue(
          onboardingCompleted: false,
          seenContentVersion: 0,
          targetContentVersion: 5,
        ),
        isFalse,
      );
    });

    test('completed onboarding below target triggers', () {
      expect(
        onboardingRevisionDue(
          onboardingCompleted: true,
          seenContentVersion: 1,
          targetContentVersion: 2,
        ),
        isTrue,
      );
    });
  });

  group('OnboardingRevisionEntry.appliesTo', () {
    test('null platforms applies to every platform', () {
      final entry = _entry(1);
      for (final platform in OnboardingPlatform.values) {
        expect(entry.appliesTo(platform), isTrue);
      }
    });

    test('a non-null set restricts to its members', () {
      final entry = _entry(1, platforms: {OnboardingPlatform.linux});
      expect(entry.appliesTo(OnboardingPlatform.linux), isTrue);
      expect(entry.appliesTo(OnboardingPlatform.macos), isFalse);
      expect(entry.appliesTo(OnboardingPlatform.windows), isFalse);
    });
  });
}
