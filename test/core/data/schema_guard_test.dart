/// Schema guard (DEV-295): the declared schema version is the top step of the
/// migration ladder, and a file written by a newer build is refused instead of
/// being opened and stamped down to this build's version.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:whispaste/core/data/database.dart';

void main() {
  test('schemaVersion equals the highest "from < N" migration step', () {
    final source = File('lib/core/data/database.dart').readAsStringSync();
    final steps = RegExp(
      r'from < (\d+)',
    ).allMatches(source).map((m) => int.parse(m.group(1)!)).toList();
    expect(steps, isNotEmpty);
    final highest = steps.reduce((a, b) => a > b ? a : b);

    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, highest);
  });

  test(
    'a file from a newer build is refused and keeps its version and data',
    () async {
      final dir = Directory.systemTemp.createTempSync('wp_schema_guard_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/history.sqlite';

      final current = HistoryDatabase.forTesting(NativeDatabase(File(path)));
      await current.customSelect('SELECT 1').get();
      final supported = current.schemaVersion;
      await current.close();

      final raw = sqlite.sqlite3.open(path);
      raw.execute('CREATE TABLE guard_probe (v TEXT);');
      raw.execute("INSERT INTO guard_probe (v) VALUES ('keep');");
      raw.execute('PRAGMA user_version = ${supported + 1};');
      raw.close();

      final newer = HistoryDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(newer.close);
      await expectLater(
        newer.customSelect('SELECT 1').get(),
        throwsA(
          isA<DatabaseTooNewException>()
              .having((e) => e.storedVersion, 'storedVersion', supported + 1)
              .having((e) => e.supportedVersion, 'supportedVersion', supported),
        ),
      );

      final check = sqlite.sqlite3.open(path);
      addTearDown(check.close);
      expect(
        check.select('PRAGMA user_version').single.values.first,
        supported + 1,
      );
      expect(
        check.select('SELECT v FROM guard_probe').map((r) => r['v']).toList(),
        ['keep'],
      );
    },
  );
}
