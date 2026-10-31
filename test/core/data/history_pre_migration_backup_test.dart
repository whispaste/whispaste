import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:whispaste/core/data/database.dart';

/// Fails when the connection opens, as a failing schema migration would.
class _FailingOpen extends QueryInterceptor {
  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      Future.error(StateError('migration failed'));
}

/// `chmod` exists only on POSIX hosts. Windows has no equivalent that locks a
/// folder for the delete, so the permission tricks are skipped there.
void _chmod(String mode, String path) {
  if (!Platform.isWindows) Process.runSync('chmod', [mode, path]);
}

void main() {
  late Directory root;
  late String copyPath;
  late String targetPath;

  /// A sound `history.db` next to the copy: only then may the copy go.
  void writeSoundTarget() {
    sqlite3.open(targetPath)
      ..execute('CREATE TABLE marker (v TEXT)')
      ..close();
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp74-pre-migration-');
    copyPath = p.join(root.path, 'history.db.pre-migration');
    targetPath = p.join(root.path, 'history.db');
    File(copyPath).writeAsStringSync('plaintext history');
  });

  tearDown(() {
    _chmod('755', root.path);
    root.deleteSync(recursive: true);
  });

  test('a successful start removes the pre-migration copy', () async {
    writeSoundTarget();
    final db = HistoryDatabase.forTesting(
      NativeDatabase.memory(),
      () => root.path,
    );
    addTearDown(db.close);

    await db.select(db.historyEntries).get();

    expect(File(copyPath).existsSync(), isFalse);
  });

  test('a failing migration keeps the copy as the rescue anchor', () async {
    writeSoundTarget();
    final db = HistoryDatabase.forTesting(
      NativeDatabase.memory().interceptWith(_FailingOpen()),
      () => root.path,
    );
    addTearDown(db.close);

    await expectLater(db.select(db.historyEntries).get(), throwsStateError);

    expect(File(copyPath).existsSync(), isTrue);
  });

  test(
    'a copy that cannot be deleted is retried on the next start',
    () async {
      writeSoundTarget();
      _chmod('555', root.path);
      final first = HistoryDatabase.forTesting(
        NativeDatabase.memory(),
        () => root.path,
      );
      addTearDown(first.close);
      await first.select(first.historyEntries).get();
      expect(File(copyPath).existsSync(), isTrue, reason: 'still locked');

      _chmod('755', root.path);
      final second = HistoryDatabase.forTesting(
        NativeDatabase.memory(),
        () => root.path,
      );
      addTearDown(second.close);
      await second.select(second.historyEntries).get();

      expect(File(copyPath).existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test('the copy stays while history.db next to it is missing', () async {
    final db = HistoryDatabase.forTesting(
      NativeDatabase.memory(),
      () => root.path,
    );
    addTearDown(db.close);

    await db.select(db.historyEntries).get();

    expect(File(copyPath).existsSync(), isTrue);
  });

  test('the copy stays while history.db next to it is damaged', () async {
    File(targetPath).writeAsStringSync('not a database');
    final db = HistoryDatabase.forTesting(
      NativeDatabase.memory(),
      () => root.path,
    );
    addTearDown(db.close);

    await db.select(db.historyEntries).get();

    expect(File(copyPath).existsSync(), isTrue);
  });

  test('the migration copies an existing target and keeps its bytes', () async {
    final nested = p.join(root.path, 'WhisPaste', 'history.db');
    Directory(p.dirname(nested)).createSync(recursive: true);
    sqlite3.open(nested)
      ..execute('CREATE TABLE marker (v TEXT)')
      ..close();
    final target = p.join(root.path, 'history.db');
    sqlite3.open(target)
      ..execute('CREATE TABLE marker (v TEXT)')
      ..close();
    File(copyPath).deleteSync();
    final targetBytes = File(target).readAsBytesSync();

    final result = await migrateFromNestedPath(root.path, isWindows: true);

    expect(result.error, isNull);
    expect(File(copyPath).readAsBytesSync(), targetBytes);
    expect(File(target).existsSync(), isTrue);
  });

  group('migrateFromNestedPath move', () {
    late String nested;
    late String target;
    late String staging;

    /// A database with [rows] rows in `history_entries`.
    void writeDb(String path, int rows) {
      final db = sqlite3.open(path);
      try {
        db.execute('CREATE TABLE IF NOT EXISTS history_entries (id TEXT)');
        for (var i = 0; i < rows; i++) {
          db.execute("INSERT INTO history_entries VALUES ('r$i')");
        }
      } finally {
        db.close();
      }
    }

    int rowsIn(String path) {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        return db
                .select('SELECT COUNT(*) AS n FROM history_entries')
                .single['n']
            as int;
      } finally {
        db.close();
      }
    }

    setUp(() {
      nested = p.join(root.path, 'WhisPaste', 'history.db');
      target = p.join(root.path, 'history.db');
      staging = p.join(root.path, 'history.db.migrating');
      Directory(p.dirname(nested)).createSync(recursive: true);
      writeDb(nested, 2);
      File(copyPath).deleteSync();
    });

    test('a Go-era target is replaced by the verified nested copy, kept as '
        'the pre-migration copy, and the nested folder goes', () async {
      writeDb(target, 1);

      final result = await migrateFromNestedPath(root.path, isWindows: true);

      expect(result.error, isNull);
      expect(result.databasePath, target);
      expect(rowsIn(target), 2);
      expect(rowsIn(copyPath), 1);
      expect(File(staging).existsSync(), isFalse);
      expect(Directory(p.dirname(nested)).existsSync(), isFalse);
    });

    test('without a target the nested copy becomes the target', () async {
      final result = await migrateFromNestedPath(root.path, isWindows: true);

      expect(result.error, isNull);
      expect(rowsIn(target), 2);
      expect(File(copyPath).existsSync(), isFalse);
    });

    test('a nested file left behind after a completed move is never imported '
        'again over newer data', () async {
      await migrateFromNestedPath(root.path, isWindows: true);
      expect(
        File(p.join(root.path, nestedPathMovedMarker)).existsSync(),
        isTrue,
      );
      // New dictations land in the target; the nested folder survived its
      // deletion (a locked file on Windows).
      writeDb(target, 3);
      Directory(p.dirname(nested)).createSync(recursive: true);
      writeDb(nested, 2);

      final result = await migrateFromNestedPath(root.path, isWindows: true);

      expect(result.error, isNull);
      expect(result.databasePath, target);
      expect(rowsIn(target), 5);
      expect(Directory(p.dirname(nested)).existsSync(), isFalse);
    });

    test('a marker that cannot be written keeps the nested folder in use, '
        'and the next start finishes the move', () async {
      writeDb(target, 1);
      final marker = p.join(root.path, nestedPathMovedMarker);
      // A folder in the marker's place makes the write fail on every host.
      Directory(marker).createSync();

      final first = await migrateFromNestedPath(root.path, isWindows: true);

      expect(first.error, isNotNull);
      expect(first.databasePath, nested);
      expect(rowsIn(nested), 2);
      expect(rowsIn(target), 2);

      Directory(marker).deleteSync();
      final second = await migrateFromNestedPath(root.path, isWindows: true);

      expect(second.error, isNull);
      expect(second.databasePath, target);
      expect(rowsIn(target), 2);
      expect(File(marker).existsSync(), isTrue);
      expect(Directory(p.dirname(nested)).existsSync(), isFalse);
    });

    test(
      'committed pages still in the source WAL are part of the copy',
      () async {
        final open = sqlite3.open(nested)
          ..execute('PRAGMA journal_mode = WAL')
          ..execute("INSERT INTO history_entries VALUES ('in-wal')");
        addTearDown(open.close);

        final result = await migrateFromNestedPath(root.path, isWindows: true);

        expect(result.error, isNull);
        expect(rowsIn(target), 3);
      },
    );

    test(
      'an unreadable source keeps the original and reports the error',
      () async {
        File(nested).writeAsBytesSync(List.filled(4096, 7));
        writeDb(target, 1);

        final result = await migrateFromNestedPath(root.path, isWindows: true);

        expect(result.error, isNotNull);
        expect(result.databasePath, nested);
        expect(rowsIn(target), 1);
        expect(File(staging).existsSync(), isFalse);
        expect(File(nested).existsSync(), isTrue);
      },
    );

    test('a failing copy of the source keeps the target and the original '
        'in use', () async {
      writeDb(target, 1);
      final ops = NestedPathMoveOps(
        copy: (from, to) async {
          if (from == nested) throw StateError('disk full');
          await File(from).copy(to);
        },
      );

      final result = await migrateFromNestedPath(
        root.path,
        isWindows: true,
        ops: ops,
      );

      expect(result.error, isA<StateError>());
      expect(result.databasePath, nested);
      expect(rowsIn(target), 1);
      expect(File(staging).existsSync(), isFalse);
      expect(File(copyPath).existsSync(), isFalse);
      expect(rowsIn(result.databasePath), 2);
    });

    test('a failing backup of the target keeps the target untouched', () async {
      writeDb(target, 1);
      final ops = NestedPathMoveOps(
        copy: (from, to) async {
          if (from == target) throw StateError('backup failed');
          await File(from).copy(to);
        },
      );

      final result = await migrateFromNestedPath(
        root.path,
        isWindows: true,
        ops: ops,
      );

      expect(result.error, isA<StateError>());
      expect(rowsIn(target), 1);
      expect(File(staging).existsSync(), isFalse);
      expect(File(copyPath).existsSync(), isFalse);
      expect(File(nested).existsSync(), isTrue);
    });

    test('a copy that fails verification is never swapped in', () async {
      writeDb(target, 1);
      final ops = NestedPathMoveOps(
        verifyCopy: (source, copy) => throw StateError('row count differs'),
      );

      final result = await migrateFromNestedPath(
        root.path,
        isWindows: true,
        ops: ops,
      );

      expect(result.error, isA<StateError>());
      expect(rowsIn(target), 1);
      expect(File(staging).existsSync(), isFalse);
      expect(File(copyPath).existsSync(), isFalse);
    });

    test('a failing swap keeps the target and drops the backup', () async {
      writeDb(target, 1);
      final ops = NestedPathMoveOps(
        swapIn: (from, to) async => throw StateError('file in use'),
      );

      final result = await migrateFromNestedPath(
        root.path,
        isWindows: true,
        ops: ops,
      );

      expect(result.error, isA<StateError>());
      expect(rowsIn(target), 1);
      expect(File(staging).existsSync(), isFalse);
      expect(File(copyPath).existsSync(), isFalse);
      expect(File(nested).existsSync(), isTrue);
    });

    test(
      'a swap that removed the target restores it from the rescue copy',
      () async {
        writeDb(target, 1);
        final ops = NestedPathMoveOps(
          swapIn: (from, to) async {
            // Dart's rename removes an existing target before it moves the new
            // file in; a failure after that step leaves no target behind.
            File(to).deleteSync();
            throw StateError('file in use');
          },
        );

        final result = await migrateFromNestedPath(
          root.path,
          isWindows: true,
          ops: ops,
        );

        expect(result.error, isA<StateError>());
        expect(rowsIn(target), 1);
        expect(File(copyPath).existsSync(), isFalse);
        expect(File(nested).existsSync(), isTrue);
      },
    );

    test('a rescue copy that cannot be restored is kept', () async {
      writeDb(target, 1);
      final ops = NestedPathMoveOps(
        copy: (from, to) async {
          if (from == copyPath) throw StateError('disk full');
          await File(from).copy(to);
        },
        swapIn: (from, to) async {
          File(to).deleteSync();
          throw StateError('file in use');
        },
      );

      final result = await migrateFromNestedPath(
        root.path,
        isWindows: true,
        ops: ops,
      );

      expect(result.error, isA<StateError>());
      expect(File(target).existsSync(), isFalse);
      expect(rowsIn(copyPath), 1);
    });
  });
}
