/// Sound feedback service — plays audio cues for recording events.
///
/// Uses flutter_soloud for cross-platform, low-latency, multi-voice audio.
/// Supports volume control via the `soundVolume` setting (0–100 → 0.0–1.0).
/// All sounds can overlay — no silent drops on rapid-fire cues.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// How long the engine stays initialized after the last cue before its
  /// native audio device gets released (issue #148: SoLoud's miniaudio
  /// backend calls `ma_device_start()` once at init and never stops the
  /// device again until `deinit()` -- on a Bluetooth multipoint headset,
  /// that keeps the Mac's audio route claimed and blocks the phone's own
  /// audio on the same headset for as long as the device stays open, which
  /// used to mean "until WhisPaste exits". 30s is generous (every cue is
  /// well under 1s) so back-to-back cues during a recording session never
  /// thrash init/deinit. Mutable only so tests can shrink it.
  @visibleForTesting
  Duration idleReleaseTimeout = const Duration(seconds: 30);

  Timer? _idleTimer;

  @override
  void build() {
    // Lazy init — engine starts on first sound request.
    ref.onDispose(_dispose);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> playRecordStart() =>
      _play('start.wav', _settings.recordStartSound);

  Future<void> playRecordStop() => _play('stop.wav', _settings.recordStopSound);

  Future<void> playTranscriptionComplete() =>
      _play('success.wav', _settings.transcriptionCompleteSound);

  Future<void> playDurationWarning() =>
      _play('warning.wav', _settings.durationWarningSound);

  Future<void> playError() => _play('error.wav', _settings.sound.errorSound);

  /// Boots the audio engine and preloads the cues ahead of the first cue.
  ///
  /// Without this the entire native SoLoud init lands on the first [_play]
  /// call — which is the record-start cue, i.e. squarely inside the
  /// hotkey→overlay path. A captured cold start paid 1005 ms of UI-thread
  /// jank and a 1226 ms hotkey→overlay there (budget: 33 ms), once per
  /// session, right when the user first reaches for the app.
  ///
  /// Skipped entirely when the user has muted or disabled every cue, so this
  /// never starts a native audio engine nobody asked for.
  Future<void> prewarm() async {
    final s = _settings;
    if (s.soundVolume <= 0) return;
    final anyCueEnabled =
        s.recordStartSound ||
        s.recordStopSound ||
        s.transcriptionCompleteSound ||
        s.durationWarningSound ||
        s.sound.errorSound;
    if (!anyCueEnabled) return;
    await _ensureInit();
  }

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
        } catch (e) {
          _log.debug('SoLoud deinit failed during recovery (non-fatal): $e');
        }
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
      if (_initialized) _armIdleTimer();
    } catch (e) {
      _log.warning('SoLoud init failed: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (_volume <= 0) return;
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
      _armIdleTimer();
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
        } catch (e) {
          _log.debug('SoLoud stop handle failed during prune (non-fatal): $e');
        }
      }
    } catch (e) {
      _log.debug('Handle prune error: $e');
      _activeHandles.clear();
    }
  }

  /// (Re-)starts the idle-release countdown. Called after every successful
  /// engine init and every play call so an active session never gets its
  /// audio route torn down mid-use.
  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleReleaseTimeout, _onIdleTimeout);
  }

  /// Test-only entry point for [_armIdleTimer] -- the real call sites
  /// ([_ensureInit], [_play]) are unreachable in `flutter test` because they
  /// require the native engine to have actually initialized first.
  @visibleForTesting
  void armIdleTimerForTesting() => _armIdleTimer();

  void _onIdleTimeout() {
    if (_engineVoiceCountSafe() > 0) {
      // Still audibly playing (e.g. a longer custom cue) -- postpone.
      _armIdleTimer();
      return;
    }
    releaseEngineForIdle();
  }

  int _engineVoiceCountSafe() {
    try {
      return _engine.getVoiceCount();
    } catch (e) {
      return 0;
    }
  }

  /// Releases the native audio engine after [idleReleaseTimeout] of
  /// inactivity -- unlike [_dispose]'s "keep the engine alive forever"
  /// (written for the rapid create/destroy cycle of a provider rebuild,
  /// where an immediate reinit right after deinit risked corrupting
  /// SoLoud's temp dir), this fires long after any such rebuild has
  /// settled. A clean deinit() followed by a much-later init() is exactly
  /// what SoLoud's own init() relies on for hot-restart recovery (it calls
  /// deinit() then re-initializes synchronously when it detects the native
  /// player is still up), so this idle path does not carry that risk.
  ///
  /// `@visibleForTesting` (and non-underscore) so a test subclass can
  /// override it to verify the idle-timer scheduling in [_armIdleTimer]/
  /// [_onIdleTimeout] without touching the real native engine, which is
  /// unavailable under `flutter test` (see this file's test doc comment).
  @visibleForTesting
  void releaseEngineForIdle() {
    for (final handle in _activeHandles) {
      try {
        _engine.stop(handle);
      } catch (e) {
        _log.debug('SoLoud stop handle failed during idle release: $e');
      }
    }
    _activeHandles.clear();
    for (final source in _sources.values) {
      try {
        _engine.disposeSource(source);
      } catch (e) {
        _log.debug('SoLoud disposeSource failed during idle release: $e');
      }
    }
    _sources.clear();
    _initialized = false;
    try {
      _engine.deinit();
    } catch (e) {
      _log.debug('SoLoud deinit failed during idle release (non-fatal): $e');
    }
    _log.info(
      'SoLoud engine released after ${idleReleaseTimeout.inSeconds}s idle '
      '(frees any exclusively-claimed Bluetooth audio route, issue #148)',
    );
  }

  void _dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    // Stop tracked handles and dispose loaded sources.
    for (final handle in _activeHandles) {
      try {
        _engine.stop(handle);
      } catch (e) {
        _log.debug('SoLoud stop handle failed during dispose (non-fatal): $e');
      }
    }
    _activeHandles.clear();
    for (final source in _sources.values) {
      try {
        _engine.disposeSource(source);
      } catch (e) {
        _log.debug(
          'SoLoud disposeSource failed during dispose (non-fatal): $e',
        );
      }
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

final soundFeedbackProvider = NotifierProvider<SoundFeedbackService, void>(
  SoundFeedbackService.new,
);
