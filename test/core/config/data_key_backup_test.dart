import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/data_key_backup.dart';
import 'package:whispaste/core/config/data_key_store.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/features/settings/data_key_backup_flow.dart'
    show writeDataKeyBackupFile;

/// In-memory stand-in for the system key store.
class _FakeSecureStore extends SecureKeyStore {
  _FakeSecureStore() : super(null, () async => KeyringAvailability.usable);

  final values = <String, String>{};

  @override
  Future<String?> readKey(String key) async => values[key];

  @override
  Future<void> writeKey(String key, String value) async => values[key] = value;

  @override
  Future<void> deleteKey(String key) async => values.remove(key);
}

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

List<int> _key(int seed) =>
    List<int>.generate(32, (i) => (i * 31 + seed) & 0xff);

DataKeyBackupError? _error(DataKeyBackupParse parse) =>
    parse is DataKeyBackupInvalid ? parse.error : null;

void main() {
  group('recovery code', () {
    test('is 56 characters in groups of four and reads back the key', () {
      for (final seed in [0, 1, 77, 255]) {
        final key = _key(seed);
        final code = dataKeyRecoveryCode(key);
        expect(code.split('-'), hasLength(14));
        expect(code.replaceAll('-', ''), hasLength(dataKeyRecoveryCodeLength));
        final parsed = parseDataKeyRecoveryCode(code);
        expect(parsed, isA<DataKeyBackupValid>());
        expect((parsed as DataKeyBackupValid).bytes, key);
        expect(parsed.fingerprint, dataKeyFingerprint(key));
      }
    });

    test('every single-character typo fails the checksum', () {
      final code = dataKeyRecoveryCode(_key(9)).replaceAll('-', '');
      for (var i = 0; i < code.length; i++) {
        final other = _alphabet[(_alphabet.indexOf(code[i]) + 1) % 32];
        final typo = code.replaceRange(i, i + 1, other);
        expect(
          _error(parseDataKeyRecoveryCode(typo)),
          DataKeyBackupError.checksumMismatch,
          reason: 'position $i',
        );
      }
    });

    test('swapped neighbours fail the checksum', () {
      final code = dataKeyRecoveryCode(_key(3)).replaceAll('-', '');
      var swaps = 0;
      for (var i = 0; i < code.length - 1; i++) {
        if (code[i] == code[i + 1]) continue;
        final swapped =
            code.substring(0, i) +
            code[i + 1] +
            code[i] +
            code.substring(i + 2);
        expect(
          _error(parseDataKeyRecoveryCode(swapped)),
          DataKeyBackupError.checksumMismatch,
        );
        swaps++;
      }
      expect(swaps, greaterThan(0));
    });

    test('handwriting tolerance: case, spaces, dashes, I/L/O', () {
      final key = _key(42);
      final code = dataKeyRecoveryCode(key);
      final sloppy = code
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('1', 'l')
          .replaceAll('0', 'O');
      final parsed = parseDataKeyRecoveryCode('  $sloppy\n');
      expect((parsed as DataKeyBackupValid).bytes, key);
      final withI = code.replaceAll('1', 'I');
      expect(
        (parseDataKeyRecoveryCode(withI) as DataKeyBackupValid).bytes,
        key,
      );
    });

    test('rejects empty, wrong length and foreign characters', () {
      final code = dataKeyRecoveryCode(_key(5));
      expect(_error(parseDataKeyRecoveryCode(' - ')), DataKeyBackupError.empty);
      expect(
        _error(parseDataKeyRecoveryCode(code.substring(0, code.length - 1))),
        DataKeyBackupError.wrongLength,
      );
      expect(
        _error(parseDataKeyRecoveryCode('${code}A')),
        DataKeyBackupError.wrongLength,
      );
      expect(
        _error(parseDataKeyRecoveryCode(code.replaceFirst(RegExp('.'), 'U'))),
        DataKeyBackupError.invalidCharacter,
      );
    });

    test('rejects keys of the wrong size', () {
      expect(() => dataKeyRecoveryCode([1, 2, 3]), throwsArgumentError);
    });
  });

  group('backup file', () {
    final createdAt = DateTime.utc(2026, 11, 10, 12);

    test('holds the same key as the code', () {
      final key = _key(11);
      final contents = dataKeyBackupFileContents(key, createdAt);
      final json = jsonDecode(contents) as Map<String, Object?>;
      expect(json['recoveryCode'], dataKeyRecoveryCode(key));
      final parsed = parseDataKeyBackupFile(contents);
      expect((parsed as DataKeyBackupValid).bytes, key);
    });

    test('rejects what is not a readable backup', () {
      final key = _key(12);
      final json =
          jsonDecode(dataKeyBackupFileContents(key, createdAt))
              as Map<String, Object?>;
      String with_(Map<String, Object?> changes) =>
          jsonEncode({...json, ...changes});

      expect(_error(parseDataKeyBackupFile('')), DataKeyBackupError.empty);
      expect(
        _error(parseDataKeyBackupFile('not json')),
        DataKeyBackupError.notABackup,
      );
      expect(
        _error(parseDataKeyBackupFile(with_({'format': 'other'}))),
        DataKeyBackupError.notABackup,
      );
      expect(
        _error(parseDataKeyBackupFile(with_({'version': 2}))),
        DataKeyBackupError.unsupportedVersion,
      );
      expect(
        _error(parseDataKeyBackupFile(with_({'recoveryCode': null}))),
        DataKeyBackupError.notABackup,
      );
      expect(
        _error(
          parseDataKeyBackupFile(
            with_({'fingerprint': dataKeyFingerprint(_key(13))}),
          ),
        ),
        DataKeyBackupError.checksumMismatch,
      );
    });
  });

  test('parsed results never print the key', () {
    final key = _key(20);
    final parsed = parseDataKeyRecoveryCode(dataKeyRecoveryCode(key));
    final printed = parsed.toString();
    expect(printed, isNot(contains(dataKeyRecoveryCode(key))));
    expect(printed, isNot(contains(dataKeyFingerprint(key))));
    expect(printed, isNot(contains(base64Encode(key))));
  });

  group('hand-over with the data-key store', () {
    late Directory dir;
    late _FakeSecureStore secure;

    DataKeyStore store() => DataKeyStore(
      secure,
      dataDir: () => dir.path,
      isLinux: false,
      posix: !Platform.isWindows,
    );

    Map<String, Object?> marker() =>
        jsonDecode(
              File(p.join(dir.path, dataKeyMarkerFileName)).readAsStringSync(),
            )
            as Map<String, Object?>;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp_data_key_backup_');
      secure = _FakeSecureStore();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('code and saved file read back to the marker fingerprint', () async {
      final ready = await store().obtain() as DataKeyReady;
      final fingerprint = marker()['fingerprint'];

      final fromCode = parseDataKeyRecoveryCode(
        dataKeyRecoveryCode(ready.key.bytes),
      );
      expect((fromCode as DataKeyBackupValid).fingerprint, fingerprint);

      final path = p.join(dir.path, 'backup', dataKeyBackupFileName);
      Directory(p.dirname(path)).createSync();
      final saved = await writeDataKeyBackupFile(
        path,
        ready.key.bytes,
        DateTime.now(),
        posix: !Platform.isWindows,
      );
      expect(saved, isTrue);
      if (!Platform.isWindows) {
        expect(File(path).statSync().mode & 0x1ff, 0x180);
      }
      final fromFile = parseDataKeyBackupFile(File(path).readAsStringSync());
      expect((fromFile as DataKeyBackupValid).fingerprint, fingerprint);
      expect(fromFile.bytes, fromCode.bytes);
    });

    test('a failed file write reports false and leaves nothing', () async {
      final ready = await store().obtain() as DataKeyReady;
      final path = p.join(dir.path, 'missing', 'x.wpkey');
      final saved = await writeDataKeyBackupFile(
        path,
        ready.key.bytes,
        DateTime.now(),
        posix: !Platform.isWindows,
      );
      expect(saved, isFalse);
      expect(File(path).existsSync(), isFalse);
    });

    test('records the backup time only for the current key', () async {
      final s = store();
      final ready = await s.obtain() as DataKeyReady;
      expect(s.recordedBackupAt(), isNull);

      final at = DateTime.utc(2026, 11, 10, 9, 30);
      expect(await s.recordBackup(ready.key, at), isTrue);
      expect(store().recordedBackupAt(), at);
      expect(marker()['fingerprint'], dataKeyFingerprint(ready.key.bytes));

      // A key from another installation is not this one's backup.
      final otherDir = Directory.systemTemp.createTempSync('wp_data_key_o_');
      addTearDown(() => otherDir.deleteSync(recursive: true));
      final other =
          await DataKeyStore(
                _FakeSecureStore(),
                dataDir: () => otherDir.path,
                isLinux: false,
                posix: !Platform.isWindows,
              ).obtain()
              as DataKeyReady;
      expect(await s.recordBackup(other.key, DateTime.now()), isFalse);
      expect(store().recordedBackupAt(), at);
    });

    test('a new key starts without a backup time', () async {
      final s = store();
      final ready = await s.obtain() as DataKeyReady;
      await s.recordBackup(ready.key, DateTime.utc(2026, 11, 10));

      File(p.join(dir.path, dataKeyMarkerFileName)).deleteSync();
      secure.values.clear();
      final fresh = store();
      final next = await fresh.obtain() as DataKeyReady;
      expect(next.created, isTrue);
      expect(fresh.recordedBackupAt(), isNull);
    });

    test('no backup is recorded without a marker', () async {
      final s = store();
      final ready = await s.obtain() as DataKeyReady;
      File(p.join(dir.path, dataKeyMarkerFileName)).deleteSync();
      expect(await s.recordBackup(ready.key, DateTime.now()), isFalse);
    });
  });
}
