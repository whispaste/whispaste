/// Load-time check of the Parakeet GGUF: exact size first, then the stamp.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_gguf_check_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  ParakeetGgufFile expectedFor(List<int> bytes) => ParakeetGgufFile(
    quant: ParakeetGgufQuant.q8Zero,
    sizeBytes: bytes.length,
    sha256: sha256.convert(bytes).toString(),
  );

  test(
    'a file of the pinned size and hash is ok, also on the second load',
    () async {
      final bytes = List<int>.filled(64 * 1024, 5);
      final path = '${tempDir.path}/model.bin';
      File(path).writeAsBytesSync(bytes);
      final expected = expectedFor(bytes);

      expect(await verifyParakeetGguf(path, expected), ParakeetGgufCheck.ok);
      expect(await verifyParakeetGguf(path, expected), ParakeetGgufCheck.ok);
    },
  );

  test('a file shortened by one byte is a size mismatch', () async {
    final bytes = List<int>.filled(64 * 1024, 5);
    final path = '${tempDir.path}/model.bin';
    File(path).writeAsBytesSync(bytes);
    final expected = expectedFor(bytes);
    expect(await verifyParakeetGguf(path, expected), ParakeetGgufCheck.ok);

    File(path).writeAsBytesSync(bytes.sublist(0, bytes.length - 1));

    expect(
      await verifyParakeetGguf(path, expected),
      ParakeetGgufCheck.sizeMismatch,
    );
  });

  test('a missing file is reported as missing', () async {
    final bytes = List<int>.filled(16, 1);
    expect(
      await verifyParakeetGguf('${tempDir.path}/none.bin', expectedFor(bytes)),
      ParakeetGgufCheck.missing,
    );
  });
}
