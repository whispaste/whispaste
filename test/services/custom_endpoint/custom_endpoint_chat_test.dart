/// Request and answer rules of Smart Mode on the user's own server (#1957):
/// thinking text never reaches the paste, a cut-off answer is no answer, and
/// every request carries a token limit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_chat.dart';

Map<String, Object?> _answer(
  String? content, {
  String finish = 'stop',
  Map<String, Object?> extra = const {},
}) => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content, ...extra},
      'finish_reason': finish,
    },
  ],
};

void main() {
  group('stripReasoningText', () {
    test('keeps a plain answer, trimmed', () {
      expect(stripReasoningText('\n\nHallo Welt.\n'), 'Hallo Welt.');
    });

    test('drops a leading think block (llama.cpp --reasoning-format none)', () {
      expect(
        stripReasoningText(
          '<think>\nOkay, the user wants…\n</think>\n\nHallo.',
        ),
        'Hallo.',
      );
    });

    test('drops thinking and reasoning variants and several blocks', () {
      expect(
        stripReasoningText('<Thinking>a</Thinking><reasoning>b</reasoning> X'),
        'X',
      );
    });

    test('an unclosed think block means no answer', () {
      expect(stripReasoningText('<think>\nStill thinking about'), '');
    });

    test('a closing tag without an opening one drops what came before it', () {
      // DeepSeek-R1 distills: the template opens the block in the prompt.
      expect(
        stripReasoningText('Let me see…\n</think>\n\nDas Meeting.'),
        'Das Meeting.',
      );
    });

    test('the gpt-oss channel format keeps only the final channel', () {
      expect(
        stripReasoningText(
          '<|channel|>analysis<|message|>We should clean.<|end|>'
          '<|start|>assistant<|channel|>final<|message|>Sauber.<|return|>',
        ),
        'Sauber.',
      );
      expect(
        stripReasoningText('<|channel|>analysis<|message|>Only thinking'),
        '',
      );
    });
  });

  group('customEndpointChatAnswer', () {
    test('reads only the content, never the separate thinking fields', () {
      final answer = customEndpointChatAnswer(
        _answer(
          'Clean text.',
          extra: {'reasoning_content': 'secret', 'reasoning': 'secret'},
        ),
      );
      expect(answer.outcome, CustomEndpointChatOutcome.answer);
      expect(answer.text, 'Clean text.');
    });

    test('an answer cut off at the token limit is not an answer', () {
      final answer = customEndpointChatAnswer(
        _answer('Das Meeting ist mor', finish: 'length'),
      );
      expect(answer.outcome, CustomEndpointChatOutcome.truncated);
      expect(answer.text, isEmpty);
    });

    test('no choices or a non-text content is malformed', () {
      expect(
        customEndpointChatAnswer({'choices': []}).outcome,
        CustomEndpointChatOutcome.malformed,
      );
      expect(
        customEndpointChatAnswer({'error': 'x'}).outcome,
        CustomEndpointChatOutcome.malformed,
      );
      expect(
        customEndpointChatAnswer(_answer(null, extra: {'content': 3})).outcome,
        CustomEndpointChatOutcome.malformed,
      );
    });

    test('only thinking in the answer gives an empty text', () {
      final answer = customEndpointChatAnswer(_answer('<think>hmm</think>'));
      expect(answer.outcome, CustomEndpointChatOutcome.answer);
      expect(answer.text, isEmpty);
    });
  });

  group('customEndpointChatBody', () {
    test('turns thinking off, limits tokens and never streams', () {
      final body = customEndpointChatBody(
        model: 'qwen3:0.6b',
        systemPrompt: 'Clean up.',
        userText: 'ähm hallo',
        thinkingOff: true,
      );
      expect(body['model'], 'qwen3:0.6b');
      expect(body['reasoning_effort'], 'none');
      expect(body['stream'], false);
      expect(body['max_tokens'], 1024);
      expect(body['messages'], [
        {'role': 'system', 'content': 'Clean up.'},
        {'role': 'user', 'content': 'ähm hallo'},
      ]);
    });

    test('a server that refused the field gets no reasoning_effort', () {
      final body = customEndpointChatBody(
        model: 'm',
        systemPrompt: '',
        userText: 'OK',
        thinkingOff: false,
        maxTokens: 1,
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body['max_tokens'], 1);
      expect(body['messages'], [
        {'role': 'user', 'content': 'OK'},
      ]);
    });

    test('the token limit grows with the dictation and stays bounded', () {
      expect(customEndpointMaxTokens(''), 1024);
      expect(customEndpointMaxTokens('x' * 3000), 2012);
      expect(customEndpointMaxTokens('x' * 100000), 4096);
    });

    test('only a refused request that carried the field is retried', () {
      expect(customEndpointRetryWithoutThinkingOff(400, sent: true), isTrue);
      expect(customEndpointRetryWithoutThinkingOff(422, sent: true), isTrue);
      expect(customEndpointRetryWithoutThinkingOff(400, sent: false), isFalse);
      expect(customEndpointRetryWithoutThinkingOff(404, sent: true), isFalse);
      expect(customEndpointRetryWithoutThinkingOff(500, sent: true), isFalse);
    });
  });
}
