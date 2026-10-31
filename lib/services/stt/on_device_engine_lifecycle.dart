/// Engine-agnostic lifecycle contract for on-device STT backends.
///
/// [RecordingOrchestrator] previously read [localSttBundleProvider] directly
/// for every lifecycle signal (recording start/stop, prepare, idle-prewarm,
/// readiness/error snapshot) — an implicit assumption that "on-device" always
/// means the whisper.cpp server. This interface makes that contract explicit
/// so a second on-device engine (Parakeet/sherpa_onnx) can satisfy it without
/// the orchestrator special-casing engines at every call site.
///
/// [WhisperEngineLifecycleAdapter] is a pure pass-through to the existing
/// [SttServerStateNotifier] — zero behavior change for the whisper path.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stt_bundle.dart';

/// Minimal readiness/error snapshot the orchestrator needs, independent of
/// any single engine's internal state shape (whisper's [SttStatus] carries
/// far more than this — port, model tiers, benchmark flags — none of which
/// the orchestrator actually reads).
class EngineLifecycleStatus {
  const EngineLifecycleStatus({required this.isReady, this.errorMessage});

  final bool isReady;
  final String? errorMessage;
}

/// Lifecycle contract every on-device engine adapter must satisfy.
abstract class OnDeviceEngineLifecycle {
  /// Current readiness/error snapshot.
  EngineLifecycleStatus get status;

  /// Starts the backend if not already running (may take seconds — model
  /// load / cold start). Throws on failure.
  Future<void> ensureRunning();

  /// Best-effort warm-up so the first recording after app start doesn't pay
  /// the cold-start penalty. Failures are non-fatal.
  Future<void> prewarm();

  /// Stops the backend (e.g. after switching provider/model). Returns a
  /// [Future] that completes once native resources are actually freed —
  /// callers that need the process to stay alive until then (app quit) must
  /// await it; fire-and-forget callers can ignore the returned Future.
  Future<void> stop();

  /// Signals a recording session started (pauses idle-shutdown timers).
  void notifyRecordingStarted();

  /// Signals a recording session ended (resumes idle-shutdown timers).
  void notifyRecordingStopped();

  /// Signals a transcription finished (restarts the idle countdown).
  void notifyTranscriptionCompleted();
}

/// Adapts the existing whisper.cpp [SttServerStateNotifier] to
/// [OnDeviceEngineLifecycle]. Every method delegates 1:1 to the notifier
/// already used by [RecordingOrchestrator] — this adapter changes no
/// whisper behavior, only the call shape.
class WhisperEngineLifecycleAdapter implements OnDeviceEngineLifecycle {
  const WhisperEngineLifecycleAdapter(this.ref);

  final Ref ref;

  SttServerStateNotifier get _notifier =>
      ref.read(localSttBundleProvider.notifier);

  @override
  EngineLifecycleStatus get status {
    final s = ref.read(localSttBundleProvider);
    return EngineLifecycleStatus(
      isReady: s.isReady,
      errorMessage: s.errorMessage,
    );
  }

  @override
  Future<void> ensureRunning() => _notifier.ensureRunning();

  @override
  Future<void> prewarm() => _notifier.prewarm();

  @override
  Future<void> stop() => _notifier.stop();

  @override
  void notifyRecordingStarted() => _notifier.notifyRecordingStarted();

  @override
  void notifyRecordingStopped() => _notifier.notifyRecordingStopped();

  @override
  void notifyTranscriptionCompleted() =>
      _notifier.notifyTranscriptionCompleted();
}
