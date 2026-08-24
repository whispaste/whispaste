/// Tests for the feature spotlight hint —
/// `.scratch/feature-spotlight/issues/01-spotlight-mechanism.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/feature_spotlight/feature_spotlight.dart';
import 'package:whispaste/core/feature_spotlight/feature_spotlight_notifier.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/widgets/feature_spotlight_notice.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

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

/// Stub that lets tests drive [FeatureSpotlightState] without touching
/// settings or the onboarding-surface gate directly.
class _FakeFeatureSpotlightNotifier extends FeatureSpotlightNotifier {
  int dismissCallCount = 0;

  @override
  Future<void> checkAndMaybeShow({required bool onboardingCompleted}) async {}

  /// Flips [FeatureSpotlightState.pending] so
  /// [WpFeatureSpotlightWatcher]'s listener fires immediately (no show
  /// delay in this watcher, unlike the store thank-you one).
  void triggerShow(List<FeatureSpotlightEntry> entries) =>
      state = FeatureSpotlightState(pending: entries);

  @override
  Future<void> dismiss() async {
    dismissCallCount++;
    state = const FeatureSpotlightState();
  }
}

/// Stands in for a user with an onboarding revision run in progress.
class _RunningRevisionNotifier extends OnboardingRevisionRunNotifier {
  @override
  bool build() => true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FeatureSpotlightEntry _entry(String id) => FeatureSpotlightEntry(
  id: id,
  title: (l10n) => 'Title $id',
  description: (l10n) => 'Description $id',
);

AppSettings _completedUser() => AppSettings.defaults.copyWithSections(
  onboarding: const OnboardingSettings(onboardingCompleted: true),
);

/// Pumps [WpFeatureSpotlightWatcher] and lets the dialog's fade-in animation
/// settle.
Future<_FakeFeatureSpotlightNotifier> _showDialog(
  WidgetTester tester,
  List<FeatureSpotlightEntry> entries,
) async {
  final notifier = _FakeFeatureSpotlightNotifier();
  final settingsNotifier = _FakeSettingsNotifier(_completedUser());

  await tester.pumpWidget(
    makeTestable(
      const WpFeatureSpotlightWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [
        featureSpotlightProvider.overrideWith(() => notifier),
        settingsProvider.overrideWith(() => settingsNotifier),
      ],
    ),
  );
  await tester.pump(); // initial build, ref.listen registered

  notifier.triggerShow(entries);
  await tester.pump(); // state change propagated
  await tester.pumpAndSettle(); // showGeneralDialog + fade/slide animation

  return notifier;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WpFeatureSpotlightWatcher', () {
    testWidgets('shows the heading and every pending entry, dismiss button '
        'included', (tester) async {
      await _showDialog(tester, [_entry('a'), _entry('b')]);

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.featureSpotlightHeading), findsOneWidget);
      expect(find.text('Title a'), findsOneWidget);
      expect(find.text('Description a'), findsOneWidget);
      expect(find.text('Title b'), findsOneWidget);
      expect(find.text('Description b'), findsOneWidget);
      expect(find.text(l10n.featureSpotlightDismiss), findsOneWidget);
    });

    testWidgets('tapping dismiss closes the dialog and calls dismiss() on the '
        'notifier — twice by design (the explicit tap, plus the safety-net '
        'call after the dialog route closes, same shape as '
        'WpStoreThankYouWatcher._markDone), which is fine because dismiss() '
        'is documented as idempotent', (tester) async {
      final notifier = await _showDialog(tester, [_entry('a')]);

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.featureSpotlightDismiss));
      await tester.pumpAndSettle();

      expect(find.text(l10n.featureSpotlightHeading), findsNothing);
      expect(notifier.dismissCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets(
      'an entry with an image renders it; one without renders no image',
      (tester) async {
        final withImage = FeatureSpotlightEntry(
          id: 'a',
          title: (l10n) => 'Title a',
          description: (l10n) => 'Description a',
          image: 'assets/feature_spotlight/side_panel.webp',
        );
        await _showDialog(tester, [withImage, _entry('b')]);

        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'suppressed if an onboarding revision run starts between check time '
      'and the listener firing',
      (tester) async {
        final notifier = _FakeFeatureSpotlightNotifier();
        final settingsNotifier = _FakeSettingsNotifier(_completedUser());

        await tester.pumpWidget(
          makeTestable(
            const WpFeatureSpotlightWatcher(child: SizedBox()),
            locale: const Locale('en'),
            overrides: [
              featureSpotlightProvider.overrideWith(() => notifier),
              settingsProvider.overrideWith(() => settingsNotifier),
              onboardingRevisionRunProvider.overrideWith(
                () => _RunningRevisionNotifier(),
              ),
            ],
          ),
        );
        await tester.pump();

        notifier.triggerShow([_entry('a')]);
        await tester.pump();
        await tester.pumpAndSettle();

        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.featureSpotlightHeading),
          findsNothing,
          reason:
              'The re-check in _maybeShow must catch a revision run that '
              'started after the notifier already decided to show.',
        );
      },
    );

    testWidgets(
      'on a short screen, the entry list scrolls instead of overflowing, '
      'and a visible scrollbar + bottom fade signal that there is more',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        // Short enough that two image-bearing entries cannot fit — the
        // regression this guards is the live-tested "BOTTOM OVERFLOWED BY
        // 146 PIXELS" report, where a plain unscrollable Column just clipped
        // silently past the card edge.
        tester.view.physicalSize = const Size(800, 500);
        tester.view.devicePixelRatio = 1.0;

        final withImage = FeatureSpotlightEntry(
          id: 'a',
          title: (l10n) => 'Title a',
          description: (l10n) => 'Description a',
          image: 'assets/feature_spotlight/side_panel.webp',
        );
        final withImage2 = FeatureSpotlightEntry(
          id: 'b',
          title: (l10n) => 'Title b',
          description: (l10n) => 'Description b',
          image: 'assets/feature_spotlight/snippet_picker.webp',
        );
        await _showDialog(tester, [withImage, withImage2]);

        // The regression itself: Flutter reports an overflow via a caught
        // FlutterError during the frame, which `tester.takeException()`
        // surfaces — a bare `Flexible`/`SingleChildScrollView` bound to a
        // `maxHeight` does not, on its own, prevent this if a descendant
        // still demands more than its slot (that was the live-tested bug).
        expect(tester.takeException(), isNull);

        final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
        expect(
          scrollbar.thumbVisibility,
          isTrue,
          reason:
              'Content taller than the viewport must show a thumb — '
              'otherwise scrolling is possible but undiscoverable.',
        );

        final fades = tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .toList();
        expect(fades, hasLength(2), reason: 'One top fade, one bottom fade.');
        // Scrolled to the very top on open, so only the bottom fade (more
        // content below) should be showing; the top one stays hidden until
        // the user actually scrolls down.
        expect(fades.where((f) => f.opacity == 1).length, 1);
        expect(fades.where((f) => f.opacity == 0).length, 1);
      },
    );
  });
}
