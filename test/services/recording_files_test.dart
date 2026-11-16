/// The capture step reads the finished WAV in 1 MB steps into one buffer of
/// its size (#1642): the bytes are exactly the file's, whatever its length.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording_files.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('recording_files'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List pattern(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) i * 31 % 251]);

  for (final length in [0, 1, 1024 * 1024, 2 * 1024 * 1024 + 7]) {
    test('reads a file of $length bytes byte for byte', () async {
      final path = '${dir.path}/whispaste_$length.wav';
      final content = pattern(length);
      File(path).writeAsBytesSync(content);

      expect(await const RealRecordingFiles().readAsBytes(path), content);
    });
  }

  test('a missing file fails like File.readAsBytes', () async {
    await expectLater(
      readFileChunked('${dir.path}/missing.wav'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
