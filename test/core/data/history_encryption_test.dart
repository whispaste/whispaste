// Encryption of the history database at rest (#1020): the one-time
// conversion, its abort paths and the start-up wiring. Uses fixed test keys
// in temp folders only; no system key store is touched.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/encryption_preference.dart';
import 'package:whispaste/core/data/history_backups.dart';
import 'package:whispaste/core/data/history_encryption.dart';
import 'package:whispaste/core/data/sqlite_copy_check.dart';
import 'package:whispaste/services/path_service.dart' as paths;

final _key = 'ab' * 32;
final _otherKey = 'cd' * 32;

late Directory _tmp;

String _seedPlain(String path, {int rows = 3}) {
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE t(x TEXT)');
    for (var i = 0; i < rows; i++) {
      db.execute("INSERT INTO t VALUES ('secret transcript $i')");
    }
  } finally {
    db.close();
  }
  return path;
}

List<String> _rows(String path, {String? hexKey}) {
  final db = openSqlite(path, hexKey: hexKey);
  try {
    return [
      for (final r in db.select('SELECT x FROM t ORDER BY rowid')) '${r['x']}',
    ];
  } finally {
    db.close();
  }
}

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('wp_enc_'));
  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  String dbPath() => p.join(_tmp.path, 'history.db');

  test('sqliteHexKey takes 32 bytes only', () {
    expect(sqliteHexKey(List.filled(32, 0xab)), _key);
    expect(() => sqliteHexKey(List.filled(16, 1)), throwsArgumentError);
  });

  test('the conversion encrypts the file and keeps every row', () {
    final path = _seedPlain(dbPath());
    final before = _rows(path);

    final run = encryptHistoryDatabase(path, _key);

    expect(run.result, HistoryEncryptionResult.encrypted);
    expect(isPlainSqliteFile(path), isFalse);
    expect(
      String.fromCharCodes(File(path).readAsBytesSync()),
      isNot(contains('secret transcript')),
    );
    expect(_rows(path, hexKey: _key), before);
    expect(
      () => _rows(path, hexKey: _otherKey),
      throwsA(isA<SqliteException>()),
    );
    expect(() => _rows(path), throwsA(isA<SqliteException>()));
    expect(File(historyEncryptionStagingPath(path)).existsSync(), isFalse);

    // Runs once: a second start finds nothing to do.
    expect(
      encryptHistoryDatabase(path, _key).result,
      HistoryEncryptionResult.notNeeded,
    );
    expect(
      encryptHistoryDatabase(p.join(_tmp.path, 'missing.db'), _key).result,
      HistoryEncryptionResult.notNeeded,
    );
  });

  group('an aborted conversion keeps the plain original', () {
    void expectOriginalKept(String path, List<String> before) {
      expect(isPlainSqliteFile(path), isTrue);
      expect(_rows(path), before);
      expect(File(historyEncryptionStagingPath(path)).existsSync(), isFalse);
    }

    for (final step in ['write', 'verify', 'swap']) {
      test('failure in $step', () {
        final path = _seedPlain(dbPath());
        final before = _rows(path);
        const real = HistoryEncryptionOps();
        Never fail() => throw const FileSystemException('disk full');
        final ops = HistoryEncryptionOps(
          writeCopy: (s, t, k) {
            real.writeCopy(s, t, k);
            if (step == 'write') fail();
          },
          verifyCopy: (s, t, k) =>
              step == 'verify' ? fail() : real.verifyCopy(s, t, k),
          swapIn: (f, t) => step == 'swap' ? fail() : real.swapIn(f, t),
        );

        final run = encryptHistoryDatabase(path, _key, ops: ops);

        expect(run.result, HistoryEncryptionResult.failed);
        expect(run.error, 'FileSystemException');
        expectOriginalKept(path, before);
        // The next start completes it.
        expect(
          encryptHistoryDatabase(path, _key).result,
          HistoryEncryptionResult.encrypted,
        );
        expect(_rows(path, hexKey: _key), before);
      });
    }

    test('a copy that is still plain is never swapped in', () {
      final path = _seedPlain(dbPath());
      final before = _rows(path);
      final run = encryptHistoryDatabase(
        path,
        _key,
        ops: HistoryEncryptionOps(writeCopy: (s, t, k) => File(s).copySync(t)),
      );
      expect(run.result, HistoryEncryptionResult.failed);
      expectOriginalKept(path, before);
    });

    test('a staging file left by a killed run is removed first', () {
      final path = _seedPlain(dbPath());
      final staging = historyEncryptionStagingPath(path);
      File(staging).writeAsStringSync('half written');
      File('$staging-journal').writeAsStringSync('x');

      expect(
        encryptHistoryDatabase(path, _key).result,
        HistoryEncryptionResult.encrypted,
      );
      expect(File(staging).existsSync(), isFalse);
      expect(File('$staging-journal').existsSync(), isFalse);
    });

    test('a pending journal postpones the conversion', () {
      final path = _seedPlain(dbPath());
      File('$path-journal').writeAsStringSync('');
      final run = encryptHistoryDatabase(path, _key);
      expect(run.result, HistoryEncryptionResult.failed);
      expect(run.error, 'pending-journal');
      expect(isPlainSqliteFile(path), isTrue);
    });
  });

  test(
    'backup and version check read an encrypted file with the key',
    () async {
      final path = _seedPlain(dbPath());
      final db = sqlite3.open(path);
      db.execute('PRAGMA user_version = 7');
      db.close();
      encryptHistoryDatabase(path, _key);

      expect(storedSchemaVersion(path, hexKey: _key), 7);
      final outcome = await writeHistoryBackup(
        _tmp.path,
        source: path,
        now: DateTime(2026, 11, 11),
        hexKey: _key,
      );
      expect(outcome.result, HistoryBackupResult.created);
      final copies = Directory(historyBackupDir(_tmp.path)).listSync();
      expect(copies, hasLength(1));
      expect(isPlainSqliteFile(copies.single.path), isFalse);
      expect(
        _rows(copies.single.path, hexKey: _key),
        _rows(path, hexKey: _key),
      );
    },
  );

  group('decryption (#1022)', () {
    test('turns the encrypted file back into a plain one, every row', () {
      final path = _seedPlain(dbPath());
      final before = _rows(path);
      encryptHistoryDatabase(path, _key);

      final run = decryptHistoryDatabase(path, _key);

      expect(run.result, HistoryEncryptionResult.decrypted);
      expect(isPlainSqliteFile(path), isTrue);
      expect(_rows(path), before);
      expect(File(historyEncryptionStagingPath(path)).existsSync(), isFalse);
      expect(
        decryptHistoryDatabase(path, _key).result,
        HistoryEncryptionResult.notNeeded,
      );
    });

    test('a wrong key keeps the encrypted original', () {
      final path = _seedPlain(dbPath());
      encryptHistoryDatabase(path, _key);
      final bytes = File(path).readAsBytesSync();

      final run = decryptHistoryDatabase(path, _otherKey);

      expect(run.result, HistoryEncryptionResult.failed);
      expect(File(path).readAsBytesSync(), bytes);
    });

    for (final step in ['write', 'verify', 'swap']) {
      test('failure in $step keeps the encrypted original', () {
        final path = _seedPlain(dbPath());
        final before = _rows(path);
        encryptHistoryDatabase(path, _key);
        const real = HistoryEncryptionOps.decrypt();
        Never fail() => throw const FileSystemException('disk full');
        final ops = HistoryEncryptionOps.decrypt(
          writeCopy: (s, t, k) {
            real.writeCopy(s, t, k);
            if (step == 'write') fail();
          },
          verifyCopy: (s, t, k) =>
              step == 'verify' ? fail() : real.verifyCopy(s, t, k),
          swapIn: (f, t) => step == 'swap' ? fail() : real.swapIn(f, t),
        );

        expect(
          decryptHistoryDatabase(path, _key, ops: ops).result,
          HistoryEncryptionResult.failed,
        );
        expect(isPlainSqliteFile(path), isFalse);
        expect(_rows(path, hexKey: _key), before);
        expect(File(historyEncryptionStagingPath(path)).existsSync(), isFalse);
        // The next start completes it.
        expect(
          decryptHistoryDatabase(path, _key).result,
          HistoryEncryptionResult.decrypted,
        );
        expect(_rows(path), before);
      });
    }

    test('a copy that is still encrypted is never swapped in', () {
      final path = _seedPlain(dbPath());
      encryptHistoryDatabase(path, _key);
      final bytes = File(path).readAsBytesSync();
      final run = decryptHistoryDatabase(
        path,
        _key,
        ops: HistoryEncryptionOps.decrypt(
          writeCopy: (s, t, k) => File(s).copySync(t),
        ),
      );
      expect(run.result, HistoryEncryptionResult.failed);
      expect(File(path).readAsBytesSync(), bytes);
    });
  });

  group('start-up wiring', () {
    setUp(() {
      paths.appDataDirOverride = _tmp.path;
      resetEncryptionSessionForTesting();
    });
    tearDown(() {
      paths.appDataDirOverride = null;
      resetEncryptionSessionForTesting();
    });

    Future<void> start(HistoryKeySource keySource) async {
      final db = HistoryDatabase(keySource: keySource);
      try {
        await db.customSelect('SELECT 1').get();
      } finally {
        await db.close();
      }
    }

    test('a new install creates the database encrypted', () async {
      await start(() async => _key);
      expect(isPlainSqliteFile(dbPath()), isFalse);
      await start(() async => _key);
    });

    test('a plain database is backed up, then encrypted once', () async {
      await start(() async => null); // before the key existed
      expect(isPlainSqliteFile(dbPath()), isTrue);

      await start(() async => _key);

      expect(isPlainSqliteFile(dbPath()), isFalse);
      expect(Directory(historyBackupDir(_tmp.path)).listSync(), isNotEmpty);
      final versionAfter = storedSchemaVersion(dbPath(), hexKey: _key);
      expect(versionAfter, historySchemaVersion);
    });

    test('switched off, the next start decrypts; on again encrypts', () async {
      await start(() async => _key);
      expect(isPlainSqliteFile(dbPath()), isFalse);
      final preference = EncryptionPreference(_tmp.path);

      expect(preference.setWanted(false), isTrue);
      resetEncryptionSessionForTesting(); // the restart
      final seen = <EncryptionConversionProgress?>[];
      void listener() => seen.add(encryptionConversionProgress.value);
      encryptionConversionProgress.addListener(listener);
      try {
        await start(() async => _key);
      } finally {
        encryptionConversionProgress.removeListener(listener);
      }

      expect(isPlainSqliteFile(dbPath()), isTrue);
      expect(seen, [
        const EncryptionConversionProgress(
          toPlain: true,
          step: EncryptionConversionStep.history,
        ),
        null,
      ]);
      expect(
        storedSchemaVersion(dbPath()),
        historySchemaVersion,
        reason: 'the plain file opens without a key',
      );
      // Off stays off: no start encrypts it again.
      await start(() async => _key);
      expect(isPlainSqliteFile(dbPath()), isTrue);

      preference.setWanted(true);
      resetEncryptionSessionForTesting();
      await start(() async => _key);
      expect(isPlainSqliteFile(dbPath()), isFalse);
    });

    test('switched off, a new install creates a plain database', () async {
      EncryptionPreference(_tmp.path).setWanted(false);
      resetEncryptionSessionForTesting();
      await start(() async => _key);
      expect(isPlainSqliteFile(dbPath()), isTrue);
    });

    test('switched off without the key, the encrypted file stays', () async {
      await start(() async => _key);
      final bytes = File(dbPath()).readAsBytesSync();
      EncryptionPreference(_tmp.path).setWanted(false);
      resetEncryptionSessionForTesting();

      await expectLater(
        start(() async => null),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
      expect(File(dbPath()).readAsBytesSync(), bytes);
    });

    test('an encrypted database without its key is left untouched', () async {
      await start(() async => _key);
      final bytes = File(dbPath()).readAsBytesSync();

      await expectLater(
        start(() async => null),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
      await expectLater(
        start(() async => throw StateError('store locked')),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
      await expectLater(
        start(() async => throw const HistoryKeyringUnavailableException()),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
      expect(File(dbPath()).readAsBytesSync(), bytes);
    });
  });
}
