library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';

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
    testWidgets('updates locale when the language selector is tapped', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(const AppSettings(locale: 'en'));

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: WelcomeStep(onNext: _noop)),
          size: const Size(1280, 980),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'de');
    });

    testWidgets('updates theme mode from preview cards and system chip', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(themeMode: ThemeMode.dark),
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
}

void _noop() {}
