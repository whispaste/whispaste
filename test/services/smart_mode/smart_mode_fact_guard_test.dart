import 'dart:async' show Completer, TimeoutException;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/smart_mode/smart_mode_fact_guard.dart';

void main() {
  test('a timed-out isolate fails closed with null (GS-045)', () async {
    final long = List.filled(15000, 'Wort').join(' ');
    final result = await checkSmartModeFacts(
      input: long,
      output: long,
      checkNames: true,
      knownTerms: const [],
      singleCapitalisedWordsAreNames: true,
      timeout: Duration.zero,
    );
    expect(result.violations, isNull);
    expect(result.failure, SmartModeGuardFailure.timedOut);
  });

  test(
    'a timeout thrown inside the guard is reported as timed out (DEV-151)',
    () async {
      debugSmartModeFactGuardOverride =
          ({
            required input,
            required output,
            required checkNames,
            required knownTerms,
            required singleCapitalisedWordsAreNames,
          }) => throw TimeoutException('slow');
      addTearDown(() => debugSmartModeFactGuardOverride = null);

      final result = await checkSmartModeFacts(
        input: 'a',
        output: 'b',
        checkNames: true,
        knownTerms: const [],
        singleCapitalisedWordsAreNames: true,
      );

      expect(result.violations, isNull);
      expect(result.failure, SmartModeGuardFailure.timedOut);
    },
  );

  group('smartModeFactViolations', () {
    test('identical text has no violations', () {
      const text = 'Anna kommt am 12.03.2026 um 14:30 Uhr, Preis 1.250,50 EUR.';
      expect(
        smartModeFactViolations(input: text, output: text, checkNames: true),
        isEmpty,
      );
    });

    test('changed number is reported as a number violation', () {
      final v = smartModeFactViolations(
        input: 'Wir brauchen 3 Stühle.',
        output: 'Wir brauchen 30 Stühle.',
        checkNames: true,
      );
      expect(v.map((e) => e.kind), [SmartModeFactKind.number]);
      expect(v.single.token, '3');
    });

    test('a number is not matched inside a longer number', () {
      final v = smartModeFactViolations(
        input: 'Um 2 Uhr.',
        output: 'Um 2026 Uhr.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['2']);
    });

    test('dropped date is reported as a date only', () {
      final v = smartModeFactViolations(
        input: 'Abgabe am 12.03.2026.',
        output: 'Abgabe bald.',
        checkNames: true,
      );
      expect(v.map((e) => e.kind), [SmartModeFactKind.date]);
    });

    test('altered URL is reported as url', () {
      final v = smartModeFactViolations(
        input: 'Siehe https://example.org/a?x=1 dort.',
        output: 'Siehe https://example.org/a dort.',
        checkNames: true,
      );
      expect(v.map((e) => e.kind), [SmartModeFactKind.url]);
    });

    test('altered e-mail address is reported as email', () {
      final v = smartModeFactViolations(
        input: 'Schreib an info@example.org bitte.',
        output: 'Schreib an info@example.com bitte.',
        checkNames: true,
      );
      expect(v.map((e) => e.kind), [SmartModeFactKind.email]);
    });

    test('capitalized word at sentence start is not treated as a name', () {
      final v = smartModeFactViolations(
        input: 'Heute regnet es. Morgen nicht.',
        output: 'Heute regnet es. Morgen nicht.',
        checkNames: true,
      );
      expect(v, isEmpty);
    });

    test('name check is off for translate: German nouns change case', () {
      final v = smartModeFactViolations(
        input: 'Wir gehen heute Einkaufen.',
        output: 'We are going shopping today.',
        checkNames: false,
      );
      expect(v.where((e) => e.kind == SmartModeFactKind.name), isEmpty);
    });

    test('number checks still apply when names are off', () {
      final v = smartModeFactViolations(
        input: 'Gib 5 Euro.',
        output: 'Give 6 euros.',
        checkNames: false,
      );
      expect(v.map((e) => e.token), ['5']);
    });

    group('names (Eigennamen)', () {
      test('a single capitalised word is not a name, so an inflected German '
          'noun does not fall back', () {
        final v = smartModeFactViolations(
          input: 'Der Termin ist morgen.',
          output: 'Die Termine sind morgen.',
          checkNames: true,
        );
        expect(v, isEmpty);
      });

      test('a noun inflected in the output keeps its stem (no fallback)', () {
        final v = smartModeFactViolations(
          input: 'Ich habe die Kinder gesehen und den Vertrag gelesen.',
          output: 'Ich habe das Kind gesehen und den Vertrag gelesen.',
          checkNames: true,
        );
        expect(v, isEmpty);
      });

      test('a missing second word of a two-word name falls back', () {
        final v = smartModeFactViolations(
          input: 'Ich habe mit Anna Schmidt gesprochen.',
          output: 'Ich habe mit Anna Meier gesprochen.',
          checkNames: true,
        );
        expect(v.map((e) => e.kind), [SmartModeFactKind.name]);
        expect(v.single.token, 'Schmidt');
      });

      test('a two-word name that is kept verbatim passes', () {
        final v = smartModeFactViolations(
          input: 'Ich habe mit Anna Schmidt gesprochen.',
          output: 'Mit Anna Schmidt habe ich gesprochen.',
          checkNames: true,
        );
        expect(v, isEmpty);
      });

      test('a dictionary name at sentence start is checked', () {
        final v = smartModeFactViolations(
          input: 'Müller kommt morgen.',
          output: 'Mueller kommt morgen.',
          checkNames: true,
          knownTerms: const ['Müller'],
        );
        expect(v.map((e) => e.kind), [SmartModeFactKind.name]);
        expect(v.single.token, 'Müller');
      });

      test('a dictionary name stays checked for translate (names off)', () {
        final v = smartModeFactViolations(
          input: 'Das Gespräch mit WhisPaste war gut.',
          output: 'The talk with the app was good.',
          checkNames: false,
          knownTerms: const ['WhisPaste'],
        );
        expect(v.map((e) => e.token), ['WhisPaste']);
      });

      test('an all-caps acronym is checked even at sentence start', () {
        final v = smartModeFactViolations(
          input: 'SAP ist das Update.',
          output: 'Das Update ist da.',
          checkNames: true,
        );
        expect(v.map((e) => e.kind), [SmartModeFactKind.name]);
        expect(v.single.token, 'SAP');
      });

      test('an inner-capital word such as iPhone is checked', () {
        final v = smartModeFactViolations(
          input: 'Mein iPhone ist kaputt.',
          output: 'Mein Telefon ist kaputt.',
          checkNames: true,
        );
        expect(v.map((e) => e.token), ['iPhone']);
      });

      test('a stem-preserving inflection of a name is accepted', () {
        final v = smartModeFactViolations(
          input: 'Wir fahren mit der Deutschen Bahn.',
          output: 'Wir fahren mit der Deutschen Bahnen.',
          checkNames: true,
        );
        expect(v, isEmpty);
      });
    });
  });

  group('dictionary name terms', () {
    test('names with particles, hyphens and apostrophes are kept', () {
      const names = [
        'iPhone',
        'eBay',
        'Anna-Lena Schmidt-Müller',
        "O'Brien",
        'van der Berg',
        'von Braun',
        'de Gaulle',
        'Anna Maria Schmidt Lehmann',
      ];
      expect(dictionaryNameTerms(names), names);
    });

    test('phrases and lowercase words are not protected', () {
      expect(
        dictionaryNameTerms([
          'Mit freundlichen Grüßen',
          'müller',
          'Anna Maria Schmidt Lehmann Weber',
          'Bitte Kurz',
        ]),
        ['Bitte Kurz'],
      );
    });

    test('names are kept, text snippets are not', () {
      expect(
        dictionaryNameTerms([
          'WhisPaste',
          'Müller',
          'Anna Schmidt',
          'Mit freundlichen Grüßen',
          'bitte kurz',
        ]),
        ['WhisPaste', 'Müller', 'Anna Schmidt'],
      );
    });
  });

  group('fact guard rules (DEV-56, DEV-58, stems, caps, speed)', () {
    test('a name after an honorific is checked (DEV-82)', () {
      final v = smartModeFactViolations(
        input: 'Das hat Frau Schmidt bestätigt.',
        output: 'Das hat Frau Schmitt bestätigt.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['Schmidt']);
    });

    test('a greeting before an honorific is not a name (DEV-82)', () {
      final v = smartModeFactViolations(
        input: 'Guten Tag Frau Schmidt.',
        output: 'Hallo Frau Schmidt.',
        checkNames: true,
      );
      expect(v, isEmpty);
    });

    test(
      'an abbreviated honorific with a dot names the next word (DEV-85)',
      () {
        final v = smartModeFactViolations(
          input: 'Ich habe Sig. Rossi getroffen.',
          output: 'Ich habe Sig. Russo getroffen.',
          checkNames: true,
        );
        expect(v.map((e) => e.token), ['Rossi']);
      },
    );

    test('a changed letter in a longer name is a violation (stem len - 1)', () {
      final v = smartModeFactViolations(
        input: 'Ich spreche mit Anna Schmidt.',
        output: 'Ich spreche mit Anna Schmitt.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['Schmidt']);
    });

    test(
      'an inflected longer name and a plural of a short name keep the stem',
      () {
        final v = smartModeFactViolations(
          input: 'Ich spreche mit Anna Schmidt.',
          output: 'Ich spreche mit Annas Schmidts.',
          checkNames: true,
        );
        expect(v, isEmpty);
      },
    );

    test('a single capitalised first name is a name outside German', () {
      final v = smartModeFactViolations(
        input: 'Ich habe mit Julia gesprochen.',
        output: 'I talked with Julie.',
        checkNames: true,
        singleCapitalisedWordsAreNames: true,
      );
      expect(v.map((e) => e.token), ['Julia']);
    });

    test('the same single word is not a name in German (no fallback)', () {
      final v = smartModeFactViolations(
        input: 'Ich habe mit Julia gesprochen.',
        output: 'Ich habe mit Julie gesprochen.',
        checkNames: true,
      );
      expect(v, isEmpty);
    });

    test('a sentence-initial single word stays unchecked outside German', () {
      final v = smartModeFactViolations(
        input: 'Julia kommt morgen.',
        output: 'Julie comes tomorrow.',
        checkNames: true,
        singleCapitalisedWordsAreNames: true,
      );
      expect(v, isEmpty);
    });

    test('an honorific is not part of a name run (DEV-58)', () {
      final v = smartModeFactViolations(
        input: 'Guten Tag Frau Schmidt.',
        output: 'Hallo Frau Schmidt.',
        checkNames: true,
      );
      expect(v, isEmpty);
    });

    test('a stem may be at most two characters longer than the name', () {
      // "Annahme" is three characters longer than "Anna": not the same name.
      final v = smartModeFactViolations(
        input: 'Ich spreche mit Anna Schmidt.',
        output: 'Ich spreche mit Annahme Schmidt.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['Anna']);
    });

    test(
      'all-caps words are no acronym evidence in a mostly-caps dictation',
      () {
        final v = smartModeFactViolations(
          input: 'ICH TREFFE SAP HEUTE UND MORGEN WIEDER DIE LEUTE.',
          output: 'Ich treffe heute und morgen wieder die Leute.',
          checkNames: true,
        );
        expect(v, isEmpty);
      },
    );

    test('an acronym in normal-case dictation is still checked', () {
      final v = smartModeFactViolations(
        input: 'Das Update von SAP ist fertig.',
        output: 'Das Update ist fertig.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['SAP']);
    });

    test('the check is linear in the number of tokens (GS-018, DEV-84)', () {
      String tokens(int count) =>
          [for (var i = 0; i < count; i++) _uniqueName(i)].join(' ');
      int steps(int count) {
        final text = tokens(count);
        var counted = 0;
        smartModeFactViolations(
          input: text,
          output: text,
          checkNames: true,
          onStep: () => counted++,
        );
        return counted;
      }

      final small = steps(2000);
      final large = steps(4000);
      expect(large, lessThan(small * 3), reason: 'quadratic would be about 4x');
    });

    test('without a step seam the check writes no global state (DEV-106)', () {
      // Production passes no counter; the check must still run and report.
      final v = smartModeFactViolations(
        input: 'Ich habe mit Anna Schmidt gesprochen.',
        output: 'Ich habe mit Anna Meier gesprochen.',
        checkNames: true,
      );
      expect(v.map((e) => e.token), ['Schmidt']);
    });
  });

  group('guarded check for callers (DEV-141, GS-032)', () {
    tearDown(() => debugSmartModeFactGuardOverride = null);

    test(
      'a long input runs off the main isolate with the same result',
      () async {
        final input = '${'Wir haben nichts Neues. ' * 1000} Preis 14 Euro.';
        final output = '${'Wir haben nichts Neues. ' * 1000} Preis 15 Euro.';
        expect(input.length, greaterThan(smartModeFactGuardIsolateThreshold));

        final direct = smartModeFactViolations(
          input: input,
          output: output,
          checkNames: true,
          knownTerms: const [],
          singleCapitalisedWordsAreNames: true,
        );
        final guarded = (await checkSmartModeFacts(
          input: input,
          output: output,
          checkNames: true,
          knownTerms: const [],
          singleCapitalisedWordsAreNames: true,
        )).violations;

        expect(direct, isNotEmpty);
        expect(guarded, isNotNull);
        expect(
          guarded!.map((v) => (v.kind, v.token)),
          direct.map((v) => (v.kind, v.token)),
        );
      },
    );

    test('an exception yields null, so callers fail closed', () async {
      debugSmartModeFactGuardOverride =
          ({
            required input,
            required output,
            required checkNames,
            required knownTerms,
            required singleCapitalisedWordsAreNames,
          }) => throw StateError('boom with user text 42');

      final guarded = await checkSmartModeFacts(
        input: 'Wir haben 3 Stück.',
        output: 'Wir haben 3 Stück.',
        checkNames: true,
        knownTerms: const [],
        singleCapitalisedWordsAreNames: true,
      );

      expect(guarded.violations, isNull);
      expect(guarded.failure, SmartModeGuardFailure.error);
    });
  });

  group('e-mail scan and full-width tokens (GS-032)', () {
    test('overlapping e-mail windows do not throw (DEV-141)', () {
      final text = 'a@${'x' * 60}.${'x' * 9}.com@y.org';
      expect(text.length, 82);
      expect(
        () => smartModeFactViolations(
          input: text,
          output: text,
          checkNames: true,
          knownTerms: const [],
          singleCapitalisedWordsAreNames: false,
        ),
        returnsNormally,
      );
    });

    test('a second overlapping shape does not throw (GS-034)', () {
      final text = '${'a' * 10}@${'x' * 60}.cc@dd.ee';
      expect(
        () => smartModeFactViolations(
          input: text,
          output: '',
          checkNames: true,
          knownTerms: const [],
          singleCapitalisedWordsAreNames: false,
        ),
        returnsNormally,
      );
    });

    test('random @-dense strings up to 2k chars never throw (fuzz)', () {
      const alphabet = 'a@＠.．x1 -_';
      final random = math.Random(41);
      for (var round = 0; round < 300; round++) {
        final length = random.nextInt(2000);
        final text = String.fromCharCodes(
          List.generate(
            length,
            (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
          ),
        );
        expect(
          () => smartModeFactViolations(
            input: text,
            output: text.toUpperCase(),
            checkNames: true,
            knownTerms: const [],
            singleCapitalisedWordsAreNames: true,
          ),
          returnsNormally,
          reason: 'round $round',
        );
      }
    });

    test('a full-width @ address is a protected e-mail', () {
      final violations = smartModeFactViolations(
        input: 'Schreib an info＠evil.example bitte.',
        output: 'Schreib bitte.',
        checkNames: false,
      );
      expect(violations, [
        const SmartModeFactViolation(
          kind: SmartModeFactKind.email,
          token: 'info＠evil.example',
        ),
      ]);
    });

    test('a full-width dot in a domain is part of the address', () {
      final violations = smartModeFactViolations(
        input: 'Mail info@evil．example',
        output: 'Mail',
        checkNames: false,
      );
      expect(violations, [
        const SmartModeFactViolation(
          kind: SmartModeFactKind.email,
          token: 'info@evil．example',
        ),
      ]);
    });

    test('a full-width domain link is a protected URL token', () {
      final violations = smartModeFactViolations(
        input: 'Siehe https://a.example/x.',
        output: 'Siehe https://a.example/x. Mehr: https://evil．example',
        checkNames: false,
      );
      expect(violations, isEmpty);
      final added = smartModeFactViolations(
        input: 'Mehr: https://evil．example',
        output: 'Siehe https://a.example/x.',
        checkNames: false,
      );
      expect(added.map((v) => v.kind), [SmartModeFactKind.url]);
    });
  });

  group('factGuardLanguage (DEV-107)', () {
    test('a configured language wins over the detected one', () {
      expect(factGuardLanguage(configured: 'de', detected: 'en'), 'de');
    });

    test('auto uses the detected language', () {
      expect(factGuardLanguage(configured: 'auto', detected: 'en'), 'en');
    });

    test('auto without a detected language falls back to German', () {
      expect(factGuardLanguage(configured: 'auto', detected: null), 'de');
      expect(factGuardLanguage(configured: 'auto', detected: ''), 'de');
    });
  });

  group('smartModeFactGuard eval fixtures', () {
    // Fixture with traps. Each case: input, output, expected kinds.
    // `checkNames` follows the preset the case is meant for. Negations
    // ("nicht", "kein") are not covered by this deterministic guard; they
    // are checked by the prompt and by the manual eval.
    const cases = <_EvalCase>[
      _EvalCase(
        name: 'cleanup keeps everything, removes filler',
        input: 'äh also am 3. Mai um 9 Uhr bei Max Müller, ähm.',
        output: 'Am 3. Mai um 9 Uhr bei Max Müller.',
        checkNames: true,
        expected: [],
      ),
      _EvalCase(
        name: 'cleanup drops a number',
        input: 'Es kostet 1250 Euro.',
        output: 'Es kostet Euro.',
        checkNames: true,
        expected: ['number'],
      ),
      _EvalCase(
        name: 'concise rewrites a date to a different day',
        input: 'Das Treffen ist am 12.03.2026 in Berlin.',
        output: 'Das Treffen ist am 13.03.2026 in Berlin.',
        checkNames: true,
        expected: ['date'],
      ),
      _EvalCase(
        name: 'number formatted differently is a change (kept strict)',
        input: 'Preis 3,5 Prozent.',
        output: 'Preis 3.5 Prozent.',
        checkNames: true,
        expected: ['number'],
      ),
      _EvalCase(
        name: 'two-word name misspelled by the model',
        input: 'Die Mail kommt von Julia Fischer.',
        output: 'Die Mail kommt von Julia Fisher.',
        checkNames: true,
        expected: ['name'],
      ),
      _EvalCase(
        name: 'clear stage: inflected nouns and reordered sentence pass',
        input: 'Der Termin war gestern, die Kunden kamen spät.',
        output: 'Gestern war der Termin; die Kunde kam spät.',
        checkNames: true,
        expected: [],
      ),
      _EvalCase(
        name: 'translate keeps numbers and URL',
        input: 'Schau auf www.whispaste.de am 4. Juli, es sind 7 Tage.',
        output: 'Look at www.whispaste.de on July 4, it is 7 days.',
        checkNames: false,
        expected: [],
      ),
      _EvalCase(
        name: 'translate with a changed URL path',
        input: 'Link: https://whispaste.de/hilfe/1',
        output: 'Link: https://whispaste.de/help/1',
        checkNames: false,
        expected: ['url'],
      ),
      _EvalCase(
        name: 'list item count changed is a number change',
        input: 'Drei Punkte: 1, 2 und 3.',
        output: 'Drei Punkte: 1, 2 und 4.',
        checkNames: true,
        expected: ['number'],
      ),
      _EvalCase(
        name: 'year inside a larger number does not satisfy a shorter one',
        input: 'Platz 20 von 200.',
        output: 'Platz 200 von 200.',
        checkNames: true,
        expected: ['number'],
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final v = smartModeFactViolations(
          input: c.input,
          output: c.output,
          checkNames: c.checkNames,
        );
        expect(
          (v.map((e) => e.kind.name).toSet().toList()..sort()),
          (c.expected.toSet().toList()..sort()),
        );
      });
    }
  });

  group('real guard isolate (GS-045 remainder)', () {
    test('a short deadline times out and the isolate is killed', () async {
      final big = 'a' * 30000;
      Future<SmartModeFactCheck> check(Duration timeout) => checkSmartModeFacts(
        input: big,
        output: big,
        checkNames: true,
        knownTerms: const [],
        singleCapitalisedWordsAreNames: true,
        timeout: timeout,
      );

      final timedOut = await check(const Duration(microseconds: 1));
      expect(timedOut.failure, SmartModeGuardFailure.timedOut);

      // The killed isolate exits, which frees the slot for the next check.
      for (var i = 0; i < 200 && debugGuardIsolateInFlight; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(debugGuardIsolateInFlight, isFalse);

      final later = await check(smartModeIsolateTimeout);
      expect(later.violations, isNotNull);
    });
  });

  group('single guard isolate in flight (GS-045 remainder)', () {
    test('a second timed-out check does not start a new isolate', () async {
      var starts = 0;
      final gate = Completer<void>();
      debugGuardIsolateRunner = <T>(T Function() computation) {
        starts++;
        return gate.future.then((_) => computation());
      };
      addTearDown(() => debugGuardIsolateRunner = null);
      final big = 'a' * 15000;

      Future<SmartModeFactCheck> check(Duration timeout) => checkSmartModeFacts(
        input: big,
        output: big,
        checkNames: true,
        knownTerms: const [],
        singleCapitalisedWordsAreNames: true,
        timeout: timeout,
      );

      final first = await check(const Duration(milliseconds: 10));
      final second = await check(const Duration(milliseconds: 10));

      expect(first.failure, SmartModeGuardFailure.timedOut);
      expect(second.failure, SmartModeGuardFailure.timedOut);
      expect(starts, 1);

      // Once the first isolate has ended, the next check runs again.
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final third = await check(smartModeIsolateTimeout);
      expect(third.violations, isNotNull);
      expect(starts, 2);
    });
  });
}

class _EvalCase {
  const _EvalCase({
    required this.name,
    required this.input,
    required this.output,
    required this.checkNames,
    required this.expected,
  });

  final String name;
  final String input;
  final String output;
  final bool checkNames;
  final List<String> expected;
}

/// Capitalised token with four distinct lowercase letters derived from [i].
String _uniqueName(int i) {
  final letters = StringBuffer('Q');
  var rest = i;
  for (var k = 0; k < 4; k++) {
    letters.writeCharCode(0x61 + rest % 26);
    rest ~/= 26;
  }
  return letters.toString();
}
