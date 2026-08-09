/// Tests for [OnboardingRevisionRunNotifier] — the session-only flag and the
/// two state transitions around it — `.scratch/onboarding-revisions/
/// issues/03`. [onboardingSurfaceActive] itself already has coverage
/// wherever the eight read sites it feeds are tested (see that library's
/// doc comment for the full list); this file is about `start()`/`complete()`
/// specifically, which is the seam ticket 03 actually builds on top of.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(AppSettings initial) : _settings = initial;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

OnboardingRevisionEntry _entry(int version) => OnboardingRevisionEntry(
  version: version,
  reason: (l10n) => 'reason $version',
);

ProviderContainer _makeContainer({
  required AppSettings initial,
  OnboardingRevisionRegistry registry = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(initial)),
      onboardingRevisionRegistryProvider.overrideWithValue(registry),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('OnboardingRevisionRunNotifier.start', () {
    test('flips the flag to true', () async {
      final container = _makeContainer(
        initial: AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(
            onboardingCompleted: true,
            onboardingCurrentStep: 3,
          ),
        ),
      );
      await container.read(settingsProvider.future);

      expect(container.read(onboardingRevisionRunProvider), isFalse);
      await container.read(onboardingRevisionRunProvider.notifier).start();
      expect(container.read(onboardingRevisionRunProvider), isTrue);
    });

    test('resets the shared step-position field to 0 — belt-and-suspenders '
        'against a value left over from an interrupted first run or a '
        'non-clean prior revision run', () async {
      final container = _makeContainer(
        initial: AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(
            onboardingCompleted: true,
            onboardingCurrentStep: 3,
          ),
        ),
      );
      await container.read(settingsProvider.future);

      await container.read(onboardingRevisionRunProvider.notifier).start();

      expect(
        container
            .read(settingsProvider)
            .value!
            .onboarding
            .onboardingCurrentStep,
        0,
      );
    });
  });

  group('OnboardingRevisionRunNotifier.complete', () {
    test('stamps the registry\'s current target version, resets the step '
        'position, and clears the flag', () async {
      final container = _makeContainer(
        initial: AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(
            onboardingCompleted: true,
            onboardingContentVersion: 1,
          ),
        ),
        registry: [_entry(1), _entry(2)],
      );
      await container.read(settingsProvider.future);
      await container.read(onboardingRevisionRunProvider.notifier).start();

      await container.read(onboardingRevisionRunProvider.notifier).complete();

      final onboarding = container.read(settingsProvider).value!.onboarding;
      expect(onboarding.onboardingContentVersion, 2);
      expect(onboarding.onboardingCurrentStep, 0);
      expect(container.read(onboardingRevisionRunProvider), isFalse);
    });

    test('reaching completion and the (future) visible exit are the same call '
        '— both simply invoke complete(), so calling it directly here stands '
        'in for either', () async {
      final container = _makeContainer(
        initial: AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        ),
        registry: [_entry(1)],
      );
      await container.read(settingsProvider.future);
      await container.read(onboardingRevisionRunProvider.notifier).start();

      // Simulates a mid-flow abort — no navigation happened, complete() is
      // invoked directly, exactly as ticket 04's exit button will.
      await container.read(onboardingRevisionRunProvider.notifier).complete();

      expect(
        onboardingRevisionDue(
          onboardingCompleted: true,
          seenContentVersion: container
              .read(settingsProvider)
              .value!
              .onboarding
              .onboardingContentVersion,
          targetContentVersion: targetOnboardingContentVersion([
            _entry(1),
          ], currentOnboardingPlatform()),
        ),
        isFalse,
        reason:
            'A run offered at most once per version must not still be '
            'due immediately after it ends, whichever way it ended.',
      );
    });
  });
}
