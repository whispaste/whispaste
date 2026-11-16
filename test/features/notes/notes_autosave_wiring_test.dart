/// Pins the autosave flush triggers wired into `NotesPage` beyond note
/// switch/dispose: editor blur and `_deleteForever` (code-review fix,
/// closing a gap against the four triggers documented on
/// `NoteAutosave.schedule`).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/notes_search_bar.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

List<Object> get _noTagOverrides => [
  // The metadata index would start isolates; these tests are not about it.
  contentMetadataProvider.overrideWith((ref, key) => Stream.value(null)),
  contentMetadataPreviewProvider.overrideWith((ref, text) async => null),
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Note _note({required String id, required String content, DateTime? deletedAt}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    isQuickNote: false,
    deletedAt: deletedAt,
    createdAt: t,
    updatedAt: t,
  );
}

/// The note body. The panel's title field comes first in the tree now, so
/// `.first` on the panel's fields would type into the title instead.
Finder _editorTextFields() => find.descendant(
  of: find.byKey(const ValueKey('notes-editor-body')),
  matching: find.byType(TextField),
);

Finder _searchTextField() => find.descendant(
  of: find.byType(NotesSearchBar),
  matching: find.byType(TextField),
);

/// Records `save()` calls instead of hitting the DB.
class _RecordingSaveActions extends NotesActions {
  _RecordingSaveActions(super.db);

  final List<(String, String)> saveCalls = [];

  @override
  Future<void> save(String noteId, String content) async {
    saveCalls.add((noteId, content));
  }
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'editor blur flushes the pending autosave without waiting for the debounce',
    (tester) async {
      final notes = [_note(id: 'n1', content: 'Hello')];
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingSaveActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hello'));
      await tester.pumpAndSettle();

      await tester.tap(_editorTextFields().first);
      await tester.pump();
      await tester.enterText(_editorTextFields().first, 'Hello world');
      // No pump past the quiet pause — only blur should flush this.
      await tester.pump();
      expect(actions.saveCalls, isEmpty);

      await tester.tap(_searchTextField());
      await tester.pump();

      expect(actions.saveCalls, contains(('n1', 'Hello world')));
    },
  );

  testWidgets('Cmd/Ctrl+S saves the note at once and the status says saved', (
    tester,
  ) async {
    final notes = [_note(id: 'n1', content: 'Hello')];
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final actions = _RecordingSaveActions(db);
    addTearDown(db.close);

    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        size: const Size(1800, 900),
        overrides: [
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          notesActionsProvider.overrideWith((ref) => actions),
          ..._noTagOverrides,
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    await tester.tap(_editorTextFields().first);
    await tester.pump();
    await tester.enterText(_editorTextFields().first, 'Hello world');
    await tester.pump();
    expect(actions.saveCalls, isEmpty);
    expect(
      find.byKey(const ValueKey('notes-editor-save-status-saving')),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(primaryShortcutModifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(primaryShortcutModifier);
    // Shorter than the quiet pause: only the shortcut can have written.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(actions.saveCalls, contains(('n1', 'Hello world')));
    expect(
      find.byKey(const ValueKey('notes-editor-save-status-saved')),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('delete-forever flushes the pending autosave before deleting', (
    tester,
  ) async {
    final notes = [
      _note(id: 'n1', content: 'Hello', deletedAt: DateTime(2025, 6, 2)),
    ];
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final actions = _RecordingSaveActions(db);
    addTearDown(db.close);

    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        size: const Size(1800, 900),
        overrides: [
          trashNotesProvider.overrideWith((ref) => Stream.value(notes)),
          notesProvider.overrideWith((ref) => Stream.value(const [])),
          notesActionsProvider.overrideWith((ref) => actions),
          ..._noTagOverrides,
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to the trash filter, then open the trashed note.
    // The view filter lives in the toolbar's filter menu.
    await tester.tap(find.bySemanticsIdentifier('notes-filter-menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('notes-filter-trash'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    await tester.enterText(_editorTextFields().first, 'Hello salvaged');
    // No pump past the debounce — deleteForever's own flush must fire it.
    await tester.pump();
    expect(actions.saveCalls, isEmpty);

    await tester.tap(find.byIcon(LucideIcons.trash2).last);
    await tester.pump();

    expect(actions.saveCalls, contains(('n1', 'Hello salvaged')));
  });
}
