/// Tests for the verification stamp: one full SHA-256 per file version, later
/// checks only compare the stamp with size and modification time.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/file_verification_service.dart';

/// Counts the full hashes that [FileVerificationService.verify] performs.
class _CountingVerifier extends FileVerificationService {
  _CountingVerifier();

  int fullHashes = 0;

  @override
  Future<VerificationResult> verify(File file, String expectedHash) {
    fullHashes++;
    return super.verify(file, expectedHash);
  }
}

void main() {
  late Directory tempDir;
  const service = FileVerificationService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_stamp_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File writeBytes(String name, List<int> bytes) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(bytes);

  String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

  test(
    'the first check hashes the file and writes a stamp next to it',
    () async {
      final bytes = List<int>.filled(4096, 7);
      final file = writeBytes('model.bin', bytes);

      final result = await service.verifyStamped(file, hashOf(bytes));

      expect(result, isA<VerificationOk>());
      expect(File(verifiedStampPath(file.path)).existsSync(), isTrue);
    },
  );

  test(
    'a later check with unchanged size and mtime does not hash again',
    () async {
      final bytes = List<int>.filled(4096, 7);
      final file = writeBytes('model.bin', bytes);
      final counting = _CountingVerifier();

      expect(
        await counting.verifyStamped(file, hashOf(bytes)),
        isA<VerificationOk>(),
      );
      expect(
        await counting.verifyStamped(file, hashOf(bytes)),
        isA<VerificationOk>(),
      );

      expect(counting.fullHashes, 1);
    },
  );

  test('a file shortened by one byte is rejected even with a stamp', () async {
    final bytes = List<int>.filled(4096, 7);
    final file = writeBytes('model.bin', bytes);
    expect(
      await service.verifyStamped(file, hashOf(bytes)),
      isA<VerificationOk>(),
    );

    final raf = file.openSync(mode: FileMode.append);
    raf.truncateSync(bytes.length - 1);
    raf.closeSync();

    expect(
      await service.verifyStamped(file, hashOf(bytes)),
      isNot(isA<VerificationOk>()),
    );
  });

  test('a changed modification time forces a new hash', () async {
    final bytes = List<int>.filled(4096, 7);
    final file = writeBytes('model.bin', bytes);
    final counting = _CountingVerifier();
    await counting.verifyStamped(file, hashOf(bytes));

    file.writeAsBytesSync(List<int>.filled(4096, 9));
    file.setLastModifiedSync(DateTime(2001));

    final result = await counting.verifyStamped(file, hashOf(bytes));
    expect(result, isA<VerificationMismatch>());
    expect(counting.fullHashes, 2);
  });

  test('a different expected hash does not reuse an old stamp', () async {
    final bytes = List<int>.filled(4096, 7);
    final file = writeBytes('model.bin', bytes);
    await service.verifyStamped(file, hashOf(bytes));

    final result = await service.verifyStamped(file, hashOf([1, 2, 3]));

    expect(result, isA<VerificationMismatch>());
  });

  test('a missing file is an I/O error and writes no stamp', () async {
    final file = File('${tempDir.path}/absent.bin');

    final result = await service.verifyStamped(file, hashOf([1]));

    expect(result, isA<VerificationIoError>());
    expect(File(verifiedStampPath(file.path)).existsSync(), isFalse);
  });

  test('a corrupt stamp file is ignored and the file is hashed', () async {
    final bytes = List<int>.filled(4096, 7);
    final file = writeBytes('model.bin', bytes);
    File(verifiedStampPath(file.path)).writeAsStringSync('{not json');

    expect(
      await service.verifyStamped(file, hashOf(bytes)),
      isA<VerificationOk>(),
    );
  });

  test('from the second check on, verification takes at most 5 ms', () async {
    final bytes = List<int>.filled(8 * 1024 * 1024, 3);
    final file = writeBytes('big.bin', bytes);
    final expected = hashOf(bytes);

    final first = Stopwatch()..start();
    final firstResult = await service.verifyStamped(file, expected);
    first.stop();

    final second = Stopwatch()..start();
    final secondResult = await service.verifyStamped(file, expected);
    second.stop();

    expect(firstResult, isA<VerificationOk>());
    expect(secondResult, isA<VerificationOk>());
    expect(second.elapsedMicroseconds, lessThanOrEqualTo(5000));
    // The first check does the full hash and must be the slower one.
    expect(first.elapsedMicroseconds, greaterThan(second.elapsedMicroseconds));
  });
}
