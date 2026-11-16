/// A loopback stand-in for the automation API, used by the CLI and MCP tests.
///
/// It records every request so a test can assert on the method, path, query,
/// bearer header, and body that the client actually sent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.contentType,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String? authorization;
  final String? contentType;
  final List<int> body;

  Map<String, Object?> get jsonBody =>
      jsonDecode(utf8.decode(body)) as Map<String, Object?>;
}

class FakeAutomationApi {
  FakeAutomationApi._(this._server, this.requests);

  final HttpServer _server;
  final List<RecordedRequest> requests;

  int get port => _server.port;

  /// Starts a server that answers every request with [respond].
  static Future<FakeAutomationApi> start(
    Future<Response> Function(RecordedRequest request) respond,
  ) async {
    final requests = <RecordedRequest>[];
    Future<Response> handler(Request request) async {
      final body = await request.read().fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      final recorded = RecordedRequest(
        method: request.method,
        path: request.url.path.isEmpty ? '/' : '/${request.url.path}',
        query: request.url.queryParameters,
        authorization: request.headers['authorization'],
        contentType: request.headers['content-type'],
        body: body,
      );
      requests.add(recorded);
      return respond(recorded);
    }

    final server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    return FakeAutomationApi._(server, requests);
  }

  Future<void> close() => _server.close(force: true);
}

/// JSON response helper matching the app's shape.
Response jsonReply(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

/// A port nothing listens on: bind, read the port, close again.
Future<int> closedLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
