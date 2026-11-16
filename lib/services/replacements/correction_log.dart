/// Pure side of the learning log (#383): why an observed correction is, or is
/// not, offered as a suggestion. No database, no UI.
library;

import 'correction_candidate_detector.dart';
import 'correction_signal.dart';

/// Why a logged correction stands where it stands.
enum CorrectionLogReason {
  /// Seen often enough and shown in the suggestion list.
  suggested,

  /// Seen fewer than [correctionCandidateThreshold] times so far.
  needsMore,

  /// Its source or target is already a replacement trigger.
  alreadyReplacement,

  /// Its target is already one of the user's vocabulary terms.
  alreadyTerm,

  /// The user took it over (as a replacement or a term).
  accepted,

  /// The user dismissed it for good.
  rejected,
}

/// One row of the learning log.
class CorrectionLogEntry {
  const CorrectionLogEntry({
    required this.id,
    required this.sourceText,
    required this.targetText,
    required this.occurrenceCount,
    required this.signalSource,
    required this.lastSeenAt,
    required this.reason,
  });

  final String id;
  final String sourceText;
  final String targetText;
  final int occurrenceCount;
  final CorrectionSignalSource signalSource;
  final DateTime lastSeenAt;
  final CorrectionLogReason reason;
}

/// Maps the state of one observation to its [CorrectionLogReason]. A decision
/// of the user wins, then an existing replacement or term, then the count.
CorrectionLogReason correctionLogReason({
  required CorrectionObservationStatus status,
  required int occurrenceCount,
  required bool coveredByReplacement,
  required bool coveredByTerm,
}) {
  if (status == CorrectionObservationStatus.accepted ||
      status == CorrectionObservationStatus.acceptedTerm) {
    return CorrectionLogReason.accepted;
  }
  if (status == CorrectionObservationStatus.rejected) {
    return CorrectionLogReason.rejected;
  }
  if (coveredByReplacement) return CorrectionLogReason.alreadyReplacement;
  if (coveredByTerm) return CorrectionLogReason.alreadyTerm;
  return occurrenceCount >= correctionCandidateThreshold
      ? CorrectionLogReason.suggested
      : CorrectionLogReason.needsMore;
}
