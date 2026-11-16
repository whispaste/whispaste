/// Number phrases shared by the written-form rules.
///
/// The value of a phrase comes from [toNumericOnly], the same German and
/// English number parser the Zahlen-Modus uses, so both features agree on
/// what "dreiundzwanzig" or "twenty five" means. The regex fragments below
/// only find candidate phrases; the parser decides whether they are numbers.
library;

import '../number_transforms.dart';

final RegExp _plainInteger = RegExp(r'^[0-9]{1,9}$');

/// Words that the parser reads as a number on their own ("und" becomes 0),
/// but that never are one in a spoken form.
const _notANumber = <String>{'und', 'and', 'oh', 'zero'};

/// Integer value of one spoken number phrase, or null when [phrase] is not a
/// plain whole number. Separators, signs and mixed phrases give null.
int? spokenInteger(String phrase) {
  final trimmed = phrase.trim();
  if (trimmed.isEmpty || _notANumber.contains(trimmed.toLowerCase())) {
    return null;
  }
  final digits = toNumericOnly(trimmed);
  if (digits == null || !_plainInteger.hasMatch(digits)) return null;
  return int.parse(digits);
}

/// English hours 1 to 12 as regex alternatives.
const enHours =
    'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve';

/// English cardinal units, teens and tens as regex alternatives.
const enUnits = 'one|two|three|four|five|six|seven|eight|nine';
const enTeens =
    'ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|'
    'eighteen|nineteen';
const enTens = 'twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety';

/// English number of 0 to 99 written as words: "fifty", "twenty five",
/// "twenty-five", "twelve". Digits are left to the callers.
const enTwoDigitWords =
    '(?:(?:$enTens)(?:[\\s-]+(?:$enUnits))?|$enTeens|$enUnits)';
