/// Unit tests for SttHealthProbe.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/services/stt/stt_health_probe.dart';

void main() {
  group('SttHealthProbe.checkOnce', () {
    test('returns true on HTTP 200 /health', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('ok', 200);
        return http.Response('not found', 404);
      });
      final probe = SttHealthProbe(client: client);
      final result = await probe.checkOnce('127.0.0.1', 9999);
      expect(result, isTrue);
    });

    test('returns false on HTTP 503 /health', () async {
      final client = MockClient((_) async => http.Response('not ready', 503));
      final probe = SttHealthProbe(client: client);
      final result = await probe.checkOnce('127.0.0.1', 9999);
      expect(result, isFalse);
    });

    test('returns false on connection error', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('fail'),
      );
      final probe = SttHealthProbe(client: client);
      final result = await probe.checkOnce('127.0.0.1', 9999);
      expect(result, isFalse);
    });

    test('requests correct URL path', () async {
      Uri? capturedUri;
      final client = MockClient((req) async {
        capturedUri = req.url;
        return http.Response('ok', 200);
      });
      final probe = SttHealthProbe(client: client);
      await probe.checkOnce('127.0.0.1', 8765);
      expect(capturedUri?.path, '/health');
      expect(capturedUri?.port, 8765);
    });
  });

  group('SttHealthProbe.watchUntilReady', () {
    test('emits true and completes when server becomes ready', () async {
      var callCount = 0;
      final client = MockClient((req) async {
        callCount++;
        // Return 200 on the second call.
        if (callCount >= 2) return http.Response('ok', 200);
        return http.Response('not ready', 503);
      });
      final probe = SttHealthProbe(client: client);
      final stream = probe.watchUntilReady(
        '127.0.0.1',
        9999,
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(milliseconds: 500),
      );

      final results = await stream.toList();
      expect(results.last, isTrue);
    });

    test('emits false as last value when timeout elapses', () async {
      final client = MockClient((_) async => http.Response('not ready', 503));
      final probe = SttHealthProbe(client: client);
      final stream = probe.watchUntilReady(
        '127.0.0.1',
        9999,
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(milliseconds: 60),
      );

      final results = await stream.toList();
      expect(results.last, isFalse);
    });
  });
}
