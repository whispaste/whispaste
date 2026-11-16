/// Time budgets for one transcription (#1639, #1619).
///
/// Cloud providers keep the orchestrator formula `60 s + 0.8 × audio`. Local
/// engines (whisper.cpp, Parakeet GPU and sherpa-onnx) get one budget that the
/// engine itself enforces: it follows the measured speed of the machine, has a
/// generous floor and grows while the engine keeps reporting progress. When it
/// runs out, the engine aborts the native decode instead of leaving it running
/// behind a Dart timeout, so the next dictation finds a free engine.
///
/// Pure functions only, so the numbers are testable without an engine.
library;

import 'dart:math' as math;

/// Fixed part of every local budget: model warm-up, VAD, the first encoder
/// pass. Short dictations mostly live on it.
const Duration kLocalBudgetBase = Duration(seconds: 60);

/// Seconds of decode time per second of audio when no speed was measured on
/// this machine. Matches the old engine stuck-guard (3 × audio).
const double kLocalBudgetUnknownFactor = 3.0;

/// Headroom over a measured real-time factor. The benchmark decodes a 6-s
/// clip; a long recording on a warm, throttled or busy machine runs slower.
const double kLocalBudgetRtfSafety = 3.0;

/// Smallest factor, even on a very fast machine: a 60-min recording that
/// measured RTF 0.03 still gets one hour.
const double kLocalBudgetMinFactor = 1.0;

/// Largest factor. A machine that needs more than eight times the recording
/// length is not usable for that model; past it the budget never grows, not
/// even through progress. It also bounds the orchestrator backstop.
const double kLocalBudgetMaxFactor = 8.0;

/// Largest boost after budget overruns (see [localBudgetFactor]).
const int kLocalBudgetMaxBoost = 4;

/// Audio of the longest piece a local engine decodes in one native call
/// (whisper pause chunks and Parakeet slices stay under 25 s).
const Duration kLocalSliceAudio = Duration(seconds: 30);

/// How long a decode may take to return after its abort flag was raised.
/// whisper.cpp checks the flag after the encoder and between decoder steps,
/// so the longest wait is one encoder pass on a slow CPU.
const Duration kLocalAbortGrace = Duration(seconds: 30);

/// Cloud formula, unchanged: `60 s + 0.8 × audio`, rounded to whole seconds.
Duration cloudTranscriptionTimeout(Duration audio) {
  final audioSec = audio.isNegative ? 0 : audio.inMilliseconds / 1000;
  return Duration(seconds: 60 + (audioSec * 0.8).round());
}

/// Seconds of decode time allowed per second of audio.
///
/// [measuredRtf] is this machine's benchmark for the loaded model and compute
/// path (`null` = not measured): `3 × rtf`, at least
/// [kLocalBudgetMinFactor]. Without a measurement
/// [kLocalBudgetUnknownFactor]. [boost] multiplies it after a previous decode
/// ran out of budget, so a retry of the same audio does not hit the same wall
/// (1, 2 or 4). Never above [kLocalBudgetMaxFactor].
double localBudgetFactor({double? measuredRtf, int boost = 1}) {
  final rtf = measuredRtf;
  final base = (rtf == null || !rtf.isFinite || rtf <= 0)
      ? kLocalBudgetUnknownFactor
      : math.max(kLocalBudgetMinFactor, rtf * kLocalBudgetRtfSafety);
  final b = boost.clamp(1, kLocalBudgetMaxBoost);
  return math.min(kLocalBudgetMaxFactor, base * b);
}

Duration _scaled(Duration audio, double factor) {
  if (audio.isNegative) return Duration.zero;
  return Duration(microseconds: (audio.inMicroseconds * factor).round());
}

/// Upper limit for a local decode of [audio], however much progress it
/// reports: `60 s + 8 × audio`.
Duration localTranscriptionHardCap(Duration audio) =>
    kLocalBudgetBase + _scaled(audio, kLocalBudgetMaxFactor);

/// One local budget for [audio]: `60 s + factor × audio` (see
/// [localBudgetFactor]), at most [localTranscriptionHardCap].
Duration localTranscriptionBudget(
  Duration audio, {
  double? measuredRtf,
  int boost = 1,
}) {
  final factor = localBudgetFactor(measuredRtf: measuredRtf, boost: boost);
  final budget = kLocalBudgetBase + _scaled(audio, factor);
  final cap = localTranscriptionHardCap(audio);
  return budget > cap ? cap : budget;
}

/// How far each progress report pushes the deadline out: the time for one
/// slice ([kLocalSliceAudio]) decoded twice (whisper's loop rescue runs a
/// second pass) at [factor], plus [kLocalBudgetBase].
Duration localProgressStallWindow(double factor) =>
    kLocalBudgetBase + _scaled(kLocalSliceAudio * 2, factor);

/// Orchestrator backstop for a local transcription step. The engine enforces
/// its own budget and aborts first; this only catches an engine that does
/// not return at all, including one GPU-to-CPU retry and the abort grace.
Duration localOrchestratorTimeout(Duration audio) =>
    localTranscriptionHardCap(audio) +
    kLocalAbortGrace +
    const Duration(minutes: 2);

/// State-machine stuck guard while `transcribing`: one minute past the
/// slowest step budget (local backstop, which is always above the cloud
/// formula), at least [floor].
Duration transcriptionStuckBudget(Duration audio, {required Duration floor}) {
  final budget = localOrchestratorTimeout(audio) + const Duration(minutes: 1);
  return budget > floor ? budget : floor;
}
