// #1074: Aufnahmen and Notizen keep their working state across a page
// switch. The shell below disposes the page and builds it anew, as the app
// shell does, inside the same ProviderScope.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

/// Shows [page] or an empty "other page", like switching in the sidebar.
class _SwitchShell extends StatelessWidget {
  const _SwitchShell({required this.visible, required this.page});

  final ValueNotifier<bool> visible;
  final Widget page;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: visible,
    builder: (context, show, _) =>
        show ? page : const SizedBox(key: ValueKey('other-page')),
  );
}

Future<void> _switchAwayAndBack(
  WidgetTester tester,
  ValueNotifier<bool> visible,
) async {
  visible.value = false;
  await tester.pumpAndSettle();
  visible.value = true;
  await tester.pumpAndSettle();
}

/// The Aufnahmen list itself, whichever view is active.
Finder _historyList() => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w is ListView && w.key is PageStorageKey<String>,
      ),
      matching: find.byType(Scrollable),
    )
    .first;

HistoryEntry _entry(String id, DateTime ts) => HistoryEntry(
  id: id,
  content: 'Entry $id note',
  title: 'Entry $id note',
  timestamp: ts,
  durationSec: 10.0,
  processingDurationSec: 0.5,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

Note _note(String id, String content) {
  final t = DateTime(2025, 6, 1);
  return Note(
    archived: false,
    id: id,
    content: content,
    pinned: false,
    isQuickNote: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

/// Serves notes from memory instead of the database and never discards.
class _MemoryNotesActions extends NotesActions {
  _MemoryNotesActions(super.db, this.notes);

  final List<Note> notes;

  @override
  Future<Note?> getNote(String noteId) async =>
      notes.where((n) => n.id == noteId).firstOrNull;

  @override
  Future<bool> discardIfBlank(String noteId) async => false;
}

void main() {
  testWidgets('Aufnahmen keeps multi-selection, search and scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final l10n = await L10n.delegate.load(const Locale('en'));
    final entries = [
      for (var i = 0; i < 40; i++)
        _entry('e$i', DateTime(2026, 1, 1).subtract(Duration(hours: i))),
    ];
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      makeTestable(
        _SwitchShell(visible: visible, page: const HistoryPage()),
        locale: const Locale('en'),
        overrides: [
          pagedHistoryProvider.overrideWith((ref) => Stream.value(entries)),
          archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
          trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'note');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entry e0 note').first);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(primaryShortcutModifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(primaryShortcutModifier);
    await tester.pumpAndSettle();
    expect(find.text(l10n.historyItemsSelected(40)), findsOneWidget);

    final list = _historyList();
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(list).position.pixels;
    expect(offset, greaterThan(0));

    await _switchAwayAndBack(tester, visible);

    expect(find.text(l10n.historyItemsSelected(40)), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'note',
    );
    expect(
      tester.state<ScrollableState>(_historyList()).position.pixels,
      offset,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Notizen keeps the open note and the search', (tester) async {
    final notes = [_note('n1', 'First note'), _note('n2', 'Second note')];
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      makeTestable(
        _SwitchShell(visible: visible, page: const NotesPage()),
        size: const Size(1800, 900),
        locale: const Locale('en'),
        overrides: [
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          notesActionsProvider.overrideWith(
            (ref) => _MemoryNotesActions(db, notes),
          ),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('n2')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('notes-search-field'));
    await tester.enterText(search, 'note');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-editor-title')), findsOneWidget);

    await _switchAwayAndBack(tester, visible);

    expect(find.byKey(const ValueKey('notes-editor-title')), findsOneWidget);
    expect(find.textContaining('Second note'), findsWidgets);
    final field = tester.widget(search);
    final controller = field is TextField
        ? field.controller
        : tester
              .widget<TextField>(
                find.descendant(of: search, matching: find.byType(TextField)),
              )
              .controller;
    expect(controller?.text, 'note');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
