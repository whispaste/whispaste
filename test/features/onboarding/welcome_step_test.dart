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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WelcomeStep', () {
    testWidgets('renders one selector item per supported locale', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep(onNext: _noop)),
          size: const Size(1280, 980),
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
          const SingleChildScrollView(child: WelcomeStep(onNext: _noop)),
          size: const Size(1280, 980),
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
          const SingleChildScrollView(child: WelcomeStep(onNext: _noop)),
          size: const Size(1280, 980),
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

    testWidgets('updates theme mode from preview cards and system chip', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(themeMode: ThemeMode.dark),
        ),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep(onNext: _noop)),
          size: const Size(1280, 980),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.themeMode, ThemeMode.light);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.themeMode, ThemeMode.system);
    });

    testWidgets('fires onNext when the CTA button is tapped', (tester) async {
      var nextCalled = false;

      await tester.pumpWidget(
        makeTestable(
          SingleChildScrollView(
            child: WelcomeStep(onNext: () => nextCalled = true),
          ),
          size: const Size(1280, 980),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(nextCalled, isTrue);
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

void _noop() {}
