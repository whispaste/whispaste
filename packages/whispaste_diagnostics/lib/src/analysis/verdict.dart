/// Verdict builder — derives suspicions and a primary fingerprint from probe
/// data and DLL analysis, porting and extending the PS1 verdict logic.
///
/// Ported from the "AUTOMATISCHE BEWERTUNG" section of whispaste-diagnose.ps1
/// and extended to cover:
///   - fehlende DLL (konkret benannt) → stt-exit-dll-missing
///   - fehlende VC++-Runtime → stt-exit-dll-missing
///   - whisper-server in AV-Quarantäne → stt-exit-dll-missing
///   - RAM < 7500 MB (§6.6) → stt-exit-other
///   - stale TCC (macOS) → stt-exit-other
///   - Modell-ABI-Mismatch → stt-model-abi-mismatch
///   - whisper-server exit code classification via [mapFailureToFingerprint]
///
/// Fingerprint priority order (highest first):
///   1. stt-exit-dll-missing (includes AV quarantine — binary can't load)
///   2. stt-model-abi-mismatch
///   3. stt-exit-heap-corruption
///   4. stt-exit-gpu-fatal / stt-cuda-oom
///   5. stt-exit-other (RAM scarce, stale TCC, or unclassified exit)
///
/// The public interface ([buildVerdict], [VerdictResult], [VerdictSuspicion])
/// is the only surface that tests may assert against. Internal helpers are
/// private.
library;

import 'dll_analysis.dart';
import 'fingerprint_mapping.dart';

// ---------------------------------------------------------------------------
// Result models
// ---------------------------------------------------------------------------

/// A single suspicion entry: a concrete problem hypothesis and its canonical
/// Sentry fingerprint.
class VerdictSuspicion {
  const VerdictSuspicion({required this.fingerprint, required this.detail});

  /// The canonical Sentry fingerprint (mirrors crash_fingerprints.dart).
  final String fingerprint;

  /// Human-readable description of the suspicion (English, for the report).
  final String detail;

  @override
  String toString() => '[$fingerprint] $detail';
}

/// Overall verdict derived from all available probe data.
class VerdictResult {
  const VerdictResult({
    required this.suspicions,
    required this.primaryFingerprint,
  });

  /// Ordered list of suspicions (highest-priority first).
  final List<VerdictSuspicion> suspicions;

  /// The most actionable fingerprint, or `null` when the system is healthy.
  ///
  /// When [suspicions] is non-empty, this is the fingerprint of the first
  /// (highest-priority) suspicion.
  final String? primaryFingerprint;

  /// `true` when no suspicions were found.
  bool get healthy => suspicions.isEmpty;
}

// ---------------------------------------------------------------------------
// Fingerprint priority ranking (lower = higher priority)
// ---------------------------------------------------------------------------

const Map<String, int> _fingerprintPriority = <String, int>{
  'stt-exit-dll-missing': 0,
  'stt-model-abi-mismatch': 1,
  'stt-exit-heap-corruption': 2,
  'stt-exit-gpu-fatal': 3,
  'stt-cuda-oom': 3,
  'stt-exit-other': 4,
};

int _priorityOf(String fp) => _fingerprintPriority[fp] ?? 99;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Builds a [VerdictResult] from all available probe signals.
///
/// All parameters accept synthesised fixture values in tests — no OS calls.
///
/// [dllAnalysis] — result of [analyzeDllDeps].
/// [ramScarce] — `true` when total RAM < 7500 MB (§6.6, [kRamCheckThresholdMB]).
/// [avQuarantined] — `true` when the binary has a quarantine / AV-threat flag.
/// [staleTcc] — `true` when macOS TCC says Accessibility is allowed but
///   `AXIsProcessTrusted` returns false (§3.5 stale-TCC bug).
/// [modelAbiMismatch] — `true` when the server binary exited with code 3 while
///   the model SHA-256 was intact (ABI mismatch after a server-variant change).
/// [serverExitCode] — the last known whisper-server exit code, or `null`.
/// [stderrSnippet] — optional stderr tail for fingerprint refinement.
VerdictResult buildVerdict({
  required DllAnalysisResult dllAnalysis,
  required bool ramScarce,
  required bool avQuarantined,
  required bool staleTcc,
  required bool modelAbiMismatch,
  required int? serverExitCode,
  String? stderrSnippet,
}) {
  final suspicions = <VerdictSuspicion>[];

  // 1. Missing DLLs — most actionable for Windows users.
  if (dllAnalysis.vcRuntimeMissing) {
    final missing = dllAnalysis.missingDlls.where(_isVcRuntimeDll).join(', ');
    suspicions.add(
      VerdictSuspicion(
        fingerprint: 'stt-exit-dll-missing',
        detail:
            'VC++ runtime DLL(s) missing: $missing. '
            'Install the VC++ Redistributable x64 from '
            'https://aka.ms/vs/17/release/vc_redist.x64.exe',
      ),
    );
  } else if (dllAnalysis.missingDlls.isNotEmpty) {
    final missing = dllAnalysis.missingDlls.join(', ');
    suspicions.add(
      VerdictSuspicion(
        fingerprint: 'stt-exit-dll-missing',
        detail:
            'Missing bundled DLL(s): $missing. '
            'Re-download the whisper-server binary or reinstall WhisPaste.',
      ),
    );
  }

  // 2. Backend loader DLL missing (GPU backend dependency not installed).
  final backendMissing = dllAnalysis.backendLoaderMissing;
  if (backendMissing != null) {
    suspicions.add(
      VerdictSuspicion(
        fingerprint: 'stt-exit-dll-missing',
        detail:
            'GPU backend loader DLL not found: $backendMissing. '
            'The GPU driver may not be installed or may be outdated.',
      ),
    );
  }

  // 3. AV quarantine — binary present but OS refuses to load it.
  if (avQuarantined) {
    suspicions.add(
      const VerdictSuspicion(
        fingerprint: 'stt-exit-dll-missing',
        detail:
            'whisper-server is in AV quarantine or blocked by Gatekeeper. '
            'The binary cannot load its dependencies. '
            'Allow the binary in your AV/security settings.',
      ),
    );
  }

  // 4. Model ABI mismatch — exit code 3 with intact model file.
  if (modelAbiMismatch) {
    suspicions.add(
      const VerdictSuspicion(
        fingerprint: 'stt-model-abi-mismatch',
        detail:
            'Server binary exited with code 3 while the model file is '
            'intact. The installed whisper-server variant cannot load this '
            'model (ABI mismatch after a server update). '
            'Re-download the model or reinstall WhisPaste.',
      ),
    );
  }

  // 5. Exit-code based fingerprint (refines from code + stderr).
  final exitFp = mapFailureToFingerprint(
    exitCode: serverExitCode,
    stderrSnippet: stderrSnippet,
  );
  if (exitFp != null) {
    // Avoid duplicating stt-exit-dll-missing if already added via DLL analysis.
    final alreadyCovered = suspicions.any((s) => s.fingerprint == exitFp);
    if (!alreadyCovered) {
      suspicions.add(
        VerdictSuspicion(
          fingerprint: exitFp,
          detail: _exitCodeDetail(serverExitCode!, exitFp),
        ),
      );
    }
  }

  // 6. RAM scarce (§6.6: < 7500 MB).
  if (ramScarce) {
    suspicions.add(
      const VerdictSuspicion(
        fingerprint: 'stt-exit-other',
        detail:
            'Total RAM is below the 7500 MB threshold (§6.6). '
            'WhisPaste may not have enough memory to load the model. '
            'Close other applications or use a smaller model.',
      ),
    );
  }

  // 7. Stale TCC (macOS §3.5).
  if (staleTcc) {
    suspicions.add(
      const VerdictSuspicion(
        fingerprint: 'stt-exit-other',
        detail:
            'Stale TCC entry detected: Accessibility is toggled ON in '
            'System Settings but AXIsProcessTrusted returns false. '
            'Toggle the Accessibility permission OFF then ON again in '
            'System Settings > Privacy & Security > Accessibility.',
      ),
    );
  }

  // Sort by priority so [primaryFingerprint] is the most actionable.
  suspicions.sort(
    (a, b) => _priorityOf(a.fingerprint).compareTo(_priorityOf(b.fingerprint)),
  );

  return VerdictResult(
    suspicions: suspicions,
    primaryFingerprint: suspicions.isEmpty
        ? null
        : suspicions.first.fingerprint,
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _isVcRuntimeDll(String dll) {
  return dll.startsWith('vcruntime') ||
      dll.startsWith('msvcp') ||
      dll.startsWith('vcomp') ||
      dll.startsWith('concrt');
}

String _exitCodeDetail(int code, String fingerprint) {
  final hex =
      '0x${(code & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0')}';
  return 'whisper-server exited with code $code ($hex) → $fingerprint';
}
