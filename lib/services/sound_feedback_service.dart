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

  /// Track active sound handles to prevent voice pool accumulation.
  final List<SoundHandle> _activeHandles = [];
  static const _maxTrackedHandles = 16;

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

  /// Play a preview of the start sound at the given [volume] (0–100).
  /// Used by the settings UI to preview volume changes.
  Future<void> playVolumePreview(double volume) async {
    try {
      await _ensureInit();
      final source = _sources['start.wav'];
      if (source == null) return;
      _engine.play(source, volume: (volume / 100.0).clamp(0.0, 1.0));
    } catch (e) {
      _log.warning('Volume preview error: $e');
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  double get _volume => (_settings.soundVolume / 100.0).clamp(0.0, 1.0);

  SoLoud get _engine => SoLoud.instance;

  Future<void> _ensureInit() async {
    if (_initialized && _sources.isNotEmpty) return;
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
      _sources.clear();
      for (final name in assets) {
        try {
          _sources[name] = await _engine.loadAsset('assets/sounds/$name');
        } catch (e) {
          _log.warning('Failed to preload $name: $e');
        }
      }
      // Recovery: if all preloads failed (e.g. temp dir invalidated),
      // restart the engine from scratch and retry.
      if (_sources.isEmpty) {
        _log.warning('All preloads failed — restarting engine for recovery');
        try {
          _engine.deinit();
        } catch (_) {}
        await _engine.init(bufferSize: 1024, channels: Channels.mono);
        for (final name in assets) {
          try {
            _sources[name] = await _engine.loadAsset('assets/sounds/$name');
          } catch (e) {
            _log.warning('Recovery preload failed for $name: $e');
          }
        }
        _log.info('Recovery preload: ${_sources.length}/5');
      }
      _initialized = _sources.isNotEmpty;
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
      // Prune finished handles to prevent accumulation.
      _pruneHandles();
      final handle = _engine.play(source, volume: _volume);
      _activeHandles.add(handle);
      _log.debug('Playing $assetName (vol=${_volume.toStringAsFixed(2)})');
    } catch (e) {
      _log.warning('Sound playback error ($assetName): $e');
      // Invalidate cached state so the next call forces a full re-init.
      _initialized = false;
      _sources.clear();
      _activeHandles.clear();
    }
  }

  /// Remove completed sound handles; stop oldest if pool is full.
  void _pruneHandles() {
    try {
      _activeHandles.removeWhere((h) {
        try {
          return !_engine.getIsValidVoiceHandle(h);
        } catch (_) {
          return true;
        }
      });
      // If still over limit, stop the oldest handles.
      while (_activeHandles.length >= _maxTrackedHandles) {
        try {
          _engine.stop(_activeHandles.removeAt(0));
        } catch (_) {}
      }
    } catch (e) {
      _log.debug('Handle prune error: $e');
      _activeHandles.clear();
    }
  }

  void _dispose() {
    // Stop tracked handles and dispose loaded sources.
    for (final handle in _activeHandles) {
      try {
        _engine.stop(handle);
      } catch (_) {}
    }
    _activeHandles.clear();
    for (final source in _sources.values) {
      try {
        _engine.disposeSource(source);
      } catch (_) {}
    }
    _sources.clear();
    _initialized = false;
    // Do NOT deinit the singleton SoLoud engine — it persists across
    // provider rebuilds. Calling deinit() here and init() in a new
    // instance can corrupt the temp-dir, causing preload failures.
    _log.info('SoLoud sources disposed (engine kept alive)');
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final soundFeedbackProvider =
    NotifierProvider<SoundFeedbackService, void>(SoundFeedbackService.new);
