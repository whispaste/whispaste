import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/media_pause/media_pause_backends.dart';
import 'package:whispaste/services/media_pause/media_pause_controller.dart';

class _FakeBackend implements MediaPauseBackend {
  _FakeBackend(this.outcome);

  MediaPauseOutcome outcome;
  Completer<void>? gate;
  int pauses = 0;
  int resumes = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<MediaPauseOutcome> pauseIfPlaying() async {
    pauses++;
    await gate?.future;
    return outcome;
  }

  @override
  Future<void> resumePaused() async => resumes++;
}

class _FakeBus implements MprisBus {
  _FakeBus(this.status);

  final Map<String, String> status;
  final calls = <String>[];

  @override
  Future<bool> isReachable() async => true;

  @override
  Future<List<String>> listPlayers() async => status.keys.toList();

  @override
  Future<String?> playbackStatus(String player) async => status[player];

  @override
  Future<void> pause(String player) async {
    calls.add('pause:$player');
    status[player] = 'Paused';
  }

  @override
  Future<void> play(String player) async {
    calls.add('play:$player');
    status[player] = 'Playing';
  }
}

void main() {
  group('MediaPauseController', () {
    test('resumes what it paused itself', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(backend: backend, isEnabled: () => true);
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.pauses, 1);
      expect(backend.resumes, 1);
    });

    test('leaves already paused playback paused', () async {
      final backend = _FakeBackend(MediaPauseOutcome.nothingPlaying);
      final c = MediaPauseController(backend: backend, isEnabled: () => true);
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.resumes, 0);
    });

    test('does nothing while the setting is off', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(backend: backend, isEnabled: () => false);
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.pauses, 0);
      expect(backend.resumes, 0);
    });

    test('does nothing when the system is unavailable', () async {
      final backend = _FakeBackend(MediaPauseOutcome.unavailable);
      final c = MediaPauseController(backend: backend, isEnabled: () => true);
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.resumes, 0);
    });

    test('stop during an in-flight pause resumes after it finished', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused)
        ..gate = Completer<void>();
      final c = MediaPauseController(backend: backend, isEnabled: () => true);
      c.recordingStarted();
      final ended = c.recordingEnded();
      await Future<void>.delayed(Duration.zero);
      expect(backend.resumes, 0);
      backend.gate!.complete();
      await ended;
      expect(backend.resumes, 1);
    });

    test('still resumes when the setting is switched off meanwhile', () async {
      var enabled = true;
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(
        backend: backend,
        isEnabled: () => enabled,
      );
      c.recordingStarted();
      await Future<void>.delayed(Duration.zero);
      enabled = false;
      await c.recordingEnded();
      expect(backend.resumes, 1);
    });

    test('a second end does not resume twice', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(backend: backend, isEnabled: () => true);
      c.recordingStarted();
      await c.recordingEnded();
      await c.recordingEnded();
      expect(backend.resumes, 1);
    });
  });

  group('MprisMediaPauseBackend', () {
    test('pauses only playing players and resumes exactly those', () async {
      final bus = _FakeBus({'a': 'Playing', 'b': 'Paused'});
      final backend = MprisMediaPauseBackend(bus);
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.paused);
      await backend.resumePaused();
      expect(bus.calls, ['pause:a', 'play:a']);
    });

    test('reports nothing playing and resumes nothing', () async {
      final bus = _FakeBus({'a': 'Paused'});
      final backend = MprisMediaPauseBackend(bus);
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.nothingPlaying);
      await backend.resumePaused();
      expect(bus.calls, isEmpty);
    });

    test('does not restart a player the user paused meanwhile', () async {
      final bus = _FakeBus({'a': 'Playing'});
      final backend = MprisMediaPauseBackend(bus);
      await backend.pauseIfPlaying();
      bus.status['a'] = 'Stopped';
      await backend.resumePaused();
      expect(bus.calls, ['pause:a']);
    });
  });

  group('ChannelMediaPauseBackend contract', () {
    const channel = MethodChannel(mediaPauseChannelName);
    TestWidgetsFlutterBinding.ensureInitialized();

    void mock(Future<Object?> Function(MethodCall) h) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, h);

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('uses the agreed method names and maps results', () async {
      final seen = <String>[];
      var answer = 'paused';
      mock((call) async {
        seen.add(call.method);
        return switch (call.method) {
          'isAvailable' => true,
          'pauseIfPlaying' => answer,
          _ => null,
        };
      });
      final backend = ChannelMediaPauseBackend(channel);
      expect(await backend.isAvailable(), isTrue);
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.paused);
      answer = 'nothing';
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.nothingPlaying);
      answer = 'unavailable';
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.unavailable);
      await backend.resumePaused();
      expect(seen, [
        'isAvailable',
        'pauseIfPlaying',
        'pauseIfPlaying',
        'pauseIfPlaying',
        'resumePaused',
      ]);
    });

    test('missing host or host error means unavailable', () async {
      final backend = ChannelMediaPauseBackend(channel);
      expect(await backend.isAvailable(), isFalse);
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.unavailable);
      mock((_) async => throw PlatformException(code: 'x'));
      expect(await backend.isAvailable(), isFalse);
      expect(await backend.pauseIfPlaying(), MediaPauseOutcome.unavailable);
      await backend.resumePaused();
    });
  });
}
