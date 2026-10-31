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

  group('classifyModelLoadFailure', () {
    test(
      'stderr "failed to open <model>" → fileUnreadable, not abiMismatch',
      () {
        // Field repro FLUTTER_WHISPASTE-A0 (GTX 650 Kepler): the server
        // exits with code 3 but the real stderr is a file-open failure, not
        // an ABI drift. The SHA-256 was verified intact moments before, so
        // the old SHA-only heuristic mislabels this as a binary/model ABI
        // mismatch and triggers a pointless vulkan→cpu binary fallback.
        final stderr = <String>[
          'whisper_init_from_file_with_params_no_state: failed to open '
              r"'C:\Users\maikg\AppData\Roaming\WhisPaste\models\stt\"
              "ggml-small-q5_1.bin'",
          'error: failed to initialize whisper context',
        ];
        expect(
          classifyModelLoadFailure(stderr),
          ModelLoadFailureCause.fileUnreadable,
        );
      },
    );

    test('stderr without a file-open line → abiMismatch (default)', () {
      final stderr = <String>['error: failed to initialize whisper context'];
      expect(
        classifyModelLoadFailure(stderr),
        ModelLoadFailureCause.abiMismatch,
      );
    });

    test('empty stderr → abiMismatch (no evidence of a file-access fault)', () {
      expect(
        classifyModelLoadFailure(const <String>[]),
        ModelLoadFailureCause.abiMismatch,
      );
    });

    test('match is case-insensitive and substring-based', () {
      final stderr = <String>['WHISPER: FAILED TO OPEN model'];
      expect(
        classifyModelLoadFailure(stderr),
        ModelLoadFailureCause.fileUnreadable,
      );
    });
  });
}
