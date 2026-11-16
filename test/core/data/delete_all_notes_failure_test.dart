/// `HistoryDatabase.deleteAllNotes` is all or nothing (#459): when removing the
/// notes fails, everything that hangs off them stays as it was, including the
/// snippets' link to their source note.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a failing delete keeps versions, tags and the snippet link', () async {
    final note = await db.createNote();
    await db.recordNoteVersionIfChanged(note.id, title: null, content: 'a');
    final tag = await db.createTag('work');
    await db.tagNote(note.id, tag.id);
    await db.upsertSnippet(
      id: 's1',
      title: 'T',
      body: 'b',
      createdAt: DateTime(2026, 11, 4),
      sourceNoteId: note.id,
    );
    await db.customStatement('''
      CREATE TRIGGER block_note_delete BEFORE DELETE ON notes
      BEGIN SELECT RAISE(ABORT, 'blocked'); END
    ''');

    await expectLater(db.deleteAllNotes(), throwsA(isA<SqliteException>()));

    expect(await db.noteVersionsFor(note.id), isNotEmpty);
    expect(await db.select(db.noteTags).get(), isNotEmpty);
    expect(await db.getNote(note.id), isNotNull);
    expect((await db.readSnippetWithFields('s1'))!.row.sourceNoteId, note.id);

    await db.customStatement('DROP TRIGGER block_note_delete');
    await db.deleteAllNotes();
    expect(await db.getNote(note.id), isNull);
    expect((await db.readSnippetWithFields('s1'))!.row.sourceNoteId, isNull);
  });
}
