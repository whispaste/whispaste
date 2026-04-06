/// Sound feedback service — plays audio cues for recording events.
///
/// Uses a small pool of pre-initialized [AudioPlayer] instances (one per
/// sound type) for reliability. Players are reused across calls to avoid
/// per-call native resource allocation that can fail on Windows.
///
/// Failures are silently logged — sound feedback is non-critical and must
/// never block the recording pipeline.
library;

import 'dart:async';

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
  final Map<String, AudioPlayer> _pool = {};
  final Map<String, Timer> _cleanupTimers = {};

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

  AudioPlayer _getOrCreatePlayer(String assetName) {
    return _pool.putIfAbsent(assetName, () {
      _log.debug('Creating audio player for $assetName');
      return AudioPlayer();
    });
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled || !_pluginAvailable) return;

    try {
      final player = _getOrCreatePlayer(assetName);

      // Stop any in-progress playback before starting new.
      await player.stop();

      // Set volume from settings (0.0–1.0).
      final volume = _settings.soundVolume / 100.0;
      await player.setVolume(volume);

      await player.play(AssetSource('sounds/$assetName'));

      // Safety timer: force-stop after 4s in case onPlayerComplete never fires.
      _cleanupTimers[assetName]?.cancel();
      _cleanupTimers[assetName] = Timer(const Duration(seconds: 4), () {
        player.stop().catchError((_) {});
      });

      _log.debug('Playing $assetName (vol: ${(volume * 100).round()}%)');
    } on Exception catch (e) {
      if (e.toString().contains('MissingPlugin')) {
        _log.warning('audioplayers plugin unavailable: $e');
        _pluginAvailable = false;
      } else {
        _log.debug('Sound playback failed ($assetName): $e');
      }
    }
  }

  void _disposeAll() {
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    _cleanupTimers.clear();
    for (final player in _pool.values) {
      try {
        player.dispose();
      } on Exception catch (_) {}
    }
    _pool.clear();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
