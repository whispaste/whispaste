/// UIA-HIS-06: taking back a bulk action reverses only the flag it set.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insert(String id, {required bool archived}) =>
      db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: Value(id),
          content: Value('text $id'),
          timestamp: Value(DateTime(2026, 11, 2)),
          archived: Value(archived),
        ),
      );

  Future<HistoryEntry> entry(String id) =>
      (db.select(db.historyEntries)..where((e) => e.id.equals(id))).getSingle();

  test('undo of a bulk delete keeps an archived entry archived', () async {
    await insert('a', archived: true);
    await insert('b', archived: false);
    await db.softDeleteEntries(['a', 'b']);

    await db.batchRestoreFromTrash(['a', 'b']);

    final a = await entry('a');
    expect(a.deletedAt, isNull);
    expect(a.archived, isTrue);
    expect((await entry('b')).deletedAt, isNull);
  });

  test('undo of a bulk archive clears only the archive flag', () async {
    await insert('a', archived: false);
    await db.batchArchive(['a']);
    expect((await entry('a')).archived, isTrue);

    await db.batchUnarchive(['a']);

    expect((await entry('a')).archived, isFalse);
  });
}
