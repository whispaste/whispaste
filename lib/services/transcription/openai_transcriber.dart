import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import 'transcriber_interface.dart';

/// Calls OpenAI Whisper API (`/v1/audio/transcriptions`).
///
/// Requires `openAiApiKey` to be set in secure storage.
class OpenAiTranscriber implements Transcriber {
  OpenAiTranscriber({required this.ref, http.Client? httpClient})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final Ref ref;
  final http.Client _client;
  final bool _ownsClient;

  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';
  static const _model = 'whisper-1';
  static const _timeout = Duration(seconds: 60);

  Future<String?> get _apiKey async =>
      ref.read(secureKeyStoreProvider).readKey('wp_openai_api_key');

  @override
  Future<void> prepare() async {
    final key = await _apiKey;
    if (key == null || key.trim().isEmpty) {
      throw const TranscriberException(
        'OpenAI API key not set. Add your key in Settings → Cloud Providers.',
        reason: TranscriberFailureReason.authError,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    final key = await _apiKey;
    if (key == null || key.trim().isEmpty) {
      throw const TranscriberException(
        'OpenAI API key not set.',
        reason: TranscriberFailureReason.authError,
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $key'
      ..fields['model'] = _model
      ..fields['response_format'] = 'json'
      ..files.add(
        http.MultipartFile.fromBytes('file', wavBytes, filename: 'audio.wav'),
      );

    if (language != null && language.isNotEmpty && language != 'auto') {
      request.fields['language'] = language;
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const TranscriberException(
        'OpenAI request timed out.',
        reason: TranscriberFailureReason.timeout,
      );
    } on Exception catch (e) {
      throw TranscriberException(
        'Network error: $e',
        reason: TranscriberFailureReason.networkError,
      );
    }

    final body = await streamed.stream.bytesToString();

    switch (streamed.statusCode) {
      case 200:
        final json = jsonDecode(body) as Map<String, dynamic>;
        return (json['text'] as String? ?? '').trim();
      case 401:
        throw const TranscriberException(
          'OpenAI API key is invalid or expired.',
          reason: TranscriberFailureReason.authError,
        );
      case 429:
        throw const TranscriberException(
          'OpenAI rate limit exceeded. Please wait and try again.',
          reason: TranscriberFailureReason.quotaExceeded,
        );
      default:
        throw TranscriberException(
          'OpenAI API error (HTTP ${streamed.statusCode}): $body',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  @override
  void release() {
    if (_ownsClient) _client.close();
  }
}
