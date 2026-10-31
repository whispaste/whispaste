/// Sound feedback service — plays audio cues for recording events.
///
/// Uses flutter_soloud for cross-platform, low-latency, multi-voice audio.
/// Supports volume control via the `soundVolume` setting (0–100 → 0.0–1.0).
/// All sounds can overlay — no silent drops on rapid-fire cues.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('SoundFeedback');

/// The cue files under `assets/sounds/`.
const soundCueAssets = [
  'start.wav',
  'stop.wav',
  'success.wav',
  'error.wav',
  'warning.wav',
];

/// The quiet cue after a successful paste. Only the generated sets have one.
const pasteCueAsset = 'paste.wav';

/// The folder under `assets/sounds/` that holds [set]'s cues, or null for the
/// original cues in `assets/sounds/` itself. Gletscher and Atem are not
/// bundled yet (their Settings choice comes later) and play Bernstein.
String? _soundSetFolder(SoundSet set) => switch (set) {
  SoundSet.classic => null,
  SoundSet.bernstein || SoundSet.gletscher || SoundSet.atem => 'bernstein',
};

/// The cue names [set] has: every [soundCueAssets] entry, plus
/// [pasteCueAsset] for the generated sets.
@visibleForTesting
List<String> soundCueNames(SoundSet set) => [
  ...soundCueAssets,
  if (_soundSetFolder(set) != null) pasteCueAsset,
];

/// The asset key of cue [name] in [set]. The duration warning has no
/// generated variant and stays the original in every set.
@visibleForTesting
String soundCueAssetKey(SoundSet set, String name) {
  final folder = _soundSetFolder(set);
  if (folder == null || name == 'warning.wav') return 'assets/sounds/$name';
  return 'assets/sounds/$folder/$name';
}

/// Loads every cue of [set] (see [soundCueNames]): [readAsset] gets the
/// asset key, [load] its bytes. A cue that fails is reported to [onFailure]
/// and left out, so one broken file never silences the others.
///
/// Cues go to SoLoud from memory (`loadMem`), not through `loadAsset`:
/// that writes each asset to a temp file in a fixed, machine-wide folder
/// (`/tmp/SoLoudLoader-Temp-Files` on Linux). When another user on the
/// machine created that folder first, every write failed and all cues
/// stayed silent (XP-2-07).
@visibleForTesting
Future<Map<String, S>> loadSoundCues<S>({
  required Future<Uint8List> Function(String key) readAsset,
  required Future<S> Function(String key, Uint8List bytes) load,
  required void Function(String name, Object error) onFailure,
  SoundSet set = SoundSet.classic,
}) async {
  final sources = <String, S>{};
  for (final name in soundCueNames(set)) {
    final key = soundCueAssetKey(set, name);
    try {
      sources[name] = await load(key, await readAsset(key));
    } catch (e) {
      onFailure(name, e);
    }
  }
  return sources;
}

Future<Uint8List> _readBundledAsset(String key) async {
  final data = await rootBundle.load(key);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SoundFeedbackService extends Notifier<void> {
  bool _initialized = false;

  /// The init in flight; concurrent callers await it instead of returning
  /// before the sources are loaded (a cue during prewarm was dropped).
  Future<void>? _initFuture;

  /// Preloaded audio sources keyed by asset name.
  final Map<String, AudioSource> _sources = {};

  /// The sound set [_sources] were loaded for; a changed setting reloads.
  SoundSet? _loadedSet;

  /// One-shot sources loaded on demand by [playOneShot], keyed by asset key.
  final Map<String, AudioSource> _oneShotSources = {};

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

  /// Runs from the moment this service opened the native audio device; read
  /// by [prewarmOneShot] so a caller can hold a one-shot until the device
  /// actually plays.
  final Stopwatch _engineAge = Stopwatch();

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

  /// The very quiet cue after a successful paste. Silent for sets without one.
  // loam-ignore: unused-public-exports – called at the paste-success site in recording_behavior.dart (whispaste-7f)
  Future<void> playPaste() async {
    if (!soundCueNames(_settings.sound.soundSet).contains(pasteCueAsset)) {
      return;
    }
    await _play(pasteCueAsset, _settings.sound.pasteSound);
  }

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
        s.sound.errorSound ||
        s.sound.pasteSound;
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

  /// Plays a bundled asset outside [soundCueAssets] once, such as the welcome
  /// sound mark, at the user's volume. The source is loaded on first use and
  /// kept until the idle release, so the cue preload stays small. Returns
  /// null when the volume is zero or playback fails; the caller decides
  /// whether the sound is wanted at all.
  Future<SoundHandle?> playOneShot(String assetKey) async {
    if (_volume <= 0) return null;
    try {
      await _ensureInit();
      final source = _oneShotSources[assetKey] ??= await _engine.loadMem(
        assetKey,
        await _readBundledAsset(assetKey),
      );
      _pruneHandles();
      final handle = _engine.play(source, volume: _volume);
      _activeHandles.add(handle);
      _armIdleTimer();
      return handle;
    } catch (e) {
      _log.warning('One-shot playback error ($assetKey): $e');
      return null;
    }
  }

  /// Boots the engine and loads [assetKey] ahead of [playOneShot], and keeps
  /// the engine from its idle release for the next [idleReleaseTimeout].
  /// Returns how long the audio device has been open, or null when the engine
  /// could not start or the asset could not load.
  Future<Duration?> prewarmOneShot(String assetKey) async {
    try {
      await _ensureInit();
      if (!_initialized) return null;
      _oneShotSources[assetKey] ??= await _engine.loadMem(
        assetKey,
        await _readBundledAsset(assetKey),
      );
      _armIdleTimer();
      return _engineAge.elapsed;
    } catch (e) {
      _log.warning('One-shot prewarm error ($assetKey): $e');
      return null;
    }
  }

  /// The volume [playOneShot] plays at, 0–1.
  double get oneShotVolume => _volume;

  /// Stops a handle returned by [playOneShot] with a short fade, so a cut
  /// never clicks.
  void stopOneShot(SoundHandle handle) {
    try {
      if (!_engine.getIsValidVoiceHandle(handle)) return;
      const fade = Duration(milliseconds: 120);
      _engine.fadeVolume(handle, 0, fade);
      _engine.scheduleStop(handle, fade);
    } catch (e) {
      _log.debug('One-shot stop failed (non-fatal): $e');
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  double get _volume => (_settings.soundVolume / 100.0).clamp(0.0, 1.0);

  SoLoud get _engine => SoLoud.instance;

  Future<void> _ensureInit() async {
    if (_initialized &&
        _sources.isNotEmpty &&
        _loadedSet == _settings.sound.soundSet) {
      return;
    }
    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;
    final init = _init();
    _initFuture = init;
    try {
      await init;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _init() async {
    try {
      if (!_engine.isInitialized) {
        await _engine.init(bufferSize: 1024, channels: Channels.mono);
        _engineAge
          ..reset()
          ..start();
        _log.info('SoLoud engine initialized');
      } else if (!_engineAge.isRunning) {
        // Opened before this service existed (hot restart): counted from
        // here, which costs at most one short wait before a one-shot.
        _engineAge.start();
      }
      await _loadCues((name, e) => _log.warning('Failed to preload $name: $e'));
      // Recovery: if all preloads failed (e.g. the engine lost its state),
      // restart the engine from scratch and retry.
      if (_sources.isEmpty) {
        _log.warning('All preloads failed — restarting engine for recovery');
        try {
          _engine.deinit();
        } catch (e) {
          _log.debug('SoLoud deinit failed during recovery (non-fatal): $e');
        }
        await _engine.init(bufferSize: 1024, channels: Channels.mono);
        _engineAge
          ..reset()
          ..start();
        await _loadCues(
          (name, e) => _log.warning('Recovery preload failed for $name: $e'),
        );
        _log.info('Recovery preload: ${_sources.length} cues');
      }
      _initialized = _sources.isNotEmpty;
      _log.info(
        'Sound assets preloaded (${_sources.length} cues, '
        '${_loadedSet?.value})',
      );
      if (_initialized) _armIdleTimer();
    } catch (e) {
      _log.warning('SoLoud init failed: $e');
    }
  }

  Future<void> _loadCues(void Function(String name, Object e) onFailure) async {
    final set = _settings.sound.soundSet;
    final sources = await loadSoundCues<AudioSource>(
      readAsset: _readBundledAsset,
      load: (key, bytes) => _engine.loadMem(key, bytes),
      onFailure: onFailure,
      set: set,
    );
    _disposeCueSources();
    _sources.addAll(sources);
    _loadedSet = set;
  }

  /// Frees the cue sources, e.g. before the cues of another set load.
  void _disposeCueSources() {
    for (final source in _sources.values) {
      try {
        _engine.disposeSource(source);
      } catch (e) {
        _log.debug('SoLoud disposeSource failed for a cue: $e');
      }
    }
    _sources.clear();
  }

  Future<void> _play(String assetName, bool enabled) async {
    if (_volume <= 0) return;
    if (!enabled) return;
    try {
      // Opening the audio device is a synchronous FFI call (~30 ms). Cues
      // fire from inside recording-state transitions, so yield first: the
      // init must not run ahead of the mic start on the hotkey's critical
      // path.
      if (!_initialized) await Future<void>.delayed(Duration.zero);
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
      _oneShotSources.clear();
      _activeHandles.clear();
    }
  }

  void _disposeOneShotSources() {
    for (final source in _oneShotSources.values) {
      try {
        _engine.disposeSource(source);
      } catch (e) {
        _log.debug('SoLoud disposeSource failed for a one-shot: $e');
      }
    }
    _oneShotSources.clear();
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
    _disposeOneShotSources();
    _initialized = false;
    _engineAge
      ..stop()
      ..reset();
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
    _disposeOneShotSources();
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
