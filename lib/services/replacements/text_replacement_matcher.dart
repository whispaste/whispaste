import 'dart:io' show Platform;
import 'dart:math' show min;

import '../../core/logging/app_logger.dart';
import '../../core/utils/string_similarity.dart';
import '../snippets/system_variables.dart';

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

/// Whether [trigger] can be matched by similarity: at least
/// [fuzzyMinTriggerLength] characters and some letter or digit. A fuzzy rule
/// matches every other trigger exactly (see [CompiledTextReplacements]).
bool triggerAllowsFuzzy(String trigger) =>
    trigger.trim().length >= fuzzyMinTriggerLength &&
    _triggerParts(trigger).isNotEmpty;

/// The triggers of a similar entry that match exactly instead (#204): every
/// non-empty trigger for which [triggerAllowsFuzzy] is false. Empty for an
/// exact entry, whose triggers all match exactly anyway.
List<String> exactFallbackTriggers(
  TextReplacementMatchMode mode,
  Iterable<String> triggers,
) => mode == TextReplacementMatchMode.fuzzy
    ? [
        for (final t in triggers)
          if (t.trim().isNotEmpty && !triggerAllowsFuzzy(t)) t,
      ]
    : const [];

/// Match settings of a newly created entry with [triggers] (maintainer
/// 2026-10-31): similar at [fuzzyThresholdStrict], which also catches small
/// recognition variants, when every trigger allows it; otherwise exact.
/// Mixed lists stay exact because a fuzzy rule would silently drop its short
/// or punctuation triggers. Every way of creating an entry uses this;
/// existing entries keep what they have.
({TextReplacementMatchMode mode, double? fuzzyThreshold}) newEntryMatch(
  Iterable<String> triggers,
) {
  final list = [
    for (final t in triggers)
      if (t.trim().isNotEmpty) t,
  ];
  return list.isNotEmpty && list.every(triggerAllowsFuzzy)
      ? (
          mode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: fuzzyThresholdStrict,
        )
      : (mode: TextReplacementMatchMode.exact, fuzzyThreshold: null);
}

/// Turns a trigger phrase into a regex fragment that matches regardless of
/// which non-letter/non-digit glue dictation put between its words: a single
/// space, a doubled space (e.g. from a stray extra space when the trigger
/// itself was typed/dictated), a hyphen, an em/en dash, or any run of those.
/// Other punctuation belongs to the trigger and is matched literally, so
/// `C++`, `.NET`, handles and email-like triggers retain their meaning.
String _flexibleTriggerPattern(String trigger) => trigger.trim().splitMapJoin(
  RegExp(
    r'(?<=[\p{L}\p{M}\p{N}])[\s\-–—]+(?=[\p{L}\p{M}\p{N}])',
    unicode: true,
  ),
  onMatch: (_) => r'[^\p{L}\p{M}\p{N}]+',
  onNonMatch: RegExp.escape,
);

/// The alphanumeric runs of [trigger], in order. Empty when the trigger has
/// no letters or digits at all.
List<String> _triggerParts(String trigger) => trigger
    .split(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true))
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
    return r'(?<![\p{L}\p{M}\p{N}_])' +
        _flexibleTriggerPattern(trigger) +
        r'(?![\p{L}\p{M}\p{N}_])';
  }
  final literal = trigger.trim();
  return literal.runes.length >= 2 ? RegExp.escape(literal) : null;
}

/// Glue around a trigger that inserts a line break: spaces before it, and
/// punctuation plus spaces after it. The comma/period *before* a break is a
/// deliberate keep: it closes the preceding clause ("Hello, new paragraph.
/// Next" becomes "Hello,\n\nNext"). Only used for line-break replacements,
/// so plain replacements keep their exact trigger boundaries.
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

/// Dictation replacements run synchronously, so `{\$clipboard}` is empty
/// here; date, time and the other variables resolve as in snippets.
String _resolveReplacementVariables(String text) => resolveSystemVariables(
  text,
  now: DateTime.now(),
  locale: Platform.localeName,
).text;

bool _startsWithBreak(String replacementText) =>
    replacementText.startsWith('\n');

bool _endsWithBreak(String replacementText) => replacementText.endsWith('\n');

/// Widens a match [start]..[end] over leading spaces and [_trailingGlue], only
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
final _wordRun = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

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
///
/// A window starts at its first letter or digit and ends after its last one:
/// punctuation that sticks to the outer words ("Kubernetes." or "(WhisPaste")
/// is neither scored nor replaced, so a match at the end of a sentence keeps
/// its period. Punctuation between the words stays part of the window.
class _WindowIndex {
  _WindowIndex(this._text, this._tokens);

  final String _text;
  final List<_Token> _tokens;
  final Map<int, List<_Window>> _bySize = {};

  List<_Window> windows(int size) => _bySize.putIfAbsent(size, () {
    if (size <= 0 || size > _tokens.length) return const [];
    final out = <_Window>[];
    for (var i = 0; i + size <= _tokens.length; i++) {
      final core = _wordCore(
        _text,
        _tokens[i].start,
        _tokens[i + size - 1].end,
      );
      if (core == null) continue;
      final (start, end) = core;
      out.add(_Window(start, end, _text.substring(start, end).toLowerCase()));
    }
    return out;
  });
}

final _leadingNonWord = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);
final _trailingNonWord = RegExp(r'[^\p{L}\p{N}]+$', unicode: true);

/// [start]..[end] of [text] without leading and trailing characters that are
/// neither letters nor digits; null when nothing is left.
(int, int)? _wordCore(String text, int start, int end) {
  final slice = text.substring(start, end);
  final from = _leadingNonWord.firstMatch(slice)?.end ?? 0;
  if (from == slice.length) return null;
  final to = _trailingNonWord.firstMatch(slice)?.start ?? slice.length;
  return (start + from, start + to);
}

class _CompiledExact {
  _CompiledExact(
    this.ruleIndex,
    this.pattern,
    this.replacementText,
    this.firstWords,
    this.triggerLength,
  );

  final int ruleIndex;
  final RegExp pattern;
  final String replacementText;
  final int triggerLength;

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
    this.resolveVariables = _resolveReplacementVariables,
  }) {
    for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
      final r = rules[ruleIndex];
      if (r.matchMode == TextReplacementMatchMode.exact) {
        _exact.addAll(_compileExact(ruleIndex, r));
      } else {
        final compiled = _compileFuzzy(ruleIndex, r);
        if (compiled != null) _fuzzy.add(compiled);
        // Triggers a similar rule cannot score (too short, no letter or
        // digit) match exactly instead of being skipped silently
        // (maintainer 2026-11-02, #204). They join the exact pass, which
        // runs before the similar one.
        final skipped = exactFallbackTriggers(r.matchMode, r.triggers);
        if (skipped.isNotEmpty) {
          final fallback = _compileExact(
            ruleIndex,
            TextReplacementRule(triggers: skipped, replacement: r.replacement),
          );
          _exact.addAll(fallback);
        }
      }
    }
  }

  /// Fills `{\$name}` system variables (#663) into a replacement right when
  /// it is inserted, so date and time are those of the dictation.
  final String Function(String) resolveVariables;

  /// Windows one fuzzy pass may score; see [kFuzzyWindowBudget].
  final int fuzzyWindowBudget;
  final List<_CompiledExact> _exact = [];

  /// [_exact] grouped by rule, in rule order (the cascade steps).
  late final List<List<_CompiledExact>> _exactGroups = () {
    final groups = <List<_CompiledExact>>[];
    for (final e in _exact) {
      if (groups.isNotEmpty && groups.last.first.ruleIndex == e.ruleIndex) {
        groups.last.add(e);
      } else {
        groups.add([e]);
      }
    }
    return groups;
  }();
  final List<_CompiledFuzzy> _fuzzy = [];

  /// Whether the last [apply] or [applyFuzzyOnly] call ran out of
  /// [kFuzzyWindowBudget] and so applied only part of its fuzzy rules.
  bool fuzzyBudgetExceeded = false;

  /// Exact replacements, then fuzzy, on [text]. With [cascade] off (#1004)
  /// every rule only matches the original [text], see [applyOnOriginal].
  String apply(String text, {List<int>? hits, bool cascade = true}) {
    if (!cascade) return applyOnOriginal(text, hits: hits);
    final afterExact = applyExactOnly(text, hits: hits);
    return applyFuzzyOnly(afterExact, hits: hits);
  }

  /// Every rule matches only the original [text]; inserted text is never
  /// replaced again (setting "build on each other" off, #1004). Overlaps:
  /// exact triggers before similar ones, the longest exact trigger wins
  /// (ties prefer list order), similar candidates by score.
  String applyOnOriginal(String text, {List<int>? hits}) {
    fuzzyBudgetExceeded = false;
    final exact = _exact.isEmpty
        ? const <_FuzzyCandidate>[]
        : _resolveOverlaps(
            _exactCandidates(text, _wordSet(text), _exact),
            preferRuleOrder: true,
          );
    final fuzzy = <_FuzzyCandidate>[];
    for (final c in _fuzzyCandidates(text)) {
      if (!exact.any((e) => c.start < e.end && e.start < c.end)) fuzzy.add(c);
    }
    final accepted = [...exact, ..._resolveOverlaps(fuzzy)]
      ..sort((a, b) => a.start.compareTo(b.start));
    if (accepted.isEmpty) return text;
    final exactSet = exact.toSet();
    final out = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < accepted.length; i++) {
      final match = accepted[i];
      var (start, end) = exactSet.contains(match)
          ? _widenLineBreakGlue(text, match.start, match.end, match.replacement)
          : (match.start, match.end);
      // Glue never swallows the next match and is consumed only once.
      if (start < cursor) start = cursor;
      if (i + 1 < accepted.length && accepted[i + 1].start < end) {
        end = accepted[i + 1].start;
      }
      out
        ..write(text.substring(cursor, start))
        ..write(resolveVariables(match.replacement));
      cursor = end;
      if (hits != null) hits[match.ruleIndex]++;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }

  /// Exact rules as a cascade: rule by rule in list order, each on the text the
  /// earlier rules produced, so inserted text can be replaced again by a later
  /// rule. Within one step the longest trigger across all rules wins an
  /// overlap (code points; ties prefer rule order, then the earlier
  /// occurrence): a shorter trigger never hides a longer one of another rule,
  /// which then fires at its own turn. One rule never rematches its own output.
  String applyExactOnly(String text, {List<int>? hits}) {
    if (_exact.isEmpty) return text;
    var result = text;
    var words = _wordSet(result);
    for (final group in _exactGroups) {
      final ruleIndex = group.first.ruleIndex;
      final own = _exactCandidates(result, words, group);
      if (own.isEmpty) continue;
      final all = [...own];
      for (final other in _exactGroups) {
        if (!identical(other, group)) {
          all.addAll(_exactCandidates(result, words, other));
        }
      }
      final accepted = _resolveOverlaps(all, preferRuleOrder: true);
      final mine = [
        for (final c in accepted)
          if (c.ruleIndex == ruleIndex) c,
      ]..sort((a, b) => a.start.compareTo(b.start));
      if (mine.isEmpty) continue;
      final others = [
        for (final c in accepted)
          if (c.ruleIndex != ruleIndex) c,
      ];
      final out = StringBuffer();
      var cursor = 0;
      for (var i = 0; i < mine.length; i++) {
        final match = mine[i];
        var (start, end) = _widenLineBreakGlue(
          result,
          match.start,
          match.end,
          match.replacement,
        );
        // Glue never swallows a trigger another rule (or the next match)
        // will replace, and is consumed only once.
        for (final o in others) {
          if (o.end <= match.start && o.end > start) start = o.end;
          if (o.start >= match.end && o.start < end) end = o.start;
        }
        if (i + 1 < mine.length && mine[i + 1].start < end) {
          end = mine[i + 1].start;
        }
        out.write(result.substring(cursor, start < cursor ? cursor : start));
        out.write(resolveVariables(match.replacement));
        cursor = end;
        if (hits != null) hits[match.ruleIndex]++;
      }
      out.write(result.substring(cursor));
      final next = out.toString();
      if (next != result) {
        result = next;
        words = _wordSet(result);
      }
    }
    return result;
  }

  /// Every occurrence of the triggers in [group] in [text], overlapping ones
  /// included (the pattern is a lookahead).
  static List<_FuzzyCandidate> _exactCandidates(
    String text,
    Set<String> words,
    List<_CompiledExact> group,
  ) {
    final out = <_FuzzyCandidate>[];
    for (final e in group) {
      final firstWords = e.firstWords;
      if (firstWords != null && !firstWords.any(words.contains)) continue;
      for (final match in e.pattern.allMatches(text)) {
        out.add(
          _FuzzyCandidate(
            match.start,
            match.start + match.group(1)!.length,
            e.triggerLength,
            e.replacementText,
            e.ruleIndex,
          ),
        );
      }
    }
    return out;
  }

  /// Only the fuzzy-mode rules, applied to [text] (normally the output of
  /// [applyExactOnly]). When [kFuzzyWindowBudget] runs out, the candidates
  /// found so far are applied.
  String applyFuzzyOnly(String text, {List<int>? hits}) {
    fuzzyBudgetExceeded = false;
    final candidates = _fuzzyCandidates(text);
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
      result = result.replaceRange(
        match.start,
        match.end,
        resolveVariables(match.replacement),
      );
    }
    return result;
  }

  /// Every window of [text] a similar rule scores high enough. Sets
  /// [fuzzyBudgetExceeded] when [kFuzzyWindowBudget] runs out.
  List<_FuzzyCandidate> _fuzzyCandidates(String text) {
    if (_fuzzy.isEmpty) return const [];
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return const [];

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
    return candidates;
  }

  static Iterable<_CompiledExact> _compileExact(
    int ruleIndex,
    TextReplacementRule r,
  ) sync* {
    final replacementText = _renderReplacement(r.replacement);
    for (final trigger in r.triggers) {
      final fragment = _exactTriggerPattern(trigger);
      if (fragment == null) continue;
      final parts = _triggerParts(trigger);
      yield _CompiledExact(
        ruleIndex,
        RegExp('(?=($fragment))', caseSensitive: false, unicode: true),
        replacementText,
        parts.isEmpty ? null : {parts.first.toLowerCase()},
        trigger.trim().runes.length,
      );
    }
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
      // Compared in the same trimmed form as the windows (see [_wordCore]).
      final (from, to) = _wordCore(trigger, 0, trigger.length)!;
      triggers.add(
        _CompiledTrigger(
          trigger.substring(from, to).toLowerCase(),
          wordCount,
          minScore,
        ),
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
        if (score >= t.minScore && !_isOtherWordForm(w.lower, t.lower)) {
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

final _whitespace = RegExp(r'\s+');

/// Typical inflection endings per app language that turn one form of a word
/// into another by appending letters (maintainer 2026-11-01, core review
/// L-14 F5). Only such an ending marks a word form; any other appended
/// letters ("whispe" heard for "whisper") are a recognition error. The
/// matcher does not know the dictation language, so all lists apply.
const _wordFormEndings = <String, List<String>>{
  'de': ['e', 'n', 'en', 'nen', 's', 'es', 'er', 'ern', 'em', 'ens'],
  'en': ['s', 'es', 'd', 'ed', 'ing', 'er', 'ers', 'est'],
  'es': ['s', 'es'],
  'pt': ['s', 'es'],
  'ru': [
    'а',
    'я',
    'у',
    'ю',
    'е',
    'ы',
    'и',
    'ой',
    'ей',
    'ом',
    'ем',
    'ов',
    'ев',
    'ам',
    'ям',
    'ах',
    'ях',
    'ами',
    'ями',
  ],
  'he': ['ים', 'ות', 'ה', 'ת', 'י', 'ו'],
};

final Set<String> _anyWordFormEnding = {
  for (final endings in _wordFormEndings.values) ...endings,
};

/// Whether the lowercased [a] and [b] differ by another form of one of their
/// words ("projekte ideen" and "projekt ideen"), see [_isOtherWordFormOfWord].
/// Words are compared pairwise, so a multi-word trigger is guarded like a
/// single word; windows with a different word count are never word forms.
/// Inside a multi-word trigger only words of at least
/// [fuzzyMinTriggerLength] count: "id" heard as "idee" is a recognition
/// error, not a word form.
bool isOtherWordForm(String a, String b) => _isOtherWordForm(a, b);

bool _isOtherWordForm(String a, String b) {
  final aWords = a.split(_whitespace);
  final bWords = b.split(_whitespace);
  if (aWords.length != bWords.length) return false;
  if (aWords.length == 1) return _isOtherWordFormOfWord(a, b);
  for (var i = 0; i < aWords.length; i++) {
    final shorter = min(aWords[i].length, bWords[i].length);
    if (shorter >= fuzzyMinTriggerLength &&
        _isOtherWordFormOfWord(aWords[i], bWords[i])) {
      return true;
    }
  }
  return false;
}

/// Whether one of the words [a] and [b] is the other plus a typical ending
/// ("projekte" and "projekt", "meeting" and "meetings"), see
/// [_wordFormEndings]. That is another form of the same word, not a
/// recognition error, so a similar match on it would silently rewrite
/// correct text.
bool _isOtherWordFormOfWord(String a, String b) {
  if (a.length == b.length) return false;
  final (short, long) = a.length < b.length ? (a, b) : (b, a);
  return long.startsWith(short) &&
      _anyWordFormEnding.contains(long.substring(short.length));
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
List<_FuzzyCandidate> _resolveOverlaps(
  List<_FuzzyCandidate> candidates, {
  bool preferRuleOrder = false,
}) {
  final sorted = [...candidates]
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore == 0 && preferRuleOrder) {
        final byRule = a.ruleIndex.compareTo(b.ruleIndex);
        if (byRule != 0) return byRule;
      }
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

/// Applies exact-mode [rules] to [text] as a cascade (see
/// [CompiledTextReplacements.applyExactOnly]). When [hits] is
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
  bool cascade = true,
}) => CompiledTextReplacements(rules).apply(text, hits: hits, cascade: cascade);

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
