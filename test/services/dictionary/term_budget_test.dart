/// Where the term list stops reaching the active recognition (#622): the
/// limit is worked out per recognition, from the real token count of the
/// loaded model (a fake counter here), never guessed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/dictionary/term_budget.dart';

/// One token per started 4 characters: enough to place a limit exactly.
Future<int?> _fakeCount(String text) async => (text.length / 4).ceil();

Future<int?> _onDevice(
  List<String> terms, {
  OnDeviceEngine engine = OnDeviceEngine.whisper,
  TermTokenCounter? counter = _fakeCount,
}) => firstLeftOutTerm(
  terms,
  provider: SttProviderType.onDevice,
  engine: engine,
  countTokens: counter,
);

/// Distinct terms of exactly 30 bytes each.
List<String> _thirty(int n) => [
  for (var i = 0; i < n; i++)
    'w${i.toString().padLeft(2, '0')}'.padRight(30, 'x'),
];

void main() {
  group('on-device Whisper (fake counter, limit 63)', () {
    test('a short list is used completely', () async {
      expect(await _onDevice(['GitHub', 'npm', 'JSON']), isNull);
    });

    test('a model that goes away mid-count claims nothing', () async {
      var calls = 0;
      final terms = [for (var i = 0; i < 60; i++) 'term$i'];
      expect(
        await _onDevice(terms, counter: (t) async => ++calls == 1 ? 999 : null),
        isNull,
      );
    });

    test('without a loaded model nothing is claimed', () async {
      final terms = [for (var i = 0; i < 60; i++) 'term$i'];
      expect(await _onDevice(terms, counter: (_) async => null), isNull);
      expect(await _onDevice(terms, counter: null), isNull);
    });
  });

  group('Deepgram (50 terms, 500 bytes)', () {
    Future<int?> deepgram(List<String> terms) => firstLeftOutTerm(
      terms,
      provider: SttProviderType.deepgram,
      engine: OnDeviceEngine.whisper,
    );

    test('the 51st term is the first one left out', () async {
      expect(await deepgram([for (var i = 0; i < 50; i++) 'a$i']), isNull);
      expect(await deepgram([for (var i = 0; i < 51; i++) 'a$i']), 50);
    });

    test('a repeated term is sent once and takes no room', () async {
      final terms = [for (var i = 0; i < 50; i++) 'a$i', 'A0', 'A1'];
      expect(await deepgram(terms), isNull);
    });

    test('a long term past the budget is the first one reported', () async {
      final terms = [..._thirty(16), 'y' * 40, 'z'];
      expect(await deepgram(terms), 16);
    });

    test('the byte budget cuts before the count', () async {
      final terms = _thirty(20);
      expect(await deepgram(terms), 16); // 16 * 30 = 480, the 17th makes 510
    });
  });

  group('recognitions without a limit known to the app', () {
    final many = [for (var i = 0; i < 200; i++) 'term$i'];

    test('Parakeet has no prompt channel', () async {
      expect(await _onDevice(many, engine: OnDeviceEngine.parakeet), isNull);
    });

    test('OpenAI and the own endpoint report none', () async {
      for (final p in [
        SttProviderType.openAI,
        SttProviderType.customEndpoint,
      ]) {
        expect(
          await firstLeftOutTerm(
            many,
            provider: p,
            engine: OnDeviceEngine.whisper,
            countTokens: _fakeCount,
          ),
          isNull,
        );
      }
    });
  });

  group('measured with the real whisper tokenizer (large-v3-turbo, #786)', () {
    // 26 typical German/English terms, token counts of the first n terms
    // joined, measured with whisper.cpp v1.9.5 `whisper_tokenize` (the call
    // the app counts with) on 2026-11-05. The counter is a lookup of these
    // measurements, so the test pins the bisection against real BPE counts,
    // which are not linear in the text length.
    const terms = [
      'GitHub',
      'npm',
      'JSON',
      'Kubernetes',
      'WhisPaste',
      'Straßenbahn',
      'Donaudampfschifffahrtsgesellschaft',
      'Müller-Lüdenscheidt',
      'Größenänderung',
      'Datenschutzgrundverordnung',
      'DSGVO',
      'PostgreSQL',
      'TypeScript',
      'OAuth2',
      'iPhone',
      'Äpfel',
      'Übergabepunkt',
      'Qualitätssicherung',
      'Dr. Weißenböck',
      'Anthropic',
      'ChatGPT',
      'Supabase',
      'Mac Studio',
      'Zürich',
      'Łukasz',
      'Wörterbuch',
    ];
    const commaPrefix = [
      3, 6, 8, 10, 14, 19, 29, 40, 47, 55, 59, 63, 66, 70, 72, 76, 81, 89, //
      98, 101, 106, 110, 113, 117, 121, 127,
    ];
    const linePrefix = [
      3, 6, 9, 12, 17, 23, 33, 44, 51, 60, 64, 69, 73, 78, 81, 86, 91, 100, //
      109, 113, 118, 122, 125, 129, 134, 140,
    ];

    Future<int?> Function(String) lookup(String sep, List<int> prefix) {
      final byText = {
        for (var n = 1; n <= terms.length; n++)
          terms.take(n).join(sep): prefix[n - 1],
      };
      return (text) async => byText[text];
    }

    test(
      'comma list: 12 terms are exactly 63 tokens, the 13th is cut',
      () async {
        expect(await _onDevice(terms, counter: lookup(', ', commaPrefix)), 12);
      },
    );

    test(
      'one term per line: 10 terms fit (60), the 11th (64) is cut',
      () async {
        final cut = await firstLeftOutTerm(
          terms,
          provider: SttProviderType.onDevice,
          engine: OnDeviceEngine.whisper,
          style: 'one\nper line',
          countTokens: lookup('\n', linePrefix),
        );
        expect(cut, 10);
      },
    );
  });
}
