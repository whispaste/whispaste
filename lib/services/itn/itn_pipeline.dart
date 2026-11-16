/// The written-form stage (inverse text normalization, "Schreibformen") of the
/// dictation text chain: spoken e-mail addresses, web addresses, dates, clock
/// times and amounts of money become their written form.
///
/// Position in the chain: after spoken line breaks and before the dictionary
/// replacements, so a user's own replacement always has the last word.
///
/// Fixed order, each rule on the output of the one before:
/// 1. E-mail, before the web address: the domain of an address must not be
///    read as a web address.
/// 2. Web address.
/// 3. Date, before the clock time: "fünfzehnter März zehn Uhr" keeps its
///    time after the date is written.
/// 4. Clock time.
/// 5. Money, last: it reads number words the earlier rules have left alone.
///
/// Output formats (decision, recorded in the rule files and the changelog):
/// - E-mail: lowercase, "max.mustermann@gmail.com".
/// - Web address: lowercase host, "www.beispiel.de", a path keeps its case.
/// - German date: "15. März 2027"; English date: "March 15, 2027".
/// - German time: "10:30 Uhr", "um 10 Uhr"; English time: "10:30",
///   "10:30 am", "10:00" for "ten o'clock".
/// - German money: "50 €", "2,50 €", "50 $"; English: "$50", "€2.50".
///
/// Languages: the rules are written for German and English only. Every other
/// language, and "auto" while the language is still unknown, gets no change.
/// Other languages wait for the follow-up package N4b.
///
/// Each rule is switched on its own; a rule that is off changes nothing.
/// Reading and writing are pure functions, so the chain is safe to test
/// without an app or a model.
library;

import 'dictation_transform.dart';
import 'itn_date.dart';
import 'itn_email.dart';
import 'itn_money.dart';
import 'itn_time.dart';
import 'itn_url.dart';

/// The five kinds of written form, one switch each.
enum WrittenFormKind { email, url, date, time, money }

/// The rules in chain order, each with its kind.
const _chain = <(WrittenFormKind, DictationTransform)>[
  (WrittenFormKind.email, ItnEmail()),
  (WrittenFormKind.url, ItnUrl()),
  (WrittenFormKind.date, ItnDate()),
  (WrittenFormKind.time, ItnTime()),
  (WrittenFormKind.money, ItnMoney()),
];

/// The context for [languageCode], or null when no rule applies to it.
TransformContext? transformContextFor(String languageCode) {
  final base = languageCode.toLowerCase().split(RegExp(r'[-_]')).first;
  if (base == 'de' || base == 'en') {
    return TransformContext(languageCode: base);
  }
  return null;
}

/// Runs the enabled written-form rules over [text] in chain order.
String applyWrittenForms(
  String text, {
  required String languageCode,
  required Set<WrittenFormKind> enabled,
}) {
  if (enabled.isEmpty) return text;
  final ctx = transformContextFor(languageCode);
  if (ctx == null) return text;
  var out = text;
  for (final (kind, rule) in _chain) {
    if (enabled.contains(kind)) out = rule.apply(out, ctx);
  }
  return out;
}
