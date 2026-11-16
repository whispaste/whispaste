/// Riverpod wiring of the media pause (#563).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'media_pause_backends.dart';
import 'media_pause_controller.dart';

final mediaPauseBackendProvider = Provider<MediaPauseBackend>(
  (ref) => mediaPauseBackendFactory(),
);

final mediaPauseControllerProvider = Provider<MediaPauseController>(
  (ref) => MediaPauseController(
    backend: ref.watch(mediaPauseBackendProvider),
    isEnabled: () =>
        ref.read(settingsProvider).value?.audioInput.pauseMediaWhileRecording ??
        false,
  ),
);

/// Whether the system lets WhisPaste pause media; the settings row shows
/// "not available" when this is `false`.
final mediaPauseAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(mediaPauseBackendProvider).isAvailable(),
);
