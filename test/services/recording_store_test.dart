import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/recording_store.dart';

void main() {
  late HistoryDatabase db;
  late DriftRecordingStore store;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = DriftRecordingStore(db);
  });

  tearDown(() => db.close());

  RecordingInput makeInput({
    String transcript = 'hello world',
    bool applyReplacements = false,
    int maxEntries = 0,
  }) => RecordingInput(
    transcript: transcript,
    audioDuration: const Duration(seconds: 5),
    modelId: 'ggml-tiny',
    isLocal: true,
    languageCode: 'en',
    applyTextReplacements: applyReplacements,
    historyMaxEntries: maxEntries,
    wordCount: transcript.trim().split(RegExp(r'\s+')).length,
    processingDurationSec: 2,
  );

  group('DriftRecordingStore', () {
    test('saves entry to database', () async {
      final result = await store.save(
        makeInput(transcript: 'test transcription'),
      );

      expect(result.entryId, isNotEmpty);
      expect(result.processedTranscript, 'test transcription');

      final entries = await db.allEntries(limit: 100, offset: 0);
      expect(entries, hasLength(1));
      expect(entries.first.content, 'test transcription');
    });

    test('applies text replacements when enabled', () async {
      final now = DateTime.now();
      final id = now.millisecondsSinceEpoch.toString();
      await db.upsertReplacement(
        TextReplacementsCompanion.insert(
          id: id,
          trigger: 'hello',
          replacement: 'Hi there',
          createdAt: now,
        ),
      );

      final result = await store.save(
        makeInput(transcript: 'hello world', applyReplacements: true),
      );

      expect(result.processedTranscript, 'Hi there world');
    });

    test('skips replacements when applyTextReplacements is false', () async {
      final now = DateTime.now();
      final id = now.millisecondsSinceEpoch.toString();
      await db.upsertReplacement(
        TextReplacementsCompanion.insert(
          id: id,
          trigger: 'hello',
          replacement: 'Hi there',
          createdAt: now,
        ),
      );

      final result = await store.save(
        makeInput(transcript: 'hello world', applyReplacements: false),
      );

      expect(result.processedTranscript, 'hello world');
    });

    test('records daily stat after save', () async {
      await store.save(makeInput(transcript: 'one two three'));

      final count = await db.analyticsEntryCount();
      expect(count, greaterThan(0));
    });

    test('trims entries when historyMaxEntries is hit', () async {
      // Save 3 entries with limit 2
      await store.save(makeInput(transcript: 'entry one', maxEntries: 2));
      await store.save(makeInput(transcript: 'entry two', maxEntries: 2));
      final result = await store.save(
        makeInput(transcript: 'entry three', maxEntries: 2),
      );

      expect(result.trimmedCount, 1);
      final entries = await db.allEntries(limit: 100, offset: 0);
      expect(entries, hasLength(2));
    });

    test('does not trim when historyMaxEntries is 0', () async {
      for (var i = 0; i < 5; i++) {
        await store.save(makeInput(transcript: 'entry $i', maxEntries: 0));
      }
      final entries = await db.allEntries(limit: 100, offset: 0);
      expect(entries, hasLength(5));
    });
  });
}
