/// Arbitrates a start/stop race for a single recording attempt.
///
/// [AudioServiceNotifier.startRecording] needs an unbounded amount of async
/// setup time (mic permission check, input-device routing override, HAL
/// settle wait) before capture is actually active and `state.isRecording`
/// flips true. If [AudioServiceNotifier.stopRecording] is called during that
/// window, there is nothing to stop yet — naively it's a no-op, the pending
/// start finishes anyway, and a live microphone capture is left running
/// unsupervised until the *next*, unrelated start/stop cycle happens to tear
/// it down (see FLUTTER_WHISPASTE memory-leak / garbled-transcript
/// investigation, 2026-08-14).
///
/// This tracks whether a start is in flight and whether a stop arrived while
/// it was, so the start can self-abort instead of orphaning the capture.
library;

class RecordingStartStopArbiter {
  bool _startInProgress = false;
  bool _stopRequestedDuringStart = false;

  /// Call at the very beginning of `startRecording()`, before any `await`.
  void beginStart() {
    _startInProgress = true;
    _stopRequestedDuringStart = false;
  }

  /// Call once the async start setup has finished (right before capture
  /// would be reported as active). Returns `true` when a stop arrived while
  /// starting — the caller must immediately tear the just-opened capture
  /// down instead of reporting it as active.
  bool endStart() {
    _startInProgress = false;
    final shouldAbort = _stopRequestedDuringStart;
    _stopRequestedDuringStart = false;
    return shouldAbort;
  }

  /// Call when `stopRecording()` is invoked but nothing is actively
  /// recording yet. Returns `true` when a start is in flight and has been
  /// flagged for abort once it finishes; `false` when there is genuinely
  /// nothing to stop.
  bool requestStopWhileNotRecording() {
    if (!_startInProgress) return false;
    _stopRequestedDuringStart = true;
    return true;
  }
}
