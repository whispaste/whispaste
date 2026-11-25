// A lost data key (#1023): the encrypted history is set aside unchanged, the
// app opens an empty one, and the old file comes back once its key does.
// Fixed test keys in temp folders only; no system key store is touched.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_encryption.dart';
import 'package:whispaste/core/data/history_set_aside.dart';
import 'package:whispaste/services/path_service.dart' as paths;

final _key = 'ab' * 32;
final _otherKey = 'cd' * 32;

late Directory _tmp;

String _dbPath() => p.join(_tmp.path, 'history.db');

Future<void> _start(HistoryKeySource keySource, {String? text}) async {
  final db = HistoryDatabase(keySource: keySource);
  try {
    await db.customSelect('SELECT 1').get();
    if (text != null) await db.writeAppSetting('marker_text', text);
  } finally {
    await db.close();
  }
}

Future<String?> _read(HistoryKeySource keySource) async {
  final db = HistoryDatabase(keySource: keySource);
  try {
    return await db.readAppSetting('marker_text');
  } finally {
    await db.close();
  }
}

List<Directory> _setAsideFolders() {
  final root = Directory(historySetAsideDir(_tmp.path));
  if (!root.existsSync()) return const [];
  return root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Never _lost() => throw const HistoryKeyLostException();

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('wp_set_aside_');
    paths.appDataDirOverride = _tmp.path;
    takeHistoryStartupProblems();
  });
  tearDown(() {
    paths.appDataDirOverride = null;
    takeHistoryStartupProblems();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  test(
    'a lost key starts empty and keeps the encrypted file unchanged',
    () async {
      await _start(() async => _key, text: 'old data');
      File(p.join(_tmp.path, 'data_key.json')).writeAsStringSync('{"m":1}');
      final bytes = File(_dbPath()).readAsBytesSync();

      await _start(() async => _lost(), text: 'new data');

      final folders = _setAsideFolders();
      expect(folders, hasLength(1));
      final kept = File(p.join(folders.single.path, 'history.db'));
      expect(kept.readAsBytesSync(), bytes, reason: 'moved, never rewritten');
      expect(
        File(p.join(folders.single.path, 'data_key.json')).readAsStringSync(),
        '{"m":1}',
      );
      expect(takeHistoryStartupProblems(), [
        HistoryStartupProblem.keyLostStartedEmpty,
      ]);
      expect(hasSetAsideHistory(_tmp.path), isTrue);
      // The fresh history is in use and stays plain without a key.
      expect(isPlainSqliteFile(_dbPath()), isTrue);
      expect(await _read(() async => _lost()), 'new data');

      // A second start with the key still lost changes nothing more.
      await _start(() async => _lost());
      expect(_setAsideFolders(), hasLength(1));
      expect(kept.readAsBytesSync(), bytes);
      expect(takeHistoryStartupProblems(), isEmpty);
    },
  );

  test('another key leaves the set-aside file where it is', () async {
    await _start(() async => _key, text: 'old data');
    await _start(() async => _lost());
    takeHistoryStartupProblems();

    await _start(() async => _otherKey);

    expect(_setAsideFolders(), hasLength(1));
    expect(takeHistoryStartupProblems(), isEmpty);
  });

  test(
    'the old key brings the history back, the interim one is kept',
    () async {
      await _start(() async => _key, text: 'old data');
      await _start(() async => _lost(), text: 'interim data');
      takeHistoryStartupProblems();

      expect(await _read(() async => _key), 'old data');

      expect(takeHistoryStartupProblems(), [
        HistoryStartupProblem.setAsideHistoryRestored,
      ]);
      final folders = _setAsideFolders();
      expect(folders, hasLength(1));
      expect(folders.single.path, endsWith(historySetAsideInterimSuffix));
      final interim = p.join(folders.single.path, 'history.db');
      expect(isPlainSqliteFile(interim), isTrue);
      // The interim history is never matched against a key again.
      expect(setAsideHistoryFor(_tmp.path, _key), isNull);
      await _start(() async => _key);
      expect(takeHistoryStartupProblems(), isEmpty);
      expect(File(interim).existsSync(), isTrue);
    },
  );

  test('a locked keyring or an unreadable key still moves nothing', () async {
    await _start(() async => _key);
    final bytes = File(_dbPath()).readAsBytesSync();

    for (final source in <HistoryKeySource>[
      () async => null,
      () async => throw const HistoryKeyringUnavailableException(),
    ]) {
      await expectLater(
        _start(source),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
    }
    expect(_setAsideFolders(), isEmpty);
    expect(File(_dbPath()).readAsBytesSync(), bytes);
  });

  test(
    'a file that cannot be set aside stays and shows the start screen',
    () async {
      await _start(() async => _key);
      final bytes = File(_dbPath()).readAsBytesSync();
      // A file where the folder should be: the move fails.
      File(historySetAsideDir(_tmp.path)).writeAsStringSync('in the way');

      await expectLater(
        _start(() async => _lost()),
        throwsA(isA<HistoryKeyUnavailableException>()),
      );
      expect(File(_dbPath()).readAsBytesSync(), bytes);
      expect(takeHistoryStartupProblems(), isEmpty);
    },
  );

  test('without a set-aside history the sweeps run', () {
    expect(hasSetAsideHistory(_tmp.path), isFalse);
    Directory(
      p.join(historySetAsideDir(_tmp.path), 'empty'),
    ).createSync(recursive: true);
    expect(hasSetAsideHistory(_tmp.path), isFalse);
  });
}
