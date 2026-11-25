import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_log.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';

void main() {
  group('correctionLogReason', () {
    CorrectionLogReason reason({
      CorrectionObservationStatus status = CorrectionObservationStatus.pending,
      int count = 1,
      bool replacement = false,
      bool term = false,
    }) => correctionLogReason(
      status: status,
      occurrenceCount: count,
      coveredByReplacement: replacement,
      coveredByTerm: term,
    );

    test('a count below the threshold needs more sightings', () {
      expect(reason(), CorrectionLogReason.needsMore);
    });

    test('reaching the threshold makes it a suggestion', () {
      expect(
        reason(count: correctionCandidateThreshold),
        CorrectionLogReason.suggested,
      );
    });

    test('an existing replacement or term explains why nothing is shown', () {
      expect(
        reason(count: 5, replacement: true),
        CorrectionLogReason.alreadyReplacement,
      );
      expect(reason(count: 5, term: true), CorrectionLogReason.alreadyTerm);
    });

    test('a decision of the user wins over everything else', () {
      expect(
        reason(status: CorrectionObservationStatus.accepted, replacement: true),
        CorrectionLogReason.accepted,
      );
      expect(
        reason(status: CorrectionObservationStatus.rejected, count: 9),
        CorrectionLogReason.rejected,
      );
    });
  });

  group('CorrectionLearningService log', () {
    late HistoryDatabase db;
    const service = CorrectionLearningService();

    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> see(CorrectionSignalSource source, DateTime at) =>
        service.recordSignal(
          CorrectionSignal(
            sourceText: 'teh meeting',
            targetText: 'the meeting',
            timestamp: at,
            source: source,
          ),
          db,
        );

    test(
      'a correction seen once is logged with its source and count',
      () async {
        await see(CorrectionSignalSource.manualEdit, DateTime(2026, 11, 1));

        final entry = (await service.log(db)).single;
        expect(entry.sourceText, 'teh');
        expect(entry.occurrenceCount, 1);
        expect(entry.signalSource, CorrectionSignalSource.manualEdit);
        expect(entry.reason, CorrectionLogReason.needsMore);
        expect(await service.pendingCandidates(db), isEmpty);
      },
    );

    test('the second sighting counts up and turns into a suggestion', () async {
      await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 1));
      await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 2));

      final entry = (await service.log(db)).single;
      expect(entry.occurrenceCount, 2);
      expect(entry.reason, CorrectionLogReason.suggested);
      expect(entry.lastSeenAt, DateTime(2026, 11, 2));
      expect(await service.pendingCandidates(db), hasLength(1));
    });

    test('a term the user already has is named as the reason', () async {
      await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 1));

      final entry = (await service.log(db, existingTerms: {'The'})).single;
      expect(entry.reason, CorrectionLogReason.alreadyTerm);
    });

    test(
      'deleting an entry removes only that row and resets counting',
      () async {
        await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 1));
        await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 2));
        final id = (await service.log(db)).single.id;

        await service.deleteLogEntry(id, db);
        expect(await service.log(db), isEmpty);
        expect(await service.pendingCandidates(db), isEmpty);

        await see(CorrectionSignalSource.voiceCommand, DateTime(2026, 11, 3));
        expect((await service.log(db)).single.occurrenceCount, 1);
      },
    );
  });

  test('a correction an existing replacement covers still shows in the log '
      '(#1969)', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const service = CorrectionLearningService();
    await db.upsertReplacementWithTriggers(
      id: 'existing',
      triggers: const ['teh'],
      replacement: 'the',
      createdAt: DateTime(2026, 1, 1),
      matchMode: 'exact',
      fuzzyThreshold: null,
      origin: 'manual',
    );
    final proposed = await service.recordSignal(
      CorrectionSignal(
        sourceText: 'teh meeting',
        targetText: 'the meeting',
        timestamp: DateTime(2026, 1, 2),
        source: CorrectionSignalSource.manualEdit,
      ),
      db,
    );

    expect(proposed, 0);
    final log = await service.log(db);
    expect(log.single.reason, CorrectionLogReason.alreadyReplacement);
    expect(await service.pendingCandidates(db), isEmpty);
  });
}
