import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
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

class _FakeDuck implements MediaDuckBackend {
  _FakeDuck(this.volumes);

  /// Current volume per id; only ids in [playing] count as audible.
  final Map<String, double> volumes;
  Set<String> playing = {};
  bool failSet = false;
  int lists = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<DuckTarget>> playingTargets() async {
    lists++;
    return [
      for (final id in playing) DuckTarget(id, [volumes[id]!]),
    ];
  }

  @override
  Future<void> setLevels(List<DuckTarget> targets) async {
    if (failSet) throw StateError('host gone');
    for (final t in targets) {
      if (volumes.containsKey(t.id)) volumes[t.id] = t.levels.single;
    }
  }
}

const _sinkInputs = '''
Sink Input #41
\tDriver: PipeWire
\tCorked: no
\tMute: no
\tVolume: front-left: 52429 /  80% / -5.81 dB,   front-right: 45875 /  70% / -9.29 dB
\t        balance -0.12
\tProperties:
\t\tapplication.name = "Firefox"
\t\tapplication.process.id = "1200"
Sink Input #42
\tCorked: yes
\tVolume: mono: 65536 / 100% / 0.00 dB
\tProperties:
\t\tapplication.process.id = "1300"
Sink Input #43
\tCorked: no
\tVolume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB
\tProperties:
\t\tapplication.process.id = "999"
''';

void main() {
  group('MediaWhileRecording setting', () {
    test('an existing pause switch stays pause', () {
      expect(
        readMediaWhileRecording({'pause_media_while_recording': 'true'}),
        MediaWhileRecording.pause,
      );
      expect(
        readMediaWhileRecording({'pause_media_while_recording': 'false'}),
        MediaWhileRecording.off,
      );
      expect(readMediaWhileRecording({}), MediaWhileRecording.off);
    });

    test('the new key wins and round-trips', () {
      for (final mode in MediaWhileRecording.values) {
        final map = const AudioInputSettings()
            .copyWith(mediaWhileRecording: mode)
            .toMap();
        expect(AudioInputSettings.fromMap(map).mediaWhileRecording, mode);
        expect(
          map['pause_media_while_recording'],
          '${mode == MediaWhileRecording.pause}',
        );
      }
    });
  });

  group('MediaPauseController', () {
    test('resumes what it paused itself', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.pauses, 1);
      expect(backend.resumes, 1);
    });

    test('leaves already paused playback paused', () async {
      final backend = _FakeBackend(MediaPauseOutcome.nothingPlaying);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.resumes, 0);
    });

    test('does nothing while the setting is off', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.off,
      );
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.pauses, 0);
      expect(backend.resumes, 0);
    });

    test('does nothing when the system is unavailable', () async {
      final backend = _FakeBackend(MediaPauseOutcome.unavailable);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.resumes, 0);
    });

    test('a pause without answer still asks for the resume', () async {
      // The host may pause after the call timed out; it resumes only what
      // it paused itself, so asking is safe.
      final backend = _FakeBackend(MediaPauseOutcome.noAnswer);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
      c.recordingStarted();
      await c.recordingEnded();
      expect(backend.resumes, 1);
    });

    test('stop during an in-flight pause resumes after it finished', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused)
        ..gate = Completer<void>();
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
      c.recordingStarted();
      final ended = c.recordingEnded();
      await Future<void>.delayed(Duration.zero);
      expect(backend.resumes, 0);
      backend.gate!.complete();
      await ended;
      expect(backend.resumes, 1);
    });

    test('still resumes when the setting is switched off meanwhile', () async {
      var mode = MediaWhileRecording.pause;
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(backend: backend, mode: () => mode);
      c.recordingStarted();
      await Future<void>.delayed(Duration.zero);
      mode = MediaWhileRecording.off;
      await c.recordingEnded();
      expect(backend.resumes, 1);
    });

    test('a second end does not resume twice', () async {
      final backend = _FakeBackend(MediaPauseOutcome.paused);
      final c = MediaPauseController(
        backend: backend,
        mode: () => MediaWhileRecording.pause,
      );
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

  group('MediaPauseController ducking', () {
    MediaPauseController duckController(_FakeDuck duck, DuckJournal journal) =>
        MediaPauseController(
          backend: _FakeBackend(MediaPauseOutcome.unavailable),
          duckBackend: duck,
          journal: journal,
          mode: () => MediaWhileRecording.duck,
        );

    test('turns down only what plays and restores it exactly', () async {
      final duck = _FakeDuck({'music': 0.7, 'quiet': 0.4})..playing = {'music'};
      final journal = MemoryDuckJournal();
      final c = duckController(duck, journal);
      c.recordingStarted();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(duck.volumes['music'], closeTo(0.7 * duckFactor, 1e-9));
      expect(duck.volumes['quiet'], 0.4);
      expect(journal.saved, [
        const DuckTarget('music', [0.7]),
      ]);
      await c.recordingEnded();
      expect(duck.volumes['music'], 0.7);
      expect(journal.saved, isEmpty);
    });

    test('nothing playing: nothing changed, no journal', () async {
      final duck = _FakeDuck({'music': 0.7});
      final journal = MemoryDuckJournal();
      final c = duckController(duck, journal);
      c.recordingStarted();
      await c.recordingEnded();
      expect(duck.volumes['music'], 0.7);
      expect(journal.saved, isEmpty);
    });

    test('a crash leaves the journal; the next start restores it', () async {
      final duck = _FakeDuck({'music': 0.7})..playing = {'music'};
      final journal = MemoryDuckJournal();
      duckController(duck, journal).recordingStarted();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(duck.volumes['music'], closeTo(0.175, 1e-9));
      // "Crash": the controller is gone without recordingEnded.
      final next = duckController(duck, journal);
      await next.restoreAfterCrash();
      expect(duck.volumes['music'], 0.7);
      expect(journal.saved, isEmpty);
    });

    test('a failed restore keeps the journal for the next start', () async {
      final duck = _FakeDuck({'music': 0.7})..playing = {'music'};
      final journal = MemoryDuckJournal();
      final c = duckController(duck, journal);
      c.recordingStarted();
      await Future<void>.delayed(Duration.zero);
      duck.failSet = true;
      await c.recordingEnded();
      expect(journal.saved, isNotEmpty);
      duck.failSet = false;
      await duckController(duck, journal).restoreAfterCrash();
      expect(duck.volumes['music'], 0.7);
    });

    test('file journal survives a round trip and ignores damage', () async {
      final dir = await Directory.systemTemp.createTemp('duck_journal');
      addTearDown(() => dir.delete(recursive: true));
      final journal = FileDuckJournal('${dir.path}/j.json');
      expect(await journal.load(), isEmpty);
      const saved = [
        DuckTarget('a', [0.5, 0.25]),
      ];
      await journal.save(saved);
      expect(await journal.load(), saved);
      await journal.clear();
      expect(await journal.load(), isEmpty);
      await File('${dir.path}/j.json').writeAsString('{broken');
      expect(await journal.load(), isEmpty);
    });
  });

  group('PactlMediaDuckBackend', () {
    test('parses streams with raw per-channel volumes', () {
      final inputs = parsePactlSinkInputs(_sinkInputs);
      expect(inputs.map((i) => i.index), [41, 42, 43]);
      expect(inputs[0].rawVolumes, [52429, 45875]);
      expect(inputs[0].corked, isFalse);
      expect(inputs[0].processId, 1200);
      expect(inputs[1].corked, isTrue);
      expect(inputs[1].rawVolumes, [65536]);
    });

    test('ducks uncorked foreign streams and restores raw values', () async {
      final calls = <List<String>>[];
      final backend = PactlMediaDuckBackend(
        ownPid: 999,
        run: (args) async {
          calls.add(args);
          return args.first == 'list' ? _sinkInputs : '';
        },
      );
      final targets = await backend.playingTargets();
      expect(targets.map((t) => t.id), ['41:1200:Firefox']);
      await backend.setLevels([for (final t in targets) t.scaled(duckFactor)]);
      await backend.setLevels(targets);
      final sets = calls.where((c) => c.first == 'set-sink-input-volume');
      expect(sets.map((c) => c.skip(1).join(' ')), [
        '41 13107 11469',
        '41 52429 45875',
      ]);
    });

    test('skips a stream whose index now belongs to another process', () async {
      final calls = <List<String>>[];
      final backend = PactlMediaDuckBackend(
        ownPid: 999,
        run: (args) async {
          calls.add(args);
          return args.first == 'list' ? _sinkInputs : '';
        },
      );
      await backend.setLevels([
        const DuckTarget('41:4242:Other', [1.0, 1.0]),
      ]);
      expect(calls.where((c) => c.first == 'set-sink-input-volume'), isEmpty);
    });

    test('restores a new stream that inherited the ducked volume', () async {
      // Stream 41 ended while ducked; the same process opened 44 and 45. The
      // sound server gave 44 the ducked volume, 45 was set by the user.
      const after = '''
Sink Input #44
\tCorked: no
\tVolume: front-left: 13107 /  20% / -41.94 dB,   front-right: 11468 /  17% / -45.40 dB
\tProperties:
\t\tapplication.process.id = "1200"
Sink Input #45
\tCorked: no
\tVolume: front-left: 30000 /  46% / -20.36 dB,   front-right: 30000 /  46% / -20.36 dB
\tProperties:
\t\tapplication.process.id = "1200"
''';
      final calls = <List<String>>[];
      final backend = PactlMediaDuckBackend(
        ownPid: 999,
        run: (args) async {
          calls.add(args);
          return args.first == 'list' ? after : '';
        },
      );
      await backend.setLevels([
        const DuckTarget('41:1200:', [52429 / 65536, 45875 / 65536]),
        const DuckTarget('41:4242:', [1.0, 1.0]),
      ]);
      final sets = calls.where((c) => c.first == 'set-sink-input-volume');
      expect(sets.map((c) => c.skip(1).join(' ')), ['44 52429 45875']);
    });

    test('a new process of the same app gets its volume back', () async {
      // The player started a new process for the next stream; the sound
      // server handed it the ducked volume by app name.
      const after = '''
Sink Input #50
\tCorked: no
\tVolume: mono: 16384 /  25% / -36.12 dB
\tProperties:
\t\tapplication.name = "Player: Main"
\t\tapplication.process.id = "2002"
''';
      final calls = <List<String>>[];
      final backend = PactlMediaDuckBackend(
        ownPid: 999,
        run: (args) async {
          calls.add(args);
          return args.first == 'list' ? after : '';
        },
      );
      expect(
        parsePactlSinkInputs(after).single.applicationName,
        'Player: Main',
      );
      await backend.setLevels([
        const DuckTarget('48:2001:Player: Main', [1.0]),
      ]);
      final sets = calls.where((c) => c.first == 'set-sink-input-volume');
      expect(sets.map((c) => c.skip(1).join(' ')), ['50 65536']);
    });

    test('no pactl: restore throws so the journal stays', () async {
      final backend = PactlMediaDuckBackend(run: (_) async => null);
      expect(await backend.isAvailable(), isFalse);
      expect(await backend.playingTargets(), isEmpty);
      expect(
        () => backend.setLevels([
          const DuckTarget('1:2', [1.0]),
        ]),
        throwsA(isA<PactlUnavailable>()),
      );
    });
  });

  group('ChannelMediaDuckBackend contract', () {
    const channel = MethodChannel(mediaPauseChannelName);
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('uses the agreed method names and payloads', () async {
      final seen = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen.add(call);
            return switch (call.method) {
              'duckAvailable' => true,
              'playingVolumes' => [
                {
                  'id': 'dev',
                  'levels': [0.5],
                },
              ],
              _ => null,
            };
          });
      final backend = ChannelMediaDuckBackend(channel);
      expect(await backend.isAvailable(), isTrue);
      final targets = await backend.playingTargets();
      expect(targets, [
        const DuckTarget('dev', [0.5]),
      ]);
      await backend.setLevels(targets);
      expect(seen.map((c) => c.method), [
        'duckAvailable',
        'playingVolumes',
        'setVolumes',
      ]);
      expect(seen.last.arguments, [
        {
          'id': 'dev',
          'levels': [0.5],
        },
      ]);
    });

    test('missing host: unavailable, and restore throws', () async {
      final backend = ChannelMediaDuckBackend(channel);
      expect(await backend.isAvailable(), isFalse);
      expect(
        () => backend.setLevels([
          const DuckTarget('dev', [0.5]),
        ]),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
