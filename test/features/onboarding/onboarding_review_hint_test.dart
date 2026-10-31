/// Tests for the one-time microphone-and-paste notice (Onboarding v6, V08,
/// E1 a) and for the review it opens.
///
/// The notice is for a finished setup on an older flow version only. It is
/// shown once on the start page, counts as shown by stamping the current flow
/// version, and opens a review on the microphone page without forcing a run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/onboarding_review_hint.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  /// Every write, in order. The shown mark is the write under test.
  final List<AppSettings> writes = [];

  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    writes.add(_settings);
    state = AsyncData(_settings);
  }
}

/// A setup finished before the current flow version (a released install).
AppSettings _finishedOnOlderFlow() => AppSettings.defaults.copyWithSections(
  onboarding: const OnboardingSettings(onboardingCompleted: true),
);

/// A setup finished on the current flow version, or one never finished.
AppSettings _currentFlow({required bool completed}) =>
    AppSettings.defaults.copyWithSections(
      onboarding: OnboardingSettings(
        onboardingCompleted: completed,
        onboardingFlowVersion: kOnboardingFlowVersion,
      ),
    );

Future<_FakeSettingsNotifier> _pumpBanner(
  WidgetTester tester, {
  required AppSettings settings,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(800, 600),
}) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Align(
            alignment: Alignment.topCenter,
            child: OnboardingReviewHintBanner(),
          ),
        ),
      ),
      size: size,
      locale: locale,
      overrides: [settingsProvider.overrideWith(() => notifier)],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Finder _banner() => find.byKey(const ValueKey('onboarding-review-hint'));

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(OnboardingReviewHintBanner)),
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Real metrics, so the layout checks below measure what ships.
    await loadAppFonts();
  });

  group('onboardingReviewHintDue', () {
    test('is due only for a finished setup on an older flow version', () {
      expect(
        onboardingReviewHintDue(onboardingCompleted: true, flowVersion: 0),
        isTrue,
        reason: 'A released install has no stored flow version at all.',
      );
      expect(
        onboardingReviewHintDue(
          onboardingCompleted: true,
          flowVersion: kOnboardingFlowVersion - 1,
        ),
        isTrue,
      );
      expect(
        onboardingReviewHintDue(
          onboardingCompleted: true,
          flowVersion: kOnboardingFlowVersion,
        ),
        isFalse,
        reason: 'Shown once: the stamp is the current flow version.',
      );
      expect(
        onboardingReviewHintDue(onboardingCompleted: false, flowVersion: 0),
        isFalse,
        reason: 'A new install (first run) never gets the notice.',
      );
    });
  });

  group('the start-page notice', () {
    testWidgets('is shown to a finished setup and marks itself shown', (
      tester,
    ) async {
      final notifier = await _pumpBanner(
        tester,
        settings: _finishedOnOlderFlow(),
      );

      expect(_banner(), findsOneWidget);
      expect(find.text(l10n.onboardingReviewHintMessage), findsOneWidget);
      expect(
        notifier.current.onboarding.onboardingFlowVersion,
        kOnboardingFlowVersion,
        reason: 'Showing the notice is what makes it count as shown.',
      );
    });

    testWidgets('is never shown to a new install', (tester) async {
      final notifier = await _pumpBanner(
        tester,
        settings: _currentFlow(completed: false),
      );

      expect(_banner(), findsNothing);
      expect(notifier.writes, isEmpty);
    });

    testWidgets('stays gone once it has been shown', (tester) async {
      await _pumpBanner(tester, settings: _currentFlow(completed: true));

      expect(_banner(), findsNothing);
    });

    testWidgets('dismissing hides it for this visit', (tester) async {
      await _pumpBanner(tester, settings: _finishedOnOlderFlow());

      await tester.tap(
        find.byKey(const ValueKey('onboarding-review-hint-dismiss')),
      );
      await tester.pumpAndSettle();

      expect(_banner(), findsNothing);
    });

    testWidgets(
      'leaving the start page ends the visit: coming back shows nothing',
      (tester) async {
        await _pumpBanner(tester, settings: _finishedOnOlderFlow());
        final container = _container(tester);

        container.read(activePageProvider.notifier).setPage('settings');
        await tester.pumpAndSettle();
        expect(_banner(), findsNothing);

        container.read(activePageProvider.notifier).setPage(kDefaultStartPage);
        await tester.pumpAndSettle();
        expect(
          _banner(),
          findsNothing,
          reason: 'Already marked shown, so a return visit must not repeat it.',
        );
      },
    );

    testWidgets(
      'its link opens a review on the microphone page, not a forced run',
      (tester) async {
        await _pumpBanner(tester, settings: _finishedOnOlderFlow());

        await tester.tap(
          find.byKey(const ValueKey('onboarding-review-hint-open')),
        );
        await tester.pumpAndSettle();

        final container = _container(tester);
        expect(container.read(onboardingManuallyOpenProvider), isTrue);
        expect(
          container.read(onboardingReviewStepProvider),
          OnboardingStepId.mic,
        );
        expect(_banner(), findsNothing);
      },
    );
  });
}
