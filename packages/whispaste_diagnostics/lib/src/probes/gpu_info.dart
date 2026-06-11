/// Cross-platform GPU detection for optimal AI inference backend selection.
///
/// Pure-Dart (no Flutter, no Riverpod). The Riverpod `gpuInfoProvider` wrapper
/// lives in the app layer (`lib/services/hardware_info_service.dart`) and
/// delegates to [detectGpu] from this module.
///
/// Detects the primary GPU vendor and capabilities to determine which
/// whisper-server binary variant (CUDA, Vulkan, CPU) should be downloaded
/// and whether flash-attention or GPU acceleration should be enabled.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Process-runner test seam
// ---------------------------------------------------------------------------

/// Function signature for a process runner that returns a [ProcessResult].
///
/// Production code uses [Process.run]; tests can swap in a fake that returns
/// canned outputs or blocks for a controlled duration.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Default production runner — wraps [Process.run] directly.
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments,
) => Process.run(executable, arguments);

ProcessRunner _processRunner = _defaultProcessRunner;

/// Overrides the [ProcessRunner] used by Windows GPU detection.
///
/// Pass `null` to restore the default ([Process.run]). Intended for tests
/// only — production code must never call this.
@visibleForTesting
void setProcessRunnerForTesting(ProcessRunner? runner) {
  _processRunner = runner ?? _defaultProcessRunner;
}

/// Per-probe timeout for the parallel Windows GPU detection probes
/// (`wmic` and `powershell`). On expiry the probe is treated as "empty"
/// and the other probe's result wins.
@visibleForTesting
const Duration kWindowsGpuProbeTimeout = Duration(seconds: 8);

// ---------------------------------------------------------------------------
// RAM requirement
// ---------------------------------------------------------------------------

/// Minimum system RAM required to run WhisPaste reliably (in MB).
///
/// Enforced at startup: the app shows a blocking screen and refuses to
/// proceed on systems below this threshold. 8 GB is required to load at
/// least the balanced STT model without memory pressure.
const int kMinRamMB = 8192;

/// Effective check threshold used in the startup preflight (in MB).
///
/// Windows and Linux report visible RAM, which is always slightly less than
/// physical RAM (BIOS holes, iGPU reservations, etc.). A machine with exactly
/// 8 GB of DIMMs typically reports 7617–7900 MB as `TotalVisibleMemorySize`.
/// Using 7500 MB as the check threshold avoids false-positives on legitimate
/// 8 GB machines while still blocking systems with less than ~7.3 GB physical.
///
/// macOS is safe: `sysctl hw.memsize` returns raw physical bytes.
const int kRamCheckThresholdMB = 7500;

// ---------------------------------------------------------------------------
// STT model VRAM requirements
// ---------------------------------------------------------------------------

/// Estimated VRAM requirements for each STT model (in MB).
/// These are conservative estimates: whisper models need the model weights in
/// VRAM PLUS scratch space for attention matrices and CUDA runtime overhead.
/// The actual peak usage can be 1.3–1.5× the model file size.
const Map<String, int> sttModelVramMB = {
  'whisper-small': 900,
  'whisper-medium': 1500,
  'whisper-large-v3-turbo': 2600,
};

// ---------------------------------------------------------------------------
// GPU vendor enum
// ---------------------------------------------------------------------------

/// GPU vendor categories that map to whisper-server binary variants.
enum GpuVendor {
  nvidia, // → CUDA backend (best perf with NVIDIA GPUs)
  amd, // → Vulkan backend
  intel, // → Vulkan backend
  apple, // → Metal backend (macOS/iOS, Apple Silicon)
  none, // → CPU (OpenBLAS) backend
}

// ---------------------------------------------------------------------------
// GPU info
// ---------------------------------------------------------------------------

/// Detected GPU information used for binary selection and server configuration.
class GpuInfo {
  const GpuInfo({
    required this.vendor,
    required this.name,
    this.vramMB,
    this.cudaAvailable = false,
    this.vulkanAvailable = false,
  });

  final GpuVendor vendor;
  final String name;
  final int? vramMB;
  final bool cudaAvailable;
  final bool vulkanAvailable;

  /// The optimal whisper-server binary variant for this GPU.
  String get optimalBackend {
    switch (vendor) {
      case GpuVendor.nvidia:
        if (!cudaAvailable) return 'vulkan';
        // CUDA is present, but the prebuilt cuda12 binary only runs on
        // Maxwell (sm_52) and newer. Kepler/Fermi cards (GeForce 4xx–7xx)
        // must use the Vulkan build or they crash on launch — see
        // [supportsCuda12].
        return supportsCuda12 ? 'cuda' : 'vulkan';
      case GpuVendor.amd:
      case GpuVendor.intel:
        return 'vulkan';
      case GpuVendor.apple:
        return 'metal';
      case GpuVendor.none:
        return 'cpu';
    }
  }

  /// Whether any GPU is available for acceleration.
  bool get hasGpu => vendor != GpuVendor.none;

  /// Whether flash attention is supported.
  ///
  /// Flash Attention in whisper.cpp requires CUDA compute capability sm_75+
  /// (Turing architecture, 2018+). Older NVIDIA cards (Kepler sm_30, Maxwell
  /// sm_50, Pascal sm_61) will crash with an illegal instruction or fatal
  /// abort when `--flash-attn` is passed.
  ///
  /// Heuristic: RTX branding guarantees Turing+. GTX 16xx (1630/1650/1660)
  /// are Turing-architecture cards sold under the GTX label. Professional
  /// datacenter cards (A-series, T4, L-series, H-series) are Ampere+.
  /// All other GTX cards are Maxwell/Pascal and must not use flash-attn.
  bool get supportsFlashAttn {
    if (vendor != GpuVendor.nvidia || !cudaAvailable) return false;
    final upper = name.toUpperCase();
    // RTX branding: Turing (20xx), Ampere (30xx), Ada (40xx), Blackwell (50xx)
    if (upper.contains('RTX')) return true;
    // GTX 16xx series: Turing architecture with GTX branding (1630/1650/1660)
    if (RegExp(r'GTX\s*16\d\d').hasMatch(upper)) return true;
    // NVIDIA datacenter/professional Turing+ cards
    if (RegExp(
      r'\b(T4|A10G?|A16|A30|A40|A100|A800|L4|L40S?|H100|H200)\b',
    ).hasMatch(upper)) {
      return true;
    }
    // All other GTX cards (6xx Kepler, 7xx Kepler/Maxwell, 9xx Maxwell,
    // 10xx Pascal) do not support flash attention.
    return false;
  }

  /// Whether this NVIDIA GPU can run the CUDA 12 `whisper-server` build.
  ///
  /// The prebuilt cuda12 binary targets compute capability sm_50+. CUDA 12
  /// dropped Fermi (sm_2x) and Kepler (sm_3x) support entirely, so handing it
  /// to an older card aborts during CUDA init — in the field this surfaces as
  /// an immediate exit code -1 with an empty stderr (FLUTTER_WHISPASTE-6X) or
  /// a model-load failure (exit 3). Those GPUs must use the Vulkan build.
  ///
  /// Heuristic mirrors [supportsFlashAttn]: the model name encodes the
  /// generation. Maxwell (GTX 9xx, sm_52) and newer are CUDA-12-capable. When
  /// the model name is unknown — e.g. a discrete NVIDIA inferred only from
  /// `nvcuda.dll` on a hybrid laptop, named "… + NVIDIA (discrete)" — we
  /// assume CUDA 12 works: such machines are modern in practice, and a missed
  /// false-negative there is far rarer than the Kepler crash-loop we guard
  /// against.
  bool get supportsCuda12 {
    if (vendor != GpuVendor.nvidia || !cudaAvailable) return false;
    final upper = name.toUpperCase();
    // GeForce 400/500/600/700 (Fermi + Kepler): a three-digit model number in
    // the 400–799 range. GTX 745/750/750 Ti are technically Maxwell but share
    // the 7xx label; routing them to Vulkan only costs a little speed (Vulkan
    // runs fine on them), whereas a missed Kepler is a hard crash loop — so we
    // deliberately err toward Vulkan for the whole 7xx range.
    if (RegExp(r'\b(?:GTX|GT|GEFORCE)\s*[4-7]\d{2}\b').hasMatch(upper)) {
      return false;
    }
    // Kepler-era professional cards: Quadro K / Tesla K / GRID K series.
    if (RegExp(r'\b(?:QUADRO|TESLA|GRID)\s*K\d').hasMatch(upper)) {
      return false;
    }
    return true;
  }

  @override
  String toString() =>
      'GpuInfo($vendor, "$name", vram=${vramMB ?? "?"}MB, '
      'cuda=$cudaAvailable, vulkan=$vulkanAvailable, '
      'backend=$optimalBackend)';
}

// ---------------------------------------------------------------------------
// Cached detection
// ---------------------------------------------------------------------------

GpuInfo? _cached;

/// One-shot guard for the GPU-detection-failure callback.
/// Re-armed by [clearGpuCache] so a recovery-driven re-detection can also
/// re-report a failure if the second attempt is just as blind.
bool _gpuDetectionCaptureSent = false;

/// Optional callback invoked at most once per session when GPU detection
/// fails (both probes return empty / vendor remains [GpuVendor.none]).
///
/// Register this from the app layer to route the event into Sentry or any
/// other telemetry sink — the core package has no Sentry dependency.
///
/// Callback signature: `void Function({required String reason, bool cudaAvailable})`.
typedef GpuDetectionFailureCallback =
    void Function({required String reason, bool cudaAvailable});

GpuDetectionFailureCallback? _onDetectionFailed;

/// Registers the GPU-detection-failure callback.
///
/// Call once at app startup (e.g. from `main.dart`) to wire up Sentry
/// telemetry. The callback fires at most once per session per [clearGpuCache]
/// cycle.
void setGpuDetectionFailureCallback(GpuDetectionFailureCallback? callback) {
  _onDetectionFailed = callback;
}

/// Emits the GPU-detection-failure event at most once per app session.
/// The guard avoids spamming the bucket on every `detectGpu()` re-entry.
@visibleForTesting
void captureGpuDetectionFailureOnce({
  required String reason,
  bool cudaAvailable = false,
}) {
  if (_gpuDetectionCaptureSent) return;
  _gpuDetectionCaptureSent = true;
  _onDetectionFailed?.call(reason: reason, cudaAvailable: cudaAvailable);
}

/// Detects the primary GPU. Result is cached after the first call.
///
/// Detection is fast (~100–500ms) and runs once per session. Subsequent
/// calls return immediately from cache.
Future<GpuInfo> detectGpu() async {
  if (_cached != null) return _cached!;

  try {
    if (Platform.isWindows) {
      _cached = await _detectWindows();
    } else if (Platform.isMacOS) {
      _cached = await _detectMacOS();
    } else if (Platform.isLinux) {
      _cached = await _detectLinux();
    } else {
      _cached = const GpuInfo(vendor: GpuVendor.none, name: 'Unsupported OS');
    }
  } catch (e) {
    captureGpuDetectionFailureOnce(reason: 'top-level-exception: $e');
    _cached = const GpuInfo(
      vendor: GpuVendor.none,
      name: 'Detection failed — using CPU',
    );
  }

  return _cached!;
}

/// Returns cached GPU info if available, `null` otherwise.
///
/// Use [detectGpu] for the initial detection. This getter is for code
/// that needs a synchronous check after detection has already run.
GpuInfo? get cachedGpuInfo => _cached;

/// Clears the cached GPU info **and** re-arms the once-per-session
/// failure-callback guard. Used by tests, and by the server-binary-recovery
/// hook so a fresh detection after recovery can re-report a failure if the
/// second pass is also blind.
void clearGpuCache() {
  _cached = null;
  _gpuDetectionCaptureSent = false;
}

/// Runs the Windows GPU-detection path regardless of the host platform.
///
/// Intended for tests that want to exercise the parallel wmic + PowerShell
/// resilience logic on macOS / Linux CI runners. The result is **not** cached
/// — callers may invoke this repeatedly without `clearGpuCache()`.
@visibleForTesting
Future<GpuInfo> detectGpuWindowsForTesting() => _detectWindows();

// ---------------------------------------------------------------------------
// Asset pattern mapping
// ---------------------------------------------------------------------------

/// Returns the asset name patterns in priority order for the detected GPU.
///
/// [gpuMode] is the user's GPU preference: 'auto', 'enabled', 'disabled'.
/// [isWhisPaste] selects between WhisPaste and upstream whisper.cpp naming.
List<String> serverAssetPatterns(
  GpuInfo gpu,
  String gpuMode,
  bool isWhisPaste,
) {
  if (gpuMode == 'disabled') {
    return isWhisPaste ? ['cpu'] : ['blas-bin'];
  }

  // Map GPU vendor → binary variant priority.
  if (isWhisPaste) {
    switch (gpu.vendor) {
      case GpuVendor.nvidia:
        // `supportsCuda12` (not raw `cudaAvailable`): a Kepler/Fermi card has
        // CUDA but cannot run the cuda12 build, so it must skip straight to
        // the Vulkan variant. See [GpuInfo.supportsCuda12].
        return gpu.supportsCuda12
            ? ['cuda12', 'vulkan', 'cpu']
            : ['vulkan', 'cpu'];
      case GpuVendor.amd:
      case GpuVendor.intel:
        return ['vulkan', 'cpu'];
      case GpuVendor.apple:
        return ['metal', 'cpu'];
      case GpuVendor.none:
        return ['cpu'];
    }
  } else {
    // Upstream whisper.cpp naming.
    switch (gpu.vendor) {
      case GpuVendor.nvidia:
        return gpu.supportsCuda12
            ? ['cublas-12', 'vulkan', 'blas-bin']
            : ['vulkan', 'blas-bin'];
      case GpuVendor.amd:
      case GpuVendor.intel:
        return ['vulkan', 'blas-bin'];
      case GpuVendor.apple:
        return ['metal', 'blas-bin'];
      case GpuVendor.none:
        return ['blas-bin'];
    }
  }
}

// ---------------------------------------------------------------------------
// Proactive GPU capability gating
// ---------------------------------------------------------------------------

/// Whether it is safe to use GPU acceleration for this [gpu].
///
/// Returns `false` for known-problematic GPUs that should be routed to CPU
/// BEFORE the server starts — avoiding the slow reactive stall→CPU fallback.
/// Returns `true` (conservative) for all other cases: unknown names, modern
/// cards, non-GPU vendors that embed a fixed backend (Metal, Vulkan on Intel).
///
/// Precedence in [SttServerStateNotifier._start]:
///   1. User override (`gpuAcceleration` = `enabled`/`disabled`)
///   2. This predicate (`shouldUseGpu == false` → CPU)
///   3. The existing `auto`-path (optimalBackend etc.)
///
/// The reactive [SttServerStateNotifier._gpuFallbackActive] fallback remains
/// the safety net for cases this predicate does not catch.
bool shouldUseGpu(GpuInfo gpu) {
  // GpuVendor.none → no GPU present, CPU is the only option.
  if (gpu.vendor == GpuVendor.none) return false;

  // NVIDIA Kepler/Fermi: already detected by supportsCuda12 (false for 4xx–7xx
  // GeForce and Quadro K / Tesla K). These cards either crash the cuda12 build
  // or hang the Vulkan build (FLUTTER_WHISPASTE-9W / -6X). Route to CPU.
  if (gpu.vendor == GpuVendor.nvidia) {
    // supportsCuda12 returns false for Kepler/Fermi, regardless of backend.
    // Reuse the same heuristic to keep the logic DRY.
    if (!gpu.supportsCuda12) return false;
    return true;
  }

  // AMD: old GCN (HD 7xxx / HD 8xxx, codenames Tahiti / Cape Verde / Pitcairn)
  // predates the ROCm/Vulkan support level whisper.cpp needs. Identified
  // conservatively by three-digit model numbers in the 7000–8999 range.
  // Post-GCN1 Polaris and later (RX 4xx / 5xx+) are fine — additive approach.
  if (gpu.vendor == GpuVendor.amd) {
    final upper = gpu.name.toUpperCase();
    if (RegExp(r'\bHD\s*[78]\d{3}\b').hasMatch(upper)) return false;
    return true;
  }

  // Intel, Apple, and any future vendor: allow GPU (conservative).
  return true;
}

// ---------------------------------------------------------------------------
// Binary compatibility check
// ---------------------------------------------------------------------------

/// Metadata file written after each successful whisper-server download.
const _serverInfoFilename = '.server-info.json';

/// Whether a binary downloaded for [storedBackend] can run on a machine
/// whose GPU-optimal backend is [optimalBackend].
///
/// Pure decision core of the Layer-1 metadata check in
/// [isServerBinaryCompatible] — see the rationale there. Normalises the
/// naming drift between the GPU detector (`cuda`), WhisPaste release assets
/// (`cuda12` / `cpu`) and upstream whisper.cpp assets (`cublas-12` /
/// `blas-bin`).
bool storedBackendRunsOn({
  required String storedBackend,
  required String optimalBackend,
}) {
  final stored = switch (storedBackend.trim().toLowerCase()) {
    'cuda' || 'cuda12' || 'cublas-12' => 'cuda',
    'blas-bin' => 'cpu',
    final other => other,
  };

  // The CPU floor runs on every machine (FLUTTER_WHISPASTE-80).
  if (stored == 'cpu') return true;

  return switch (optimalBackend) {
    // NVIDIA: cuda is optimal, vulkan is the recovery downgrade — both run.
    'cuda' => stored == 'cuda' || stored == 'vulkan',
    'vulkan' => stored == 'vulkan',
    'metal' => stored == 'metal',
    // Optimal cpu (no GPU): only the cpu floor fits — handled above.
    _ => false,
  };
}

/// Checks if the existing whisper-server binary in [sttDirPath] is compatible
/// with the detected [gpu].
///
/// Uses two layers of validation:
/// 1. **Metadata check**: reads `.server-info.json` written during download
///    and compares the stored backend against the GPU's optimal backend.
/// 2. **DLL heuristic**: if CUDA DLLs are present on a non-NVIDIA system,
///    the binary is incompatible regardless of metadata.
///
/// Returns `true` if compatible or no binary exists. Returns `false` if the
/// binary was downloaded for a different backend than what the current GPU
/// requires (e.g., CPU binary on a Vulkan-capable system, or CUDA binary
/// on a non-NVIDIA system).
bool isServerBinaryCompatible(String sttDirPath, GpuInfo gpu) {
  final serverFile = File(
    p.join(
      sttDirPath,
      Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
    ),
  );
  if (!serverFile.existsSync()) return true; // Nothing to validate.

  // --- Layer 1: Metadata-based check ----------------------------------------
  // "Compatible" means *runnable on this machine*, not *optimal for it*:
  // ServerBinaryRecovery deliberately installs more conservative variants
  // (cuda → vulkan → cpu) after a GPU build fails to start. Treating such an
  // intentional downgrade as incompatible deletes the one binary that works
  // and re-pulls the failing optimal build — recovery then wants the
  // downgrade again, the per-session generation guard fires and the user
  // dead-ends in „recovery exhausted" although the next variant down would
  // have worked. Field shapes: FLUTTER_WHISPASTE-80 (cpu floor deleted on a
  // GPU machine) and FLUTTER_WHISPASTE-A0 (vulkan deleted on a cuda machine,
  // cuda↔vulkan ping-pong). Only a backend the machine genuinely cannot run
  // (cuda on AMD, metal on Windows, …) is incompatible.
  final info = readServerBinaryInfo(sttDirPath);
  if (info != null) {
    final storedBackend = (info['backend'] as String? ?? '')
        .trim()
        .toLowerCase();
    if (storedBackend.isNotEmpty) {
      return storedBackendRunsOn(
        storedBackend: storedBackend,
        optimalBackend: gpu.optimalBackend,
      );
    }
  }

  // --- Layer 2: DLL heuristic (Windows-only) --------------------------------
  if (Platform.isWindows) {
    final cudaDlls = ['cublas64_12.dll', 'cublaslt64_12.dll', 'ggml-cuda.dll'];
    final hasCudaDlls = cudaDlls.any(
      (dll) => File(p.join(sttDirPath, dll)).existsSync(),
    );

    if (hasCudaDlls && gpu.vendor != GpuVendor.nvidia) {
      return false;
    }

    // No inverse check ("non-CUDA binary on a CUDA-capable NVIDIA system"):
    // `writeServerBinaryInfo` is best-effort (FileSystemException swallowed,
    // observed failing under MSIX), so a recovery-installed Vulkan or CPU
    // build can legitimately sit here without metadata. Flagging it as
    // incompatible would re-enter the same delete→re-pull ping-pong the
    // Layer-1 downgrade tolerance above exists to prevent.

    // --- Layer 3: Vulkan DLL heuristic --------------------------------------
    // Vulkan binaries always include ggml-vulkan.dll. If the GPU needs
    // Vulkan but the DLL is absent, the binary is not a Vulkan build.
    if (gpu.optimalBackend == 'vulkan') {
      final hasVulkanDll = File(
        p.join(sttDirPath, 'ggml-vulkan.dll'),
      ).existsSync();
      if (!hasVulkanDll) {
        // CPU/BLAS floor markers → this is the universal fallback build,
        // possibly installed by ServerBinaryRecovery with a failed
        // .server-info.json write (best-effort, observed under MSIX).
        // Deleting it would re-pull the GPU build and re-enter the
        // delete→re-download loop the FLUTTER_WHISPASTE-80 fix closed for
        // metadata'd CPU builds — so the floor stays, the user can upgrade
        // explicitly via Settings. (CUDA leftovers never reach this branch:
        // the wrong-vendor check above already flagged them.)
        const cpuFloorMarkers = [
          'ggml-blas.dll',
          'libopenblas.dll',
          'ggml-cpu.dll',
        ];
        final looksLikeCpuFloor = cpuFloorMarkers.any(
          (dll) => File(p.join(sttDirPath, dll)).existsSync(),
        );
        if (looksLikeCpuFloor) return true;
        // No backend runtime DLLs at all: a torso from a broken extraction,
        // not a working fallback — keep flagging it so the startup
        // self-heal re-downloads a working build.
        return false;
      }
    }
  }

  return true;
}

/// Writes metadata about the downloaded whisper-server binary.
///
/// Called after a successful server binary download/extraction so that
/// [isServerBinaryCompatible] can later validate without DLL heuristics.
Future<void> writeServerBinaryInfo(
  String sttDirPath,
  GpuInfo gpu, {
  String? sourceRepo,
  String? assetName,
}) async {
  final infoFile = File(p.join(sttDirPath, _serverInfoFilename));
  final info = <String, Object>{
    'backend': gpu.optimalBackend,
    'gpu_vendor': gpu.vendor.name,
    'gpu_name': gpu.name,
    'cuda_available': gpu.cudaAvailable,
    'vulkan_available': gpu.vulkanAvailable,
    'downloaded_at': DateTime.now().toUtc().toIso8601String(),
  };
  if (sourceRepo != null) info['source_repo'] = sourceRepo;
  if (assetName != null) info['asset_name'] = assetName;
  try {
    await infoFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(info),
    );
  } on FileSystemException {
    // Best-effort: ignore write failures (read-only FS, permissions, etc.)
  }
}

/// Reads the stored server binary metadata, or `null` if no info file exists.
Map<String, dynamic>? readServerBinaryInfo(String sttDirPath) {
  final infoFile = File(p.join(sttDirPath, _serverInfoFilename));
  if (!infoFile.existsSync()) return null;
  try {
    return jsonDecode(infoFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return null;
  }
}

/// Validates the server binary at startup and deletes it if incompatible.
///
/// Returns `true` if the binary was deleted (caller should mark server as
/// not ready). Returns `false` if no action was needed.
Future<bool> validateAndCleanIncompatibleBinary(String sttDirPath) async {
  final gpu = await detectGpu();
  final serverPath = p.join(
    sttDirPath,
    Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
  );
  if (!File(serverPath).existsSync()) return false;

  if (!isServerBinaryCompatible(sttDirPath, gpu)) {
    await deleteServerBinary(sttDirPath);
    return true;
  }

  return false;
}

/// Deletes the whisper-server binary, associated DLLs, and the metadata
/// file from [sttDirPath].
///
/// Used to force a re-download of the correct binary variant.
Future<void> deleteServerBinary(String sttDirPath) async {
  final dir = Directory(sttDirPath);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync()) {
    if (entity is File) {
      final name = p.basename(entity.path).toLowerCase();
      if (name.endsWith('.exe') ||
          name.endsWith('.dll') ||
          name.endsWith('.dylib') ||
          name.endsWith('.so') ||
          name == 'whisper-server' ||
          name == _serverInfoFilename) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Best-effort: ignore individual deletion failures.
        }
      }
    }
  }
}

/// The Microsoft Visual C++ runtime DLLs the CPU-floor (`cpu` / `blas-bin`)
/// whisper-server build links against.
const List<String> vcRuntimeDllNames = <String>[
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'msvcp140.dll',
  'vcomp140.dll',
];

/// Whether *all* the Visual C++ runtime DLLs the CPU floor needs are
/// resolvable on this system via the relevant parts of the Windows DLL
/// search order: the binary's own directory ([sttDirPath]) and `System32`.
///
/// Non-Windows always returns `true`: STATUS_DLL_NOT_FOUND is a Windows exit
/// code, so this probe is only meaningful there.
bool vcRuntimeDllsPresent(String sttDirPath) {
  if (!Platform.isWindows) return true;

  final searchDirs = <String>[sttDirPath];
  final systemRoot =
      Platform.environment['SystemRoot'] ??
      Platform.environment['WINDIR'] ??
      r'C:\Windows';
  searchDirs.add(p.join(systemRoot, 'System32'));

  bool resolvable(String dll) =>
      searchDirs.any((dir) => File(p.join(dir, dll)).existsSync());

  return vcRuntimeDllNames.every(resolvable);
}

/// System-provided loader DLLs each GPU-accelerated whisper-server build
/// imports at *load time*, keyed by `.server-info.json` backend.
const Map<String, List<String>> backendLoaderDllNames = <String, List<String>>{
  'vulkan': <String>['vulkan-1.dll'],
  'cuda': <String>['cudart64_12.dll', 'cublas64_12.dll'],
};

/// Pure decision core of [firstUnresolvableBackendLoaderDll], exposed for
/// testing so the backend→loader mapping can be exercised off Windows.
///
/// Returns the first DLL in [backend]'s loader set for which [resolve]
/// returns `false`, or `null` when [backend] has no GPU-loader dependency
/// (CPU / BLAS / Metal / unknown) or every dependency resolves.
@visibleForTesting
String? firstUnresolvableBackendLoaderDllFor({
  required String? backend,
  required bool Function(String dll) resolve,
}) {
  final b = backend?.trim().toLowerCase();
  if (b == null || b.isEmpty) return null;
  final required = backendLoaderDllNames[b];
  if (required == null) return null;
  for (final dll in required) {
    if (!resolve(dll)) return dll;
  }
  return null;
}

/// Returns the first system loader DLL the installed GPU-variant binary in
/// [sttDirPath] needs but the system cannot resolve, or `null` when every
/// dependency resolves.
///
/// Non-Windows always returns `null`.
String? firstUnresolvableBackendLoaderDll(String sttDirPath) {
  if (!Platform.isWindows) return null;

  final backend = readServerBinaryInfo(sttDirPath)?['backend'] as String?;

  // Resolve against the *directory listing* for the binary dir instead of
  // per-file `existsSync`: field evidence (FLUTTER_WHISPASTE-A0) showed
  // `existsSync` returning false-negatives on the virtualised
  // `%APPDATA%\Roaming` path under MSIX while the same files appeared in the
  // `listSync`-based inventory. A false "missing" here needlessly kicks the
  // working GPU build into recovery. System32 is not virtualised, so the
  // plain probe stays fine there.
  final dirInventory = listServerDirFiles(
    sttDirPath,
  ).map((f) => f.toLowerCase()).toSet();
  final systemRoot =
      Platform.environment['SystemRoot'] ??
      Platform.environment['WINDIR'] ??
      r'C:\Windows';
  final system32 = p.join(systemRoot, 'System32');

  bool resolvable(String dll) =>
      dirInventory.contains(dll) || File(p.join(system32, dll)).existsSync();

  return firstUnresolvableBackendLoaderDllFor(
    backend: backend,
    resolve: resolvable,
  );
}

/// Lists the file names present in [sttDirPath] (non-recursive), or an empty
/// list when the directory is missing or unreadable.
List<String> listServerDirFiles(String sttDirPath) {
  try {
    final dir = Directory(sttDirPath);
    if (!dir.existsSync()) return const <String>[];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList(growable: false);
  } on FileSystemException {
    return const <String>[];
  }
}

// ---------------------------------------------------------------------------
// Windows detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectWindows() async {
  // Phase 1: Quick check — is CUDA runtime available?
  final cudaAvailable = File(r'C:\Windows\System32\nvcuda.dll').existsSync();

  // Phase 2: Run wmic + PowerShell in parallel, each with its own 8 s cap.
  final parsed = await _raceForFirstNonNull<_GpuParsed>([
    _wmicGetGpus(),
    _powershellGetGpus(),
  ]);

  String gpuName = 'Unknown';
  GpuVendor vendor = GpuVendor.none;
  int? vramMB;

  if (parsed != null) {
    gpuName = parsed.name;
    vendor = parsed.vendor;
    vramMB = parsed.vramMB;
  }

  // Dual-GPU detection: if CUDA DLLs exist but wmic found Intel/AMD as
  // primary display adapter, an NVIDIA discrete GPU is likely available.
  if (cudaAvailable && vendor != GpuVendor.nvidia) {
    vendor = GpuVendor.nvidia;
    gpuName = '$gpuName + NVIDIA (discrete)';
  }

  if (vendor == GpuVendor.nvidia) {
    vramMB = await _windowsNvidiaVramMB() ?? vramMB;
  }

  if (vendor == GpuVendor.none) {
    captureGpuDetectionFailureOnce(
      reason: parsed == null
          ? 'windows-both-probes-empty'
          : 'windows-vendor-unclassified',
      cudaAvailable: cudaAvailable,
    );
    return GpuInfo(
      vendor: GpuVendor.none,
      name: 'Detection failed — using CPU',
      cudaAvailable: cudaAvailable,
    );
  }

  return GpuInfo(
    vendor: vendor,
    name: gpuName,
    vramMB: vramMB,
    cudaAvailable: cudaAvailable,
    vulkanAvailable: vendor != GpuVendor.none,
  );
}

/// Races a set of `Future<T?>` probes and returns the first non-null result.
Future<T?> _raceForFirstNonNull<T>(List<Future<T?>> probes) {
  if (probes.isEmpty) return Future<T?>.value(null);

  final completer = Completer<T?>();
  var remaining = probes.length;

  for (final probe in probes) {
    probe.then(
      (value) {
        if (completer.isCompleted) return;
        if (value != null) {
          completer.complete(value);
          return;
        }
        remaining -= 1;
        if (remaining == 0) completer.complete(null);
      },
      onError: (Object _, StackTrace _) {
        if (completer.isCompleted) return;
        remaining -= 1;
        if (remaining == 0) completer.complete(null);
      },
    );
  }

  return completer.future;
}

Future<_GpuParsed?> _wmicGetGpus() async {
  try {
    final result = await _processRunner('wmic', [
      'path',
      'win32_videocontroller',
      'get',
      'name,adapterram',
      '/format:list',
    ]).timeout(kWindowsGpuProbeTimeout);

    if (result.exitCode != 0) return null;
    return _parseWmicList(result.stdout.toString());
  } on TimeoutException {
    return null;
  } catch (e) {
    return null;
  }
}

Future<int?> _windowsNvidiaVramMB() async {
  try {
    final result = await _processRunner('nvidia-smi', [
      '--query-gpu=memory.total',
      '--format=csv,noheader,nounits',
    ]).timeout(const Duration(seconds: 5));

    if (result.exitCode != 0) return null;

    for (final line in result.stdout.toString().split('\n')) {
      final mb = int.tryParse(line.trim());
      if (mb != null && mb > 0) return mb;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

_GpuParsed? _parseWmicList(String output) {
  final gpus = <_GpuParsed>[];
  String? currentName;
  int? currentVram;

  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      if (currentName != null && currentName.isNotEmpty) {
        gpus.add(
          _GpuParsed(
            name: currentName,
            vendor: _classifyVendor(currentName),
            vramMB: currentVram,
          ),
        );
      }
      currentName = null;
      currentVram = null;
      continue;
    }

    final eqIdx = trimmed.indexOf('=');
    if (eqIdx < 0) continue;
    final key = trimmed.substring(0, eqIdx).trim().toLowerCase();
    final value = trimmed.substring(eqIdx + 1).trim();

    if (key == 'name') {
      currentName = value;
    } else if (key == 'adapterram') {
      final bytes = int.tryParse(value);
      if (bytes != null && bytes > 0) {
        currentVram = bytes ~/ (1024 * 1024);
      }
    }
  }

  // Flush last block.
  if (currentName != null && currentName.isNotEmpty) {
    gpus.add(
      _GpuParsed(
        name: currentName,
        vendor: _classifyVendor(currentName),
        vramMB: currentVram,
      ),
    );
  }

  if (gpus.isEmpty) return null;

  // Prefer discrete GPU: NVIDIA > AMD > Intel > None.
  gpus.sort((a, b) => a.vendor.index.compareTo(b.vendor.index));
  return gpus.first;
}

Future<_GpuParsed?> _powershellGetGpus() async {
  try {
    final result = await _processRunner('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_VideoController | '
          r'ForEach-Object { "$($_.Name)|$($_.AdapterRAM)" }',
    ]).timeout(kWindowsGpuProbeTimeout);

    if (result.exitCode != 0) return null;

    final gpus = <_GpuParsed>[];
    for (final line in result.stdout.toString().split('\n')) {
      final parts = line.trim().split('|');
      if (parts.isEmpty || parts[0].isEmpty) continue;

      final name = parts[0];
      final vramBytes = parts.length > 1 ? int.tryParse(parts[1]) : null;

      gpus.add(
        _GpuParsed(
          name: name,
          vendor: _classifyVendor(name),
          vramMB: vramBytes != null && vramBytes > 0
              ? vramBytes ~/ (1024 * 1024)
              : null,
        ),
      );
    }

    if (gpus.isEmpty) return null;
    gpus.sort((a, b) => a.vendor.index.compareTo(b.vendor.index));
    return gpus.first;
  } on TimeoutException {
    return null;
  } catch (e) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// macOS detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectMacOS() async {
  // Check for Apple Silicon (ARM64).
  try {
    final uname = await Process.run('uname', ['-m']);
    if (uname.stdout.toString().trim() == 'arm64') {
      String chipName = 'Apple Silicon';
      try {
        final sysctl = await Process.run('sysctl', [
          '-n',
          'machdep.cpu.brand_string',
        ]);
        final brand = sysctl.stdout.toString().trim();
        if (brand.isNotEmpty) chipName = brand;
      } catch (_) {}

      return GpuInfo(
        vendor: GpuVendor.apple,
        name: chipName,
        vramMB: await _macUnifiedMemoryMB(),
      );
    }
  } catch (_) {}

  // Intel Mac — check for discrete GPU.
  try {
    final result = await Process.run('system_profiler', [
      'SPDisplaysDataType',
      '-detailLevel',
      'mini',
    ]).timeout(const Duration(seconds: 10));

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      final chipName = _extractMacGpuName(output);
      final vramMB = _extractMacVramMB(output);
      final lower = output.toLowerCase();

      if (lower.contains('amd') || lower.contains('radeon')) {
        return GpuInfo(
          vendor: GpuVendor.amd,
          name: chipName ?? 'AMD GPU',
          vramMB: vramMB,
          vulkanAvailable: true,
        );
      }
    }
  } catch (_) {}

  // Fallback: Intel integrated on Intel Mac.
  return const GpuInfo(vendor: GpuVendor.intel, name: 'Intel (Mac)');
}

Future<int?> _macUnifiedMemoryMB() async {
  try {
    final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
    if (result.exitCode != 0) return null;
    final bytes = int.tryParse(result.stdout.toString().trim());
    if (bytes == null || bytes <= 0) return null;
    return bytes ~/ (1024 * 1024);
  } catch (e) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// RAM detection (cross-platform)
// ---------------------------------------------------------------------------

/// Detects total physical system RAM in MB.
///
/// Uses platform-native commands (same pattern as GPU detection).
/// Returns `null` when detection fails — callers should treat `null` as
/// "unknown" and NOT block the app (fail-open to avoid false positives).
Future<int?> detectRamMB() async {
  try {
    if (Platform.isMacOS || Platform.isLinux) {
      return await _unixRamMB();
    } else if (Platform.isWindows) {
      return await _windowsRamMB();
    }
  } catch (e) {
    // ignore
  }
  return null;
}

Future<int?> _unixRamMB() async {
  if (Platform.isMacOS) {
    final r = await Process.run('/usr/sbin/sysctl', [
      '-n',
      'hw.memsize',
    ]).timeout(const Duration(seconds: 5));
    if (r.exitCode != 0) return null;
    return parseSysctlMemsizeMb(r.stdout.toString());
  } else {
    try {
      final lines = await File('/proc/meminfo').readAsLines();
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          return parseLinuxMemTotalMb(line);
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }
}

Future<int?> _windowsRamMB() async {
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize',
    ]).timeout(const Duration(seconds: 10));
    if (r.exitCode == 0) {
      final kb = int.tryParse(r.stdout.toString().trim());
      if (kb != null && kb > 0) return kb ~/ 1024;
    }
  } catch (_) {}

  try {
    final r = await Process.run('wmic', [
      'os',
      'get',
      'TotalVisibleMemorySize',
      '/Value',
    ]).timeout(const Duration(seconds: 5));
    if (r.exitCode == 0) {
      final result = parseWmicOsMemoryMb(r.stdout.toString());
      if (result != null) return result;
    }
  } catch (_) {}

  return null;
}

// ---------------------------------------------------------------------------
// Pure RAM parsing helpers — exported for unit testing.
// ---------------------------------------------------------------------------

/// Parses `sysctl -n hw.memsize` stdout into MB.
///
/// Returns `null` for empty, non-numeric, or non-positive output.
@visibleForTesting
int? parseSysctlMemsizeMb(String output) {
  final bytes = int.tryParse(output.trim());
  if (bytes == null || bytes <= 0) return null;
  return bytes ~/ (1024 * 1024);
}

/// Parses a Linux `/proc/meminfo` snippet containing a `MemTotal:` line into MB.
///
/// Returns `null` when the line is absent or the value cannot be parsed.
@visibleForTesting
int? parseLinuxMemTotalMb(String memInfoOutput) {
  final match = RegExp(r'MemTotal:\s+(\d+)').firstMatch(memInfoOutput);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

/// Parses `wmic os get TotalVisibleMemorySize /Value` stdout into MB.
///
/// Returns `null` when the key is absent or the value cannot be parsed.
@visibleForTesting
int? parseWmicOsMemoryMb(String wmicOutput) {
  final match = RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(wmicOutput);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

int? _extractMacVramMB(String profilerOutput) {
  for (final line in profilerOutput.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.toLowerCase().startsWith('vram')) continue;

    final match = RegExp(
      r'(\d+)\s*(gb|mb)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) continue;

    final amount = int.tryParse(match.group(1) ?? '');
    final unit = match.group(2)?.toLowerCase();
    if (amount == null || unit == null) continue;
    return unit == 'gb' ? amount * 1024 : amount;
  }
  return null;
}

String? _extractMacGpuName(String profilerOutput) {
  for (final line in profilerOutput.split('\n')) {
    if (line.contains('Chipset Model:') || line.contains('Chip:')) {
      return line.split(':').last.trim();
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Linux detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectLinux() async {
  // Phase 1: Check PCI vendor IDs via sysfs (fastest, no external tools).
  try {
    final drmDir = Directory('/sys/class/drm');
    if (drmDir.existsSync()) {
      for (final card in drmDir.listSync()) {
        final vendorFile = File('${card.path}/device/vendor');
        if (!vendorFile.existsSync()) continue;
        final vendorId = vendorFile.readAsStringSync().trim().toLowerCase();

        if (vendorId == '0x10de') {
          return GpuInfo(
            vendor: GpuVendor.nvidia,
            name: await _linuxGpuName() ?? 'NVIDIA GPU',
            vramMB: await _linuxNvidiaVramMB(),
            cudaAvailable: _linuxHasCuda(),
            vulkanAvailable: true,
          );
        }
        if (vendorId == '0x1002') {
          return GpuInfo(
            vendor: GpuVendor.amd,
            name: await _linuxGpuName() ?? 'AMD GPU',
            vramMB: _linuxAmdVramMB(),
            vulkanAvailable: true,
          );
        }
        if (vendorId == '0x8086') {
          return GpuInfo(
            vendor: GpuVendor.intel,
            name: await _linuxGpuName() ?? 'Intel GPU',
            vulkanAvailable: true,
          );
        }
      }
    }
  } catch (_) {}

  // Phase 2: Fallback to lspci.
  try {
    final result = await Process.run('lspci', ['-nn']);
    if (result.exitCode == 0) {
      final output = result.stdout.toString().toLowerCase();
      if (output.contains('[10de:') || output.contains('nvidia')) {
        return GpuInfo(
          vendor: GpuVendor.nvidia,
          name: 'NVIDIA GPU',
          vramMB: await _linuxNvidiaVramMB(),
          cudaAvailable: _linuxHasCuda(),
          vulkanAvailable: true,
        );
      }
      if (output.contains('[1002:') ||
          output.contains('amd') ||
          output.contains('radeon')) {
        return GpuInfo(
          vendor: GpuVendor.amd,
          name: 'AMD GPU',
          vramMB: _linuxAmdVramMB(),
          vulkanAvailable: true,
        );
      }
      if (output.contains('[8086:') || output.contains('intel')) {
        return const GpuInfo(
          vendor: GpuVendor.intel,
          name: 'Intel GPU',
          vulkanAvailable: true,
        );
      }
    }
  } catch (_) {}

  return const GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected');
}

Future<String?> _linuxGpuName() async {
  try {
    final result = await Process.run('lspci', []);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.contains('VGA') ||
          line.contains('3D controller') ||
          line.contains('Display controller')) {
        final colons = line.split(':');
        if (colons.length >= 3) return colons.sublist(2).join(':').trim();
      }
    }
  } catch (_) {}
  return null;
}

bool _linuxHasCuda() {
  return File('/usr/lib/x86_64-linux-gnu/libcuda.so').existsSync() ||
      File('/usr/lib64/libcuda.so').existsSync() ||
      File('/usr/bin/nvidia-smi').existsSync();
}

Future<int?> _linuxNvidiaVramMB() async {
  try {
    final result = await Process.run('nvidia-smi', [
      '--query-gpu=memory.total',
      '--format=csv,noheader,nounits',
    ]).timeout(const Duration(seconds: 5));

    if (result.exitCode != 0) return null;

    for (final line in result.stdout.toString().split('\n')) {
      final mb = int.tryParse(line.trim());
      if (mb != null && mb > 0) return mb;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

int? _linuxAmdVramMB() {
  try {
    final drmDir = Directory('/sys/class/drm');
    if (!drmDir.existsSync()) return null;

    for (final card in drmDir.listSync()) {
      final vramFile = File('${card.path}/device/mem_info_vram_total');
      if (!vramFile.existsSync()) continue;
      final bytes = int.tryParse(vramFile.readAsStringSync().trim());
      if (bytes != null && bytes > 0) {
        return bytes ~/ (1024 * 1024);
      }
    }
  } catch (e) {
    // ignore
  }
  return null;
}

// ---------------------------------------------------------------------------
// Vendor classification
// ---------------------------------------------------------------------------

GpuVendor _classifyVendor(String gpuName) {
  final lower = gpuName.toLowerCase();
  if (lower.contains('nvidia') ||
      lower.contains('geforce') ||
      lower.contains('quadro') ||
      lower.contains('rtx ') ||
      lower.contains('tesla')) {
    return GpuVendor.nvidia;
  }
  if (lower.contains('amd') ||
      lower.contains('radeon') ||
      lower.contains('rx ')) {
    return GpuVendor.amd;
  }
  if (lower.contains('intel') ||
      lower.contains('iris') ||
      lower.contains('uhd') ||
      lower.contains('hd graphics')) {
    return GpuVendor.intel;
  }
  if (lower.contains('apple') ||
      lower.contains('m1') ||
      lower.contains('m2') ||
      lower.contains('m3') ||
      lower.contains('m4')) {
    return GpuVendor.apple;
  }
  return GpuVendor.none;
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _GpuParsed {
  _GpuParsed({required this.name, required this.vendor, this.vramMB});
  final String name;
  final GpuVendor vendor;
  final int? vramMB;
}
