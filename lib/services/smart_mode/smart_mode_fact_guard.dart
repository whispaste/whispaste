/// Fact guard for Smart Mode results (matrix 2.5, "Fakten-Wächter").
///
/// A small local model can silently change a number, a date, a URL, an
/// e-mail address or a proper name while it "cleans up" a dictation. This
/// pure check extracts those protected tokens from the raw input and reports
/// every one that no longer survives into the output. It runs fully offline
/// and has no model dependency, so it works the same for every engine.
library;

import 'dart:async' show Completer, TimeoutException, unawaited;
import 'dart:isolate' show Isolate, ReceivePort, SendPort;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../../core/logging/app_logger.dart';

/// Dictionary targets that are protected as names: at most four space-separated
/// parts, at least one capitalised part, and every other part a lowercase name
/// particle ("van der Berg", "de Gaulle"). Hyphenated parts count as one part.
/// Text snippets such as "Mit freundlichen Grüßen" are not names. A target
/// without any capital ("müller") is not protected.
List<String> dictionaryNameTerms(Iterable<String> targets) => [
  for (final target in targets)
    if (_isNameTarget(target)) target,
];

bool _isNameTarget(String target) {
  final parts = target.trim().split(_whitespace);
  if (parts.length > 4) return false;
  var hasCapital = false;
  for (final part in parts) {
    if (_upperAny.hasMatch(part)) {
      hasCapital = true;
    } else if (!_nameParticles.contains(part)) {
      return false;
    }
  }
  return hasCapital;
}

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _upperAny = RegExp(r'\p{Lu}', unicode: true);

/// Lowercase particles that may stand inside a name ("van der Berg").
const _nameParticles = <String>{
  'von',
  'van',
  'der',
  'den',
  'de',
  'del',
  'della',
  'di',
  'da',
  'du',
  'la',
  'le',
  'ten',
  'ter',
  'zu',
  'af',
  'al',
  'bin',
  'ibn',
  'y',
  'e',
};

/// Whether single capitalised words count as names for [languageCode]: every
/// language but German. "auto" means German rules, the same default as the
/// pipeline uses when no language was detected (DEV-83).
bool singleWordsAreNamesFor(String languageCode) {
  final code = languageCode.toLowerCase();
  return code != 'auto' && !code.startsWith('de');
}

/// Language that decides the name rule (DEV-83, DEV-107): the configured
/// language wins, then the language the engine detected, then German.
String factGuardLanguage({required String configured, String? detected}) {
  if (configured.isNotEmpty && configured.toLowerCase() != 'auto') {
    return configured;
  }
  if (detected != null && detected.isNotEmpty) return detected;
  return 'de';
}

/// Kind of protected token that went missing.
enum SmartModeFactKind { number, date, url, email, name }

/// One protected token from the input that does not survive into the output.
class SmartModeFactViolation {
  const SmartModeFactViolation({required this.kind, required this.token});

  final SmartModeFactKind kind;

  /// The token as it appeared in the input.
  final String token;

  @override
  bool operator ==(Object other) =>
      other is SmartModeFactViolation &&
      other.kind == kind &&
      other.token == token;

  @override
  int get hashCode => Object.hash(kind, token);

  @override
  String toString() => 'SmartModeFactViolation(${kind.name}: $token)';
}

final RegExp _urlPattern = RegExp(
  r'(?:https?://|www\.)[^\s]*[^\s.,;:!?)\]"'
  "'"
  r'»]',
  caseSensitive: false,
);

/// RFC 5321/1035 length bounds (local part 64, domain label 63). The bounds
/// keep the scan linear: an unbounded run of name characters made every start
/// position scan to the end of the text (GS-032). Full-width `＠` and `．`
/// count as separators, so the injected variants are caught too.
final RegExp _emailPattern = RegExp(
  r'[\p{L}\p{N}_.+-]{1,64}[@＠][\p{L}\p{N}_-]{1,63}(?:[.．][\p{L}\p{N}_-]{1,63})+',
  unicode: true,
);
final RegExp _datePattern = RegExp(r'\b\d{1,4}[./-]\d{1,2}[./-]\d{1,4}\b');
final RegExp _numberPattern = RegExp(r'\p{Nd}+(?:[.,]\p{Nd}+)*', unicode: true);
final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// The deviations of a free instruction that the instruction does not name
/// (GS-030, BIZ-31). Every [missing] token (in the selection, not in the
/// result) and every [added] token (in the result, not in the selection) must
/// appear in the instruction on its own. One named token never explains
/// another one. "Named" is a whole-token, case-insensitive match, so "3" does
/// not name "13" or "30".
List<SmartModeFactViolation> smartModeUnexplainedViolations({
  required List<SmartModeFactViolation> missing,
  required List<SmartModeFactViolation> added,
  required String instruction,
}) {
  final named = instruction.toLowerCase();
  return [
    for (final violation in [...missing, ...added])
      if (!_containsWhole(named, violation.token.toLowerCase())) violation,
  ];
}

/// Returns every protected token of [input] that is missing from [output].
///
/// - Numbers, dates, URLs and e-mail addresses are matched as whole tokens
///   (`2` is not satisfied by `2026`). They are masked out in that order, so
///   their digits are not reported a second time as separate numbers.
/// - Names (only when [checkNames] is true) are words that are part of a run
///   of at least two capitalised words (`Anna Schmidt`), or that contain a
///   digit, an inner capital (`iPhone`) or are an all-caps acronym (`SAP`).
///   A single capitalised word is not a name, so German nouns that are
///   inflected in the output ("Termin" to "Termine") do not trigger a
///   fallback.
/// - [knownTerms] (dictionary entries) are always checked, wherever they
///   occur in the input and whether or not names are checked.
///
/// A name counts as kept when the output contains a word with the same stem:
/// a common prefix of at least `max(4, length - 3)` characters, ignoring case.
///
/// [onStep] is a test seam for the linearity check (DEV-84): it is called once
/// per output token indexed, per name examined and per token visited.
List<SmartModeFactViolation> smartModeFactViolations({
  required String input,
  required String output,
  required bool checkNames,
  Iterable<String> knownTerms = const <String>[],
  bool singleCapitalisedWordsAreNames = false,
  @visibleForTesting void Function()? onStep,
}) {
  final violations = <SmartModeFactViolation>[];
  final seen = <SmartModeFactViolation>{};

  void report(SmartModeFactKind kind, String token) {
    final violation = SmartModeFactViolation(kind: kind, token: token);
    if (seen.add(violation)) violations.add(violation);
  }

  final outputWords = _wordPattern
      .allMatches(output)
      .map((m) => m.group(0)!.toLowerCase())
      .toList();
  final index = _OutputIndex(outputWords, onStep);

  // Repeated tokens (the same date in a long dictation) are searched once.
  final presentInOutput = <String, bool>{};
  void checkExact(SmartModeFactKind kind, String token) {
    final present = presentInOutput.putIfAbsent(
      token,
      () => _containsWhole(output, token),
    );
    if (!present) report(kind, token);
  }

  var masked = input;
  for (final match in _urlPattern.allMatches(input)) {
    checkExact(SmartModeFactKind.url, match.group(0)!);
  }
  masked = masked.replaceAllMapped(_urlPattern, _blank);

  final emails = _emailRanges(masked);
  for (final (start, end) in emails) {
    checkExact(SmartModeFactKind.email, masked.substring(start, end));
  }
  masked = _blankRanges(masked, emails);

  for (final match in _datePattern.allMatches(masked)) {
    checkExact(SmartModeFactKind.date, match.group(0)!);
  }
  masked = masked.replaceAllMapped(_datePattern, _blank);

  for (final match in _numberPattern.allMatches(masked)) {
    checkExact(SmartModeFactKind.number, match.group(0)!);
  }

  if (checkNames) {
    final rules = _NameRules(
      singleWords: singleCapitalisedWordsAreNames,
      acronyms: !_mostlyUppercase(input),
    );
    // Long dictations repeat names; each distinct name is matched once.
    final kept = <String, bool>{};
    for (final word in _nameWords(masked, rules, onStep)) {
      final ok = kept.putIfAbsent(word.toLowerCase(), () => index.keeps(word));
      if (!ok) report(SmartModeFactKind.name, word);
    }
  }

  for (final term in knownTerms) {
    if (term.trim().isEmpty || !_containsWhole(masked, term)) continue;
    final words = _wordPattern.allMatches(term).map((m) => m.group(0)!);
    if (words.any((w) => !index.keeps(w))) {
      report(SmartModeFactKind.name, term);
    }
  }

  return violations;
}

/// Which name rules apply to one check (see [smartModeFactViolations]).
class _NameRules {
  const _NameRules({required this.singleWords, required this.acronyms});

  /// Single capitalised words mid-sentence count as names (non-German).
  final bool singleWords;

  /// All-caps words count as names (off for dictations that are mostly caps).
  final bool acronyms;
}

/// Honorifics are not part of a name run ("Frau Schmidt" names Schmidt only).
const _honorifics = <String>{
  'frau',
  'herr',
  'fr',
  'hr',
  'dr',
  'prof',
  'mr',
  'mrs',
  'ms',
  'miss',
  'mx',
  'sr',
  'sra',
  'sig',
  'm',
  'mme',
  'mlle',
};

/// Name words of [text] (already masked): capitalised words in a run of at
/// least two, single capitalised words when [rules] allow it, plus strong
/// names (digits, inner capitals, acronyms). Linear in the text length.
Iterable<String> _nameWords(
  String text,
  _NameRules rules,
  void Function()? onStep,
) sync* {
  final matches = _wordPattern.allMatches(text).toList();
  // A run partner is capitalised, not the first word of a sentence (a
  // sentence-initial capital is grammar) and not an honorific.
  final partner = [
    for (final match in matches)
      _isCapitalised(match.group(0)!) &&
          !(!rules.acronyms && _isAllCaps(match.group(0)!)) &&
          !_honorifics.contains(match.group(0)!.toLowerCase()) &&
          !_startsSentence(text, match.start),
  ];
  for (var i = 0; i < matches.length; i++) {
    onStep?.call();
    final word = matches[i].group(0)!;
    if (_isStrongName(word, rules.acronyms)) {
      yield word;
      continue;
    }
    if (_followsHonorific(text, matches, i) && _isCapitalised(word)) {
      yield word;
      continue;
    }
    if (!partner[i]) continue;
    if (rules.singleWords) {
      yield word;
      continue;
    }
    final partnerBefore =
        i > 0 &&
        partner[i - 1] &&
        _isOnlySpace(text, matches[i - 1].end, matches[i].start);
    final partnerAfter =
        i + 1 < matches.length &&
        partner[i + 1] &&
        _isOnlySpace(text, matches[i].end, matches[i + 1].start);
    if (partnerBefore || partnerAfter) yield word;
  }
}

/// Whether word [i] directly follows an honorific ("Frau Schmidt", "Dr. Müller"):
/// only spaces, or one dot and spaces, between them.
bool _followsHonorific(String text, List<RegExpMatch> matches, int i) {
  if (i == 0) return false;
  final previous = matches[i - 1];
  if (!_honorifics.contains(previous.group(0)!.toLowerCase())) return false;
  var from = previous.end;
  if (from < matches[i].start && text[from] == '.') from++;
  return _isOnlySpace(text, from, matches[i].start);
}

/// Whether the word at [start] begins a sentence: the text starts there, a
/// newline directly precedes it, or a sentence end and a space precede it.
/// Scans backwards over the preceding whitespace only (no substring copies).
bool _startsSentence(String text, int start) {
  if (start == 0) return true;
  if (text.codeUnitAt(start - 1) == _newline) return true;
  var i = start - 1;
  var sawSpace = false;
  while (i >= 0 && _isSpaceUnit(text.codeUnitAt(i))) {
    sawSpace = true;
    i--;
  }
  if (i < 0) return true;
  return sawSpace && _sentenceEnd.contains(text[i]);
}

const _newline = 0x0A;
const _sentenceEnd = '.!?';
final RegExp _spaceUnit = RegExp(r'\s');

bool _isSpaceUnit(int unit) => _spaceUnit.hasMatch(String.fromCharCode(unit));

/// Gap between two name words: only spaces, no sentence end or newline.
bool _isOnlySpace(String text, int from, int to) {
  if (to < from) return false;
  for (var i = from; i < to; i++) {
    final unit = text.codeUnitAt(i);
    if (!_isSpaceUnit(unit) || unit == _newline) return false;
    if (_sentenceEnd.contains(text[i])) return false;
  }
  return true;
}

/// Whether most letters of [text] are upper case (over 60 %). Such a dictation
/// is shouted or typed in caps, so all-caps words are no evidence of a name.
bool _mostlyUppercase(String text) {
  var letters = 0;
  var upper = 0;
  for (final match in _letter.allMatches(text)) {
    letters++;
    if (_upperLetter.hasMatch(match.group(0)!)) upper++;
  }
  return letters > 0 && upper * 10 > letters * 6;
}

final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _upperLetter = RegExp(r'^\p{Lu}$', unicode: true);

bool _isStrongName(String word, bool acronyms) {
  final letters = word.replaceAll(RegExp(r'\d'), '');
  final hasDigit = letters.length != word.length;
  if (hasDigit && letters.isNotEmpty) return true;
  if (_isAllCaps(word)) return acronyms;
  return _hasInnerCapital(word);
}

bool _hasLetter(String word) => RegExp(r'\p{L}', unicode: true).hasMatch(word);

/// All-caps word with at least two letters (an acronym or a shouted word).
bool _isAllCaps(String word) =>
    word.length >= 2 && word == word.toUpperCase() && _hasLetter(word);

bool _isCapitalised(String word) =>
    RegExp(r'^\p{Lu}', unicode: true).hasMatch(word);

bool _hasInnerCapital(String word) =>
    RegExp(r'\p{Lu}', unicode: true).allMatches(word.substring(1)).isNotEmpty;

/// Output words indexed under each of their first one to four letters, so a
/// name is compared only with words that share its first letters (GS-018).
class _OutputIndex {
  _OutputIndex(List<String> lowerWords, this._onStep) {
    for (final word in lowerWords) {
      _onStep?.call();
      final longest = word.length < _indexPrefix ? word.length : _indexPrefix;
      for (var n = 1; n <= longest; n++) {
        _buckets.putIfAbsent(word.substring(0, n), () => []).add(word);
      }
    }
  }

  static const _indexPrefix = 4;
  final _buckets = <String, List<String>>{};
  final void Function()? _onStep;

  /// Whether the output holds a word with the same stem as [name].
  bool keeps(String name) {
    final lowerName = name.toLowerCase();
    final stem = _stemLength(lowerName.length);
    final key = lowerName.length < _indexPrefix
        ? lowerName
        : lowerName.substring(0, _indexPrefix);
    for (final word in _buckets[key] ?? const <String>[]) {
      _onStep?.call();
      if (word.length - lowerName.length > 2) continue;
      if (_commonPrefixLength(lowerName, word) >= stem) return true;
    }
    return false;
  }
}

/// Stem a name must keep in the output. Names up to five characters match in
/// full ("Julia" is not "Julie"); longer names may differ in their last
/// character only ("Schmidts" keeps "Schmidt", "Schmitt" does not).
int _stemLength(int nameLength) =>
    nameLength <= 5 ? nameLength : nameLength - 1;

int _commonPrefixLength(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < limit && a[i] == b[i]) {
    i++;
  }
  return i;
}

final RegExp _atSign = RegExp('[@＠]');

/// Ranges of the e-mail addresses in [text]. Only the window around each @
/// is matched, so the scan stays linear in the text length (GS-032).
List<(int, int)> _emailRanges(String text) {
  final ranges = <(int, int)>{};
  for (final at in _atSign.allMatches(text)) {
    final windowStart = at.start > 64 ? at.start - 64 : 0;
    final windowEnd = at.end + 320 < text.length ? at.end + 320 : text.length;
    final window = text.substring(windowStart, windowEnd);
    for (final match in _emailPattern.allMatches(window)) {
      final start = windowStart + match.start;
      final end = windowStart + match.end;
      if (start <= at.start && at.start < end) ranges.add((start, end));
    }
  }
  return ranges.toList()..sort((a, b) => a.$1.compareTo(b.$1));
}

/// Blanks [ranges] in [text]. Overlapping or adjacent windows are merged
/// first, so every range starts at or after the end of the previous one
/// (DEV-141, GS-034).
String _blankRanges(String text, List<(int, int)> ranges) {
  if (ranges.isEmpty) return text;
  final sorted = [...ranges]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final (start, end) in sorted) {
    if (merged.isNotEmpty && start <= merged.last.$2) {
      final previous = merged.removeLast();
      merged.add((previous.$1, end > previous.$2 ? end : previous.$2));
    } else {
      merged.add((start, end));
    }
  }
  final buffer = StringBuffer();
  var last = 0;
  for (final (start, end) in merged) {
    buffer
      ..write(text.substring(last, start))
      ..write(' ' * (end - start));
    last = end;
  }
  buffer.write(text.substring(last));
  return buffer.toString();
}

String _blank(Match match) => ' ' * match.group(0)!.length;

/// Whole-token containment: [token] must not be a fragment of a longer
/// letter or digit run in [text].
bool _containsWhole(String text, String token) {
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(token)}(?![\\p{L}\\p{N}])',
    unicode: true,
  );
  return pattern.hasMatch(text);
}

final _guardLog = AppLogger('SmartModeFactGuard');

/// Test seam: replaces the guard so a test can make it throw and check the
/// fail-closed paths. Null in production.
@visibleForTesting
List<SmartModeFactViolation> Function({
  required String input,
  required String output,
  required bool checkNames,
  required List<String> knownTerms,
  required bool singleCapitalisedWordsAreNames,
})?
debugSmartModeFactGuardOverride;

/// Inputs (selection plus output, in UTF-16 units) above which the guard runs
/// in a background isolate, so a long text cannot freeze the UI (GS-032).
const int smartModeFactGuardIsolateThreshold = 20000;

/// Test seam for the guard isolates; null runs them with [Isolate.run].
@visibleForTesting
Future<T> Function<T>(T Function() computation)? debugGuardIsolateRunner;

bool _guardIsolateInFlight = false;

/// Whether a guard isolate is still alive (test visibility, GS-045 remainder).
@visibleForTesting
bool get debugGuardIsolateInFlight => _guardIsolateInFlight;

/// Runs [computation] in a background isolate with at most one such isolate
/// alive (GS-045 remainder). On timeout the isolate is killed immediately, so
/// a hung guard cannot pile up. A call that arrives while an earlier isolate
/// is still alive fails at once with a [TimeoutException] (fail-closed)
/// instead of starting another one. The slot frees when the isolate exits.
Future<T> runGuardIsolate<T>(T Function() computation, Duration timeout) {
  if (_guardIsolateInFlight) {
    return Future<T>.error(
      TimeoutException('previous guard isolate still running'),
    );
  }
  _guardIsolateInFlight = true;
  final seam = debugGuardIsolateRunner;
  if (seam != null) {
    final run = seam<T>(computation);
    unawaited(
      run.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _guardIsolateInFlight = false;
      }),
    );
    return run.timeout(timeout);
  }
  return _spawnGuardIsolate<T>(computation, timeout);
}

/// Entry point of a guard isolate: sends the result and exits.
void _runGuardComputation<T>((T Function(), SendPort) message) {
  Isolate.exit(message.$2, message.$1());
}

Future<T> _spawnGuardIsolate<T>(
  T Function() computation,
  Duration timeout,
) async {
  final result = ReceivePort();
  final errors = ReceivePort();
  final exit = ReceivePort();
  final done = Completer<T>();
  result.listen((value) {
    if (!done.isCompleted) done.complete(value as T);
  });
  errors.listen((_) {
    if (!done.isCompleted) {
      done.completeError(StateError('guard isolate failed'));
    }
  });
  exit.listen((_) {
    _guardIsolateInFlight = false;
    result.close();
    errors.close();
    exit.close();
  });
  final Isolate isolate;
  try {
    isolate = await Isolate.spawn<(T Function(), SendPort)>(
      _runGuardComputation<T>,
      (computation, result.sendPort),
      onExit: exit.sendPort,
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
  } on Object {
    _guardIsolateInFlight = false;
    result.close();
    errors.close();
    exit.close();
    rethrow;
  }
  _guardIsolateInFlight = true;
  try {
    return await done.future.timeout(timeout);
  } on TimeoutException {
    isolate.kill(priority: Isolate.immediate);
    rethrow;
  }
}

/// Longest wait for an isolate result before the caller treats it as a
/// failure (GS-032, GS-045). Shared by the fact guard and the name diff, so a
/// hung isolate can never hold up an insert for longer than this.
const Duration smartModeIsolateTimeout = Duration(seconds: 3);

/// Why [checkSmartModeFacts] gave no answer.
enum SmartModeGuardFailure {
  /// The guard threw. The text is not judged; callers fail closed.
  error,

  /// The isolate did not answer within the timeout (GS-045). Reported on its
  /// own, so a slow check is not mistaken for a changed fact (DEV-151).
  timedOut,
}

/// Result of [checkSmartModeFacts]: the violations, or the reason there are
/// none to report.
@immutable
class SmartModeFactCheck {
  const SmartModeFactCheck.checked(this.violations) : failure = null;

  const SmartModeFactCheck.failed(SmartModeGuardFailure reason)
    : violations = null,
      failure = reason;

  /// Null when the check did not run to the end ([failure] says why).
  final List<SmartModeFactViolation>? violations;
  final SmartModeGuardFailure? failure;
}

/// [smartModeFactViolations] for callers that must fail closed. Long inputs
/// run off the main isolate. A throw gives [SmartModeGuardFailure.error], a
/// timeout [SmartModeGuardFailure.timedOut]; only the exception's class is
/// logged, never the text (DEV-141, GS-034).
Future<SmartModeFactCheck> checkSmartModeFacts({
  required String input,
  required String output,
  required bool checkNames,
  required List<String> knownTerms,
  required bool singleCapitalisedWordsAreNames,
  Duration timeout = smartModeIsolateTimeout,
}) async {
  try {
    if (input.length + output.length > smartModeFactGuardIsolateThreshold &&
        debugSmartModeFactGuardOverride == null) {
      // The isolate gets the same timeout as the name diff (GS-032 remainder).
      final violations = await runGuardIsolate(
        () => smartModeFactViolations(
          input: input,
          output: output,
          checkNames: checkNames,
          knownTerms: knownTerms,
          singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
        ),
        timeout,
      );
      return SmartModeFactCheck.checked(violations);
    }
    final check = debugSmartModeFactGuardOverride ?? smartModeFactViolations;
    return SmartModeFactCheck.checked(
      check(
        input: input,
        output: output,
        checkNames: checkNames,
        knownTerms: knownTerms,
        singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
      ),
    );
  } on TimeoutException {
    _guardLog.warning('Fact guard timed out after $timeout');
    return const SmartModeFactCheck.failed(SmartModeGuardFailure.timedOut);
  } catch (error) {
    _guardLog.warning('Fact guard failed (${error.runtimeType})');
    return const SmartModeFactCheck.failed(SmartModeGuardFailure.error);
  }
}

/// Name words the guard sees in [text], with the same rules as the blocking
/// check. Report-only: the name-change summary of a free instruction (2c).
List<String> smartModeNameWords(
  String text, {
  required bool singleCapitalisedWordsAreNames,
}) {
  final rules = _NameRules(
    singleWords: singleCapitalisedWordsAreNames,
    acronyms: !_mostlyUppercase(text),
  );
  return _nameWords(text, rules, null).toList();
}
