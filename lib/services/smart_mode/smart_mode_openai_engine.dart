/// Cloud [SmartModeEngine] backed by OpenAI's Chat Completions API — the
/// only cloud provider for Smart Mode v1 (see
/// `internal-notes`). Mirrors
/// [OpenAiTranscriber]'s HTTP/error-handling shape and reuses the same
/// secure-storage API key (`wp_openai_api_key`, shared with Cloud STT — one
/// OpenAI key for the whole app, not a separate Smart-Mode-specific one).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/custom_endpoint_rules.dart';
import '../../core/config/secure_key_store.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show CloudProviderSettings;
import '../../core/logging/app_logger.dart';
import '../custom_endpoint/custom_endpoint_chat.dart';
import 'smart_mode_engine.dart';

final _log = AppLogger('SmartModeOpenAi');

/// Address, optional key and model of one Smart Mode request.
class _ChatTarget {
  const _ChatTarget(this.uri, this.key, this.model, {this.base});

  final Uri uri;
  final String? key;
  final String model;

  /// The own endpoint's API base; null for OpenAI.
  final Uri? base;
}

/// Real cloud [SmartModeEngine] — [RecordingOrchestrator]/
/// [SmartModeRetroactiveService] read this via [Ref.read] exactly like
/// [SmartModeFfiEngine], never watch it (stateless per call).
class SmartModeOpenAiEngine implements SmartModeEngine, SmartWriteEngine {
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

  /// `gpt-4o-mini` is shut down on 2027-01-14; `gpt-6-luna` is its
  /// successor at a lower price (ADR 0010).
  static const _model = 'gpt-6-luna';

  /// The OpenAI model Smart Mode asks, named in the notice when the key may
  /// not use it (#2116).
  static const openAiModel = _model;

  /// Cleanup budget, unchanged by #251.
  static const _timeout = Duration(seconds: 20);

  /// Write budget (#251): a whole text takes longer than a cleanup.
  static const _writeTimeout = Duration(seconds: 30);

  /// Output limit of a write job (#251): room for a long letter; a longer
  /// answer is cut off (`finish_reason: length`) and counts as failed.
  static const _writeMaxTokens = 2048;

  /// Output limit of a structured snippet choice (#252): a short JSON object.
  static const _choiceMaxTokens = 128;

  /// How long a warm-up request may take: a large model can need this long to
  /// load from disk, and nobody waits for it.
  static const _warmUpTimeout = Duration(seconds: 120);

  /// A warm-up is skipped when the server answered this recently: Ollama keeps
  /// a model loaded for 5 minutes, LM Studio for 60.
  static const _warmUpInterval = Duration(minutes: 1);

  /// API bases of own endpoints that refused `reasoning_effort` (400/422).
  /// Kept for the app session, so such a server gets one refused request, not
  /// one per dictation.
  static final Set<String> _refusesThinkingOff = {};

  /// When the own endpoint last answered or a warm-up started.
  DateTime? _lastContact;

  /// Test hook for the clock of [_lastContact].
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// Forgets which servers refused `reasoning_effort`. Tests only.
  @visibleForTesting
  static void resetThinkingOffMemory() => _refusesThinkingOff.clear();

  /// The OpenAI target needs its key; the own endpoint needs an address and a
  /// model, and the key is optional.
  Future<_ChatTarget> _target() =>
      withSecureTrigger('smart mode', _resolveTarget);

  Future<_ChatTarget> _resolveTarget() async {
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
      base: check.uri,
    );
  }

  /// Loads the model of the own endpoint ahead of the dictation (#1957).
  ///
  /// Ollama, LM Studio and others load a model on its first request and drop
  /// it after some idle minutes; a large model then needs longer to load than
  /// Smart Mode waits. Called when a recording with Smart Mode starts, this
  /// sends a one-token request with no dictated text, so the model is ready
  /// when the text arrives. Only for a server on this device or in the local
  /// network (a hosted provider keeps its models loaded and may bill each
  /// request), at most once a minute, and never with an error: a failure here
  /// shows up on the real request.
  Future<void> warmUp() async {
    if (!_custom) return;
    final last = _lastContact;
    if (last != null && now().difference(last) < _warmUpInterval) return;
    final _ChatTarget target;
    try {
      target = await _target();
    } on Object {
      return;
    }
    final base = target.base!;
    if (customEndpointNetworkOf(base.host) == CustomEndpointNetwork.remote) {
      return;
    }
    _lastContact = now();
    try {
      await _client
          .post(
            target.uri,
            headers: _headers(target),
            body: jsonEncode(
              customEndpointChatBody(
                model: target.model,
                systemPrompt: '',
                userText: 'OK',
                thinkingOff: !_refusesThinkingOff.contains(base.toString()),
                maxTokens: 1,
              ),
            ),
          )
          .timeout(_warmUpTimeout);
    } on Object catch (error) {
      // Best effort: the dictation's own request reports the problem to the
      // user. Only the error type is logged; the message may carry the
      // server address.
      _log.debug('Smart Mode warm-up failed: ${error.runtimeType}');
    }
  }

  static Map<String, String> _headers(_ChatTarget target) => {
    if (target.key != null) 'Authorization': 'Bearer ${target.key}',
    'Content-Type': 'application/json',
  };

  /// Abort triggers of the requests still running, by job id. [cancel] and
  /// [cancelWrite] complete them, so the HTTP client really drops the
  /// request instead of letting it run on unseen (#251).
  final Map<String, Completer<void>> _inFlight = {};
  int _nextRequest = 0;

  /// One POST that [cancel] or [cancelWrite] can abort. A client that cannot
  /// abort a request itself still releases the caller at once with
  /// [_AbortedError]; past [timeout] the request is aborted and the caller
  /// gets a [TimeoutException].
  Future<http.Response> _post(
    _ChatTarget target,
    Map<String, Object> body, {
    required Duration timeout,
    String? jobId,
  }) async {
    final id = jobId ?? 'run-${_nextRequest++}';
    final abort = Completer<void>();
    _inFlight[id] = abort;
    final request =
        http.AbortableRequest('POST', target.uri, abortTrigger: abort.future)
          ..headers.addAll(_headers(target))
          ..body = jsonEncode(body);
    try {
      final aborted = abort.future.then<http.Response>(
        (_) => throw const _AbortedError(),
      );
      final sent = _client.send(request).then(http.Response.fromStream);
      return await Future.any([sent, aborted]).timeout(
        timeout,
        onTimeout: () {
          _abort(abort);
          throw TimeoutException('smart mode request', timeout);
        },
      );
    } finally {
      if (identical(_inFlight[id], abort)) _inFlight.remove(id);
    }
  }

  static void _abort(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
  }

  /// Aborts every running request of this engine, cleanup and write.
  @override
  Future<void> cancel() async {
    final pending = _inFlight.values.toList();
    _inFlight.clear();
    pending.forEach(_abort);
  }

  @override
  void cancelWrite(String jobId) {
    final abort = _inFlight.remove(jobId);
    if (abort != null) _abort(abort);
  }

  @override
  Duration get writeTimeout => _writeTimeout;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    final target = await _target();
    if (_custom) {
      return _runCustom(target, systemPrompt: systemPrompt, userText: userText);
    }

    final http.Response response;
    try {
      response = await _post(
        target,
        _openAiBody(
          target.model,
          systemPrompt,
          userText,
          maxTokens: customEndpointMaxTokens(userText),
        ),
        timeout: _timeout,
      );
    } on _AbortedError {
      throw StateError('smart_mode_openai_cancelled');
    } on http.RequestAbortedException {
      throw StateError('smart_mode_openai_cancelled');
    } on TimeoutException {
      throw StateError('smart_mode_openai_timeout');
    } on Exception catch (e) {
      throw StateError('smart_mode_openai_network_error: ${e.runtimeType}');
    }

    switch (response.statusCode) {
      case 200:
        final answer = customEndpointChatAnswer(_decode(response.body));
        return switch (answer.outcome) {
          CustomEndpointChatOutcome.answer => answer.text,
          CustomEndpointChatOutcome.truncated => throw StateError(
            'smart_mode_openai_truncated',
          ),
          CustomEndpointChatOutcome.malformed => throw StateError(
            'smart_mode_openai_bad_format',
          ),
        };
      case 401:
        throw StateError('smart_mode_openai_invalid_api_key');
      case 429:
        throw StateError('smart_mode_openai_rate_limited');
      default:
        // The body stays out of the error: it may quote the request.
        throw StateError('smart_mode_openai_error_${response.statusCode}');
    }
  }

  /// One write job (#251, ADR 0015) on OpenAI: [_writeTimeout], room for a
  /// whole text ([_writeMaxTokens]), a cut-off answer counts as a failure,
  /// and [cancelWrite] with [jobId] really aborts the request. Every failure
  /// is a [SmartWriteEngineException] with a `smart_write_openai_*` code; the
  /// log names the job and the HTTP status only, never prompt or answer text.
  /// There is no failover to the local model.
  @override
  Future<String> write({
    required String systemPrompt,
    required String userText,
    required String jobId,
    Map<String, Object>? jsonSchema,
  }) async {
    if (_custom) {
      // The own endpoint keeps the cleanup request shape for now.
      return run(systemPrompt: systemPrompt, userText: userText);
    }
    final target = await _target();
    final http.Response response;
    try {
      response = await _post(
        target,
        _openAiBody(
          target.model,
          systemPrompt,
          userText,
          maxTokens: jsonSchema == null ? _writeMaxTokens : _choiceMaxTokens,
          jsonSchema: jsonSchema,
        ),
        timeout: _writeTimeout,
        jobId: jobId,
      );
    } on _AbortedError {
      throw const SmartWriteEngineException(smartWriteCancelledCode);
    } on http.RequestAbortedException {
      throw const SmartWriteEngineException(smartWriteCancelledCode);
    } on TimeoutException {
      _log.warning('[$jobId] OpenAI write timed out');
      throw const SmartWriteEngineException('smart_write_openai_timeout');
    } on Exception catch (e) {
      _log.warning('[$jobId] OpenAI write unreachable (${e.runtimeType})');
      throw const SmartWriteEngineException('smart_write_openai_network');
    }
    final status = response.statusCode;
    if (status != 200) _log.warning('[$jobId] OpenAI write HTTP $status');
    switch (status) {
      case 200:
        final answer = customEndpointChatAnswer(_decode(response.body));
        return switch (answer.outcome) {
          CustomEndpointChatOutcome.answer => answer.text,
          CustomEndpointChatOutcome.truncated =>
            throw const SmartWriteEngineException(
              'smart_write_openai_incomplete',
            ),
          CustomEndpointChatOutcome.malformed =>
            throw const SmartWriteEngineException('smart_write_openai_network'),
        };
      case 401 || 403:
        throw const SmartWriteEngineException('smart_write_openai_invalid_key');
      case 429:
        throw const SmartWriteEngineException(
          'smart_write_openai_rate_limited',
        );
      default:
        throw const SmartWriteEngineException('smart_write_openai_network');
    }
  }

  /// The request body for [_model], a reasoning model: thinking off, the
  /// output limit as `max_completion_tokens`, and no `temperature`, which
  /// reasoning models refuse while thinking is on.
  static Map<String, Object> _openAiBody(
    String model,
    String systemPrompt,
    String userText, {
    required int maxTokens,
    Map<String, Object>? jsonSchema,
  }) => {
    'model': model,
    'messages': [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userText},
    ],
    'reasoning_effort': 'none',
    'max_completion_tokens': maxTokens,
    if (jsonSchema != null)
      'response_format': {'type': 'json_schema', 'json_schema': jsonSchema},
  };

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// One Smart Mode request to the own endpoint (W-M3, #1957): thinking off
  /// where the server allows it, a token limit, and only the answer text,
  /// never the thinking. A server that refuses `reasoning_effort` gets the
  /// request once more without it.
  Future<String> _runCustom(
    _ChatTarget target, {
    required String systemPrompt,
    required String userText,
  }) async {
    final baseKey = target.base.toString();
    var thinkingOff = !_refusesThinkingOff.contains(baseKey);
    while (true) {
      final http.Response response;
      try {
        response = await _post(
          target,
          customEndpointChatBody(
            model: target.model,
            systemPrompt: systemPrompt,
            userText: userText,
            thinkingOff: thinkingOff,
          ),
          timeout: _timeout,
        );
      } on _AbortedError {
        throw StateError('smart_mode_custom_cancelled');
      } on http.RequestAbortedException {
        throw StateError('smart_mode_custom_cancelled');
      } on TimeoutException {
        throw StateError('smart_mode_custom_timeout');
      } on Exception {
        throw StateError('smart_mode_custom_unreachable');
      }
      final status = response.statusCode;
      if (customEndpointRetryWithoutThinkingOff(status, sent: thinkingOff)) {
        _refusesThinkingOff.add(baseKey);
        thinkingOff = false;
        continue;
      }
      if (status == 429) throw StateError('smart_mode_openai_rate_limited');
      if (status != 200) throw _customFailure(status, response.body);
      _lastContact = now();
      final Object? json;
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        throw StateError('smart_mode_custom_bad_format');
      }
      final answer = customEndpointChatAnswer(json);
      return switch (answer.outcome) {
        CustomEndpointChatOutcome.answer => answer.text,
        CustomEndpointChatOutcome.truncated => throw StateError(
          'smart_mode_custom_truncated',
        ),
        CustomEndpointChatOutcome.malformed => throw StateError(
          'smart_mode_custom_bad_format',
        ),
      };
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

/// Raised for the caller when [SmartModeOpenAiEngine.cancel] aborted its
/// request.
class _AbortedError implements Exception {
  const _AbortedError();
}
