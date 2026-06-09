/// Self-healing orchestrator for incompatible whisper-server binaries.
///
/// Centralises the recovery logic that used to live duplicated inside the
/// `dllMissing` / `dllEntryPoint` / `modelLoad`-ABI-mismatch switch arms of
/// [SttServerStateNotifier]. When the speech service crashes because the
/// installed server binary is broken (missing DLL, entry-point mismatch,
/// model/binary ABI drift, GPU-fatal abort), this module:
///
///   1. Picks the next-most-conservative server variant for the detected
///      GPU via [nextVariant] (pure function, PRD-Modul-1 table).
///   2. Deletes the incompatible binary, downloads the chosen variant via
///      the injected [WhisperServerDownloader], validates it with
///      [isServerBinaryCompatible], and persists `.server-info.json` so
///      startup checks accept it later.
///   3. Returns one of three sealed [RecoveryResult] cases so the caller
///      (the notifier) can decide whether to restart the server, flip to
///      CPU-fallback state, or surface an actionable toast.
///
/// The orchestrator owns an in-process **recovery-generation counter** —
/// at most one recovery attempt per `(variant)` per app session. The
/// counter is the safety belt against the infinite-loop risk called out
/// in PRD-Modul-1 § Risiken: a CPU binary that itself crashes on missing
/// VC++ runtime must not trigger another `recover()` → another download
/// → another crash cascade.
///
/// No Riverpod dependencies — testable in isolation with fakes for the
/// downloader and the filesystem layer. See
/// `test/services/stt/server_binary_recovery_test.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../hardware_info_service.dart' as hw;
import '../whisper_server_downloader.dart';

final _log = AppLogger('ServerBinaryRecovery');

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Why a recovery attempt was triggered. Mapped 1:1 to the
/// [crash_fingerprints] inventory by [_fingerprintFor] when an exhausted
/// recovery has to report to Sentry.
enum RecoveryReason {
  /// `STATUS_DLL_NOT_FOUND` — incompatible CUDA/Vulkan DLL set.
  dllMissing,

  /// `STATUS_ENTRYPOINT_NOT_FOUND` — DLL present but ABI-incompatible.
  dllEntryPoint,

  /// `modelLoad` exit with intact model SHA-256 — binary cannot load the
  /// model because the whisper.cpp ABI drifted between server versions.
  abiMismatch,

  /// `STATUS_STACK_BUFFER_OVERRUN` / CUDA fatal abort.
  gpuFatal,
}

/// Sealed outcome of a [ServerBinaryRecovery.recover] call. The notifier
/// branches on the concrete subtype to decide its next state transition.
sealed class RecoveryResult {
  const RecoveryResult();
}

/// A new server variant was successfully downloaded and validated.
/// Caller should restart the whisper-server with the new binary.
class RecoveryRetried extends RecoveryResult {
  const RecoveryRetried(this.chosenVariant);

  /// Variant name from the PRD-Modul-1 table — one of
  /// `cuda12` / `cublas-12` / `vulkan` / `metal` / `cpu` / `blas-bin`.
  final String chosenVariant;

  @override
  String toString() => 'RecoveryRetried($chosenVariant)';
}

/// Recovery fell back all the way to the CPU variant. Caller should
/// restart the server in CPU mode. This is distinct from
/// [RecoveryRetried] only for telemetry / log clarity — both successful
/// outcomes lead to a server restart.
class RecoveryFellBackToCpu extends RecoveryResult {
  const RecoveryFellBackToCpu();

  @override
  String toString() => 'RecoveryFellBackToCpu';
}

/// Distinguishes *why* recovery exhausted so the caller can pick the
/// right actionable toast. Most exhaustions are [generic] (restart / re-
/// download). [vcRuntimeMissing] is the special case where the CPU floor
/// build itself aborts with `STATUS_DLL_NOT_FOUND` — the machine is
/// missing the Microsoft Visual C++ runtime the upstream BLAS build links
/// against (notably `VCOMP140.DLL` / OpenMP), which no restart can fix.
enum RecoveryExhaustedKind { generic, vcRuntimeMissing }

/// No further fallback variant exists (already on CPU, or the generation
/// counter saw the same variant retry twice). Caller should surface the
/// [userMessage] to the user — this is the only path that emits a Sentry
/// capture.
class RecoveryExhausted extends RecoveryResult {
  const RecoveryExhausted(
    this.userMessage, {
    this.kind = RecoveryExhaustedKind.generic,
  });

  /// User-facing message, vocabulary-compliant („Sprachdienst",
  /// „Sprachmodell" — never „STT" / „binary" / „Modell-Datei").
  final String userMessage;

  /// Why we exhausted — drives the toast variant in the UI layer.
  final RecoveryExhaustedKind kind;

  @override
  String toString() => 'RecoveryExhausted($userMessage, kind=${kind.name})';
}

// ---------------------------------------------------------------------------
// Pure helper — nextVariant
// ---------------------------------------------------------------------------

/// Returns the next-most-conservative server variant to try, or `null`
/// when no further fallback exists. Pure — exposed for unit testing.
///
/// PRD-Modul-1 table:
///
/// | Current        | Next         |
/// |----------------|--------------|
/// | cuda12         | vulkan       |
/// | cublas-12      | vulkan       |
/// | vulkan         | cpu / blas-bin (whispaste vs upstream naming) |
/// | metal          | cpu          |
/// | cpu / blas-bin | exhausted    |
///
/// `currentVariant` may also be `null` / empty when `.server-info.json`
/// is missing — that case is treated as "unknown current binary", and we
/// fall straight to the optimal-backend variant from the GPU detector so
/// the next download attempts the right one rather than the previous one.
String? nextVariant(String? currentVariant, hw.GpuInfo gpu) {
  final normalized = currentVariant?.trim().toLowerCase() ?? '';

  // Unknown current → start at the GPU's optimal backend rather than
  // looping at the unknown level. The caller's existing crash already
  // tells us "whatever was installed didn't work", so we don't try to
  // re-install it — we let the GPU detector pick afresh.
  if (normalized.isEmpty) {
    return gpu.optimalBackend == 'cuda' ? 'cuda12' : gpu.optimalBackend;
  }

  switch (normalized) {
    case 'cuda':
    case 'cuda12':
    case 'cublas-12':
      return 'vulkan';
    case 'vulkan':
      // Variant naming differs between WhisPaste-owned releases (`cpu`)
      // and upstream whisper.cpp (`blas-bin`). The downloader looks them
      // both up via `serverAssetPatterns`, so either name maps to the
      // same final asset; we surface `cpu` as the human-readable label.
      return 'cpu';
    case 'metal':
      return 'cpu';
    case 'cpu':
    case 'blas-bin':
      return null; // exhausted — already at the safest variant
    default:
      // Unrecognised variant string (forward-compat for future backends)
      // → treat like vulkan-style mid-tier and fall to CPU.
      return 'cpu';
  }
}

// ---------------------------------------------------------------------------
// ServerBinaryRecovery
// ---------------------------------------------------------------------------

/// Default implementation of the recovery orchestrator.
///
/// Construct once per app session (the generation counter must persist
/// across multiple `recover()` calls in the same session).
class ServerBinaryRecovery {
  ServerBinaryRecovery({
    WhisperServerDownloader? downloader,
    BinaryStore? store,
  }) : _downloader = downloader ?? WhisperServerDownloader(),
       _store = store ?? const _DefaultBinaryStore();

  final WhisperServerDownloader _downloader;
  final BinaryStore _store;

  /// Variants we have already attempted in this session. Guards against
  /// the infinite-loop risk in PRD-Modul-1 § Risiken: if a CPU binary
  /// itself crashes (missing VC++ runtime, broken zip extraction, …),
  /// the second `recover()` call must NOT trigger another download —
  /// it must exhaust immediately so the user sees the actionable toast.
  final Set<String> _triedVariants = <String>{};

  /// Public read of the in-session generation counter — exposed only so
  /// tests can assert the guard fires without relying on private state.
  @visibleForTesting
  Set<String> get triedVariantsForTesting => Set.unmodifiable(_triedVariants);

  /// Reset the generation counter. Production never calls this — it is
  /// here exclusively for tests that want to verify the "already-tried"
  /// guard without spinning up a fresh recovery instance every time.
  @visibleForTesting
  void resetGenerationForTesting() => _triedVariants.clear();

  /// PRD-spec entry point. Drives the recovery state-machine and returns
  /// one of the sealed [RecoveryResult] subtypes.
  ///
  /// - [reason] — why we are recovering; controls the Sentry fingerprint
  ///   on the exhausted path.
  /// - [gpu]    — current GPU info, fed into the next-variant decision.
  /// - [sttDirPath] — directory where the whisper-server binary lives.
  /// - [activeModelId] — currently active model ID (logged for context
  ///   only; the downloader does not need it).
  Future<RecoveryResult> recover({
    required RecoveryReason reason,
    required hw.GpuInfo gpu,
    required String sttDirPath,
    required String? activeModelId,
  }) async {
    final current = _store.readBackend(sttDirPath);
    final next = nextVariant(current, gpu);

    _log.info(
      'Recovery requested: reason=${reason.name} '
      'gpu=${gpu.vendor.name} current=${current ?? "<unknown>"} '
      'next=${next ?? "<exhausted>"} activeModel=${activeModelId ?? "<none>"}',
    );

    if (next == null) {
      return _exhaust(
        reason: reason,
        gpu: gpu,
        current: current,
        activeModelId: activeModelId,
        sttDirPath: sttDirPath,
        cause: 'no-fallback-variant-left',
      );
    }

    // Generation guard: each variant gets exactly one shot per session.
    // We register the attempt BEFORE the download so a failed download
    // also counts as "tried" — preventing the retry from re-entering
    // the same variant and looping forever.
    if (!_triedVariants.add(next)) {
      _log.warning(
        'Recovery short-circuit: variant "$next" already tried this '
        'session; exhausting to break potential infinite loop.',
      );
      return _exhaust(
        reason: reason,
        gpu: gpu,
        current: current,
        activeModelId: activeModelId,
        sttDirPath: sttDirPath,
        cause: 'variant-already-tried-this-session',
      );
    }

    // Best-effort: clear the incompatible binary so the next download
    // doesn't trip over leftover DLLs that the compatibility check
    // would still flag as wrong-vendor.
    try {
      await _store.deleteBinary(sttDirPath);
    } on Object catch (e) {
      _log.warning('Could not delete old binary before recovery: $e');
    }

    // Download the next-most-conservative variant. We pass `gpuMode` as
    // either 'auto' (so the downloader's own `serverAssetPatterns` picks
    // the chosen variant for this GPU) or 'disabled' for the CPU floor —
    // the latter forces the CPU/BLAS asset regardless of the GPU.
    final gpuMode = (next == 'cpu' || next == 'blas-bin') ? 'disabled' : 'auto';

    try {
      await _downloader.download(destDir: sttDirPath, gpuMode: gpuMode);
    } on Object catch (e) {
      _log.warning(
        'Recovery download failed for variant "$next": $e. Exhausting.',
      );
      return _exhaust(
        reason: reason,
        gpu: gpu,
        current: current,
        activeModelId: activeModelId,
        sttDirPath: sttDirPath,
        cause: 'download-failed: $e',
      );
    }

    // Validate the freshly-installed binary; if `isServerBinaryCompatible`
    // still says no, treat that as exhausted as well — the download
    // succeeded but produced something the system can't run.
    final isCompatible = _store.isCompatible(sttDirPath, gpu);
    if (!isCompatible) {
      _log.warning(
        'Recovery download produced an incompatible binary for variant '
        '"$next" — exhausting.',
      );
      return _exhaust(
        reason: reason,
        gpu: gpu,
        current: current,
        activeModelId: activeModelId,
        sttDirPath: sttDirPath,
        cause: 'post-download-validation-failed',
      );
    }

    // Persist server-info metadata so the next startup compatibility
    // check sees the new backend. `WhisperServerDownloader` writes this
    // itself on the happy path using `gpu.optimalBackend` — but that
    // value reflects the GPU, not the variant we just *fell back to*.
    // Recovery has authoritative knowledge of the installed backend
    // (e.g. `vulkan` on an NVIDIA box whose optimal backend is still
    // `cuda`), so we re-assert the metadata with the variant we chose.
    // The recorded backend doubles as the "current variant" the next
    // `recover()` call reads from `.server-info.json`.
    await _store.writeServerInfo(sttDirPath, gpu, installedBackend: next);

    if (next == 'cpu' || next == 'blas-bin') {
      _log.info('Recovery succeeded: fell back to CPU variant.');
      return const RecoveryFellBackToCpu();
    }

    _log.info('Recovery succeeded: retried with variant "$next".');
    return RecoveryRetried(next);
  }

  // -------------------------------------------------------------------------
  // Private — exhausted-path capture
  // -------------------------------------------------------------------------

  RecoveryResult _exhaust({
    required RecoveryReason reason,
    required hw.GpuInfo gpu,
    required String? current,
    required String? activeModelId,
    required String sttDirPath,
    required String cause,
  }) {
    // VC++-runtime case: the installed binary that just crashed *is* the
    // CPU floor (`cpu` / `blas-bin`) and it died with STATUS_DLL_NOT_FOUND.
    // The CPU build is the universal fallback, so there is no further
    // variant to try. *One* possible fault is a missing Microsoft Visual C++
    // runtime DLL (the upstream BLAS build links MSVCP140 / VCRUNTIME140 /
    // VCRUNTIME140_1 / VCOMP140, none of which ship in the zip) — a restart
    // cannot fix that; the user must install the VC++ Redistributable.
    //
    // But the variant name alone does NOT prove the runtime is missing: a
    // CPU build can die with STATUS_DLL_NOT_FOUND on a machine where the
    // VC++ runtime is fully installed (e.g. a bundled `ggml-*.dll` that did
    // not extract). Field evidence (FLUTTER_WHISPASTE-A0: VC++ 14.51 present
    // in System32, yet flagged vcRuntimeMissing) showed the old name-only
    // heuristic produced false positives that sent users to reinstall a
    // redistributable they already had. So we additionally probe the actual
    // DLLs and only claim vcRuntimeMissing when they are genuinely absent.
    final vcRuntimePresent = _store.vcRuntimePresent(sttDirPath);

    // Corroborate the `existsSync`-based probe against the actual on-disk file
    // inventory. Field evidence (FLUTTER_WHISPASTE-A0, v1.2.35) showed the
    // probe returning false under MSIX even though the diagnostic dump listed
    // VCRUNTIME140/MSVCP140/VCOMP140 right there in the stt dir — an
    // `existsSync` false-negative on the virtualised `%APPDATA%\Roaming` path.
    // When the inventory contradicts the probe, trust the inventory: claiming
    // „install VC++" on a machine that already has it sends the user on a
    // useless goose chase and pollutes telemetry.
    final dirFiles = _store.listBinaryDirFiles(sttDirPath);
    final lowerDirFiles = dirFiles.map((f) => f.toLowerCase()).toSet();
    final vcDllsOnDisk = hw.vcRuntimeDllNames.every(lowerDirFiles.contains);

    final isVcRuntimeMissing =
        reason == RecoveryReason.dllMissing &&
        _isCpuVariant(current) &&
        !vcRuntimePresent &&
        !vcDllsOnDisk;

    // Always route the user to the in-app diagnostics export so they know what
    // to send us regardless of which exhaustion branch they hit.
    const diagnosticsHint =
        ' Erstelle bitte über „Debug-Informationen kopieren" eine Diagnose '
        'und sende sie uns.';

    // PRD §UI-strings: vocabulary-compliant — „Sprachdienst" / „Sprachmodell".
    final userMessage = isVcRuntimeMissing
        ? 'Sprachdienst kann nicht starten: eine Windows-Komponente fehlt '
              '(Microsoft Visual C++). Bitte installiere das Visual C++ '
              'Redistributable (x64) und starte WhisPaste neu.$diagnosticsHint'
        : 'Sprachdienst kann nicht starten. '
              'Bitte App neu starten oder Sprachmodell neu laden.$diagnosticsHint';

    CrashReporter.instance?.captureError(
      message:
          'whisper-server recovery exhausted '
          '(reason=${reason.name}, cause=$cause)',
      severity: 'error',
      type: 'stt_recovery_exhausted',
      fingerprint: <String>[_fingerprintFor(reason)],
      extras: {
        'reason': reason.name,
        'cause': cause,
        'gpu_vendor': gpu.vendor.name,
        'gpu_name': gpu.name,
        'current_variant': current ?? '<unknown>',
        'tried_variants': _triedVariants.toList(growable: false),
        'active_model_id': activeModelId ?? '<none>',
        'platform': Platform.operatingSystem,
        'vc_runtime_present': vcRuntimePresent,
        'vc_runtime_missing': isVcRuntimeMissing,
        // Corroboration signal: whether the VC++ DLLs were actually in the
        // on-disk listing even when the `existsSync` probe said otherwise.
        'vc_dlls_on_disk': vcDllsOnDisk,
        // What was actually on disk when recovery gave up — lets us see
        // which binary/DLL files were present (or which one was missing)
        // straight from the Sentry event, without a field round-trip.
        'stt_dir_files': dirFiles,
      },
    );

    return RecoveryExhausted(
      userMessage,
      kind: isVcRuntimeMissing
          ? RecoveryExhaustedKind.vcRuntimeMissing
          : RecoveryExhaustedKind.generic,
    );
  }

  /// Whether [variant] names the CPU floor build (`cpu` / `blas-bin`),
  /// case-insensitively. Used to recognise a crashed CPU build, which is
  /// the only variant that has no further fallback.
  static bool _isCpuVariant(String? variant) {
    final v = variant?.trim().toLowerCase();
    return v == 'cpu' || v == 'blas-bin';
  }

  /// Maps [RecoveryReason] to a Sentry fingerprint constant from the
  /// crash-fingerprints inventory (issue-01 contract).
  static String _fingerprintFor(RecoveryReason reason) => switch (reason) {
    RecoveryReason.dllMissing => sttExitDllMissing,
    RecoveryReason.dllEntryPoint => sttExitDllMissing,
    RecoveryReason.abiMismatch => sttModelAbiMismatch,
    RecoveryReason.gpuFatal => sttExitGpuFatal,
  };
}

// ---------------------------------------------------------------------------
// BinaryStore — filesystem seam for testing
// ---------------------------------------------------------------------------

/// Filesystem-and-metadata operations the recovery orchestrator needs.
/// Production code uses [_DefaultBinaryStore] which delegates straight to
/// the existing top-level helpers in `hardware_info_service.dart`; tests
/// pass a fake so they can drive recovery without real disk I/O.
abstract class BinaryStore {
  /// Reads the persisted `.server-info.json` and returns the `backend`
  /// field, or `null` when the file is absent / malformed.
  String? readBackend(String sttDirPath);

  /// Deletes the whisper-server binary + accompanying DLLs.
  Future<void> deleteBinary(String sttDirPath);

  /// Validates the binary in [sttDirPath] against [gpu].
  bool isCompatible(String sttDirPath, hw.GpuInfo gpu);

  /// Whether the Visual C++ runtime DLLs the CPU floor links against are
  /// present (binary directory + `System32`). Lets the orchestrator tell a
  /// genuine missing-VC++-runtime fault apart from a CPU build that died
  /// with STATUS_DLL_NOT_FOUND for some other reason. Non-Windows: `true`.
  bool vcRuntimePresent(String sttDirPath);

  /// File names present in [sttDirPath] — captured into the exhausted-
  /// recovery telemetry so the event records what was actually on disk.
  List<String> listBinaryDirFiles(String sttDirPath);

  /// Persists the post-recovery `.server-info.json` snapshot.
  ///
  /// [installedBackend] overrides what is written to the `backend` field
  /// — the recovery orchestrator passes the *actual* variant it installed
  /// (e.g. `vulkan` after a CUDA-→-Vulkan fallback) rather than
  /// `gpu.optimalBackend`, because the GPU itself has not changed.
  Future<void> writeServerInfo(
    String sttDirPath,
    hw.GpuInfo gpu, {
    required String installedBackend,
  });
}

class _DefaultBinaryStore implements BinaryStore {
  const _DefaultBinaryStore();

  @override
  String? readBackend(String sttDirPath) {
    final info = hw.readServerBinaryInfo(sttDirPath);
    final backend = info?['backend'] as String?;
    if (backend == null || backend.isEmpty) return null;
    return backend;
  }

  @override
  Future<void> deleteBinary(String sttDirPath) =>
      hw.deleteServerBinary(sttDirPath);

  @override
  bool isCompatible(String sttDirPath, hw.GpuInfo gpu) =>
      hw.isServerBinaryCompatible(sttDirPath, gpu);

  @override
  bool vcRuntimePresent(String sttDirPath) =>
      hw.vcRuntimeDllsPresent(sttDirPath);

  @override
  List<String> listBinaryDirFiles(String sttDirPath) =>
      hw.listServerDirFiles(sttDirPath);

  @override
  Future<void> writeServerInfo(
    String sttDirPath,
    hw.GpuInfo gpu, {
    required String installedBackend,
  }) async {
    // `hw.writeServerBinaryInfo` derives `backend` from `gpu.optimalBackend`,
    // which is the GPU-optimal value — *not* what we just installed when
    // recovery falls back to a more conservative variant. Synthesise a
    // GpuInfo whose `optimalBackend` returns the installed variant so the
    // existing helper writes the right value.
    final patched = _GpuInfoWithBackend(gpu, installedBackend);
    await hw.writeServerBinaryInfo(sttDirPath, patched);
  }
}

/// Decorator-style override of [hw.GpuInfo] whose `optimalBackend` returns
/// a caller-supplied string. Used only by [_DefaultBinaryStore] to feed
/// the installed-variant value into the existing `writeServerBinaryInfo`
/// helper without changing that helper's signature.
class _GpuInfoWithBackend extends hw.GpuInfo {
  _GpuInfoWithBackend(hw.GpuInfo base, this._backend)
    : super(
        vendor: base.vendor,
        name: base.name,
        vramMB: base.vramMB,
        cudaAvailable: base.cudaAvailable,
        vulkanAvailable: base.vulkanAvailable,
      );

  final String _backend;

  @override
  String get optimalBackend => _backend;
}
