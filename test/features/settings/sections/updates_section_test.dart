/// Tests for [UpdatesSection] — release channel toggle + automatic update
/// check, and the store-channel hide rule (AC „Store-Build blendet den Toggle
/// sinnvoll aus").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/updates_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_channel_service.dart';

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

/// Taps the [Switch] inside the [SettingRow] that shows [label].
Future<void> _tapRowSwitch(WidgetTester tester, String label) async {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(SettingRow),
  );
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pump();
}

late L10n l10n;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('UpdatesSection', () {
    testWidgets('AC-1: toggling Beta-Updates switches the channel to beta', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsBetaUpdates);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdatesSection)),
      );
      expect(container.read(updateChannelProvider).value, UpdateChannel.beta);
    });

    testWidgets('toggling Beta-Updates off returns to stable', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
      await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdatesSection)),
      );
      expect(container.read(updateChannelProvider).value, UpdateChannel.stable);
    });

    testWidgets('toggling "check for updates" writes through to settings', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(); // checkUpdates defaults true
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => notifier),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsCheckUpdates);

      expect(notifier.state.value!.updates.checkUpdates, isFalse);
    });

    testWidgets('AC-4: section is hidden on the store deploy channel', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            deployChannelProvider.overrideWith((ref) => DeployChannel.store),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsBetaUpdates), findsNothing);
      expect(find.text(l10n.settingsCheckUpdates), findsNothing);
    });

    testWidgets('renders both controls on a non-store channel', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsCheckUpdates), findsOneWidget);
      expect(find.text(l10n.settingsBetaUpdates), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
    });
  });
}
