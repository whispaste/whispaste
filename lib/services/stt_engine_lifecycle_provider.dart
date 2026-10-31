/// Resolves the active on-device engine's [OnDeviceEngineLifecycle] adapter
/// based on the current [AppSettings.onDeviceEngine] setting.
///
/// [RecordingOrchestrator] reads this provider instead of reaching directly
/// into whisper's `localSttBundleProvider` — see
/// `lib/services/stt/on_device_engine_lifecycle.dart` for the rationale.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import 'stt/on_device_engine_lifecycle.dart';
import 'stt_parakeet/parakeet_lifecycle_adapter.dart';

final onDeviceEngineLifecycleProvider = Provider<OnDeviceEngineLifecycle>((
  ref,
) {
  final settings = ref.watch(settingsProvider).value;
  final engine = settings?.onDeviceEngine ?? OnDeviceEngine.whisper;

  return switch (engine) {
    OnDeviceEngine.whisper => WhisperEngineLifecycleAdapter(ref),
    OnDeviceEngine.parakeet => ParakeetEngineLifecycleAdapter(ref),
  };
});
