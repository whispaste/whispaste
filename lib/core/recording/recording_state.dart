import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../../services/smart_mode/smart_mode_presets.dart' show SmartModePreset;

// ---------------------------------------------------------------------------
// Phase enum
// ---------------------------------------------------------------------------

/// Discrete phases of a recording lifecycle.
///
/// [refining] is a Smart-Mode-v2-only phase (ticket 02) between
/// [transcribing] and [done]: a local-model post-processing pass (e.g. the
/// Cleanup preset) runs while the state machine sits here. It never leads to
/// [error] — any refining failure or timeout falls back to [done] with the
/// raw transcript unchanged (`docs/adr/0009-smart-mode-never-blocks-prinzip.md`).
/// Recordings with no active Smart Mode preset skip this phase entirely and
/// transition [transcribing] → [done] exactly as before this ticket.
enum RecordingPhase { idle, recording, transcribing, refining, done, error }

/// Whether a dictation holds the transcriber: recording, transcribing or
/// refining. `done` and `error` are end states that stay until the next
/// action, so they do not count as busy. Every caller that asks "is a
/// dictation running" uses this one rule.
bool isDictationBusy(RecordingPhase phase) => switch (phase) {
  RecordingPhase.recording ||
  RecordingPhase.transcribing ||
  RecordingPhase.refining => true,
  RecordingPhase.idle || RecordingPhase.done || RecordingPhase.error => false,
};

/// Where a finished transcript goes. [clipboard] is today's behaviour
/// (`AfterTranscriptionAction` — clipboard/paste). [quickNote] appends it to
/// the exclusively-marked quick note instead, bypassing clipboard/paste
/// entirely (see `RecordingOrchestrator._handleAfterTranscription`).
/// [templateField] runs the identical recording/transcription pipeline but
/// skips every "done" side effect (paste/clipboard write, history entry) —
/// the transcript is instead picked up by `InteractiveSnippetController`,
/// which drives one `templateField` recording per field of an interactive
/// snippet and composes/pastes/saves the combined result itself once all
/// fields are done.
/// [selectionEdit] ("edit selection by voice", `internal-notes`)
/// treats the transcript as an *instruction*: the orchestrator reads the
/// foreground app's selection, runs the instruction over it with the Smart
/// Mode engine and pastes the result over the selection — no history entry,
/// no snippet picker, no text transforms.
enum RecordingTarget { clipboard, quickNote, templateField, selectionEdit }

/// State of the local STT server subprocess.
enum SttServerState { stopped, starting, ready, error }

// ---------------------------------------------------------------------------
// Immutable state
// ---------------------------------------------------------------------------

/// Complete snapshot of the recording state machine.
class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.idle,
    this.elapsed = Duration.zero,
    this.audioLevel = 0.0,
    this.transcript,
    this.errorMessage,
    this.sessionId,
    this.pasteFailed = false,
    this.copiedOnly = false,
    this.historyOnly = false,
    this.pasteUnconfirmed = false,
    this.pasted = false,
  });

  final RecordingPhase phase;
  final Duration elapsed;
  final double audioLevel;
  final String? transcript;
  final String? errorMessage;

  /// Unique correlation ID for this recording session.
  ///
  /// Generated when a recording starts, stays constant through the entire
  /// pipeline (recording → transcribing → done/error), and is included in
  /// all log entries and Sentry breadcrumbs for traceability.
  final String? sessionId;

  /// Set alongside [phase] `done` when this recording's after-transcription
  /// paste/insert attempt failed (an error tone + toast were already
  /// reported for it) — lets the UI skip the separate "transcription
  /// complete" success tone instead of playing a contradictory success
  /// chime right after the failure chime.
  final bool pasteFailed;

  /// The auto-paste block list stopped the paste, so the transcript is only on
  /// the clipboard (GS-075). Shown as "Nur kopiert" in the overlay.
  final bool copiedOnly;

  /// A blocked paste with the clipboard copy switched off (maintainer 4a+c):
  /// the transcript is only in the history. Shown as "Nicht eingefügt".
  final bool historyOnly;

  /// The paste was attempted and its outcome is not a confirmed paste (for
  /// example the target was changed during processing, or no read receipt
  /// could be armed). The transcript is on the clipboard. Shown as "In der
  /// Zwischenablage", never as "Eingefügt". Only set when the paste was
  /// attempted; [pasteFailed] and [copiedOnly] take precedence in the label.
  final bool pasteUnconfirmed;

  /// Set alongside [phase] `done` when the paste into the target app was
  /// confirmed (`PasteOutcome.success`). The only signal that a transcript
  /// really landed in another app; a clipboard-only or quick-note result is
  /// `false`. Read by the "Erste Schritte" card.
  final bool pasted;

  // -- convenience getters --------------------------------------------------

  bool get isIdle => phase == RecordingPhase.idle;
  bool get isRecording => phase == RecordingPhase.recording;
  bool get isTranscribing => phase == RecordingPhase.transcribing;
  bool get isRefining => phase == RecordingPhase.refining;
  bool get isDone => phase == RecordingPhase.done;
  bool get isError => phase == RecordingPhase.error;

  // -- copyWith -------------------------------------------------------------

  RecordingState copyWith({
    RecordingPhase? phase,
    Duration? elapsed,
    double? audioLevel,
    String? transcript,
    String? errorMessage,
    String? sessionId,
    bool? pasteFailed,
    bool? copiedOnly,
    bool? historyOnly,
    bool? pasteUnconfirmed,
    bool? pasted,
    // loam-ignore: code-duplicates – the repo-wide copyWith(field: field ?? this.field, ...) shape, shared by RecordingState and UpdateState.
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      audioLevel: audioLevel ?? this.audioLevel,
      transcript: transcript ?? this.transcript,
      errorMessage: errorMessage ?? this.errorMessage,
      sessionId: sessionId ?? this.sessionId,
      pasteFailed: pasteFailed ?? this.pasteFailed,
      copiedOnly: copiedOnly ?? this.copiedOnly,
      historyOnly: historyOnly ?? this.historyOnly,
      pasteUnconfirmed: pasteUnconfirmed ?? this.pasteUnconfirmed,
      pasted: pasted ?? this.pasted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingState &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          elapsed == other.elapsed &&
          audioLevel == other.audioLevel &&
          transcript == other.transcript &&
          errorMessage == other.errorMessage &&
          sessionId == other.sessionId &&
          pasteFailed == other.pasteFailed &&
          (copiedOnly, historyOnly, pasteUnconfirmed, pasted) ==
              (
                other.copiedOnly,
                other.historyOnly,
                other.pasteUnconfirmed,
                other.pasted,
              );

  @override
  int get hashCode => Object.hash(
    phase,
    elapsed,
    audioLevel,
    transcript,
    errorMessage,
    sessionId,
    pasteFailed,
    copiedOnly,
    historyOnly,
    pasteUnconfirmed,
    pasted,
  );

  @override
  String toString() =>
      'RecordingState(phase: $phase, elapsed: $elapsed, '
      'audioLevel: ${audioLevel.toStringAsFixed(2)}, '
      'transcript: $transcript, error: $errorMessage, '
      'session: $sessionId, pasteFailed: $pasteFailed)';
}

// ---------------------------------------------------------------------------
// Transcription budget
// ---------------------------------------------------------------------------

/// Budget per second of audio for the transcribing stuck-guards. A CPU-only
/// Whisper run has to finish within this many times the recording's length
/// before it counts as stuck. Not measured on CPU-only hardware; chosen so a
/// 60-minute recording gets three hours before it is abandoned.
const double kTranscriptionBudgetFactor = 3.0;

/// The stuck-guard budget for transcribing [audio]:
/// `max(floor, factor × audio)`.
///
/// Shared by the Whisper inference guard (`SttServerStateNotifier`) and the
/// transcribing guard in [RecordingNotifier]. [floor] is the minimum budget
/// (5 min in production), so short recordings keep their previous timeout.
/// Non-positive durations return [floor].
Duration transcriptionStuckBudget(Duration audio, {required Duration floor}) {
  final scaled = audio * kTranscriptionBudgetFactor;
  return scaled > floor ? scaled : floor;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages recording lifecycle transitions and the elapsed-time timer.
class RecordingNotifier extends Notifier<RecordingState> {
  static final _log = AppLogger('RecordingNotifier');

  Timer? _elapsedTimer;

  /// Safety-net timer: if the state machine stays in transcribing for longer
  /// than its budget (at least [_stuckTimeout]), auto-fail to unblock the UI.
  Timer? _stuckGuard;
  static const _stuckTimeout = Duration(minutes: 5);

  /// Safety-net timer for [RecordingPhase.refining] (Smart Mode v2, ticket
  /// 02). This is a last-resort backstop, not the primary timeout — the
  /// orchestrator's own engine-call timeout (`PipelineStepRunner`, seconds
  /// not minutes) is expected to fire first in practice. If it somehow
  /// doesn't (e.g. an isolate deadlock), this guard still guarantees the
  /// pipeline reaches `done` with the raw transcript rather than hanging
  /// forever — never `error`, per ADR 0009.
  Timer? _refiningGuard;
  static const _refiningTimeout = Duration(seconds: 30);

  @override
  RecordingState build() {
    ref.onDispose(() {
      _cancelTimer();
      _stuckGuard?.cancel();
      _refiningGuard?.cancel();
    });
    return const RecordingState();
  }

  // -- public transitions ---------------------------------------------------

  /// Transition idle → recording. Starts the elapsed timer.
  void startRecording() {
    if (state.phase != RecordingPhase.idle) {
      _log.debug('startRecording ignored – current phase: ${state.phase}');
      return;
    }
    final sid = _generateSessionId();
    state = RecordingState(phase: RecordingPhase.recording, sessionId: sid);
    _startTimer();
  }

  /// Transition recording → transcribing. Stops the timer.
  void stopRecording() {
    if (state.phase != RecordingPhase.recording) {
      _log.debug('stopRecording ignored – current phase: ${state.phase}');
      return;
    }
    _cancelTimer();
    state = state.copyWith(phase: RecordingPhase.transcribing, audioLevel: 0.0);
    _startStuckGuard();
  }

  /// Transition transcribing → refining (Smart Mode v2, ticket 02). Stores
  /// [interimTranscript] on the state immediately so [_refiningGuard] can
  /// fall back to it even if it fires before the orchestrator calls
  /// [completeTranscription] itself.
  void startRefining(String interimTranscript) {
    if (state.phase != RecordingPhase.transcribing) {
      _log.debug('startRefining ignored – current phase: ${state.phase}');
      return;
    }
    _stuckGuard?.cancel();
    state = state.copyWith(
      phase: RecordingPhase.refining,
      transcript: interimTranscript,
    );
    _startRefiningGuard();
  }

  /// Transition transcribing/refining → done.
  ///
  /// [pasteFailed] carries whether this recording's after-transcription
  /// paste/insert attempt failed — set on the resulting state so the UI can
  /// skip the "transcription complete" success tone for it (an error tone
  /// was already played for the paste failure itself).
  void completeTranscription(
    String text, {
    bool pasteFailed = false,
    bool copiedOnly = false,
    bool historyOnly = false,
    bool pasteUnconfirmed = false,
    bool pasted = false,
  }) {
    if (state.phase != RecordingPhase.transcribing &&
        state.phase != RecordingPhase.refining) {
      _log.debug(
        'completeTranscription ignored – current phase: ${state.phase}',
      );
      return;
    }
    _stuckGuard?.cancel();
    _refiningGuard?.cancel();
    _log.debug('Phase ${state.phase} → done (text: ${text.length} chars)');
    state = state.copyWith(
      phase: RecordingPhase.done,
      transcript: text,
      pasteFailed: pasteFailed,
      copiedOnly: copiedOnly,
      historyOnly: historyOnly,
      pasteUnconfirmed: pasteUnconfirmed,
      pasted: pasted,
    );
  }

  /// Transition any phase → error. [transcript] is kept when the finished
  /// text is still worth offering (e.g. a failed quick-note append, so the
  /// error toast can copy it).
  void fail(String error, {String? transcript}) {
    _cancelTimer();
    _stuckGuard?.cancel();
    _refiningGuard?.cancel();
    state = RecordingState(
      phase: RecordingPhase.error,
      errorMessage: error,
      transcript: transcript,
    );
  }

  /// Reset from any phase → idle.
  void reset() {
    final prevPhase = state.phase;
    _cancelTimer();
    _stuckGuard?.cancel();
    _refiningGuard?.cancel();
    _log.debug('Phase $prevPhase → idle (reset)');
    state = const RecordingState();
  }

  /// Update the current microphone level (0.0–1.0).
  /// Only effective while [phase] is [RecordingPhase.recording].
  void updateAudioLevel(double level) {
    if (state.phase != RecordingPhase.recording) return;
    state = state.copyWith(audioLevel: level.clamp(0.0, 1.0));
  }

  // -- internal timer -------------------------------------------------------

  void _startTimer() {
    _cancelTimer();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase == RecordingPhase.recording) {
        state = state.copyWith(
          elapsed: state.elapsed + const Duration(seconds: 1),
        );
      }
    });
  }

  void _cancelTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  /// Safety net: auto-fail if stuck in transcribing too long.
  void _startStuckGuard() {
    _stuckGuard?.cancel();
    // The budget scales with the recording's length (`state.elapsed`), with
    // [_stuckTimeout] as the floor for short recordings.
    final budget = transcriptionStuckBudget(
      state.elapsed,
      floor: _stuckTimeout,
    );
    _stuckGuard = Timer(budget, () {
      if (state.phase == RecordingPhase.transcribing) {
        _log.error(
          'State machine stuck in ${state.phase} for '
          '${budget.inMinutes} min — auto-failing '
          '(session=${state.sessionId})',
        );
        fail('pipeline_timeout');
      }
    });
  }

  /// Safety net: silently fall back to `done` with the raw transcript if
  /// stuck in refining too long. Never transitions to `error` — see
  /// [_refiningGuard]'s doc comment.
  void _startRefiningGuard() {
    _refiningGuard?.cancel();
    _refiningGuard = Timer(_refiningTimeout, () {
      if (state.phase == RecordingPhase.refining) {
        _log.warning(
          'State machine stuck in refining for '
          '${_refiningTimeout.inSeconds}s — falling back to raw transcript '
          '(session=${state.sessionId})',
        );
        completeTranscription(state.transcript ?? '');
      }
    });
  }

  /// Generates a short, unique-enough correlation ID for log tracing.
  ///
  /// Format: `<base36-timestamp>-<hex-random>` e.g. `"m1abc2d-3f7a"`.
  /// Not cryptographic — just needs to be unique within a user session.
  static final _rng = math.Random();
  static String _generateSessionId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = _rng.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$ts-$rnd';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Primary recording state provider.
final recordingProvider = NotifierProvider<RecordingNotifier, RecordingState>(
  RecordingNotifier.new,
);

/// Whether the app is currently recording (backward-compatible bool).
final isRecordingProvider = Provider<bool>((ref) {
  return ref.watch(recordingProvider.select((s) => s.isRecording));
});

/// Current microphone audio level (0.0–1.0) for VU / waveform widgets.
final audioLevelProvider = Provider<double>((ref) {
  return ref.watch(recordingProvider.select((s) => s.audioLevel));
});

/// Elapsed recording duration for timer display.
final recordingElapsedProvider = Provider<Duration>((ref) {
  return ref.watch(recordingProvider.select((s) => s.elapsed));
});

/// Current recording phase.
final recordingPhaseProvider = Provider<RecordingPhase>((ref) {
  return ref.watch(recordingProvider.select((s) => s.phase));
});

/// The main hotkey latched a hands-free recording (double tap): releasing
/// the key no longer stops it. Set by the trigger handler; a page reads it
/// together with [recordingPhaseProvider], because a recording that ends
/// elsewhere clears the latch only on the next press.
class HandsFreeRecordingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool handsFree) => state = handsFree;
}

final handsFreeRecordingProvider =
    NotifierProvider<HandsFreeRecordingNotifier, bool>(
      HandsFreeRecordingNotifier.new,
    );

/// Current recording session correlation ID (null when idle).
final recordingSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(recordingProvider.select((s) => s.sessionId));
});

/// Lightweight info notification channel for the recording pipeline.
///
/// Set by the orchestrator when a non-error condition needs user feedback
/// (e.g. "server is downloading"). Listened to by the UI for info toasts.
/// Auto-cleared after reading.
class RecordingInfoNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String code) => state = code;
  void clear() => state = null;
}

final recordingInfoProvider = NotifierProvider<RecordingInfoNotifier, String?>(
  RecordingInfoNotifier.new,
);

/// Pending CUDA OOM recovery context for the recording UI.
typedef OomRecoveryState = ({
  bool pending,
  String? nextModelId,
  bool hasCloudConfigured,
  bool isPermanentFail,
  String? cloudProviderName,
});

class OomRecoveryNotifier extends Notifier<OomRecoveryState> {
  @override
  OomRecoveryState build() {
    return (
      pending: false,
      nextModelId: null,
      hasCloudConfigured: false,
      isPermanentFail: false,
      cloudProviderName: null,
    );
  }

  void showPending({
    required String? nextModelId,
    required bool hasCloudConfigured,
    required bool isPermanentFail,
    String? cloudProviderName,
  }) {
    state = (
      pending: true,
      nextModelId: nextModelId,
      hasCloudConfigured: hasCloudConfigured,
      isPermanentFail: isPermanentFail,
      cloudProviderName: cloudProviderName,
    );
  }

  void clear() {
    state = (
      pending: false,
      nextModelId: null,
      hasCloudConfigured: false,
      isPermanentFail: false,
      cloudProviderName: null,
    );
  }
}

final oomRecoveryPendingProvider =
    NotifierProvider<OomRecoveryNotifier, OomRecoveryState>(
      OomRecoveryNotifier.new,
    );

/// The active recording's target, readable outside the orchestrator (e.g. by
/// the recording overlay, ticket 25) — unlike
/// `RecordingOrchestrator._hotkeyPressedAtForLatencyKpi`, which is
/// deliberately internal-only. Set unconditionally at the start of every
/// recording (never reset at stop/finish) — see `startRecording`'s doc
/// comment on why "next start always overwrites" beats "reset at every exit
/// path".
class RecordingTargetNotifier extends Notifier<RecordingTarget> {
  @override
  RecordingTarget build() => RecordingTarget.clipboard;

  void set(RecordingTarget target) => state = target;
}

final recordingTargetProvider =
    NotifierProvider<RecordingTargetNotifier, RecordingTarget>(
      RecordingTargetNotifier.new,
    );

/// A Smart-Mode preset forced onto the active recording, overriding
/// `settings.smartMode.standardPreset` for that recording only (ticket 04 of
/// `internal-notes`: the Smart-Mode hotkey applies its bound preset
/// independently of the main hotkey's standard preset). `null` means "no
/// override — use the standard preset as usual", which is what every
/// non-Smart-Mode-hotkey caller passes.
///
/// Same "next start always overwrites, never reset at exit" convention as
/// [RecordingTargetNotifier] — see its doc comment for the rationale.
class SmartModeHotkeyOverridePresetNotifier extends Notifier<SmartModePreset?> {
  @override
  SmartModePreset? build() => null;

  void set(SmartModePreset? preset) => state = preset;
}

final smartModeHotkeyOverridePresetProvider =
    NotifierProvider<SmartModeHotkeyOverridePresetNotifier, SmartModePreset?>(
      SmartModeHotkeyOverridePresetNotifier.new,
    );

/// An STT language code forced onto the active recording, overriding
/// `settings.sttLanguageCode` for that recording only — used by the
/// Automation API's `POST /v1/dictation/trigger` `language` field so a
/// single triggered dictation can target a different language without
/// touching the persisted Settings value. `null` means "no override — use
/// the configured language as usual", which is what every non-API caller
/// (main hotkey, floating button) passes.
///
/// Same "next start always overwrites, never reset at exit" convention as
/// [RecordingTargetNotifier] — see its doc comment for the rationale.
class SttLanguageOverrideNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? languageCode) => state = languageCode;
}

final sttLanguageOverrideProvider =
    NotifierProvider<SttLanguageOverrideNotifier, String?>(
      SttLanguageOverrideNotifier.new,
    );

/// The transcription language the current recording actually runs with, as
/// shown by the overlay's language chip (SW-10). Set by the orchestrator at
/// start (override, else the global setting, SW-03) and replaced once more
/// when the target app's profile language resolves (SW-07). Settings changes
/// never reach it. `null` before the first recording.
class RecordingLanguageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? languageCode) => state = languageCode;
}

final recordingLanguageProvider =
    NotifierProvider<RecordingLanguageNotifier, String?>(
      RecordingLanguageNotifier.new,
    );

/// The app profile the current recording runs with, by name (ticket 13, part
/// 3): the manual choice, or the profile the per-app rules matched for the
/// target at start. `null` when no profile applies. The overlay chip reads it;
/// the orchestrator sets it, and each new recording starts with `null`.
class RecordingProfileNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? profileName) => state = profileName;
}

final recordingProfileProvider =
    NotifierProvider<RecordingProfileNotifier, String?>(
      RecordingProfileNotifier.new,
    );

/// An auto-stop-on-silence timeout (in seconds) forced onto the active
/// recording, overriding `settings.recordingSafety.autoStopSilence` for that
/// recording only — used by the Automation API's `POST /v1/dictation/trigger`
/// `silence_timeout` field so a single triggered dictation can lengthen,
/// shorten, or (`0`) disable silence auto-stop without touching the
/// persisted Settings value. `null` means "no override — use the configured
/// timeout as usual", which is what every non-API caller (main hotkey,
/// floating button) passes.
///
/// Same "next start always overwrites, never reset at exit" convention as
/// [RecordingTargetNotifier] — see its doc comment for the rationale.
class AutoStopSilenceOverrideNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void set(double? seconds) => state = seconds;
}

final autoStopSilenceOverrideProvider =
    NotifierProvider<AutoStopSilenceOverrideNotifier, double?>(
      AutoStopSilenceOverrideNotifier.new,
    );
