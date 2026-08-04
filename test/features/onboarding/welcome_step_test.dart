library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/locale_native_name.dart';
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
