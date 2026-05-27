/// Central inventory of Sentry crash-report fingerprint constants.
///
/// Every `CrashReporter.captureError` call **must** pass one of the
/// constants from this file — inline string literals are forbidden by
/// API (the `fingerprint` parameter on `captureError` is `required`).
///
/// Why this exists:
/// - Sentry's Free-Tier issue quota is shared with every other whispaste
///   project. Typo-induced fingerprint drift (e.g. `'stt-exit-other'` vs
///   `'stt_exit_other'`) silently shards what should be one issue cluster
///   into two — burning quota and obscuring diagnosis.
/// - Code review can now spot a missing or mismatched fingerprint by
///   constant name instead of having to recognise a magic string.
/// - The PRD-inventory subset is contract-pinned by
///   `test/core/logging/crash_fingerprints_test.dart` against the
///   reliability-sprint PRD table (Modul 6 „CrashFingerprint").
///
/// String-value naming convention: `<domain>-<subdomain>-<kind>` (lowercase,
/// hyphen-separated). The string is the Sentry-wire value; the Dart constant
/// name is lowerCamelCase to satisfy `constant_identifier_names`.
///
/// Source of truth: `.scratch/reliability-sprint/prd.md` — Modul 6.
library;

// ---------------------------------------------------------------------------
// PRD inventory — 13 canonical fingerprints from the reliability sprint.
// DO NOT change these wire values without updating the contract test.
// ---------------------------------------------------------------------------

/// `STATUS_DLL_NOT_FOUND` / DLL entry-point exits from `whisper-server`.
/// Collapses the WP-74 + WP-75 cluster (50 users, 70 events at PRD time).
const String sttExitDllMissing = 'stt-exit-dll-missing';

/// GPU-fatal exit from `whisper-server` (driver crash, CUDA OOM-side abort,
/// Vulkan validation kill). Distinct from `sttExitHeapCorruption` so the
/// GPU-fallback-policy can be diagnosed separately.
const String sttExitGpuFatal = 'stt-exit-gpu-fatal';

/// Heap/stack corruption exits (Windows STATUS_HEAP_CORRUPTION,
/// STATUS_STACK_BUFFER_OVERRUN, ABRT on Unix). Often manifests as a
/// CPU-fallback retry candidate.
const String sttExitHeapCorruption = 'stt-exit-heap-corruption';

/// Catch-all for `whisper-server` exits that the classifier could not
/// place into a more specific bucket. Keeps every unclassified exit code
/// in one issue instead of one-per-exit-code.
const String sttExitOther = 'stt-exit-other';

/// `modelLoad` exit when the model SHA-256 matches expected — i.e. the
/// model file is intact but the installed `whisper-server` binary cannot
/// load it (ABI mismatch after a server-variant change). This is the
/// WP-32 cluster (75 users, 186 events at PRD time).
const String sttModelAbiMismatch = 'stt-model-abi-mismatch';

/// `modelLoad` exit when the model SHA-256 does NOT match expected.
/// The on-disk model file is corrupted and needs a silent re-download.
const String sttModelCorrupted = 'stt-model-corrupted';

/// Final `SqliteException(5) database is locked` after the
/// SqliteWriteCoordinator's retry budget is exhausted. One fingerprint
/// for the entire write surface so duplicates like WP-7B…7M collapse to
/// a single Sentry issue.
const String historyWriteFailed = 'history-write-failed';

/// Catch-all for Drift / SQLite mutation errors that are NOT
/// `SqliteException(5)` (e.g. constraint violations, encoding errors,
/// disk-full failures).
const String historyWriteOther = 'history-write-other';

/// Catch-all for `WhisperServerDownloader.download` failures that are not
/// the stall-detector path (network errors, 404s, asset-pattern misses).
const String serverDownloadFailed = 'server-download-failed';

/// `HttpStallDetector` 30 s no-byte-progress kill in the server-binary
/// download stream. Distinct from `serverDownloadFailed` so the stall
/// frequency can be tracked separately.
const String serverDownloadStalled = 'server-download-stalled';

/// Catch-all for `ModelDownloadNotifier` failures (model asset fetch,
/// SHA verification, file rename).
const String modelDownloadFailed = 'model-download-failed';

/// **Reserved but intentionally unused at capture sites**: the update
/// check (`update_service.dart`, GitHub `releases/latest`) is removed
/// from the Sentry capture path entirely — network failures there are
/// expected and gulp the Free-Tier quota. Constant stays in the
/// inventory as a contract marker so the choice is visible in review.
const String updateCheckFailed = 'update-check-failed';

/// `FactoryResetCoordinator` failed-phase fingerprint.
const String factoryResetFailed = 'factory-reset-failed';

// ---------------------------------------------------------------------------
// Pre-existing fingerprints kept as constants so call sites do not need
// inline string literals. These predate the PRD inventory but were already
// in use; promoting them to named constants closes the „no inline literals"
// loop without re-grouping historical Sentry issues.
// ---------------------------------------------------------------------------

/// `Process.start` for `whisper-server` failed (ENOENT, exec bit, path
/// invalid). Used by `stt_server_state_notifier.dart` spawn path.
const String sttSpawnFailed = 'stt-spawn-failed';

/// `whisper-server` is alive but produced no stderr progress within the
/// configured heartbeat window — typically a model-load stall.
const String sttHeartbeatTimeout = 'stt-heartbeat-timeout';

/// `whisper-server` exited before reaching the ready state and the exit
/// did not flow through the classified exit-code switch (i.e. the
/// `_EarlyExitException` escape hatch).
const String sttEarlyExit = 'stt-early-exit';

/// Auto-escalation path from `AppLogger` — any `_log.error` / `_log.fatal`
/// that did NOT explicitly call `captureError` with its own fingerprint
/// lands here. One bucket keeps the auto-escalation noise from sharding.
const String appLoggerAutoEscalated = 'app-logger-auto-escalated';

/// Riverpod `ProviderObserver.providerDidFail` capture. One bucket per
/// failing provider would explode quota; collapsing to one fingerprint
/// keeps the channel reviewable.
const String riverpodProviderFailed = 'riverpod-provider-failed';

// ---------------------------------------------------------------------------
// W1 inference inventory (wartung-2026-05). HTTP-status classification for
// the local `whisper-server` inference endpoint. The classifier in
// `InferenceErrorClassifier` (Issue 02) maps a response status to one of
// these fingerprints so Sentry buckets distinct failure modes separately.
// `inferenceClientRejected` is intentionally NOT in this inventory: pre-flight
// validator rejects stay as breadcrumbs and do not reach the Sentry capture
// path.
// ---------------------------------------------------------------------------

/// HTTP 400 from `whisper-server` inference endpoint. Indicates the
/// request was syntactically valid HTTP but semantically rejected by the
/// server (e.g. malformed multipart, invalid prompt, unsupported sampling
/// parameter). Distinct from the pre-flight validator path, which never
/// captures.
const String inferenceBadRequest = 'inference-bad-request';

/// HTTP 413 (Payload Too Large) from `whisper-server` inference endpoint.
/// The WAV exceeded the server's accepted upload size — typically a sign
/// the pre-flight validator's size cap drifted out of sync with the
/// server config.
const String inferencePayloadTooLarge = 'inference-payload-too-large';

/// HTTP 415 (Unsupported Media Type) from `whisper-server` inference
/// endpoint. The uploaded audio container or codec is not supported by
/// the running server build (e.g. WAV with an unexpected codec tag).
const String inferenceUnsupportedMedia = 'inference-unsupported-media';

/// HTTP 5xx (500–599) from `whisper-server` inference endpoint. Server-side
/// failure — model crash, OOM, internal panic. Distinct from process-exit
/// fingerprints because the server stayed up long enough to answer.
const String inferenceServerError = 'inference-server-error';

/// Any other non-200 status from `whisper-server` inference endpoint
/// (e.g. 4xx that is not 400/413/415, or unexpected 3xx redirects). Acts
/// as the catch-all bucket so unforeseen status codes do not shard into
/// per-code Sentry issues.
const String inferenceUnknownStatus = 'inference-unknown-status';

// ---------------------------------------------------------------------------
// Hardware-Debugging-Audit (2026-05). Adds four buckets that previously
// collapsed into `appLoggerAutoEscalated` (or were silently absent) and
// hid hardware-specific failure modes — CUDA-OOM, inference-time socket
// loss, startup deadlines, and total GPU-detection blackout. Each one
// pre-empts a class of „we know users hit this but Sentry shows nothing
// actionable" reports.
// ---------------------------------------------------------------------------

/// whisper-server hit CUDA out-of-memory at runtime. Distinct from
/// [sttExitGpuFatal] because OOM is a soft-recoverable shape (smaller
/// model / CPU-fallback) whereas GPU-fatal aborts indicate driver-level
/// trouble. Extras carry GPU name, VRAM, model id and the offending
/// stderr tail so the next debugger can map the report to a hardware
/// constellation without needing user access.
const String sttCudaOom = 'stt-cuda-oom';

/// `SocketException` / `http.ClientException` raised mid-inference (the
/// whisper-server died while answering /inference). Previously fell into
/// the catch-all auto-escalation bucket; isolating it gives a clear
/// signal for „server crashed during transcription on this hardware".
const String sttInferenceConnectionLost = 'stt-inference-connection-lost';

/// `_waitReady` exceeded its absolute wall-clock deadline (default 180 s)
/// even though stderr kept producing heartbeats. Catches the long-load
/// stall shape that the heartbeat window alone cannot terminate — e.g.
/// a model that loads layer-by-layer for 10 minutes on a thrashing disk
/// because the OS paged everything out.
const String sttStartupDeadline = 'stt-startup-deadline';

/// GPU detection produced no usable result — every probe timed out or
/// errored. Captured at most once per app session via an in-process
/// guard so it does not spam Sentry on every `detectGpu()` re-entry.
/// Mostly seen on machines where WMI / PowerShell is locked down by
/// corporate AV or group policy.
const String gpuDetectionFailed = 'gpu-detection-failed';

// ---------------------------------------------------------------------------
// Full iterable for tooling (e.g. „verify no inline fingerprint string in
// the codebase appears outside this file"). Order is irrelevant — Sentry
// treats fingerprints as a set of strings, not an ordered list.
// ---------------------------------------------------------------------------

/// All fingerprint wire values registered in this inventory. Iteration
/// order is not stable and must not be relied upon.
const List<String> allCrashFingerprints = <String>[
  // PRD-pinned 13.
  sttExitDllMissing,
  sttExitGpuFatal,
  sttExitHeapCorruption,
  sttExitOther,
  sttModelAbiMismatch,
  sttModelCorrupted,
  historyWriteFailed,
  historyWriteOther,
  serverDownloadFailed,
  serverDownloadStalled,
  modelDownloadFailed,
  updateCheckFailed,
  factoryResetFailed,
  // Pre-existing call-site fingerprints retained as constants.
  sttSpawnFailed,
  sttHeartbeatTimeout,
  sttEarlyExit,
  appLoggerAutoEscalated,
  riverpodProviderFailed,
  // W1 inference inventory (wartung-2026-05).
  inferenceBadRequest,
  inferencePayloadTooLarge,
  inferenceUnsupportedMedia,
  inferenceServerError,
  inferenceUnknownStatus,
  // Hardware-Debugging-Audit (2026-05).
  sttCudaOom,
  sttInferenceConnectionLost,
  sttStartupDeadline,
  gpuDetectionFailed,
];
