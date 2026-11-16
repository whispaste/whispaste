import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/playback/recording_playback.dart';

/// Records what the playback logic asks of the player; the test ends a
/// playback by hand through its [ends] callback, or fails the next start.
class _FakePlayer implements RecordingPlayer {
  final played = <String>[];
  final ends = <void Function()>[];
  int stops = 0;
  bool failNext = false;

  @override
  Future<bool> play(String path, {required void Function() onEnd}) async {
    played.add(path);
    if (failNext) {
      failNext = false;
      return false;
    }
    ends.add(onEnd);
    return true;
  }

  @override
  void stop() => stops++;
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
}
