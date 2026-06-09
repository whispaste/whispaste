/// Unit tests for fingerprint_mapping.dart (AC3).
///
/// Verifies that the 13 canonical PRD fingerprint constants are present in the
/// mapping table and that failure-mode classification routes to the correct
/// fingerprint. Sentry-deckungsgleich requirement: the mapped string values
/// must match the app's crash_fingerprints.dart wire values exactly.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/analysis/fingerprint_mapping.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Inventory: all 13 PRD-pinned fingerprint constants are present
  // ---------------------------------------------------------------------------

  group('kPrdCrashFingerprints — 13 canonical fingerprints', () {
    test('contains exactly 13 entries', () {
      expect(kPrdCrashFingerprints.length, 13);
    });

    test('stt-exit-dll-missing is present', () {
      expect(kPrdCrashFingerprints, contains('stt-exit-dll-missing'));
    });

    test('stt-exit-gpu-fatal is present', () {
      expect(kPrdCrashFingerprints, contains('stt-exit-gpu-fatal'));
    });

    test('stt-exit-heap-corruption is present', () {
      expect(kPrdCrashFingerprints, contains('stt-exit-heap-corruption'));
    });

    test('stt-exit-other is present', () {
      expect(kPrdCrashFingerprints, contains('stt-exit-other'));
    });

    test('stt-model-abi-mismatch is present', () {
      expect(kPrdCrashFingerprints, contains('stt-model-abi-mismatch'));
    });

    test('stt-model-corrupted is present', () {
      expect(kPrdCrashFingerprints, contains('stt-model-corrupted'));
    });

    test('history-write-failed is present', () {
      expect(kPrdCrashFingerprints, contains('history-write-failed'));
    });

    test('history-write-other is present', () {
      expect(kPrdCrashFingerprints, contains('history-write-other'));
    });

    test('server-download-failed is present', () {
      expect(kPrdCrashFingerprints, contains('server-download-failed'));
    });

    test('server-download-stalled is present', () {
      expect(kPrdCrashFingerprints, contains('server-download-stalled'));
    });

    test('model-download-failed is present', () {
      expect(kPrdCrashFingerprints, contains('model-download-failed'));
    });

    test('update-check-failed is present', () {
      expect(kPrdCrashFingerprints, contains('update-check-failed'));
    });

    test('factory-reset-failed is present', () {
      expect(kPrdCrashFingerprints, contains('factory-reset-failed'));
    });
  });

  // ---------------------------------------------------------------------------
  // mapFailureToFingerprint — routing to canonical fingerprints
  // ---------------------------------------------------------------------------

  group('mapFailureToFingerprint', () {
    test('STATUS_DLL_NOT_FOUND (0xC0000135) → stt-exit-dll-missing', () {
      expect(
        mapFailureToFingerprint(exitCode: 0xC0000135),
        'stt-exit-dll-missing',
      );
    });

    test(
      'STATUS_DLL_NOT_FOUND as signed int (-1073741515) → stt-exit-dll-missing',
      () {
        expect(
          mapFailureToFingerprint(exitCode: -1073741515),
          'stt-exit-dll-missing',
        );
      },
    );

    test('STATUS_ENTRYPOINT_NOT_FOUND (0xC0000139) → stt-exit-dll-missing', () {
      expect(
        mapFailureToFingerprint(exitCode: 0xC0000139),
        'stt-exit-dll-missing',
      );
    });

    test('heap corruption (0xC0000374) → stt-exit-heap-corruption', () {
      expect(
        mapFailureToFingerprint(exitCode: 0xC0000374),
        'stt-exit-heap-corruption',
      );
    });

    test('stack buffer overrun (0xC0000409) → stt-exit-heap-corruption', () {
      expect(
        mapFailureToFingerprint(exitCode: 0xC0000409),
        'stt-exit-heap-corruption',
      );
    });

    test('SIGABRT (134) → stt-exit-heap-corruption', () {
      expect(
        mapFailureToFingerprint(exitCode: 134),
        'stt-exit-heap-corruption',
      );
    });

    test('stderr "CUDA out of memory" → stt-cuda-oom', () {
      expect(
        mapFailureToFingerprint(
          exitCode: 1,
          stderrSnippet: 'CUDA out of memory',
        ),
        'stt-cuda-oom',
      );
    });

    test('stderr "vulkan" with non-zero exit → stt-exit-gpu-fatal', () {
      expect(
        mapFailureToFingerprint(exitCode: 1, stderrSnippet: 'vulkan error'),
        'stt-exit-gpu-fatal',
      );
    });

    test('model-load exit 3 → stt-model-abi-mismatch', () {
      expect(mapFailureToFingerprint(exitCode: 3), 'stt-model-abi-mismatch');
    });

    test('unknown exit code → stt-exit-other', () {
      expect(mapFailureToFingerprint(exitCode: 42), 'stt-exit-other');
    });

    test('null exit code (no crash) → null', () {
      expect(mapFailureToFingerprint(exitCode: null), isNull);
    });

    test('exit 0 (success) → null', () {
      expect(mapFailureToFingerprint(exitCode: 0), isNull);
    });
  });
}
