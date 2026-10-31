/// Wall-clock budget for the verification stamp: from the second check on,
/// a file is verified by comparing the stamp, not by hashing again. The
/// functional guarantee (no second full hash) stays in
/// test/services/file_verification_stamp_test.dart.
///
/// Not part of a test run: see benchmarks/README.md.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/file_verification_service.dart';

void main() {
  late Directory tempDir;
  const service = FileVerificationService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_stamp_bench_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('from the second check on, verification takes at most 5 ms', () async {
    final bytes = List<int>.filled(8 * 1024 * 1024, 3);
    final file = File('${tempDir.path}/big.bin')..writeAsBytesSync(bytes);
    final expected = sha256.convert(bytes).toString();

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
