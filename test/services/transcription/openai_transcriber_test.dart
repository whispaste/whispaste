import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/transcription/openai_transcriber.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

/// Helper provider that exposes a test-configured [OpenAiTranscriber].
///
/// This indirection is necessary because [Ref] is a sealed class in
/// Riverpod 3 and cannot be implemented outside the framework.
final _testTranscriberProvider =
    Provider.family<OpenAiTranscriber, http.Client>(
      (ref, client) => OpenAiTranscriber(ref: ref, httpClient: client),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OpenAiTranscriber', () {
    test('returns transcript on HTTP 200', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'text': 'hello world'}), 200),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      final result = await transcriber.transcribe(_silentWav());

      expect(result, 'hello world');
    });

    test('throws authError on HTTP 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-bad'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      expect(
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
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      expect(
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

    test('prepare throws authError when API key is empty', () async {
      final container = _makeContainer({});
      addTearDown(container.dispose);

      final transcriber = container.read(
        _testTranscriberProvider(
          MockClient((_) async => http.Response('', 200)),
        ),
      );

      expect(
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

    test('throws networkError on connection failure', () async {
      final client = MockClient(
        (_) async => throw const SocketException('refused'),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      expect(
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
  });
}
