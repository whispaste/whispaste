/// WP-43a C-M-4: replacing the whole dictionary and importing a batch are each
/// one transaction. A failing row leaves the stored list exactly as it was,
/// never a half-written one.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.upsertReplacementWithTriggers(
      id: 'old',
      triggers: const ['alt'],
      replacement: 'Alt',
      createdAt: DateTime(2026),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> storedIds() async =>
      (await db.readAllReplacements()).map((r) => r.row.id).toList();

  test('replace-all with a failing row keeps the previous list', () async {
    await expectLater(
      db.writeReplacements([
        ReplacementWrite(
          id: 'a',
          triggers: const ['eins'],
          replacement: 'Eins',
          createdAt: DateTime(2026),
        ),
        // Empty trigger list: rejected while the batch is being written.
        ReplacementWrite(
          id: 'b',
          triggers: const [],
          replacement: 'leer',
          createdAt: DateTime(2026),
        ),
      ], replaceAll: true),
      throwsA(isA<AssertionError>()),
    );

    expect(await storedIds(), ['old']);
  });

  test('a batch import with a failing row adds nothing', () async {
    await expectLater(
      db.writeReplacements([
        ReplacementWrite(
          id: 'a',
          triggers: const ['eins'],
          replacement: 'Eins',
          createdAt: DateTime(2026),
        ),
        ReplacementWrite(
          id: 'b',
          triggers: const [],
          replacement: 'leer',
          createdAt: DateTime(2026),
        ),
      ]),
      throwsA(isA<AssertionError>()),
    );

    expect(await storedIds(), ['old']);
  });

  test('replace-all with valid rows swaps the whole list', () async {
    await db.writeReplacements([
      ReplacementWrite(
        id: 'new',
        triggers: const ['neu'],
        replacement: 'Neu',
        createdAt: DateTime(2026),
      ),
    ], replaceAll: true);

    expect(await storedIds(), ['new']);
  });
}
