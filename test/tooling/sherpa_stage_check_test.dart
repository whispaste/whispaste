import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The stage check refuses a sherpa-onnx build that does not match
// scripts/sherpa-onnx.pin or pubspec.lock. The shell test builds fixture repos
// and asserts that mismatches fail and matching stages pass.
void main() {
  test(
    'stage check: mismatches fail, matching stages pass',
    () {
      final result = Process.runSync('bash', [
        'scripts/check-sherpa-stage.test.sh',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
    // Skipped on Windows on purpose: this shell test is driven only by
    // scripts/build-sherpa-onnx.sh (macOS/Linux). The Windows build,
    // build-sherpa-onnx.ps1, calls check-sherpa-stage.cmake directly and never
    // runs this script, so there is no Windows code path to verify here.
    skip: Platform.isWindows ? 'bash build script, not used on Windows' : null,
  );
}
