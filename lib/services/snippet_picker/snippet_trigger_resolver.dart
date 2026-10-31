/// Pure routing of a dictation that starts with the Snippet-Picker trigger
/// word (postprocessing-2026, decision M2).
///
/// Three outcomes, decided on the whole transcript only, never mid-dictation:
/// - the transcript is not the trigger word followed by anything → nothing;
/// - the transcript is the trigger word alone → the picker, unfiltered;
/// - the transcript is "`<trigger> <name>`" → the snippet whose title matches
///   [name] unambiguously is inserted directly; otherwise the picker opens
///   pre-filtered by the spoken [name].
library;

import '../../core/utils/string_similarity.dart';
import '../exact_match_normalization.dart' show normalizeForExactMatch;

/// Minimum similarity (0.0..1.0) between the spoken name and a snippet title
/// for a direct insert. Same threshold as the fuzzy text replacements.
const double snippetDirectMinSimilarity = 0.85;

/// Minimum lead (0.0..1.0) of the best title over the runner-up. Below this
/// the name is ambiguous ("Rechnung Mai" vs. "Rechnung Juni" spoken as
/// "Rechnung") and the picker opens instead.
const double snippetDirectMinGap = 0.10;

/// A snippet title as the resolver sees it: id and title only.
typedef SnippetTitleCandidate = ({String id, String title});

/// What a dictation that starts with the trigger word should do.
sealed class SnippetTriggerRoute {
  const SnippetTriggerRoute();
}

/// Not a trigger: the dictation takes the normal pipeline.
final class SnippetTriggerNone extends SnippetTriggerRoute {
  const SnippetTriggerNone();
}

/// Open the picker. [query] is the spoken name to pre-filter by; null when
/// the whole dictation was the trigger word alone.
final class SnippetTriggerPicker extends SnippetTriggerRoute {
  const SnippetTriggerPicker({this.query});

  final String? query;
}

/// Insert the snippet with [snippetId] directly, without the picker.
final class SnippetTriggerDirect extends SnippetTriggerRoute {
  const SnippetTriggerDirect(this.snippetId);

  final String snippetId;
}

/// Folds the German and common Latin diacritics to their base letter, so
/// "Müller" and "Mueller"/"Muller" compare equal. Applied to the comparison
/// only, never to the text that is shown or inserted.
final _foldPattern = RegExp('[äöüßàáâãåçèéêëìíîïñòóôõùúûýÿ]');

const _foldTable = {
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'ß': 'ss',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

String _fold(String s) =>
    s.replaceAllMapped(_foldPattern, (m) => _foldTable[m[0]] ?? m[0]!);

/// Normalized word list of [s] (case, punctuation and spacing folded by
/// [normalizeForExactMatch]); empty when there are no words.
List<String> _words(String s) {
  final normalized = normalizeForExactMatch(s);
  return normalized.isEmpty ? const [] : normalized.split(' ');
}

/// The words of [transcript] that follow the trigger words, or null when
/// the transcript does not begin with the trigger words. An empty [trigger]
/// (feature off) never matches.
List<String>? _wordsAfterTrigger(String trigger, String transcript) {
  final triggerWords = _words(trigger);
  if (triggerWords.isEmpty) return null;
  final spoken = _words(transcript);
  if (spoken.length < triggerWords.length) return null;
  for (var i = 0; i < triggerWords.length; i++) {
    if (_fold(spoken[i]) != _fold(triggerWords[i])) return null;
  }
  return spoken.sublist(triggerWords.length);
}

/// Cheap pre-check: does [transcript] begin with [trigger]? Lets the caller
/// skip the snippet read for ordinary dictations.
bool snippetTriggerPrefixMatches(String trigger, String transcript) =>
    _wordsAfterTrigger(trigger, transcript) != null;

/// Routes [transcript] against [trigger] and the snippet [snippets].
///
/// Direct insert requires BOTH: the best title reaches
/// [snippetDirectMinSimilarity] AND leads the runner-up by at least
/// [snippetDirectMinGap]. A single title has no runner-up and counts as
/// unambiguous. Empty or ambiguous matches, and an empty snippet list, open
/// the picker with the spoken name as its filter.
SnippetTriggerRoute resolveSnippetTrigger({
  required String trigger,
  required String transcript,
  required Iterable<SnippetTitleCandidate> snippets,
}) {
  final rest = _wordsAfterTrigger(trigger, transcript);
  if (rest == null) return const SnippetTriggerNone();
  if (rest.isEmpty) return const SnippetTriggerPicker();

  final spoken = rest.join(' ');
  final foldedSpoken = _fold(spoken);
  String? bestId;
  var best = 0.0;
  var second = 0.0;
  for (final candidate in snippets) {
    final title = _fold(normalizeForExactMatch(candidate.title));
    if (title.isEmpty) continue;
    final score = stringSimilarity(foldedSpoken, title);
    if (bestId == null || score > best) {
      second = best;
      best = score;
      bestId = candidate.id;
    } else if (score > second) {
      second = score;
    }
  }

  if (bestId != null &&
      best >= snippetDirectMinSimilarity &&
      best - second >= snippetDirectMinGap) {
    return SnippetTriggerDirect(bestId);
  }
  return SnippetTriggerPicker(query: spoken);
}
