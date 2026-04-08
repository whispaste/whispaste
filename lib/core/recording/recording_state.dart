import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Phase enum
// ---------------------------------------------------------------------------

/// Discrete phases of a recording lifecycle.
enum RecordingPhase { idle, recording, transcribing, processing, done, error }

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
  });

  final RecordingPhase phase;
  final Duration elapsed;
  final double audioLevel;
  final String? transcript;
  final String? errorMessage;

  // -- convenience getters --------------------------------------------------

  bool get isIdle => phase == RecordingPhase.idle;
  bool get isRecording => phase == RecordingPhase.recording;
  bool get isTranscribing => phase == RecordingPhase.transcribing;
  bool get isProcessing => phase == RecordingPhase.processing;
  bool get isDone => phase == RecordingPhase.done;
  bool get isError => phase == RecordingPhase.error;

  // -- copyWith -------------------------------------------------------------

  RecordingState copyWith({
    RecordingPhase? phase,
    Duration? elapsed,
    double? audioLevel,
    String? transcript,
    String? errorMessage,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      audioLevel: audioLevel ?? this.audioLevel,
      transcript: transcript ?? this.transcript,
      errorMessage: errorMessage ?? this.errorMessage,
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
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        phase,
        elapsed,
        audioLevel,
        transcript,
        errorMessage,
      );

  @override
  String toString() =>
      'RecordingState(phase: $phase, elapsed: $elapsed, '
      'audioLevel: ${audioLevel.toStringAsFixed(2)}, '
      'transcript: $transcript, error: $errorMessage)';
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages recording lifecycle transitions and the elapsed-time timer.
class RecordingNotifier extends Notifier<RecordingState> {
  static final _log = AppLogger('RecordingNotifier');

  Timer? _elapsedTimer;

  /// Safety-net timer: if the state machine stays in transcribing/processing
  /// for longer than this, auto-fail to unblock the UI.
  Timer? _stuckGuard;
  static const _stuckTimeout = Duration(minutes: 5);

  @override
  RecordingState build() {
    ref.onDispose(() {
      _cancelTimer();
      _stuckGuard?.cancel();
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
    state = const RecordingState(phase: RecordingPhase.recording);
    _startTimer();
  }

  /// Transition recording → transcribing. Stops the timer.
  void stopRecording() {
    if (state.phase != RecordingPhase.recording) {
      _log.debug('stopRecording ignored – current phase: ${state.phase}');
      return;
    }
    _cancelTimer();
    state = state.copyWith(
      phase: RecordingPhase.transcribing,
      audioLevel: 0.0,
    );
    _startStuckGuard();
  }

  /// Transition transcribing → done with the resulting [text].
  void completeTranscription(String text) {
    if (state.phase != RecordingPhase.transcribing &&
        state.phase != RecordingPhase.processing) {
      _log.debug(
        'completeTranscription ignored – current phase: ${state.phase}',
      );
      return;
    }
    _stuckGuard?.cancel();
    _log.debug('Phase ${state.phase} → done (text: ${text.length} chars)');
    state = state.copyWith(phase: RecordingPhase.done, transcript: text);
  }

  /// Transition transcribing → processing (post-processing via LLM).
  void startProcessing() {
    if (state.phase != RecordingPhase.transcribing) {
      _log.debug('startProcessing ignored – current phase: ${state.phase}');
      return;
    }
    state = state.copyWith(phase: RecordingPhase.processing);
    // Restart stuck guard for the processing phase.
    _startStuckGuard();
  }

  /// Transition any phase → error.
  void fail(String error) {
    _cancelTimer();
    _stuckGuard?.cancel();
    state = RecordingState(
      phase: RecordingPhase.error,
      errorMessage: error,
    );
  }

  /// Reset from any phase → idle.
  void reset() {
    final prevPhase = state.phase;
    _cancelTimer();
    _stuckGuard?.cancel();
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

  /// Safety net: auto-fail if stuck in transcribing/processing too long.
  void _startStuckGuard() {
    _stuckGuard?.cancel();
    _stuckGuard = Timer(_stuckTimeout, () {
      if (state.phase == RecordingPhase.transcribing ||
          state.phase == RecordingPhase.processing) {
        _log.error(
          'State machine stuck in ${state.phase} for '
          '${_stuckTimeout.inMinutes} min — auto-failing',
        );
        fail('pipeline_timeout');
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Primary recording state provider.
final recordingProvider =
    NotifierProvider<RecordingNotifier, RecordingState>(RecordingNotifier.new);

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
