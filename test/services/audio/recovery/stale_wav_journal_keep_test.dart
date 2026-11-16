/// A WAV named by a journal entry is an interrupted recording awaiting its
/// startup recovery. The stale-file sweep must leave it alone.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  test('a stale WAV that a journal entry names survives the sweep', () async {
    final dir = Directory.systemTemp.createTempSync('wp_journal_keep_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final launchedAt = DateTime(2026, 10, 26, 12);
    final journal = RecordingJournal(p.join(dir.path, 'journal'));

    final journaled = File(p.join(dir.path, 'whispaste_1.wav'))
      ..writeAsBytesSync([0])
      ..setLastModifiedSync(launchedAt.subtract(const Duration(hours: 1)));
    final orphan = File(p.join(dir.path, 'whispaste_2.wav'))
      ..writeAsBytesSync([0])
      ..setLastModifiedSync(launchedAt.subtract(const Duration(hours: 1)));
    await journal.begin(
      id: 'rec-1',
      startedAt: launchedAt.subtract(const Duration(hours: 1)),
      wavPath: journaled.path,
    );

    await AudioServiceNotifier.cleanupStaleFiles(
      directory: dir,
      modifiedBefore: launchedAt,
      now: () => launchedAt,
      journal: journal,
    );

    expect(journaled.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });
}
