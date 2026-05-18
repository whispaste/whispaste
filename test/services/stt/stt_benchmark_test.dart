/// Unit tests for SttBenchmark.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/services/stt/stt_benchmark.dart';

void main() {
  const benchmark = SttBenchmark();

  group('SttBenchmark.run', () {
    test('returns RTF as double on successful 200 response', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/inference') {
          return http.Response('{"text":""}', 200);
        }
        return http.Response('not found', 404);
      });
      final rtf = await benchmark.run(
        '127.0.0.1',
        9999,
        'whisper-small',
        client: client,
      );
      expect(rtf, isNotNull);
      expect(rtf, greaterThanOrEqualTo(0.0));
    });

    test('returns null on connection failure', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('connection refused'),
      );
      final rtf = await benchmark.run(
        '127.0.0.1',
        9999,
        'whisper-small',
        client: client,
      );
      expect(rtf, isNull);
    });

    test('sends POST to /inference endpoint', () async {
      String? capturedMethod;
      String? capturedPath;
      final client = MockClient((req) async {
        capturedMethod = req.method;
        capturedPath = req.url.path;
        return http.Response('{"text":""}', 200);
      });
      await benchmark.run('127.0.0.1', 8080, 'whisper-small', client: client);
      expect(capturedMethod, 'POST');
      expect(capturedPath, '/inference');
    });

    test('measures non-negative elapsed time', () async {
      final client = MockClient((req) async {
        return http.Response('{"text":""}', 200);
      });
      final rtf = await benchmark.run(
        '127.0.0.1',
        9999,
        'whisper-small',
        client: client,
      );
      // RTF >= 0 since elapsed >= 0 and audioDuration = 3000.
      expect(rtf, greaterThanOrEqualTo(0.0));
    });
  });
}
