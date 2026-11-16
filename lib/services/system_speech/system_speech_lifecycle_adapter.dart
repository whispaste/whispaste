/// Adapts the system speech engine to [OnDeviceEngineLifecycle]. The system
/// keeps its own language assets, so the app has no process to start or stop.
/// Prewarm loads the model for the language chosen in Settings, at app start
/// and when a recording starts, so the first result arrives sooner.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../stt/on_device_engine_lifecycle.dart';
import 'system_speech_channel.dart';
import 'system_speech_status.dart';

final _log = AppLogger('SystemSpeech');

class SystemSpeechLifecycleAdapter implements OnDeviceEngineLifecycle {
  const SystemSpeechLifecycleAdapter(this.ref);

  final Ref ref;

  @override
  EngineLifecycleStatus get status =>
      const EngineLifecycleStatus(isReady: true, errorMessage: null);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {}

  /// Loads the model for the configured language. An automatic language or an
  /// unsupported OS has nothing to load; failures stay silent because the
  /// recording falls back to the local engine anyway.
  @override
  Future<void> prewarm() async {
    if (!systemSpeechOsSupported()) return;
    final locale = systemSpeechLocaleFor(
      ref.read(settingsProvider).value?.sttLanguageCode,
    );
    if (locale == null) return;
    try {
      await ref.read(systemSpeechChannelProvider).prewarm(locale);
    } on SystemSpeechException catch (e) {
      _log.debug('prewarm skipped: ${e.code}');
    }
  }

  @override
  Future<void> stop() async {}

  @override
  void notifyRecordingStarted() => unawaited(prewarm());

  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}
