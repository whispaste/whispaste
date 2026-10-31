/// Settings → Recordings: "Aufnahmen speichern" (history-off feature).
///
/// Switching it off offers to delete the recordings that already exist, in a
/// confirmation dialog (never a silent delete). A persistent row offers the
/// same deletion while the switch is off. Checked at 800 px with text scaling
/// 1.3 and in a right-to-left language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/history_section.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester, {
  required HistorySettings history,
  bool hasEntries = true,
  List<int>? deletions,
  Size size = const Size(800, 1000),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notifier = _FakeSettingsNotifier(AppSettings(history: history));
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SingleChildScrollView(child: HistorySection()),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(() => notifier),
        historyHasEntriesProvider.overrideWith((ref) async => hasEntries),
        historyDeleteAllEntriesProvider.overrideWithValue(() async {
          deletions?.add(1);
        }),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Finder _saveRow() =>
    find.byKey(const ValueKey('settings-row-privacy-history-save'));

Finder _deleteRow() =>
    find.byKey(const ValueKey('settings-row-privacy-history-delete-existing'));

Future<void> _tapSaveSwitch(WidgetTester tester) async {
  // The row's own switch: the first Switch below the save row's key.
  await tester.tap(
    find.descendant(of: _saveRow(), matching: find.byType(Switch)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Aufnahmen speichern switch', () {
    testWidgets('is on by default and has a test id', (tester) async {
      await _pump(tester, history: const HistorySettings());

      expect(_saveRow(), findsOneWidget);
      final toggle = tester.widget<Switch>(
        find.descendant(of: _saveRow(), matching: find.byType(Switch)),
      );
      expect(toggle.value, isTrue);
      expect(
        find.bySemanticsIdentifier('privacy-history-save-toggle'),
        findsOneWidget,
      );
    });

    testWidgets('switching off with existing recordings asks before deleting', (
      tester,
    ) async {
      final deletions = <int>[];
      final notifier = await _pump(
        tester,
        history: const HistorySettings(),
        deletions: deletions,
      );

      await _tapSaveSwitch(tester);

      expect(notifier.current.history.saveHistory, isFalse);
      // The offer is a dialog; nothing is deleted yet.
      expect(find.text(l10n.settingsHistorySaveDeleteTitle), findsOneWidget);
      expect(deletions, isEmpty);

      await tester.tap(find.text(l10n.settingsHistorySaveDeleteKeep));
      await tester.pumpAndSettle();
      expect(deletions, isEmpty, reason: 'keeping must not delete');
    });

    testWidgets('confirming the offer deletes the existing recordings', (
      tester,
    ) async {
      final deletions = <int>[];
      await _pump(
        tester,
        history: const HistorySettings(),
        deletions: deletions,
      );

      await _tapSaveSwitch(tester);
      await tester.tap(find.text(l10n.settingsHistoryDeleteConfirm));
      await tester.pumpAndSettle();

      expect(deletions, hasLength(1));
    });

    testWidgets('without existing recordings switching off asks nothing', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        history: const HistorySettings(),
        hasEntries: false,
      );

      await _tapSaveSwitch(tester);

      expect(notifier.current.history.saveHistory, isFalse);
      expect(find.text(l10n.settingsHistorySaveDeleteTitle), findsNothing);
    });

    testWidgets('the delete row appears only while saving is off', (
      tester,
    ) async {
      await _pump(tester, history: const HistorySettings());
      expect(_deleteRow(), findsNothing);

      // A fresh tree: the second pump's notifier would not replace the first.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, history: const HistorySettings(saveHistory: false));
      expect(_deleteRow(), findsOneWidget);
    });

    testWidgets('the delete row asks for confirmation before deleting', (
      tester,
    ) async {
      final deletions = <int>[];
      await _pump(
        tester,
        history: const HistorySettings(saveHistory: false),
        deletions: deletions,
      );

      await tester.tap(
        find.descendant(of: _deleteRow(), matching: find.byType(WpButton)),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsHistoryDeleteConfirm), findsOneWidget);
      expect(deletions, isEmpty);
    });
  });
}
