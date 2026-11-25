/// Orchestrates learning from corrections (issue #144): persists word-level
/// candidates from observed [CorrectionSignal]s, exposes the ones that crossed
/// [correctionCandidateThreshold] for the suggestions tab, and commits the
/// user's decisions. Nothing is applied without a decision. Everything stays
/// on the device; there is no cloud confirmation step.
///
/// Same split as `vocabulary_import_service.dart`: this file is the DB
/// orchestration layer around the pure logic in
/// `correction_candidate_detector.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import 'correction_candidate_detector.dart';
import 'correction_log.dart';
import 'correction_signal.dart';
import 'text_replacement_matcher.dart' show newEntryMatch;

/// Storage value of [CorrectionObservationRow.unit] for word-level candidates.
const String correctionUnitWord = 'word';

/// One candidate ready for the suggestions tab -- the display-facing counterpart
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

  /// Display string: the pair and how often it was corrected, so the list
  /// shows why a suggestion appeared.
  String get displayText => '$sourceText → $targetText  (×$occurrenceCount)';
}

/// What the user decided for one shown candidate.
enum CorrectionDecision {
  /// Create a replacement: whenever the spoken source appears, write the target.
  replacement,

  /// Add the target as a vocabulary term (recognition hint, no text rewrite).
  term,

  /// Dismiss it for good.
  reject,
}

/// Outcome of [CorrectionLearningService.commit]. The vocabulary terms are
/// returned, not written: the caller merges them into the settings, which
/// this service does not own.
class CorrectionCommitResult {
  const CorrectionCommitResult({
    required this.replacementsAdded,
    required this.terms,
  });

  final int replacementsAdded;

  /// Target spellings the user chose to keep as terms, in decision order.
  final List<String> terms;
}

class CorrectionLearningService {
  const CorrectionLearningService();

  /// Persists the candidates of one observed [signal]. Each candidate is
  /// counted under its own key (source and target), so repeats of the same
  /// word-level fix add up even when the surrounding sentences differ.
  /// Candidates that duplicate an existing replacement trigger are stored for
  /// the log but never counted as proposed.
  ///
  /// Call-sites check the "learn from corrections" setting themselves before
  /// calling this; the service has no settings dependency.
  ///
  /// Returns how many of the signal's pairs now wait for a decision in the
  /// Dictionary, so the "Learn correction" hotkey can say whether it proposed
  /// something (a pair rejected before stays rejected and counts zero).
  Future<int> recordSignal(CorrectionSignal signal, HistoryDatabase db) async {
    final pairs = extractCorrectionCandidates(
      before: signal.sourceText,
      after: signal.targetText,
      // Target-app pairs are single changes whose case-only fixes already
      // passed the mid-sentence check (`target_field_span.dart`).
      // The hotkey match runs the same check (`selection_correction_match`).
      keepCaseOnly:
          signal.source == CorrectionSignalSource.targetAppEdit ||
          signal.source == CorrectionSignalSource.selectionHotkey,
    );
    if (pairs.isEmpty) return 0;
    var proposed = 0;
    // One transaction per signal: the read of the current count and the write
    // of the new one must not interleave with a second, overlapping signal
    // for the same key (two edits saved in quick succession), or one count
    // is lost or the unique key on `normalized_key` is violated. The
    // database serialises them through its single-writer coordinator.
    await db.correctionObservationTransaction(() async {
      final triggers = await _existingTriggers(db);
      for (final pair in pairs) {
        // A pair an existing replacement already covers is still logged
        // (#1969): the log names it "already a replacement" instead of the
        // correction vanishing without a trace. It is never proposed.
        final covered = isDuplicateCorrectionCandidate(
          pair,
          existingTriggers: triggers,
          existingTerms: const {},
        );
        final key = normalizeCorrectionKey(pair.sourceText, pair.targetText);
        final row = await db.readCorrectionObservation(key);
        final existing = row == null ? null : _observationFromRow(row);
        final outcome = applyCorrectionCandidate(
          pair,
          signal.timestamp,
          existing,
          // A hotkey press is a deliberate correction: propose it at once.
          immediate: signal.source == CorrectionSignalSource.selectionHotkey,
        );

        await db.upsertCorrectionObservation(
          id: row?.id ?? generateV4Uuid(),
          normalizedKey: key,
          sourceText: outcome.observation.sourceText,
          targetText: outcome.observation.targetText,
          occurrenceCount: outcome.observation.occurrenceCount,
          status: outcome.observation.status.name,
          source: signal.source.name,
          unit: correctionUnitWord,
          firstSeenAt: row?.firstSeenAt ?? signal.timestamp,
          lastSeenAt: signal.timestamp,
        );
        if (!covered &&
            outcome.observation.status == CorrectionObservationStatus.pending &&
            outcome.observation.occurrenceCount >=
                correctionCandidateThreshold) {
          proposed++;
        }
      }
    });
    return proposed;
  }

  /// Every candidate currently eligible for review -- still pending and
  /// observed at least [correctionCandidateThreshold] times, last seen within
  /// [correctionDecayWindow] of [now], and not a duplicate of [existingTerms]
  /// (the user's vocabulary, case ignored). Older rows are hidden, not
  /// deleted.
  Future<List<CorrectionCandidate>> pendingCandidates(
    HistoryDatabase db, {
    Set<String> existingTerms = const {},
    DateTime? now,
  }) async {
    final rows = await db.readPendingCorrectionCandidates(
      correctionCandidateThreshold,
      seenSince: (now ?? DateTime.now()).subtract(correctionDecayWindow),
    );
    final terms = {for (final t in existingTerms) normalizeCorrectionText(t)};
    final triggers = await _existingTriggers(db);
    return [
      for (final row in rows)
        if (!isDuplicateCorrectionCandidate(
          CorrectionCandidatePair(
            sourceText: row.sourceText,
            targetText: row.targetText,
          ),
          existingTriggers: triggers,
          existingTerms: terms,
        ))
          CorrectionCandidate(
            id: row.id,
            sourceText: row.sourceText,
            targetText: row.targetText,
            occurrenceCount: row.occurrenceCount,
          ),
    ];
  }

  /// Every word-level correction seen so far, newest first, each with the
  /// reason it is or is not suggested (#383). [existingTerms] is the user's
  /// vocabulary, case ignored.
  Future<List<CorrectionLogEntry>> log(
    HistoryDatabase db, {
    Set<String> existingTerms = const {},
  }) async {
    final rows = await db.readWordCorrectionObservations();
    final terms = {for (final t in existingTerms) normalizeCorrectionText(t)};
    final triggers = await _existingTriggers(db);
    return [
      for (final row in rows)
        CorrectionLogEntry(
          id: row.id,
          sourceText: row.sourceText,
          targetText: row.targetText,
          occurrenceCount: row.occurrenceCount,
          signalSource: CorrectionSignalSource.values.firstWhere(
            (s) => s.name == row.source,
            orElse: () => CorrectionSignalSource.manualEdit,
          ),
          lastSeenAt: row.lastSeenAt,
          reason: correctionLogReason(
            status: CorrectionObservationStatus.values.byName(row.status),
            occurrenceCount: row.occurrenceCount,
            coveredByReplacement:
                triggers.contains(normalizeCorrectionText(row.sourceText)) ||
                triggers.contains(normalizeCorrectionText(row.targetText)),
            coveredByTerm: terms.contains(
              normalizeCorrectionText(row.targetText),
            ),
          ),
        ),
    ];
  }

  /// Removes one row from the log. Replacements and terms made from it stay.
  Future<void> deleteLogEntry(String id, HistoryDatabase db) =>
      db.deleteCorrectionObservation(id);

  /// Reopen before removing the term: a failed database write must never
  /// remove a term while leaving its suggestion closed. If settings fails,
  /// restore the decision; the saved term remains intact either way.
  Future<void> undoTerm({
    required String id,
    required HistoryDatabase db,
    required Future<void> Function(String term) removeTerm,
  }) async {
    final row = await db.readCorrectionObservationById(id);
    if (row == null || row.status != 'acceptedTerm') return;
    await db.setCorrectionObservationStatus(id, 'pending');
    try {
      await removeTerm(row.targetText);
    } catch (_) {
      await db.setCorrectionObservationStatus(id, 'acceptedTerm');
      rethrow;
    }
  }

  /// Commits [decisions] for the candidates the user was shown. A candidate
  /// that is shown but missing from [decisions] is left pending (the
  /// suggestions tab always decides one candidate at a time).
  ///
  /// [CorrectionDecision.replacement] creates a `learned` replacement with the
  /// same match settings as any new entry, unless the trigger exists already.
  /// Decisions hide the candidate until its log row is deleted; [undoTerm]
  /// explicitly reopens an accepted term suggestion.
  ///
  /// [saveTerms] stores the vocabulary terms of a [CorrectionDecision.term]
  /// decision. A term candidate is marked accepted only after it returned, so
  /// a failure or crash in between leaves the suggestion pending instead of
  /// losing the term.
  Future<CorrectionCommitResult> commit({
    required Map<String, CorrectionDecision> decisions,
    required HistoryDatabase db,
    Future<void> Function(List<String> terms)? saveTerms,
  }) async {
    final now = DateTime.now();
    var replacementsAdded = 0;
    final terms = <String>[];

    for (final entry in decisions.entries) {
      final row = await db.readCorrectionObservationById(entry.key);
      if (row == null || row.status != 'pending') continue;

      switch (entry.value) {
        case CorrectionDecision.reject:
          await db.setCorrectionObservationStatus(row.id, 'rejected');
        case CorrectionDecision.term:
          terms.add(row.targetText);
          await saveTerms?.call([row.targetText]);
          await db.setCorrectionObservationStatus(row.id, 'acceptedTerm');
        case CorrectionDecision.replacement:
          final triggers = await _existingTriggers(db);
          if (!triggers.contains(normalizeCorrectionText(row.sourceText))) {
            final match = newEntryMatch([row.sourceText]);
            await db.upsertReplacementWithTriggers(
              id: generateV4Uuid(),
              triggers: [row.sourceText],
              replacement: row.targetText,
              createdAt: now,
              matchMode: match.mode.name,
              fuzzyThreshold: match.fuzzyThreshold,
              origin: 'learned',
            );
            replacementsAdded++;
          }
          await db.setCorrectionObservationStatus(row.id, 'accepted');
      }
    }
    return CorrectionCommitResult(
      replacementsAdded: replacementsAdded,
      terms: terms,
    );
  }

  /// Takes back a [CorrectionDecision.reject] (the undo of the suggestions
  /// tab): the row is pending again and shows up as a suggestion. Only a
  /// rejected row is touched; an accepted one keeps its decision.
  Future<void> restoreRejected(String id, HistoryDatabase db) async {
    final row = await db.readCorrectionObservationById(id);
    if (row == null ||
        row.status != CorrectionObservationStatus.rejected.name) {
      return;
    }
    await db.setCorrectionObservationStatus(
      id,
      CorrectionObservationStatus.pending.name,
    );
  }

  Future<Set<String>> _existingTriggers(HistoryDatabase db) async {
    final replacements = await db.readAllReplacements();
    return {
      for (final r in replacements)
        for (final t in r.triggers) normalizeCorrectionText(t),
    };
  }

  CorrectionObservation _observationFromRow(CorrectionObservationRow row) =>
      CorrectionObservation(
        sourceText: row.sourceText,
        targetText: row.targetText,
        occurrenceCount: row.occurrenceCount,
        status: CorrectionObservationStatus.values.byName(row.status),
        lastSeenAt: row.lastSeenAt,
      );
}

/// Overridable in tests, same shape as `vocabularyImportServiceProvider`
/// (`replacements_page.dart`). Lives here rather than on a feature page so the
/// history panel's voice correction and manual edit can depend on it without
/// importing across features.
final correctionLearningServiceProvider = Provider<CorrectionLearningService>(
  (ref) => const CorrectionLearningService(),
);

final learnedTermsProvider = FutureProvider<Set<String>>((ref) async {
  final rows = await ref
      .watch(historyDatabaseProvider)
      .readWordCorrectionObservations();
  return {
    for (final row in rows)
      if (row.status == 'acceptedTerm') row.targetText.trim().toLowerCase(),
  };
});
