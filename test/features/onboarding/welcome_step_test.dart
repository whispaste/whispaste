library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/locale_native_name.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';
import 'package:whispaste/widgets/language_selector.dart';

import '../../fixtures/test_helpers.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

late L10n l10n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Real bundled UI font instead of the square-glyph test font. The media
    // panel's geometry assertions below are only meaningful against real
    // metrics: with the test font the beat captions wrap to three lines that
    // never occur in the shipped app, which changes every height in the row.
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
  });

  group('WelcomeStep', () {
    testWidgets('renders one selector item per supported locale', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep()),
          size: const Size(1280, 980),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      // Open the dropdown so all entries become visible — the closed
      // state only shows the currently active locale.
      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      for (final locale in L10n.supportedLocales) {
        expect(
          find.text(localeNativeName(locale)),
          findsWidgets,
          reason: 'expected native label for ${locale.languageCode}',
        );
      }
      // Sanity: today's bundled locales are de/en/he, so we expect
      // exactly three labels — guards against accidental duplication.
      expect(L10n.supportedLocales.length, 3);
    });

    testWidgets('updates locale when the German label is tapped', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep()),
          size: const Size(1280, 980),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      // Slice 06 turned the language selector into a dropdown — open it
      // first, then tap the German entry inside the popup.
      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'de');
    });

    testWidgets('updates locale to he when the Hebrew label is tapped', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep()),
          size: const Size(1280, 980),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text(localeNativeName(const Locale('he'))).last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'he');
    });

    testWidgets(
      'renders the three demo beats with Flutter-rendered l10n captions and '
      'no theme selector (the theme choice moved to page 3 — pre-rendered '
      'loops cannot follow a live theme switch)',
      (tester) async {
        final notifier = FakeSettingsNotifier(
          const AppSettings(interface_: InterfaceSettings(locale: 'en')),
        );

        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: WelcomeStep()),
            size: const Size(1280, 980),
            locale: const Locale('en'),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // The three beats: titles + captions come from l10n, never from
        // artwork — the placeholder/loop asset stays text-free.
        expect(find.text(l10n.onboardingBeat1Title), findsOneWidget);
        expect(find.text(l10n.onboardingBeat1Caption), findsOneWidget);
        expect(find.text(l10n.onboardingBeat2Title), findsOneWidget);
        expect(find.text(l10n.onboardingBeat2Caption), findsOneWidget);
        expect(find.text(l10n.onboardingBeat3Title), findsOneWidget);
        expect(find.text(l10n.onboardingBeat3Caption), findsOneWidget);

        // Theme selector is gone from page 1.
        expect(find.text(l10n.onboardingThemeLight), findsNothing);
        expect(find.text(l10n.onboardingThemeDark), findsNothing);
        expect(find.text(l10n.onboardingThemeSystem), findsNothing);
      },
    );

    testWidgets(
      'first beat is active by default (highlighted tile + large media '
      'area); tapping another beat moves highlight and media',
      (tester) async {
        final notifier = FakeSettingsNotifier(
          const AppSettings(interface_: InterfaceSettings(locale: 'en')),
        );

        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: WelcomeStep()),
            size: const Size(1280, 980),
            locale: const Locale('en'),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // Default: beat 0 active — only its media placeholder is mounted.
        expect(find.byKey(onboardingBeatMediaKey(0)), findsOneWidget);
        expect(find.byKey(onboardingBeatMediaKey(1)), findsNothing);
        expect(find.byKey(onboardingBeatMediaKey(2)), findsNothing);

        // The active tile carries the card highlight (non-transparent
        // background), inactive tiles stay transparent — visually
        // de-emphasised but fully rendered.
        Color tileColor(int index) {
          final container = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byKey(onboardingBeatTileKey(index)),
              matching: find.byType(AnimatedContainer),
            ),
          );
          return (container.decoration! as BoxDecoration).color!;
        }

        expect(tileColor(0), isNot(Colors.transparent));
        expect(tileColor(1), Colors.transparent);
        expect(tileColor(2), Colors.transparent);

        // Tap the third beat: highlight + media follow.
        await tester.tap(find.byKey(onboardingBeatTileKey(2)));
        await tester.pumpAndSettle();

        expect(find.byKey(onboardingBeatMediaKey(2)), findsOneWidget);
        expect(find.byKey(onboardingBeatMediaKey(0)), findsNothing);
        expect(tileColor(2), isNot(Colors.transparent));
        expect(tileColor(0), Colors.transparent);

        // All three titles + captions remain in the tree regardless of
        // which beat is active — screen readers always reach them.
        expect(find.text(l10n.onboardingBeat1Title), findsOneWidget);
        expect(find.text(l10n.onboardingBeat2Title), findsOneWidget);
        expect(find.text(l10n.onboardingBeat3Title), findsOneWidget);
      },
    );

    testWidgets(
      'beat showcase mirrors under RTL: text list and media area swap sides '
      'via ambient Directionality (LTR: list start-left; RTL/Hebrew: '
      'list start-right)',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('he')]) {
          final notifier = FakeSettingsNotifier(
            AppSettings(
              interface_: InterfaceSettings(locale: locale.languageCode),
            ),
          );

          await tester.pumpWidget(
            makeTestable(
              const SingleChildScrollView(child: WelcomeStep()),
              size: const Size(1280, 980),
              locale: locale,
              overrides: [settingsProvider.overrideWith(() => notifier)],
            ),
          );
          await tester.pumpAndSettle();

          final tileCenter = tester.getCenter(
            find.byKey(onboardingBeatTileKey(0)),
          );
          final mediaCenter = tester.getCenter(
            find.byKey(onboardingBeatMediaKey(0)),
          );

          if (locale.languageCode == 'he') {
            expect(
              tileCenter.dx,
              greaterThan(mediaCenter.dx),
              reason:
                  'In RTL (he) the beat text list must sit on the right of '
                  'the media area — the Row must mirror via Directionality',
            );
          } else {
            expect(
              tileCenter.dx,
              lessThan(mediaCenter.dx),
              reason:
                  'In LTR (${locale.languageCode}) the beat text list must '
                  'sit on the left of the media area',
            );
          }

          expect(
            tester.takeException(),
            isNull,
            reason: 'No layout exception in ${locale.languageCode}',
          );

          // Clean teardown between locales.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );
  });

  group('WelcomeStep — beat tile semantics', () {
    testWidgets('each beat is an activatable button carrying its own title, '
        'caption and selection state — a selectable node without a tap '
        'action would be announced and then be unusable', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep()),
          size: const Size(1280, 980),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(FakeSettingsNotifier.new)],
        ),
      );
      await tester.pumpAndSettle();

      for (final (index, title, caption) in [
        (0, l10n.onboardingBeat1Title, l10n.onboardingBeat1Caption),
        (1, l10n.onboardingBeat2Title, l10n.onboardingBeat2Caption),
        (2, l10n.onboardingBeat3Title, l10n.onboardingBeat3Caption),
      ]) {
        expect(
          tester.getSemantics(find.byKey(onboardingBeatTileKey(index))),
          matchesSemantics(
            label: '$title\n$caption',
            isButton: true,
            hasSelectedState: true,
            isSelected: index == 0,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
          reason: 'semantics mismatch for beat $index',
        );
      }

      handle.dispose();
    });

    testWidgets(
      'a focused beat tile is activated by Enter — the focus ring shares its '
      'node with the InkWell, so wiring the ring must not swallow the key',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: WelcomeStep()),
            size: const Size(1280, 980),
            locale: const Locale('en'),
            overrides: [
              settingsProvider.overrideWith(FakeSettingsNotifier.new),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(onboardingBeatMediaKey(0)), findsOneWidget);

        final ink = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(onboardingBeatTileKey(2)),
            matching: find.byType(InkWell),
          ),
        );
        expect(
          ink.focusNode?.canRequestFocus,
          isTrue,
          reason: 'the tile must own a focusable node to be keyboard-reachable',
        );
        ink.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.byKey(onboardingBeatMediaKey(2)), findsOneWidget);
        expect(find.byKey(onboardingBeatMediaKey(0)), findsNothing);
      },
    );
  });

  // ── Page-1 geometry and the demo-clip seam (round 3) ────────────────────

  group('WelcomeStep — media panel', () {
    /// Renders page 1 at its real frame width. The default 800-px test
    /// surface would clamp the frame and silently falsify every width
    /// assertion below, so the surface is widened to the real onboarding
    /// window first.
    Future<void> pumpAtFrameWidth(
      WidgetTester tester, {
      bool disableAnimations = false,
      Brightness brightness = Brightness.dark,
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      tester.view.physicalSize = kOnboardingWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        makeTestable(
          MediaQuery(
            data: MediaQueryData(
              disableAnimations: disableAnimations,
              textScaler: textScaler,
            ),
            child: const SingleChildScrollView(
              child: SizedBox(
                width: kOnboardingWelcomeFrameWidth,
                child: WelcomeStep(),
              ),
            ),
          ),
          size: const Size(1280, 980),
          brightness: brightness,
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(FakeSettingsNotifier.new)],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is the wider column and owns its own height — the beat list '
        'no longer dictates how tall the panel gets', (tester) async {
      await pumpAtFrameWidth(tester);

      final media = tester.getSize(find.byKey(onboardingBeatMediaKey(0)));
      final tile = tester.getSize(find.byKey(onboardingBeatTileKey(0)));

      expect(media.width, closeTo(kOnboardingBeatMediaWidth, 0.5));
      expect(media.height, kOnboardingBeatMediaHeight);
      expect(
        media.width,
        greaterThan(tile.width),
        reason:
            'The Conductor reference puts the media panel above the text '
            'column in width; page 1 had it the other way round.',
      );
    });

    testWidgets('keeps its height when the beat list grows — the row grows '
        'around the panel instead of the panel shrinking to the text, which '
        'is the whole inversion this layout is built on', (tester) async {
      await pumpAtFrameWidth(tester);
      final tileAtDefaultScale = tester.getSize(
        find.byKey(onboardingBeatTileKey(0)),
      );

      await pumpAtFrameWidth(tester, textScaler: const TextScaler.linear(1.5));

      expect(
        tester.getSize(find.byKey(onboardingBeatTileKey(0))).height,
        greaterThan(tileAtDefaultScale.height),
        reason: 'the enlarged text scale must actually enlarge the tiles',
      );
      expect(
        tester.getSize(find.byKey(onboardingBeatMediaKey(0))).height,
        kOnboardingBeatMediaHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the beat icon when a clip fails to load — the '
        'fallback is what lets this page ship before any recording exists, '
        'and it is per variant, so a dark-only delivery still renders', (
      tester,
    ) async {
      await pumpAtFrameWidth(tester);

      final imageFinder = find.descendant(
        of: find.byKey(onboardingBeatMediaKey(0)),
        matching: find.byType(Image),
      );
      final image = tester.widget<Image>(imageFinder);
      expect(
        image.errorBuilder,
        isNotNull,
        reason:
            'Without an errorBuilder a missing asset is an unhandled image '
            'error, not a placeholder.',
      );

      // Exercise the fallback directly: whether the asset load rejects
      // before or after a given pump depends on the real event loop, which
      // fake-async pumping does not drive — asserting on that timing would
      // make this test order-dependent rather than meaningful.
      final fallback = image.errorBuilder!(
        tester.element(imageFinder),
        Exception('asset missing'),
        null,
      );
      await tester.pumpWidget(
        makeTestable(
          fallback,
          // Same override count as the first pump — Riverpod's ProviderScope
          // asserts on that when the same scope element is reused.
          overrides: [settingsProvider.overrideWith(FakeSettingsNotifier.new)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('asks for the loop variant normally and for the still variant '
        'under reduced motion — an animated WebP cannot be paused, so the '
        'accessibility flag has to pick a different file', (tester) async {
      String assetOfActivePanel(WidgetTester tester) {
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byKey(onboardingBeatMediaKey(0)),
            matching: find.byType(Image),
          ),
        );
        return (image.image as AssetImage).assetName;
      }

      await pumpAtFrameWidth(tester);
      expect(
        assetOfActivePanel(tester),
        onboardingBeatAssetPath(index: 0, isDark: true, still: false),
      );

      await pumpAtFrameWidth(tester, disableAnimations: true);
      expect(
        assetOfActivePanel(tester),
        onboardingBeatAssetPath(index: 0, isDark: true, still: true),
      );
    });

    testWidgets('follows the theme — a clip recorded in dark mode must not be '
        'shown on a light page', (tester) async {
      await pumpAtFrameWidth(tester, brightness: Brightness.light);

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(onboardingBeatMediaKey(0)),
          matching: find.byType(Image),
        ),
      );
      expect(
        (image.image as AssetImage).assetName,
        onboardingBeatAssetPath(index: 0, isDark: false, still: false),
      );
    });

    test('asset paths are 1-based per beat and name both axes explicitly', () {
      expect(
        onboardingBeatAssetPath(index: 0, isDark: true, still: false),
        'assets/onboarding/beat_1_loop_dark.webp',
      );
      expect(
        onboardingBeatAssetPath(index: 2, isDark: false, still: true),
        'assets/onboarding/beat_3_still_light.webp',
      );
    });
  });

  group('localeNativeName', () {
    test('returns endonyms for shipped locales', () {
      expect(localeNativeName(const Locale('en')), 'English');
      expect(localeNativeName(const Locale('de')), 'Deutsch');
      expect(localeNativeName(const Locale('he')), 'עברית');
    });

    test('falls back to upper-cased language subtag for unknown locales', () {
      // Mock locale stand-in for the extensibility scenario described in
      // the issue — if someone wires a brand-new locale into the app, the
      // helper must still produce *something* renderable rather than
      // throwing.
      expect(localeNativeName(const Locale('xx')), 'XX');
    });
  });
}
