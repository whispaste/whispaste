import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/features/overview/overview_recent.dart';
import 'package:whispaste/services/audio/playback/recording_playback.dart';

import '../../fixtures/test_helpers.dart';

/// Hand-off test (#170): the "Listen" button of a recent row reaches the
/// shared player with that row's own recording, and rows without audio
/// offer no button at all.
class _FakePlayer implements RecordingPlayer {
  final played = <String>[];

  @override
  Future<bool> play(
    String path, {
    required void Function() onEnd,
    Duration from = Duration.zero,
  }) async {
    played.add(path);
    return true;
  }

  @override
  bool seek(Duration to) => false;

  @override
  Duration? get position => null;

  @override
  void stop() {}
}

HistoryEntry _entry(String id, int minute) => HistoryEntry(
  id: id,
  content: 'text $id',
  title: '',
  timestamp: DateTime(2026, 11, 9, 12, minute),
  durationSec: 1,
  processingDurationSec: 0,
  language: 'de',
  languageHint: '',
  tags: '',
  pinned: false,
  source: 'dictation',
  model: 'whisper',
  isLocal: true,
  costUsd: 0,
  archived: false,
  titleEdited: false,
  colorSlot: 0,
);

void main() {
  testWidgets('play reaches the player with the row\'s own recording', (
    tester,
  ) async {
    final player = _FakePlayer();
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: SingleChildScrollView(child: OverviewRecent())),
        size: const Size(900, 1200),
        overrides: [
          latestRecordingsProvider.overrideWith(
            (ref) => Stream.value([_entry('a', 1), _entry('b', 2)]),
          ),
          overviewRecentAudioProvider.overrideWith(
            (ref) => Stream.value(const {'b': '/audio/b.wav'}),
          ),
          recordingPlayerProvider.overrideWithValue(player),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsIdentifier('overview-recent-play-a'), findsNothing);
    final play = find.bySemanticsIdentifier('overview-recent-play-b');
    expect(play, findsOneWidget);

    await tester.tap(play);
    await tester.pump();

    expect(player.played, ['/audio/b.wav']);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OverviewRecent)),
    );
    expect(container.read(recordingPlaybackProvider), 'b');
  });
}
