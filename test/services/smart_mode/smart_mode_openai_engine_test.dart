import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/smart_mode/smart_mode_openai_engine.dart';

/// Helper provider that exposes a test-configured [SmartModeOpenAiEngine].
///
/// Mirrors `openai_transcriber_test.dart`'s `_testTranscriberProvider`: [Ref]
/// is a sealed class in Riverpod 3 and cannot be implemented outside the
/// framework, so a real container-backed provider stands in for it.
final _testEngineProvider = Provider.family<SmartModeOpenAiEngine, http.Client>(
  (ref, client) => SmartModeOpenAiEngine(ref: ref, httpClient: client),
);

class _FakeSecureKeyStore implements SecureKeyStore {
  _FakeSecureKeyStore(this._store);
  final Map<String, String> _store;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartModeOpenAiEngine', () {
    test('returns trimmed content on HTTP 200', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '  cleaned up text  '},
              },
            ],
          }),
          200,
        ),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final engine = container.read(_testEngineProvider(client));
      final result = await engine.run(
        systemPrompt: 'Clean up the text.',
        userText: 'uh so like this is the text',
      );

      expect(result, 'cleaned up text');
    });

    test('throws when no API key is stored', () async {
      final container = _makeContainer({});
      addTearDown(container.dispose);

      final engine = container.read(
        _testEngineProvider(MockClient((_) async => http.Response('', 200))),
      );

      expect(
        () => engine.run(systemPrompt: 'p', userText: 't'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'smart_mode_openai_api_key_missing',
          ),
        ),
      );
    });

    test('throws on HTTP 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-bad'});
      addTearDown(container.dispose);

      final engine = container.read(_testEngineProvider(client));

      expect(
        () => engine.run(systemPrompt: 'p', userText: 't'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'smart_mode_openai_invalid_api_key',
          ),
        ),
      );
    });

    test('throws on HTTP 429', () async {
      final client = MockClient((_) async => http.Response('Limited', 429));
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final engine = container.read(_testEngineProvider(client));

      expect(
        () => engine.run(systemPrompt: 'p', userText: 't'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'smart_mode_openai_rate_limited',
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

      final engine = container.read(_testEngineProvider(client));

      expect(
        () => engine.run(systemPrompt: 'p', userText: 't'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message.startsWith('smart_mode_openai_network_error'),
            'message starts with smart_mode_openai_network_error',
            isTrue,
          ),
        ),
      );
    });

    test(
      'throws timeout on slow response',
      () async {
        final client = MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 25));
          return http.Response('', 200);
        });
        final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
        addTearDown(container.dispose);

        final engine = container.read(_testEngineProvider(client));

        expect(
          () => engine.run(systemPrompt: 'p', userText: 't'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'smart_mode_openai_timeout',
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
