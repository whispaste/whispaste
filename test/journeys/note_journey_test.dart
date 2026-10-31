/// Journey 2 "Notiz": create a note, edit it (autosave into the database),
/// mark it as a favourite (marker and sort order), and find it via search.
///
/// Real `NotesPage`, real providers and a real in-memory Drift database
/// (`makeTestable(db: …)`). Nothing on this path needs a fake: STT, LLM, audio
/// and OS integration are not touched by notes. Every element is addressed by
/// its key, never by its localised label.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../fixtures/test_helpers.dart';

/// Tag streams are overridden, as in `notes_page_test.dart`: left alone, the
/// Drift tag watchers schedule timers that flutter_test reports as pending.
List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Finder get _newNoteButton => find.byKey(const ValueKey('notes-new-note'));
Finder get _searchField => find.byKey(const ValueKey('notes-search-field'));
Finder get _bodyField => find.descendant(
  of: find.byKey(const ValueKey('notes-editor-body')),
  matching: find.byType(EditableText),
);
Finder get _searchEditable =>
    find.descendant(of: _searchField, matching: find.byType(EditableText));
Finder _listTile(String noteId) => find.byKey(ValueKey(noteId));
Finder _tileFavouriteButton(String noteId) =>
    find.byKey(ValueKey('notes-favorite-$noteId'));

/// The filled (marked) star inside a favourite control.
Finder _solidStarIn(Finder favouriteButton) => find.descendant(
  of: favouriteButton,
  matching: find.byWidgetPredicate(
    (w) => w is FaIcon && w.icon == FontAwesomeIcons.solidStar.data,
  ),
);

/// Reads straight from the database. The widget tree is pumped with fake
/// time, but Drift I/O must run on the real event loop, hence `runAsync`.
Future<Note?> _dbNote(
  WidgetTester tester,
  HistoryDatabase db,
  String id,
) async {
  final note = await tester.runAsync(() async {
    final read = await db.getNote(id);
    // Yield once more so the write's stream re-emission is delivered too.
    await Future<void>.delayed(Duration.zero);
    return read;
  });
  await tester.pump();
  return note;
}

Future<List<Note>> _allActiveNotes(
  WidgetTester tester,
  HistoryDatabase db,
) async {
  // One-shot query, not `watchNotes().first`: cancelling a Drift stream from
  // inside the fake-async zone leaves a timer that flutter_test reports.
  final rows =
      await tester.runAsync(
        () => (db.select(db.notes)..where((n) => n.deletedAt.isNull())).get(),
      ) ??
      const <Note>[];
  return rows;
}

/// The note the list holds that is not [known] — the one a create just made.
Future<Note> _newestNote(
  WidgetTester tester,
  HistoryDatabase db, {
  required Set<String> known,
}) async {
  final notes = await _allActiveNotes(tester, db);
  return notes.firstWhere((n) => !known.contains(n.id));
}

/// Unmounts the page the way the production app does before a test ends.
/// Drift's stream cancellation on provider teardown schedules a zero-length
/// timer; the framework's pending-timer check needs it flushed in the test body,
/// not in a tearDown (which runs after that check).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

Future<void> _pumpNotesPage(WidgetTester tester, HistoryDatabase db) async {
  await tester.pumpWidget(
    makeTestable(
      const NotesPage(),
      db: db,
      size: const Size(1800, 900),
      overrides: _noTagOverrides,
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Vertical position of a tile; a smaller `dy` is higher in the list.
double _tileTop(WidgetTester tester, String noteId) =>
    tester.getTopLeft(_listTile(noteId)).dy;

void main() {
  group('Journey: Notiz', () {
    testWidgets(
      'create, edit with autosave, favourite, reorder and search the note',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await _pumpNotesPage(tester, db);

        // 1. Create the first note. It starts empty and the body has focus.
        await tester.tap(_newNoteButton);
        await tester.pumpAndSettle();
        final first = await _newestNote(tester, db, known: const {});
        expect(first.content, isEmpty);
        expect(_listTile(first.id), findsOneWidget);

        // 2. Edit it. Nothing is persisted before the 400 ms debounce ends.
        await tester.enterText(_bodyField, 'Shopping list\nMilk, eggs');
        await tester.pump(const Duration(milliseconds: 300));
        expect((await _dbNote(tester, db, first.id))!.content, isEmpty);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          (await _dbNote(tester, db, first.id))!.content,
          'Shopping list\nMilk, eggs',
        );

        // 3. Create a second note. Leaving the first one flushes its content,
        //    which is non-blank, so the first note must survive.
        await tester.tap(_newNoteButton);
        await tester.pumpAndSettle();
        final second = await _newestNote(tester, db, known: {first.id});
        await tester.enterText(_bodyField, 'Project ideas');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect((await _dbNote(tester, db, first.id))!.content, isNotEmpty);
        expect(
          (await _dbNote(tester, db, second.id))!.content,
          'Project ideas',
        );
        // Most recently updated first while nothing is favourited.
        expect(
          _tileTop(tester, second.id),
          lessThan(_tileTop(tester, first.id)),
        );

        // 4. Re-open the first note and edit it again.
        await tester.tap(_listTile(first.id));
        await tester.pumpAndSettle();
        await tester.enterText(_bodyField, 'Shopping list\nMilk, eggs, bread');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(
          (await _dbNote(tester, db, first.id))!.content,
          'Shopping list\nMilk, eggs, bread',
        );

        // 5. Mark the first note as a favourite: filled star, moved to top.
        expect(_solidStarIn(_tileFavouriteButton(first.id)), findsNothing);
        await tester.tap(_tileFavouriteButton(first.id));
        await tester.pumpAndSettle();
        expect((await _dbNote(tester, db, first.id))!.pinned, isTrue);
        expect(_solidStarIn(_tileFavouriteButton(first.id)), findsOneWidget);
        expect(
          _tileTop(tester, first.id),
          lessThan(_tileTop(tester, second.id)),
        );

        // 6. Search is case-insensitive and matches note content.
        await tester.enterText(_searchEditable, 'BREAD');
        await tester.pumpAndSettle();
        expect(_listTile(first.id), findsOneWidget);
        expect(_listTile(second.id), findsNothing);

        // A query nothing matches shows the no-results state.
        await tester.enterText(_searchEditable, 'no such words here');
        await tester.pumpAndSettle();
        expect(_listTile(first.id), findsNothing);
        expect(_listTile(second.id), findsNothing);
        expect(
          find.byKey(const ValueKey('notes-search-empty')),
          findsOneWidget,
        );

        // Clearing the query brings the whole list back.
        await tester.enterText(_searchEditable, '');
        await tester.pumpAndSettle();
        expect(_listTile(first.id), findsOneWidget);
        expect(_listTile(second.id), findsOneWidget);
        expect(find.byKey(const ValueKey('notes-search-empty')), findsNothing);
        await _unmount(tester);
      },
    );

    testWidgets('a blank note is discarded for good when the user leaves it', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await _pumpNotesPage(tester, db);

      await tester.tap(_newNoteButton);
      await tester.pumpAndSettle();
      final blank = await _newestNote(tester, db, known: const {});

      // Whitespace only counts as blank (trim rule).
      await tester.enterText(_bodyField, '   \n  \t ');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Creating another note leaves the blank one: it must be deleted
      // outright, not moved to the trash.
      await tester.tap(_newNoteButton);
      await tester.pumpAndSettle();

      expect(await _dbNote(tester, db, blank.id), isNull);
      expect(_listTile(blank.id), findsNothing);
      final remaining = await _allActiveNotes(tester, db);
      expect(remaining, hasLength(1));
      expect(remaining.single.id, isNot(blank.id));
      await _unmount(tester);
    });

    testWidgets('a favourite can be removed again and the marker goes away', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await _pumpNotesPage(tester, db);

      await tester.tap(_newNoteButton);
      await tester.pumpAndSettle();
      final note = await _newestNote(tester, db, known: const {});
      await tester.enterText(_bodyField, 'Keep me');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(_tileFavouriteButton(note.id));
      await tester.pumpAndSettle();
      expect((await _dbNote(tester, db, note.id))!.pinned, isTrue);
      expect(_solidStarIn(_tileFavouriteButton(note.id)), findsOneWidget);

      await tester.tap(_tileFavouriteButton(note.id));
      await tester.pumpAndSettle();
      expect((await _dbNote(tester, db, note.id))!.pinned, isFalse);
      expect(_solidStarIn(_tileFavouriteButton(note.id)), findsNothing);
      await _unmount(tester);
    });

    testWidgets('favouriting straight after typing keeps the unsaved draft', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await _pumpNotesPage(tester, db);

      await tester.tap(_newNoteButton);
      await tester.pumpAndSettle();
      final note = await _newestNote(tester, db, known: const {});

      // No debounce wait: the favourite action has to flush the draft
      // first, or the stream re-emitting the stale row overwrites it.
      await tester.enterText(_bodyField, 'Unsaved draft');
      await tester.pump();
      await tester.tap(_tileFavouriteButton(note.id));
      await tester.pumpAndSettle();

      final saved = await _dbNote(tester, db, note.id);
      expect(saved!.content, 'Unsaved draft');
      expect(saved.pinned, isTrue);
      await _unmount(tester);
    });

    testWidgets('a search that matches nothing shows the empty result state', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await _pumpNotesPage(tester, db);

      await tester.tap(_newNoteButton);
      await tester.pumpAndSettle();
      final note = await _newestNote(tester, db, known: const {});
      await tester.enterText(_bodyField, 'Only this');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.enterText(_searchEditable, 'absent');
      await tester.pumpAndSettle();
      expect(_listTile(note.id), findsNothing);
      expect(find.byKey(const ValueKey('notes-search-empty')), findsOneWidget);
      await _unmount(tester);
    });
  });
}
