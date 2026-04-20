import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import '../logging/app_logger.dart';
import '../../services/model_download_service.dart';

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
    this.sessionId,
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
    String? sessionId,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      audioLevel: audioLevel ?? this.audioLevel,
      transcript: transcript ?? this.transcript,
      errorMessage: errorMessage ?? this.errorMessage,
      sessionId: sessionId ?? this.sessionId,
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
          sessionId == other.sessionId;

  @override
  int get hashCode => Object.hash(
    phase,
    elapsed,
    audioLevel,
    transcript,
    errorMessage,
    sessionId,
  );

  @override
  String toString() =>
      'RecordingState(phase: $phase, elapsed: $elapsed, '
      'audioLevel: ${audioLevel.toStringAsFixed(2)}, '
      'transcript: $transcript, error: $errorMessage, '
      'session: $sessionId)';
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

  /// Transition transcribing/processing → done (no LLM post-processing).
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

  /// Transition any phase → error.
  void fail(String error) {
    _cancelTimer();
    _stuckGuard?.cancel();
    state = RecordingState(phase: RecordingPhase.error, errorMessage: error);
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
          '${_stuckTimeout.inMinutes} min — auto-failing '
          '(session=${state.sessionId})',
        );
        fail('pipeline_timeout');
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

/// Current recording session correlation ID (null when idle).
final recordingSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(recordingProvider.select((s) => s.sessionId));
});

// ---------------------------------------------------------------------------
// Recording readiness — can the system start a recording?
// ---------------------------------------------------------------------------

/// Pre-conditions for starting a recording.
enum RecordingReadiness {
  /// Everything is set — server binary + model present.
  ready,

  /// Server binary missing, not currently downloading.
  serverMissing,

  /// Server binary is being auto-downloaded.
  serverDownloading,

  /// Selected model file is missing.
  modelMissing,
}

/// Computed readiness state — watches download state + settings.
final recordingReadinessProvider = Provider<RecordingReadiness>((ref) {
  final dl = ref.watch(modelDownloadProvider);
  final settings = ref.watch(settingsProvider).value;

  // While settings are loading or onboarding isn't done, report ready
  // and let the orchestrator's hard preflight catch those cases.
  if (settings == null || !settings.onboardingCompleted) {
    return RecordingReadiness.ready;
  }

  if (!dl.serverReady) {
    if (dl.isBusy) return RecordingReadiness.serverDownloading;
    return RecordingReadiness.serverMissing;
  }

  final modelId = settings.effectiveModelId;
  if (!dl.downloadedModels.contains(modelId)) {
    return RecordingReadiness.modelMissing;
  }

  return RecordingReadiness.ready;
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
});

class OomRecoveryNotifier extends Notifier<OomRecoveryState> {
  @override
  OomRecoveryState build() {
    return (
      pending: false,
      nextModelId: null,
      hasCloudConfigured: false,
      isPermanentFail: false,
    );
  }

  void showPending({
    required String? nextModelId,
    required bool hasCloudConfigured,
    required bool isPermanentFail,
  }) {
    state = (
      pending: true,
      nextModelId: nextModelId,
      hasCloudConfigured: hasCloudConfigured,
      isPermanentFail: isPermanentFail,
    );
  }

  void clear() {
    state = (
      pending: false,
      nextModelId: null,
      hasCloudConfigured: false,
      isPermanentFail: false,
    );
  }
}

final oomRecoveryPendingProvider =
    NotifierProvider<OomRecoveryNotifier, OomRecoveryState>(
      OomRecoveryNotifier.new,
    );
