/// The dictation path of a user's own sherpa-onnx model (#1789): the engine
/// state behind [OnDeviceEngine.userModel], its [Transcriber] and its
/// lifecycle adapter.
///
/// One [UserSherpaEngine] at a time, for the `user-…` id the settings name.
/// Changing the id stops the old engine. Like Parakeet it stays warm for the
/// session; failures surface as [StateError]s that the guard
/// (`user_model_guards.dart`) turns into a fallback.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../audio/wav_header_repair.dart';
import '../model_hardware_telemetry.dart' show modelLifecycleTelemetryProvider;
import '../model_telemetry_identity.dart' show ownModelFactsFrom, ownModelKey;
import '../stt/on_device_engine_lifecycle.dart';
import '../transcription/transcriber_interface.dart';
import 'user_models_provider.dart';
import 'user_sherpa_engine.dart';

final _log = AppLogger('UserSherpaRuntime');

/// Readiness of the own sherpa-onnx engine.
class UserSherpaStatus {
  const UserSherpaStatus({this.modelId, this.isReady = false, this.error});

  final String? modelId;
  final bool isReady;
  final String? error;
}

/// Loads, runs and stops the own sherpa-onnx model the settings name.
class UserSherpaEngineNotifier extends Notifier<UserSherpaStatus> {
  UserSherpaEngine? _engine;
  Future<void>? _starting;

  @override
  UserSherpaStatus build() {
    ref.listen(settingsProvider.select((s) => s.value?.stt.model), (
      prev,
      next,
    ) {
      if (prev != next && _engine != null) unawaited(stop());
    });
    ref.onDispose(() => unawaited(_engine?.stop()));
    return const UserSherpaStatus();
  }

  String get _modelId =>
      (ref.read(settingsProvider).value ?? AppSettings.defaults)
          .effectiveModelId;

  /// Loads the model when it is not running yet. Throws [StateError] when it
  /// is missing, not ready or does not load.
  Future<void> ensureRunning() async {
    final id = _modelId;
    if (_engine != null && state.modelId == id && state.isReady) return;
    final running = _starting;
    if (running != null) return running;
    final start = _start(id);
    _starting = start;
    try {
      await start;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(String id) async {
    await stop();
    final store = ref.read(userModelStoreProvider);
    final model = store.readSync().byId(id);
    if (model == null || !model.isReady) {
      state = UserSherpaStatus(modelId: id, error: 'stt_model_file_missing');
      throw StateError('stt_model_file_missing');
    }
    final engine = UserSherpaEngine(model: model, dir: store.modelDir(id));
    // Native code runs the model in this process: a crash during the load
    // takes it out of use at the next start.
    store.markInFlight(id);
    try {
      await engine.start(cores: Platform.numberOfProcessors);
    } on Object catch (e) {
      _log.warning('Own model $id did not load: ${e.runtimeType}');
      try {
        // Usage statistics (#1791): the model key and fixed values only.
        ref
            .read(modelLifecycleTelemetryProvider)
            .loadFailed(
              ownModelKey(ownModelFactsFrom(model)),
              cause: 'file',
              gpu: false,
            );
      } on Object catch (t) {
        _log.debug('model telemetry skipped: ${t.runtimeType}');
      }
      state = UserSherpaStatus(modelId: id, error: 'stt_model_load_failed');
      throw StateError('stt_model_load_failed');
    } finally {
      store.clearInFlight();
    }
    _engine = engine;
    state = UserSherpaStatus(modelId: id, isReady: true);
  }

  /// Transcribes WhisPaste's canonical 16 kHz mono PCM16 WAV.
  Future<String> transcribe(List<int> wav, {Duration? timeout}) async {
    await ensureRunning();
    return _engine!.transcribe(repairWavHeader(wav), timeout: timeout);
  }

  Future<void> stop() async {
    final engine = _engine;
    _engine = null;
    state = const UserSherpaStatus();
    await engine?.stop();
  }
}

final userSherpaEngineProvider =
    NotifierProvider<UserSherpaEngineNotifier, UserSherpaStatus>(
      UserSherpaEngineNotifier.new,
    );

/// How long one recording may take on an own model: generous, since the
/// model's speed is unknown; past it the audio is kept for a retry.
Duration userSherpaTimeLimit(List<int> wav) {
  // 32 000 bytes per second of 16 kHz mono PCM16.
  final seconds = wav.length ~/ 32000;
  return Duration(seconds: 60 + seconds * 2);
}

/// [Transcriber] for [OnDeviceEngine.userModel].
class UserSherpaTranscriber implements Transcriber {
  const UserSherpaTranscriber({required this.ref});

  final Ref ref;

  UserSherpaEngineNotifier get _notifier =>
      ref.read(userSherpaEngineProvider.notifier);

  @override
  Future<void> prepare() async {
    try {
      await _notifier.ensureRunning();
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    try {
      return await _notifier.transcribe(
        wavBytes,
        timeout: userSherpaTimeLimit(wavBytes),
      );
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  void release() {}
}

/// [OnDeviceEngineLifecycle] for [OnDeviceEngine.userModel].
class UserSherpaLifecycleAdapter implements OnDeviceEngineLifecycle {
  const UserSherpaLifecycleAdapter(this.ref);

  final Ref ref;

  UserSherpaEngineNotifier get _notifier =>
      ref.read(userSherpaEngineProvider.notifier);

  @override
  EngineLifecycleStatus get status {
    final s = ref.read(userSherpaEngineProvider);
    return EngineLifecycleStatus(isReady: s.isReady, errorMessage: s.error);
  }

  @override
  Future<void> ensureRunning({bool warmup = true}) => _notifier.ensureRunning();

  // An own model is loaded on the first recording, never ahead of it: a model
  // that crashes must not take the app down at start.
  @override
  Future<void> prewarm() async {}

  @override
  Future<void> stop() => _notifier.stop();

  @override
  void notifyRecordingStarted() {}

  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}
