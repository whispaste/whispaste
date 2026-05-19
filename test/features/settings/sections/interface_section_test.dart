/// Tests confirming that the language picker inside [InterfaceSection]
/// is the shared [LanguageSelector] widget — single source of truth for
/// the supported-locales list (Slice 07 of the onboarding follow-up).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/widgets/language_selector.dart';

import '../../../fixtures/test_helpers.dart';

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

  group('InterfaceSection language picker', () {
    testWidgets('renders a LanguageSelector widget', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceSection()),
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(interface_: InterfaceSettings(locale: 'en')),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LanguageSelector), findsOneWidget);
    });

    testWidgets('tapping a different entry writes the code to the provider', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'de');
    });
  });
}
