import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

/// Inserts one row into [table], giving a value to every column the insert
/// needs. Columns with a default and nullable columns are left to the database.
Future<void> _seedRow(HistoryDatabase db, TableInfo table) async {
  final name = table.actualTableName;
  final info = await db.customSelect('PRAGMA table_info("$name")').get();
  final columns = <String>[];
  final values = <Object?>[];
  for (final col in info) {
    final notNull = col.read<int>('notnull') == 1;
    final hasDefault = col.data['dflt_value'] != null;
    final isKey = col.read<int>('pk') > 0;
    if (!notNull || (hasDefault && !isKey)) continue;
    final type = col.read<String>('type').toUpperCase();
    columns.add('"${col.read<String>('name')}"');
    values.add(type.contains('INT') ? 0 : 'seed-$name');
  }
  if (columns.isEmpty) {
    await db.customStatement('INSERT INTO "$name" DEFAULT VALUES');
  } else {
    final marks = List.filled(columns.length, '?').join(', ');
    await db.customStatement(
      'INSERT INTO "$name" (${columns.join(', ')}) VALUES ($marks)',
      values,
    );
  }
}

Future<int> _count(HistoryDatabase db, String name) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM "$name"')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  test('the factory reset empties every table of the database', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Guard: a table added to the database is seeded and must be cleared too.
    for (final table in db.allTables) {
      await _seedRow(db, table);
    }
    await db.writeAppSettings({'history_hide_on_open': 'true'});
    for (final table in db.allTables) {
      expect(
        await _count(db, table.actualTableName),
        greaterThan(0),
        reason: '${table.actualTableName} was not seeded',
      );
    }

    await db.deleteAllData();

    for (final table in db.allTables) {
      expect(
        await _count(db, table.actualTableName),
        0,
        reason: '${table.actualTableName} survives the factory reset',
      );
    }
    expect(await _count(db, 'app_settings'), 0);
  });
}
