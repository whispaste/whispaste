/// Central gate for every nudge dialog (review, support, feature spotlight).
///
/// Growth review R-11: a nudge never opens while a dictation runs (recording,
/// transcribing, refining), and only after the user has been idle inside the
/// app for [kNudgeIdleThreshold]. Idle time is measured from app-internal
/// input (pointer and keyboard events inside the window). A global idle
/// signal is not available on all three desktop platforms in the same form,
/// so the gate deliberately uses only what the app itself sees.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/recording/recording_state.dart';

/// Minimum time without app-internal input before a nudge may open.
const Duration kNudgeIdleThreshold = Duration(seconds: 30);

/// Re-check interval while a dictation blocks nudges.
const Duration kNudgeBusyRecheck = Duration(seconds: 1);

/// Outcome of one gate evaluation.
sealed class NudgeDecision {
  const NudgeDecision();
}

/// The nudge may open now.
final class NudgeAllow extends NudgeDecision {
  const NudgeAllow();
}

/// The nudge must wait; re-evaluate after [after].
final class NudgeWait extends NudgeDecision {
  const NudgeWait(this.after);

  final Duration after;
}

/// Pure decision: no dictation is running and the idle window has passed.
NudgeDecision decideNudge({
  required bool dictationBusy,
  required DateTime now,
  required DateTime lastInputAt,
}) {
  if (dictationBusy) return const NudgeWait(kNudgeBusyRecheck);
  final idle = now.difference(lastInputAt);
  if (idle < kNudgeIdleThreshold) {
    return NudgeWait(kNudgeIdleThreshold - idle);
  }
  return const NudgeAllow();
}

/// Holds the last app-internal input time and answers "may a nudge open?".
final class NudgeGate {
  NudgeGate({required this.clock, required this.isDictationBusy})
    : _lastInputAt = clock();

  final DateTime Function() clock;
  final bool Function() isDictationBusy;

  DateTime _lastInputAt;
  final Set<Timer> _timers = {};

  /// Records app-internal input. [at] defaults to the gate's clock.
  void noteInput([DateTime? at]) => _lastInputAt = at ?? clock();

  NudgeDecision decide() => decideNudge(
    dictationBusy: isDictationBusy(),
    now: clock(),
    lastInputAt: _lastInputAt,
  );

  /// Completes once [decide] allows a nudge. Re-checks on every wait.
  Future<void> whenAllowed() {
    final completer = Completer<void>();
    void check() {
      switch (decide()) {
        case NudgeAllow():
          completer.complete();
        case NudgeWait(:final after):
          late final Timer timer;
          timer = Timer(after, () {
            _timers.remove(timer);
            check();
          });
          _timers.add(timer);
      }
    }

    check();
    return completer.future;
  }

  /// Cancels every pending re-check. Waits that are still open never complete.
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// Clock of the nudge gate. A seam so tests can drive time.
final nudgeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// App-wide gate. Dictation busy-state comes from the recording phase.
///
/// Growth review GR-007 (decision 8b): the end of a dictation counts as user
/// activity. Without this, a dictation into another application leaves the
/// in-app idle clock untouched, and a nudge could open right after the paste.
final nudgeGateProvider = Provider<NudgeGate>((ref) {
  final gate = NudgeGate(
    clock: ref.read(nudgeClockProvider),
    isDictationBusy: () => isDictationBusy(ref.read(recordingPhaseProvider)),
  );
  // Listens to the notifier itself: its state changes reach listeners at once,
  // while a derived phase provider only recomputes when it is read.
  ref.listen<RecordingState>(recordingProvider, (previous, next) {
    final phaseChanged = previous?.phase != next.phase;
    if (phaseChanged && !isDictationBusy(next.phase)) gate.noteInput();
  });
  ref.onDispose(gate.dispose);
  return gate;
});
