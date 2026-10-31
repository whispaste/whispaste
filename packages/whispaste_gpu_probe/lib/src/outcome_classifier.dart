/// Pure outcome classifier for probe candidate results.
///
/// No I/O, no side effects. Maps raw signals (exit code, timeout flag,
/// transcript, language, WER) onto the [Outcome] taxonomy.
library;

import 'probe_types.dart';

// ---------------------------------------------------------------------------
// Named constants
// ---------------------------------------------------------------------------

/// WER fraction at or above which a transcription is classified as
/// [Outcome.wrongOutput].
///
/// A WER of 0.30 means 30 % of words were incorrect. This is intentionally
/// lenient: the probe is checking whether the backend *can* transcribe at all,
/// not whether it matches a gold standard perfectly. Values below this
/// threshold pass as [Outcome.ok]; at or above it trigger [Outcome.wrongOutput].
const double werWrongOutputThreshold = 0.30;

// ---------------------------------------------------------------------------
// Windows NTSTATUS codes that indicate a pre-main() startup failure
// ---------------------------------------------------------------------------

/// Exit codes that indicate the process failed before reaching `main()`.
///
/// These are Windows NTSTATUS codes where no user-space code ran at all.
/// Both the signed 32-bit form (as returned by Dart's `Process.exitCode`)
/// and the unsigned 32-bit form are included for robustness.
const Set<int> _failedToStartExitCodes = {
  // STATUS_DLL_NOT_FOUND (0xC0000135) — signed and unsigned forms.
  -1073741515, // signed
  0xC0000135, // unsigned = 3221225781
};

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Classifies a completed (or aborted) candidate run into an [Outcome].
///
/// Parameters:
/// - [exitCode]: the process exit code, or null if the process never started.
/// - [timedOut]: whether the run was killed due to a heartbeat/deadline timeout.
/// - [transcript]: the raw transcription text (may be empty).
/// - [detectedLanguage]: BCP-47 language code detected by Whisper, or null.
/// - [expectedLanguage]: BCP-47 language code that was requested.
/// - [wer]: pre-computed Word Error Rate (fraction), or null if not available.
///
/// Priority order:
/// 1. [timedOut] → [Outcome.hung]
/// 2. [_failedToStartExitCodes] → [Outcome.failedToStart]
/// 3. Non-zero exit code → [Outcome.crashed]
/// 4. Empty/whitespace transcript → [Outcome.wrongOutput]
/// 5. Language mismatch → [Outcome.wrongOutput]
/// 6. WER ≥ [werWrongOutputThreshold] → [Outcome.wrongOutput]
/// 7. Otherwise → [Outcome.ok]
Outcome classifyOutcome({
  required int? exitCode,
  required bool timedOut,
  required String transcript,
  required String? detectedLanguage,
  required String expectedLanguage,
  required double? wer,
}) {
  // 1. Timeout/stillstand takes precedence over everything else.
  if (timedOut) return Outcome.hung;

  // 2. Pre-main() startup failure (missing DLLs, bad binary).
  if (exitCode != null && _failedToStartExitCodes.contains(exitCode)) {
    return Outcome.failedToStart;
  }

  // 3. Abnormal exit code (process crashed or returned an error).
  if (exitCode != null && exitCode != 0) return Outcome.crashed;

  // 4. Empty transcript — nothing was produced.
  if (transcript.trim().isEmpty) return Outcome.wrongOutput;

  // 5. Wrong language detected.
  if (detectedLanguage != null && detectedLanguage != expectedLanguage) {
    return Outcome.wrongOutput;
  }

  // 6. WER at or above the threshold.
  if (wer != null && wer >= werWrongOutputThreshold) {
    return Outcome.wrongOutput;
  }

  // 7. All checks passed.
  return Outcome.ok;
}
