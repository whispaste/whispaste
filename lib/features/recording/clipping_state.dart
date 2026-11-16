/// Clipping state — last-recording clipping counter exposed to the settings UI.
///
/// The audio pipeline counts how many samples of a recording were too loud:
/// at the int16 limits in the microphone signal (automatic level,
/// `wav_leveler.dart`) or pushed past them by the manual volume
/// (`PcmGainProcessor.clippedSamples`). When a recording finishes
/// successfully, [RecordingOrchestrator] pushes that count and the recording's
/// sample count into this provider so the audio section can render a "the
/// last recording was too loud" banner.
///
/// Semantics (#1611):
///   - The banner shows only from a noticeable share
///     ([audibleClippingShare]); a single clipped sample is inaudible.
///   - Every successful recording overrides the previous value — a clean
///     follow-up clears the banner automatically.
///   - Failed/aborted recordings do **not** touch this state.
///   - [dismiss] explicitly resets the counter to `0` (user clicked the
///     banner's close action).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of the last recording's clipping outcome.
/// Share of too-loud samples from which the distortion is audible: 0.1 %.
const double audibleClippingShare = 0.001;

class ClippingState {
  const ClippingState({
    this.count = 0,
    this.sampleCount = 0,
    this.recordingFinishedAt,
  });

  /// Number of too-loud samples in the last successful recording.
  final int count;

  /// Samples of that recording; `0` when unknown (then [count] decides
  /// alone, so a known clip is never hidden).
  final int sampleCount;

  /// Wall-clock time at which the recording that produced [count] finished.
  /// `null` only for the initial empty state.
  final DateTime? recordingFinishedAt;

  /// True when the UI should render the clipping banner.
  bool get shouldShowBanner {
    if (count <= 0) return false;
    if (sampleCount <= 0) return true;
    return count / sampleCount >= audibleClippingShare;
  }
}

/// Notifier that the [RecordingOrchestrator] pushes the final clipping
/// counter into and the settings UI listens to.
///
/// State is the last recording's clipping result (default zero) or whatever
/// the user last left it at via [dismiss]. The state is *only* mutated by:
///   - [reportRecordingFinished] — called by the orchestrator after a
///     successful capture step (any phase that transitions to
///     `processing`/`done`). The new count overrides whatever was there.
///   - [dismiss] — called by the banner's close button; resets the count
///     to `0` so the banner disappears.
class ClippingStateNotifier extends Notifier<ClippingState> {
  @override
  ClippingState build() => const ClippingState();

  /// Records the outcome of a freshly finished recording.
  ///
  /// [clippedSamples] is the recording's too-loud count, [sampleCount] its
  /// length in samples. Stored verbatim — a clean follow-up recording
  /// overrides a previous count (which auto-hides a leftover banner).
  void reportRecordingFinished(int clippedSamples, {int sampleCount = 0}) {
    state = ClippingState(
      count: clippedSamples,
      sampleCount: sampleCount,
      recordingFinishedAt: DateTime.now(),
    );
  }

  /// User dismissed the banner — reset the counter to `0` so the banner
  /// disappears until the next clipped recording.
  void dismiss() {
    state = ClippingState(
      count: 0,
      sampleCount: state.sampleCount,
      recordingFinishedAt: state.recordingFinishedAt,
    );
  }
}

/// Global clipping state provider.
final clippingStateProvider =
    NotifierProvider<ClippingStateNotifier, ClippingState>(
      ClippingStateNotifier.new,
    );
