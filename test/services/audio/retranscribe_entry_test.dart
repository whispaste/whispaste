/// Re-transcription of a history entry from its retained audio.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio/retranscribe_entry.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

class _FakeTranscriber implements Transcriber {
  _FakeTranscriber({this.fail = false});

  final String result = 'neuer text';
  final bool fail;
  int prepared = 0;
  int released = 0;
  List<int>? received;

  @override
  Future<void> prepare() async {
    prepared++;
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    received = wavBytes;
    if (fail) throw Exception('engine down');
    return result;
  }

  @override
  void release() {
    released++;
  }
}

void main() {
  late Directory tmp;
  late HistoryDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-retranscribe-');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: const Value('e1'),
        content: const Value('alter text'),
        title: const Value('alter text'),
        timestamp: Value(DateTime(2026, 10, 17)),
        durationSec: const Value(1.0),
        source: const Value('dictation'),
        isLocal: const Value(true),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> attachAudio(String path) async {
    File(path).writeAsBytesSync([1, 2, 3]);
    await db.insertAudioAttachment(entryId: 'e1', filePath: path, sizeBytes: 3);
  }

  Future<String> contentOf(String id) async {
    final row = await (db.select(
      db.historyEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.content;
  }

  test('replaces the entry text with the new transcript', () async {
    await attachAudio('${tmp.path}/e1.wav');
    final transcriber = _FakeTranscriber();

    final outcome = await retranscribeEntry(
      db: db,
      transcriber: transcriber,
      entryId: 'e1',
    );

    expect(outcome, RetranscribeOutcome.done);
    expect(await contentOf('e1'), 'neuer text');
    expect(transcriber.received, [1, 2, 3]);
    expect(transcriber.released, 1);
  });

  test('reports no audio when the entry has no retained audio', () async {
    final transcriber = _FakeTranscriber();

    final outcome = await retranscribeEntry(
      db: db,
      transcriber: transcriber,
      entryId: 'e1',
    );

    expect(outcome, RetranscribeOutcome.noAudio);
    expect(transcriber.prepared, 0);
    expect(await contentOf('e1'), 'alter text');
  });

  test('reports no audio when the retained file is gone', () async {
    await attachAudio('${tmp.path}/e1.wav');
    File('${tmp.path}/e1.wav').deleteSync();

    final outcome = await retranscribeEntry(
      db: db,
      transcriber: _FakeTranscriber(),
      entryId: 'e1',
    );

    expect(outcome, RetranscribeOutcome.noAudio);
  });

  test('keeps the old text and releases the engine when it fails', () async {
    await attachAudio('${tmp.path}/e1.wav');
    final transcriber = _FakeTranscriber(fail: true);

    final outcome = await retranscribeEntry(
      db: db,
      transcriber: transcriber,
      entryId: 'e1',
    );

    expect(outcome, RetranscribeOutcome.failed);
    expect(await contentOf('e1'), 'alter text');
    expect(transcriber.released, 1);
  });
}
