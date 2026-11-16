/// #1004: the rule order the user sets is the order `readAllReplacements`
/// returns (and the cascade applies), and it survives edits.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: ['t$id'],
        replacement: 'r$id',
        createdAt: DateTime(2026, 1, 1 + i),
      );
    }
  });

  tearDown(() => db.close());

  Future<List<String>> order() async => [
    for (final r in await db.readAllReplacements()) r.row.id,
  ];

  test('without a saved order the creation order applies', () async {
    expect(await order(), ['a', 'b', 'c']);
  });

  test('a saved order is read back and survives an edit', () async {
    await db.reorderReplacements(['c', 'a', 'b']);
    expect(await order(), ['c', 'a', 'b']);
    await db.upsertReplacementWithTriggers(
      id: 'a',
      triggers: ['ta2'],
      replacement: 'ra2',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(await order(), ['c', 'a', 'b']);
  });

  test('unlisted rules follow, unknown ids are ignored', () async {
    await db.reorderReplacements(['b', 'zzz']);
    expect(await order(), ['b', 'a', 'c']);
  });

  test('a rule added after sorting goes to the end', () async {
    await db.reorderReplacements(['c', 'b', 'a']);
    await db.upsertReplacementWithTriggers(
      id: 'd',
      triggers: ['td'],
      replacement: 'rd',
      createdAt: DateTime(2025, 1, 1),
    );
    expect(await order(), ['c', 'b', 'a', 'd']);
  });
}
