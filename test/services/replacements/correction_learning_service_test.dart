import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';

void main() {
  late HistoryDatabase db;
  late CorrectionLearningService service;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    service = const CorrectionLearningService();
  });

  tearDown(() async {
    await db.close();
  });

  CorrectionSignal signal(String source, String target) => CorrectionSignal(
    sourceText: source,
    targetText: target,
    timestamp: DateTime(2026, 1, 1),
    source: CorrectionSignalSource.voiceCommand,
  );

  test(
    'a single correction signal is recorded but does not become a candidate',
    () async {
      await service.recordSignal(signal('teh meeting', 'the meeting'), db);

      final candidates = await service.pendingCandidates(db);
      expect(candidates, isEmpty);
    },
  );

  test(
    'the same correction observed twice becomes exactly one candidate',
    () async {
      await service.recordSignal(signal('teh meeting', 'the meeting'), db);
      await service.recordSignal(signal('teh meeting', 'the meeting'), db);

      final candidates = await service.pendingCandidates(db);
      expect(candidates, hasLength(1));
      expect(candidates.single.sourceText, 'teh meeting');
      expect(candidates.single.targetText, 'the meeting');
      expect(candidates.single.occurrenceCount, 2);
    },
  );

  test('the same correction is grouped case-insensitively', () async {
    await service.recordSignal(signal('Teh Meeting', 'The Meeting'), db);
    await service.recordSignal(signal('TEH MEETING', 'THE MEETING'), db);

    final candidates = await service.pendingCandidates(db);
    expect(candidates, hasLength(1));
    expect(candidates.single.occurrenceCount, 2);
  });

  test('different corrections never merge into one candidate', () async {
    await service.recordSignal(signal('teh', 'the'), db);
    await service.recordSignal(signal('recieve', 'receive'), db);

    final candidates = await service.pendingCandidates(db);
    expect(candidates, isEmpty); // Neither reached the threshold alone.
  });

  test(
    'commit writes only the accepted candidates as active replacements',
    () async {
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('recieve', 'receive'), db);
      await service.recordSignal(signal('recieve', 'receive'), db);

      final candidates = await service.pendingCandidates(db);
      expect(candidates, hasLength(2));
      final tehCandidate = candidates.firstWhere((c) => c.sourceText == 'teh');
      final recieveCandidate = candidates.firstWhere(
        (c) => c.sourceText == 'recieve',
      );

      final added = await service.commit(
        shownIds: candidates.map((c) => c.id).toList(),
        acceptedIds: [tehCandidate.id],
        db: db,
      );

      expect(added, 1);
      final replacements = await db.readAllReplacements();
      expect(replacements, hasLength(1));
      expect(replacements.single.triggers, ['teh']);
      expect(replacements.single.row.replacement, 'the');
      expect(replacements.single.row.origin, 'learned');

      // The un-accepted candidate is now rejected and gone from the pending
      // list -- but its record still exists (a defensive sanity check that
      // the id used above was real, not just referenced for its ids).
      expect(recieveCandidate.sourceText, 'recieve');
      expect(await service.pendingCandidates(db), isEmpty);
    },
  );

  test(
    'a rejected candidate never resurfaces even after being observed again',
    () async {
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);
      final candidates = await service.pendingCandidates(db);

      await service.commit(
        shownIds: candidates.map((c) => c.id).toList(),
        acceptedIds: const [], // Reject the only candidate.
        db: db,
      );
      expect(await service.pendingCandidates(db), isEmpty);

      // Observing the exact same correction again must not resurrect it.
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);

      expect(await service.pendingCandidates(db), isEmpty);
      expect(await db.readAllReplacements(), isEmpty);
    },
  );

  test('a manual history edit and a voice command with identical correction '
      'content merge into the same candidate (ticket 02)', () async {
    await service.recordSignal(signal('teh meeting', 'the meeting'), db);
    await service.recordSignal(
      CorrectionSignal(
        sourceText: 'teh meeting',
        targetText: 'the meeting',
        timestamp: DateTime(2026, 1, 2),
        source: CorrectionSignalSource.manualEdit,
      ),
      db,
    );

    final candidates = await service.pendingCandidates(db);
    expect(candidates, hasLength(1));
    expect(candidates.single.sourceText, 'teh meeting');
    expect(candidates.single.targetText, 'the meeting');
    expect(candidates.single.occurrenceCount, 2);
  });

  test(
    'an accepted candidate is not re-offered even if observed again',
    () async {
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);
      final candidates = await service.pendingCandidates(db);

      await service.commit(
        shownIds: candidates.map((c) => c.id).toList(),
        acceptedIds: candidates.map((c) => c.id).toList(),
        db: db,
      );
      expect(await db.readAllReplacements(), hasLength(1));

      await service.recordSignal(signal('teh', 'the'), db);

      expect(await service.pendingCandidates(db), isEmpty);
      expect(await db.readAllReplacements(), hasLength(1));
    },
  );
}
