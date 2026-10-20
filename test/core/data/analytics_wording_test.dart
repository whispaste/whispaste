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
            source: 'manualEdit',
            firstSeenAt: DateTime(2026, 10, 1),
            lastSeenAt: lastSeenAt ?? DateTime(2026, 10, 10),
          ),
        );
  }

  group('analyticsWording', () {
    test('unchanged entries count the same raw and revised', () async {
      await addEntry(id: 'a', content: 'eins zwei drei');
      final w = await db.analyticsWording();
      expect(w.rawWords, 3);
      expect(w.revisedWords, 3);
      expect(w.actionCount, 0);
    });

    test('transformed entries count raw from originalTranscript', () async {
      await addEntry(
        id: 'b',
        content: 'kurz',
        originalTranscript: 'ein etwas längerer roher Satz',
      );
      final w = await db.analyticsWording();
      expect(w.rawWords, 5);
      expect(w.revisedWords, 1);
      expect(w.actionCount, 1);
    });

    test('soft-deleted entries are excluded', () async {
      await addEntry(
        id: 'c',
        content: 'nicht mitzählen',
        deletedAt: DateTime(2026, 10, 11),
      );
      final w = await db.analyticsWording();
      expect(w.revisedWords, 0);
      expect(w.actionCount, 0);
    });

    test('since filters by entry timestamp', () async {
      await addEntry(
        id: 'old',
        content: 'alt',
        timestamp: DateTime(2026, 1, 1),
      );
      await addEntry(
        id: 'new',
        content: 'neu hier',
        timestamp: DateTime(2026, 10, 10),
      );
      final w = await db.analyticsWording(since: DateTime(2026, 9, 1));
      expect(w.revisedWords, 2);
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
