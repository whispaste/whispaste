import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/custom_endpoint_rules.dart';
import '../../core/config/secure_key_store.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show CloudProviderSettings;
import '../audio/import/pcm_decoder.dart';
import '../audio/pcm16_pause_finder.dart';
import '../audio/wav_header_repair.dart';
import '../stt/transcript_hallucination_filter.dart';
import 'cloud_request.dart';
import 'continuity_guard.dart';
import 'transcript_seam.dart';
import 'transcriber_interface.dart';

/// Largest upload OpenAI accepts for `/v1/audio/transcriptions` is 25 MB; the
/// margin below it covers the multipart framing.
const int kOpenAiMaxUploadBytes = 24 * 1000 * 1000;

/// Longest upload slice for a recording that is too large for a single
/// request: 10 minutes of 16 kHz mono 16-bit PCM (about 19.2 MB). A slice may
/// end earlier, at a pause (see [_openAiPauseSearchBytes]), never later.
const int _openAiSliceBytes = 10 * 60 * 32000;

/// How far before the 10-minute limit a slice may end to land in a pause: the
/// latest pause of at least 700 ms in the last 20 s of the slice wins.
const int _openAiPauseSearchBytes = 20 * 32000;

/// Audio repeated at the start of the next slice after a hard cut (no pause
/// found): 2 s, so no word is lost at the seam. The repeated words are
/// removed from the next slice's text by [dropSeamRepeat].
const int _openAiHardCutOverlapBytes = 2 * 32000;

/// Where one upload goes and with which key and model. The OpenAI adapter
/// has a fixed address and a required key; the own endpoint (W-M3) takes both
/// from the settings and needs no key.
class _UploadTarget {
  const _UploadTarget({
    required this.uri,
    required this.key,
    required this.model,
    required this.custom,
  });

  final Uri uri;
  final String? key;
  final String model;
  final bool custom;
}

/// One upload of a split recording: [parts] in send order, which together
/// make up the request body of [length] bytes.
class WavUploadSlice {
  const WavUploadSlice(
    this.parts,
    this.length, {
    this.overlapsPrevious = false,
  });

  final List<Uint8List> parts;
  final int length;

  /// True when this slice starts with audio the previous slice already ends
  /// with (its boundary was a hard cut), so the text seam needs de-duplication.
  final bool overlapsPrevious;
}

/// Splits a WAV recording into uploads that each fit [kOpenAiMaxUploadBytes].
///
/// Recordings written by WhisPaste carry the canonical 44-byte header
/// (16 kHz, mono, 16-bit). A recording that already fits comes back as one
/// upload. Every longer one is cut into slices of whole samples. Each cut is
/// placed at the latest pause in the search window before the slice limit; a
/// hard cut at the limit overlaps the next slice by 2 s. A slice is its own
/// 44-byte header plus a view of the samples, so no slice copies the recording
/// (a copy per slice held the whole file twice in memory).
///
/// The split is a pure function of the audio bytes: the same recording always
/// yields the same slices, so the finished slices of an earlier attempt (the
/// manifest) match the retry.
List<WavUploadSlice> splitWavForUpload(List<int> wavBytes) {
  final wav = wavBytes is Uint8List ? wavBytes : Uint8List.fromList(wavBytes);
  if (wav.length <= kOpenAiMaxUploadBytes) {
    return [
      WavUploadSlice([wav], wav.length),
    ];
  }
  final pcmLength = wav.length - 44;
  final pcm = ByteData.sublistView(wav, 44);
  final slices = <WavUploadSlice>[];
  var start = 0;
  var overlaps = false;
  while (pcmLength - start > _openAiSliceBytes) {
    final limit = start + _openAiSliceBytes;
    final pause = findLatestPauseMidByte(
      pcm,
      limit - _openAiPauseSearchBytes,
      limit,
    );
    final end = pause ?? limit;
    slices.add(_sliceOf(wav, start, end, overlapsPrevious: overlaps));
    overlaps = pause == null;
    start = pause ?? end - _openAiHardCutOverlapBytes;
  }
  slices.add(_sliceOf(wav, start, pcmLength, overlapsPrevious: overlaps));
  return slices;
}

/// One slice over the PCM bytes `[start, end)` of [wav], as a header plus a
/// view (no copy).
WavUploadSlice _sliceOf(
  Uint8List wav,
  int start,
  int end, {
  required bool overlapsPrevious,
}) {
  final length = end - start;
  final samples = Uint8List.sublistView(wav, 44 + start, 44 + end);
  return WavUploadSlice(
    [wavHeaderPcm16Mono(length), samples],
    44 + length,
    overlapsPrevious: overlapsPrevious,
  );
}

/// Joins the slice texts in order. At a hard-cut seam the words the next text
/// repeats from the previous one are removed; a pause seam is joined as-is.
String joinSliceTexts(List<String> texts, List<WavUploadSlice> slices) =>
    joinSeamTexts(texts, [
      for (var i = 0; i < texts.length; i++)
        i < slices.length && slices[i].overlapsPrevious,
    ]);

/// The `prompt` field: the custom vocabulary, then the continuity text of the
/// previous slice ([carry]). Empty parts are dropped.
///
/// The carry is at most 200 characters (about 40 to 60 tokens, cut at a word
/// start; see [kContinuityContextChars]). It sits at the end of the prompt, so
/// it is the part a truncation of an overlong vocabulary would keep last.
String openAiPrompt(String? vocabulary, String? carry) => [vocabulary, carry]
    .whereType<String>()
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .join(' ');

/// Calls OpenAI's speech-to-text API (`/v1/audio/transcriptions`, model
/// `gpt-transcribe`; see ADR 0005).
///
/// Requires `openAiApiKey` to be set in secure storage. A recording over the
/// upload limit goes up in slices; a slice that fails with a transient error
/// is retried on its own (see [retryCloudRequest]), and a failure that
/// survives the retries reports the finished slices in
/// [TranscriberException.completedParts].
class OpenAiTranscriber implements Transcriber, ResumableTranscriber {
  OpenAiTranscriber({
    required this.ref,
    this.httpClient,
    this.wait = _defaultWait,
    this.custom = false,
  });

  /// The user's own OpenAI-compatible server (W-M3): address, optional key and
  /// model come from the settings, read at each request.
  OpenAiTranscriber.customEndpoint({
    required Ref ref,
    http.Client? httpClient,
    Future<void> Function(Duration delay) wait = _defaultWait,
  }) : this(ref: ref, httpClient: httpClient, wait: wait, custom: true);

  final Ref ref;
  final http.Client? httpClient;
  final bool custom;

  /// Waits between retries. Tests replace it so they do not sleep.
  final Future<void> Function(Duration delay) wait;

  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';
  // whisper-1 and gpt-4o(-mini)-transcribe are retired on 26 Feb 2027.
  static const _model = 'gpt-transcribe';

  Future<String?> get _apiKey async => ref
      .read(secureKeyStoreProvider)
      .readKey(custom ? 'wp_custom_endpoint_api_key' : 'wp_openai_api_key');

  /// Address, key and model of the next upload. The OpenAI key is required;
  /// the own endpoint needs an address and a model, the key is optional.
  Future<_UploadTarget> _target() async {
    if (!custom) {
      final key = await _apiKey;
      if (key == null || key.trim().isEmpty) {
        throw const TranscriberException(
          'OpenAI API key not set. Add your key in Settings → Speech recognition.',
          reason: TranscriberFailureReason.authError,
        );
      }
      return _UploadTarget(
        uri: Uri.parse(_endpoint),
        key: key,
        model: _model,
        custom: false,
      );
    }
    final cloud =
        ref.read(settingsProvider).value?.cloudProvider ??
        CloudProviderSettings.defaults;
    final check = checkCustomEndpointUrl(cloud.customEndpointUrl);
    final model = cloud.customEndpointSttModel.trim();
    if (!check.isValid || model.isEmpty) {
      throw const TranscriberException(
        'Own endpoint is not configured (address or model missing).',
        reason: TranscriberFailureReason.endpointNotConfigured,
      );
    }
    final key = (await _apiKey)?.trim();
    return _UploadTarget(
      uri: customEndpointUrl(check.uri!, '/audio/transcriptions'),
      key: key == null || key.isEmpty ? null : key,
      model: model,
      custom: true,
    );
  }

  @override
  Future<void> prepare() async {
    await _target();
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) =>
      transcribeResumable(wavBytes, language: language);

  @override
  Future<String> transcribeResumable(
    List<int> wavBytes, {
    String? language,
    List<String> completedParts = const [],
    bool Function()? isCancelled,
    SliceCheckpoint? onSliceDone,
  }) async {
    final target = await _target();

    // An unfinished recording goes up with its size fields repaired.
    final wav = repairWavHeader(wavBytes);

    // Long dictations go up in slices, one text per slice in slice order. The
    // split is deterministic, so finished slices of the same audio still match.
    final slices = splitWavForUpload(wav);
    final texts = completedParts.length <= slices.length
        ? [...completedParts]
        : <String>[];
    final sliced = slices.length > 1;
    // The finished slices are reported before the first request too, so a
    // resumed run shows its progress at once.
    if (sliced && onSliceDone != null) {
      await onSliceDone(List.unmodifiable(texts), slices.length);
    }
    for (var i = texts.length; i < slices.length; i++) {
      // The previous slice's stored text is the continuity context. A looping
      // slice carries nothing (see continuity_guard.dart). Stored texts are the
      // cleaned ones, so a retry derives the same context from the manifest.
      final carry = i > 0 ? continuityCarryFor(texts[i - 1]) : null;
      try {
        final text = await retryCloudRequest(
          () => _transcribeUpload(
            target,
            slices[i],
            language: language,
            carry: carry,
          ),
          isCancelled: isCancelled,
          wait: wait,
        );
        texts.add(carry == null ? text : stripPromptEcho(carry, text));
        if (sliced && onSliceDone != null) {
          await onSliceDone(List.unmodifiable(texts), slices.length);
        }
      } on TranscriberException catch (e) {
        throw TranscriberException(
          e.message,
          reason: e.reason,
          retryAfter: e.retryAfter,
          completedParts: List.unmodifiable(texts),
        );
      }
    }
    return joinSliceTexts(texts, slices);
  }

  Future<String> _transcribeUpload(
    _UploadTarget target,
    WavUploadSlice slice, {
    String? language,
    String? carry,
  }) async {
    final request = _uploadRequest(
      target,
      slice,
      language: language,
      carry: carry,
    );
    final key = target.key;
    if (key != null) request.headers['Authorization'] = 'Bearer $key';

    final CloudSttResponse response;
    try {
      response = await sendCloudSttRequest(
        request,
        timeout: cloudRequestTimeout(slice.length),
        client: httpClient,
      );
    } on TimeoutException {
      throw TranscriberException(
        target.custom
            ? 'Own endpoint request timed out.'
            : 'OpenAI request timed out.',
        reason: TranscriberFailureReason.timeout,
      );
    } on Exception catch (e) {
      if (target.custom) {
        throw TranscriberException(
          'Own endpoint not reachable (${e.runtimeType}).',
          reason: TranscriberFailureReason.endpointUnreachable,
        );
      }
      throw TranscriberException(
        'Network error: $e',
        reason: TranscriberFailureReason.networkError,
      );
    }

    if (target.custom && response.status != 200 && response.status != 429) {
      throw _customHttpFailure(response.status, response.body);
    }

    switch (response.status) {
      case 200:
        if (target.custom) {
          final text = _customTranscript(response.body);
          return isNonSpeechTranscript(text) ? '' : text;
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
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
        throw _rateLimitFailure(target, response);
      default:
        if (response.status >= 500) {
          throw TranscriberException(
            'OpenAI server error (HTTP ${response.status}).',
            reason: TranscriberFailureReason.serverError,
          );
        }
        // The body is not part of the message: it can echo the transcript,
        // and messages reach the log. Only a short error code is kept.
        final code = _apiErrorCode(response.body);
        final detail = code == null ? '' : ', code: $code';
        throw TranscriberException(
          'OpenAI API error (HTTP ${response.status}$detail).',
          reason: TranscriberFailureReason.unknown,
        );
    }
  }

  http.MultipartRequest _uploadRequest(
    _UploadTarget target,
    WavUploadSlice slice, {
    String? language,
    String? carry,
  }) {
    final request = http.MultipartRequest('POST', target.uri)
      ..fields['model'] = target.model
      ..fields['response_format'] = 'json'
      ..files.add(
        http.MultipartFile(
          'file',
          Stream<List<int>>.fromIterable(slice.parts),
          slice.length,
          filename: 'audio.wav',
        ),
      );

    // gpt-transcribe takes the array `languages` instead of `language`, and
    // the API rejects a request that carries both. The app sends one code, so
    // the single `languages[]` entry is the whole array.
    if (language != null && language.isNotEmpty && language != 'auto') {
      request.fields['languages[]'] = language;
    }

    // Custom Vocabulary (settings_sections.dart::SttSettings.customVocabulary)
    // — same field the on-device Whisper path feeds into whisper.cpp's
    // initial_prompt (stt_server_state_notifier.dart). OpenAI's `prompt`
    // field is documented for gpt-transcribe as unstructured context about
    // the recording. It biases style and vocabulary rather than acting as a
    // strict prefix. `keywords` (literal terms) exists too, but it rejects the
    // whole request on a `<`, `>` or line break, so it is not used here.
    final prompt = openAiPrompt(
      ref.read(settingsProvider).value?.customVocabulary,
      carry,
    );
    if (prompt.isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

    return request;
  }

  /// The transcript of an own-endpoint answer; anything else is a wrong format.
  static String _customTranscript(String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (json is Map && json['text'] is String) {
      return (json['text'] as String).trim();
    }
    throw const TranscriberException(
      'Own endpoint answered without a transcript.',
      reason: TranscriberFailureReason.badResponse,
    );
  }

  /// The error of a non-200 answer from the own endpoint. The body is not
  /// carried into the message, so it cannot leak into logs.
  /// The same status code carries a billing limit (not retried) and a rate
  /// limit (retried, the audio is kept if it still fails); the body tells them
  /// apart. Own-endpoint texts name no provider.
  static TranscriberException _rateLimitFailure(
    _UploadTarget target,
    CloudSttResponse response,
  ) {
    if (response.body.contains('insufficient_quota')) {
      return TranscriberException(
        target.custom
            ? 'Own endpoint quota used up.'
            : 'OpenAI quota used up. Check the billing settings.',
        reason: TranscriberFailureReason.quotaExceeded,
      );
    }
    return TranscriberException(
      target.custom
          ? 'Own endpoint rate limit exceeded.'
          : 'OpenAI rate limit exceeded. Please wait and try again.',
      reason: TranscriberFailureReason.rateLimited,
      retryAfter: response.retryAfter,
    );
  }

  /// The short error code an API answers with (`{"error": {"code": …}}`), or
  /// null. Only a plain identifier is kept, so no free text leaves the body.
  static String? _apiErrorCode(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    final error = decoded is Map ? decoded['error'] : null;
    final code = error is Map ? (error['code'] ?? error['type']) : null;
    if (code is String && RegExp(r'^[a-z_]{1,40}$').hasMatch(code)) {
      return code;
    }
    return null;
  }

  static TranscriberException _customHttpFailure(int status, String body) {
    final (reason, text) = switch (customEndpointHttpClass(status, body)) {
      CustomEndpointHttpClass.unauthorized => (
        TranscriberFailureReason.authError,
        'Own endpoint refused the key',
      ),
      CustomEndpointHttpClass.modelMissing => (
        TranscriberFailureReason.modelMissing,
        'Own endpoint has no such model',
      ),
      CustomEndpointHttpClass.badFormat => (
        TranscriberFailureReason.badResponse,
        'Own endpoint answered in an unexpected format',
      ),
      CustomEndpointHttpClass.serverError => (
        TranscriberFailureReason.serverError,
        'Own endpoint server error',
      ),
    };
    return TranscriberException('$text (HTTP $status).', reason: reason);
  }

  @override
  void release() {}
}

Future<void> _defaultWait(Duration delay) => Future<void>.delayed(delay);
