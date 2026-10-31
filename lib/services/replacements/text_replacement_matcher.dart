import 'dart:math' show min;

import '../../core/logging/app_logger.dart';
import '../../core/utils/string_similarity.dart';

final _log = AppLogger('Replacements');

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
String _flexibleTriggerPattern(String trigger) =>
    _triggerParts(trigger).map(RegExp.escape).join(r'[^\p{L}\p{N}]+');

/// The alphanumeric runs of [trigger], in order. Empty when the trigger has
/// no letters or digits at all.
List<String> _triggerParts(String trigger) => trigger
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((p) => p.isNotEmpty)
    .toList(growable: false);

/// True when [trigger] never fires as an exact trigger: a single punctuation
/// mark such as `?`. The replacement editor warns about it; the matcher
/// drops it in [_exactTriggerPattern]. Empty triggers are not reported.
bool exactTriggerNeverFires(String trigger) =>
    trigger.trim().isNotEmpty && _exactTriggerPattern(trigger) == null;

/// The regex fragment of one exact trigger, or null when it may not fire.
///
/// A trigger with letters or digits matches whole words only. A trigger
/// without any (such as `->` or `...`) matches its text literally, at any
/// position. It needs at least two characters, because a single punctuation
/// mark such as `?` would change ordinary text everywhere.
String? _exactTriggerPattern(String trigger) {
  if (_triggerParts(trigger).isNotEmpty) {
    return r'(?<![\p{L}\p{N}])' +
        _flexibleTriggerPattern(trigger) +
        r'(?![\p{L}\p{N}])';
  }
  final literal = trigger.trim();
  return literal.runes.length >= 2 ? RegExp.escape(literal) : null;
}

/// Glue around a trigger that inserts a line break: spaces before it, and
/// punctuation plus spaces after it. The comma/period *before* a break is a
/// deliberate keep: it closes the preceding clause ("Hello, new paragraph.
/// Next" becomes "Hello,\n\nNext"). Only used for line-break replacements,
/// so plain replacements keep their exact trigger boundaries.
const _leadingSpaces = r'[ \t]*';
const _trailingGlue = r'[.,;:!?…]*[ \t]*';

/// Turns the stored replacement text into the text that gets inserted.
///
/// Escape syntax (documented in the replacement editor helper text):
/// - `\n` inserts a line break, so `\n\n` gives a blank line;
/// - `\\` inserts one literal backslash, so `\\n` stays a literal `\n`;
/// - any other backslash is kept as typed.
///
/// Spaces directly around an inserted break are dropped. Runs of spaces
/// collapse to one (as before), which never touches a line break.
String _renderReplacement(String raw) {
  final decoded = raw.replaceAllMapped(
    RegExp(r'\\(\\|n)'),
    (m) => m.group(1) == 'n' ? '\n' : r'\',
  );
  return decoded
      .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n')
      .replaceAll(RegExp(' {2,}'), ' ');
}

bool _startsWithBreak(String replacementText) =>
    replacementText.startsWith('\n');

bool _endsWithBreak(String replacementText) => replacementText.endsWith('\n');

/// Widens a fuzzy match [start]..[end] over the glue [_leadingSpaces] and
/// [_trailingGlue] — the same rule the exact pass applies via regex, and only
/// on the sides where [replacementText] actually has a line break.
(int, int) _widenLineBreakGlue(
  String text,
  int start,
  int end,
  String replacementText,
) {
  var s = start;
  if (_startsWithBreak(replacementText)) {
    while (s > 0 && (text[s - 1] == ' ' || text[s - 1] == '\t')) {
      s--;
    }
  }
  var e = end;
  if (_endsWithBreak(replacementText)) {
    e = RegExp(_trailingGlue).matchAsPrefix(text, end)?.end ?? end;
  }
  return (s, e);
}

/// Cap on the windows one call scores with the similarity measure, per fuzzy
/// pass. A count, not wall-clock time, so the same input always gives the same
/// result. When it runs out the windows collected so far are applied (rules in
/// rule order), [CompiledTextReplacements.fuzzyBudgetExceeded] reports it and
/// the overrun is logged.
const int kFuzzyWindowBudget = 200000;

class _WindowBudget {
  _WindowBudget(this._left);

  int _left;

  /// Spends one window; false when none is left.
  bool take() {
    if (_left <= 0) return false;
    _left--;
    return true;
  }
}

/// Matches a word run the way the word index sees it: maximal letters/digits.
final _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);

Set<String> _wordSet(String text) => {
  for (final m in _wordRun.allMatches(text.toLowerCase())) m.group(0)!,
};

/// One word window of the transcript, lowercased and measured once per call
/// so that every fuzzy trigger reuses it.
class _Window {
  _Window(this.start, this.end, this.lower) : runeLength = lower.runes.length;

  final int start;
  final int end;
  final String lower;
  final int runeLength;
}

/// The windows of one transcript, built per window size on first use.
class _WindowIndex {
  _WindowIndex(this._text, this._tokens);

  final String _text;
  final List<_Token> _tokens;
  final Map<int, List<_Window>> _bySize = {};

  List<_Window> windows(int size) => _bySize.putIfAbsent(size, () {
    if (size <= 0 || size > _tokens.length) return const [];
    return [
      for (var i = 0; i + size <= _tokens.length; i++)
        _Window(
          _tokens[i].start,
          _tokens[i + size - 1].end,
          _text
              .substring(_tokens[i].start, _tokens[i + size - 1].end)
              .toLowerCase(),
        ),
    ];
  });
}

class _CompiledExact {
  _CompiledExact(
    this.ruleIndex,
    this.pattern,
    this.replacementText,
    this.firstWords,
  );

  final int ruleIndex;
  final RegExp pattern;
  final String replacementText;

  /// Lowercased first word of every trigger. A trigger's first alphanumeric
  /// run must be a whole word of the text (the pattern's boundaries force
  /// it), so a rule with none of these words in the text cannot match.
  /// Null when some trigger has no word at all: that rule is never skipped.
  final Set<String>? firstWords;
}

class _CompiledTrigger {
  _CompiledTrigger(this.lower, this.wordCount, this.minScore)
    : runeLength = lower.runes.length;

  final String lower;

  /// Length in code points, the unit [stringSimilarity] works in.
  final int runeLength;
  final int wordCount;
  final int minScore;
}

class _CompiledFuzzy {
  _CompiledFuzzy(this.ruleIndex, this.triggers, this.replacementText);

  final int ruleIndex;
  final List<_CompiledTrigger> triggers;
  final String replacementText;
}

/// A rule list compiled once, so the per-dictation cost is the matching, not
/// rebuilding up to one regex per rule on every call.
///
/// Build it when the rules change and reuse it for every transcript. The
/// result is identical to the free functions below, which are wrappers around
/// this class.
class CompiledTextReplacements {
  CompiledTextReplacements(
    List<TextReplacementRule> rules, {
    this.fuzzyWindowBudget = kFuzzyWindowBudget,
  }) {
    for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
      final r = rules[ruleIndex];
      if (r.matchMode == TextReplacementMatchMode.exact) {
        final compiled = _compileExact(ruleIndex, r);
        if (compiled != null) _exact.add(compiled);
      } else {
        final compiled = _compileFuzzy(ruleIndex, r);
        if (compiled != null) _fuzzy.add(compiled);
      }
    }
  }

  /// Windows one fuzzy pass may score; see [kFuzzyWindowBudget].
  final int fuzzyWindowBudget;
  final List<_CompiledExact> _exact = [];
  final List<_CompiledFuzzy> _fuzzy = [];

  /// Whether the last [apply] or [applyFuzzyOnly] call ran out of
  /// [kFuzzyWindowBudget] and so applied only part of its fuzzy rules.
  bool fuzzyBudgetExceeded = false;

  /// Exact replacements, then fuzzy, on [text].
  String apply(String text, {List<int>? hits}) {
    final afterExact = applyExactOnly(text, hits: hits);
    return applyFuzzyOnly(afterExact, hits: hits);
  }

  /// Only the exact-mode rules, in rule order.
  String applyExactOnly(String text, {List<int>? hits}) {
    var result = text;
    Set<String>? words;
    var wordsStale = true;
    for (final e in _exact) {
      final firstWords = e.firstWords;
      if (firstWords != null) {
        if (wordsStale) {
          words = _wordSet(result);
          wordsStale = false;
        }
        if (!firstWords.any(words!.contains)) continue;
      }
      final String next;
      if (hits == null) {
        next = result.replaceAll(e.pattern, e.replacementText);
      } else {
        var count = 0;
        next = result.replaceAllMapped(e.pattern, (_) {
          count++;
          return e.replacementText;
        });
        hits[e.ruleIndex] += count;
      }
      if (next != result) {
        result = next;
        wordsStale = true;
      }
    }
    return result;
  }

  /// Only the fuzzy-mode rules, applied to [text] (normally the output of
  /// [applyExactOnly]). When [kFuzzyWindowBudget] runs out, the candidates
  /// found so far are applied.
  String applyFuzzyOnly(String text, {List<int>? hits}) {
    fuzzyBudgetExceeded = false;
    if (_fuzzy.isEmpty) return text;
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return text;

    final budget = _WindowBudget(fuzzyWindowBudget);
    final index = _WindowIndex(text, tokens);
    final candidates = <_FuzzyCandidate>[];
    outer:
    for (final f in _fuzzy) {
      for (final t in f.triggers) {
        final ok = _collectWindows(text, index, t, f, candidates, budget);
        if (!ok) {
          fuzzyBudgetExceeded = true;
          _log.warning(
            'fuzzy replacement budget exhausted; applied the first '
            '${candidates.length} candidates only',
          );
          break outer;
        }
      }
    }
    if (candidates.isEmpty) return text;

    final accepted = _resolveOverlaps(candidates)
      ..sort((a, b) => b.start.compareTo(a.start));
    if (hits != null) {
      for (final match in accepted) {
        hits[match.ruleIndex]++;
      }
    }

    var result = text;
    for (final match in accepted) {
      result = result.replaceRange(match.start, match.end, match.replacement);
    }
    return result;
  }

  static _CompiledExact? _compileExact(int ruleIndex, TextReplacementRule r) {
    // All of a rule's triggers are matched in one alternation pass against
    // the untouched segment — matching them one at a time would let a later
    // trigger match text just inserted by an earlier one.
    final sortedTriggers = [...r.triggers]
      ..sort((a, b) => b.length.compareTo(a.length));
    final alternatives = sortedTriggers
        .map(_exactTriggerPattern)
        .whereType<String>()
        .toList(growable: false);
    if (alternatives.isEmpty) return null;
    final replacementText = _renderReplacement(r.replacement);
    // A replacement that starts or ends with a line break also takes the
    // glue on that side of the trigger with it (see [_leadingSpaces]).
    final pattern = RegExp(
      (_startsWithBreak(replacementText) ? _leadingSpaces : '') +
          r'(?:' +
          alternatives.join('|') +
          r')' +
          (_endsWithBreak(replacementText) ? _trailingGlue : ''),
      caseSensitive: false,
      unicode: true,
    );
    // A wordless trigger can match anywhere, so such a rule is never skipped
    // by the word-set check in [applyExactOnly].
    final hasWordless = sortedTriggers.any((t) => _triggerParts(t).isEmpty);
    final firstWords = hasWordless
        ? null
        : <String>{
            for (final trigger in sortedTriggers)
              _triggerParts(trigger).first.toLowerCase(),
          };
    return _CompiledExact(ruleIndex, pattern, replacementText, firstWords);
  }

  static _CompiledFuzzy? _compileFuzzy(int ruleIndex, TextReplacementRule r) {
    final threshold = r.fuzzyThreshold ?? 0.85;
    final minScore = (threshold * 100).round();
    final triggers = <_CompiledTrigger>[];
    for (final trigger in r.triggers) {
      if (trigger.trim().length < fuzzyMinTriggerLength) continue;
      // Wordless triggers only ever match exactly, never by similarity.
      if (_triggerParts(trigger).isEmpty) continue;
      final wordCount = _tokenize(trigger).length;
      if (wordCount == 0) continue;
      triggers.add(
        _CompiledTrigger(trigger.toLowerCase(), wordCount, minScore),
      );
    }
    if (triggers.isEmpty) return null;
    return _CompiledFuzzy(
      ruleIndex,
      triggers,
      _renderReplacement(r.replacement),
    );
  }

  /// Scores every window of the trigger's word count (±1) and keeps the ones
  /// at or above the threshold. Returns false when the budget ran out.
  ///
  /// Windows whose best possible score is already below the threshold are
  /// skipped before the costly similarity: the similarity is 2·LCS/(a+b) and
  /// LCS ≤ min(a, b), so 2·min(a, b)/(a+b) bounds it from above. Only windows
  /// that are actually scored use up the budget.
  bool _collectWindows(
    String text,
    _WindowIndex index,
    _CompiledTrigger t,
    _CompiledFuzzy f,
    List<_FuzzyCandidate> out,
    _WindowBudget budget,
  ) {
    for (final windowSize in {
      if (t.wordCount > 1) t.wordCount - 1,
      t.wordCount,
      t.wordCount + 1,
    }) {
      for (final w in index.windows(windowSize)) {
        final total = w.runeLength + t.runeLength;
        if (total > 0) {
          final bound = 2 * min(w.runeLength, t.runeLength) / total;
          if ((bound * 100).round() < t.minScore) continue;
        }
        if (!budget.take()) return false;
        // Whole percent, rounded like the previous library's integer ratio,
        // so the whole-percent thresholds and overlap ordering stay unchanged.
        final score = (stringSimilarity(w.lower, t.lower) * 100).round();
        if (score >= t.minScore) {
          final (from, to) = _widenLineBreakGlue(
            text,
            w.start,
            w.end,
            f.replacementText,
          );
          out.add(
            _FuzzyCandidate(from, to, score, f.replacementText, f.ruleIndex),
          );
        }
      }
    }
    return true;
  }
}

class _FuzzyCandidate {
  _FuzzyCandidate(
    this.start,
    this.end,
    this.score,
    this.replacement,
    this.ruleIndex,
  );
  final int start;
  final int end;
  final int score;
  final String replacement;
  final int ruleIndex;
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

/// Applies every exact-mode [rules] entry to [text], in order. When [hits] is
/// given it must be as long as [rules]; the entry at each rule's index is
/// increased by the number of places that rule changed.
String applyExactReplacements(
  String text,
  List<TextReplacementRule> rules, {
  List<int>? hits,
}) => CompiledTextReplacements(rules).applyExactOnly(text, hits: hits);

/// Applies every fuzzy-mode entry in [rules] to [text]. Prefer
/// [CompiledTextReplacements] when the same rules are applied repeatedly.
String applyFuzzyReplacements(
  String text,
  List<TextReplacementRule> rules, {
  List<int>? hits,
}) => CompiledTextReplacements(rules).applyFuzzyOnly(text, hits: hits);

/// Runs exact replacements, then fuzzy replacements, on [text]. Order
/// matters: fuzzy windows are computed against the already-exact-replaced
/// text. [hits], when given, has one counter per rule (same order as [rules]).
String applyTextReplacements(
  String text,
  List<TextReplacementRule> rules, {
  List<int>? hits,
}) => CompiledTextReplacements(rules).apply(text, hits: hits);

class _Token {
  _Token(this.start, this.end);
  final int start;
  final int end;
}

final _wordPattern = RegExp(r'\S+');

List<_Token> _tokenize(String text) => [
  for (final m in _wordPattern.allMatches(text)) _Token(m.start, m.end),
];

/// Keeps the compiled form of the last rule list seen, so a list that did not
/// change is compiled once for all dictations. The key covers every field
/// the matcher reads, so an edit to any rule forces a recompile.
class CompiledRulesCache {
  String? _key;
  CompiledTextReplacements? _compiled;

  CompiledTextReplacements forRules(List<TextReplacementRule> rules) {
    final key = _signature(rules);
    if (key != _key || _compiled == null) {
      _compiled = CompiledTextReplacements(rules);
      _key = key;
    }
    return _compiled!;
  }

  static String _signature(List<TextReplacementRule> rules) {
    final out = StringBuffer();
    for (final r in rules) {
      out
        ..write(r.matchMode.index)
        ..write('\u001f')
        ..write(r.fuzzyThreshold)
        ..write('\u001f')
        ..write(r.replacement)
        ..write('\u001f')
        ..writeAll(r.triggers, '\u001e')
        ..write('\u001d');
    }
    return out.toString();
  }
}
