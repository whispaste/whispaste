/// Notes trash retention (#275): trashed notes follow the same period and the
/// same setting as the recordings trash (`historyAutoTrashDays`, 0 = never).
/// Notes trashed before the rule existed were promised to stay, so nothing
/// disappears before one full period after the first purge run. A simulated
/// clock drives every case.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';

void main() {
  late HistoryDatabase db;
  late NotesActions actions;
  final t0 = DateTime(2026, 11, 2, 12);

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    actions = NotesActions(db);
  });

  tearDown(() => db.close());

  Future<String> trashedNote(String content, DateTime deletedAt) async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, content);
    await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
      NotesCompanion(deletedAt: Value(deletedAt)),
    );
    return note.id;
  }

  Future<Set<String>> allIds() => db.allNoteIds();

  test('never (0 days) removes nothing and records no start date', () async {
    final id = await trashedNote('old', t0.subtract(const Duration(days: 999)));

    expect(await actions.purgeExpiredTrash(days: 0, now: t0), 0);
    expect(await allIds(), {id});
    expect(await db.readAppMeta(NotesActions.trashRetentionSinceKey), isNull);
  });

  test('a note trashed before the first run is kept for a full period '
      'after that run, then removed', () async {
    final legacy = await trashedNote(
      'legacy',
      t0.subtract(const Duration(days: 400)),
    );

    // First run: only records the start, deletes nothing.
    expect(await actions.purgeExpiredTrash(days: 90, now: t0), 0);
    expect(await allIds(), {legacy});

    final almost = t0.add(const Duration(days: 89));
    expect(await actions.purgeExpiredTrash(days: 90, now: almost), 0);
    expect(await allIds(), {legacy});

    final due = t0.add(const Duration(days: 91));
    expect(await actions.purgeExpiredTrash(days: 90, now: due), 1);
    expect(await allIds(), isEmpty);
  });

  test('a note trashed after the start follows its own deletion date, '
      'and active notes are never touched', () async {
    final active = (await db.createNote()).id;
    await db.updateNoteContent(active, 'keep me');
    await actions.purgeExpiredTrash(days: 30, now: t0); // sets the start

    final trashedAt = t0.add(const Duration(days: 5));
    final fresh = await trashedNote('fresh', trashedAt);

    // 29 days after trashing: still there.
    expect(
      await actions.purgeExpiredTrash(
        days: 30,
        now: trashedAt.add(const Duration(days: 29)),
      ),
      0,
    );
    // 31 days after trashing: gone; the active note stays.
    expect(
      await actions.purgeExpiredTrash(
        days: 30,
        now: trashedAt.add(const Duration(days: 31)),
      ),
      1,
    );
    expect(await allIds(), {active});
    expect(fresh, isNot(active));
  });

  test('restoring a trashed note takes it out of the purge', () async {
    await actions.purgeExpiredTrash(days: 30, now: t0);
    final id = await trashedNote('back', t0.add(const Duration(days: 1)));
    await actions.restore(id);

    expect(
      await actions.purgeExpiredTrash(
        days: 30,
        now: t0.add(const Duration(days: 400)),
      ),
      0,
    );
    expect(await allIds(), {id});
  });
}
