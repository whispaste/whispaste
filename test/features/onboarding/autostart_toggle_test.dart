/// Widget tests for [OnboardingAutostartToggle] — the autostart card on the
/// Autostart & Auto-Paste onboarding page.
///
/// Moved here from the former `ReadyStep` together with the widget; the
/// behavioural guarantee is unchanged: the toggle persists
/// `launchAtStartup` in both directions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/steps/autostart_toggle.dart';

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

Future<void> _pump(
  WidgetTester tester, {
  required _FakeSettingsNotifier settings,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: OnboardingAutostartToggle()),
      size: const Size(1280, 980),
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => settings)],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingAutostartToggle', () {
    testWidgets(
      'off by default; tapping the toggle persists launchAtStartup = true',
      (tester) async {
        final settings = _FakeSettingsNotifier();
        await _pump(tester, settings: settings);

        expect(settings.state.value!.launchAtStartup, isFalse);

        final toggle = find.descendant(
          of: find.byKey(kOnboardingAutostartToggleKey),
          matching: find.byType(Switch),
        );
        expect(toggle, findsOneWidget);
        expect(tester.widget<Switch>(toggle).value, isFalse);

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(
          settings.state.value!.launchAtStartup,
          isTrue,
          reason: 'Tapping the toggle must persist launchAtStartup = true',
        );
      },
    );

    testWidgets('tapping again toggles it back off', (tester) async {
      final settings = _FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(launchAtStartup: true)),
      );
      await _pump(tester, settings: settings);

      final toggle = find.descendant(
        of: find.byKey(kOnboardingAutostartToggleKey),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(settings.state.value!.launchAtStartup, isFalse);
    });
  });
}
