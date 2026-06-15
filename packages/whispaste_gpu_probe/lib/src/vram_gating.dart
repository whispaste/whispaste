/// VRAM gating — pre-flight check that marks a candidate as [Outcome.skipped]
/// when the required model VRAM exceeds the available GPU budget.
///
/// Pure-Dart, no side-effects.  All external data is injected.
library;

import 'package:whispaste_diagnostics/whispaste_diagnostics.dart';

import 'probe_types.dart';

// ---------------------------------------------------------------------------
// Pure gate function (AC1 + AC2)
// ---------------------------------------------------------------------------

/// Result of a VRAM pre-flight check.
sealed class VramGateResult {
  const VramGateResult();
}

/// The model fits within the available VRAM budget.
final class VramFits extends VramGateResult {
  const VramFits();
}

/// The model is too large; [reason] explains the shortfall.
final class VramSkipped extends VramGateResult {
  const VramSkipped(this.reason);

  /// Human-readable explanation, suitable for [CandidateResult.errorDetail].
  final String reason;
}

/// Checks whether a model identified by [modelSizeKey] fits in [vramBudgetMB].
///
/// [modelSizeKey] must be one of the keys in [sttModelVramMB]
/// (e.g. `'whisper-small'`, `'whisper-medium'`, `'whisper-large-v3-turbo'`).
/// Unknown keys are treated as "fits" (fail-open — we can only gate what we know).
///
/// [vramBudgetMB] is the detected VRAM budget in MB.  When `null` (unknown)
/// the gate passes: we cannot reject a candidate we cannot measure.
///
/// Uses [sttModelVramMB] from `package:whispaste_diagnostics` directly —
/// no copy, no duplication (AC2).
VramGateResult checkVramGate({
  required String modelSizeKey,
  required int? vramBudgetMB,
}) {
  if (vramBudgetMB == null) return const VramFits();

  final requiredMB = sttModelVramMB[modelSizeKey];
  if (requiredMB == null) return const VramFits(); // unknown model → fail-open

  if (vramBudgetMB < requiredMB) {
    return VramSkipped(
      'Model "$modelSizeKey" requires ~$requiredMB MB VRAM '
      'but only $vramBudgetMB MB detected — skipped to avoid OOM.',
    );
  }

  return const VramFits();
}

// ---------------------------------------------------------------------------
// VramGatedCandidate wrapper (AC4)
// ---------------------------------------------------------------------------

/// Wraps a [ProbeCandidate] with a VRAM pre-flight check.
///
/// Before delegating to [delegate].run(), the wrapper calls [checkVramGate].
/// If the model does not fit, it returns a [CandidateResult] with
/// [Outcome.skipped] immediately — the delegate's [run] is **never** called.
///
/// Inject a fixed [vramBudgetMB] in tests; pass `null` to disable gating
/// (fail-open, same as when VRAM is unknown).
class VramGatedCandidate implements ProbeCandidate {
  const VramGatedCandidate({
    required this.delegate,
    required this.modelSizeKey,
    required this.vramBudgetMB,
  });

  /// The real candidate to run when the VRAM gate passes.
  final ProbeCandidate delegate;

  /// Key into [sttModelVramMB] (e.g. `'whisper-medium'`).
  final String modelSizeKey;

  /// Detected VRAM budget in MB; `null` means unknown (gate passes).
  final int? vramBudgetMB;

  @override
  String get id => delegate.id;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    final gate = checkVramGate(
      modelSizeKey: modelSizeKey,
      vramBudgetMB: vramBudgetMB,
    );

    if (gate is VramSkipped) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        errorDetail: gate.reason,
      );
    }

    return delegate.run(ctx);
  }
}
