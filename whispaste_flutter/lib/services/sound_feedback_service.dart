/// Sound feedback service — plays audio cues for recording events.
///
/// Reads the three sound-feedback toggles from [AppSettings] and plays the
/// corresponding WAV asset when enabled. Failures are silently logged —
/// sound feedback is non-critical and must never block the recording pipeline.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SoundFeedbackService extends Notifier<void> {
  static final _log = AppLogger('SoundFeedback');

  AudioPlayer? _player;

  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  @override
  void build() {
    ref.onDispose(() {
      _player?.dispose();
      _player = null;
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Plays the recording-start sound if enabled in settings.
  Future<void> playRecordStart() => _play('start.wav', _settings.recordStartSound);

  /// Plays the recording-stop sound if enabled in settings.
  Future<void> playRecordStop() => _play('stop.wav', _settings.recordStopSound);

  /// Plays the transcription-complete sound if enabled in settings.
  Future<void> playTranscriptionComplete() =>
      _play('success.wav', _settings.transcriptionCompleteSound);

  /// Plays the error sound (always plays when called — caller decides when).
  Future<void> playError() => _play('error.wav', true);

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled) return;

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/$assetName'));
    } on Exception catch (e) {
      _log.debug('Sound playback failed ($assetName): $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
