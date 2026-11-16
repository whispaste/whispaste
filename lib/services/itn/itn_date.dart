/// Calendar dates spoken as ordinal day and month name, written with digits.
///
/// Output formats (decision, see the library doc of the pipeline):
/// - German: "fünfzehnter März zweitausendsiebenundzwanzig" becomes
///   "15. März 2027"; without a year, "15. März".
/// - English: "March fifteenth, two thousand twenty seven" becomes
///   "March 15, 2027"; without a year, "March 15".
///
/// A month name alone ("im März") and a day alone ("der zehnte") stay text.
/// The day must be an ordinal directly before the month, so "zehn März" or
/// "März 2027" are left as they are. A year that does not read as a year in
/// 1900 to 2099 stays as spoken, so "March fifteenth twenty five" becomes
/// "March 15 twenty five" and never "March 15, 2005".
library;

import 'dictation_transform.dart';
import 'itn_numbers.dart';

final class ItnDate implements DictationTransform {
  const ItnDate();

  @override
  String get id => 'date';

  static final RegExp _hint = RegExp(
    r'januar|februar|märz|april|\bmai\b|juni|juli|august|september|oktober|'
    r'november|dezember|january|february|march|\bmay\b|june|july|october|'
    r'december|\bdecember\b',
    caseSensitive: false,
    unicode: true,
  );

  static const _germanMonths = <String, String>{
    'januar': 'Januar',
    'februar': 'Februar',
    'märz': 'März',
    'april': 'April',
    'mai': 'Mai',
    'juni': 'Juni',
    'juli': 'Juli',
    'august': 'August',
    'september': 'September',
    'oktober': 'Oktober',
    'november': 'November',
    'dezember': 'Dezember',
  };

  static const _englishMonths = <String, String>{
    'january': 'January',
    'february': 'February',
    'march': 'March',
    'april': 'April',
    'may': 'May',
    'june': 'June',
    'july': 'July',
    'august': 'August',
    'september': 'September',
    'october': 'October',
    'november': 'November',
    'december': 'December',
  };

  // Ordinal suffixes, longest first, so "fünfzehnten" is read with "ten".
  static const _germanSuffixes = [
    'sten',
    'ster',
    'stem',
    'stes',
    'ste',
    'ten',
    'ter',
    'tem',
    'tes',
    'te',
  ];

  // Stems that the plain rules do not reach: "erste" becomes "ers", "dritte"
  // becomes "dritt" and "achte" becomes "ach" before the suffix is re-added.
  static const _irregularStems = <String, String>{
    'ers': 'ein',
    'dritt': 'drei',
  };

  static final RegExp _germanDayPattern = RegExp(
    r'(\p{L}+(?:ste|sten|ster|stem|stes|te|ten|ter|tem|tes))\s+('
    r'Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|'
    r'November|Dezember)'
    r'(?:\s+(\d{4}|\p{L}+tausend\p{L}*(?:\s+\p{L}+)?))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _englishDayPattern = RegExp(
    r'(?<![\p{L}\p{N}])(January|February|March|April|May|June|July|August|'
    r'September|October|November|December)\s+'
    '((?:(?:twenty|thirty)[\\s-])?(?:first|second|third|fourth|fifth|sixth|'
    'seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|'
    'fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|'
    'thirtieth))'
    '(?:,?\\s+(\\d{4}|two\\s+thousand(?:\\s+and)?\\s+$enTwoDigitWords|'
    'twenty\\s+$enTwoDigitWords))?'
    r'(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static const _englishOrdinals = <String, int>{
    'first': 1,
    'second': 2,
    'third': 3,
    'fourth': 4,
    'fifth': 5,
    'sixth': 6,
    'seventh': 7,
    'eighth': 8,
    'ninth': 9,
    'tenth': 10,
    'eleventh': 11,
    'twelfth': 12,
    'thirteenth': 13,
    'fourteenth': 14,
    'fifteenth': 15,
    'sixteenth': 16,
    'seventeenth': 17,
    'eighteenth': 18,
    'nineteenth': 19,
    'twentieth': 20,
    'thirtieth': 30,
  };

  @override
  String apply(String text, TransformContext ctx) => applyByLanguage(
    text,
    ctx,
    hint: _hint,
    german: _replaceGermanDays,
    english: _replaceEnglishDays,
  );

  String _replaceGermanDays(String text) =>
      text.replaceAllMapped(_germanDayPattern, _replaceGerman);

  String _replaceEnglishDays(String text) =>
      text.replaceAllMapped(_englishDayPattern, _replaceEnglish);

  String _replaceGerman(Match m) {
    final day = _germanOrdinalDay(m[1]!);
    if (day == null) return m[0]!;
    final month = _germanMonths[m[2]!.toLowerCase()]!;
    final yearText = m[3];
    final head = '$day. $month';
    if (yearText == null) return head;
    // The year is the longest leading run of words that reads as one; words
    // after it ("... zweitausendsiebenundzwanzig ist") go back into the text.
    final words = yearText.split(_space);
    for (var count = words.length; count >= 1; count--) {
      final year = _year(words.take(count).join(' '));
      if (year == null) continue;
      final rest = words.skip(count).join(' ');
      return rest.isEmpty ? '$head $year' : '$head $year $rest';
    }
    return '$head ${yearText.trim()}';
  }

  static final RegExp _space = RegExp(r'\s+');

  String _replaceEnglish(Match m) {
    final day = _englishOrdinalDay(m[2]!);
    if (day == null) return m[0]!;
    final month = _englishMonths[m[1]!.toLowerCase()]!;
    final yearText = m[3];
    final head = '$month $day';
    if (yearText == null) return head;
    final year = _englishYear(yearText);
    if (year == null) return '$head ${yearText.trim()}';
    return '$head, $year';
  }

  /// Day 1 to 31 of a German ordinal word ("fünfzehnter", "erste", "dritten").
  static int? _germanOrdinalDay(String word) {
    final lower = word.toLowerCase();
    for (final suffix in _germanSuffixes) {
      if (lower.length <= suffix.length || !lower.endsWith(suffix)) continue;
      final stem = lower.substring(0, lower.length - suffix.length);
      for (final candidate in _germanStemCandidates(stem)) {
        final day = spokenInteger(_irregularStems[candidate] ?? candidate);
        if (day != null && day >= 1 && day <= 31) return day;
      }
    }
    return null;
  }

  /// The number words a German ordinal stem can stand for: "fünf" from
  /// "fünf", "sechs" from "sechs" plus "te"-stripping, "acht" from "ach".
  static List<String> _germanStemCandidates(String stem) => [
    stem,
    '${stem}en',
    '${stem}e',
    '${stem}t',
    '${stem}s',
  ];

  static int? _englishOrdinalDay(String phrase) {
    final parts = phrase.toLowerCase().split(RegExp(r'[\s-]+'));
    if (parts.length == 1) return _englishOrdinals[parts.first];
    if (parts.length != 2) return null;
    final tens = _englishTensWords[parts.first];
    final unit = _englishOrdinals[parts.last];
    if (tens == null || unit == null || unit > 9) return null;
    return tens + unit;
  }

  /// "twenty-first" and "thirty first": the tens word, then a unit ordinal.
  static const _englishTensWords = <String, int>{'twenty': 20, 'thirty': 30};

  /// A year written as digits or as German words, when it lies in 1900 to 2099.
  static int? _year(String text) {
    final value = spokenInteger(text);
    return value != null && value >= 1900 && value <= 2099 ? value : null;
  }

  /// A year in English words: "two thousand twenty seven" or the spoken
  /// form "twenty twenty seven" (2027), or digits. "twenty five" is not a
  /// year: the spoken form needs a two-digit second part from 10 up, so a
  /// bare number of 1 to 9 never turns into 20xx.
  static int? _englishYear(String text) {
    final lower = text.toLowerCase();
    if (lower.startsWith('twenty ')) {
      final rest = spokenInteger(lower.substring('twenty '.length));
      if (rest == null || rest < 10 || rest > 99) return null;
      return 2000 + rest;
    }
    return _year(text);
  }
}
