/// Orchestrates vocabulary-learning-from-corrections (ticket 01
/// `.scratch/vocab-learning-corrections/`): persists observed
/// [CorrectionSignal]s, exposes the ones that have crossed
/// [correctionCandidateThreshold] as candidates for the review UI, and
/// commits the user's accept/reject decisions -- an accepted candidate
/// becomes a live `TextReplacement` (origin `learned`), a rejected one is
/// marked so it never resurfaces with identical content.
///
/// Same split as `vocabulary_import_service.dart`: this file is the DB
/// orchestration layer around the pure logic in
/// `correction_candidate_detector.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import 'correction_candidate_detector.dart';
import 'correction_signal.dart';

/// One candidate ready for the review UI -- the display-facing counterpart
/// of a persisted `CorrectionObservationRow` that has crossed
/// [correctionCandidateThreshold].
class CorrectionCandidate {
  const CorrectionCandidate({
    required this.id,
    required this.sourceText,
    required this.targetText,
    required this.occurrenceCount,
  });

  final String id;
  final String sourceText;
  final String targetText;
  final int occurrenceCount;

  /// Display string for the review UI (reused verbatim from
  /// `VocabularyImportReviewPage`, which only knows how to render a flat
  /// `List<String>` -- see its doc comment on why a dedicated widget was not
  /// built for this ticket).
  String get displayText => '$sourceText → $targetText';
}

class CorrectionLearningService {
  const CorrectionLearningService();

  /// Persists one observed [signal]: folds it into the existing observation
  /// for its normalized correction key (if any) via [applyCorrectionSignal]
  /// and writes the result back. Call-sites are expected to check the
  /// "auto-detect corrections" settings toggle themselves before calling
  /// this -- this service has no settings dependency of its own, matching
  /// the "reine, testbare Funktion" split the detector already has.
  Future<void> recordSignal(CorrectionSignal signal, HistoryDatabase db) async {
    final key = normalizeCorrectionKey(signal.sourceText, signal.targetText);
    final row = await db.readCorrectionObservation(key);
    final existing = row == null ? null : _observationFromRow(row);
    final outcome = applyCorrectionSignal(signal, existing);

    await db.upsertCorrectionObservation(
      id: row?.id ?? generateV4Uuid(),
      normalizedKey: key,
      sourceText: outcome.observation.sourceText,
      targetText: outcome.observation.targetText,
      occurrenceCount: outcome.observation.occurrenceCount,
      status: outcome.observation.status.name,
      source: signal.source.name,
      firstSeenAt: row?.firstSeenAt ?? signal.timestamp,
      lastSeenAt: signal.timestamp,
    );
  }

  /// Every correction currently eligible for review -- still pending and
  /// observed at least [correctionCandidateThreshold] times.
  Future<List<CorrectionCandidate>> pendingCandidates(
    HistoryDatabase db,
  ) async {
    final rows = await db.readPendingCorrectionCandidates(
      correctionCandidateThreshold,
    );
    return [
      for (final row in rows)
        CorrectionCandidate(
          id: row.id,
          sourceText: row.sourceText,
          targetText: row.targetText,
          occurrenceCount: row.occurrenceCount,
        ),
    ];
  }

  /// Commits a review decision over a batch of [shownIds] (every candidate
  /// id the user was shown): [acceptedIds] (a subset of [shownIds]) become
  /// live exact-match replacement entries with `origin: 'learned'`; every
  /// other id in [shownIds] is marked `rejected` so it can never resurface
  /// with identical content -- the review UI has no separate per-item
  /// "reject" action (it only offers select-and-commit or cancel-entirely,
  /// see `VocabularyImportReviewPage`), so "shown but not selected when the
  /// user commits" is this feature's reject signal. Returns the number of
  /// candidates accepted.
  Future<int> commit({
    required List<String> shownIds,
    required List<String> acceptedIds,
    required HistoryDatabase db,
  }) async {
    final accepted = acceptedIds.toSet();
    final now = DateTime.now();
    var addedCount = 0;

    for (final id in shownIds) {
      if (!accepted.contains(id)) {
        await db.setCorrectionObservationStatus(id, 'rejected');
        continue;
      }
      final row = await db.readCorrectionObservationById(id);
      if (row == null) continue; // Defensive: id vanished between reads.
      await db.upsertReplacementWithTriggers(
        id: generateV4Uuid(),
        triggers: [row.sourceText],
        replacement: row.targetText,
        createdAt: now,
        origin: 'learned',
      );
      await db.setCorrectionObservationStatus(id, 'accepted');
      addedCount++;
    }
    return addedCount;
  }

  CorrectionObservation _observationFromRow(CorrectionObservationRow row) =>
      CorrectionObservation(
        sourceText: row.sourceText,
        targetText: row.targetText,
        occurrenceCount: row.occurrenceCount,
        status: CorrectionObservationStatus.values.byName(row.status),
      );
}

/// Overridable in tests, same shape as `vocabularyImportServiceProvider`
/// (`replacements_page.dart`). Lives here rather than on a feature page so
/// both the Replacements settings page and the history detail panel's voice
/// correction dispatch (`voice_note_button.dart`) can depend on it without
/// importing across features.
final correctionLearningServiceProvider = Provider<CorrectionLearningService>(
  (ref) => const CorrectionLearningService(),
);
