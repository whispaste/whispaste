/// Riverpod wiring of the media pause and duck (#563, #1511).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show MediaWhileRecording;
import '../../core/logging/app_logger.dart';
import '../path_service.dart' as paths;
import 'media_pause_backends.dart';
import 'media_pause_controller.dart';

final _log = AppLogger('MediaPause');

final mediaPauseBackendProvider = Provider<MediaPauseBackend>(
  (ref) => mediaPauseBackendFactory(),
);

final mediaDuckBackendProvider = Provider<MediaDuckBackend>(
  (ref) => mediaDuckBackendFactory(),
);

/// Seam for tests: widget tests keep the journal in memory.
DuckJournal Function() duckJournalFactory = () =>
    FileDuckJournal(p.join(paths.appDataDir(), 'media_duck_journal.json'));

final mediaPauseControllerProvider = Provider<MediaPauseController>(
  (ref) => MediaPauseController(
    backend: ref.watch(mediaPauseBackendProvider),
    duckBackend: ref.watch(mediaDuckBackendProvider),
    journal: duckJournalFactory(),
    mode: () =>
        ref.read(settingsProvider).value?.audioInput.mediaWhileRecording ??
        MediaWhileRecording.off,
  ),
);

/// Whether the system lets WhisPaste pause media; the settings list marks
/// "Pause" as not available when this is `false`.
final mediaPauseAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(mediaPauseBackendProvider).isAvailable(),
);

/// Whether the system lets WhisPaste turn playback down.
final mediaDuckAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(mediaDuckBackendProvider).isAvailable(),
);

/// macOS only: asks once for the automation permission of each supported
/// player that is running (Music, Spotify). Called when the user picks
/// "Pause", never during a dictation, so no system dialog interrupts it.
Future<void> requestMediaPlayerAccess() async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    await const MethodChannel(
      mediaPauseChannelName,
    ).invokeMethod<int>('requestPlayerAccess');
  } on PlatformException catch (e) {
    _log.warning('requestPlayerAccess failed: $e');
  } on MissingPluginException catch (e) {
    // No host (tests).
    _log.debug('requestPlayerAccess has no host', e);
  }
}
