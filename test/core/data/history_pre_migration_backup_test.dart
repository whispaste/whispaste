import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
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

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp74-pre-migration-');
    copyPath = p.join(root.path, 'history.db.pre-migration');
    File(copyPath).writeAsStringSync('plaintext history');
  });

  tearDown(() {
    _chmod('755', root.path);
    root.deleteSync(recursive: true);
  });

  test('a successful start removes the pre-migration copy', () async {
    final db = HistoryDatabase.forTesting(
      NativeDatabase.memory(),
      () => root.path,
    );
    addTearDown(db.close);

    await db.select(db.historyEntries).get();

    expect(File(copyPath).existsSync(), isFalse);
  });

  test('a failing migration keeps the copy as the rescue anchor', () async {
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

    await migrateFromNestedPath(root.path, isWindows: true);

    expect(File(copyPath).existsSync(), isTrue);
    expect(File(target).existsSync(), isTrue);
  });
}
