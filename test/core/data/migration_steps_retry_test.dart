import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_backups.dart';
import 'package:whispaste/services/path_service.dart' as paths;

/// Every version a file can be upgraded FROM. The staircase in
/// `HistoryDatabase.migration` runs a step for each `from < N`; stamping a
/// complete current file as N-1 makes exactly that step (and all later ones)
/// run. A new step adds its predecessor here, or the guard below fails.
const List<int> _sourceVersions = [
  1, 2, 3, 4, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, //
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  42,
  43,
  44,
  45,
  46,
  47,
];

/// Counts the write statements of the open and throws on the [failAt]-th one.
/// drift hands the migration the inner executor, so the fault goes in through
/// the user's `beforeOpen`, like in `history_migration_safety_test.dart`.
class _FailNthWrite extends QueryInterceptor {
  _FailNthWrite(this.failAt);

  /// 0 never fails; the count then tells how many writes the open makes.
  final int failAt;
  int writes = 0;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_FaultyUser(user, this));

  void _count() {
    writes++;
    if (writes == failAt) {
      // SQLITE_BUSY is transient: no step may tolerate it, so it always
      // rolls the whole open back (a data-dependent code like 1 is
      // tolerated by some steps and would not abort).
      throw SqliteException(extendedResultCode: 5, message: 'injected');
    }
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_isWrite(statement)) _count();
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count();
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count();
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count();
    return super.runDelete(executor, statement, args);
  }

  static bool _isWrite(String sql) {
    final s = sql.trimLeft().toUpperCase();
    // FTS5 takes its read-only check as an INSERT; the open's index
    // inspection runs it per search index after the upgrade has committed
    // (#628), and it changes nothing a fault could leave half done.
    if (s.contains("VALUES ('INTEGRITY-CHECK')")) return false;
    return !(s.startsWith('PRAGMA') && !s.contains('=')) &&
        !s.startsWith('SELECT');
  }
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

/// Schema and rows of a file, as plain strings for `equals`.
class _Snapshot {
  _Snapshot(this.version, this.schema, this.rows);

  final int version;
  final Map<String, String> schema;
  final Map<String, List<String>> rows;
}

_Snapshot _snapshot(File file) {
  final raw = sqlite3.open(file.path);
  try {
    final version = raw.select('PRAGMA user_version').single.columnAt(0) as int;
    final schema = <String, String>{};
    final rows = <String, List<String>>{};
    final objects = raw.select(
      'SELECT type, name, sql FROM sqlite_master '
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    for (final o in objects) {
      final name = o['name'] as String;
      schema['${o['type']} $name'] = '${o['sql']}';
      final isPlainTable =
          o['type'] == 'table' &&
          !(o['sql'] as String? ?? '').toUpperCase().contains('VIRTUAL') &&
          !name.contains('_fts');
      if (isPlainTable) {
        // Ids, "now" stamps and the colour slot differ between two runs of
        // the same upgrade; everything else must be identical.
        final info = raw.select('PRAGMA table_info("$name")');
        final columns = [for (final c in info) c['name'] as String];
        // The colour slot is random, but NULL against set still matters.
        final slotAt = {
          for (var i = 0; i < columns.length; i++)
            if (columns[i].contains('slot')) i,
        };
        final list = [
          for (final r in raw.select(
            'SELECT ${columns.map((c) => '"$c"').join(', ')} FROM "$name"',
          ))
            [
              for (var i = 0; i < r.values.length; i++)
                slotAt.contains(i)
                    ? (r.values[i] == null ? 'null' : '<slot>')
                    : _mask(r.values[i]),
            ].join('|'),
        ]..sort();
        rows[name] = list;
      }
    }
    return _Snapshot(version, schema, rows);
  } finally {
    raw.close();
  }
}

final _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);

String _mask(Object? v) {
  if (v is int) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((v - nowSec).abs() < 3600) return '<now>';
  }
  return '$v'.replaceAll(_uuid, '<id>');
}

void main() {
  late Directory tmpDir;
  late File dbFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('wp603_steps_');
    dbFile = File(p.join(tmpDir.path, 'history.db'));
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  /// A complete current file with rows in it, stamped as [from].
  Future<void> seed(File file, int from) async {
    final db = HistoryDatabase.forTesting(NativeDatabase(file));
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'a',
        timestamp: DateTime(2026, 10, 1),
        tags: const Value('["Work","ideas"]'),
      ),
    );
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(id: 'b', timestamp: DateTime(2026, 10, 2)),
    );
    await db.createNote();
    await db.customStatement('PRAGMA user_version = $from');
    await db.close();
  }

  /// Opens [file] with the staircase; a fault surfaces from the first query.
  Future<void> open(File file, {_FailNthWrite? fault}) async {
    final executor = fault == null
        ? NativeDatabase(file)
        : NativeDatabase(file).interceptWith(fault);
    final db = HistoryDatabase.forTesting(executor);
    try {
      await db.customSelect('SELECT 1').get();
    } finally {
      try {
        await db.close();
      } on Object {
        // A failed open can surface again on close; the file is what counts.
      }
    }
  }

  group('every upgrade step survives an abort and a repeat', () {
    for (final from in _sourceVersions) {
      test('from v$from: abort, then retry, ends like an undisturbed '
          'upgrade', () async {
        // Close one pristine source per version, then give the reference and
        // every fault attempt independent copies of exactly the same bytes.
        // Recreating the current schema for each abort adds many durable writes
        // without exercising another migration path.
        final source = File(p.join(tmpDir.path, 'source.db'));
        await seed(source, from);
        final reference = await source.copy(
          p.join(tmpDir.path, 'reference.db'),
        );
        final counter = _FailNthWrite(0);
        await open(reference, fault: counter);
        final expected = _snapshot(reference);
        expect(expected.version, historySchemaVersion);
        expect(counter.writes, greaterThan(0));

        // Abort at the first, a middle and the last write of the open. The
        // very last one is drift's own version stamp, which is not ours to
        // break, so the one before it is the last one tried.
        final aborts = {1, (counter.writes / 2).ceil(), counter.writes - 1};
        for (final failAt in aborts) {
          await source.copy(dbFile.path);
          final before = _snapshot(dbFile);

          Object? thrown;
          try {
            await open(dbFile, fault: _FailNthWrite(failAt));
          } on Object catch (e) {
            thrown = e;
          }
          // The staircase never swallows a transient failure; steps after it
          // (beforeOpen) may tolerate one by design and then finish.
          if (failAt == 1) {
            expect(thrown, isNotNull, reason: 'the first write must abort');
          }
          final aborted = _snapshot(dbFile);
          if (thrown != null) {
            // An aborted open leaves the file as it was: same rows, and the
            // old stamp, so the next start upgrades again.
            expect(aborted.rows, before.rows, reason: 'write $failAt');
            expect(aborted.schema, before.schema, reason: 'write $failAt');
            expect(aborted.version, before.version, reason: 'write $failAt');
          } else {
            // A tolerated late failure: the open finished, the stamp is new.
            expect(aborted.version, historySchemaVersion);
          }

          await open(dbFile);
          final retried = _snapshot(dbFile);
          expect(retried.version, expected.version, reason: 'write $failAt');
          expect(retried.rows, expected.rows, reason: 'write $failAt');
          expect(retried.schema, expected.schema, reason: 'write $failAt');

          // A second open of the finished file changes nothing.
          await open(dbFile);
          final again = _snapshot(dbFile);
          expect(again.rows, expected.rows);
          expect(again.schema, expected.schema);
          dbFile.deleteSync();
        }
      });
    }
  });

  test('the step list covers the whole staircase', () {
    final source = File('lib/core/data/database.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _upgradeLegacySteps');
    final end = source.indexOf('beforeOpen: (details)');
    final staircase = source.substring(start, end);
    final thresholds = {
      for (final m in RegExp(r'from < (\d+)').allMatches(staircase))
        int.parse(m.group(1)!),
    };
    expect(thresholds, isNotEmpty);
    final covered = {for (final v in _sourceVersions) v + 1};
    expect(
      thresholds.difference(covered),
      isEmpty,
      reason:
          'a new `from < N` step needs ${thresholds.difference(covered).map((n) => n - 1)} in _sourceVersions',
    );
    // The newest step is exercised too: nothing sits above the last source.
    expect(_sourceVersions.last, historySchemaVersion - 1);
  });

  group('start-up wiring of the safety copy', () {
    late String appData;

    setUp(() {
      appData = tmpDir.path;
      paths.appDataDirOverride = appData;
    });

    tearDown(() => paths.appDataDirOverride = null);

    List<String> backups() {
      final dir = Directory(historyBackupDir(appData));
      return dir.existsSync()
          ? [for (final f in dir.listSync()) p.basename(f.path)]
          : <String>[];
    }

    Future<void> startApp() async {
      final db = HistoryDatabase();
      try {
        await db.customSelect('SELECT 1').get();
      } finally {
        await db.close();
      }
    }

    test('an ordinary start without an upgrade takes no safety copy', () async {
      await seed(File(p.join(appData, 'history.db')), historySchemaVersion);

      await startApp();
      await startApp();

      expect(backups(), isEmpty);
    });

    test('a start that has to upgrade takes one first', () async {
      await seed(File(p.join(appData, 'history.db')), 20);

      await startApp();

      expect(backups(), isNotEmpty);
    });
  });
}
