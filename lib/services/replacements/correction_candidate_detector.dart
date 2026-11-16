/// Pure candidate detection for learning from corrections (issue #144).
///
/// A [CorrectionSignal] carries the whole text before and after a correction.
/// [extractCorrectionCandidates] reduces it to word-level candidates
/// ("Kubernetis" -> "Kubernetes"), keeping only small, plausible fixes:
/// one to four changed words, no stop-word-only phrases, no case-only or
/// punctuation-only changes, and at most [correctionMaxCandidatesPerCorrection]
/// suggestions per correction. Each candidate is then counted across repeats
/// (threshold [correctionCandidateThreshold], decay after
/// [correctionDecayWindow]) before it is shown.
///
/// Deliberately dependency-free (no Drift, no UI): the database layer lives in
/// `correction_learning_service.dart`.
library;

import 'correction_stopwords.dart';
import 'correction_word_diff.dart';

/// A correction must be observed this many times before it is proposed.
/// One occurrence never proposes (a single correction is not yet a pattern).
/// Two is the smallest threshold that meets that rule; a suggestion that
/// needs more repeats only delays a correct fix.
const int correctionCandidateThreshold = 2;

/// A repeat counts only while the previous one is this recent. Older
/// occurrences do not add up: a misrecognised name corrected once a quarter
/// is not a pattern, and must not reach the threshold years later.
const Duration correctionDecayWindow = Duration(days: 30);

/// Suggestions offered per correction. Several fixes in one correction are
/// possible, but more than two would turn a broad edit into noise; when more
/// qualify, names and technical terms are kept first (see
/// [_nameOrTermSignal]).
const int correctionMaxCandidatesPerCorrection = 2;

/// Longest phrase (source or target) a candidate may have, in characters.
/// Longer phrases are rewrites, not spellings.
const int correctionMaxPhraseChars = 40;

/// Lifecycle of one persisted correction observation.
enum CorrectionObservationStatus {
  /// Not yet decided -- may or may not have crossed [correctionCandidateThreshold].
  pending,

  /// Accepted as a replacement (or a term before #624); terminal.
  accepted,

  /// Accepted as a vocabulary term; can be reopened by explicit undo.
  acceptedTerm,

  /// Dismissed by the user; terminal. Must never resurface with identical content.
  rejected,
}

/// One proposed fix: the words the text had and the words they should be.
class CorrectionCandidatePair {
  const CorrectionCandidatePair({
    required this.sourceText,
    required this.targetText,
  });

  /// Original spelling as it appeared in the text before the correction.
  final String sourceText;

  /// Spelling the user corrected it to.
  final String targetText;

  @override
  bool operator ==(Object other) =>
      other is CorrectionCandidatePair &&
      other.sourceText == sourceText &&
      other.targetText == targetText;

  @override
  int get hashCode => Object.hash(sourceText, targetText);

  @override
  String toString() =>
      'CorrectionCandidatePair("$sourceText" -> "$targetText")';
}

/// Normalizes correction text for case-insensitive, whitespace-tolerant
/// grouping: trims, lowercases, and collapses any run of whitespace to a
/// single space.
String normalizeCorrectionText(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Grouping key of one candidate. The separator is a control character that
/// cannot occur in normalized text, so "a b" -> "c" and "a" -> "b c" stay apart.
String normalizeCorrectionKey(String sourceText, String targetText) =>
    '${normalizeCorrectionText(sourceText)}\u001f'
    '${normalizeCorrectionText(targetText)}';

/// Word-level candidates of one correction, best first, at most
/// [correctionMaxCandidatesPerCorrection].
///
/// Empty when the correction is not a usable fix: no changed word at all
/// (case, punctuation or spacing only), more than [correctionMaxChangedWords]
/// changed words (a rewrite), a pure insertion or deletion (nothing to
/// replace), or a diff too large to compare word by word.
///
/// [keepCaseOnly] keeps a change of case alone as one candidate ("kubernetes"
/// -> "Kubernetes"). Only target-app edits set it, and only when the word
/// stands mid-sentence, where a capital marks a name (issue #384).
List<CorrectionCandidatePair> extractCorrectionCandidates({
  required String before,
  required String after,
  bool keepCaseOnly = false,
}) {
  final hunks = diffCorrectionWords(before, after);
  if (hunks == null) return const [];
  if (hunks.isEmpty) {
    final pair = CorrectionCandidatePair(
      sourceText: before.trim(),
      targetText: after.trim(),
    );
    String spelling(String text) =>
        [for (final w in wordsOf(text)) w.text].join(' ');
    final caseOnly =
        keepCaseOnly && spelling(pair.sourceText) != spelling(pair.targetText);
    return caseOnly &&
            _isUsableSource(pair.sourceText) &&
            _isUsableTarget(pair.targetText)
        ? [pair]
        : const [];
  }

  var changed = 0;
  for (final hunk in hunks) {
    if (hunk.sourceWords.isEmpty || hunk.targetWords.isEmpty) return const [];
    changed += hunk.changedWords;
  }
  if (changed > correctionMaxChangedWords) return const [];

  final candidates = <CorrectionCandidatePair>[];
  final seen = <String>{};
  for (final hunk in hunks) {
    final pair = CorrectionCandidatePair(
      sourceText: hunk.sourceWords.join(' '),
      targetText: hunk.targetWords.join(' '),
    );
    if (!_isUsableSource(pair.sourceText) ||
        !_isUsableTarget(pair.targetText)) {
      continue;
    }
    if (!seen.add(normalizeCorrectionKey(pair.sourceText, pair.targetText))) {
      continue;
    }
    candidates.add(pair);
  }

  // Stable ordering by hand: names and technical terms first, then text order.
  final indexed = [
    for (var i = 0; i < candidates.length; i++) (i, candidates[i]),
  ];
  indexed.sort((x, y) {
    final byPriority = _priority(x.$2).compareTo(_priority(y.$2));
    return byPriority != 0 ? byPriority : x.$1.compareTo(y.$1);
  });
  return [
    for (final (_, pair) in indexed.take(correctionMaxCandidatesPerCorrection))
      pair,
  ];
}

/// Whether [pair] duplicates something the user already has. A candidate is
/// dropped when its source is already a replacement trigger, or when its
/// target is already a trigger or a vocabulary term (matching case-insensitively).
/// [existingTriggers] and [existingTerms] hold normalized texts.
bool isDuplicateCorrectionCandidate(
  CorrectionCandidatePair pair, {
  required Set<String> existingTriggers,
  required Set<String> existingTerms,
}) {
  final source = normalizeCorrectionText(pair.sourceText);
  final target = normalizeCorrectionText(pair.targetText);
  return existingTriggers.contains(source) ||
      existingTriggers.contains(target) ||
      existingTerms.contains(target);
}

/// Persisted state for one candidate key -- the pure, DB-shape-independent
/// counterpart of a `CorrectionObservations` row.
class CorrectionObservation {
  const CorrectionObservation({
    required this.sourceText,
    required this.targetText,
    required this.occurrenceCount,
    required this.status,
    required this.lastSeenAt,
  });

  /// The most recently observed original-case source spelling.
  final String sourceText;

  /// The most recently observed original-case target spelling.
  final String targetText;

  final int occurrenceCount;
  final CorrectionObservationStatus status;

  /// When the latest occurrence was seen; the decay window counts from here.
  final DateTime lastSeenAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CorrectionObservation &&
          runtimeType == other.runtimeType &&
          sourceText == other.sourceText &&
          targetText == other.targetText &&
          occurrenceCount == other.occurrenceCount &&
          status == other.status &&
          lastSeenAt == other.lastSeenAt;

  @override
  int get hashCode =>
      Object.hash(sourceText, targetText, occurrenceCount, status, lastSeenAt);

  @override
  String toString() =>
      'CorrectionObservation("$sourceText" -> "$targetText", '
      'x$occurrenceCount, $status, $lastSeenAt)';
}

/// Result of folding one new occurrence into an [existing] observation.
class CorrectionObservationOutcome {
  const CorrectionObservationOutcome({
    required this.observation,
    required this.becameCandidate,
  });

  /// The observation state to persist.
  final CorrectionObservation observation;

  /// `true` exactly when this occurrence crossed [correctionCandidateThreshold]
  /// for the first time after a decay or from the start.
  final bool becameCandidate;
}

/// Pure decision function: folds one occurrence of [pair], seen at [seenAt],
/// into [existing] (`null` if this candidate was never observed).
///
/// An observation that is already accepted or rejected is returned unchanged:
/// an accepted one is a live rule, and a rejected one must never come back.
/// A pending one whose last occurrence is older than [correctionDecayWindow]
/// starts counting again at 1. With [immediate] (a deliberate correction,
/// #934) a pending pair reaches [correctionCandidateThreshold] at once.
CorrectionObservationOutcome applyCorrectionCandidate(
  CorrectionCandidatePair pair,
  DateTime seenAt,
  CorrectionObservation? existing, {
  bool immediate = false,
}) {
  if (existing != null &&
      existing.status != CorrectionObservationStatus.pending) {
    return CorrectionObservationOutcome(
      observation: existing,
      becameCandidate: false,
    );
  }

  final decayed =
      existing != null &&
      seenAt.difference(existing.lastSeenAt) > correctionDecayWindow;
  final previousCount = existing == null || decayed
      ? 0
      : existing.occurrenceCount;
  final counted = previousCount + 1;
  final newCount = immediate && counted < correctionCandidateThreshold
      ? correctionCandidateThreshold
      : counted;
  final updated = CorrectionObservation(
    sourceText: pair.sourceText,
    targetText: pair.targetText,
    occurrenceCount: newCount,
    status: CorrectionObservationStatus.pending,
    lastSeenAt: seenAt,
  );

  final wasCandidate = previousCount >= correctionCandidateThreshold;
  final isCandidate = newCount >= correctionCandidateThreshold;
  return CorrectionObservationOutcome(
    observation: updated,
    becameCandidate: isCandidate && !wasCandidate,
  );
}

/// Whether [observation] qualifies for review: still pending and observed at
/// least [correctionCandidateThreshold] times.
bool isCorrectionCandidate(CorrectionObservation observation) =>
    observation.status == CorrectionObservationStatus.pending &&
    observation.occurrenceCount >= correctionCandidateThreshold;

// ---------------------------------------------------------------------------
// Filters and ranking
// ---------------------------------------------------------------------------

final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);
final RegExp _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _cjk = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}'
  r'\p{Script=Hangul}\p{Script=Thai}]',
  unicode: true,
);

/// A spelling to replace. Needs a letter (so pure numbers, which would hit
/// every occurrence of that number, are never proposed) and two characters.
/// A function word is never replaced: "the" -> "teh" would rewrite every
/// "the" in every later text.
bool _isUsableSource(String phrase) =>
    phrase.runes.length >= 2 &&
    _hasLetter.hasMatch(phrase) &&
    _isUsablePhrase(phrase) &&
    !_isOnlyStopwords(phrase);

/// A spelling to write instead. Digits are fine ("zwei" -> "2"), and so is a
/// function word ("teh" -> "the" is the typical typo fix).
bool _isUsableTarget(String phrase) =>
    _hasLetterOrDigit.hasMatch(phrase) && _isUsablePhrase(phrase);

bool _isUsablePhrase(String phrase) {
  if (phrase.runes.length > correctionMaxPhraseChars) return false;
  // Unspaced CJK text has no word boundaries; one "word" would be a sentence.
  return !(_cjk.hasMatch(phrase) && !phrase.contains(' '));
}

bool _isOnlyStopwords(String phrase) =>
    phrase.toLowerCase().split(' ').every(correctionStopwords.contains);

/// Names and technical terms: an uppercase letter or a symbol typical for
/// product and code names ("WhisPaste", "C++", ".NET", "@handle").
final RegExp _nameOrTermSignal = RegExp(r'[\p{Lu}+#@&/._\-]', unicode: true);

int _priority(CorrectionCandidatePair pair) =>
    _nameOrTermSignal.hasMatch(pair.targetText) ? 0 : 1;
