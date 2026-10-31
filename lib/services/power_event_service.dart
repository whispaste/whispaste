/// System sleep and wake for the recording safety net (ticket, matrix 9.5).
///
/// The native runners send `willSleep` just before the machine suspends and
/// `didWake` after it resumes, on the channel `com.whispaste.power`. A
/// recording that is running at sleep is finished, not discarded: the stop
/// path saves the audio and starts transcription. If that happened, the
/// on-device engine is checked again at wake.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'hotkey_service.dart';
import 'hotkey_self_heal.dart';
import '../core/recording/recording_state.dart';
import 'audio_service.dart';
import 'low_power_state.dart';
import 'recording_orchestrator.dart';
import 'stt_engine_lifecycle_provider.dart';

const powerEventChannelName = 'com.whispaste.power';

final _log = AppLogger('PowerEvents');

typedef PowerEventCallback = Future<void> Function();

/// Receives sleep and wake events from the native runner and dispatches them
/// to the two callbacks. Knows nothing about recordings itself.
class PowerEventService {
  PowerEventService({
    required this.onWillSleep,
    required this.onDidWake,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(powerEventChannelName);

  final PowerEventCallback onWillSleep;
  final PowerEventCallback onDidWake;
  final MethodChannel _channel;

  void start() => _channel.setMethodCallHandler(_handle);

  void stop() => _channel.setMethodCallHandler(null);

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'willSleep':
        await onWillSleep();
      case 'didWake':
        await onDidWake();
      default:
        throw MissingPluginException('Unknown power event ${call.method}');
    }
  }
}

/// Whether the speech engine should be re-warmed after the system woke up:
/// only for a local engine, never while a dictation is running, and not in
/// low-power mode.
bool shouldPrewarmAfterWake({
  required bool isLocalProvider,
  required bool isIdle,
  required LowPowerState lowPower,
}) => isLocalProvider && isIdle && !lowPowerBlocksAutoWarm(lowPower);

/// Delay between the wake signal and the engine re-warm.
const kWakePrewarmDelay = Duration(seconds: 3);

/// Kept alive for the whole app session. [WhisPasteApp] watches it at
/// startup so the channel handler is registered before the first sleep.
final powerEventServiceProvider = Provider<PowerEventService>((ref) {
  final service = PowerEventService(
    onWillSleep: () async {
      if (ref.read(recordingProvider).phase != RecordingPhase.recording) {
        return;
      }
      _log.info('System going to sleep during a recording — finishing it');
      await ref.read(recordingOrchestratorProvider.notifier).stopRecording();
    },
    onDidWake: () async {
      _log.info('System woke up');
      unawaited(
        ref
            .read(hotkeyServiceProvider.notifier)
            .requestHotkeyHeal(HotkeyHealTrigger.wake),
      );
      ref.read(audioServiceProvider.notifier).forgetMicStartCache();
      // Let the system settle (audio devices, GPU state) before the re-warm.
      await Future<void>.delayed(kWakePrewarmDelay);
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      final isIdle = ref.read(recordingProvider).phase == RecordingPhase.idle;
      final lowPower = await readLowPowerState();
      if (!shouldPrewarmAfterWake(
        isLocalProvider: settings.sttProviderType.isLocal,
        isIdle: isIdle,
        lowPower: lowPower,
      )) {
        if (lowPowerBlocksAutoWarm(lowPower)) {
          _log.info('Low-power mode is on: skipping the engine re-warm');
        }
        return;
      }
      // Always re-warm: VRAM may be lost across sleep even when the model was
      // still reported as loaded. prewarm() is idempotent and cheap when the
      // model is still loaded.
      try {
        await ref.read(onDeviceEngineLifecycleProvider).prewarm();
      } on Exception catch (e) {
        _log.warning('Engine prewarm after wake failed (non-fatal): $e');
      }
    },
  );

  service.start();
  ref.onDispose(service.stop);
  return service;
});
