/// E-mail addresses spoken out loud, written in lowercase.
///
/// "max punkt mustermann at gmail punkt com" becomes
/// "max.mustermann@gmail.com", and "john at gmail dot com" becomes
/// "john@gmail.com". Both languages share the markers, because a German
/// dictation often contains an English address.
///
/// Conservative by design:
/// - The domain must end in a known top-level domain after a spoken dot.
///   "at" alone, or "at" followed by a plain word, stays text.
/// - The local part needs a joined name ("max punkt mustermann") or a single
///   word right before "at". Articles and prepositions never join it
///   ("an max at gmx punkt de" keeps "an").
/// - Markers: "at" / "at sign" / "klammeraffe" (the sign), "punkt" / "dot"
///   (the dot), "unterstrich" / "underscore" (the underscore).
///
/// Runs first in the chain, so the domain of an address is never read as a
/// web address by [ItnUrl].
library;

import 'dictation_transform.dart';

final class ItnEmail implements DictationTransform {
  const ItnEmail();

  @override
  String get id => 'email';

  /// Cheap pre-check: without a marker no pattern runs.
  static final RegExp _hint = RegExp(
    r'\bat\b|klammeraffe|\bdot\b|\bpunkt\b',
    caseSensitive: false,
    unicode: true,
  );

  static const _joiner = r'(?:punkt|dot|unterstrich|underscore)';
  static const _label = r'[\p{L}\p{N}]+';
  static const _tld = r'(?:com|de|org|net|eu|io|ch|at|co|info|dev|uk)';

  /// Local part (one or more joined names), the "at" marker, the domain
  /// (one or more labels), the dot marker and the top-level domain.
  static final RegExp _pattern = RegExp(
    r'(?<![\p{L}\p{N}])'
    '((?:$_label\\s+$_joiner\\s+)*$_label)'
    r'\s+(?:at(?:\s+sign)?|klammeraffe)\s+'
    '($_label(?:\\s+$_joiner\\s+$_label)*)'
    '\\s+$_joiner\\s+($_tld)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _space = RegExp(r'\s+');

  @override
  String apply(String text, TransformContext ctx) {
    if (!_hint.hasMatch(text)) return text;
    return text.replaceAllMapped(_pattern, (m) {
      final local = m[1]!;
      final domain = m[2]!;
      final tld = m[3]!.toLowerCase();
      if (_hasStopWord(local) || _hasStopWord(domain)) return m[0]!;
      return '${_written(local)}@${_written(domain)}.$tld';
    });
  }

  bool _hasStopWord(String phrase) => phrase
      .split(_space)
      .any((word) => labelStopWords.contains(word.toLowerCase()));

  /// Joins a spoken name chain: words stay, "punkt"/"dot" become ".",
  /// "unterstrich"/"underscore" become "_". Lowercased.
  static String _written(String phrase) {
    final words = <String>[];
    final separators = <String>[];
    for (final token in phrase.split(_space)) {
      final lower = token.toLowerCase();
      if (lower == 'punkt' || lower == 'dot') {
        separators.add('.');
      } else if (lower == 'unterstrich' || lower == 'underscore') {
        separators.add('_');
      } else {
        words.add(lower);
      }
    }
    final out = StringBuffer(words.first);
    for (var i = 1; i < words.length; i++) {
      out
        ..write(separators[i - 1])
        ..write(words[i]);
    }
    return out.toString();
  }
}
