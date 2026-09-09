/// Pure candidate-detection logic for vocabulary-learning-from-corrections
/// (ticket 01 `.scratch/vocab-learning-corrections/`). Deliberately
/// dependency-free (no Drift, no UI) — testable with plain
/// [CorrectionSignal]/[CorrectionObservation] values, same split as
/// `vocabulary_import_scanner.dart` (pure logic) vs.
/// `vocabulary_import_service.dart` (DB orchestration).
library;

import 'correction_signal.dart';

/// A correction must be observed this many times (normalized,
/// case-insensitive) before it is proposed as a candidate. One occurrence is
/// deliberately not enough — PRD.md acceptance criteria: "eine einzelne
/// Korrektur erzeugt noch keinen Vorschlag". 2 is the smallest threshold that
/// satisfies that requirement while still surfacing a candidate as early as
/// possible (a 3rd repeat of the exact same fix is a strong signal on its
/// own; requiring more would just delay a correct suggestion).
const int correctionCandidateThreshold = 2;

/// Lifecycle of one persisted correction observation.
enum CorrectionObservationStatus {
  /// Not yet reviewed — may or may not have crossed [correctionCandidateThreshold].
  pending,

  /// User confirmed it in the review UI; now a live replacement entry.
  accepted,

  /// User dismissed it in the review UI — must never resurface with
  /// identical (normalized) content.
  rejected,
}

/// Combines [sourceText]/[targetText] into the key two corrections are
/// grouped by: normalized-equal source AND target text must both match for
/// two signals to count as "the same correction" — correcting different
/// source text to the same target (or vice versa) is not the same fix.
String normalizeCorrectionKey(String sourceText, String targetText) =>
    '${normalizeCorrectionText(sourceText)} '
    '${normalizeCorrectionText(targetText)}';

/// Persisted state for one normalized correction key — the pure,
/// DB-shape-independent counterpart of a `CorrectionObservations` row (see
/// `correction_learning_service.dart`).
class CorrectionObservation {
  const CorrectionObservation({
    required this.sourceText,
    required this.targetText,
    required this.occurrenceCount,
    required this.status,
  });

  /// The most recently observed original-case source text for this key.
  final String sourceText;

  /// The most recently observed original-case target text for this key.
  final String targetText;

  final int occurrenceCount;
  final CorrectionObservationStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CorrectionObservation &&
          runtimeType == other.runtimeType &&
          sourceText == other.sourceText &&
          targetText == other.targetText &&
          occurrenceCount == other.occurrenceCount &&
          status == other.status;

  @override
  int get hashCode =>
      Object.hash(sourceText, targetText, occurrenceCount, status);

  @override
  String toString() =>
      'CorrectionObservation("$sourceText" -> "$targetText", '
      'x$occurrenceCount, $status)';
}

/// Result of folding one new [CorrectionSignal] into an [existing]
/// observation (`null` if this correction has never been observed before).
class CorrectionObservationOutcome {
  const CorrectionObservationOutcome({
    required this.observation,
    required this.becameCandidate,
  });

  /// The observation state to persist.
  final CorrectionObservation observation;

  /// `true` exactly when this signal's occurrence count just crossed
  /// [correctionCandidateThreshold] for the first time — lets a caller show
  /// a one-time "new suggestion" notification instead of re-notifying on
  /// every later repeat of an already-eligible correction.
  final bool becameCandidate;
}

/// Pure decision function: folds [signal] into [existing] (the previously
/// persisted observation for the same normalized key, or `null` if this is
/// the first time it has been seen) and returns the updated state.
///
/// An observation that is already [CorrectionObservationStatus.accepted] or
/// [CorrectionObservationStatus.rejected] is left untouched: an accepted
/// correction is already a live replacement (counting further repeats would
/// serve no purpose), and a rejected one must never resurface with identical
/// content (a core acceptance criterion) — so it is never re-counted back
/// into [CorrectionObservationStatus.pending].
CorrectionObservationOutcome applyCorrectionSignal(
  CorrectionSignal signal,
  CorrectionObservation? existing,
) {
  if (existing != null &&
      existing.status != CorrectionObservationStatus.pending) {
    return CorrectionObservationOutcome(
      observation: existing,
      becameCandidate: false,
    );
  }

  final previousCount = existing?.occurrenceCount ?? 0;
  final newCount = previousCount + 1;
  final updated = CorrectionObservation(
    sourceText: signal.sourceText,
    targetText: signal.targetText,
    occurrenceCount: newCount,
    status: CorrectionObservationStatus.pending,
  );

  final wasCandidate = previousCount >= correctionCandidateThreshold;
  final isCandidate = newCount >= correctionCandidateThreshold;
  return CorrectionObservationOutcome(
    observation: updated,
    becameCandidate: isCandidate && !wasCandidate,
  );
}

/// Whether [observation] currently qualifies to be shown as a candidate in
/// the review UI: still pending, and observed at least
/// [correctionCandidateThreshold] times.
bool isCorrectionCandidate(CorrectionObservation observation) =>
    observation.status == CorrectionObservationStatus.pending &&
    observation.occurrenceCount >= correctionCandidateThreshold;
