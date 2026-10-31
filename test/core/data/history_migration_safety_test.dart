import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:whispaste/core/data/database.dart';

/// Routes the migration's queries through [_FailFirstColumnRead]. drift hands
/// the migration the inner executor, so a plain interceptor never sees them.
class _FaultyMigration extends QueryInterceptor {
  _FaultyMigration(this.code);

  final int code;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_FaultyUser(user, _FailFirstColumnRead(code)));
}

class _FaultyUser implements QueryExecutorUser {
  _FaultyUser(this._user, this._fault);

  final QueryExecutorUser _user;
  final QueryInterceptor _fault;

  @override
  int get schemaVersion => _user.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      _user.beforeOpen(executor.interceptWith(_fault), details);
}

/// Fails the first `PRAGMA table_info('history_entries')`: the v18 step,
/// inside a catch block that tolerates data-dependent failures.
class _FailFirstColumnRead extends QueryInterceptor {
  _FailFirstColumnRead(this.code);

  final int code;
  bool _armed = true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_armed && statement.contains("table_info('history_entries')")) {
      _armed = false;
      throw SqliteException(extendedResultCode: code, message: 'injected');
    }
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  group('_migrateJsonTags', () {
    late HistoryDatabase db;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> insertEntry(String id, String tagsJson) {
      return db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: id,
          timestamp: DateTime(2026, 10, 1),
          tags: Value(tagsJson),
        ),
      );
    }

    Future<List<String>> linkNames() async {
      final rows = await db
          .customSelect(
            'SELECT e.entry_id AS entry, t.name AS tag FROM entry_tags e '
            'JOIN tags t ON t.id = e.tag_id ORDER BY entry, tag',
          )
          .get();
      return [for (final r in rows) '${r.data['entry']}:${r.data['tag']}'];
    }

    test(
      'running twice gives the same tags and links, no duplicates',
      () async {
        await insertEntry('a', '["Work"," work ","Ideas"]');
        await insertEntry('b', '["ideas"]');

        await db.migrateJsonTagsForTesting();
        final first = await linkNames();
        final firstTags = (await db.allTags()).map((t) => t.name).toList()
          ..sort();

        await db.migrateJsonTagsForTesting();

        expect(await linkNames(), first);
        expect(
          (await db.allTags()).map((t) => t.name).toList()..sort(),
          firstTags,
        );
        expect(first, ['a:ideas', 'a:work', 'b:ideas']);
        expect(firstTags, ['ideas', 'work']);
      },
    );

    test('a non-string element skips only that element', () async {
      await insertEntry('c', '[1,"ops",null]');

      await db.migrateJsonTagsForTesting();

      expect(await linkNames(), ['c:ops']);
    });
  });

  group('onUpgrade transaction', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_tx_');
      dbFile = File(p.join(tmpDir.path, 'history.db'));
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    /// A complete v31 file stamped as v17, so every step from v18 runs on it.
    Future<void> seedV17() async {
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.customStatement('PRAGMA user_version = 17');
      await seed.close();
    }

    int storedVersion() {
      final raw = sqlite3.open(dbFile.path);
      try {
        return raw.select('PRAGMA user_version').single.columnAt(0) as int;
      } finally {
        raw.close();
      }
    }

    test('a transient error in a tolerant step rolls the upgrade back, and '
        'a fresh open retries it', () async {
      await seedV17();

      final failing = HistoryDatabase.forTesting(
        NativeDatabase(dbFile).interceptWith(_FaultyMigration(5)),
      );
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsA(
          isA<DatabaseUpgradeInterruptedException>().having(
            (e) => e.cause.resultCode,
            'cause',
            5,
          ),
        ),
      );
      try {
        await failing.close();
      } on Object {
        // The failed open may surface again on close; the file is what counts.
      }
      expect(storedVersion(), 17);

      final retry = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await retry.customSelect('SELECT 1').get();
      await retry.close();
      expect(storedVersion(), retry.schemaVersion);
    });

    test('a data-dependent error in a tolerant step is logged and the '
        'upgrade completes', () async {
      await seedV17();

      final db = HistoryDatabase.forTesting(
        NativeDatabase(dbFile).interceptWith(_FaultyMigration(1)),
      );
      await db.customSelect('SELECT 1').get();
      await db.close();

      expect(storedVersion(), db.schemaVersion);
    });

    test('a failing later step rolls back every earlier step of the same '
        'open and keeps the old version', () async {
      // A v28 file: without the v30 column and the v31 table. Dropping the
      // snippets table makes the v31 step fail after the v30 step ran.
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.customStatement(
        'ALTER TABLE hotkey_latency_entries DROP COLUMN stop_to_text_ms',
      );
      await seed.customStatement('DROP TABLE note_versions');
      await seed.customStatement('PRAGMA foreign_keys = OFF');
      await seed.customStatement('DROP TABLE snippets');
      await seed.customStatement('PRAGMA user_version = 28');
      await seed.close();

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      // Pin the failure to the v31 step: the snippets table is gone there.
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('snippets'),
          ),
        ),
      );
      try {
        await db.close();
      } on Object {
        // The failed open may surface again on close; the file is what counts.
      }

      final raw = sqlite3.open(dbFile.path);
      addTearDown(raw.close);
      expect(raw.select('PRAGMA user_version').single.columnAt(0), 28);
      final columns = {
        for (final row in raw.select(
          "PRAGMA table_info('hotkey_latency_entries')",
        ))
          row['name'],
      };
      expect(columns, isNot(contains('stop_to_text_ms')));
      final tables = {
        for (final row in raw.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name'],
      };
      expect(tables, isNot(contains('note_versions')));
    });
  });
}
