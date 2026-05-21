/// Clipping state — last-recording clipping counter exposed to the settings UI.
///
/// The audio pipeline counts how many int16 samples saturated to the int16
/// limits during a recording (see `PcmGainProcessor.clippedSamples`). When a
/// recording finishes successfully, [RecordingOrchestrator] pushes that final
/// count into this provider so the gain slider section can render a "your
/// gain was too high" banner.
///
/// Semantics:
///   - A [count] of `0` means no banner is shown.
///   - A non-zero [count] overrides the previous value on the next successful
///     recording — including a clean follow-up (a fresh `count == 0` clears
///     the banner automatically).
///   - Failed/aborted recordings do **not** touch this state.
///   - [dismiss] explicitly resets the counter to `0` (user clicked the
///     banner's close action).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of the last recording's clipping outcome.
class ClippingState {
  const ClippingState({this.count = 0, this.recordingFinishedAt});

  /// Number of clipped int16 samples observed during the last successful
  /// recording. `0` means no clipping (and no banner).
  final int count;

  /// Wall-clock time at which the recording that produced [count] finished.
  /// `null` only for the initial empty state.
  final DateTime? recordingFinishedAt;

  /// True when the UI should render the clipping banner.
  bool get shouldShowBanner => count > 0;
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
  /// [clippedSamples] is the final counter from the recording's
  /// `PcmGainProcessor`. The value is stored verbatim — a fresh `0` from a
  /// clean follow-up recording overrides a previous non-zero count (which
  /// auto-hides any banner left over from the prior recording).
  void reportRecordingFinished(int clippedSamples) {
    state = ClippingState(
      count: clippedSamples,
      recordingFinishedAt: DateTime.now(),
    );
  }

  /// User dismissed the banner — reset the counter to `0` so the banner
  /// disappears until the next clipped recording.
  void dismiss() {
    state = ClippingState(
      count: 0,
      recordingFinishedAt: state.recordingFinishedAt,
    );
  }
}

/// Global clipping state provider.
final clippingStateProvider =
    NotifierProvider<ClippingStateNotifier, ClippingState>(
      ClippingStateNotifier.new,
    );
