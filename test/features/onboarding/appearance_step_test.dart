/// Widget tests for [AppearanceStep] — the theme choice, the picture half of
/// the Appearance onboarding page (the autostart toggle beside it has its own
/// test; the page that composes both is covered in the overlay test).
///
/// The theme tests migrated here from `welcome_step_test.dart` when the choice
/// moved off page 1 (the pre-rendered demo clips there cannot follow a live
/// theme switch), and the control became three picture swatches when the
/// choice got its own page. What is asserted is unchanged by that: tapping a
/// swatch writes the new [ThemeMode] to settings immediately — no confirm
/// step, nothing blocks Next — and every swatch stays reachable and correctly
/// labelled for a screen reader, which is what the previous segmented control
/// guaranteed too.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';

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

Future<_FakeSettingsNotifier> _pumpStep(
  WidgetTester tester, {
  AppSettings? settings,
}) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: AppearanceStep()),
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

  group('AppearanceStep — theme choice', () {
    testWidgets('updates theme mode when a swatch is tapped', (tester) async {
      final notifier = await _pumpStep(
        tester,
        settings: const AppSettings(
          interface_: InterfaceSettings(themeMode: ThemeMode.dark),
        ),
      );

      await tester.tap(find.byKey(appearanceThemeSwatchKey(ThemeMode.light)));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.light);

      await tester.tap(find.byKey(appearanceThemeSwatchKey(ThemeMode.system)));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.system);

      await tester.tap(find.byKey(appearanceThemeSwatchKey(ThemeMode.dark)));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.interface_.themeMode, ThemeMode.dark);
    });

    testWidgets('renders all three swatches with the default settings — the '
        'step needs no input to be walkable', (tester) async {
      await _pumpStep(tester);

      expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
      for (final mode in ThemeMode.values) {
        expect(
          find.byKey(appearanceThemeSwatchKey(mode)),
          findsOneWidget,
          reason: 'missing swatch for $mode',
        );
      }
      expect(find.text(l10n.onboardingThemeLight), findsOneWidget);
      expect(find.text(l10n.onboardingThemeDark), findsOneWidget);
      expect(find.text(l10n.onboardingThemeSystem), findsOneWidget);
    });

    testWidgets('every swatch is a button whose semantics carry the theme '
        'name and the selection state — the picture is decorative and must '
        'not be what a screen reader has to interpret', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpStep(
        tester,
        settings: const AppSettings(
          interface_: InterfaceSettings(themeMode: ThemeMode.system),
        ),
      );

      for (final (mode, label) in [
        (ThemeMode.light, l10n.onboardingThemeLight),
        (ThemeMode.dark, l10n.onboardingThemeDark),
        (ThemeMode.system, l10n.onboardingThemeSystem),
      ]) {
        expect(
          tester.getSemantics(find.byKey(appearanceThemeSwatchKey(mode))),
          matchesSemantics(
            label: label,
            isButton: true,
            hasSelectedState: true,
            isSelected: mode == ThemeMode.system,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
          reason: 'semantics mismatch for $mode',
        );
      }

      handle.dispose();
    });

    testWidgets('carries no title of its own — the Appearance page owns the '
        'heading, because the page is the theme choice AND the autostart '
        'toggle and only the page can name both', (tester) async {
      await _pumpStep(tester);

      expect(find.text(l10n.onboardingAppearancePageTitle), findsNothing);
      expect(find.text(l10n.onboardingAppearancePageSubtitle), findsNothing);
      // The swatches are the whole widget.
      expect(find.byKey(kAppearanceThemeSelectorKey), findsOneWidget);
    });
  });

  group('AppearanceStep \u2014 keyboard access', () {
    testWidgets(
      'a focused swatch is activated by Enter \u2014 the focus ring shares its '
      'node with the InkWell, so wiring the ring must not swallow the key',
      (tester) async {
        final notifier = await _pumpStep(
          tester,
          settings: const AppSettings(
            interface_: InterfaceSettings(themeMode: ThemeMode.dark),
          ),
        );

        final ink = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(appearanceThemeSwatchKey(ThemeMode.light)),
            matching: find.byType(InkWell),
          ),
        );
        expect(
          ink.focusNode?.canRequestFocus,
          isTrue,
          reason:
              'the swatch must own a focusable node to be keyboard-reachable',
        );
        ink.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(notifier.state.value!.interface_.themeMode, ThemeMode.light);
      },
    );
  });
}
