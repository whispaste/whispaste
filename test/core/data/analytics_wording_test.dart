/// Analytics 9.7: raw versus revised word counts, transform action count and
/// frequent corrections. Runs against an in-memory history database.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addEntry({
    required String id,
    required String content,
    String? originalTranscript,
    DateTime? timestamp,
    DateTime? deletedAt,
  }) {
    return db
        .into(db.historyEntries)
        .insert(
          HistoryEntriesCompanion.insert(
            id: id,
            content: Value(content),
            timestamp: timestamp ?? DateTime(2026, 10, 10),
            originalTranscript: Value(originalTranscript),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<void> addCorrection({
    required String id,
    required String source,
    required String target,
    required int count,
    String status = 'pending',
    String unit = 'word',
    DateTime? lastSeenAt,
  }) {
    return db
        .into(db.correctionObservations)
        .insert(
          CorrectionObservationsCompanion.insert(
            id: id,
            normalizedKey: id,
            sourceText: source,
            targetText: target,
            occurrenceCount: Value(count),
            status: Value(status),
            unit: Value(unit),
            source: 'manualEdit',
            firstSeenAt: DateTime(2026, 10, 1),
            lastSeenAt: lastSeenAt ?? DateTime(2026, 10, 10),
          ),
        );
  }

  Future<void> dictate({
    required int words,
    int? raw,
    bool transformed = false,
    DateTime? at,
  }) => db.recordDailyStat(
    timestamp: at ?? DateTime(2026, 10, 10, 9),
    model: 'small',
    isLocal: true,
    durationSec: 4,
    processingDurationSec: 1,
    wordCount: words,
    costUsd: 0,
    rawWordCount: raw,
    transformed: transformed,
  );

  // #887: the wording figures come from the daily aggregates, not from the
  // history, so deleting or disabling the history leaves them unchanged.
  group('analyticsWording', () {
    test('unchanged dictations count the same raw and revised', () async {
      await dictate(words: 3);
      final w = await db.analyticsWording();
      expect(w.rawWords, 3);
      expect(w.revisedWords, 3);
      expect(w.actionCount, 0);
    });

    test('transformed dictations count raw words and one action', () async {
      await dictate(words: 1, raw: 5, transformed: true);
      await dictate(words: 2);
      final w = await db.analyticsWording();
      expect(w.rawWords, 7);
      expect(w.revisedWords, 3);
      expect(w.actionCount, 1);
    });

    test('deleting the history does not change the figures', () async {
      await addEntry(
        id: 'b',
        content: 'kurz',
        originalTranscript: 'ein etwas längerer roher Satz',
      );
      await dictate(words: 1, raw: 5, transformed: true);
      final before = await db.analyticsWording();

      await db.delete(db.historyEntries).go();
      final after = await db.analyticsWording();

      expect(after.rawWords, before.rawWords);
      expect(after.revisedWords, before.revisedWords);
      expect(after.actionCount, before.actionCount);
      expect(after.actionCount, 1);
    });

    test('since filters by day', () async {
      await dictate(words: 1, at: DateTime(2026, 1, 1, 9));
      await dictate(words: 2, at: DateTime(2026, 10, 10, 9));
      final w = await db.analyticsWording(since: DateTime(2026, 9, 1));
      expect(w.revisedWords, 2);
    });

    test('a statistics reset clears them', () async {
      await dictate(words: 4, raw: 6, transformed: true);
      await db.resetDailyStats();
      final w = await db.analyticsWording();
      expect(w.rawWords, 0);
      expect(w.actionCount, 0);
    });
  });

  group('analyticsDailyActivity', () {
    test('one slot per day, oldest first, today last', () async {
      final today = DateTime(2026, 10, 10);
      await dictate(words: 1, at: DateTime(2026, 10, 10, 8));
      await dictate(words: 1, at: DateTime(2026, 10, 10, 18));
      await dictate(words: 1, at: DateTime(2026, 10, 8, 9));
      await dictate(words: 1, at: DateTime(2026, 9, 1, 9)); // out of range
      expect(await db.analyticsDailyActivity(days: 4, today: today), [
        0,
        1,
        0,
        2,
      ]);
    });
  });

  group('analyticsTopCorrections', () {
    test('orders by occurrence and excludes rejected', () async {
      await addCorrection(id: 'x', source: 'gaus', target: 'Gauß', count: 2);
      await addCorrection(
        id: 'y',
        source: 'whisper',
        target: 'Whisper',
        count: 5,
      );
      await addCorrection(
        id: 'z',
        source: 'nope',
        target: 'nein',
        count: 9,
        status: 'rejected',
      );
      final top = await db.analyticsTopCorrections();
      expect(top.map((c) => c.sourceText), ['whisper', 'gaus']);
      expect(top.first.count, 5);
    });

    test('never shows whole-text rows from schema v25', () async {
      await addCorrection(id: 'w', source: 'gaus', target: 'Gauß', count: 1);
      await addCorrection(
        id: 't',
        source: 'a complete dictated text',
        target: 'a complete corrected text',
        count: 9,
        unit: 'text',
      );
      final top = await db.analyticsTopCorrections();
      expect(top.map((c) => c.sourceText), ['gaus']);
    });

    test('limit caps the list', () async {
      for (var i = 0; i < 4; i++) {
        await addCorrection(
          id: 'k$i',
          source: 's$i',
          target: 't$i',
          count: i + 1,
        );
      }
      final top = await db.analyticsTopCorrections(limit: 2);
      expect(top, hasLength(2));
      expect(top.first.count, 4);
    });

    test('since filters by last-seen time', () async {
      await addCorrection(
        id: 'old',
        source: 'alt',
        target: 'Alt',
        count: 7,
        lastSeenAt: DateTime(2026, 1, 1),
      );
      final top = await db.analyticsTopCorrections(since: DateTime(2026, 9, 1));
      expect(top, isEmpty);
    });
  });
}
