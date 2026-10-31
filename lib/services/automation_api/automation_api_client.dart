/// Pure-Dart client for the local automation API (WP-38 / 8.2).
///
/// Shared by the `tool/whispaste.dart` CLI and the MCP server. It talks only
/// to the IPv4 loopback address with the bearer token, so it cannot reach a
/// remote host even when a caller passes odd input. No Flutter imports.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'automation_api_port.dart';

/// A non-2xx answer from the API, or a transport failure.
///
/// [error] is the API's own error code (for example `snippet_not_found`), or
/// `unreachable` / `timeout` / `invalid_response` for local failures.
class AutomationApiException implements Exception {
  const AutomationApiException({required this.statusCode, required this.error});

  /// HTTP status, or `0` when no response was received.
  final int statusCode;
  final String error;

  @override
  String toString() => 'AutomationApiException($statusCode, $error)';
}

/// An [HttpClient] that always connects directly. The default client honours
/// `HTTP_PROXY`, which would send the bearer token and hook payloads to a
/// proxy and break the loopback-only guarantee.
HttpClient newLoopbackHttpClient() =>
    HttpClient()..findProxy = automationProxyDecision;

/// Proxy decision for automation traffic: always direct.
String automationProxyDecision(Uri target) => 'DIRECT';

/// Default time the client waits for any step of one API call. Server-side
/// waits that a client can trigger (multiline preview) must end before this.
const kAutomationClientTimeout = Duration(seconds: 15);

class AutomationApiClient {
  AutomationApiClient({
    required this.token,
    this.port = kAutomationApiDefaultPort,
    this.timeout = kAutomationClientTimeout,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? newLoopbackHttpClient;

  final String token;
  final int port;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: path,
    queryParameters: query,
  );

  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) =>
      _send('GET', _uri(path, query));

  Future<Map<String, Object?>> postJson(String path, Object? body) =>
      _send('POST', _uri(path), json: body);

  Future<Map<String, Object?>> postWav(String path, List<int> bytes) =>
      _send('POST', _uri(path), bytes: bytes, contentType: 'audio/wav');

  // -- Typed helpers used by the CLI and the MCP tools ----------------------

  Future<Map<String, Object?>> status() => get('/v1/status');

  Future<Map<String, Object?>> listNotes({int? limit}) =>
      get('/v1/notes', query: limit == null ? null : {'limit': '$limit'});

  Future<Map<String, Object?>> createNote(String content) =>
      postJson('/v1/notes', {'content': content});

  Future<Map<String, Object?>> listSnippets() => get('/v1/snippets');

  Future<Map<String, Object?>> renderSnippet(
    String name,
    Map<String, String> values,
  ) => postJson('/v1/snippets/render', {'name': name, 'values': values});

  Future<Map<String, Object?>> latestDictation() => get('/v1/history/latest');

  Future<Map<String, Object?>> triggerDictation({
    bool wait = false,
    String? language,
  }) =>
      postJson('/v1/dictation/trigger', {'wait': wait, 'language': ?language});

  Future<Map<String, Object?>> transcribe(List<int> wav) =>
      postWav('/v1/transcriptions', wav);

  Future<Map<String, Object?>> _send(
    String method,
    Uri uri, {
    Object? json,
    List<int>? bytes,
    String contentType = 'application/json',
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      } else if (bytes != null) {
        request.headers.contentType = ContentType.parse(contentType);
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = _decode(response.statusCode, text);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw AutomationApiException(
        statusCode: response.statusCode,
        error: decoded['error'] as String? ?? 'http_${response.statusCode}',
      );
    } on SocketException {
      throw const AutomationApiException(statusCode: 0, error: 'unreachable');
    } on TimeoutException {
      throw const AutomationApiException(statusCode: 0, error: 'timeout');
    } on HttpException {
      throw const AutomationApiException(statusCode: 0, error: 'unreachable');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _decode(int statusCode, String text) {
    if (text.trim().isEmpty) return const {};
    final decoded = _tryDecode(text);
    if (decoded is Map<String, dynamic>) {
      return Map<String, Object?>.of(decoded);
    }
    throw AutomationApiException(
      statusCode: statusCode,
      error: 'invalid_response',
    );
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
