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
    bool insertHistoryEntry = true,
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
    insertHistoryEntry: insertHistoryEntry,
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

    test(
      'regression: a doubled internal space in a stored trigger/replacement '
      'no longer breaks matching against a normally-spaced transcript',
      () async {
        // Real-world repro: a user's Text-Replacement rows were saved with
        // an accidental extra space ("Cloud  Code" -> "Claude  Code"). The
        // old literal RegExp.escape() required two literal spaces, so the
        // rule could never fire against Whisper's normally single-spaced
        // output — the transcript kept the mis-heard "Cloud Code" forever.
        final now = DateTime.now();
        await db.upsertReplacementWithTriggers(
          id: now.millisecondsSinceEpoch.toString(),
          triggers: ['Cloud  Code'],
          replacement: 'Claude  Code',
          createdAt: now,
        );

        final result = await store.save(
          makeInput(
            transcript: 'wir bauen das für Cloud Code, wie würde das gehen',
            applyReplacements: true,
          ),
        );

        expect(
          result.processedTranscript,
          'wir bauen das für Claude Code, wie würde das gehen',
        );
      },
    );

    test('matches a trigger phrase surrounded by punctuation the old '
        'whitelist-based boundary rejected (quotes, parens, dash, hyphen '
        'suffix) — boundary is now "not a letter/digit" rather than a fixed '
        'punctuation list', () async {
      final now = DateTime.now();
      await db.upsertReplacementWithTriggers(
        id: now.millisecondsSinceEpoch.toString(),
        triggers: ['Cloud Code'],
        replacement: 'Claude Code',
        createdAt: now,
      );

      for (final (input, expected) in [
        (
          'wir bauen "Cloud Code" jetzt aus',
          'wir bauen "Claude Code" jetzt aus',
        ),
        (
          'wir bauen (Cloud Code) jetzt aus',
          'wir bauen (Claude Code) jetzt aus',
        ),
        ('das Tool—Cloud Code—ist gemeint', 'das Tool—Claude Code—ist gemeint'),
        (
          'wir nutzen Cloud Code-Projekt jetzt',
          'wir nutzen Claude Code-Projekt jetzt',
        ),
      ]) {
        final result = await store.save(
          makeInput(transcript: input, applyReplacements: true),
        );
        expect(result.processedTranscript, expected, reason: input);
      }
    });

    test('treats a hyphen between trigger words the same as a space — '
        'dictation is inconsistent about which one it emits for a compound '
        'brand name', () async {
      final now = DateTime.now();
      await db.upsertReplacementWithTriggers(
        id: now.millisecondsSinceEpoch.toString(),
        triggers: ['Cloud Code'],
        replacement: 'Claude Code',
        createdAt: now,
      );

      final result = await store.save(
        makeInput(
          transcript: 'wir nutzen Cloud-Code jetzt',
          applyReplacements: true,
        ),
      );

      expect(result.processedTranscript, 'wir nutzen Claude Code jetzt');
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

    test(
      'save() assigns a decorative color slot in the 8-category range',
      () async {
        await store.save(makeInput(transcript: 'colorful entry'));

        final entries = await db.allEntries(limit: 100, offset: 0);
        expect(entries.first.colorSlot, inInclusiveRange(0, 7));
      },
    );

    test('regression: insertHistoryEntry: false (quick-note dictations) still '
        'applies text replacements but writes no row to history_entries — a '
        'quick note must never also appear in Verlauf', () async {
      final now = DateTime.now();
      await db.upsertReplacementWithTriggers(
        id: now.millisecondsSinceEpoch.toString(),
        triggers: ['hello'],
        replacement: 'Hi there',
        createdAt: now,
      );

      final result = await store.save(
        makeInput(
          transcript: 'hello world',
          applyReplacements: true,
          insertHistoryEntry: false,
        ),
      );

      expect(result.processedTranscript, 'Hi there world');
      final entries = await db.allEntries(limit: 100, offset: 0);
      expect(entries, isEmpty);
    });

    test(
      'insertHistoryEntry: false does not trim existing history entries',
      () async {
        await store.save(makeInput(transcript: 'kept one', maxEntries: 1));
        final result = await store.save(
          makeInput(
            transcript: 'quick note text',
            maxEntries: 1,
            insertHistoryEntry: false,
          ),
        );

        expect(result.trimmedCount, 0);
        final entries = await db.allEntries(limit: 100, offset: 0);
        expect(entries, hasLength(1));
        expect(entries.first.content, 'kept one');
      },
    );

    test('two consecutive saves never share a color slot', () async {
      for (var i = 0; i < 10; i++) {
        await store.save(makeInput(transcript: 'entry $i'));
      }

      final entries = await db.allEntries(limit: 100, offset: 0);
      // allEntries returns newest-first; walk it to compare each entry to
      // the one created immediately before it.
      final byCreationOrder = entries.reversed.toList();
      for (var i = 1; i < byCreationOrder.length; i++) {
        expect(
          byCreationOrder[i].colorSlot,
          isNot(byCreationOrder[i - 1].colorSlot),
        );
      }
    });
  });
}
