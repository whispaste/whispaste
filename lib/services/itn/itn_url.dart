/// Web addresses spoken out loud, written in lowercase for the host.
///
/// "www punkt beispiel punkt de" becomes "www.beispiel.de",
/// "beispiel punkt de schrägstrich impressum" becomes "beispiel.de/impressum",
/// "https doppelpunkt schrägstrich schrägstrich example dot com" becomes
/// "https://example.com". The path keeps the spoken case.
///
/// Same caution as [ItnEmail]: the host needs a joined name and a known
/// top-level domain after a spoken dot, so "Punkt" in running text stays a
/// word. Runs after [ItnEmail], so an address is never split here.
library;

import 'dictation_transform.dart';

final class ItnUrl implements DictationTransform {
  const ItnUrl();

  @override
  String get id => 'url';

  static final RegExp _hint = RegExp(
    r'\bwww\b|\bdot\b|\bpunkt\b|schrägstrich|\bslash\b',
    caseSensitive: false,
    unicode: true,
  );

  static const _joiner = r'(?:punkt|dot)';
  static const _slash = r'(?:schrägstrich|slash)';
  static const _label = r'[\p{L}\p{N}]+';
  static const _tld = r'(?:com|de|org|net|eu|io|ch|at|co|info|dev|uk)';

  /// Optional scheme ("https doppelpunkt schrägstrich schrägstrich"), optional
  /// "www", host labels ending in a known top-level domain, and optional path
  /// segments ("schrägstrich impressum").
  static final RegExp _pattern = RegExp(
    r'(?<![\p{L}\p{N}@])'
    '(?:(https?)\\s+(?:doppelpunkt|colon)\\s+$_slash\\s+$_slash\\s+)?'
    '(?:(www|w\\s+w\\s+w)\\s+$_joiner\\s+)?'
    '($_label(?:\\s+$_joiner\\s+$_label)*)'
    '\\s+$_joiner\\s+($_tld)(?![\\p{L}\\p{N}])'
    '((?:\\s+$_slash\\s+$_label)*)',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _slashWord = RegExp(
    r'\s+(?:schrägstrich|slash)\s+',
    caseSensitive: false,
    unicode: true,
  );

  @override
  String apply(String text, TransformContext ctx) {
    if (!_hint.hasMatch(text)) return text;
    return text.replaceAllMapped(_pattern, (m) {
      // Groups: 1 scheme, 2 "www", 3 host labels, 4 top-level domain, 5 path.
      final host = m[3]!;
      if (host
          .split(_space)
          .any((word) => labelStopWords.contains(word.toLowerCase()))) {
        return m[0]!;
      }
      final scheme = m[1];
      final www = m[2] != null;
      final labels = host
          .split(_space)
          .where((word) => word.toLowerCase() != 'punkt')
          .where((word) => word.toLowerCase() != 'dot')
          .map((word) => word.toLowerCase())
          .join('.');
      final path = (m[5] ?? '').replaceAllMapped(_slashWord, (_) => '/');
      final buffer = StringBuffer();
      if (scheme != null) buffer.write('${scheme.toLowerCase()}://');
      if (www) buffer.write('www.');
      buffer
        ..write(labels)
        ..write('.')
        ..write(m[4]!.toLowerCase())
        ..write(path);
      return buffer.toString();
    });
  }
}
