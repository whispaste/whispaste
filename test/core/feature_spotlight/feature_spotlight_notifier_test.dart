/// ProviderContainer-level tests for [FeatureSpotlightNotifier] —
/// `.scratch/feature-spotlight/issues/01-spotlight-mechanism.md`.
///
/// These cover the acceptance criteria the pure `pendingFeatureSpotlights`
/// tests (`feature_spotlight_test.dart`) cannot: the onboarding-surface
/// gating (incomplete onboarding, a manual review, a revision run in
/// progress) and the persistence round-trip through `OnboardingSettings`.
/// No widgets are pumped — a plain [ProviderContainer] is enough, exactly
/// like `onboarding_revision_run_test.dart`'s `_FakeSettingsNotifier`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/feature_spotlight/feature_spotlight.dart';
import 'package:whispaste/core/feature_spotlight/feature_spotlight_notifier.dart';
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

/// Stands in for a user with an onboarding revision run in progress —
/// mirrors `store_thank_you_dialog_test.dart`'s `_RunningRevisionNotifier`.
class _RunningRevisionNotifier extends OnboardingRevisionRunNotifier {
  @override
  bool build() => true;
}

class _ManuallyOpenNotifier extends OnboardingManuallyOpenNotifier {
  @override
  bool build() => true;
}

/// A completed-onboarding user with no ids marked seen yet.
AppSettings _completedUser({String seenFeatureSpotlightIds = ''}) =>
    AppSettings.defaults.copyWithSections(
      onboarding: OnboardingSettings(
        onboardingCompleted: true,
        seenFeatureSpotlightIds: seenFeatureSpotlightIds,
      ),
    );

/// No id parameter — every entry in these tests is platform-unscoped
/// (`platforms: null`), on purpose: `checkAndMaybeShow` resolves the
/// platform via `currentOnboardingPlatform()` off `dart:io`, so a
/// platform-scoped entry would make these tests host-dependent. Platform
/// filtering is covered by the pure `pendingFeatureSpotlights` tests, where
/// it's an explicit parameter.
FeatureSpotlightEntry _entry(String id) => FeatureSpotlightEntry(
  id: id,
  title: (l10n) => 'title $id',
  description: (l10n) => 'description $id',
);

/// Builds a [ProviderContainer] and waits for the fake [SettingsNotifier]'s
/// `AsyncNotifier.build()` to settle before returning it — [settingsProvider]
/// starts in `AsyncLoading` on the first read, and `checkAndMaybeShow`/
/// `dismiss` read `.value` synchronously, so an unsettled container would
/// make every test see a `null` (never-set-up) settings snapshot.
Future<ProviderContainer> _makeContainer({
  required AppSettings settings,
  required FeatureSpotlightRegistry registry,
  bool revisionRunning = false,
  bool manuallyOpen = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
      featureSpotlightRegistryProvider.overrideWithValue(registry),
      if (revisionRunning)
        onboardingRevisionRunProvider.overrideWith(
          () => _RunningRevisionNotifier(),
        ),
      if (manuallyOpen)
        onboardingManuallyOpenProvider.overrideWith(
          () => _ManuallyOpenNotifier(),
        ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);
  return container;
}

void main() {
  group('FeatureSpotlightNotifier.checkAndMaybeShow', () {
    test('an empty registry never shows a hint', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: const [],
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(featureSpotlightProvider).shouldShow, isFalse);
    });

    test('onboardingCompleted == false suppresses the hint even with pending '
        'entries', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: [_entry('a')],
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: false);

      expect(container.read(featureSpotlightProvider).shouldShow, isFalse);
    });

    test('a manually reopened onboarding review suppresses the hint', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: [_entry('a')],
        manuallyOpen: true,
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(featureSpotlightProvider).shouldShow, isFalse);
    });

    test('a revision run in progress suppresses the hint AND leaves '
        'seenFeatureSpotlightIds untouched — no data loss, still pending next '
        'start', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: [_entry('a')],
        revisionRunning: true,
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(featureSpotlightProvider).shouldShow, isFalse);
      expect(
        container
            .read(settingsProvider)
            .value
            ?.onboarding
            .seenFeatureSpotlightIds,
        '',
        reason:
            'checkAndMaybeShow must never write the seen-ids field — only '
            'dismiss() does, and it was never called here',
      );
    });

    test('multiple pending entries are bundled into a single showing, newest '
        'first', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: [_entry('a'), _entry('b'), _entry('c')],
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      final pending = container.read(featureSpotlightProvider).pending;
      expect(pending.map((e) => e.id).toList(), ['c', 'b', 'a']);
    });

    test('entries already in seenFeatureSpotlightIds are excluded', () async {
      final container = await _makeContainer(
        settings: _completedUser(seenFeatureSpotlightIds: 'a'),
        registry: [_entry('a'), _entry('b')],
      );
      await container
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      final pending = container.read(featureSpotlightProvider).pending;
      expect(pending.map((e) => e.id).toList(), ['b']);
    });
  });

  group('FeatureSpotlightNotifier.dismiss', () {
    test(
      'persists every currently-pending entry as seen and clears the state',
      () async {
        final container = await _makeContainer(
          settings: _completedUser(),
          registry: [_entry('a'), _entry('b')],
        );
        final notifier = container.read(featureSpotlightProvider.notifier);
        await notifier.checkAndMaybeShow(onboardingCompleted: true);
        expect(container.read(featureSpotlightProvider).shouldShow, isTrue);

        await notifier.dismiss();

        expect(container.read(featureSpotlightProvider).shouldShow, isFalse);
        expect(
          parseFeatureSpotlightSeenIds(
            container
                    .read(settingsProvider)
                    .value
                    ?.onboarding
                    .seenFeatureSpotlightIds ??
                '',
          ),
          {'a', 'b'},
        );
      },
    );

    test(
      'double-dismiss is idempotent — the second call is a safe no-op',
      () async {
        final container = await _makeContainer(
          settings: _completedUser(),
          registry: [_entry('a')],
        );
        final notifier = container.read(featureSpotlightProvider.notifier);
        await notifier.checkAndMaybeShow(onboardingCompleted: true);
        await notifier.dismiss();
        final afterFirst = container
            .read(settingsProvider)
            .value
            ?.onboarding
            .seenFeatureSpotlightIds;

        await notifier.dismiss();
        final afterSecond = container
            .read(settingsProvider)
            .value
            ?.onboarding
            .seenFeatureSpotlightIds;

        expect(afterSecond, afterFirst);
      },
    );

    test('after a dismiss and app restart, a fresh checkAndMaybeShow with the '
        'updated settings yields no pending entries', () async {
      final container = await _makeContainer(
        settings: _completedUser(),
        registry: [_entry('a')],
      );
      final notifier = container.read(featureSpotlightProvider.notifier);
      await notifier.checkAndMaybeShow(onboardingCompleted: true);
      await notifier.dismiss();

      // Simulate a fresh app start: a brand-new container reading the
      // settings the previous one just persisted.
      final restarted = await _makeContainer(
        settings: container.read(settingsProvider).value!,
        registry: [_entry('a')],
      );
      await restarted
          .read(featureSpotlightProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(restarted.read(featureSpotlightProvider).shouldShow, isFalse);
    });
  });
}
