/// Unit tests for [WelcomeSoundService]: the logo once per install, the intro
/// on every call, the sound settings, the busy block (dictation, microphone
/// test) and stopping a sound that is still playing, the intro's prewarm and
/// device settle, and the debug replay. The player is a fake; SoLoud is not available
/// in `flutter test`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/welcome_sound_service.dart';

final class _FakePlayer implements WelcomeSoundPlayer {
  final List<String> played = [];
  final List<Object> stopped = [];

  /// Prewarms, waits and plays in call order.
  final List<String> calls = [];
  bool fail = false;
  void Function()? onPlay;

  /// How long the device has been open; null means the engine cannot start.
  Duration? engineAge = const Duration(seconds: 5);

  @override
  double get volume => 0.8;

  @override
  Future<Duration?> prewarm(String assetKey) async {
    calls.add('prewarm $assetKey');
    return engineAge;
  }

  @override
  Future<Object?> play(String assetKey) async {
    calls.add('play $assetKey');
    onPlay?.call();
    if (fail) return null;
    played.add(assetKey);
    return played.length;
  }

  @override
  void stop(Object handle) => stopped.add(handle);
}

void main() {
  late _FakePlayer player;
  late bool allowed;
  late bool busy;
  late WelcomeSoundService service;
  late List<Duration> waits;

  WelcomeSoundService build({bool ignorePlayedMarker = false}) =>
      WelcomeSoundService(
        prefs: SharedPreferences.getInstance,
        player: player,
        soundsAllowed: () => allowed,
        isBusy: () => busy,
        ignorePlayedMarker: ignorePlayedMarker,
        wait: (d) async {
          waits.add(d);
          player.calls.add('wait ${d.inMilliseconds}');
        },
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    player = _FakePlayer();
    allowed = true;
    busy = false;
    waits = [];
    service = build();
  });

  group('logo', () {
    test('plays once per install', () async {
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.played);
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.alreadyPlayed);
      expect(player.played, [kWelcomeSoundAsset]);
    });

    test('the marker survives a restart', () async {
      await service.playLogoOnce();
      service = build();
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.alreadyPlayed);
      expect(player.played, hasLength(1));
    });

    test('later calls in the same run neither read prefs nor play', () async {
      await service.playLogoOnce();
      await SharedPreferences.getInstance().then((p) => p.clear());
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.alreadyPlayed);
      expect(player.played, hasLength(1));
    });

    test('sounds off: nothing plays and the moment is used up', () async {
      allowed = false;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.soundsOff);
      allowed = true;
      service = build();
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.alreadyPlayed);
      expect(player.played, isEmpty);
    });

    test('busy: nothing plays and a later call still may', () async {
      busy = true;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.busy);
      busy = false;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.played);
    });

    test('busy while the asset loads: the started logo is stopped', () async {
      player.onPlay = () => busy = true;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.busy);
      expect(player.stopped, [1]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kLogoSoundPlayedKey), isNull);
    });

    test('a failed playback is not marked', () async {
      player.fail = true;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.failed);
      player.fail = false;
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.played);
    });

    test('concurrent calls play once', () async {
      await Future.wait([service.playLogoOnce(), service.playLogoOnce()]);
      expect(player.played, hasLength(1));
    });

    test('a debug build replays a used logo once per run', () async {
      await service.playLogoOnce();
      service = build(ignorePlayedMarker: true);
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.played);
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.alreadyPlayed);
      expect(player.played, hasLength(2));
    });
  });

  test('stop ends a sounding sound once', () async {
    await service.playLogoOnce();
    service
      ..stop()
      ..stop();
    expect(player.stopped, [1]);
  });

  group('intro', () {
    test('plays on every call, nothing is stored', () async {
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
      service = build();
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
      expect(player.played, List.filled(3, kIntroSoundAsset));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('the intro does not use up the logo', () async {
      await service.playIntro();
      expect(await service.playLogoOnce(), WelcomeSoundOutcome.played);
    });

    test('one sound at a time: the logo fades out the intro', () async {
      await service.playIntro();
      await service.playLogoOnce();
      expect(player.stopped, [1]);
      service.stop();
      expect(player.stopped, [1, 2]);
    });

    test('sounds off: no intro, and a later call plays again', () async {
      allowed = false;
      expect(await service.playIntro(), WelcomeSoundOutcome.soundsOff);
      allowed = true;
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
    });

    test('busy (mic test or dictation): no intro, a later call may', () async {
      busy = true;
      expect(await service.playIntro(), WelcomeSoundOutcome.busy);
      busy = false;
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
    });

    test('the welcome screen prewarms before the intro plays', () async {
      await service.prewarmIntro();
      expect(player.calls, ['prewarm $kIntroSoundAsset']);
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
      expect(player.calls.last, 'play $kIntroSoundAsset');
      expect(waits, isEmpty, reason: 'a warm device needs no settle');
    });

    test('a freshly opened device settles before the intro starts', () async {
      player.engineAge = const Duration(milliseconds: 40);
      expect(await service.playIntro(), WelcomeSoundOutcome.played);
      expect(player.calls, [
        'prewarm $kIntroSoundAsset',
        'wait ${(kWelcomeSoundDeviceSettle - const Duration(milliseconds: 40)).inMilliseconds}',
        'play $kIntroSoundAsset',
      ]);
    });

    test('a dictation during the settle stops the intro', () async {
      player.engineAge = Duration.zero;
      service = WelcomeSoundService(
        prefs: SharedPreferences.getInstance,
        player: player,
        soundsAllowed: () => allowed,
        isBusy: () => busy,
        wait: (_) async => busy = true,
      );
      expect(await service.playIntro(), WelcomeSoundOutcome.busy);
      expect(player.played, isEmpty);
    });

    test('no engine: failed', () async {
      player.engineAge = null;
      await service.prewarmIntro();
      expect(await service.playIntro(), WelcomeSoundOutcome.failed);
      expect(player.played, isEmpty);
    });

    test('no prewarm while sounds are off', () async {
      allowed = false;
      await service.prewarmIntro();
      expect(player.calls, isEmpty);
    });

    test('each visit prewarms again after an intro played', () async {
      await service.prewarmIntro();
      await service.playIntro();
      player.calls.clear();
      await service.prewarmIntro();
      expect(player.calls, ['prewarm $kIntroSoundAsset']);
    });
  });

  group('welcomeSoundAllowed', () {
    test('defaults allow the mark', () {
      expect(welcomeSoundAllowed(AppSettings.defaults), isTrue);
    });

    test('volume zero blocks it', () {
      final s = AppSettings.defaults.copyWithSections(
        sound: const SoundSettings(soundVolume: 0),
      );
      expect(welcomeSoundAllowed(s), isFalse);
    });

    test('every cue off blocks it', () {
      final s = AppSettings.defaults.copyWithSections(
        sound: const SoundSettings(
          recordStartSound: false,
          recordStopSound: false,
          transcriptionCompleteSound: false,
          durationWarningSound: false,
          errorSound: false,
          pasteSound: false,
        ),
      );
      expect(welcomeSoundAllowed(s), isFalse);
    });
  });

  test('micTestActiveProvider defaults to false and can be set', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(micTestActiveProvider), isFalse);
    container.read(micTestActiveProvider.notifier).set(true);
    expect(container.read(micTestActiveProvider), isTrue);
  });

  for (final asset in [kWelcomeSoundAsset, kIntroSoundAsset]) {
    test('$asset is a clean 48 kHz stereo 16-bit WAV', () {
      final bytes = File(asset).readAsBytesSync();
      final header = ByteData.sublistView(bytes, 0, 44);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(header.getUint16(22, Endian.little), 2, reason: 'channels');
      expect(header.getUint32(24, Endian.little), 48000, reason: 'sample rate');
      expect(header.getUint16(34, Endian.little), 16, reason: 'bits');
      final samples = Int16List.sublistView(bytes, 44);
      // Faded in and out: no click at either edge.
      expect(samples.first.abs(), lessThan(8));
      expect(samples.last.abs(), lessThan(8));
    });
  }
}
