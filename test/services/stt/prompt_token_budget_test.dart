/// Unit tests for the pure [truncatePromptToTokenBudget] helper — the
/// front-anchored word-boundary binary search used to fix the silent
/// `initial_prompt` truncation bug (see the function's own doc comment).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/prompt_token_budget.dart';

/// Deterministic fake tokenizer: one token per whitespace-separated word,
/// so assertions can reason about exact word counts instead of a real
/// BPE's variable per-word token count.
Future<int> _wordCountTokenizer(String text) async {
  if (text.isEmpty) return 0;
  return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

void main() {
  group('truncatePromptToTokenBudget', () {
    test('returns empty string for empty input', () async {
      final result = await truncatePromptToTokenBudget(
        '',
        63,
        _wordCountTokenizer,
      );
      expect(result, '');
    });

    test('returns empty string for a non-positive budget', () async {
      final result = await truncatePromptToTokenBudget(
        'some words here',
        0,
        _wordCountTokenizer,
      );
      expect(result, '');
    });

    test('returns text unchanged when it already fits the budget', () async {
      const text = 'WhisPaste Kubernetes';
      final result = await truncatePromptToTokenBudget(
        text,
        63,
        _wordCountTokenizer,
      );
      expect(result, text);
    });

    test('returns text unchanged at exactly the budget boundary', () async {
      final text = List.generate(10, (i) => 'word$i').join(' ');
      final result = await truncatePromptToTokenBudget(
        text,
        10,
        _wordCountTokenizer,
      );
      expect(result, text);
    });

    test('truncates to the largest front-anchored prefix that fits', () async {
      final words = List.generate(100, (i) => 'word$i');
      final text = words.join(' ');
      final result = await truncatePromptToTokenBudget(
        text,
        63,
        _wordCountTokenizer,
      );
      expect(result, words.take(63).join(' '));
      expect(await _wordCountTokenizer(result), 63);
    });

    test(
      'returns empty string when not even a single leading word fits',
      () async {
        // A "tokenizer" that reports every non-empty string as exceeding
        // the budget, however short — simulates a single pathological word
        // that alone is already over budget.
        Future<int> hostileTokenizer(String text) async =>
            text.isEmpty ? 0 : 1000;
        final result = await truncatePromptToTokenBudget(
          'one two three',
          63,
          hostileTokenizer,
        );
        expect(result, '');
      },
    );

    test('preserves the front of the string, dropping the tail', () async {
      const text = 'keep-me-1 keep-me-2 keep-me-3 drop-me-4 drop-me-5';
      final result = await truncatePromptToTokenBudget(
        text,
        3,
        _wordCountTokenizer,
      );
      expect(result, 'keep-me-1 keep-me-2 keep-me-3');
    });
  });
}
