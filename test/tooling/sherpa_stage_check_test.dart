import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The stage check refuses a sherpa-onnx build that does not match
// scripts/sherpa-onnx.pin or pubspec.lock. The shell test builds fixture repos
// and asserts that mismatches fail and matching stages pass.
void main() {
  test('stage check: mismatches fail, matching stages pass', () {
    final result = Process.runSync('bash', [
      'scripts/check-sherpa-stage.test.sh',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
