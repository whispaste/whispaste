/// Permanent note deletes are all or nothing (#267): when removing the note
/// fails, its version history stays as it was.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;
  late String noteId;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final note = await db.createNote();
    noteId = note.id;
    await db.recordNoteVersionIfChanged(noteId, title: null, content: 'a');
    await db.customStatement('''
      CREATE TRIGGER block_note_delete BEFORE DELETE ON notes
      BEGIN SELECT RAISE(ABORT, 'blocked'); END
    ''');
  });
  tearDown(() => db.close());

  Future<void> expectIntact() async {
    expect(await db.noteVersionsFor(noteId), isNotEmpty);
    expect(await db.getNote(noteId), isNotNull);
  }

  test('permanentDeleteNote keeps the history when the delete fails', () async {
    await expectLater(
      db.permanentDeleteNote(noteId),
      throwsA(isA<SqliteException>()),
    );
    await expectIntact();
  });

  test('discardNoteIfBlank keeps the history when the delete fails', () async {
    await expectLater(
      db.discardNoteIfBlank(noteId),
      throwsA(isA<SqliteException>()),
    );
    await expectIntact();
  });

  test('purgeEmptyNotes keeps the history when the delete fails', () async {
    await expectLater(db.purgeEmptyNotes(), throwsA(isA<SqliteException>()));
    await expectIntact();
  });
}
