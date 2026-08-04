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
    modelId: 'whisper-small',
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
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: ['hello'],
        replacement: 'Hi there',
        createdAt: now,
      );

      final result = await store.save(
        makeInput(transcript: 'hello world', applyReplacements: true),
      );

      expect(result.processedTranscript, 'Hi there world');
    });

    test('matches a trigger regardless of transcript casing', () async {
      final now = DateTime.now();
      await db.upsertReplacementWithTriggers(
        id: now.millisecondsSinceEpoch.toString(),
        triggers: ['mfg'],
        replacement: 'Mit freundlichen Grüßen',
        createdAt: now,
      );

      final result = await store.save(
        makeInput(transcript: 'MFG', applyReplacements: true),
      );

      expect(result.processedTranscript, 'Mit freundlichen Grüßen');
    });

    test('skips replacements when applyTextReplacements is false', () async {
      final now = DateTime.now();
      final id = now.millisecondsSinceEpoch.toString();
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: ['hello'],
        replacement: 'Hi there',
        createdAt: now,
      );

      final result = await store.save(
        makeInput(transcript: 'hello world', applyReplacements: false),
      );

      expect(result.processedTranscript, 'hello world');
    });

    test(
      'each trigger of a multi-trigger replacement matches independently',
      () async {
        final now = DateTime.now();
        await db.upsertReplacementWithTriggers(
          id: now.millisecondsSinceEpoch.toString(),
          triggers: ['brb', 'be right back'],
          replacement: 'I will return shortly',
          createdAt: now,
        );

        final resultShort = await store.save(
          makeInput(transcript: 'brb everyone', applyReplacements: true),
        );
        expect(
          resultShort.processedTranscript,
          'I will return shortly everyone',
        );

        final resultLong = await store.save(
          makeInput(
            transcript: 'be right back everyone',
            applyReplacements: true,
          ),
        );
        expect(
          resultLong.processedTranscript,
          'I will return shortly everyone',
        );
      },
    );

    test(
      'a trigger match is not re-matched by a second trigger of the same '
      'replacement when the replacement text contains that second trigger',
      () async {
        // Regression: "omw" -> "on my way" must not then have "way" (a
        // second trigger of the very same replacement) match the "way"
        // just inserted by the first, cascading into "on my on my way".
        final now = DateTime.now();
        await db.upsertReplacementWithTriggers(
          id: now.millisecondsSinceEpoch.toString(),
          triggers: ['omw', 'way'],
          replacement: 'on my way',
          createdAt: now,
        );

        final result = await store.save(
          makeInput(transcript: 'omw', applyReplacements: true),
        );

        expect(result.processedTranscript, 'on my way');
      },
    );

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
