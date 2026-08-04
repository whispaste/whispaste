/// Widget tests for [AppearanceSection] — the theme choice + recording
/// duration side note on the Model & Hotkey onboarding page.
///
/// The theme tests migrated here from `welcome_step_test.dart` when the
/// choice moved from page 1 to page 3 (the pre-rendered demo loops on page 1
/// cannot follow a live theme switch): tapping a segment writes the new
/// [ThemeMode] to settings immediately — no confirm step, nothing blocks
/// Next. The duration note must show the *configured*
/// `BehaviorSettings.maxRecordDuration` (not a hard-coded 120) and disappear
/// entirely when the limit is 0 (= unlimited).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/appearance_section.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
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

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester, {
  AppSettings? settings,
}) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: AppearanceSection()),
      size: const Size(1280, 980),
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => notifier)],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('AppearanceSection — theme choice', () {
    testWidgets('updates theme mode when a segment is tapped', (tester) async {
      final notifier = await _pumpSection(
        tester,
        settings: const AppSettings(
          interface_: InterfaceSettings(themeMode: ThemeMode.dark),
        ),
      );

      await tester.tap(find.text(l10n.onboardingThemeLight));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.light);

      await tester.tap(find.text(l10n.onboardingThemeSystem));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.system);

      await tester.tap(find.text(l10n.onboardingThemeDark));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.dark);
    });

    testWidgets('renders all three segments with the default settings — the '
        'step needs no input to be walkable', (tester) async {
      await _pumpSection(tester);

      expect(find.text(l10n.onboardingThemeLight), findsOneWidget);
      expect(find.text(l10n.onboardingThemeDark), findsOneWidget);
      expect(find.text(l10n.onboardingThemeSystem), findsOneWidget);
      expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
    });
  });

  group('AppearanceSection — recording duration note', () {
    testWidgets('shows the configured maxRecordDuration value, not a '
        'hard-coded default', (tester) async {
      await _pumpSection(
        tester,
        settings: const AppSettings(
          behavior: BehaviorSettings(maxRecordDuration: 90),
        ),
      );

      expect(find.byKey(kAppearanceMaxDurationHintKey), findsOneWidget);
      expect(
        find.text(
          l10n.onboardingMaxRecordDurationHint(
            90,
            l10n.settingsRecordingSafety,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows 120 seconds with the untouched defaults', (
      tester,
    ) async {
      await _pumpSection(tester);

      expect(AppSettings.defaults.behavior.maxRecordDuration, 120);
      expect(
        find.text(
          l10n.onboardingMaxRecordDurationHint(
            120,
            l10n.settingsRecordingSafety,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides the note entirely when the limit is 0 (unlimited)', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        settings: const AppSettings(
          behavior: BehaviorSettings(maxRecordDuration: 0),
        ),
      );

      expect(find.byKey(kAppearanceMaxDurationHintKey), findsNothing);
    });
  });
}
