/// The chat request and answer of Smart Mode on the user's own
/// OpenAI-compatible server (W-M3, #1957). Pure functions, no I/O.
///
/// Checked against the servers people already run (Ollama, LM Studio,
/// llama.cpp `llama-server`, Jan, LocalAI, vLLM, text-generation-webui,
/// KoboldCpp, GPT4All):
/// - Reasoning models think before they answer. Most servers put that text in
///   a field of its own (`reasoning`, `reasoning_content`), some leave it in
///   the answer as `<think>…</think>` (llama.cpp with `--reasoning-format
///   none`, vLLM without a reasoning parser). It must never be pasted.
/// - Thinking costs seconds per dictation. `reasoning_effort: "none"` turns it
///   off on Ollama, llama.cpp, LM Studio and KoboldCpp (checked live) and on
///   vLLM (documented); a server that refuses the field gets
///   the request again without it.
/// - Without `max_tokens` some servers stop early (GPT4All after 16 tokens,
///   text-generation-webui after 512). A cut-off answer must not be pasted.
library;

/// `max_tokens` for a Smart Mode request on the own endpoint: room for an
/// answer about as long as the dictation (translations included) plus some
/// thinking, at least 1024 and at most 4096 so a server with a small context
/// does not refuse the request.
int customEndpointMaxTokens(String userText) =>
    (userText.length ~/ 2 + 512).clamp(1024, 4096);

/// The JSON body of a chat request to the own endpoint.
///
/// [thinkingOff] adds `reasoning_effort: "none"`; the caller drops it for a
/// server that refused it once.
Map<String, Object> customEndpointChatBody({
  required String model,
  required String systemPrompt,
  required String userText,
  required bool thinkingOff,
  int? maxTokens,
}) => {
  'model': model,
  'messages': [
    if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
    {'role': 'user', 'content': userText},
  ],
  'temperature': 0.3,
  'max_tokens': maxTokens ?? customEndpointMaxTokens(userText),
  'stream': false,
  if (thinkingOff) 'reasoning_effort': 'none',
};

/// Whether a refused request (400 or 422) may be retried without
/// `reasoning_effort`: only when the field was sent.
bool customEndpointRetryWithoutThinkingOff(int status, {required bool sent}) =>
    sent && (status == 400 || status == 422);

/// What a 200 answer of the own endpoint contained.
enum CustomEndpointChatOutcome {
  /// A usable answer in [CustomEndpointChatAnswer.text].
  answer,

  /// The server stopped at the token limit (`finish_reason: "length"`), so
  /// the answer is cut off or still in its thinking part.
  truncated,

  /// No choices or no text where an OpenAI-compatible answer has it.
  malformed,
}

class CustomEndpointChatAnswer {
  const CustomEndpointChatAnswer(this.outcome, [this.text = '']);

  final CustomEndpointChatOutcome outcome;

  /// The answer without any thinking text, trimmed. Empty unless [outcome] is
  /// [CustomEndpointChatOutcome.answer] (it may still be empty then, which the
  /// caller treats as a failed run).
  final String text;
}

/// Reads the decoded JSON of a 200 answer. Only `message.content` counts; the
/// separate thinking fields are never read.
CustomEndpointChatAnswer customEndpointChatAnswer(Object? json) {
  if (json is! Map || json['choices'] is! List) {
    return const CustomEndpointChatAnswer(CustomEndpointChatOutcome.malformed);
  }
  final choices = json['choices'] as List;
  final first = choices.isEmpty ? null : choices.first;
  if (first is! Map) {
    return const CustomEndpointChatAnswer(CustomEndpointChatOutcome.malformed);
  }
  if (first['finish_reason'] == 'length') {
    return const CustomEndpointChatAnswer(CustomEndpointChatOutcome.truncated);
  }
  final message = first['message'];
  final content = message is Map ? message['content'] : null;
  if (content != null && content is! String) {
    return const CustomEndpointChatAnswer(CustomEndpointChatOutcome.malformed);
  }
  return CustomEndpointChatAnswer(
    CustomEndpointChatOutcome.answer,
    stripReasoningText((content as String?) ?? ''),
  );
}

final RegExp _leadingBlock = RegExp(
  r'^\s*<(think|thinking|reasoning)>[\s\S]*?</\1>',
  caseSensitive: false,
);
final RegExp _leadingOpenTag = RegExp(
  r'^\s*<(think|thinking|reasoning)>',
  caseSensitive: false,
);
final RegExp _closeTag = RegExp(
  r'</(think|thinking|reasoning)>',
  caseSensitive: false,
);
const String _harmonyFinal = '<|channel|>final<|message|>';

/// [content] without the thinking a reasoning model left in its answer.
///
/// - Leading `<think>…</think>` blocks (also `<thinking>`, `<reasoning>`) go.
/// - An opening tag that never closes means the answer never came: empty.
/// - A closing tag without an opening one (the chat template opened the block
///   in the prompt, as with DeepSeek-R1 distills): everything up to the last
///   closing tag goes.
/// - The gpt-oss channel format keeps only its final channel.
String stripReasoningText(String content) {
  var text = content;
  final harmony = text.lastIndexOf(_harmonyFinal);
  if (harmony >= 0) {
    text = text.substring(harmony + _harmonyFinal.length);
    final end = text.indexOf('<|');
    if (end >= 0) text = text.substring(0, end);
  } else if (text.contains('<|channel|>')) {
    // Only the analysis channel arrived.
    return '';
  }
  while (true) {
    final match = _leadingBlock.firstMatch(text);
    if (match == null) break;
    text = text.substring(match.end);
  }
  if (_leadingOpenTag.hasMatch(text)) return '';
  final closes = _closeTag.allMatches(text).toList();
  if (closes.isNotEmpty) text = text.substring(closes.last.end);
  return text.trim();
}
