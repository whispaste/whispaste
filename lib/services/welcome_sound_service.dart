/// Welcome sounds — the short music bed ("Bernstein-Auftakt") on the first
/// onboarding screen and the sound logo the first time the main window shows;
/// only one of them per moment (maintainer 2026-10-30: logo and intro
/// together on screen 1 was one sound too many) (`internal-notes
/// intro-av/spec.md`, "Sound sets + referral": the Bernstein logo is the
/// default mark).
///
/// Rules (maintainer 2026-10-31):
///  - the intro plays every time the onboarding opens on its first screen
///    (first run, a review from the start, a new run after a redesign); the
///    welcome screen keeps it to once per app run, so going back to page 1
///    stays quiet. Nothing is stored for it;
///  - the logo plays once per install, the first time the main window shows
///    with the onboarding done (right after the onboarding, or a user who
///    already had it starting this version); the marker lives in
///    SharedPreferences and survives restarts;
///  - both respect the sound settings: volume zero or every cue switched off
///    means no sound (a muted logo moment counts as used, so it never
///    surprises the user later);
///  - neither plays while a dictation runs or the onboarding microphone test
///    is open, and a sound that is still playing stops (short fade) as soon
///    as either starts. A blocked logo call does not use up the moment;
///  - one sound at a time: starting one fades out another that still sounds,
///    so the logo after a quick onboarding cuts the intro short;
///  - SoLoud releases its device after 30 s idle (#148), and a one-shot
///    started right after a fresh init loses its first moments on macOS. So
///    the welcome screen prewarms the intro when it opens
///    ([WelcomeSoundService.prewarmIntro]), and a play waits until the device
///    has run for [kWelcomeSoundDeviceSettle];
///  - every call logs one info line with its outcome, so "I heard nothing"
///    reports can be read from the log.
///
/// UI-free: the welcome screen calls [WelcomeSoundService.playIntro], the
/// app shell [WelcomeSoundService.playLogoOnce]; the microphone test reports
/// itself through [micTestActiveProvider].
library;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart' show SoundHandle;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart';
import 'sound_feedback_service.dart';

final _log = AppLogger('WelcomeSound');

/// The bundled sound mark (Bernstein set, quiet-breath variant).
const String kWelcomeSoundAsset = 'assets/sounds/bernstein/logo.wav';

/// The onboarding music bed, about 4 s (maintainer choice
/// "Bernstein-Auftakt", 2026-10-30).
const String kIntroSoundAsset = 'assets/sounds/bernstein/intro.wav';

/// How long the audio device must have run before a one-shot starts, so
/// its first moments are not lost to the device start-up.
@visibleForTesting
const Duration kWelcomeSoundDeviceSettle = Duration(milliseconds: 300);

/// SharedPreferences key that marks the logo as used. The name predates the
/// logo's move from the onboarding to the main window.
@visibleForTesting
const String kLogoSoundPlayedKey = 'welcome_sound_played_firstLaunch';

/// What one welcome sound call did.
enum WelcomeSoundOutcome {
  /// The mark started.
  played,

  /// The logo already had its moment.
  alreadyPlayed,

  /// Sounds are muted or every cue is off; a logo moment is marked as used.
  soundsOff,

  /// A dictation or the microphone test is active; nothing is marked.
  busy,

  /// Playback failed; nothing is marked, a later call may try again.
  failed,
}

/// Plays and stops the mark; [SoundFeedbackService] in the app, a fake in
/// tests.
abstract interface class WelcomeSoundPlayer {
  /// Starts the engine and loads [assetKey]; returns how long the audio
  /// device has been open, or null when it could not start.
  Future<Duration?> prewarm(String assetKey);
  Future<Object?> play(String assetKey);
  void stop(Object handle);

  /// The volume a play uses, 0–1, for the log line.
  double get volume;
}

final class _SoLoudWelcomePlayer implements WelcomeSoundPlayer {
  _SoLoudWelcomePlayer(this._sounds);

  final SoundFeedbackService _sounds;

  @override
  Future<Duration?> prewarm(String assetKey) =>
      _sounds.prewarmOneShot(assetKey);

  @override
  Future<Object?> play(String assetKey) => _sounds.playOneShot(assetKey);

  @override
  double get volume => _sounds.oneShotVolume;

  @override
  void stop(Object handle) => _sounds.stopOneShot(handle as SoundHandle);
}

/// Whether the user allows sounds at all: a volume above zero and at least
/// one cue switched on. Same reading as [SoundFeedbackService.prewarm].
bool welcomeSoundAllowed(AppSettings s) {
  if (s.sound.soundVolume <= 0) return false;
  final sound = s.sound;
  return sound.recordStartSound ||
      sound.recordStopSound ||
      sound.transcriptionCompleteSound ||
      sound.durationWarningSound ||
      sound.errorSound ||
      sound.pasteSound;
}

final class WelcomeSoundService {
  WelcomeSoundService({
    required this.prefs,
    required this.player,
    required this.soundsAllowed,
    required this.isBusy,
    this.ignorePlayedMarker = false,
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  final Future<SharedPreferences> Function() prefs;
  final WelcomeSoundPlayer player;
  final bool Function() soundsAllowed;

  /// A dictation runs or the microphone test is open.
  final bool Function() isBusy;

  /// Debug builds replay a used logo once per run, so it can be listened to
  /// again; the skip is logged.
  final bool ignorePlayedMarker;

  final Future<void> Function(Duration) _wait;

  Object? _handle;
  final Set<String> _inFlight = {};

  /// The logo's moment is settled for this run (played, used before, or
  /// muted), so the many later window focuses neither read prefs nor log.
  bool _logoSettled = false;

  /// The intro's prewarm, started when the welcome screen opens.
  Future<Duration?>? _introWarm;
  final Stopwatch _sinceWelcome = Stopwatch();

  /// Plays the sound logo if this install has not had it yet. Called each
  /// time the main window shows with the onboarding done.
  Future<WelcomeSoundOutcome> playLogoOnce() async {
    if (_logoSettled) return WelcomeSoundOutcome.alreadyPlayed;
    final outcome = await _play(
      kWelcomeSoundAsset,
      onceKey: kLogoSoundPlayedKey,
    );
    if (outcome != WelcomeSoundOutcome.busy &&
        outcome != WelcomeSoundOutcome.failed) {
      _logoSettled = true;
    }
    return outcome;
  }

  /// Plays the onboarding music bed. The welcome screen calls it once per
  /// visit from the start; no marker is kept.
  Future<WelcomeSoundOutcome> playIntro() async {
    final warm = _introWarm;
    _introWarm = null;
    return _play(kIntroSoundAsset, warm: warm);
  }

  /// Starts the engine and loads the intro when the welcome screen opens, so
  /// [playIntro] finds a running device. Does nothing when sounds are off;
  /// never throws.
  Future<void> prewarmIntro() async {
    _sinceWelcome
      ..reset()
      ..start();
    try {
      if (!soundsAllowed()) return;
      _introWarm ??= player.prewarm(kIntroSoundAsset);
      await _introWarm;
    } catch (e) {
      _log.debug('intro prewarm skipped: $e');
    }
  }

  Future<WelcomeSoundOutcome> _play(
    String asset, {
    String? onceKey,
    Future<Duration?>? warm,
  }) async {
    final fresh = <bool>[];
    var delay = Duration.zero;
    WelcomeSoundOutcome done(WelcomeSoundOutcome outcome, [String? reason]) {
      _log.info(
        'welcome sound ${outcome.name}'
        '${reason == null ? '' : ' ($reason)'}: $asset, '
        'volume ${_volumeLabel()}, '
        'fresh engine ${fresh.isEmpty ? '-' : fresh.first}, '
        'delay ${delay.inMilliseconds} ms, '
        'since welcome ${_sinceWelcomeLabel()}',
      );
      return outcome;
    }

    final key = onceKey ?? asset;
    if (!_inFlight.add(key)) {
      return done(WelcomeSoundOutcome.alreadyPlayed, 'call in flight');
    }
    try {
      final store = onceKey == null ? null : await prefs();
      if (store != null && (store.getBool(key) ?? false)) {
        if (!ignorePlayedMarker) {
          return done(WelcomeSoundOutcome.alreadyPlayed, 'marker set');
        }
        _log.info('welcome sound: debug build ignores the marker $key');
      }
      if (isBusy()) return done(WelcomeSoundOutcome.busy, 'before start');
      if (!soundsAllowed()) {
        await store?.setBool(key, true);
        return done(WelcomeSoundOutcome.soundsOff);
      }
      // Joins the welcome screen's prewarm, then reads the device as it is
      // now: an idle release since then means a fresh init. The prewarm
      // keeps the engine from its idle release well beyond the short wait
      // below, so the device found here still runs at the play.
      if (warm != null) await warm;
      final age = await player.prewarm(asset);
      if (age == null) return done(WelcomeSoundOutcome.failed, 'no engine');
      fresh.add(age < kWelcomeSoundDeviceSettle);
      if (fresh.first) {
        delay = kWelcomeSoundDeviceSettle - age;
        await _wait(delay);
      }
      if (isBusy()) return done(WelcomeSoundOutcome.busy, 'after warm-up');
      final handle = await player.play(asset);
      if (handle == null) return done(WelcomeSoundOutcome.failed, 'no voice');
      // A dictation or the mic test may have started while the asset loaded.
      if (isBusy()) {
        player.stop(handle);
        return done(WelcomeSoundOutcome.busy, 'after start');
      }
      stop();
      _handle = handle;
      await store?.setBool(key, true);
      return done(WelcomeSoundOutcome.played);
    } catch (e) {
      return done(WelcomeSoundOutcome.failed, '$e');
    } finally {
      _inFlight.remove(key);
    }
  }

  String _volumeLabel() {
    try {
      return player.volume.toStringAsFixed(2);
    } catch (_) {
      return '-';
    }
  }

  String _sinceWelcomeLabel() =>
      _sinceWelcome.isRunning ? '${_sinceWelcome.elapsedMilliseconds} ms' : '-';

  /// Stops a mark or intro that is still sounding.
  void stop() {
    final handle = _handle;
    _handle = null;
    if (handle != null) player.stop(handle);
  }
}

/// Set by the onboarding microphone test while it listens. The welcome mark
/// never plays then and stops if it is still sounding.
final micTestActiveProvider = NotifierProvider<MicTestActive, bool>(
  MicTestActive.new,
);

class MicTestActive extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool active) => state = active;
}

// loam-ignore: unused-public-exports – called by the onboarding welcome step and the first-start path (feat/onboarding-v6, whispaste-7f)
final welcomeSoundProvider = Provider<WelcomeSoundService>((ref) {
  final service = WelcomeSoundService(
    prefs: SharedPreferences.getInstance,
    player: _SoLoudWelcomePlayer(ref.read(soundFeedbackProvider.notifier)),
    soundsAllowed: () => welcomeSoundAllowed(
      ref.read(settingsProvider).value ?? AppSettings.defaults,
    ),
    isBusy: () =>
        ref.read(micTestActiveProvider) ||
        isDictationBusy(ref.read(recordingPhaseProvider)),
    ignorePlayedMarker: kDebugMode,
  );
  ref.listen<bool>(micTestActiveProvider, (_, active) {
    if (active) service.stop();
  });
  ref.listen<RecordingPhase>(recordingPhaseProvider, (_, phase) {
    if (isDictationBusy(phase)) service.stop();
  });
  ref.onDispose(service.stop);
  return service;
});
