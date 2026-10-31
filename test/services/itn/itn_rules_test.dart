import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/itn/dictation_transform.dart';
import 'package:whispaste/services/itn/itn_date.dart';
import 'package:whispaste/services/itn/itn_email.dart';
import 'package:whispaste/services/itn/itn_money.dart';
import 'package:whispaste/services/itn/itn_time.dart';
import 'package:whispaste/services/itn/itn_url.dart';

const _de = TransformContext(languageCode: 'de');
const _en = TransformContext(languageCode: 'en');

/// Input to expected output pairs, per rule. Negative cases keep the text.
void _expectCases(
  DictationTransform rule,
  TransformContext ctx,
  List<(String, String)> cases,
) {
  for (final (input, expected) in cases) {
    expect(
      rule.apply(input, ctx),
      expected,
      reason: '${rule.id} (${ctx.languageCode}): "$input"',
    );
  }
}

void main() {
  group('ItnEmail', () {
    test('de: spoken address with punkt and at', () {
      _expectCases(const ItnEmail(), _de, [
        (
          'schreib max punkt mustermann at gmail punkt com',
          'schreib max.mustermann@gmail.com',
        ),
        (
          'die adresse ist john at gmx punkt de bitte',
          'die adresse ist john@gmx.de bitte',
        ),
        ('mail an Anna at web punkt de', 'mail an anna@web.de'),
        ('max unterstrich x at gmx punkt at', 'max_x@gmx.at'),
        ('mail klammeraffe', 'mail klammeraffe'),
      ]);
    });

    test('en: spoken address with dot and at', () {
      _expectCases(const ItnEmail(), _en, [
        ('john at gmail dot com please', 'john@gmail.com please'),
        (
          'send it to Anna dot Lee at Mail dot co dot uk',
          'send it to anna.lee@mail.co.uk',
        ),
        ('jane underscore doe at example dot org', 'jane_doe@example.org'),
      ]);
    });

    test(
      'negatives: no domain, unknown top-level domain, articles, idioms',
      () {
        _expectCases(const ItnEmail(), _en, [
          ('meet me at home', 'meet me at home'),
          ('john at gmail', 'john at gmail'),
          ('john at gmail dot pizza', 'john at gmail dot pizza'),
          ('look at example dot com', 'look at example dot com'),
          ('the dot com bubble', 'the dot com bubble'),
        ]);
        _expectCases(const ItnEmail(), _de, [
          ('an max at gmx punkt de', 'an max@gmx.de'),
          ('ich bin at home', 'ich bin at home'),
          ('das war ein wichtiger Punkt', 'das war ein wichtiger Punkt'),
          ('Punkt de', 'Punkt de'),
        ]);
      },
    );

    test('already written address is untouched', () {
      _expectCases(const ItnEmail(), _de, [
        ('max.mustermann@gmail.com', 'max.mustermann@gmail.com'),
      ]);
    });
  });

  group('ItnUrl', () {
    test('de: www and punkt with a known top-level domain', () {
      _expectCases(const ItnUrl(), _de, [
        (
          'besuch www punkt beispiel punkt de heute',
          'besuch www.beispiel.de heute',
        ),
        ('schau dir beispiel punkt de an', 'schau dir beispiel.de an'),
        ('w w w punkt beispiel punkt de', 'www.beispiel.de'),
      ]);
    });

    test('path with schrägstrich keeps the spoken case', () {
      _expectCases(const ItnUrl(), _de, [
        ('beispiel punkt de schrägstrich Impressum', 'beispiel.de/Impressum'),
        (
          'www punkt beispiel punkt de schrägstrich blog schrägstrich neu',
          'www.beispiel.de/blog/neu',
        ),
      ]);
    });

    test('en: scheme, dot and slash', () {
      _expectCases(const ItnUrl(), _en, [
        (
          'https colon slash slash example dot com slash news',
          'https://example.com/news',
        ),
        ('visit example dot com today', 'visit example.com today'),
        ('go to mail dot google dot com', 'go to mail.google.com'),
      ]);
    });

    test('negatives: punkt in running text, unknown tld, no label', () {
      _expectCases(const ItnUrl(), _de, [
        ('das war der Punkt Ende', 'das war der Punkt Ende'),
        ('Punkt eins und Punkt zwei', 'Punkt eins und Punkt zwei'),
        ('beispiel punkt xyz', 'beispiel punkt xyz'),
        ('der punkt de Gaulle', 'der punkt de Gaulle'),
      ]);
      _expectCases(const ItnUrl(), _en, [
        ('the dot com bubble', 'the dot com bubble'),
      ]);
    });

    test('e-mail domain is not taken as a web address', () {
      final afterEmail = const ItnUrl().apply(
        const ItnEmail().apply('john at gmail dot com', _en),
        _en,
      );
      expect(afterEmail, 'john@gmail.com');
    });
  });

  group('ItnDate', () {
    test('de: ordinal day, month and year in digits', () {
      _expectCases(const ItnDate(), _de, [
        ('fünfzehnter März zweitausendsiebenundzwanzig', '15. März 2027'),
        ('am fünfzehnten März 2027', 'am 15. März 2027'),
        ('am erster Mai war es', 'am 1. Mai war es'),
        ('am zehnten Juni', 'am 10. Juni'),
        ('am dritten März', 'am 3. März'),
        ('am achten Oktober', 'am 8. Oktober'),
        ('am einundzwanzigsten April', 'am 21. April'),
        (
          'fünfzehnter März zweitausendsiebenundzwanzig ist der Termin',
          '15. März 2027 ist der Termin',
        ),
      ]);
    });

    test('de negatives: month alone, day alone, number without month', () {
      _expectCases(const ItnDate(), _de, [
        ('im März passiert nichts', 'im März passiert nichts'),
        ('der zehnte Versuch', 'der zehnte Versuch'),
        ('zehn März', 'zehn März'),
        ('März 2027', 'März 2027'),
        ('am fünfzehnten März 1700', 'am 15. März 1700'),
        ('die Mai-Ausgabe', 'die Mai-Ausgabe'),
        ('am fünfzehnten März fünfundzwanzig', 'am 15. März fünfundzwanzig'),
      ]);
    });

    test('en: month first, day, year', () {
      _expectCases(const ItnDate(), _en, [
        ('March fifteenth, two thousand twenty seven', 'March 15, 2027'),
        ('on march fifteenth twenty twenty seven', 'on March 15, 2027'),
        ('March first', 'March 1'),
        ('see you on december twenty first', 'see you on December 21'),
        ('it was may thirtieth', 'it was May 30'),
        ('on march fifteenth twenty twenty five', 'on March 15, 2025'),
        ('on march fifteenth twenty ten', 'on March 15, 2010'),
      ]);
    });

    test('en: two-digit year without century is never 20xx', () {
      _expectCases(const ItnDate(), _en, [
        ('March fifteenth twenty five', 'March 15 twenty five'),
        ('March fifteenth, twenty five', 'March 15 twenty five'),
        ('March fifteenth twenty', 'March 15 twenty'),
      ]);
    });

    test('en negatives: no month, day first, lone ordinal', () {
      _expectCases(const ItnDate(), _en, [
        ('in March nothing happened', 'in March nothing happened'),
        ('the twentieth try', 'the twentieth try'),
        ('twenty first of March', 'twenty first of March'),
        ('March 15, 2027', 'March 15, 2027'),
      ]);
    });
  });

  group('ItnTime', () {
    test('de: hour and minutes with Uhr', () {
      _expectCases(const ItnTime(), _de, [
        ('um zehn Uhr dreißig treffen wir uns', 'um 10:30 Uhr treffen wir uns'),
        ('zehn Uhr fünf', '10:05 Uhr'),
        ('um zehn Uhr treffen wir uns', 'um 10 Uhr treffen wir uns'),
        ('um ein Uhr', 'um 1 Uhr'),
        ('um 10 Uhr 30 Schluss', 'um 10:30 Uhr Schluss'),
        ('zehn Uhr dreiundzwanzig', '10:23 Uhr'),
      ]);
    });

    test('de negatives: no Uhr, article, watch, impossible hour', () {
      _expectCases(const ItnTime(), _de, [
        ('zehn dreißig', 'zehn dreißig'),
        ('um zehn treffen wir uns', 'um zehn treffen wir uns'),
        ('ich will eine Uhr kaufen', 'ich will eine Uhr kaufen'),
        ('ein Uhr kaufen', 'ein Uhr kaufen'),
        ('er kam um 25 Uhr nie', 'er kam um 25 Uhr nie'),
        ('zehn Uhr 75', '10 Uhr 75'),
      ]);
    });

    test('en: hour and minutes, o\'clock and am/pm', () {
      _expectCases(const ItnTime(), _en, [
        ('meet at ten thirty', 'meet at 10:30'),
        ('ten oh five pm', '10:05 pm'),
        ('ten o\'clock sharp', '10:00 sharp'),
        ('ten fifteen', '10:15'),
        ('ten thirty five am', '10:35 am'),
        ('ten am', '10 am'),
      ]);
    });

    test('en negatives: single-digit minutes without oh, hyphen compounds', () {
      _expectCases(const ItnTime(), _en, [
        ('ten five', 'ten five'),
        ('two three', 'two three'),
        ('two thirty-year loan', 'two thirty-year loan'),
        ('at thirteen thirty', 'at thirteen thirty'),
      ]);
    });
  });

  group('ItnMoney', () {
    test('de: symbol after the amount, decimal comma for cents', () {
      _expectCases(const ItnMoney(), _de, [
        ('zwei Euro fünfzig', '2,50 €'),
        ('fünfzig Euro', '50 €'),
        ('das kostet 50 Euro', 'das kostet 50 €'),
        ('zehn Dollar', r'10 $'),
        ('zwei Euro zehn Cent', '2,10 €'),
        ('zwei Euro fünf Cent', '2,05 €'),
        ('ein Euro zwanzig', '1,20 €'),
        ('zwei Euro zwanzig.', '2,20 €.'),
        ('zwei Euro zwanzig, bitte', '2,20 €, bitte'),
        ('zwei Euro zwanzig Cent Leute', '2,20 € Leute'),
        ('zwei Euro fünf Cent Leute', '2,05 € Leute'),
      ]);
    });

    test('de negatives: cents below ten, unknown amount, compounds', () {
      _expectCases(const ItnMoney(), _de, [
        ('zwei Euro fünf Leute', 'zwei Euro fünf Leute'),
        ('zwei Euro zwanzig Leute', 'zwei Euro zwanzig Leute'),
        ('zwei Euro Leute', '2 € Leute'),
        ('eine Million Euro', 'eine Million Euro'),
        ('Euro-Zone', 'Euro-Zone'),
        ('die Euro', 'die Euro'),
        ('1.000 Euro', '1.000 Euro'),
      ]);
    });

    test('en: symbol before the amount, dot for cents', () {
      _expectCases(const ItnMoney(), _en, [
        ('fifty dollars', r'$50'),
        ('two dollars fifty', r'$2.50'),
        ('two euros and five cents', '€2.05'),
        ('one hundred twenty five dollars', r'$125'),
        ('the price is 50 dollars', r'the price is $50'),
        ('twenty euros', '€20'),
        ('two dollars twenty.', r'$2.20.'),
        ('two dollars twenty, please', r'$2.20, please'),
        ('two dollars fifty cents people', r'$2.50 people'),
      ]);
    });

    test('en negatives: pounds stay, cents below ten without the word', () {
      _expectCases(const ItnMoney(), _en, [
        ('two pounds of flour', 'two pounds of flour'),
        ('two dollars five', 'two dollars five'),
        ('two dollars twenty people', 'two dollars twenty people'),
        ('two dollars fifteenth', r'$2 fifteenth'),
      ]);
    });
  });
}
