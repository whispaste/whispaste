/// Re-transcription of a history entry from its retained audio.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio/encryption/recording_vault.dart';
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

final _vault = RecordingVault(dataKey: () async => List<int>.filled(32, 1));

Future<RetranscribeOutcome> _retranscribe(
  HistoryDatabase db,
  Transcriber transcriber, {
  RecordingVault? vault,
}) async {
  final result = await transcribeEntryAudio(
    db: db,
    transcriber: transcriber,
    vault: vault ?? _vault,
    entryId: 'e1',
  );
  final text = result.text;
  if (text != null) await applyRetranscript(db, 'e1', text);
  return result.outcome;
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

    final outcome = await _retranscribe(db, transcriber);

    expect(outcome, RetranscribeOutcome.done);
    expect(await contentOf('e1'), 'neuer text');
    expect(transcriber.received, [1, 2, 3]);
    expect(transcriber.released, 1);
  });

  test('transcribes an encrypted recording from its plain bytes', () async {
    await attachAudio('${tmp.path}/e1.wav');
    await _vault.protect('${tmp.path}/e1.wav');
    final transcriber = _FakeTranscriber();

    expect(await _retranscribe(db, transcriber), RetranscribeOutcome.done);
    expect(transcriber.received, [1, 2, 3]);
  });

  test('an encrypted recording without the key fails, text kept', () async {
    await attachAudio('${tmp.path}/e1.wav');
    await _vault.protect('${tmp.path}/e1.wav');
    final transcriber = _FakeTranscriber();

    final outcome = await _retranscribe(
      db,
      transcriber,
      vault: RecordingVault(dataKey: () async => null),
    );

    expect(outcome, RetranscribeOutcome.failed);
    expect(transcriber.prepared, 0);
    expect(await contentOf('e1'), 'alter text');
  });

  test('reports no audio when the entry has no retained audio', () async {
    final transcriber = _FakeTranscriber();

    final outcome = await _retranscribe(db, transcriber);

    expect(outcome, RetranscribeOutcome.noAudio);
    expect(transcriber.prepared, 0);
    expect(await contentOf('e1'), 'alter text');
  });

  test('reports no audio when the retained file is gone', () async {
    await attachAudio('${tmp.path}/e1.wav');
    File('${tmp.path}/e1.wav').deleteSync();

    final outcome = await _retranscribe(db, _FakeTranscriber());

    expect(outcome, RetranscribeOutcome.noAudio);
  });

  test('keeps the old text and releases the engine when it fails', () async {
    await attachAudio('${tmp.path}/e1.wav');
    final transcriber = _FakeTranscriber(fail: true);

    final outcome = await _retranscribe(db, transcriber);

    expect(outcome, RetranscribeOutcome.failed);
    expect(await contentOf('e1'), 'alter text');
    expect(transcriber.released, 1);
  });

  test(
    'transcribing for review leaves the entry until it is applied',
    () async {
      await attachAudio('${tmp.path}/e1.wav');

      final result = await transcribeEntryAudio(
        db: db,
        transcriber: _FakeTranscriber(),
        vault: _vault,
        entryId: 'e1',
      );

      expect(result.outcome, RetranscribeOutcome.done);
      expect(result.text, 'neuer text');
      expect(await contentOf('e1'), 'alter text');

      await applyRetranscript(db, 'e1', result.text!);
      expect(await contentOf('e1'), 'neuer text');
    },
  );

  test('the audio is offered only while the file exists', () async {
    final container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    expect(await container.read(entryHasAudioProvider('e1').future), isFalse);

    await attachAudio('${tmp.path}/e1.wav');
    container.invalidate(entryHasAudioProvider('e1'));
    expect(await container.read(entryHasAudioProvider('e1').future), isTrue);

    File('${tmp.path}/e1.wav').deleteSync();
    container.invalidate(entryHasAudioProvider('e1'));
    expect(await container.read(entryHasAudioProvider('e1').future), isFalse);
  });
}
