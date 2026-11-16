import '../../services/replacements/correction_candidate_detector.dart';
import 'role_terms.dart';

/// The term worth offering for the dictionary after a manual correction of a
/// history entry (issue #587): the corrected spelling of the best changed word
/// or phrase (names and technical terms first, as the detector orders them)
/// that the dictionary does not hold yet (case does not matter, the same rule
/// as the terms list). One term at most, so the offer reads as one question.
///
/// Uses the detector of the learning pipeline, so a rewrite, a case or
/// punctuation change and a stop-word-only fix offer nothing.
String? termToOfferAfterCorrection({
  required String before,
  required String after,
  required String vocabulary,
}) {
  final known = {
    for (final t in vocabularyTerms(vocabulary)) t.trim().toLowerCase(),
  };
  for (final pair in extractCorrectionCandidates(
    before: before,
    after: after,
  )) {
    final term = pair.targetText.trim();
    if (term.isNotEmpty && !known.contains(term.toLowerCase())) return term;
  }
  return null;
}
