/// Clock times spoken out loud, written with digits.
///
/// Output formats (decision, see the library doc of the pipeline):
/// - German: "zehn Uhr dreißig" becomes "10:30 Uhr", "um zehn Uhr" becomes
///   "um 10 Uhr". The word "Uhr" is required, so "zehn dreißig" stays text.
///   The hour "ein" needs a preposition before it ("um ein Uhr"), and
///   "eine" is never an hour ("eine Uhr kaufen" stays).
/// - English: "ten thirty" becomes "10:30", "ten oh five" becomes "10:05",
///   "ten o'clock" becomes "10:00", "ten thirty pm" becomes "10:30 pm".
///   Minutes 1 to 9 need "oh" ("ten five" stays text, "two three" stays).
///
/// Hours run 0 to 23 in German, 1 to 12 in English, minutes 0 to 59.
library;

import 'dictation_transform.dart';
import 'itn_numbers.dart';

final class ItnTime implements DictationTransform {
  const ItnTime();

  @override
  String get id => 'time';

  static final RegExp _hint = RegExp(
    r'\buhr\b|o.clock|\bam\b|\bpm\b|\bp\.m\.|\ba\.m\.|'
    r'\b(?:ein|eins|eine|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|'
    r'elf|zwölf|one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
    r'twelve)\b',
    caseSensitive: false,
    unicode: true,
  );

  /// German: hour (word or digits), "Uhr", optional minutes (word or two
  /// digits), not followed by a letter or digit.
  static final RegExp _germanPattern = RegExp(
    r'(?<![\p{L}\p{N}])(\p{L}+|\d{1,2})\s+Uhr'
    r'(?:\s+(\p{L}+|\d{2})(?![\p{L}\p{N}]))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static const _hourPrepositions = <String>{'um', 'gegen', 'bis', 'ab'};

  static final RegExp _lastWord = RegExp(r'(\p{L}+)$', unicode: true);

  /// English "H MM", "H oh M" or "H o'clock", optionally with am/pm.
  static final RegExp _englishPattern = RegExp(
    '(?<![\\p{L}\\p{N}])($enHours)\\s+'
    '(oh\\s+(?:$enUnits)|(?:$enTeens)|(?:$enTens)(?:[\\s-]+(?:$enUnits))?)'
    r'(?:\s+(am|pm|a\.m\.|p\.m\.))?(?![\p{L}\p{N}\-])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _englishClockPattern = RegExp(
    '(?<![\\p{L}\\p{N}])($enHours)\\s+o[\'’]clock(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _englishSuffixPattern = RegExp(
    '(?<![\\p{L}\\p{N}])($enHours)\\s+(am|pm|a\\.m\\.|p\\.m\\.)'
    r'(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  @override
  String apply(String text, TransformContext ctx) {
    if (!_hint.hasMatch(text)) return text;
    if (ctx.isGerman) {
      return text.replaceAllMapped(_germanPattern, (m) => _german(text, m));
    }
    if (ctx.isEnglish) {
      var out = text.replaceAllMapped(_englishPattern, _english);
      out = out.replaceAllMapped(_englishClockPattern, (m) {
        final hour = _englishHour(m[1]!);
        return hour == null ? m[0]! : '$hour:00';
      });
      return out.replaceAllMapped(_englishSuffixPattern, (m) {
        final hour = _englishHour(m[1]!);
        return hour == null ? m[0]! : '$hour ${_suffix(m[2]!)}';
      });
    }
    return text;
  }

  String _german(String text, Match m) {
    final hourText = m[1]!;
    final hour = _germanNumber(hourText);
    if (hour == null || hour > 23) return m[0]!;
    final lower = hourText.toLowerCase();
    if (lower == 'eine') return m[0]!;
    if (lower == 'ein' && !_precededByHourPreposition(text, m.start)) {
      return m[0]!;
    }
    final minuteText = m[2];
    if (minuteText == null) return '$hour Uhr';
    final minute = _germanNumber(minuteText);
    if (minute == null || minute > 59) {
      // The word after "Uhr" is not a minute: keep it, convert the hour.
      final tail = m[0]!.substring(m[0]!.toLowerCase().indexOf('uhr') + 3);
      return '$hour Uhr$tail';
    }
    return '$hour:${minute.toString().padLeft(2, '0')} Uhr';
  }

  /// Digits or a spoken German number, as an integer.
  static int? _germanNumber(String text) =>
      _digitsOnly.hasMatch(text) ? int.parse(text) : spokenInteger(text);

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  String _english(Match m) {
    final hour = _englishHour(m[1]!);
    if (hour == null) return m[0]!;
    final minuteText = m[2]!;
    final minute = minuteText.toLowerCase().startsWith('oh')
        ? spokenInteger(minuteText.substring(2).trim())
        : spokenInteger(minuteText);
    if (minute == null || minute < 0 || minute > 59) return m[0]!;
    final suffix = m[3] == null ? '' : ' ${_suffix(m[3]!)}';
    return '$hour:${minute.toString().padLeft(2, '0')}$suffix';
  }

  /// English hour 1 to 12, or null.
  static int? _englishHour(String word) {
    final hour = spokenInteger(word);
    return hour != null && hour >= 1 && hour <= 12 ? hour : null;
  }

  static String _suffix(String marker) =>
      marker.toLowerCase().startsWith('a') ? 'am' : 'pm';

  /// Whether the text right before [start] ends with one of the hour
  /// prepositions ("um ein Uhr"). Only the last few characters are read.
  static bool _precededByHourPreposition(String text, int start) {
    final from = start > 12 ? start - 12 : 0;
    final before = text.substring(from, start).trimRight().toLowerCase();
    final word = _lastWord.firstMatch(before);
    return word != null && _hourPrepositions.contains(word[1]);
  }
}
