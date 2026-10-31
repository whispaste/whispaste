/// DLL dependency analysis for whisper-server.
///
/// Spike decision: full PE import-table parsing vs. expected-DLL-set fallback.
///
/// We use the **§6 expected-DLL-set fallback** (not full PE parsing) for these
/// reasons:
///   1. Full PE parsing in pure Dart is feasible but introduces ~150 LOC of
///      low-level byte-offset arithmetic that is hard to maintain and test
///      without a real Windows binary fixture on a cross-platform CI host.
///   2. The PS1 already performs full PE analysis when run interactively on the
///      user's machine. The Dart diagnostics package is called on *any* platform
///      (including the macOS dev machine), so the analysis layer must be useful
///      even without a live Windows binary.
///   3. The expected-DLL-set approach satisfies all acceptance criteria: it
///      names concrete missing DLLs, covers VC++ runtime detection, and maps
///      cleanly onto the canonical Sentry fingerprints. PRD §6 explicitly
///      endorses this fallback.
///
/// The set [kExpectedWhisperServerDlls] documents every DLL the CPU-floor
/// whisper-server build ships or requires. Callers supply a [presentDlls] set
/// (built from the actual stt-directory file listing via [buildDllPresenceSet]),
/// and the function computes which expected DLLs are absent.
///
/// The GPU-backend loader DLLs (vulkan-1.dll, cudart64_12.dll, cublas64_12.dll)
/// are NOT shipped in the stt directory — they are system DLLs that the GPU
/// driver installs. They are checked via [analyzeDllDeps]'s [backend] parameter
/// using the same expected-set approach.
library;

// ---------------------------------------------------------------------------
// Expected DLL set (documented per AC1)
// ---------------------------------------------------------------------------

/// The complete set of DLL names (lower-case) that a healthy whisper-server
/// installation requires to be present in the stt directory or in System32.
///
/// Sources:
///   - VC++ runtime (CPU floor): linked by every whisper-server variant.
///   - ggml-cpu.dll: the CPU-only inference backend, always bundled.
///   - ggml-base.dll: shared ggml core library, always bundled.
///   - whisper.dll: the whisper model-loading library, always bundled.
///
/// Delay-load and API-set DLLs (api-ms-win-*, ext-ms-*) are virtual and
/// always resolve — they are excluded from this set intentionally.
///
/// GPU-backend loader DLLs (vulkan-1.dll, cudart64_12.dll, cublas64_12.dll)
/// are system-installed, not bundled, and are checked separately via the
/// [backend] parameter in [analyzeDllDeps].
const Set<String> kExpectedWhisperServerDlls = <String>{
  // VC++ 2015-2022 runtime — installed by the VC++ Redistributable.
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'msvcp140.dll',
  'vcomp140.dll',
  // ggml compute core (bundled in stt dir).
  'ggml-base.dll',
  'ggml-cpu.dll',
  // Whisper inference library (bundled in stt dir).
  'whisper.dll',
};

/// GPU-backend system loader DLLs, keyed by backend name.
///
/// These are NOT bundled — the GPU driver must install them.
const Map<String, List<String>> _backendLoaderDlls = <String, List<String>>{
  'vulkan': <String>['vulkan-1.dll'],
  'cuda': <String>['cudart64_12.dll', 'cublas64_12.dll'],
};

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Result of the DLL dependency analysis.
class DllAnalysisResult {
  const DllAnalysisResult({
    required this.missingDlls,
    required this.vcRuntimeMissing,
    this.backendLoaderMissing,
  });

  /// DLL names (lower-case) that are expected but absent from [presentDlls].
  final List<String> missingDlls;

  /// `true` when at least one VC++ runtime DLL is in [missingDlls].
  final bool vcRuntimeMissing;

  /// First GPU-backend loader DLL that is missing for the active [backend],
  /// or `null` when the backend has no GPU-loader requirements or they all
  /// resolve.
  final String? backendLoaderMissing;
}

// ---------------------------------------------------------------------------
// VC++ runtime DLL names (subset of kExpectedWhisperServerDlls)
// ---------------------------------------------------------------------------

const Set<String> _vcRuntimeDlls = <String>{
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'msvcp140.dll',
  'vcomp140.dll',
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Analyses whisper-server DLL dependencies against the known expected set.
///
/// [presentDlls] — lower-case DLL names actually present on disk (build from
/// [buildDllPresenceSet] over the stt-directory listing + System32 listing).
///
/// [backend] — the installed server's compute backend (from
/// `.server-info.json`), e.g. `'cpu'`, `'vulkan'`, `'cuda'`. Drives the
/// GPU-backend loader check. Pass `null` when unknown.
///
/// [windowsContext] — when `false` (non-Windows), VC++ runtime DLLs are not
/// checked as missing because STATUS_DLL_NOT_FOUND is a Windows-only failure
/// mode. Defaults to `true`.
DllAnalysisResult analyzeDllDeps({
  required Set<String> presentDlls,
  required String? backend,
  bool windowsContext = true,
}) {
  if (!windowsContext) {
    // Non-Windows: DLL concept does not apply — everything is "present".
    return const DllAnalysisResult(
      missingDlls: <String>[],
      vcRuntimeMissing: false,
    );
  }

  // Determine which expected DLLs are absent.
  final missing = <String>[
    for (final dll in kExpectedWhisperServerDlls)
      if (!presentDlls.contains(dll)) dll,
  ]..sort();

  final vcMissing = missing.any(_vcRuntimeDlls.contains);

  // Check GPU-backend loader DLLs separately.
  final b = backend?.trim().toLowerCase();
  String? backendLoaderMissing;
  if (b != null && b.isNotEmpty) {
    final loaders = _backendLoaderDlls[b];
    if (loaders != null) {
      for (final dll in loaders) {
        if (!presentDlls.contains(dll)) {
          backendLoaderMissing = dll;
          break;
        }
      }
    }
  }

  return DllAnalysisResult(
    missingDlls: missing,
    vcRuntimeMissing: vcMissing,
    backendLoaderMissing: backendLoaderMissing,
  );
}

/// Builds a lower-case DLL presence set from a raw file-name list.
///
/// Accepts mixed-case names (as returned by directory listings on Windows)
/// and normalises them to lower-case so comparisons are case-insensitive.
Set<String> buildDllPresenceSet(List<String> rawNames) =>
    rawNames.map((n) => n.toLowerCase()).toSet();
