/// Adapts [ParakeetEngineNotifier] to [OnDeviceEngineLifecycle] so
/// [RecordingOrchestrator] can drive either on-device engine through the same
/// call shape. See `lib/services/stt/on_device_engine_lifecycle.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../stt/on_device_engine_lifecycle.dart';
import 'parakeet_engine_notifier.dart';

class ParakeetEngineLifecycleAdapter implements OnDeviceEngineLifecycle {
  const ParakeetEngineLifecycleAdapter(this.ref);

  final Ref ref;

  ParakeetEngineNotifier get _notifier =>
      ref.read(parakeetEngineProvider.notifier);

  @override
  EngineLifecycleStatus get status {
    final s = ref.read(parakeetEngineProvider);
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

  // Parakeet has no idle-shutdown timer yet (Phase 1 scope, see
  // parakeet_transcriber.dart) — the worker isolate stays warm regardless of
  // recording activity, so these are no-ops rather than missing behavior.
  @override
  void notifyRecordingStarted() {}

  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}
