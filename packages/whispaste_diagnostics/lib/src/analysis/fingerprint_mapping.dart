/// Fingerprint mapping — maps whisper-server failure modes onto the 13
/// canonical Sentry crash fingerprints from crash_fingerprints.dart.
///
/// The string constants here mirror the wire values in the app's
/// `lib/core/logging/crash_fingerprints.dart` exactly (Sentry-deckungsgleich).
/// They are COPIED (not imported) because this pure-Dart package must not
/// depend on the Flutter app's lib/ tree. The contract test in AC3 asserts
/// value equality against the 13 PRD-pinned entries.
///
/// Mapping strategy (ported from whispaste-diagnose.ps1 verdict logic):
///   - Exit code 0xC0000135 / 0xC0000139 / signed equivalents → dll-missing
///   - Exit code 0xC0000374 / 0xC0000409 / SIGABRT(134) → heap-corruption
///   - stderr contains "CUDA out of memory" → cuda-oom (hardware audit)
///   - stderr contains GPU keywords (vulkan, cuda, gpu) → gpu-fatal
///   - Exit code 3 (whisper model-load failure) → model-abi-mismatch
///   - Any other non-zero exit → stt-exit-other
///   - Exit 0 or null → no fingerprint (healthy / not a crash)
library;

// ---------------------------------------------------------------------------
// 13 PRD-pinned canonical fingerprint wire values (from crash_fingerprints.dart)
// ---------------------------------------------------------------------------

/// All 13 PRD-pinned Sentry fingerprint wire values (Modul 6, reliability sprint).
///
/// Iteration order is irrelevant; used for inventory checks and contract tests.
const List<String> kPrdCrashFingerprints = <String>[
  'stt-exit-dll-missing',
  'stt-exit-gpu-fatal',
  'stt-exit-heap-corruption',
  'stt-exit-other',
  'stt-model-abi-mismatch',
  'stt-model-corrupted',
  'history-write-failed',
  'history-write-other',
  'server-download-failed',
  'server-download-stalled',
  'model-download-failed',
  'update-check-failed',
  'factory-reset-failed',
];

// Individual constants — mirror crash_fingerprints.dart wire values exactly.
const String _sttExitDllMissing = 'stt-exit-dll-missing';
const String _sttExitGpuFatal = 'stt-exit-gpu-fatal';
const String _sttExitHeapCorruption = 'stt-exit-heap-corruption';
const String _sttExitOther = 'stt-exit-other';
const String _sttModelAbiMismatch = 'stt-model-abi-mismatch';
const String _sttCudaOom = 'stt-cuda-oom';

// ---------------------------------------------------------------------------
// Exit-code constants (Windows NTSTATUS values, normalised to uint32 mask)
// ---------------------------------------------------------------------------

const int _kStatusDllNotFound = 0xC0000135;
const int _kStatusEntrypointNotFound = 0xC0000139;
const int _kStatusHeapCorruption = 0xC0000374;
const int _kStatusStackBufferOverrun = 0xC0000409;
const int _kStatusAccessViolation = 0xC0000005;

/// Normalises a potentially negative (signed 32-bit) exit code to its uint32
/// representation so comparisons with NTSTATUS hex values are unambiguous.
int _normalise(int code) => code & 0xFFFFFFFF;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Maps a whisper-server failure (exit code + optional stderr snippet) to a
/// canonical Sentry crash fingerprint string.
///
/// Returns `null` when there is no crash to report (exit code is `null` or 0).
///
/// [exitCode] — the exit code from the whisper-server process, or `null` when
/// the server did not exit (still running / healthy).
///
/// [stderrSnippet] — a short excerpt of stderr (first/last N lines). Used to
/// distinguish GPU-related crashes from generic failures when the exit code
/// alone is ambiguous.
String? mapFailureToFingerprint({
  required int? exitCode,
  String? stderrSnippet,
}) {
  if (exitCode == null || exitCode == 0) return null;

  final code = _normalise(exitCode);

  // DLL load failures: STATUS_DLL_NOT_FOUND or STATUS_ENTRYPOINT_NOT_FOUND.
  if (code == _kStatusDllNotFound || code == _kStatusEntrypointNotFound) {
    return _sttExitDllMissing;
  }

  // Heap/stack/memory corruption.
  if (code == _kStatusHeapCorruption ||
      code == _kStatusStackBufferOverrun ||
      exitCode == 134 /* SIGABRT on Unix */ ) {
    return _sttExitHeapCorruption;
  }

  // Access violation — GPU driver crash often manifests here.
  // Check stderr to refine before falling through to gpu-fatal.
  if (code == _kStatusAccessViolation) {
    return _classifyByStderr(stderrSnippet) ?? _sttExitOther;
  }

  // Model-load failure (whisper exit 3): intact binary, ABI mismatch.
  if (exitCode == 3) {
    return _sttModelAbiMismatch;
  }

  // Unknown exit — try to refine via stderr.
  return _classifyByStderr(stderrSnippet) ?? _sttExitOther;
}

/// Classifies a fingerprint from stderr content alone, or returns `null`
/// when stderr doesn't match any known failure pattern.
String? _classifyByStderr(String? stderr) {
  if (stderr == null || stderr.isEmpty) return null;
  final lower = stderr.toLowerCase();

  // CUDA OOM is high-priority: "cuda out of memory" / "out of memory" in a
  // CUDA context.
  if (lower.contains('cuda out of memory') ||
      (lower.contains('out of memory') && lower.contains('cuda'))) {
    return _sttCudaOom;
  }

  // GPU-fatal: any GPU-related keyword when the server crashes.
  if (lower.contains('vulkan') ||
      lower.contains('cuda') ||
      lower.contains('gpu fatal') ||
      lower.contains('ggml_vulkan')) {
    return _sttExitGpuFatal;
  }

  return null;
}
