/// Sound feedback service — plays audio cues for recording events.
///
/// Uses fire-and-forget [AudioPlayer] instances so rapid successive sounds
/// (start → stop → complete) never interfere with each other. Each cue
/// creates its own player, plays the asset, and self-disposes on completion.
///
/// Failures are silently logged — sound feedback is non-critical and must
/// never block the recording pipeline.
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

  bool _pluginAvailable = true;
  final List<AudioPlayer> _activePlayers = [];

  @override
  void build() {
    ref.onDispose(_disposeAll);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Plays the recording-start sound if enabled in settings.
  Future<void> playRecordStart() =>
      _play('start.wav', _settings.recordStartSound);

  /// Plays the recording-stop sound if enabled in settings.
  Future<void> playRecordStop() =>
      _play('stop.wav', _settings.recordStopSound);

  /// Plays the transcription-complete sound if enabled in settings.
  Future<void> playTranscriptionComplete() =>
      _play('success.wav', _settings.transcriptionCompleteSound);

  /// Plays the error sound (always plays when called — caller decides when).
  Future<void> playError() => _play('error.wav', true);

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled || !_pluginAvailable) return;

    try {
      final player = AudioPlayer();
      _activePlayers.add(player);

      // Set volume from settings (0.0–1.0).
      final volume = _settings.soundVolume / 100.0;
      await player.setVolume(volume);

      // Self-dispose when done playing.
      player.onPlayerComplete.listen((_) {
        _activePlayers.remove(player);
        player.dispose();
      });

      await player.play(AssetSource('sounds/$assetName'));
    } on Exception catch (e) {
      // MissingPluginException or other native failure — disable permanently.
      if (e.toString().contains('MissingPlugin')) {
        _log.warning('audioplayers plugin unavailable: $e');
        _pluginAvailable = false;
      } else {
        _log.debug('Sound playback failed ($assetName): $e');
      }
    }
  }

  void _disposeAll() {
    for (final player in _activePlayers) {
      try {
        player.dispose();
      } on Exception catch (_) {}
    }
    _activePlayers.clear();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
