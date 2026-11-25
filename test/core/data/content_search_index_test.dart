import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/index_maintenance.dart';

/// #628: notes and snippets get full-text indexes like recordings. The
/// triggers keep them current, an update adds them silently, and the start
/// heal and the manual rebuild cover them like `history_fts`.
void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_content_index_');
    file = File('${dir.path}/history.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryDatabase open() => HistoryDatabase.forTesting(NativeDatabase(file));

  Future<Set<String>> notesFound(HistoryDatabase db, String q) async =>
      (await db.searchNotesContent(
        ContentSearchSpec(freeText: q),
        limit: 50,
      )).map((n) => n.id).toSet();

  Future<Set<String>> snippetsFound(HistoryDatabase db, String q) async =>
      (await db.searchSnippetsContent(
        ContentSearchSpec(freeText: q),
        limit: 50,
      )).map((s) => s.id).toSet();

  Future<String> note(HistoryDatabase db, String text) async {
    final n = await db.createNote();
    await db.updateNoteContent(n.id, text);
    return n.id;
  }

  Future<void> snippet(HistoryDatabase db, String id, String title, String b) =>
      db.upsertSnippet(
        id: id,
        title: title,
        body: b,
        createdAt: DateTime(2026, 1, 1),
      );

  test('a new, an edited and a deleted note or snippet', () async {
    final db = open();
    addTearDown(db.close);
    final a = await note(db, 'Quarterly budget review');
    await snippet(db, 's1', 'Signature', 'Kind regards, Alex');

    expect(await notesFound(db, 'budg'), {a});
    expect(await snippetsFound(db, 'regard'), {'s1'});
    expect(await snippetsFound(db, 'signat'), {'s1'});

    await db.updateNoteContent(a, 'Travel plans');
    expect(await notesFound(db, 'budget'), isEmpty);
    expect(await notesFound(db, 'travel'), {a});
    await db.setNoteTitle(a, 'Holiday');
    expect(await notesFound(db, 'holi'), {a});

    // A pin is no text change: the index stays as it is and still matches.
    await db.toggleNotePin(a, pinned: true);
    expect(await notesFound(db, 'travel'), {a});

    await snippet(db, 's1', 'Signature', 'Best wishes');
    expect(await snippetsFound(db, 'regard'), isEmpty);
    expect(await snippetsFound(db, 'wishes'), {'s1'});

    // The trash keeps the row but the search never reaches into it.
    await db.softDeleteNote(a);
    await db.trashSnippets(['s1']);
    expect(await notesFound(db, 'travel'), isEmpty);
    expect(await snippetsFound(db, 'wishes'), isEmpty);
  });

  test('a database from before #628 gets the indexes silently', () async {
    final first = open();
    final a = await note(first, 'alpha note');
    await snippet(first, 's1', 'alpha snippet', 'body');
    await first.customStatement('DROP TRIGGER notes_fts_ai');
    await first.customStatement('DROP TRIGGER notes_fts_ad');
    await first.customStatement('DROP TRIGGER notes_fts_au');
    await first.customStatement('DROP TABLE notes_fts');
    await first.customStatement('DROP TRIGGER snippets_fts_ai');
    await first.customStatement('DROP TRIGGER snippets_fts_ad');
    await first.customStatement('DROP TRIGGER snippets_fts_au');
    await first.customStatement('DROP TABLE snippets_fts');
    await first.customStatement('DELETE FROM app_meta WHERE key IN (?, ?)', [
      kNotesSearchIndex.versionKey,
      kSnippetsSearchIndex.versionKey,
    ]);
    await first.close();

    final db = open();
    addTearDown(db.close);
    expect(await notesFound(db, 'alpha'), {a});
    expect(await snippetsFound(db, 'alpha'), {'s1'});
    expect(db.indexesRepairedOnOpen, isFalse);
  });

  for (final (name, breakIt) in <(String, String)>[
    ('missing notes index', 'DROP TABLE notes_fts'),
    ('missing snippets trigger', 'DROP TRIGGER snippets_fts_au'),
    (
      'orphaned note document',
      "INSERT INTO notes_fts(rowid, title, content) VALUES (9999, '', 'x')",
    ),
  ]) {
    test('$name is rebuilt on open and reported', () async {
      final first = open();
      final a = await note(first, 'alpha note');
      await snippet(first, 's1', 'alpha snippet', 'body');
      await first.customStatement(breakIt);
      await first.close();

      final db = open();
      addTearDown(db.close);
      expect(await notesFound(db, 'alpha'), {a});
      expect(await snippetsFound(db, 'alpha'), {'s1'});
      expect(db.indexesRepairedOnOpen, isTrue);
    });
  }

  test('a broken notes index leaves the recordings index alone', () async {
    final first = open();
    await first.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: 'e1',
        timestamp: DateTime(2026, 1, 1),
        content: const Value('alpha'),
      ),
    );
    await note(first, 'alpha note');
    // A marker row only the recordings index holds: a rebuild would drop it.
    await first.customStatement(
      'INSERT INTO history_fts(history_fts, rowid, title, content, tags) '
      "SELECT 'delete', rowid, title, content, tags FROM history_entries",
    );
    await first.customStatement(
      'INSERT INTO history_fts(rowid, title, content, tags) '
      "SELECT rowid, title, 'marker', tags FROM history_entries",
    );
    await first.customStatement('DROP TABLE notes_fts');
    await first.close();

    final db = open();
    addTearDown(db.close);
    expect((await db.searchEntries('marker')).map((e) => e.id), ['e1']);
  });

  test('the manual rebuild refills every index and counts all rows', () async {
    final db = open();
    addTearDown(db.close);
    await db.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: 'e1',
        timestamp: DateTime(2026, 1, 1),
        content: const Value('alpha'),
      ),
    );
    final a = await note(db, 'alpha note');
    await snippet(db, 's1', 'alpha', 'body');

    final steps = await db.rebuildIndexes().toList();
    final search = steps.where((p) => p.phase == IndexRebuildPhase.search);
    expect(
      search.last,
      const IndexRebuildProgress(IndexRebuildPhase.search, 3, 3),
    );
    expect(await notesFound(db, 'alpha'), {a});
    expect(await snippetsFound(db, 'alpha'), {'s1'});

    // The triggers are back: a later edit still reaches the index.
    await db.updateNoteContent(a, 'beta');
    expect(await notesFound(db, 'beta'), {a});
  });

  test('a failure in the notes index counts as index damage', () {
    expect(
      isSearchIndexFailure(
        SqliteException(
          extendedResultCode: 1,
          message: 'no such table: notes_fts',
        ),
      ),
      isTrue,
    );
  });
}
