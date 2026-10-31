/// Unit tests for [FileVerificationService].
///
/// Covers:
///   1. Successful verification — file exists and hash matches.
///   2. Hash mismatch — file exists but digest does not match.
///   3. I/O error — file does not exist.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/file_verification_service.dart';

void main() {
  late Directory tempDir;
  const service = FileVerificationService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_fvs_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC1: Successful verification
  // ──────────────────────────────────────────────────────────────────────────

  group('successful verification', () {
    test('returns VerificationOk when digest matches expectedHash', () async {
      final content = [1, 2, 3, 4, 5, 6, 7, 8];
      final file = File('${tempDir.path}/good.bin');
      await file.writeAsBytes(content);

      // Compute the correct hash so we can assert it is accepted.
      final expectedHash = sha256.convert(content).toString();

      final result = await service.verify(file, expectedHash);

      expect(result, isA<VerificationOk>());
    });

    test(
      'returns VerificationOk for an empty file with matching hash',
      () async {
        final file = File('${tempDir.path}/empty.bin');
        await file.writeAsBytes([]);

        final expectedHash = sha256.convert([]).toString();

        final result = await service.verify(file, expectedHash);

        expect(result, isA<VerificationOk>());
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC2: Hash mismatch
  // ──────────────────────────────────────────────────────────────────────────

  group('hash mismatch', () {
    test('returns VerificationMismatch when digest does not match', () async {
      final file = File('${tempDir.path}/corrupt.bin');
      await file.writeAsBytes([0xde, 0xad, 0xbe, 0xef]);

      const wrongHash =
          '0000000000000000000000000000000000000000000000000000000000000000';

      final result = await service.verify(file, wrongHash);

      expect(result, isA<VerificationMismatch>());
      final mismatch = result as VerificationMismatch;
      expect(mismatch.expectedHash, wrongHash);
      expect(mismatch.actualHash, isNotEmpty);
      expect(mismatch.actualHash, isNot(equals(wrongHash)));
    });

    test(
      'VerificationMismatch carries both expected and actual hashes',
      () async {
        const bytes = [0xAA, 0xBB, 0xCC];
        final file = File('${tempDir.path}/mismatch.bin');
        await file.writeAsBytes(bytes);

        final actualHash = sha256.convert(bytes).toString();
        const expectedHash =
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

        final result = await service.verify(file, expectedHash);

        expect(result, isA<VerificationMismatch>());
        final mismatch = result as VerificationMismatch;
        expect(mismatch.actualHash, actualHash);
        expect(mismatch.expectedHash, expectedHash);
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC3: I/O error — file missing or unreadable
  // ──────────────────────────────────────────────────────────────────────────

  group('I/O error', () {
    test('returns VerificationIoError when file does not exist', () async {
      final missing = File('${tempDir.path}/does_not_exist.bin');

      const anyHash =
          '0000000000000000000000000000000000000000000000000000000000000000';
      final result = await service.verify(missing, anyHash);

      expect(result, isA<VerificationIoError>());
    });

    test('VerificationIoError carries the underlying error', () async {
      final missing = File('${tempDir.path}/ghost.bin');

      const anyHash =
          '0000000000000000000000000000000000000000000000000000000000000000';
      final result = await service.verify(missing, anyHash);

      expect(result, isA<VerificationIoError>());
      final ioError = result as VerificationIoError;
      expect(ioError.error, isNotNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Exhaustive pattern-matching (compile-time guarantee via sealed class)
  // ──────────────────────────────────────────────────────────────────────────

  group('sealed ADT exhaustiveness', () {
    test('all branches of VerificationResult are reachable', () async {
      // VerificationOk
      final goodFile = File('${tempDir.path}/ok.bin');
      await goodFile.writeAsBytes([42]);
      final hash = sha256.convert([42]).toString();
      expect(switch (await service.verify(goodFile, hash)) {
        VerificationOk() => 'ok',
        VerificationMismatch() => 'mismatch',
        VerificationIoError() => 'ioerror',
      }, 'ok');

      // VerificationMismatch
      expect(switch (await service.verify(goodFile, 'deadbeef' * 8)) {
        VerificationOk() => 'ok',
        VerificationMismatch() => 'mismatch',
        VerificationIoError() => 'ioerror',
      }, 'mismatch');

      // VerificationIoError
      final missing = File('${tempDir.path}/absent.bin');
      expect(switch (await service.verify(missing, hash)) {
        VerificationOk() => 'ok',
        VerificationMismatch() => 'mismatch',
        VerificationIoError() => 'ioerror',
      }, 'ioerror');
    });
  });
}
