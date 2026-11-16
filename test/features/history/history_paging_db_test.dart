import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> page(int offset, int size) async =>
      (await db.watchEntries(limit: size, offset: offset).first)
          .map((e) => e.id)
          .toList();

  test('pages are ordered, gapless and duplicate-free incl. ties', () async {
    // 23 entries: 3 pinned, equal timestamps in pairs (tie-break by id).
    for (var i = 0; i < 23; i++) {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e${i.toString().padLeft(2, '0')}',
          timestamp: DateTime(2025, 1, 1).add(Duration(minutes: i ~/ 2)),
          pinned: Value(i % 8 == 0),
        ),
      );
    }
    final all = (await db.watchEntries().first).map((e) => e.id).toList();
    expect(all, hasLength(23));

    final paged = <String>[];
    for (var offset = 0; offset < 23; offset += 10) {
      final p = await page(offset, 10);
      expect(p.length, offset + 10 <= 23 ? 10 : 3); // last partial block
      paged.addAll(p);
    }
    expect(paged, all);
    expect(paged.toSet(), hasLength(23));
    expect(await page(30, 10), isEmpty);
    // Pinned first, then newest first.
    expect(all.take(3).toSet(), {'e00', 'e08', 'e16'});
    expect(all[3], 'e22');
  });

  test('a mutation inside the window updates it without gaps', () async {
    for (var i = 0; i < 6; i++) {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'm$i',
          timestamp: DateTime(2025, 1, 1, i),
        ),
      );
    }
    final first = db.watchEntries(limit: 4).skip(1).first;
    await db.softDeleteEntry('m5');
    expect((await first).map((e) => e.id), ['m4', 'm3', 'm2', 'm1']);
  });
}
