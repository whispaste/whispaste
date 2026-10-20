import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

HistoryDatabase _open(String path) =>
    HistoryDatabase.forTesting(NativeDatabase(File(path)));

void main() {
  late Directory root;
  late String dbPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp74-reset-files-');
    dbPath = p.join(root.path, 'history.db');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'a factory reset removes the pre-migration copy and the WAL sidecars',
    () async {
      final db = _open(dbPath);
      await db.customStatement('PRAGMA journal_mode=WAL');
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'one',
          timestamp: DateTime(2026, 10, 18),
        ),
      );
      final backup = File(p.join(root.path, 'history.db.pre-migration'))
        ..writeAsStringSync('plaintext history');
      final wal = File('$dbPath-wal');
      expect(wal.existsSync(), isTrue, reason: 'WAL mode is in effect');

      await db.deleteAllData();
      await eraseHistoryDatabaseFiles(db, root.path);

      expect(backup.existsSync(), isFalse);
      expect(wal.existsSync(), isFalse);
      expect(File('$dbPath-shm').existsSync(), isFalse);
      await db.close();

      // The deletion must reach the main file: a removed WAL must not undo it.
      final reopened = _open(dbPath);
      addTearDown(reopened.close);
      expect(await reopened.select(reopened.historyEntries).get(), isEmpty);
    },
  );

  test(
    'a failed checkpoint closes the database and removes its sidecars',
    () async {
      final db = HistoryDatabase.forTesting(
        NativeDatabase(File(dbPath)).interceptWith(_NoCheckpoint()),
      );
      final wal = File('$dbPath-wal')..writeAsStringSync('');

      await eraseHistoryDatabaseFiles(db, root.path);

      expect(wal.existsSync(), isFalse);
    },
  );

  test('a sidecar that stays behind fails the reset', () async {
    final db = HistoryDatabase.forTesting(
      NativeDatabase(File(dbPath)).interceptWith(_NoCheckpoint()),
    );
    // A folder where the journal should be cannot be deleted as a file.
    Directory(p.join(root.path, 'history.db-journal')).createSync();

    await expectLater(
      eraseHistoryDatabaseFiles(db, root.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a failed erase hands the retry a freshly opened database', () async {
    final opened = <HistoryDatabase>[];
    final container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(
            NativeDatabase(File(dbPath)).interceptWith(_NoCheckpoint()),
          );
          opened.add(db);
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
    addTearDown(container.dispose);
    // The failed checkpoint closes the database, and a migration copy that
    // cannot be removed as a file fails the erase.
    final journal = Directory(p.join(root.path, 'history.db.pre-migration'))
      ..createSync();

    await expectLater(
      eraseHistoryForReset(container, root.path),
      throwsA(isA<FileSystemException>()),
    );

    journal.deleteSync();
    await eraseHistoryForReset(container, root.path);
    expect(
      opened,
      hasLength(2),
      reason: 'the retry must not reuse the closed one',
    );
  });

  test(
    'after a successful reset the app still reads from a usable database',
    () async {
      final container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            final db = HistoryDatabase.forTesting(NativeDatabase(File(dbPath)));
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      addTearDown(container.dispose);
      // Reset keeps the app running: the history page re-reads right after.
      container.read(historyDatabaseProvider);
      await eraseHistoryForReset(container, root.path);

      final db = container.read(historyDatabaseProvider);
      expect(await db.select(db.historyEntries).get(), isEmpty);
    },
  );
}

/// A database whose checkpoint is refused, as a locked WAL would be.
class _NoCheckpoint extends QueryInterceptor {
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('wal_checkpoint')) {
      return Future.error(StateError('checkpoint refused'));
    }
    return super.runSelect(executor, statement, args);
  }
}
