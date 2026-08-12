/// Tests confirming the `retainRecentAudio` toggle in [PrivacySection]
/// writes through to `privacy.retainRecentAudio` — the setting that gates
/// the rotating WAV-retention feature in `RecordingOrchestrator`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

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
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('PrivacySection retain-recent-audio toggle', () {
    testWidgets('defaults to off', (tester) async {
      final notifier = FakeSettingsNotifier();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.widgetWithText(
        SettingRow,
        l10n.settingsRetainRecentAudio,
      );
      expect(row, findsOneWidget);
      final toggle = tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('toggling it writes privacy.retainRecentAudio', (tester) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(privacy: PrivacySettings(retainRecentAudio: false)),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.widgetWithText(
        SettingRow,
        l10n.settingsRetainRecentAudio,
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(notifier.state.value!.privacy.retainRecentAudio, isTrue);
    });
  });
}
