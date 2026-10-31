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

import '../../core/config/custom_endpoint_rules.dart';
import '../../core/config/secure_key_store.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show CloudProviderSettings;
import 'smart_mode_engine.dart';

/// Address, optional key and model of one Smart Mode request.
class _ChatTarget {
  const _ChatTarget(this.uri, this.key, this.model);

  final Uri uri;
  final String? key;
  final String model;
}

/// Real cloud [SmartModeEngine] — [RecordingOrchestrator]/
/// [SmartModeRetroactiveService] read this via [Ref.read] exactly like
/// [SmartModeFfiEngine], never watch it (stateless per call).
class SmartModeOpenAiEngine implements SmartModeEngine {
  SmartModeOpenAiEngine({required this.ref, http.Client? httpClient})
    : _client = httpClient ?? http.Client(),
      _custom = false;

  /// The user's own OpenAI-compatible server (W-M3): address, optional key and
  /// model come from the settings, read at each call.
  SmartModeOpenAiEngine.customEndpoint({
    required this.ref,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client(),
       _custom = true;

  final Ref ref;
  final http.Client _client;
  final bool _custom;

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';
  static const _timeout = Duration(seconds: 20);

  /// The OpenAI target needs its key; the own endpoint needs an address and a
  /// model, and the key is optional.
  Future<_ChatTarget> _target() async {
    if (!_custom) {
      final key = await ref
          .read(secureKeyStoreProvider)
          .readKey('wp_openai_api_key');
      if (key == null || key.trim().isEmpty) {
        throw StateError('smart_mode_openai_api_key_missing');
      }
      return _ChatTarget(Uri.parse(_endpoint), key, _model);
    }
    final cloud =
        ref.read(settingsProvider).value?.cloudProvider ??
        CloudProviderSettings.defaults;
    final check = checkCustomEndpointUrl(cloud.customEndpointUrl);
    final model = cloud.customEndpointSmartModel.trim();
    if (!check.isValid || model.isEmpty) {
      throw StateError('smart_mode_custom_not_configured');
    }
    final key =
        (await ref
                .read(secureKeyStoreProvider)
                .readKey('wp_custom_endpoint_api_key'))
            ?.trim();
    return _ChatTarget(
      customEndpointUrl(check.uri!, '/chat/completions'),
      key == null || key.isEmpty ? null : key,
      model,
    );
  }

  /// No-op: a cloud request holds no local compute, and it is already
  /// bounded by [_timeout].
  @override
  Future<void> cancel() async {}

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    final target = await _target();

    final http.Response response;
    try {
      response = await _client
          .post(
            target.uri,
            headers: {
              if (target.key != null) 'Authorization': 'Bearer ${target.key}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': target.model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0.3,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError(
        _custom ? 'smart_mode_custom_timeout' : 'smart_mode_openai_timeout',
      );
    } on Exception catch (e) {
      if (_custom) throw StateError('smart_mode_custom_unreachable');
      throw StateError('smart_mode_openai_network_error: $e');
    }

    if (_custom && response.statusCode != 200 && response.statusCode != 429) {
      throw _customFailure(response.statusCode, response.body);
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

  /// The error code of a non-200 answer from the own endpoint. The body stays
  /// out of the code, so it cannot reach the logs.
  static StateError _customFailure(int status, String body) => StateError(
    switch (customEndpointHttpClass(status, body)) {
      CustomEndpointHttpClass.unauthorized => 'smart_mode_custom_unauthorized',
      CustomEndpointHttpClass.modelMissing => 'smart_mode_custom_model_missing',
      CustomEndpointHttpClass.badFormat => 'smart_mode_custom_bad_format',
      CustomEndpointHttpClass.serverError => 'smart_mode_custom_server_error',
    },
  );
}
