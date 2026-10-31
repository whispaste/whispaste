/// Amounts of money spoken with a currency word, written with the symbol.
///
/// Output formats (decision, see the library doc of the pipeline):
/// - German: the symbol follows with a space and a decimal comma, "50 €",
///   "2,50 €", "50 $" (dollar). Thousands get no separator ("1000 €"),
///   which keeps the amount readable to the text steps that follow.
/// - English: the symbol leads without a space, "$50", "€2.50".
///
/// Cents follow the currency word. In German, "zwei Euro fünfzig" becomes
/// "2,50 €". Without the word "Cent", cents count only from 10 up, so
/// "zwei Euro fünf Leute" keeps its meaning; with "Cent", any cents count:
/// "zwei Euro fünf Cent" becomes "2,05 €". Such a count without the word
/// only holds when a sentence end or a punctuation mark follows ("zwei Euro
/// zwanzig." becomes "2,20 €."); otherwise the whole phrase stays text, so
/// "zwei Euro zwanzig Leute" is not split into "2 € zwanzig Leute".
/// English: "two dollars fifty" becomes "$2.50", and "two euros five cents"
/// becomes "€2.05", "two dollars twenty." becomes "$2.20.". Currency words:
/// Euro and Dollar (German), euro(s) and dollar(s) (English). "Pfund" and
/// "pound" stay text: both are also units of weight.
library;

import 'dictation_transform.dart';
import 'itn_numbers.dart';

final class ItnMoney implements DictationTransform {
  const ItnMoney();

  @override
  String get id => 'money';

  static final RegExp _hint = RegExp(
    r'euro|dollar',
    caseSensitive: false,
    unicode: true,
  );

  /// German: amount (digits with optional decimal comma, or one spoken
  /// number word), currency word, optional cents (two digits or one word).
  static final RegExp _germanPattern = RegExp(
    r'(?<![\p{L}\p{N}.,])(\d+(?:,\d{1,2})?|\p{L}+)\s+(Euro|Dollar)'
    r'(?![\p{L}\p{N}\-])'
    r'(?:\s+(\p{L}+|\d{2})(?![\p{L}\p{N}])(\s+Cent)?(?![\p{L}\p{N}]))?',
    caseSensitive: false,
    unicode: true,
  );

  static const _numberWord =
      '(?:$enUnits|$enTeens|$enTens|hundred|thousand|'
      'million|zero)';

  /// English: amount as digits or as up to six number words ("one hundred
  /// twenty five"), currency word, optional cents as words or digits, with
  /// or without "cents".
  static final RegExp _englishPattern = RegExp(
    '(?<![\\p{L}\\p{N}.,])'
    '(\\d+(?:\\.\\d{1,2})?|$_numberWord(?:(?:\\s+and)?[\\s-]+$_numberWord){0,5})'
    r'\s+(dollars?|euros?)(?![\p{L}\p{N}\-])'
    '(?:\\s+(?:and\\s+)?($enTwoDigitWords|\\d{1,2})(\\s+cents?)?'
    r'(?![\p{L}\p{N}]))?',
    caseSensitive: false,
    unicode: true,
  );

  @override
  String apply(String text, TransformContext ctx) => applyByLanguage(
    text,
    ctx,
    hint: _hint,
    german: _replaceGermanAmounts,
    english: _replaceEnglishAmounts,
  );

  String _replaceGermanAmounts(String text) =>
      text.replaceAllMapped(_germanPattern, _german);

  String _replaceEnglishAmounts(String text) =>
      text.replaceAllMapped(_englishPattern, _english);

  String _german(Match m) {
    final amountText = m[1]!;
    final currency = m[2]!.toLowerCase() == 'euro' ? '€' : r'$';
    final centsText = m[3];
    final amount = _amount(amountText);
    if (amount == null) return m[0]!;
    if (centsText == null) return '$amount $currency';
    if (amountText.contains(',')) return m[0]!;
    final cents = _digitsOnly.hasMatch(centsText)
        ? int.parse(centsText)
        : spokenInteger(centsText);
    final hasCentWord = m[4] != null;
    if (cents == null) return _withoutCents(m);
    if (cents > 99) return m[0]!;
    if (!_countsWithoutCentWord(m, cents, hasCentWord)) return m[0]!;
    return '$amount,${cents.toString().padLeft(2, '0')} $currency';
  }

  String _english(Match m) {
    final amountText = m[1]!;
    final symbol = m[2]!.toLowerCase().startsWith('euro') ? '€' : r'$';
    final centsText = m[3];
    final amount = _englishAmount(amountText);
    if (amount == null) return m[0]!;
    if (centsText == null) return '$symbol$amount';
    if (amountText.contains('.')) return m[0]!;
    final cents = _digitsOnly.hasMatch(centsText)
        ? int.parse(centsText)
        : spokenInteger(centsText);
    final hasCentWord = m[4] != null;
    if (cents == null) return _englishWithoutCents(m, symbol);
    if (!_countsWithoutCentWord(m, cents, hasCentWord)) return m[0]!;
    return '$symbol$amount.${cents.toString().padLeft(2, '0')}';
  }

  /// Cents without their word count from 10 up, and only where the amount
  /// ends: a sentence end or a punctuation mark follows the match.
  static bool _countsWithoutCentWord(Match m, int cents, bool hasCentWord) {
    if (hasCentWord) return true;
    return cents >= 10 && _clauseEnd.hasMatch(m.input.substring(m.end));
  }

  static final RegExp _clauseEnd = RegExp(r'^\s*(?:[.,;:!?)]|$)');

  /// The German amount text as written: digits with comma stay, a spoken
  /// number becomes digits. Null when it is no whole number.
  static String? _amount(String text) {
    if (text.contains(',')) return text;
    if (_digitsOnly.hasMatch(text)) return text;
    final value = spokenInteger(text);
    return value?.toString();
  }

  static String? _englishAmount(String text) {
    if (text.contains('.')) return text;
    if (_digitsOnly.hasMatch(text)) return text;
    final value = spokenInteger(text);
    return value?.toString();
  }

  /// A German match whose cents do not count: the currency part alone, the
  /// spoken cents and their word stay in the text after it.
  String _withoutCents(Match m) {
    final amount = _amount(m[1]!);
    if (amount == null) return m[0]!;
    final currency = m[2]!.toLowerCase() == 'euro' ? '€' : r'$';
    return '$amount $currency ${m[3]}${m[4] ?? ''}';
  }

  String _englishWithoutCents(Match m, String symbol) {
    final amount = _englishAmount(m[1]!);
    if (amount == null) return m[0]!;
    return '$symbol$amount ${m[3]}';
  }

  static final RegExp _digitsOnly = RegExp(r'^\d+$');
}
