import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import '../../core/config/settings_provider.dart';
import '../stt/transcript_hallucination_filter.dart';
import 'cloud_request.dart';
import 'transcriber_interface.dart';

/// Calls OpenAI Whisper API (`/v1/audio/transcriptions`).
///
/// Requires `openAiApiKey` to be set in secure storage.
class OpenAiTranscriber implements Transcriber {
  OpenAiTranscriber({required this.ref, this._httpClient});

  final Ref ref;
  final http.Client? _httpClient;

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
        'OpenAI API key not set. Add your key in Settings → Speech recognition.',
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

    // Custom Vocabulary (settings_sections.dart::SttSettings.customVocabulary)
    // — same field the on-device Whisper path feeds into whisper.cpp's
    // initial_prompt (stt_server_state_notifier.dart). OpenAI's
    // /v1/audio/transcriptions accepts an equivalent free-text `prompt`
    // field for whisper-1 (and gpt-4o(-mini)-transcribe): it biases the
    // model's style/vocabulary rather than acting as a strict prefix, but
    // is functionally the same lever users configure once in Settings.
    final vocabulary = ref
        .read(settingsProvider)
        .value
        ?.customVocabulary
        .trim();
    if (vocabulary != null && vocabulary.isNotEmpty) {
      request.fields['prompt'] = vocabulary;
    }

    final int status;
    final String body;
    try {
      (status, body) = await sendCloudSttRequest(
        request,
        timeout: _timeout,
        client: _httpClient,
      );
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

    switch (status) {
      case 200:
        final json = jsonDecode(body) as Map<String, dynamic>;
        final text = (json['text'] as String? ?? '').trim();
        // Same silence artefacts the on-device path drops (stock phrases,
        // a lone sound annotation); empty reads as a blank recording.
        return isNonSpeechTranscript(text) ? '' : text;
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
          'OpenAI API error (HTTP $status): $body',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  @override
  void release() {}
}
