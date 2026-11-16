import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart'
    show fuzzyThresholdStrict;

void main() {
  late HistoryDatabase db;
  late CorrectionLearningService service;
  // Signals are stamped with the current time so they sit inside the
  // suggestion window; the window tests move `now` instead of waiting.
  final signalTime = DateTime.now();

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
    timestamp: signalTime,
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
      expect(candidates.single.sourceText, 'teh');
      expect(candidates.single.targetText, 'the');
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

  test('a learned entry gets the new-entry match settings', () async {
    await service.recordSignal(signal('teh', 'the'), db);
    await service.recordSignal(signal('teh', 'the'), db);
    await service.recordSignal(signal('recieve', 'receive'), db);
    await service.recordSignal(signal('recieve', 'receive'), db);
    final candidates = await service.pendingCandidates(db);
    final ids = candidates.map((c) => c.id).toList();

    await service.commit(
      decisions: {for (final id in ids) id: CorrectionDecision.replacement},
      db: db,
    );

    final rows = {
      for (final r in await db.readAllReplacements()) r.triggers.single: r.row,
    };
    // Below the minimum length a trigger stays exact.
    expect(rows['teh']!.matchMode, 'exact');
    expect(rows['teh']!.fuzzyThreshold, isNull);
    expect(rows['recieve']!.matchMode, 'fuzzy');
    expect(rows['recieve']!.fuzzyThreshold, fuzzyThresholdStrict);
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

      final result = await service.commit(
        decisions: {
          tehCandidate.id: CorrectionDecision.replacement,
          recieveCandidate.id: CorrectionDecision.reject,
        },
        db: db,
      );

      expect(result.replacementsAdded, 1);
      expect(result.terms, isEmpty);
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
        decisions: {
          for (final c in candidates) c.id: CorrectionDecision.reject,
        },
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
        timestamp: signalTime.add(const Duration(days: 1)),
        source: CorrectionSignalSource.manualEdit,
      ),
      db,
    );

    final candidates = await service.pendingCandidates(db);
    expect(candidates, hasLength(1));
    expect(candidates.single.sourceText, 'teh');
    expect(candidates.single.targetText, 'the');
    expect(candidates.single.occurrenceCount, 2);
  });

  test(
    'an accepted candidate is not re-offered even if observed again',
    () async {
      await service.recordSignal(signal('teh', 'the'), db);
      await service.recordSignal(signal('teh', 'the'), db);
      final candidates = await service.pendingCandidates(db);

      await service.commit(
        decisions: {
          for (final c in candidates) c.id: CorrectionDecision.replacement,
        },
        db: db,
      );
      expect(await db.readAllReplacements(), hasLength(1));

      await service.recordSignal(signal('teh', 'the'), db);

      expect(await service.pendingCandidates(db), isEmpty);
      expect(await db.readAllReplacements(), hasLength(1));
    },
  );

  test('keeping a candidate as a term returns the target and creates no '
      'replacement', () async {
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    final candidates = await service.pendingCandidates(db);

    final result = await service.commit(
      decisions: {for (final c in candidates) c.id: CorrectionDecision.term},
      db: db,
    );

    expect(result.replacementsAdded, 0);
    expect(result.terms, ['Kubernetes']);
    expect(await db.readAllReplacements(), isEmpty);
    expect(await service.pendingCandidates(db), isEmpty);
  });

  test('a decision for an unknown id is ignored', () async {
    final result = await service.commit(
      decisions: {'does-not-exist': CorrectionDecision.replacement},
      db: db,
    );

    expect(result.replacementsAdded, 0);
    expect(await db.readAllReplacements(), isEmpty);
  });

  test('a replacement is not created twice for an existing trigger', () async {
    await db.upsertReplacementWithTriggers(
      id: 'existing',
      triggers: const ['teh'],
      replacement: 'the',
      createdAt: DateTime(2026, 1, 1),
      matchMode: 'exact',
      fuzzyThreshold: null,
      origin: 'manual',
    );
    await service.recordSignal(signal('teh', 'the'), db);
    await service.recordSignal(signal('teh', 'the'), db);
    final candidates = await service.pendingCandidates(db);

    final result = await service.commit(
      decisions: {
        for (final c in candidates) c.id: CorrectionDecision.replacement,
      },
      db: db,
    );

    expect(result.replacementsAdded, 0);
    expect(await db.readAllReplacements(), hasLength(1));
  });

  test('overlapping signals for the same correction lose no count and raise '
      'no unique-key error', () async {
    await Future.wait([
      service.recordSignal(signal('teh meeting', 'the meeting'), db),
      service.recordSignal(signal('teh call', 'the call'), db),
      service.recordSignal(signal('teh plan', 'the plan'), db),
    ]);

    final candidates = await service.pendingCandidates(db, now: signalTime);
    expect(candidates, hasLength(1));
    expect(candidates.single.occurrenceCount, 3);
  });

  test('a term candidate stays pending when saving the term fails', () async {
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    final now = signalTime;
    final candidates = await service.pendingCandidates(db, now: now);

    await expectLater(
      service.commit(
        decisions: {candidates.single.id: CorrectionDecision.term},
        db: db,
        saveTerms: (_) async => throw StateError('settings write failed'),
      ),
      throwsStateError,
    );

    expect(await service.pendingCandidates(db, now: now), hasLength(1));
  });

  test('a term candidate is accepted after its term was saved', () async {
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    await service.recordSignal(signal('kubernets', 'Kubernetes'), db);
    final now = signalTime;
    final candidates = await service.pendingCandidates(db, now: now);
    final saved = <String>[];

    await service.commit(
      decisions: {candidates.single.id: CorrectionDecision.term},
      db: db,
      saveTerms: (terms) async => saved.addAll(terms),
    );

    expect(saved, ['Kubernetes']);
    expect(await service.pendingCandidates(db, now: now), isEmpty);
    expect(
      (await db.readCorrectionObservationById(candidates.single.id))!.status,
      'acceptedTerm',
    );

    // A repeated commit cannot learn the same candidate a second time.
    await service.commit(
      decisions: {candidates.single.id: CorrectionDecision.term},
      db: db,
      saveTerms: (terms) async => saved.addAll(terms),
    );
    expect(saved, ['Kubernetes']);

    // A failed write leaves the decision and its term intact.
    await expectLater(
      service.undoTerm(
        id: candidates.single.id,
        db: db,
        removeTerm: (_) async => throw StateError('write failed'),
      ),
      throwsStateError,
    );
    expect(await service.pendingCandidates(db, now: now), isEmpty);
    await service.undoTerm(
      id: candidates.single.id,
      db: db,
      removeTerm: (term) async => saved.remove(term),
    );
    expect(saved, isEmpty);
    expect(
      (await service.pendingCandidates(db, now: now)).single.id,
      candidates.single.id,
    );
    await service.undoTerm(
      id: candidates.single.id,
      db: db,
      removeTerm: (_) async => fail('Undo must be idempotent'),
    );
  });

  test('suggestions last seen outside the decay window are hidden, not '
      'deleted', () async {
    await service.recordSignal(signal('teh meeting', 'the meeting'), db);
    await service.recordSignal(signal('teh meeting', 'the meeting'), db);

    final inside = signalTime.add(correctionDecayWindow);
    expect(await service.pendingCandidates(db, now: inside), hasLength(1));

    final outside = inside.add(const Duration(seconds: 1));
    expect(await service.pendingCandidates(db, now: outside), isEmpty);
    // Still stored.
    expect(
      await db.readCorrectionObservation(normalizeCorrectionKey('teh', 'the')),
      isNotNull,
    );
  });
}
