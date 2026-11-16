// `whispaste --transcribe-file --replacements` reads the history over a
// read-only connection (#1647): it never changes the file an open WhisPaste
// uses, and refuses files it cannot read safely.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_encryption.dart';
import 'package:whispaste/services/headless/headless_history_reader.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

final _key = 'ab' * 32;
final _createdAt = DateTime.utc(2026, 11, 1, 9);

late Directory _tmp;

String _historyPath() => p.join(_tmp.path, 'history.db');

/// A history written by the app's own database class, with three rules:
/// "b" placed first by the user, then "a" and "c" in creation order.
Future<void> _seedHistory(String path) async {
  final db = HistoryDatabase.forTesting(NativeDatabase(File(path)));
  try {
    await db.writeReplacements([
      ReplacementWrite(
        id: 'a',
        triggers: const ['whisper paste', 'wisper paste'],
        replacement: 'WhisPaste',
        createdAt: _createdAt,
      ),
      ReplacementWrite(
        id: 'b',
        triggers: const ['kubernetes'],
        replacement: 'Kubernetes',
        createdAt: _createdAt,
        matchMode: 'fuzzy',
        fuzzyThreshold: 0.8,
      ),
      ReplacementWrite(
        id: 'c',
        triggers: const ['mfg'],
        replacement: 'Mit freundlichen Grüßen',
        createdAt: _createdAt,
      ),
    ]);
    await db.reorderReplacements(['b']);
  } finally {
    await db.close();
  }
}

/// Every file of the history (main file, WAL, journal) with its bytes.
Map<String, List<int>> _snapshot() => {
  for (final f in _tmp.listSync().whereType<File>())
    p.basename(f.path): f.readAsBytesSync(),
};

Future<String?> _noKey() async => null;

Future<List<TextReplacementRule>> _read({
  Future<String?> Function() keySource = _noKey,
  bool isWindows = false,
}) => readReplacementRulesReadOnly(
  appDataDir: _tmp.path,
  keySource: keySource,
  isWindows: isWindows,
);

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('wp_headless_db_'));
  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  test('no history yet means no rules, and nothing is created', () async {
    expect(await _read(), isEmpty);
    expect(_tmp.listSync(), isEmpty);
  });

  test(
    'reads the rules in the app order and leaves every byte as it was',
    () async {
      await _seedHistory(_historyPath());
      final before = _snapshot();

      final rules = await _read();

      expect(
        [for (final r in rules) r.replacement],
        ['Kubernetes', 'WhisPaste', 'Mit freundlichen Grüßen'],
      );
      expect(rules[0].matchMode, TextReplacementMatchMode.fuzzy);
      expect(rules[0].fuzzyThreshold, 0.8);
      expect(rules[1].triggers, ['whisper paste', 'wisper paste']);
      expect(rules[1].matchMode, TextReplacementMatchMode.exact);
      expect(_snapshot(), before);
    },
  );

  test('reads while another connection holds the write lock', () async {
    await _seedHistory(_historyPath());
    // Stands in for the running app in the middle of a write.
    final writer = sqlite3.open(_historyPath());
    addTearDown(writer.close);
    writer.execute('BEGIN IMMEDIATE');
    addTearDown(() => writer.execute('ROLLBACK'));

    final rules = await _read();

    expect(rules, hasLength(3));
  });

  test('a history at another schema version is refused unchanged', () async {
    await _seedHistory(_historyPath());
    final raw = sqlite3.open(_historyPath());
    raw.execute('PRAGMA user_version = ${historySchemaVersion - 1}');
    raw.close();
    final before = _snapshot();

    await expectLater(
      _read(),
      throwsA(
        isA<HeadlessHistoryVersionException>().having(
          (e) => e.storedVersion,
          'storedVersion',
          historySchemaVersion - 1,
        ),
      ),
    );
    expect(_snapshot(), before);
  });

  test('an encrypted history needs the key and opens with it', () async {
    await _seedHistory(_historyPath());
    final run = encryptHistoryDatabase(_historyPath(), _key);
    expect(run.result, HistoryEncryptionResult.encrypted);

    await expectLater(_read(), throwsA(isA<HistoryKeyUnavailableException>()));
    expect(await _read(keySource: () async => _key), hasLength(3));
  });

  test('the key is asked only for an encrypted file', () async {
    await _seedHistory(_historyPath());
    var asked = 0;
    await _read(
      keySource: () async {
        asked++;
        return null;
      },
    );
    expect(asked, 0);
  });

  test('reads the old nested Windows file while its move is pending', () async {
    final nested = nestedHistoryPath(_tmp.path);
    Directory(p.dirname(nested)).createSync(recursive: true);
    await _seedHistory(nested);

    expect(headlessHistoryPath(_tmp.path, isWindows: true), nested);
    expect(await _read(isWindows: true), hasLength(3));
    expect(headlessHistoryPath(_tmp.path, isWindows: false), _historyPath());
  });
}
