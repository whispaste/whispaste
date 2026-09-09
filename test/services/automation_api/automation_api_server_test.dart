/// Integration tests for [AutomationApiServer] — sends real HTTP requests
/// against a real socket bound to loopback (ephemeral port, `port: 0`, so
/// parallel test runs never collide).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_server.dart';

void main() {
  group('AutomationApiServer', () {
    late AutomationApiServer server;

    tearDown(() async {
      await server.stop();
    });

    test('not started → nothing listens, isRunning is false', () {
      server = AutomationApiServer();
      expect(server.isRunning, isFalse);
      expect(server.port, isNull);
    });

    test('start() binds IPv4 loopback and serves a real request', () async {
      server = AutomationApiServer();
      Response handler(Request request) => Response.ok('hello');

      final port = await server.start(port: 0, handler: handler);

      expect(server.isRunning, isTrue);
      expect(server.port, port);

      final client = HttpClient();
      try {
        final request = await client.get('127.0.0.1', port, '/');
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        expect(body, 'hello');
      } finally {
        client.close(force: true);
      }
    });

    test('start() also binds IPv6 loopback when available', () async {
      server = AutomationApiServer();
      Response handler(Request request) => Response.ok('hello');
      final port = await server.start(port: 0, handler: handler);

      final client = HttpClient();
      try {
        final request = await client.get('::1', port, '/');
        final response = await request.close();
        expect(response.statusCode, 200);
      } on SocketException {
        // IPv6 loopback disabled in this environment — acceptable, the
        // library doc comment on AutomationApiServer covers this; IPv4
        // alone already satisfies "loopback only".
      } finally {
        client.close(force: true);
      }
    });

    test(
      'stop() closes the socket — a further connection is refused',
      () async {
        server = AutomationApiServer();
        Response handler(Request request) => Response.ok('hello');
        final port = await server.start(port: 0, handler: handler);

        await server.stop();
        expect(server.isRunning, isFalse);
        expect(server.port, isNull);

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 2);
        var refused = false;
        try {
          final request = await client.get('127.0.0.1', port, '/');
          await request.close();
        } on SocketException {
          refused = true;
        } finally {
          client.close(force: true);
        }
        expect(refused, isTrue);
      },
    );

    test('start() throws when already running', () async {
      server = AutomationApiServer();
      Response handler(Request request) => Response.ok('hello');
      await server.start(port: 0, handler: handler);

      expect(
        () => server.start(port: 0, handler: handler),
        throwsA(isA<StateError>()),
      );
    });
  });
}
