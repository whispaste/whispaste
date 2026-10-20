import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import '../stt/transcript_hallucination_filter.dart';
import 'cloud_request.dart';
import 'transcriber_interface.dart';

/// Calls the Deepgram Speech-to-Text REST API (`/v1/listen`).
///
/// Requires `deepgramApiKey` to be set in secure storage.
class DeepgramTranscriber implements Transcriber {
  DeepgramTranscriber({required this.ref, this._httpClient, Duration? timeout})
    : _timeout = timeout ?? const Duration(seconds: 60);

  final Ref ref;
  final http.Client? _httpClient;
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
        'Deepgram API key not set. Add your key in Settings → Speech recognition.',
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
      // Pass wavBytes straight through instead of copying via
      // `List<int>.from()` first: the http package's `bodyBytes` setter
      // already skips its own copy when it receives a Uint8List (which is
      // what File.readAsBytes() hands us). The removed `List<int>.from()`
      // call was doubly wasteful: it produced a *growable* `List<int>` of
      // boxed/tagged words (~8 bytes per element instead of 1, so a 10MB WAV
      // became an ~80MB transient allocation), and the setter then had to
      // copy that back into a fresh Uint8List anyway since a plain List
      // isn't one. Measured ~120ms of synchronous main-isolate work (plus
      // the resulting GC pressure) for a 10MB / ~5min WAV clip, right before
      // the network send — on the Hotkey→Text critical path.
      ..bodyBytes = wavBytes;

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
        'Deepgram request timed out.',
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
        final channels =
            (json['results'] as Map<String, dynamic>?)?['channels']
                as List<dynamic>?;
        final alternatives =
            (channels?.firstOrNull as Map<String, dynamic>?)?['alternatives']
                as List<dynamic>?;
        final transcript =
            (alternatives?.firstOrNull as Map<String, dynamic>?)?['transcript']
                as String?;
        final text = (transcript ?? '').trim();
        // Same silence artefacts the on-device path drops (stock phrases,
        // a lone sound annotation); empty reads as a blank recording.
        return isNonSpeechTranscript(text) ? '' : text;
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
          'Deepgram API error (HTTP $status): $body',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  @override
  void release() {}
}
