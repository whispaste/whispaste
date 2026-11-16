import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/data_key_backup.dart';
import 'package:whispaste/features/settings/data_key_restore_flow.dart';

/// Reading a dropped or chosen backup file (#1167): a valid file yields the
/// key and fingerprint; anything else is "not a backup", never an exception.
void main() {
  late Directory dir;
  final key = List<int>.generate(32, (i) => i * 7 % 256);

  setUp(() => dir = Directory.systemTemp.createTempSync('wp_restore_file'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final path = p.join(dir.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('a saved backup file restores the same key', () async {
    final path = write(
      'key.wpkey',
      dataKeyBackupFileContents(key, DateTime.utc(2026, 11, 10)).codeUnits,
    );
    final result = await readDataKeyBackupFile(path);
    expect(result, isA<DataKeyBackupValid>());
    expect((result as DataKeyBackupValid).bytes, key);
  });

  test('an oversized file is refused without reading it', () async {
    final path = write('big.wpkey', List<int>.filled(70 * 1024, 0x20));
    final result = await readDataKeyBackupFile(path);
    expect(
      (result as DataKeyBackupInvalid).error,
      DataKeyBackupError.notABackup,
    );
  });

  test('a missing or binary file is not a backup', () async {
    final missing = await readDataKeyBackupFile(p.join(dir.path, 'gone'));
    expect(
      (missing as DataKeyBackupInvalid).error,
      DataKeyBackupError.notABackup,
    );
    final binary = await readDataKeyBackupFile(
      write('audio.wav', [0xff, 0xfe, 0x00, 0xc3]),
    );
    expect(
      (binary as DataKeyBackupInvalid).error,
      DataKeyBackupError.notABackup,
    );
  });
}
