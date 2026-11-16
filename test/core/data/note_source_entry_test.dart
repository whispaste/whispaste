import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

/// Note <-> recording back link (issue #629): created by "Als Notiz
/// übernehmen", followed from both sides, quiet when either side is gone.
void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> addEntry(String id) => db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(id: id, timestamp: DateTime(2026, 11, 1)),
  );

  test('a note taken from a recording points at it, both ways', () async {
    await addEntry('e1');
    final note = await db.createNoteFromEntry('e1', 'hello');

    expect(note.sourceEntryId, 'e1');
    expect(note.content, 'hello');
    expect((await db.watchNoteTakenFromEntry('e1').first)?.id, note.id);
    expect((await db.watchLiveEntry('e1').first)?.id, 'e1');
  });

  test('an ordinary note has no source', () async {
    final note = await db.createNote();
    expect(note.sourceEntryId, isNull);
    expect(await db.watchNoteTakenFromEntry('e1').first, isNull);
  });

  test('a trashed note drops its mark on the recording', () async {
    await addEntry('e1');
    final note = await db.createNoteFromEntry('e1', 'x');
    await db.softDeleteNote(note.id);

    expect(await db.watchNoteTakenFromEntry('e1').first, isNull);
  });

  test('a trashed or deleted recording drops its link on the note', () async {
    await addEntry('e1');
    final note = await db.createNoteFromEntry('e1', 'x');

    await db.softDeleteEntry('e1');
    expect(await db.watchLiveEntry('e1').first, isNull);
    expect((await db.getNote(note.id))?.sourceEntryId, 'e1');

    await db.permanentDeleteEntry('e1');
    expect(await db.watchLiveEntry('e1').first, isNull);
    // The note itself is untouched.
    expect((await db.getNote(note.id))?.content, 'x');
  });

  test('taking the same recording twice follows the newest note', () async {
    await addEntry('e1');
    await db.createNoteFromEntry('e1', 'first');
    final second = await db.createNoteFromEntry('e1', 'second');

    expect((await db.watchNoteTakenFromEntry('e1').first)?.id, second.id);
  });

  test('v34 -> v35 adds the column and keeps notes, idempotent', () async {
    final tmp = await Directory.systemTemp.createTemp('wp629_mig_');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File(p.join(tmp.path, 'history.db'));

    final seed = HistoryDatabase.forTesting(NativeDatabase(file));
    final kept = await seed.createNote();
    await seed.updateNoteContent(kept.id, 'keep me');
    await seed.customStatement('ALTER TABLE notes DROP COLUMN source_entry_id');
    await seed.customStatement('PRAGMA user_version = 34');
    await seed.close();

    for (var i = 0; i < 2; i++) {
      final upgraded = HistoryDatabase.forTesting(NativeDatabase(file));
      final note = await upgraded.getNote(kept.id);
      expect(note?.content, 'keep me');
      expect(note?.sourceEntryId, isNull);
      await upgraded.close();
    }
  });
}
