import 'package:fuzzywuzzy/fuzzywuzzy.dart' show ratio;

/// One replacement rule ready to apply to a raw transcript, decoupled from
/// the DB row shape (`TextReplacement`/`ReplacementWithTriggers`) so this
/// file stays a pure, dependency-free function — see PRD.md "Testing
/// Decisions": tests exercise only input/output pairs, never DB rows.
class TextReplacementRule {
  const TextReplacementRule({
    required this.triggers,
    required this.replacement,
    this.matchMode = TextReplacementMatchMode.exact,
    this.fuzzyThreshold,
  });

  /// Every trigger phrase that fires this rule. Always non-empty.
  final List<String> triggers;
  final String replacement;
  final TextReplacementMatchMode matchMode;

  /// Similarity threshold (0.0-1.0), only meaningful for
  /// [TextReplacementMatchMode.fuzzy].
  final double? fuzzyThreshold;
}

enum TextReplacementMatchMode { exact, fuzzy }

/// A fuzzy target phrase below this many characters is never matched, even
/// at a lenient threshold — short phrases like "id"/"is" produce
/// disproportionate false positives (PRD.md "Fuzzy-Matching-Algorithmus").
const int fuzzyMinTriggerLength = 4;

/// The three named UI tolerance steps (PRD.md "Datenmodell-Erweiterung") —
/// starting values from the concept round, not yet calibrated against real
/// dictation samples (see PRD.md "Further Notes").
const double fuzzyThresholdStrict = 0.92;
const double fuzzyThresholdStandard = 0.85;
const double fuzzyThresholdTolerant = 0.75;

/// Turns a trigger phrase into a regex fragment that matches regardless of
/// which non-letter/non-digit glue dictation put between its words: a single
/// space, a doubled space (e.g. from a stray extra space when the trigger
/// itself was typed/dictated), a hyphen, an em/en dash, or any run of those.
/// Mirrors the `[^\p{L}\p{N}]+` normalization already used for Snippet-Picker
/// exact-match triggers in `exact_match_normalization.dart` — same
/// dictation-inconsistency problem, so the same tolerance.
String _flexibleTriggerPattern(String trigger) {
  final parts = trigger
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((p) => p.isNotEmpty)
      .map(RegExp.escape);
  return parts.join(r'[^\p{L}\p{N}]+');
}

/// Applies every exact-mode [rules] entry to [text], in order — extracted
/// verbatim from the pre-v20 `DriftRecordingStore.save()` logic, unchanged
/// behavior (PRD.md User Story 17: "exakte Replacements ... durch die neue
/// Fuzzy-Option nicht verändert").
String applyExactReplacements(String text, List<TextReplacementRule> rules) {
  var result = text;
  for (final r in rules) {
    if (r.matchMode != TextReplacementMatchMode.exact) continue;
    if (r.triggers.isEmpty) continue;
    // All of a rule's triggers are matched in one alternation pass against
    // the untouched segment — matching them one at a time would let a later
    // trigger match text just inserted by an earlier one.
    final sortedTriggers = [...r.triggers]
      ..sort((a, b) => b.length.compareTo(a.length));
    final alternation = sortedTriggers.map(_flexibleTriggerPattern).join('|');
    final pattern = RegExp(
      r'(?<![\p{L}\p{N}])(?:' + alternation + r')(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    final replacementText = r.replacement.replaceAll(RegExp(' {2,}'), ' ');
    result = result.replaceAll(pattern, replacementText);
  }
  return result;
}

class _FuzzyCandidate {
  _FuzzyCandidate(this.start, this.end, this.score, this.replacement);
  final int start;
  final int end;
  final int score;
  final String replacement;
}

/// Applies every fuzzy-mode entry in [rules] to [text] after exact
/// replacements have already run (see [applyTextReplacements]).
///
/// Word-boundary-aware sliding window: for each fuzzy rule, every window of
/// the target phrase's word count (±1, PRD.md "Fenstergröße = Wortanzahl des
/// Zielbegriffs, ±1") is scored against the target with
/// `fuzzywuzzy.ratio()`. Windows scoring at or above the rule's threshold are
/// candidates; overlapping candidates are resolved by keeping the
/// higher-scoring one (PRD.md "Konfliktauflösung"), then replacements are
/// applied right-to-left so earlier offsets stay valid.
String applyFuzzyReplacements(String text, List<TextReplacementRule> rules) {
  final tokens = _tokenize(text);
  if (tokens.isEmpty) return text;

  final candidates = _collectFuzzyCandidates(text, tokens, rules);
  if (candidates.isEmpty) return text;

  final accepted = _resolveOverlaps(candidates)
    ..sort((a, b) => b.start.compareTo(a.start));

  var result = text;
  for (final match in accepted) {
    result = result.replaceRange(match.start, match.end, match.replacement);
  }
  return result;
}

/// Scores every word-count-sized window (±1, see [applyFuzzyReplacements]
/// doc comment) against every fuzzy-mode rule's triggers, keeping the
/// windows that clear that rule's threshold.
List<_FuzzyCandidate> _collectFuzzyCandidates(
  String text,
  List<_Token> tokens,
  List<TextReplacementRule> rules,
) {
  final candidates = <_FuzzyCandidate>[];
  for (final r in rules) {
    if (r.matchMode != TextReplacementMatchMode.fuzzy) continue;
    final threshold = r.fuzzyThreshold ?? 0.85;
    for (final trigger in r.triggers) {
      if (trigger.trim().length < fuzzyMinTriggerLength) continue;
      final targetWordCount = _tokenize(trigger).length;
      if (targetWordCount == 0) continue;
      candidates.addAll(
        _scoreWindows(text, tokens, trigger, targetWordCount, threshold, r),
      );
    }
  }
  return candidates;
}

Iterable<_FuzzyCandidate> _scoreWindows(
  String text,
  List<_Token> tokens,
  String trigger,
  int targetWordCount,
  double threshold,
  TextReplacementRule rule,
) sync* {
  final minScore = (threshold * 100).round();
  final lowerTrigger = trigger.toLowerCase();
  for (final windowSize in {
    if (targetWordCount > 1) targetWordCount - 1,
    targetWordCount,
    targetWordCount + 1,
  }) {
    if (windowSize <= 0 || windowSize > tokens.length) continue;
    for (var i = 0; i + windowSize <= tokens.length; i++) {
      final start = tokens[i].start;
      final end = tokens[i + windowSize - 1].end;
      final score = ratio(
        text.substring(start, end).toLowerCase(),
        lowerTrigger,
      );
      if (score >= minScore) {
        yield _FuzzyCandidate(start, end, score, rule.replacement);
      }
    }
  }
}

/// Higher score wins on overlap; stable order for equal scores keeps results
/// deterministic across runs (List.sort is not guaranteed stable for close
/// comparisons otherwise, so tie-break by earlier start).
List<_FuzzyCandidate> _resolveOverlaps(List<_FuzzyCandidate> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.start.compareTo(b.start);
    });

  final accepted = <_FuzzyCandidate>[];
  for (final candidate in sorted) {
    final overlaps = accepted.any(
      (a) => candidate.start < a.end && a.start < candidate.end,
    );
    if (!overlaps) accepted.add(candidate);
  }
  return accepted;
}

/// Runs exact replacements, then fuzzy replacements, on [text] — the single
/// entry point `DriftRecordingStore.save()` calls. Order matters: fuzzy
/// windows are computed against the already-exact-replaced text, matching
/// the existing exact-then-nothing-else pipeline shape rather than
/// interleaving the two passes.
String applyTextReplacements(String text, List<TextReplacementRule> rules) {
  final afterExact = applyExactReplacements(text, rules);
  return applyFuzzyReplacements(afterExact, rules);
}

class _Token {
  _Token(this.start, this.end);
  final int start;
  final int end;
}

final _wordPattern = RegExp(r'\S+');

List<_Token> _tokenize(String text) => [
  for (final m in _wordPattern.allMatches(text)) _Token(m.start, m.end),
];
