/// Sound feedback service — plays audio cues for recording events.
///
/// Uses flutter_soloud for cross-platform, low-latency, multi-voice audio.
/// Supports volume control via the `soundVolume` setting (0–100 → 0.0–1.0).
/// All sounds can overlay — no silent drops on rapid-fire cues.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('SoundFeedback');

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SoundFeedbackService extends Notifier<void> {
  bool _initialized = false;
  bool _initializing = false;

  /// Preloaded audio sources keyed by asset name.
  final Map<String, AudioSource> _sources = {};

  @override
  void build() {
    // Lazy init — engine starts on first sound request.
    ref.onDispose(_dispose);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> playRecordStart() =>
      _play('start.wav', _settings.recordStartSound);

  Future<void> playRecordStop() =>
      _play('stop.wav', _settings.recordStopSound);

  Future<void> playTranscriptionComplete() =>
      _play('success.wav', _settings.transcriptionCompleteSound);

  Future<void> playDurationWarning() =>
      _play('warning.wav', _settings.durationWarningSound);

  Future<void> playError() => _play('error.wav', true);

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  double get _volume => (_settings.soundVolume / 100.0).clamp(0.0, 1.0);

  SoLoud get _engine => SoLoud.instance;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    if (_initializing) return; // prevent re-entrant init
    _initializing = true;
    try {
      if (!_engine.isInitialized) {
        await _engine.init(bufferSize: 1024, channels: Channels.mono);
        _log.info('SoLoud engine initialized');
      }
      // Preload all sound assets
      const assets = [
        'start.wav',
        'stop.wav',
        'success.wav',
        'error.wav',
        'warning.wav',
      ];
      for (final name in assets) {
        try {
          _sources[name] = await _engine.loadAsset('assets/sounds/$name');
        } catch (e) {
          _log.warning('Failed to preload $name: $e');
        }
      }
      _initialized = true;
      _log.info('Sound assets preloaded (${_sources.length}/5)');
    } catch (e) {
      _log.warning('SoLoud init failed: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (!enabled) return;
    try {
      await _ensureInit();
      final source = _sources[assetName];
      if (source == null) {
        _log.warning('No preloaded source for $assetName');
        return;
      }
      _engine.play(source, volume: _volume);
      _log.debug('Playing $assetName (vol=${_volume.toStringAsFixed(2)})');
    } catch (e) {
      _log.warning('Sound playback error ($assetName): $e');
    }
  }

  void _dispose() {
    if (_initialized && _engine.isInitialized) {
      for (final source in _sources.values) {
        try {
          _engine.disposeSource(source);
        } catch (_) {}
      }
      _sources.clear();
      try {
        _engine.deinit();
      } catch (_) {}
      _initialized = false;
      _log.info('SoLoud engine disposed');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
