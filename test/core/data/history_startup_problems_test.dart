// A failed move or safety copy at start is recorded for the user, not only
// logged (#602).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_backups.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp602-startup-');
    takeHistoryStartupProblems();
  });

  tearDown(() {
    takeHistoryStartupProblems();
    root.deleteSync(recursive: true);
  });

  test('a safety copy that fails is recorded once', () async {
    final source = p.join(root.path, 'history.db');
    File(source).writeAsStringSync('this is not a database');
    final outcome = await backupBeforeRiskyStep(root.path, source);
    expect(outcome.result, HistoryBackupResult.failed);
    expect(takeHistoryStartupProblems(), [HistoryStartupProblem.backupFailed]);
    expect(takeHistoryStartupProblems(), isEmpty);
  });

  test('a failed safety copy logs no path and no error text (#742)', () async {
    // The copy statement names the backup folder, so the raw SQLite error
    // would carry it (and with it the user name) into the log and Sentry.
    final source = p.join(root.path, 'history.db');
    File(source).writeAsStringSync('this is not a database');
    final lines = <String>[];
    final sub = Logger.root.onRecord.listen(
      (r) => lines.add('${r.message} ${r.error ?? ''}'),
    );
    addTearDown(sub.cancel);
    final outcome = await backupBeforeRiskyStep(root.path, source);
    expect(outcome.result, HistoryBackupResult.failed);
    expect(outcome.error, startsWith('SqliteException(code '));
    final warning = lines.singleWhere((l) => l.contains('not written'));
    expect(warning, isNot(contains(root.path)));
    expect(warning, isNot(contains(p.basename(root.path))));
  });

  test(
    'a backup folder that cannot be created reports only the type',
    () async {
      final source = p.join(root.path, 'history.db');
      sqlite3.open(source)
        ..execute('CREATE TABLE entries (id INTEGER)')
        ..close();
      // A plain file where the folder belongs fails on every platform.
      File(historyBackupDir(root.path)).writeAsStringSync('');
      final outcome = await writeHistoryBackup(
        root.path,
        source: source,
        now: DateTime.utc(2026, 11, 8),
      );
      expect(outcome.result, HistoryBackupResult.failed);
      expect(outcome.error, startsWith('FileSystemException(errno '));
      expect(outcome.error, isNot(contains(p.basename(root.path))));
    },
  );

  test('a safety copy that works records nothing', () async {
    final source = p.join(root.path, 'history.db');
    sqlite3.open(source)
      ..execute('CREATE TABLE entries (id INTEGER)')
      ..close();
    final outcome = await backupBeforeRiskyStep(root.path, source);
    expect(outcome.result, HistoryBackupResult.created);
    expect(takeHistoryStartupProblems(), isEmpty);
  });

  test('a move that failed is recorded, a move that worked is not', () {
    reportNestedPathMove(const NestedPathMigration('/data/history.db'));
    expect(takeHistoryStartupProblems(), isEmpty);
    reportNestedPathMove(
      NestedPathMigration('/old/history.db', error: StateError('disk full')),
    );
    expect(takeHistoryStartupProblems(), [HistoryStartupProblem.moveFailed]);
  });
}
