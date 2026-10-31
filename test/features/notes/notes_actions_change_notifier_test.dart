/// [NotesActions] reports saved content to its change notifier (ticket / 8.3).
/// Creating an empty note does not count as a change.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('a save reports the note id and the new content once', () async {
    final changes = <(String, String)>[];
    final actions = NotesActions(
      db,
      onChanged: (noteId, content) => changes.add((noteId, content)),
    );
    final note = await actions.create();
    await actions.save(note.id, 'Milch');

    expect(changes, [(note.id, 'Milch')]);
  });

  test('create alone does not notify', () async {
    var calls = 0;
    final actions = NotesActions(db, onChanged: (_, _) => calls++);
    await actions.create();
    expect(calls, 0);
  });
}
