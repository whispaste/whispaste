/// Cloud [SmartModeEngine] backed by OpenAI's Chat Completions API — the
/// only cloud provider for Smart Mode v1 (see
/// `docs/adr/0010-smart-mode-lokal-oder-cloud-nur-openai.md`). Mirrors
/// [OpenAiTranscriber]'s HTTP/error-handling shape and reuses the same
/// secure-storage API key (`wp_openai_api_key`, shared with Cloud STT — one
/// OpenAI key for the whole app, not a separate Smart-Mode-specific one).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import 'smart_mode_engine.dart';

/// Real cloud [SmartModeEngine] — [RecordingOrchestrator]/
/// [SmartModeRetroactiveService] read this via [Ref.read] exactly like
/// [SmartModeFfiEngine], never watch it (stateless per call).
class SmartModeOpenAiEngine implements SmartModeEngine {
  SmartModeOpenAiEngine({required this.ref, http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final Ref ref;
  final http.Client _client;

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';
  static const _timeout = Duration(seconds: 20);

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    final key = await ref
        .read(secureKeyStoreProvider)
        .readKey('wp_openai_api_key');
    if (key == null || key.trim().isEmpty) {
      throw StateError('smart_mode_openai_api_key_missing');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0.3,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError('smart_mode_openai_timeout');
    } on Exception catch (e) {
      throw StateError('smart_mode_openai_network_error: $e');
    }

    switch (response.statusCode) {
      case 200:
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        final firstChoice = (choices != null && choices.isNotEmpty)
            ? choices.first as Map<String, dynamic>
            : null;
        final content = firstChoice?['message'] as Map<String, dynamic>?;
        return (content?['content'] as String? ?? '').trim();
      case 401:
        throw StateError('smart_mode_openai_invalid_api_key');
      case 429:
        throw StateError('smart_mode_openai_rate_limited');
      default:
        throw StateError(
          'smart_mode_openai_error_${response.statusCode}: ${response.body}',
        );
    }
  }
}
