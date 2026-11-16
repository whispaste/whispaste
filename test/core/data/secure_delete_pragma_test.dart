import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

void main() {
  group('secure_delete (GS-017)', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_secdel_');
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    Future<int> secureDelete(NativeDatabase executor) async {
      final db = HistoryDatabase.forTesting(executor);
      addTearDown(db.close);
      final rows = await db.customSelect('PRAGMA secure_delete').get();
      return rows.single.data.values.single as int;
    }

    test(
      'the connection setup enables secure_delete on a file database',
      () async {
        final file = File(p.join(tmpDir.path, 'history.db'));
        expect(
          await secureDelete(
            NativeDatabase(file, setup: configureHistoryConnection),
          ),
          1,
        );
      },
    );

    test(
      'negative control: a plain connection without the setup does not',
      () async {
        final file = File(p.join(tmpDir.path, 'plain.db'));
        expect(await secureDelete(NativeDatabase(file)), isNot(1));
      },
    );

    test('the setup applies before the first migration runs', () async {
      final file = File(p.join(tmpDir.path, 'fresh.db'));
      final db = HistoryDatabase.forTesting(
        NativeDatabase(file, setup: configureHistoryConnection),
      );
      addTearDown(db.close);
      // Opening runs the migrations; the setup must already have set the pragma.
      final rows = await db.customSelect('PRAGMA secure_delete').get();
      expect(rows.single.data.values.single, 1);
    });
  });
}
