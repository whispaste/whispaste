/// Golden-tests for [classifyOutcome] — pure function, no I/O.
///
/// Table-driven approach mirrors `test/services/stt/stt_exit_classifier_test.dart`
/// in the app repo.
library;

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Happy-path
  // ---------------------------------------------------------------------------
  group('classifyOutcome — ok', () {
    test('clean exit 0, valid transcript, correct language, low WER → ok', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'hallo welt',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: 0.05,
        ),
        Outcome.ok,
      );
    });

    test('exit 0 with null WER (not measured) → ok', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'guten morgen',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.ok,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // failedToStart
  // ---------------------------------------------------------------------------
  group('classifyOutcome — failedToStart', () {
    test(
      'exit 0xC0000135 (STATUS_DLL_NOT_FOUND as signed int) → failedToStart',
      () {
        // 0xC0000135 = -1073741515 as a 32-bit signed integer.
        expect(
          classifyOutcome(
            exitCode: -1073741515,
            timedOut: false,
            transcript: '',
            detectedLanguage: null,
            expectedLanguage: 'de',
            wer: null,
          ),
          Outcome.failedToStart,
        );
      },
    );

    test(
      'exit 0xC0000135 expressed as positive unsigned int → failedToStart',
      () {
        // Some Windows APIs return the unsigned form.
        expect(
          classifyOutcome(
            exitCode: 0xC0000135,
            timedOut: false,
            transcript: '',
            detectedLanguage: null,
            expectedLanguage: 'de',
            wer: null,
          ),
          Outcome.failedToStart,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // crashed
  // ---------------------------------------------------------------------------
  group('classifyOutcome — crashed', () {
    test('exit code -1 (generic crash) → crashed', () {
      expect(
        classifyOutcome(
          exitCode: -1,
          timedOut: false,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.crashed,
      );
    });

    test('exit code 1 (abnormal exit) → crashed', () {
      expect(
        classifyOutcome(
          exitCode: 1,
          timedOut: false,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.crashed,
      );
    });

    test('exit code 139 (SIGSEGV on Linux) → crashed', () {
      expect(
        classifyOutcome(
          exitCode: 139,
          timedOut: false,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.crashed,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // hung
  // ---------------------------------------------------------------------------
  group('classifyOutcome — hung', () {
    test('timedOut flag set, exit 0 → hung', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: true,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.hung,
      );
    });

    test('timedOut flag set, exit code null → hung', () {
      expect(
        classifyOutcome(
          exitCode: null,
          timedOut: true,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.hung,
      );
    });

    // timedOut takes precedence over a non-zero exit code
    test('timedOut flag set, non-zero exit → hung (timeout wins)', () {
      expect(
        classifyOutcome(
          exitCode: -1,
          timedOut: true,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.hung,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // wrongOutput
  // ---------------------------------------------------------------------------
  group('classifyOutcome — wrongOutput', () {
    test('empty transcript → wrongOutput', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: '',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.wrongOutput,
      );
    });

    test('whitespace-only transcript → wrongOutput', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: '   ',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: null,
        ),
        Outcome.wrongOutput,
      );
    });

    test('wrong language detected → wrongOutput', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'hello world',
          detectedLanguage: 'en',
          expectedLanguage: 'de',
          wer: 0.1,
        ),
        Outcome.wrongOutput,
      );
    });

    test('WER exactly at threshold → wrongOutput', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'some words',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: werWrongOutputThreshold,
        ),
        Outcome.wrongOutput,
      );
    });

    test('WER above threshold → wrongOutput', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'garbled output',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: werWrongOutputThreshold + 0.01,
        ),
        Outcome.wrongOutput,
      );
    });

    test('WER just below threshold → ok', () {
      expect(
        classifyOutcome(
          exitCode: 0,
          timedOut: false,
          transcript: 'hallo welt',
          detectedLanguage: 'de',
          expectedLanguage: 'de',
          wer: werWrongOutputThreshold - 0.01,
        ),
        Outcome.ok,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // WER threshold is a named constant (AC4)
  // ---------------------------------------------------------------------------
  group('werWrongOutputThreshold', () {
    test('threshold is between 0 and 1 exclusive', () {
      expect(werWrongOutputThreshold, greaterThan(0.0));
      expect(werWrongOutputThreshold, lessThan(1.0));
    });
  });

  // ---------------------------------------------------------------------------
  // CandidateResult evidence fields (AC2)
  // ---------------------------------------------------------------------------
  group('CandidateResult evidence fields', () {
    test('can be constructed with all evidence fields populated', () {
      const result = CandidateResult(
        candidateId: 'test-candidate',
        outcome: Outcome.ok,
        exitCode: 0,
        durationMs: 1234,
        transcribedText: 'hallo welt',
        stderrTail: '',
        realtimeFactor: 0.42,
        modelId: 'ggml-small-q5_1',
        backend: 'cuda',
        wer: 0.05,
        peakVramMb: 512,
      );

      expect(result.candidateId, 'test-candidate');
      expect(result.outcome, Outcome.ok);
      expect(result.exitCode, 0);
      expect(result.durationMs, 1234);
      expect(result.transcribedText, 'hallo welt');
      expect(result.stderrTail, '');
      expect(result.realtimeFactor, 0.42);
      expect(result.modelId, 'ggml-small-q5_1');
      expect(result.backend, 'cuda');
      expect(result.wer, 0.05);
      expect(result.peakVramMb, 512);
    });

    test('optional evidence fields can be null', () {
      const result = CandidateResult(
        candidateId: 'minimal',
        outcome: Outcome.skipped,
      );

      expect(result.stderrTail, isNull);
      expect(result.realtimeFactor, isNull);
      expect(result.modelId, isNull);
      expect(result.backend, isNull);
      expect(result.wer, isNull);
      expect(result.peakVramMb, isNull);
    });
  });
}
