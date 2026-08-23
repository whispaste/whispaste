/// Tests for [OnboardingRevisionRunNotifier] — the session-only flag and the
/// two state transitions around it — `.scratch/onboarding-revisions/
/// issues/03`. [onboardingSurfaceActive] itself already has coverage
/// wherever the eight read sites it feeds are tested (see that library's
/// doc comment for the full list); this file is about `start()`/`complete()`
/// specifically, which is the seam ticket 03 actually builds on top of.
library;

import 'package:flutter/material.dart';
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

/// [leaveOnboardingSurface] takes a [WidgetRef], not a [ProviderContainer]
/// (it is called from `WpRecordingBehavior`'s `ConsumerState`) — so exercising
/// it here needs a real widget mounted against the test's own container,
/// exactly the way production obtains its `ref`.
Future<void> _tapLeaveOnboardingSurface(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => leaveOnboardingSurface(ref),
            child: const Text('leave'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

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

  group('leaveOnboardingSurface', () {
    testWidgets(
      'first run in progress: stamps onboardingCompleted, resets the step '
      'and the target content version — same as reaching the last step '
      'normally, so the overlay unmounts (issue #78: an "Open Settings" '
      'toast action fired from the test-recording step must make Settings '
      'actually visible)',
      (tester) async {
        final container = _makeContainer(
          initial: AppSettings.defaults.copyWithSections(
            onboarding: const OnboardingSettings(
              onboardingCompleted: false,
              onboardingCurrentStep: 6,
            ),
          ),
          registry: [_entry(1), _entry(2)],
        );
        await container.read(settingsProvider.future);

        await _tapLeaveOnboardingSurface(tester, container);

        final onboarding = container.read(settingsProvider).value!.onboarding;
        expect(onboarding.onboardingCompleted, isTrue);
        expect(onboarding.onboardingCurrentStep, 0);
        expect(
          onboarding.onboardingContentVersion,
          targetOnboardingContentVersion([
            _entry(1),
            _entry(2),
          ], currentOnboardingPlatform()),
        );
        expect(container.read(onboardingSurfaceActiveProvider), isFalse);
      },
    );

    testWidgets(
      'manual review open: closes the review, leaves onboardingCompleted '
      'alone',
      (tester) async {
        final container = _makeContainer(
          initial: AppSettings.defaults.copyWithSections(
            onboarding: const OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);
        container.read(onboardingManuallyOpenProvider.notifier).open();
        expect(container.read(onboardingSurfaceActiveProvider), isTrue);

        await _tapLeaveOnboardingSurface(tester, container);

        expect(container.read(onboardingManuallyOpenProvider), isFalse);
        expect(
          container
              .read(settingsProvider)
              .value!
              .onboarding
              .onboardingCompleted,
          isTrue,
        );
        expect(container.read(onboardingSurfaceActiveProvider), isFalse);
      },
    );

    testWidgets(
      'revision run in progress: completes the run (stamps the registry\'s '
      'target version) exactly like reading it to the end would',
      (tester) async {
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

        await _tapLeaveOnboardingSurface(tester, container);

        final onboarding = container.read(settingsProvider).value!.onboarding;
        expect(onboarding.onboardingContentVersion, 2);
        expect(container.read(onboardingRevisionRunProvider), isFalse);
        expect(container.read(onboardingSurfaceActiveProvider), isFalse);
      },
    );

    testWidgets('no onboarding surface active: no-op', (tester) async {
      final container = _makeContainer(
        initial: AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      await _tapLeaveOnboardingSurface(tester, container);

      expect(
        container.read(settingsProvider).value!.onboarding.onboardingCompleted,
        isTrue,
      );
    });
  });
}
