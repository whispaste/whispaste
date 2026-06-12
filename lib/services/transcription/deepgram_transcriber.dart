import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import 'transcriber_interface.dart';

/// Calls the Deepgram Speech-to-Text REST API (`/v1/listen`).
///
/// Requires `deepgramApiKey` to be set in secure storage.
class DeepgramTranscriber implements Transcriber {
  DeepgramTranscriber({
    required this.ref,
    http.Client? httpClient,
    Duration? timeout,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _timeout = timeout ?? const Duration(seconds: 60);

  final Ref ref;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  static const _baseEndpoint = 'https://api.deepgram.com/v1/listen';
  static const _model = 'nova-3';

  Future<String?> get _apiKey async =>
      ref.read(secureKeyStoreProvider).readKey('wp_deepgram_api_key');

  @override
  Future<void> prepare() async {
    final key = await _apiKey;
    if (key == null || key.trim().isEmpty) {
      throw const TranscriberException(
        'Deepgram API key not set. Add your key in Settings → Cloud Providers.',
        reason: TranscriberFailureReason.authError,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    final key = await _apiKey;
    if (key == null || key.trim().isEmpty) {
      throw const TranscriberException(
        'Deepgram API key not set.',
        reason: TranscriberFailureReason.authError,
      );
    }

    final queryParams = <String, String>{
      'model': _model,
      'smart_format': 'true',
      // Deepgram defaults an omitted `language` to English — auto-detect
      // must be requested explicitly via detect_language.
      if (language != null && language.isNotEmpty && language != 'auto')
        'language': language
      else
        'detect_language': 'true',
    };

    final uri = Uri.parse(_baseEndpoint).replace(queryParameters: queryParams);

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Token $key'
      ..headers['Content-Type'] = 'audio/wav'
      ..bodyBytes = List<int>.from(wavBytes);

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const TranscriberException(
        'Deepgram request timed out.',
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
        final channels =
            (json['results'] as Map<String, dynamic>?)?['channels']
                as List<dynamic>?;
        final alternatives =
            (channels?.firstOrNull as Map<String, dynamic>?)?['alternatives']
                as List<dynamic>?;
        final transcript =
            (alternatives?.firstOrNull as Map<String, dynamic>?)?['transcript']
                as String?;
        return (transcript ?? '').trim();
      case 401:
        throw const TranscriberException(
          'Deepgram API key is invalid or expired.',
          reason: TranscriberFailureReason.authError,
        );
      case 429:
        throw const TranscriberException(
          'Deepgram rate limit exceeded. Please wait and try again.',
          reason: TranscriberFailureReason.quotaExceeded,
        );
      default:
        throw TranscriberException(
          'Deepgram API error (HTTP ${streamed.statusCode}): $body',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  @override
  void release() {
    if (_ownsClient) _client.close();
  }
}
