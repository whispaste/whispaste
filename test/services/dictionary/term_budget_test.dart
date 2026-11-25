/// What each recognition gets of the term list (#622, #1969): the front,
/// most used first, in whole terms, within that recognition's real limit.
library;

import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/auto_terms.dart';
import 'package:whispaste/services/dictionary/term_budget.dart';
import 'package:whispaste/services/dictionary/vocabulary_terms.dart';
import 'package:whispaste/services/stt/prompt_token_budget.dart';
import 'package:whispaste/services/transcription/openai_transcriber.dart'
    show openAiPrompt;

/// One token per started 4 characters.
Future<int> _fakeCount(String text) async => (text.length / 4).ceil();

void main() {
  group('measured with the real whisper tokenizer (large-v3-turbo, #786)', () {
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

    Future<int> Function(String) lookup(String sep, List<int> prefix) {
      final byText = {
        for (var n = 1; n <= terms.length; n++)
          terms.take(n).join(sep): prefix[n - 1],
      };
      return (text) async => byText[text]!;
    }

    test('comma list: the 12 leading terms (63 tokens) go in', () async {
      final sent = await vocabularyWithinTokens(
        terms.join(', '),
        63,
        lookup(', ', commaPrefix),
      );
      expect(vocabularyTerms(sent), terms.take(12));
    });

    test('one term per line: 10 terms (60 tokens) go in', () async {
      final sent = await vocabularyWithinTokens(
        terms.join('\n'),
        63,
        lookup('\n', linePrefix),
      );
      expect(sent, terms.take(10).join('\n'));
    });
  });

  group('on-device Whisper keeps the most used terms, whole', () {
    // 50 used replacements, listed least used first; the hint puts the most
    // used first.
    final hint = autoTermsVocabulary([
      for (var i = 49; i >= 0; i--)
        (
          replacement: i.isEven ? 'Mac Studio $i' : 'Kubernetes$i',
          usageCount: 100 - i,
          isTerm: false,
          changed: DateTime(2026),
        ),
    ]);

    test('the cut keeps the top used terms inside 63 tokens', () async {
      final sent = await vocabularyWithinTokens(hint, 63, _fakeCount);
      final kept = vocabularyTerms(sent);
      expect(kept, isNotEmpty);
      expect(await _fakeCount(sent), lessThanOrEqualTo(63));
      expect(kept.first, 'Mac Studio 0');
      expect(kept, vocabularyTerms(hint).take(kept.length));
    });

    test('no term is handed on half cut', () async {
      // 4 characters a token, 5 tokens: the old word-level cut kept
      // "Kubernetes, Mac", half of "Mac Studio".
      const list = 'Kubernetes, Mac Studio';
      expect(
        await truncatePromptToTokenBudget(list, 5, _fakeCount),
        'Kubernetes, Mac',
      );
      expect(await vocabularyWithinTokens(list, 5, _fakeCount), 'Kubernetes');
    });

    test('without a token count only a byte-safe prefix goes', () {
      final sent = vocabularyWithinBytes(hint, 63);
      expect(utf8.encode(sent).length, lessThanOrEqualTo(63));
      expect(vocabularyTerms(sent).first, 'Mac Studio 0');
    });
  });

  group('cloud prompt (OpenAI, own endpoint)', () {
    final long = [for (var i = 0; i < 50; i++) 'Fachbegriff-Nummer-$i'];

    test('an overlong list keeps its front, within the estimate', () {
      // whisper-1 reads only the last 224 tokens: without the cut the most
      // used terms at the front were the ones lost.
      final prompt = openAiPrompt(long.join(', '), 'carried context');
      final vocab = prompt.substring(
        0,
        prompt.length - ' carried context'.length,
      );
      expect(
        estimatedPromptTokens(vocab),
        lessThanOrEqualTo(kCloudPromptVocabularyTokens),
      );
      expect(prompt, startsWith('Fachbegriff-Nummer-0, '));
      expect(vocabularyTerms(vocab).last, startsWith('Fachbegriff-Nummer-'));
      expect(prompt, endsWith(' carried context'));
    });

    test('a short list goes in full', () {
      expect(openAiPrompt('GitHub, npm', null), 'GitHub, npm');
    });
  });
}
