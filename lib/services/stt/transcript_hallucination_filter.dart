/// Whole-transcript filter for phrases whisper.cpp invents on silence.
///
/// On near-silent or non-speech audio the decoder often returns a stock
/// closing line that was common in its training subtitles. The existing
/// bracket-tag strip in the STT notifier removes `[...]` markers only, so
/// these phrases would still be pasted. This filter drops a transcript only
/// when the whole transcript equals one of the phrases after normalisation.
/// Partial matches are kept on purpose: a sentence that happens to contain
/// such a phrase is real dictation.
///
/// [isNonSpeechTranscript] adds the second silence artefact: a transcript
/// that is a single sound annotation in round brackets, such as `(Musik)`.
/// Cloud engines and whisper.cpp both produce these, and the bracket-tag
/// strip leaves round brackets alone because dictated text may use them.
///
/// The list is deliberately short and holds only phrases that are unlikely
/// to be dictated on their own. Ambiguous ones (for example a bare
/// "Vielen Dank.") are excluded, because a false positive would discard a
/// real dictation.
library;

const Set<String> _knownHallucinationPhrases = {
  'thanks for watching',
  'thank you for watching',
  'subtitles by the amara org community',
  'untertitel der amara org community',
  'untertitelung des zdf',
  'untertitel im auftrag des zdf',
  'danke fuers zuschauen',
  'vielen dank fuers zuschauen',
};

/// Whether [text] is, as a whole, one of the known hallucination phrases.
///
/// Comparison ignores case, punctuation and surrounding whitespace. Umlauts
/// are matched through their transliterations (`ü` as `ue`, `ß` as `ss`).
bool isKnownHallucinationPhrase(String text) {
  final normalized = _normalize(text);
  if (normalized.isEmpty) return false;
  return _knownHallucinationPhrases.contains(normalized);
}

String _normalize(String text) {
  final lower = text
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  // Keep letters and digits, turn everything else into a single space.
  return lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Sound annotations a transcript can consist of on silence or noise, in
/// the app's languages. Matched against the bracket content after
/// lower-casing and trimming.
const Set<String> _nonSpeechAnnotations = {
  'musik',
  'music',
  'applaus',
  'applause',
  'lachen',
  'gelächter',
  'laughter',
  'stille',
  'silence',
  'pause',
  'rauschen',
  'noise',
  'husten',
  'cough',
  'música',
  'aplausos',
  'risas',
  'risos',
  'silencio',
  'silêncio',
  'музыка',
  'аплодисменты',
  'смех',
  'тишина',
  'מוזיקה',
  'מחיאות כפיים',
  'צחוק',
  'שקט',
};

/// Whether [text], as a whole, is something the speaker did not say: a
/// known hallucination phrase or one sound annotation in round or square
/// brackets, such as `(Musik)` or `[Applause]`.
///
/// Brackets inside a longer transcript are kept: only a transcript that is
/// nothing but the annotation counts as empty.
bool isNonSpeechTranscript(String text) {
  if (isKnownHallucinationPhrase(text)) return true;
  final match = _lonelyAnnotation.firstMatch(text.trim());
  if (match == null) return false;
  final content = (match.group(1) ?? match.group(2) ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return _nonSpeechAnnotations.contains(content);
}

final _lonelyAnnotation = RegExp(r'^(?:\(([^()]*)\)|\[([^\[\]]*)\])[.!]?$');
