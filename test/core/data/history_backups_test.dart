import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:whispaste/core/data/history_backups.dart';

void main() {
  late Directory root;
  late String dbPath;
  final t0 = DateTime.utc(2026, 11, 1, 8);

  void writeRows(int n, {int? userVersion}) {
    final db = sqlite3.open(dbPath);
    try {
      db.execute('CREATE TABLE IF NOT EXISTS entries (id INTEGER, body TEXT)');
      for (var i = 0; i < n; i++) {
        db.execute("INSERT INTO entries VALUES ($i, 'text $i')");
      }
      if (userVersion != null) db.execute('PRAGMA user_version = $userVersion');
    } finally {
      db.close();
    }
  }

  int rowsIn(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return db.select('SELECT COUNT(*) FROM entries').single.columnAt(0)
          as int;
    } finally {
      db.close();
    }
  }

  Future<HistoryBackupResult> backup(DateTime now) async =>
      (await writeHistoryBackup(root.path, source: dbPath, now: now)).result;

  File stamped(String name, {int bytes = 10}) {
    final dir = Directory(historyBackupDir(root.path))
      ..createSync(recursive: true);
    return File(p.join(dir.path, name))
      ..writeAsBytesSync(List.filled(bytes, 0));
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp562-backups-');
    dbPath = p.join(root.path, 'history.db');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('when a copy is due', () {
    test('only a file below the current schema version is upgraded', () {
      expect(historyUpgradePending(dbPath, 33), isFalse, reason: 'no file');
      writeRows(1, userVersion: 32);
      expect(historyUpgradePending(dbPath, 33), isTrue);
      writeRows(0, userVersion: 33);
      expect(historyUpgradePending(dbPath, 33), isFalse);
      writeRows(0, userVersion: 0);
      expect(historyUpgradePending(dbPath, 33), isFalse, reason: 'new file');
    });
  });

  test('a copy is complete and the source stays untouched', () async {
    writeRows(5);
    expect(await backup(t0), HistoryBackupResult.created);
    final backups = listHistoryBackups(root.path);
    expect(backups, hasLength(1));
    expect(rowsIn(backups.single.path), 5);
    expect(rowsIn(dbPath), 5);
  });

  test('at most three copies stay, the oldest goes first', () async {
    for (var day = 0; day < 5; day++) {
      writeRows(1);
      await backup(t0.add(Duration(hours: day)));
    }
    final backups = listHistoryBackups(root.path);
    expect([for (final b in backups) rowsIn(b.path)], [5, 4, 3]);
  });

  test('the size cap drops the oldest copies but never the newest', () {
    stamped('history-20261101-080000.db', bytes: 100);
    stamped('history-20261101-090000.db', bytes: 100);
    stamped('history-20261101-100000.db', bytes: 100);
    pruneHistoryBackups(
      root.path,
      now: t0.add(const Duration(hours: 3)),
      policy: const HistoryBackupPolicy(maxTotalBytes: 150),
    );
    expect(listHistoryBackups(root.path).map((f) => p.basename(f.path)), [
      'history-20261101-100000.db',
    ]);
  });

  void failingDelete(String path) =>
      throw FileSystemException('locked', path, const OSError('denied', 13));

  test('a file the thinning cannot delete is reported, not lost', () {
    stamped('history-20200101-000000.db');
    final problems = pruneHistoryBackups(
      root.path,
      now: t0,
      deleteFile: failingDelete,
    );
    expect(problems, ['history-20200101-000000.db']);
    expect(
      File(p.join(historyBackupDir(root.path), problems.single)).existsSync(),
      isTrue,
    );
  });

  test('reported problems carry no folder path or OS error text', () async {
    writeRows(1);
    stamped('history-20200101-000000.db');
    stamped('history-20261101-070000.db.tmp');
    final outcome = await writeHistoryBackup(
      root.path,
      source: dbPath,
      now: t0,
      deleteFile: failingDelete,
    );
    expect(outcome.result, HistoryBackupResult.created);
    expect(
      outcome.cleanupProblems,
      unorderedEquals([
        'history-20200101-000000.db',
        'history-20261101-070000.db.tmp',
      ]),
    );
    for (final problem in outcome.cleanupProblems) {
      expect(problem, isNot(contains(root.path)));
      expect(problem, isNot(contains('denied')));
    }
  });

  test('copies go after three clean opens', () async {
    writeRows(1);
    await backup(t0);
    noteCleanHistoryOpen(root.path, now: t0);
    noteCleanHistoryOpen(root.path, now: t0);
    expect(listHistoryBackups(root.path), hasLength(1));
    noteCleanHistoryOpen(root.path, now: t0);
    expect(Directory(historyBackupDir(root.path)).existsSync(), isFalse);
  });

  test('a new copy restarts the clean-open count', () async {
    writeRows(1);
    await backup(t0);
    noteCleanHistoryOpen(root.path, now: t0);
    noteCleanHistoryOpen(root.path, now: t0);
    final later = t0.add(const Duration(hours: 1));
    await backup(later);
    noteCleanHistoryOpen(root.path, now: later);
    expect(listHistoryBackups(root.path), hasLength(2));
  });

  test('a clean open removes a copy cut off mid-write', () {
    final stale = stamped('history-20261101-080000.db.tmp');
    noteCleanHistoryOpen(root.path, now: t0);
    expect(stale.existsSync(), isFalse);
  });

  test('copies older than seven days go regardless of the count', () {
    stamped('history-20261101-080000.db');
    noteCleanHistoryOpen(root.path, now: t0.add(const Duration(days: 8)));
    expect(listHistoryBackups(root.path), isEmpty);
  });

  test('a stamp in the future is invalid and blocks nothing', () async {
    stamped('history-20301101-080000.db');
    writeRows(2);
    expect(await backup(t0), HistoryBackupResult.created);
    final names = listHistoryBackups(root.path).map((f) => p.basename(f.path));
    expect(names, ['history-20261101-080000.db']);
  });

  test('an interrupted earlier run leaves no half copy behind', () async {
    writeRows(2);
    final stale = stamped('history-20261031-080000.db.tmp');
    expect(await backup(t0), HistoryBackupResult.created);
    expect(stale.existsSync(), isFalse);
    expect(listHistoryBackups(root.path), hasLength(1));
  });

  test('an unreadable source keeps the existing copies', () async {
    writeRows(3);
    await backup(t0);
    File(dbPath).writeAsStringSync('not a database');
    expect(
      await backup(t0.add(const Duration(hours: 1))),
      HistoryBackupResult.failed,
    );
    final backups = listHistoryBackups(root.path);
    expect(backups, hasLength(1));
    expect(rowsIn(backups.single.path), 3);
    final temps = Directory(
      historyBackupDir(root.path),
    ).listSync().where((e) => e.path.endsWith('.tmp'));
    expect(temps, isEmpty);
  });

  test('an erase that failed is repeated at the next start', () {
    stamped('history-20261101-080000.db');
    File(
      p.join(root.path, historyBackupErasePendingName),
    ).writeAsStringSync('');
    retryPendingBackupErase(root.path);
    expect(Directory(historyBackupDir(root.path)).existsSync(), isFalse);
    expect(
      File(p.join(root.path, historyBackupErasePendingName)).existsSync(),
      isFalse,
    );
  });
}
