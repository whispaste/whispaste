// UIA-HIS-15: Ctrl+E cannot open the transcript editor for a trashed entry.
// UIA-HIS-31: Esc in the transcript editor discards the edit; a changed text
// asks first. UIA-HIS-19: the shortcut help lists the recordings-list keys.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

const _content = 'original transcript text';

Finder _editor() => find.byWidgetPredicate(
  (w) => w is TextField && (w.controller?.text ?? '').startsWith(_content),
);

Future<(HistoryDatabase, HistoryEntry)> _seed() async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'edit-1',
      timestamp: DateTime(2026, 1, 1, 12),
      content: const Value(_content),
      title: const Value('Edit me'),
    ),
  );
  final entry = (await db.select(db.historyEntries).get()).single;
  return (db, entry);
}

Future<void> _pump(
  WidgetTester tester,
  HistoryDatabase db,
  HistoryEntry entry, {
  bool trash = false,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    makeTestable(
      Scaffold(
        body: HistoryDetailPanel(
          entry: entry,
          isTrashView: trash,
          onClose: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
          onArchive: () {},
          onRestore: () {},
        ),
      ),
      db: db,
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => _FakeSettingsNotifier())],
    ),
  );
  await tester.pumpAndSettle();
}

/// Gives the panel's own key handler the focus, as a click on it would.
void _focusPanel(WidgetTester tester) {
  final focus = tester.widget<Focus>(
    find
        .descendant(
          of: find.byType(CallbackShortcuts).first,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode != null && w.child is Column,
          ),
        )
        .first,
  );
  focus.focusNode!.requestFocus();
}

Future<void> _ctrlE(WidgetTester tester) async {
  _focusPanel(tester);
  await tester.pump();
  await tester.sendKeyDownEvent(primaryShortcutModifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
  await tester.sendKeyUpEvent(primaryShortcutModifier);
  await tester.pumpAndSettle();
}

/// Lets toasts and timers finish, then tears the tree down.
Future<void> _end(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'Ctrl+E does not open the editor for a trashed entry (UIA-HIS-15)',
    (tester) async {
      final (db, entry) = await _seed();
      addTearDown(db.close);
      await _pump(tester, db, entry, trash: true);

      await _ctrlE(tester);

      expect(_editor(), findsNothing);
      await _end(tester);
    },
  );

  testWidgets(
    'Esc with an unchanged transcript closes the editor at once (UIA-HIS-31)',
    (tester) async {
      final (db, entry) = await _seed();
      addTearDown(db.close);
      await _pump(tester, db, entry);

      await _ctrlE(tester);
      expect(_editor(), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_editor(), findsNothing);
      expect(find.text(l10n.unsavedInputTitle), findsNothing);
      await _end(tester);
    },
  );

  testWidgets(
    'Esc with changes asks first and discards on confirm (UIA-HIS-31)',
    (tester) async {
      final (db, entry) = await _seed();
      addTearDown(db.close);
      await _pump(tester, db, entry);

      await _ctrlE(tester);
      await tester.enterText(_editor(), '$_content, changed');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(l10n.unsavedInputTitle), findsOneWidget);

      // Cancel keeps the edit open.
      await tester.tap(find.text(l10n.actionCancel).last);
      await tester.pumpAndSettle();
      expect(_editor(), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.unsavedInputDiscard).last);
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);

      final stored = (await db.select(db.historyEntries).get()).single;
      expect(stored.content, _content);
      await _end(tester);
    },
  );

  testWidgets('the shortcut help lists the recordings-list keys (UIA-HIS-19)', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _pump(tester, db, entry);

    _focusPanel(tester);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyShortcutListGroup), findsOneWidget);
    expect(find.text(l10n.historyShortcutCopyEntry), findsOneWidget);
    expect(find.text(l10n.historyShortcutDiscardEdit), findsOneWidget);

    await _end(tester);
  });
}
