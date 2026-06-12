import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/transcription/deepgram_transcriber.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

/// Helper provider that exposes a test-configured [DeepgramTranscriber].
final _testTranscriberProvider =
    Provider.family<DeepgramTranscriber, http.Client>(
      (ref, client) => DeepgramTranscriber(ref: ref, httpClient: client),
    );

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store;
  _FakeSecureKeyStore(this._store);

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async => _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => Map.of(_store);
}

ProviderContainer _makeContainer(Map<String, String> keys) {
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore(keys)),
    ],
  );
}

List<int> _silentWav() => List.filled(44, 0); // minimal WAV bytes

/// Builds a valid Deepgram JSON response body.
String _deepgramResponse(String transcript) => jsonEncode({
  'results': {
    'channels': [
      {
        'alternatives': [
          {'transcript': transcript},
        ],
      },
    ],
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeepgramTranscriber (mocked)', () {
    test('returns transcript on HTTP 200', () async {
      final client = MockClient(
        (_) async => http.Response(_deepgramResponse('hello deepgram'), 200),
      );
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      final result = await transcriber.transcribe(_silentWav());

      expect(result, 'hello deepgram');
    });

    test('returns empty string on HTTP 200 with empty transcript', () async {
      final client = MockClient(
        (_) async => http.Response(_deepgramResponse(''), 200),
      );
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      final result = await transcriber.transcribe(_silentWav());

      expect(result, '');
    });

    test('throws authError on HTTP 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-bad'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      await expectLater(
        () => transcriber.transcribe(_silentWav()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.authError,
          ),
        ),
      );
    });

    test('throws quotaExceeded on HTTP 429', () async {
      final client = MockClient(
        (_) async => http.Response('Rate limited', 429),
      );
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      await expectLater(
        () => transcriber.transcribe(_silentWav()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.quotaExceeded,
          ),
        ),
      );
    });

    test('throws networkError on connection failure', () async {
      final client = MockClient(
        (_) async => throw const SocketException('Connection refused'),
      );
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      await expectLater(
        () => transcriber.transcribe(_silentWav()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.networkError,
          ),
        ),
      );
    });

    test('throws timeout on request timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(minutes: 2));
        return http.Response('', 200);
      });
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      // Use a very short timeout to trigger the timeout exception.
      final transcriber = DeepgramTranscriber(
        ref: container.read(Provider((ref) => ref)),
        httpClient: client,
        timeout: const Duration(milliseconds: 100),
      );
      await transcriber.prepare();

      await expectLater(
        () => transcriber.transcribe(_silentWav()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.timeout,
          ),
        ),
      );
    });

    test('prepare throws authError when API key is missing', () async {
      final container = _makeContainer({});
      addTearDown(container.dispose);

      final transcriber = container.read(
        _testTranscriberProvider(
          MockClient((_) async => http.Response('', 200)),
        ),
      );

      await expectLater(
        () => transcriber.prepare(),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.authError,
          ),
        ),
      );
    });

    test('passes language as query parameter', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(_deepgramResponse('bonjour'), 200);
      });
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav(), language: 'fr');

      expect(capturedUri?.queryParameters['language'], 'fr');
    });

    test('auto language requests detect_language instead of Deepgram\'s '
        'en default (store-review regression, June 2026)', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(_deepgramResponse('privet'), 200);
      });
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav(), language: 'auto');

      expect(capturedUri?.queryParameters.containsKey('language'), isFalse);
      expect(capturedUri?.queryParameters['detect_language'], 'true');
    });

    test('uses model=nova-3 and smart_format=true query parameters', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(_deepgramResponse('test'), 200);
      });
      final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav());

      expect(capturedUri?.queryParameters['model'], 'nova-3');
      expect(capturedUri?.queryParameters['smart_format'], 'true');
    });

    test('sends Authorization: Token header', () async {
      String? capturedAuth;
      final client = MockClient((request) async {
        capturedAuth = request.headers['Authorization'];
        return http.Response(_deepgramResponse('ok'), 200);
      });
      final container = _makeContainer({'wp_deepgram_api_key': 'my-dg-key'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav());

      expect(capturedAuth, 'Token my-dg-key');
    });

    test(
      'throws unknown on unexpected HTTP status with body in message',
      () async {
        final client = MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        );
        final container = _makeContainer({'wp_deepgram_api_key': 'dg-test'});
        addTearDown(container.dispose);

        final transcriber = container.read(_testTranscriberProvider(client));
        await transcriber.prepare();

        await expectLater(
          () => transcriber.transcribe(_silentWav()),
          throwsA(
            isA<TranscriberException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  TranscriberFailureReason.unknown,
                )
                .having(
                  (e) => e.message,
                  'message contains body',
                  contains('Internal Server Error'),
                ),
          ),
        );
      },
    );
  });

  group('DeepgramTranscriber (live-smoke)', () {
    // Auto-skipped when DEEPGRAM_API_KEY dart-define is absent.
    const apiKey = String.fromEnvironment('DEEPGRAM_API_KEY');

    test(
      'live: transcribes 2-second WAV fixture and returns non-empty string',
      () async {
        if (apiKey.isEmpty) {
          // Skip gracefully without dart-define.
          return;
        }

        final wavFile = File(
          '${Directory.current.path}/test/fixtures/hello_world.wav',
        );
        expect(
          wavFile.existsSync(),
          isTrue,
          reason:
              'test/fixtures/hello_world.wav must exist for live-smoke test',
        );
        final wavBytes = await wavFile.readAsBytes();

        // Use a real http.Client (no mock).
        final container = ProviderContainer(
          overrides: [
            secureKeyStoreProvider.overrideWithValue(
              _FakeSecureKeyStore({'wp_deepgram_api_key': apiKey}),
            ),
          ],
        );
        addTearDown(container.dispose);

        final realClient = http.Client();
        final transcriber = container.read(
          _testTranscriberProvider(realClient),
        );
        addTearDown(transcriber.release);

        await transcriber.prepare();
        final result = await transcriber.transcribe(
          wavBytes.toList(),
          language: 'en',
        );

        expect(
          result.isNotEmpty,
          isTrue,
          reason: 'Live Deepgram response should have non-empty transcript',
        );
      },
      tags: ['live'],
    );
  });
}
