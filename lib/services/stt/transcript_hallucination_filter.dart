/// Filter for text a speech engine invents on silence (#2013).
///
/// On near-silent or non-speech audio the decoder often returns a stock line
/// that was common in its training subtitles ("Untertitel im Auftrag des
/// ZDF", "Thanks for watching") or a short filler ("Ähm.", "Mhm."). This
/// happens for a whole silent recording and, just as often, for the silent
/// stretch at the end of a dictation, after the last real sentence.
///
/// Three tiers decide how much evidence a phrase needs:
///
/// - [isNonSpeechTranscript]: a lone sound annotation such as `(Musik)`
///   is dropped without any further signal, for every engine.
/// - [dropInventedText] with a [SilenceSignal]: the longer per-language list
///   ([_stockPhrases], [_stockPrefixes]) and the fillers ([_fillers]). They
///   are removed as the whole transcript or as the last sentences of a
///   longer one, but only when a silence signal says nobody spoke there. A
///   real sentence that happens to read like a stock phrase stays, because
///   without the signal the filter does nothing.
/// - Ambiguous short words that people also dictate on their own ("Vielen
///   Dank.", "Okay.", "Amen."): only a transcript that is nothing else, and
///   only with strong evidence ([SilenceSignal.strong]: the engine's own
///   no-speech probability or a recording without any voice level).
///
/// Comparison ignores case, punctuation, apostrophes and surrounding
/// whitespace; German umlauts match their transliterations (`ü` as `ue`,
/// `ß` as `ss`), other accents their base letter.
///
/// Pure Dart: no Flutter import, so the corpus test and tools run anywhere.
library;

/// whisper's own no-speech probability from which a segment counts as
/// silence. The reference implementation uses the same 0.6. whisper.cpp
/// v1.9.5 reads it at the wrong position and reports ~0 (#1742,
/// `internal-notes`), so today this signal never
/// fires; it takes effect as soon as a library computes it correctly, and
/// cloud or other engines can pass their own value.
const double kNoSpeechProbSilence = 0.6;

/// The weakest of the last text tokens below this counts as a low end
/// confidence: the decoder was unsure about the tail it produced. The most
/// lenient candidate rule of the shadow protocol (`kTailRules`); here it
/// only ever removes a listed phrase, never arbitrary text.
const double kLowTailConfidence = 0.40;

/// A filler at the end counts as invented when at least this much silence
/// follows the last voiced frame of the recording.
const int kSilentTailMs = 1000;

/// What the engine and the audio say about silence in one transcription.
///
/// All fields are optional; [SilenceSignal.none] carries no evidence and
/// leaves all spoken phrases intact; only sound annotations are removed.
class SilenceSignal {
  const SilenceSignal({
    this.noSpeechProb,
    this.tailMinP,
    this.silentAudio = false,
    this.trailingSilenceMs = 0,
  });

  /// No evidence at all.
  static const none = SilenceSignal();

  /// The engine's no-speech probability of the last text segment.
  final double? noSpeechProb;

  /// Lowest probability among the last text tokens of the transcript.
  final double? tailMinP;

  /// The recording holds no frame at voice level at all.
  final bool silentAudio;

  /// Silence after the last frame above the pause level, in milliseconds.
  final int trailingSilenceMs;

  bool get _engineSilence =>
      (noSpeechProb ?? 0) >= kNoSpeechProbSilence ||
      (tailMinP != null && tailMinP! < kLowTailConfidence);

  /// Strong evidence that nothing was said: the engine reports silence by
  /// its no-speech probability, or the audio never reached voice level.
  bool get strong => (noSpeechProb ?? 0) >= kNoSpeechProbSilence || silentAudio;

  /// Evidence that the end of the transcript was not spoken: strong
  /// evidence or a low end confidence. Enough for stock phrases.
  bool get tailNotSpoken => strong || _engineSilence;

  /// Evidence enough for a filler at the end: [tailNotSpoken] or a silent
  /// stretch of at least [kSilentTailMs] after the last voice.
  bool get fillerNotSpoken =>
      tailNotSpoken || trailingSilenceMs >= kSilentTailMs;

  /// Combines two signals of the same transcription (engine and audio):
  /// each field takes the stronger of both values.
  SilenceSignal merge(SilenceSignal other) => SilenceSignal(
    noSpeechProb: _max(noSpeechProb, other.noSpeechProb),
    tailMinP: _min(tailMinP, other.tailMinP),
    silentAudio: silentAudio || other.silentAudio,
    trailingSilenceMs: trailingSilenceMs > other.trailingSilenceMs
        ? trailingSilenceMs
        : other.trailingSilenceMs,
  );

  static double? _max(double? a, double? b) =>
      a == null ? b : (b == null || a >= b ? a : b);
  static double? _min(double? a, double? b) =>
      a == null ? b : (b == null || a <= b ? a : b);

  @override
  String toString() =>
      'SilenceSignal(noSpeech=$noSpeechProb, tailMinP=$tailMinP, '
      'silentAudio=$silentAudio, trailingSilenceMs=$trailingSilenceMs)';
}

/// Original phrase list. Like the extended list, these need silence
/// evidence: people may intentionally dictate any of these lines.
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

/// Stock lines from video subtitles, per language, in normalised form. Only
/// removed with a silence signal ([SilenceSignal.tailNotSpoken]).
const Set<String> _stockPhrases = {
  // de
  'untertitel im auftrag des zdf fuer funk',
  'untertitelung im auftrag des zdf',
  'untertitel im auftrag des zdf fuer funk 2017',
  'danke schoen fuers zuschauen',
  'danke fuer das zuschauen',
  'vielen dank fuer das zuschauen',
  'vielen dank fuers zusehen',
  'danke fuers zusehen',
  'vielen dank fuer ihre aufmerksamkeit',
  'bis zum naechsten mal',
  'bis zum naechsten video',
  'wir sehen uns im naechsten video',
  'abonniert den kanal',
  'abonniere den kanal',
  // en
  'thank you so much for watching',
  'thank you very much for watching',
  'thanks for watching see you next time',
  'thank you for watching and see you next time',
  'please subscribe',
  'please subscribe to my channel',
  'please like and subscribe',
  'like and subscribe',
  'dont forget to like and subscribe',
  'see you in the next video',
  'see you next time',
  // es
  'gracias por ver',
  'gracias por ver el video',
  'muchas gracias por ver',
  'muchas gracias por ver el video',
  'gracias por mirar',
  'subtitulos realizados por la comunidad de amara org',
  'suscribete al canal',
  'no olvides suscribirte',
  'nos vemos en el proximo video',
  // fr
  'merci davoir regarde',
  'merci davoir regarde cette video',
  'merci beaucoup davoir regarde',
  'sous titres realises par la communaute damara org',
  'abonnez vous',
  'abonnez vous a la chaine',
  'a bientot pour une nouvelle video',
  // it
  'grazie per la visione',
  'grazie per aver guardato',
  'grazie a tutti per la visione',
  'sottotitoli creati dalla comunita amara org',
  'iscriviti al canale',
  'ci vediamo nel prossimo video',
  // pt
  'obrigado por assistir',
  'obrigada por assistir',
  'muito obrigado por assistir',
  'legendas pela comunidade amara org',
  'inscreva se no canal',
  'ate o proximo video',
  // ru
  'спасибо за просмотр',
  'продолжение следует',
  'подписывайтесь на канал',
  'субтитры подготовлены сообществом amara org',
  // zh
  '谢谢观看',
  '感谢观看',
  '谢谢大家观看',
  '字幕由amara org社区提供',
  '请不吝点赞 订阅 转发 打赏支持明镜与点点栏目',
  '订阅我的频道',
  // he
  'תודה שצפיתם',
  'תודה רבה שצפיתם',
  'תודה על הצפייה',
};

/// Credit lines whose end varies (a name, a year, a station). A sentence
/// matches when it starts with one of these and has at most
/// [_maxPrefixedWords] words. Silence signal required as for [_stockPhrases].
const List<String> _stockPrefixes = [
  'untertitel von ',
  'untertitel im auftrag des ',
  'untertitelung im auftrag des ',
  'untertitelung des ',
  'untertitel der ',
  'subtitles by ',
  'subtitles made by ',
  'subtitulos por ',
  'subtitulos realizados por ',
  'sous titres realises par ',
  'sous titrage ',
  'sottotitoli a cura di ',
  'sottotitoli creati da ',
  'legendas por ',
  'legendado por ',
  'субтитры сделал ',
  'субтитры создавал ',
  'редактор субтитров ',
  '字幕由',
];

const int _maxPrefixedWords = 10;

/// Short words people dictate on their own as well. Dropped only as the
/// whole transcript and only with [SilenceSignal.strong].
const Set<String> _ambiguousWords = {
  'vielen dank',
  'danke',
  'danke schoen',
  'amen',
  'so',
  'tschuess',
  'thank you',
  'thanks',
  'thank you very much',
  'bye',
  'okay',
  'ok',
  'yeah',
  'yes',
  'you',
  'gracias',
  'merci',
  'grazie',
  'obrigado',
  'obrigada',
  'спасибо',
  '谢谢',
  'תודה',
};

/// Hesitation sounds, the typical Parakeet and whisper fillers on silence.
/// Removed with [SilenceSignal.fillerNotSpoken].
const Set<String> _fillers = {
  'ae',
  'aeh',
  'aehm',
  'oeh',
  'oehm',
  'eh',
  'ehm',
  'euh',
  'uh',
  'uhm',
  'um',
  'umm',
  'erm',
  'ah',
  'uh huh',
  'mm hmm',
  'mhm hm',
  'э',
  'эм',
  'ээ',
  'м',
  'ммм',
  '嗯',
  '呃',
  'אה',
  'אמ',
};

/// `hm`, `hmm`, `mhm`, `mmh`, `mm` and their stretched forms.
final _hummedFiller = RegExp(r'^(?:h+m+|m+h*m+|m+h+)$');

/// Whether [text] is, as a whole, one of the core hallucination phrases.
bool isKnownHallucinationPhrase(String text) {
  final normalized = _normalize(text);
  if (normalized.isEmpty) return false;
  return _knownHallucinationPhrases.contains(normalized);
}

/// Whether [text] is one sound annotation in round or square brackets,
/// such as `(Musik)` or `[Applause]`. Needs no silence signal. Stock
/// phrases are not annotations and require evidence in [dropInventedText].
///
/// Brackets inside a longer transcript are kept: only a transcript that is
/// nothing but the annotation counts as empty.
bool isNonSpeechTranscript(String text) {
  final match = _lonelyAnnotation.firstMatch(text.trim());
  if (match == null) return false;
  final content = (match.group(1) ?? match.group(2) ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return _nonSpeechAnnotations.contains(content);
}

/// Removes what the engine invented on silence from [text] (#2013).
///
/// - A transcript that [isNonSpeechTranscript] matches becomes empty, with
///   or without [signal].
/// - With [SilenceSignal.strong], a transcript that is only an ambiguous
///   short word ("Vielen Dank.") or only punctuation becomes empty.
/// - The last sentences of [text] (or all of it) are removed while each is
///   a stock phrase and [SilenceSignal.tailNotSpoken] holds, or a filler and
///   [SilenceSignal.fillerNotSpoken] holds.
///
/// Everything before the removed sentences is returned unchanged (trailing
/// whitespace trimmed). Without a signal only sound annotations are removed.
String dropInventedText(String text, SilenceSignal signal) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  if (isNonSpeechTranscript(trimmed)) return '';
  if (signal.strong) {
    final whole = _normalize(trimmed);
    if (whole.isEmpty || _ambiguousWords.contains(whole)) return '';
  }
  if (!signal.fillerNotSpoken) return trimmed;

  var rest = trimmed;
  while (rest.isNotEmpty) {
    final start = _lastSentenceStart(rest);
    final sentence = _normalize(rest.substring(start));
    final invented =
        (signal.tailNotSpoken && _isStockSentence(sentence)) ||
        _isFiller(sentence);
    if (!invented) break;
    rest = rest.substring(0, start).trimRight();
  }
  return rest;
}

/// Whether [normalized] is a stock phrase of any tier but the ambiguous one.
bool _isStockSentence(String normalized) {
  if (normalized.isEmpty) return false;
  if (_knownHallucinationPhrases.contains(normalized)) return true;
  if (_stockPhrases.contains(normalized)) return true;
  for (final prefix in _stockPrefixes) {
    if (normalized.startsWith(prefix) &&
        normalized.split(' ').length <= _maxPrefixedWords) {
      return true;
    }
  }
  return false;
}

/// Whether [normalized] consists of filler sounds only ("Äh, ähm.").
bool _isFiller(String normalized) {
  if (normalized.isEmpty) return false;
  if (_fillers.contains(normalized)) return true;
  return normalized
      .split(' ')
      .every((w) => _fillers.contains(w) || _hummedFiller.hasMatch(w));
}

/// Sentence ends: `.`, `!`, `?`, `…` before whitespace, and the CJK full
/// stops anywhere. A dot inside a word ("Amara.org") is no sentence end.
const _terminators = '.!?…';
const _cjkTerminators = '。！？';

/// Start index of the last sentence of [s] (trimmed on the right): right
/// after the previous sentence end, past its whitespace.
int _lastSentenceStart(String s) {
  var i = s.length - 1;
  // Skip the terminators of the last sentence itself.
  while (i >= 0 &&
      (_terminators.contains(s[i]) || _cjkTerminators.contains(s[i]))) {
    i--;
  }
  for (; i >= 0; i--) {
    final c = s[i];
    if (_cjkTerminators.contains(c)) break;
    if (_terminators.contains(c) &&
        i + 1 < s.length &&
        s[i + 1].trim().isEmpty) {
      break;
    }
  }
  var start = i + 1;
  while (start < s.length && s[start].trim().isEmpty) {
    start++;
  }
  return start;
}

const Map<String, String> _accents = {
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
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
  'ё': 'е',
};

final _apostrophes = RegExp('[\'’`´]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _normalize(String text) {
  final buf = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final c = String.fromCharCode(rune);
    buf.write(_accents[c] ?? c);
  }
  // Apostrophes join ("fürs", "für's" and "d'avoir" read as one word);
  // every other run of non-letters becomes a single space.
  return buf
      .toString()
      .replaceAll(_apostrophes, '')
      .replaceAll(_nonWord, ' ')
      .trim();
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

final _lonelyAnnotation = RegExp(r'^(?:\(([^()]*)\)|\[([^\[\]]*)\])[.!]?$');
