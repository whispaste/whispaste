/// Cloud LLM provider implementations for post-processing.
///
/// Each provider wraps a single cloud API (OpenAI, Anthropic, Groq, Gemini)
/// behind a common [CloudLlmProvider] interface. The providers use the
/// OpenAI-compatible chat completions format wherever possible.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/settings_enums.dart';
import '../core/logging/app_logger.dart';
import 'llm_prompts.dart' as prompts;

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Common interface for cloud LLM providers.
abstract class CloudLlmProvider {
  /// Sends [text] through the given [preset] and returns processed text.
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  });

  /// Suggests tags for [text].
  Future<List<String>> suggestTags(String text);

  /// Suggests a title for [text].
  Future<String> suggestTitle(String text);
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// Creates the appropriate [CloudLlmProvider] for the given settings.
///
/// Throws [ArgumentError] if no API key is configured for the provider.
CloudLlmProvider createCloudProvider({
  required PostProcessProviderType provider,
  required String apiKey,
  required String model,
}) {
  if (apiKey.isEmpty) {
    throw ArgumentError('No API key configured for ${provider.value}');
  }

  return switch (provider) {
    PostProcessProviderType.openAI => _OpenAiProvider(apiKey: apiKey, model: model),
    PostProcessProviderType.anthropic => _AnthropicProvider(apiKey: apiKey, model: model),
    PostProcessProviderType.groq => _GroqProvider(apiKey: apiKey, model: model),
    PostProcessProviderType.gemini => _GeminiProvider(apiKey: apiKey, model: model),
    PostProcessProviderType.local => throw ArgumentError('Local is not a cloud provider'),
  };
}

/// Default model per provider when the user hasn't configured one.
String defaultModelFor(PostProcessProviderType provider) {
  return switch (provider) {
    PostProcessProviderType.openAI => 'gpt-4o-mini',
    PostProcessProviderType.anthropic => 'claude-sonnet-4-20250514',
    PostProcessProviderType.groq => 'llama-3.3-70b-versatile',
    PostProcessProviderType.gemini => 'gemini-2.0-flash',
    PostProcessProviderType.local => '',
  };
}

// ---------------------------------------------------------------------------
// OpenAI-compatible base (shared by OpenAI + Groq)
// ---------------------------------------------------------------------------

final _log = AppLogger('CloudLlm');

abstract class _OpenAiCompatibleProvider implements CloudLlmProvider {
  _OpenAiCompatibleProvider({
    required this.apiKey,
    required String model,
    required this.baseUrl,
    required this.defaultModel,
    required this.providerName,
  }) : model = model.isNotEmpty ? model : defaultModel;

  final String apiKey;
  final String model;
  final String baseUrl;
  final String defaultModel;
  final String providerName;

  final http.Client _client = http.Client();

  Future<String> _chatCompletion({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.3,
    int maxTokens = 2048,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
    });

    _log.info('$providerName request: model=$model, inputLen=${userMessage.length}');
    final sw = Stopwatch()..start();

    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    ).timeout(const Duration(seconds: 60));

    sw.stop();
    _log.info(
      '$providerName response: status=${response.statusCode}, '
      'duration=${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      throw HttpException(
        '$providerName API error (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('No choices in API response');
    }

    final message = (choices[0] as Map<String, dynamic>)['message']
        as Map<String, dynamic>;
    return ((message['content'] as String?) ?? '').trim();
  }

  @override
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    final sysPrompt = prompts.systemPrompt(preset, targetLang: targetLang);
    final temp = prompts.temperatureFor(preset);
    return _chatCompletion(
      systemPrompt: sysPrompt,
      userMessage: text,
      temperature: temp,
    );
  }

  @override
  Future<List<String>> suggestTags(String text) async {
    final result = await _chatCompletion(
      systemPrompt: prompts.tagSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 100,
    );
    return result
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  @override
  Future<String> suggestTitle(String text) async {
    return _chatCompletion(
      systemPrompt: prompts.titleSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 50,
    );
  }
}

// ---------------------------------------------------------------------------
// OpenAI
// ---------------------------------------------------------------------------

class _OpenAiProvider extends _OpenAiCompatibleProvider {
  _OpenAiProvider({required super.apiKey, required super.model})
      : super(
          baseUrl: 'https://api.openai.com/v1',
          defaultModel: 'gpt-4o-mini',
          providerName: 'OpenAI',
        );
}

// ---------------------------------------------------------------------------
// Groq
// ---------------------------------------------------------------------------

class _GroqProvider extends _OpenAiCompatibleProvider {
  _GroqProvider({required super.apiKey, required super.model})
      : super(
          baseUrl: 'https://api.groq.com/openai/v1',
          defaultModel: 'llama-3.3-70b-versatile',
          providerName: 'Groq',
        );
}

// ---------------------------------------------------------------------------
// Anthropic (Messages API)
// ---------------------------------------------------------------------------

class _AnthropicProvider implements CloudLlmProvider {
  _AnthropicProvider({required this.apiKey, required String model})
      : model = model.isNotEmpty ? model : 'claude-sonnet-4-20250514';

  final String apiKey;
  final String model;
  final http.Client _client = http.Client();

  Future<String> _messagesRequest({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.3,
    int maxTokens = 2048,
  }) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userMessage},
      ],
      'temperature': temperature,
    });

    _log.info('Anthropic request: model=$model, inputLen=${userMessage.length}');
    final sw = Stopwatch()..start();

    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    ).timeout(const Duration(seconds: 60));

    sw.stop();
    _log.info(
      'Anthropic response: status=${response.statusCode}, '
      'duration=${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Anthropic API error (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = json['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw const FormatException('No content in Anthropic response');
    }

    final textBlock = content[0] as Map<String, dynamic>;
    return ((textBlock['text'] as String?) ?? '').trim();
  }

  @override
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    final sysPrompt = prompts.systemPrompt(preset, targetLang: targetLang);
    final temp = prompts.temperatureFor(preset);
    return _messagesRequest(
      systemPrompt: sysPrompt,
      userMessage: text,
      temperature: temp,
    );
  }

  @override
  Future<List<String>> suggestTags(String text) async {
    final result = await _messagesRequest(
      systemPrompt: prompts.tagSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 100,
    );
    return result
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  @override
  Future<String> suggestTitle(String text) async {
    return _messagesRequest(
      systemPrompt: prompts.titleSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 50,
    );
  }
}

// ---------------------------------------------------------------------------
// Gemini (Google AI Studio / Generative Language API)
// ---------------------------------------------------------------------------

class _GeminiProvider implements CloudLlmProvider {
  _GeminiProvider({required this.apiKey, required String model})
      : model = model.isNotEmpty ? model : 'gemini-2.0-flash';

  final String apiKey;
  final String model;
  final http.Client _client = http.Client();

  Future<String> _generateContent({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.3,
    int maxTokens = 2048,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'parts': [
            {'text': userMessage},
          ],
        },
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    });

    _log.info('Gemini request: model=$model, inputLen=${userMessage.length}');
    final sw = Stopwatch()..start();

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 60));

    sw.stop();
    _log.info(
      'Gemini response: status=${response.statusCode}, '
      'duration=${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Gemini API error (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const FormatException('No candidates in Gemini response');
    }

    final content =
        (candidates[0] as Map<String, dynamic>)['content'] as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw const FormatException('No parts in Gemini response');
    }

    return ((parts[0] as Map<String, dynamic>)['text'] as String? ?? '').trim();
  }

  @override
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    final sysPrompt = prompts.systemPrompt(preset, targetLang: targetLang);
    final temp = prompts.temperatureFor(preset);
    return _generateContent(
      systemPrompt: sysPrompt,
      userMessage: text,
      temperature: temp,
    );
  }

  @override
  Future<List<String>> suggestTags(String text) async {
    final result = await _generateContent(
      systemPrompt: prompts.tagSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 100,
    );
    return result
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  @override
  Future<String> suggestTitle(String text) async {
    return _generateContent(
      systemPrompt: prompts.titleSuggestionPrompt,
      userMessage: text,
      temperature: prompts.suggestionTemperature,
      maxTokens: 50,
    );
  }
}
