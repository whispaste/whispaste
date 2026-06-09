/// RecordingStateMachine — enforces the recording phase transition table.
///
/// All orchestrator-driven phase changes route through [RecordingStateMachine.transition].
/// Rejected transitions (i.e. not in the allowed table) are logged as invariant
/// violations via a Sentry breadcrumb at `level: warning` and produce no state change.
///
/// The state machine does NOT own the state — it delegates every allowed
/// transition to [RecordingNotifier]. The notifier remains the single source of
/// truth for [RecordingState].
///
/// ## Allowed transitions
/// ```
/// idle          ─start→        recording
/// recording     ─stop→         transcribing
/// recording     ─guardFire→    transcribing
/// recording     ─fail→         error
/// transcribing  ─complete→     done
/// transcribing  ─fail→         error
/// done          ─reset→        idle
/// error         ─reset→        idle
/// error         ─oomRetry→     recording
/// ```
library;

import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';

// ---------------------------------------------------------------------------
// RecordingIntent
// ---------------------------------------------------------------------------

/// All valid intents that can be requested from the orchestrator.
enum RecordingIntent {
  /// Start a new recording: idle → recording.
  start,

  /// User (or orchestrator) explicitly stops recording: recording → transcribing.
  stop,

  /// SafetyGuard fires auto-stop or dead-mic fallback: recording → transcribing.
  guardFire,

  /// A pipeline step has failed: any → error.
  fail,

  /// Transcription completed: transcribing → done.
  complete,

  /// Reset to idle from done or error: done/error → idle.
  reset,

  /// OOM recovery retry: error → recording (special-cased in [RecordingOrchestrator]).
  oomRetry,
}

// ---------------------------------------------------------------------------
// RecordingStateMachine
// ---------------------------------------------------------------------------

/// Enforces the recording phase transition table.
///
/// Call [transition] once per orchestrator state change.  Inject:
/// - [phaseReader] — a zero-argument function that returns the current
///   [RecordingPhase] without accessing protected notifier state.
/// - [notifier] — the [RecordingNotifier] that owns all state mutations.
///
/// The machine delegates every allowed transition to the notifier and
/// never reads or writes [RecordingNotifier.state] directly.
class RecordingStateMachine {
  RecordingStateMachine({required this._phaseReader, required this._notifier});

  static final _log = AppLogger('RecordingStateMachine');

  final RecordingPhase Function() _phaseReader;
  final RecordingNotifier _notifier;

  // Encoded transition table:
  // allowed[phase]![intent] → the handler to invoke on the notifier.
  // Using a nested Map keeps the allowed set explicit and exhaustively
  // verifiable in unit tests.
  //
  // Design note: [RecordingIntent.reset] is allowed from ALL phases because
  // the orchestrator's public reset() API is a forced teardown that must work
  // regardless of current state (e.g., user cancels mid-recording, OOM recovery).
  // This mirrors RecordingNotifier.reset() which says "Reset from any phase → idle".
  static final _allowed =
      <RecordingPhase, Map<RecordingIntent, _TransitionAction>>{
        RecordingPhase.idle: {
          RecordingIntent.start: _TransitionAction.startRecording,
          RecordingIntent.reset: _TransitionAction.reset,
        },
        RecordingPhase.recording: {
          RecordingIntent.stop: _TransitionAction.stopRecording,
          RecordingIntent.guardFire: _TransitionAction.stopRecording,
          RecordingIntent.fail: _TransitionAction.fail,
          RecordingIntent.reset: _TransitionAction.reset,
        },
        RecordingPhase.transcribing: {
          RecordingIntent.complete: _TransitionAction.completeTranscription,
          RecordingIntent.fail: _TransitionAction.fail,
          RecordingIntent.reset: _TransitionAction.reset,
        },
        RecordingPhase.done: {RecordingIntent.reset: _TransitionAction.reset},
        RecordingPhase.error: {
          RecordingIntent.reset: _TransitionAction.reset,
          // oomRetry resets to idle; the orchestrator then shows the OOM
          // dialog and the user re-triggers recording from idle.
          RecordingIntent.oomRetry: _TransitionAction.reset,
        },
      };

  /// Attempts to transition the state machine via [intent].
  ///
  /// [transcript] is forwarded to the notifier only when [intent] is
  /// [RecordingIntent.complete]. [errorMessage] is forwarded only when
  /// [intent] is [RecordingIntent.fail].
  ///
  /// Rejected transitions (phase/intent pair not in the table) emit a Sentry
  /// breadcrumb at `level: warning` and return without mutating state.
  ///
  /// Side-effect ordering is deterministic:
  ///   1. Guard check (read current phase from notifier state).
  ///   2. Look up action in the table.
  ///   3. If rejected → log breadcrumb → return.
  ///   4. If allowed → delegate to notifier.
  void transition(
    RecordingIntent intent, {
    String? errorMessage,
    String? transcript,
  }) {
    final current = _phaseReader();
    final action = _allowed[current]?[intent];

    if (action == null) {
      _logRejected(current, intent);
      return;
    }

    switch (action) {
      case _TransitionAction.startRecording:
        _notifier.startRecording();
      case _TransitionAction.stopRecording:
        _notifier.stopRecording();
      case _TransitionAction.completeTranscription:
        _notifier.completeTranscription(transcript ?? '');
      case _TransitionAction.fail:
        _notifier.fail(errorMessage ?? 'unknown_error');
      case _TransitionAction.reset:
        _notifier.reset();
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _logRejected(RecordingPhase phase, RecordingIntent intent) {
    // Log locally for diagnostics.
    _log.warning(
      'Rejected transition: phase=$phase intent=$intent '
      '(invariant violation)',
    );

    // Sentry breadcrumb at warning level — no PII.
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'recording_state_machine:rejected_transition',
        level: SentryLevel.warning,
        data: {'phase': phase.name, 'intent': intent.name},
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helper enum (private — callers never see this)
// ---------------------------------------------------------------------------

/// Describes which [RecordingNotifier] method to invoke for an allowed transition.
enum _TransitionAction {
  startRecording,
  stopRecording,
  completeTranscription,
  fail,
  reset,
}
