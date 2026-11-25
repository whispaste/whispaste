/// Orders display names (language names, app names) the way a reader
/// expects in a list, not by raw code unit: case-insensitive and with
/// accented Latin letters sorted under their base letter, so German lists
/// "Dänisch" before "Deutsch" (#1845). Dart has no collation tables; this
/// fold covers the Latin scripts of the app's UI languages. Ties fall back to
/// the raw comparison, so the order stays total and stable.
library;

const Map<String, String> _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
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
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ß': 'ss',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ł': 'l',
  'š': 's',
  'ž': 'z',
  'č': 'c',
  'ř': 'r',
  'ě': 'e',
  'ő': 'o',
  'ű': 'u',
  'ğ': 'g',
  'ı': 'i',
  'ş': 's',
};

String _key(String name) {
  final lower = name.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

/// Comparator for display names; see the library comment.
int compareDisplayNames(String a, String b) {
  final byKey = _key(a).compareTo(_key(b));
  return byKey != 0 ? byKey : a.compareTo(b);
}
