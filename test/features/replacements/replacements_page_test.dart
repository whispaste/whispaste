/// Tests for [ReplacementsPage] (Voice Shortcuts).
///
/// Covers: sample data on empty DB, Add dialog, dialog validation,
/// Edit pre-fill, search filter, no-results state, enable/disable toggle,
/// hover → delete confirmation.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake settings notifier — captures updateSettings calls without touching
// SQLite (the real notifier reads/writes the DB).
// ---------------------------------------------------------------------------

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

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('ReplacementsPage', () {
    // -------------------------------------------------------------------------
    // 1. Sample data
    // -------------------------------------------------------------------------

    testWidgets('renders sample entries on first load (empty DB)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // ReplacementsNotifier auto-inserts three sample shortcuts when DB is empty
      expect(find.textContaining('"mfg"'), findsOneWidget);
      expect(find.textContaining('"lg"'), findsOneWidget);
      expect(find.textContaining('"tel"'), findsOneWidget);

      // Arrow icon present once per row
      expect(find.byIcon(LucideIcons.arrowRightLeft), findsNWidgets(3));
    });

    // -------------------------------------------------------------------------
    // 2. Add dialog
    // -------------------------------------------------------------------------

    testWidgets('Add button opens dialog with correct labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap the toolbar Add button (contains the plus icon)
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // Dialog title
      expect(find.text(l10n.replacementsNewShortcut), findsOneWidget);
      // Field labels
      expect(find.text(l10n.replacementsTriggerLabel), findsOneWidget);
      expect(find.text(l10n.replacementsReplacementLabel), findsOneWidget);
      // Hint text in dialog body
      expect(find.text(l10n.replacementsDialogHint), findsOneWidget);
    });

    testWidgets('save button is disabled while both fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // When _isValid == false the dialog's ElevatedButton has onPressed == null.
      // The toolbar Add button (ElevatedButton.icon) always has onPressed set,
      // so we can distinguish them.
      final buttons = tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(
        buttons.any((b) => b.onPressed == null),
        isTrue,
        reason: 'Dialog save button should be disabled with empty fields',
      );
    });

    // -------------------------------------------------------------------------
    // 3. Edit (click tile)
    // -------------------------------------------------------------------------

    testWidgets('tapping a tile opens edit dialog with pre-filled trigger', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap the mfg tile
      await tester.tap(find.textContaining('"mfg"'));
      await tester.pumpAndSettle();

      // Edit dialog title
      expect(find.text(l10n.replacementsEditShortcut), findsOneWidget);
      // Pre-filled trigger value visible inside the dialog text field
      expect(find.text('mfg'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // 4. Search filter
    // -------------------------------------------------------------------------

    testWidgets('search field filters visible replacements', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // All three visible initially
      expect(find.textContaining('"mfg"'), findsOneWidget);
      expect(find.textContaining('"lg"'), findsOneWidget);
      expect(find.textContaining('"tel"'), findsOneWidget);

      // Search for "mfg" — only the mfg row should remain
      await tester.enterText(find.byType(TextField).first, 'mfg');
      await tester.pumpAndSettle();

      expect(find.textContaining('"mfg"'), findsOneWidget);
      expect(find.textContaining('"lg"'), findsNothing);
      expect(find.textContaining('"tel"'), findsNothing);
    });

    testWidgets('search with no match shows no-results empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzzznonexistent');
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsNoMatches), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 5. Enable / disable toggle
    // -------------------------------------------------------------------------

    testWidgets('toggle switch updates textReplacementsEnabled in provider', (
      tester,
    ) async {
      // BehaviorSettings defaults textReplacementsEnabled = false.
      // Override with true so the switch starts ON, then verify toggling to OFF.
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWith(textReplacementsEnabled: true),
      );
      await tester.pumpWidget(
        makeTestable(
          const ReplacementsPage(),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Starts enabled — switch is ON and label says "disable"
      final switchOn = tester.widget<Switch>(find.byType(Switch));
      expect(switchOn.value, isTrue);
      expect(find.text(l10n.replacementsDisableAction), findsOneWidget);

      // Tap toggle to disable
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        notifier.state.value?.behavior.textReplacementsEnabled,
        isFalse,
        reason: 'Provider should reflect the new disabled state',
      );
    });

    // -------------------------------------------------------------------------
    // 6. Delete via hover
    // -------------------------------------------------------------------------

    testWidgets('hover shows delete icon; tapping it opens confirm dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Simulate mouse hover over the "mfg" tile
      final mfgTile = find.textContaining('"mfg"');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(mfgTile));
      await tester.pumpAndSettle();

      // Delete icon should appear on hover
      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

      // Tap delete
      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pumpAndSettle();

      // Confirm dialog should appear with the correct title
      expect(find.text(l10n.replacementsDeleteTitle), findsOneWidget);
    });
  });
}
