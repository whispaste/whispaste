/// Unit tests for the recording journal: begin, end, scan, and skipping of
/// corrupt journal files (5.8 metadata healing for recovery entries).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';

void main() {
  late Directory tmp;
  late RecordingJournal journal;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-journal-');
    journal = RecordingJournal('${tmp.path}/journal');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('a begun recording is found by scan until it ends', () async {
    final started = DateTime(2026, 10, 17, 9, 30);
    await journal.begin(id: 'rec-1', startedAt: started, wavPath: '/x/a.wav');

    var scan = await journal.scan();
    expect(scan.skippedCorrupt, 0);
    expect(scan.recordings.single.id, 'rec-1');
    expect(scan.recordings.single.wavPath, '/x/a.wav');
    expect(scan.recordings.single.startedAt, started);

    await journal.end('rec-1');
    scan = await journal.scan();
    expect(scan.recordings, isEmpty);
  });

  test('a recording with retention off carries no audio path', () async {
    await journal.begin(
      id: 'rec-2',
      startedAt: DateTime(2026, 10, 17),
      wavPath: null,
    );
    final scan = await journal.scan();
    expect(scan.recordings.single.wavPath, isNull);
  });

  test('corrupt journal files are skipped and counted, not fatal', () async {
    await journal.begin(
      id: 'good',
      startedAt: DateTime(2026, 10, 17),
      wavPath: '/x/good.wav',
    );
    final dir = Directory('${tmp.path}/journal');
    File('${dir.path}/broken.json').writeAsStringSync('{ not json');
    File('${dir.path}/wrong-shape.json').writeAsStringSync('[1, 2, 3]');
    File('${dir.path}/bad-date.json').writeAsStringSync(
      '{"id":"bad-date","startedAt":"yesterday","wavPath":null}',
    );
    File('${dir.path}/bad-path.json').writeAsStringSync(
      '{"id":"bad-path","startedAt":"2026-10-17T00:00:00.000","wavPath":42}',
    );

    final scan = await journal.scan();

    expect(scan.recordings.map((r) => r.id), ['good']);
    expect(scan.skippedCorrupt, 4);
    // Corrupt files stay on disk for inspection.
    expect(File('${dir.path}/broken.json').existsSync(), isTrue);
  });

  test('scan of a missing directory is empty, not an error', () async {
    final scan = await RecordingJournal('${tmp.path}/none').scan();
    expect(scan.recordings, isEmpty);
    expect(scan.skippedCorrupt, 0);
  });

  test('the entry id of the history save is kept in the journal', () async {
    await journal.begin(
      id: 'rec-3',
      startedAt: DateTime(2026, 10, 17),
      wavPath: '/x/a.wav',
      entryId: '1760000000000-0001',
    );
    final scan = await journal.scan();
    expect(scan.recordings.single.entryId, '1760000000000-0001');
  });
}
