import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/secure_key_store.dart';
import '../../core/config/settings_provider.dart';
import '../audio/wav_header_repair.dart';
import '../stt/transcript_hallucination_filter.dart';
import 'cloud_request.dart';
import 'transcriber_interface.dart';

/// Keyterm limits of Deepgram's `keyterm` parameter (developers.deepgram.com,
/// "Keyterm prompting"): at most 500 tokens across all keyterms per request,
/// and the docs advise 20 to 50 terms. A token is never shorter than one byte
/// of the term's UTF-8 text, so a byte budget of 500 cannot exceed the limit.
const _keytermMaxCount = 50;
const _keytermByteBudget = 500;

/// Models that accept the `keyterm` parameter. Other models would use the
/// separate `keywords` feature, which this transcriber does not send.
const _keytermModels = {'nova-3'};

/// The custom vocabulary as Deepgram keyterms. The terms are split at commas
/// and line breaks (as the dictionary field asks), trimmed, and kept once
/// without regard to case. The first terms win: a term that would exceed a
/// limit is skipped, and later terms that fit still count.
List<String> deepgramKeyterms(String vocabulary) {
  final seen = <String>{};
  final terms = <String>[];
  var bytes = 0;
  for (final raw in vocabulary.split(RegExp(r'[,\r\n]'))) {
    final term = raw.trim();
    if (term.isEmpty || !seen.add(term.toLowerCase())) continue;
    if (terms.length >= _keytermMaxCount) break;
    final termBytes = utf8.encode(term).length;
    if (bytes + termBytes > _keytermByteBudget) continue;
    terms.add(term);
    bytes += termBytes;
  }
  return terms;
}

/// Calls the Deepgram Speech-to-Text REST API (`/v1/listen`).
///
/// Requires `deepgramApiKey` to be set in secure storage. The custom
/// vocabulary goes along as `keyterm` parameters (see [deepgramKeyterms]).
class DeepgramTranscriber implements Transcriber {
  /// [timeout] overrides the size-based timeout (tests only); without it each
  /// request gets [cloudRequestTimeout] for its own body.
  DeepgramTranscriber({
    required this.ref,
    this._httpClient,
    this._timeout,
    this.wait = _defaultWait,
  });

  final Ref ref;
  final http.Client? _httpClient;
  final Duration? _timeout;

  /// Waits between retries. Tests replace it so they do not sleep.
  final Future<void> Function(Duration delay) wait;

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

    // An unfinished recording goes up with its size fields repaired.
    final wav = repairWavHeader(wavBytes);

    final keyterms = _keytermModels.contains(_model)
        ? deepgramKeyterms(
            ref.read(settingsProvider).value?.customVocabulary ?? '',
          )
        : const <String>[];
    final queryParams = <String, Object>{
      'model': _model,
      'smart_format': 'true',
      // One `keyterm` parameter per term; Uri repeats the key for a list.
      if (keyterms.isNotEmpty) 'keyterm': keyterms,
      // Deepgram defaults an omitted `language` to English — auto-detect
      // must be requested explicitly via detect_language.
      if (language != null && language.isNotEmpty && language != 'auto')
        'language': language
      else
        'detect_language': 'true',
    };

    final uri = Uri.parse(_baseEndpoint).replace(queryParameters: queryParams);

    // One request for the whole recording; a transient failure repeats it.
    final response = await retryCloudRequest(
      () => _send(uri, key, wav),
      wait: wait,
    );

    switch (response.status) {
      case 200:
        final json = jsonDecode(response.body) as Map<String, dynamic>;
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
        throw TranscriberException(
          'Deepgram rate limit exceeded. Please wait and try again.',
          reason: TranscriberFailureReason.rateLimited,
          retryAfter: response.retryAfter,
        );
      default:
        if (response.status >= 500) {
          throw TranscriberException(
            'Deepgram server error (HTTP ${response.status}): ${response.body}',
            reason: TranscriberFailureReason.serverError,
            retryAfter: response.retryAfter,
          );
        }
        throw TranscriberException(
          'Deepgram API error (HTTP ${response.status}): ${response.body}',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  /// Builds and sends the request once. Every attempt builds its own, because
  /// a request can only be sent once.
  Future<CloudSttResponse> _send(Uri uri, String key, List<int> wav) async {
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Token $key'
      ..headers['Content-Type'] = 'audio/wav'
      // Pass the bytes straight through instead of copying via
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
      ..bodyBytes = wav;

    try {
      return await sendCloudSttRequest(
        request,
        timeout: _timeout ?? cloudRequestTimeout(wav.length),
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
  }

  @override
  void release() {}
}

Future<void> _defaultWait(Duration delay) => Future<void>.delayed(delay);
