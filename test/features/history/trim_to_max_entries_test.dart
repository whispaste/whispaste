import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

Future<Set<String>> _activeIds(HistoryDatabase db) async {
  final rows = await (db.select(
    db.historyEntries,
  )..where((e) => e.deletedAt.isNull())).get();
  return {for (final r in rows) r.id};
}

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insert(String id, int second, {bool pinned = false}) {
    return db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: id,
        timestamp: DateTime(2026, 1, 1).add(Duration(seconds: second)),
        pinned: Value(pinned),
      ),
    );
  }

  group('trimToMaxEntries', () {
    test('moves only the oldest active entries beyond max to trash', () async {
      for (var i = 1; i <= 5; i++) {
        await insert('e$i', i);
      }

      final trashed = await db.trimToMaxEntries(3);

      expect(trashed, 2);
      expect(await _activeIds(db), {'e3', 'e4', 'e5'});
    });

    test('pinned entries are neither counted nor trashed', () async {
      await insert('pinned-oldest', 0, pinned: true);
      for (var i = 1; i <= 3; i++) {
        await insert('e$i', i);
      }

      final trashed = await db.trimToMaxEntries(2);

      expect(trashed, 1);
      expect(await _activeIds(db), {'pinned-oldest', 'e2', 'e3'});
    });

    test('equal timestamps keep the entry with the higher id', () async {
      for (final id in ['a', 'b', 'c']) {
        await insert(id, 0);
      }

      await db.trimToMaxEntries(2);

      expect(await _activeIds(db), {'b', 'c'});
    });

    test('nothing to trim returns zero and leaves entries alone', () async {
      await insert('e1', 1);
      await insert('e2', 2);

      expect(await db.trimToMaxEntries(2), 0);
      expect(await db.trimToMaxEntries(10), 0);
      expect(await _activeIds(db), {'e1', 'e2'});
    });

    test('max of zero is a no-op (unlimited history)', () async {
      await insert('e1', 1);
      await insert('e2', 2);

      expect(await db.trimToMaxEntries(0), 0);
      expect(await _activeIds(db), {'e1', 'e2'});
    });
  });
}
