import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/playback/recording_playback.dart';

/// Records what the playback logic asks of the player; the test ends a
/// playback by hand through its [ends] callback, or fails the next start.
class _FakePlayer implements RecordingPlayer {
  final played = <String>[];
  final starts = <Duration>[];
  final seeks = <Duration>[];
  final ends = <void Function()>[];
  int stops = 0;
  bool failNext = false;
  bool active = false;
  Duration? current;

  @override
  Future<bool> play(
    String path, {
    required void Function() onEnd,
    Duration from = Duration.zero,
  }) async {
    played.add(path);
    starts.add(from);
    if (failNext) {
      failNext = false;
      active = false;
      return false;
    }
    active = true;
    current = from;
    ends.add(onEnd);
    return true;
  }

  @override
  bool seek(Duration to) {
    if (!active) return false;
    seeks.add(to);
    current = to;
    return true;
  }

  @override
  Duration? get position => active ? current : null;

  @override
  void stop() {
    stops++;
    active = false;
  }
}

void main() {
  late _FakePlayer player;
  late ProviderContainer container;

  RecordingPlaybackNotifier notifier() =>
      container.read(recordingPlaybackProvider.notifier);
  String? playing() => container.read(recordingPlaybackProvider);

  setUp(() {
    player = _FakePlayer();
    container = ProviderContainer(
      overrides: [recordingPlayerProvider.overrideWithValue(player)],
    );
  });
  tearDown(() => container.dispose());

  test('start plays the path and marks its entry as playing', () async {
    await notifier().toggle('a', '/a.wav');
    expect(player.played, ['/a.wav']);
    expect(player.starts, [Duration.zero]);
    expect(playing(), 'a');
  });

  test('toggling the playing entry stops it', () async {
    await notifier().toggle('a', '/a.wav');
    await notifier().toggle('a', '/a.wav');
    expect(player.stops, 1);
    expect(player.played, ['/a.wav']);
    expect(playing(), isNull);
  });

  test('another entry takes over, and the old end leaves it playing', () async {
    await notifier().toggle('a', '/a.wav');
    await notifier().toggle('b', '/b.wav');
    expect(player.played, ['/a.wav', '/b.wav']);
    expect(playing(), 'b');

    player.ends.first();
    expect(playing(), 'b');
  });

  test('the natural end clears the playing entry', () async {
    await notifier().toggle('a', '/a.wav');
    player.ends.single();
    expect(playing(), isNull);
  });

  test('a start that fails clears the playing entry', () async {
    player.failNext = true;
    await notifier().toggle('a', '/a.wav');
    expect(playing(), isNull);
  });

  group('playFrom (#672)', () {
    const at = Duration(seconds: 7);

    test('starts a stopped recording at the position', () async {
      await notifier().playFrom('a', '/a.wav', at);
      expect(player.played, ['/a.wav']);
      expect(player.starts, [at]);
      expect(playing(), 'a');
      expect(notifier().positionOf('a'), at);
    });

    test('jumps inside the playing recording without loading again', () async {
      await notifier().toggle('a', '/a.wav');
      await notifier().playFrom('a', '/a.wav', at);
      expect(player.played, ['/a.wav']);
      expect(player.seeks, [at]);
      expect(playing(), 'a');
    });

    test('loads again when the jump fails', () async {
      await notifier().toggle('a', '/a.wav');
      player.active = false;
      await notifier().playFrom('a', '/a.wav', at);
      expect(player.played, ['/a.wav', '/a.wav']);
      expect(player.starts.last, at);
    });

    test('takes over from another entry', () async {
      await notifier().toggle('b', '/b.wav');
      await notifier().playFrom('a', '/a.wav', at);
      expect(player.seeks, isEmpty);
      expect(player.played.last, '/a.wav');
      expect(playing(), 'a');
      expect(notifier().positionOf('b'), isNull);
    });
  });
}
