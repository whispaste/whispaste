/// Tests for [UpdatesSection] — the automatic update check toggle and
/// the store-channel rules.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/updates_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

import '../../../fixtures/test_helpers.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

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
    matching: find.byType(WpSettingsRow),
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    platformSupportsSparkle = () => false;
  });

  group('UpdatesSection', () {
    testWidgets('toggling "check for updates" writes through to settings', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(); // checkUpdates defaults true
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [UpdatesSection()],
            ),
          ),
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

    testWidgets('AC-4: store channel keeps the rows, disabled with the reason '
        '(ticket)', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [UpdatesSection()],
            ),
          ),
          overrides: [
            deployChannelProvider.overrideWith((ref) => DeployChannel.store),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsCheckUpdates), findsOneWidget);
      expect(find.text(l10n.settingsStoreUpdatesUnavailable), findsWidgets);

      final checkToggle = tester.widget<Switch>(
        find.byKey(const ValueKey('settings-updates-check-toggle')),
      );
      expect(checkToggle.onChanged, isNull);
      expect(
        find.byKey(const ValueKey('settings-updates-check-now')),
        findsNothing,
      );
    });

    testWidgets(
      'AC-4b: section is hidden on the packageManaged deploy channel',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [UpdatesSection()],
              ),
            ),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.packageManaged,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsCheckUpdates), findsNothing);
      },
    );
  });
}
