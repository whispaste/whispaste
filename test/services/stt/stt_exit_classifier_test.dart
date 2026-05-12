/// Unit tests for stt_exit_classifier.dart — pure function, no DI.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_exit_classifier.dart';

void main() {
  group('classifySttExitCode', () {
    test('exit code 3 → modelLoad on all platforms', () {
      expect(classifySttExitCode(3), SttExitKind.modelLoad);
    });

    test('exit code 0 → other on all platforms', () {
      expect(classifySttExitCode(0), SttExitKind.other);
    });

    test('exit code 1 → other on all platforms', () {
      expect(classifySttExitCode(1), SttExitKind.other);
    });

    test('exit code 99 → other on all platforms', () {
      expect(classifySttExitCode(99), SttExitKind.other);
    });

    test(
      'Windows NTSTATUS codes classify correctly (or other on non-Windows)',
      () {
        if (Platform.isWindows) {
          expect(classifySttExitCode(-1073741515), SttExitKind.dllMissing);
          expect(classifySttExitCode(-1073741511), SttExitKind.dllEntryPoint);
          expect(classifySttExitCode(-1073740791), SttExitKind.gpuFatal);
          expect(classifySttExitCode(-1073741819), SttExitKind.heapCorruption);
        } else {
          // On non-Windows all NTSTATUS codes map to other.
          expect(classifySttExitCode(-1073741515), SttExitKind.other);
          expect(classifySttExitCode(-1073741511), SttExitKind.other);
          expect(classifySttExitCode(-1073740791), SttExitKind.other);
          expect(classifySttExitCode(-1073741819), SttExitKind.other);
        }
      },
    );

    test('SttExitKind has six cases', () {
      expect(SttExitKind.values.length, 6);
    });
  });
}
