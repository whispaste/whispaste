/// Unit tests for the Host-header guard of the automation API — no socket.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_host_guard.dart';

void main() {
  group('isAllowedLoopbackHost', () {
    test('accepts loopback names with and without a port', () {
      for (final host in [
        '127.0.0.1',
        '127.0.0.1:8765',
        'localhost',
        'localhost:8765',
        'LOCALHOST:8766',
        '[::1]',
        '[::1]:8765',
        'localhost:65535',
      ]) {
        expect(isAllowedLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('rejects foreign hosts (DNS rebinding) even with loopback ports', () {
      for (final host in [
        'attacker.example',
        'attacker.example:8765',
        'localhost.attacker.example:8765',
        '127.0.0.1.attacker.example',
        '127.0.0.2:8765',
        '0.0.0.0:8765',
        '192.168.1.10:8765',
      ]) {
        expect(isAllowedLoopbackHost(host), isFalse, reason: host);
      }
    });

    test('rejects malformed host values', () {
      for (final host in [
        null,
        '',
        'localhost:',
        'localhost:abc',
        'localhost:0',
        'localhost:65536',
        'localhost:123456',
        'localhost:8765:8765',
        '::1',
        '[::1',
        '[::1]x',
        '[::1]:',
        '[evil]:8765',
      ]) {
        expect(isAllowedLoopbackHost(host), isFalse, reason: '$host');
      }
    });
  });

  group('loopbackHostGuard middleware', () {
    var innerCalled = false;

    Handler build() {
      innerCalled = false;
      return const Pipeline().addMiddleware(loopbackHostGuard()).addHandler((
        Request request,
      ) {
        innerCalled = true;
        return Response.ok('ok');
      });
    }

    test('loopback Host header → passes through to the handler', () async {
      final handler = build();
      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://127.0.0.1:8765/status'),
          headers: {'host': '127.0.0.1:8765'},
        ),
      );

      expect(innerCalled, isTrue);
      expect(response.statusCode, 200);
    });

    test('foreign Host header → 403, never reaches the handler', () async {
      final handler = build();
      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://attacker.example/status'),
          headers: {'host': 'attacker.example:8765'},
        ),
      );

      expect(innerCalled, isFalse);
      expect(response.statusCode, 403);
    });

    test('missing Host header → 403', () async {
      final handler = build();
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/status')),
      );

      expect(innerCalled, isFalse);
      expect(response.statusCode, 403);
    });
  });
}
