import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
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

    test('throws timeout on slow response', () {
      fakeAsync((async) {
        // The server never answers; only the engine's timeout ends the call.
        final client = MockClient((_) => Completer<http.Response>().future);
        final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
        addTearDown(container.dispose);

        final engine = container.read(_testEngineProvider(client));

        Object? error;
        unawaited(
          engine
              .run(systemPrompt: 'p', userText: 't')
              .then<void>((_) {}, onError: (Object e) => error = e),
        );
        async.elapse(const Duration(seconds: 25));

        expect(
          error,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'smart_mode_openai_timeout',
          ),
        );
      });
    });
  });

  group('SmartModeOpenAiEngine.write (#251)', () {
    http.Response answer(String content, {String finish = 'stop'}) =>
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
                'finish_reason': finish,
              },
            ],
          }),
          200,
        );

    Matcher code(String expected) => isA<SmartWriteEngineException>().having(
      (e) => e.code,
      'code',
      expected,
    );

    SmartModeOpenAiEngine engineFor(http.Client client) {
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);
      return container.read(_testEngineProvider(client));
    }

    test('sends the write request shape and returns the draft', () async {
      Map<String, dynamic>? body;
      final engine = engineFor(
        MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return answer('  Dear Anna  ');
        }),
      );

      final draft = await engine.write(
        systemPrompt: 's',
        userText: 'u',
        jobId: 'job-1',
      );

      expect(draft, 'Dear Anna');
      expect(body!['model'], 'gpt-6-luna');
      expect(body!['max_completion_tokens'], 2048);
      expect(body!['reasoning_effort'], 'none');
      expect(body!.containsKey('temperature'), isFalse);
      expect(engine.writeTimeout, const Duration(seconds: 30));
    });

    test('maps every failure to its own code', () async {
      final cases = <String, Future<http.Response> Function(http.Request)>{
        'smart_write_openai_incomplete': (_) async =>
            answer('Dear An', finish: 'length'),
        'smart_write_openai_invalid_key': (_) async => http.Response('', 401),
        'smart_write_openai_rate_limited': (_) async => http.Response('', 429),
        'smart_write_openai_network': (_) async =>
            throw const SocketException('refused'),
      };
      for (final entry in cases.entries) {
        final engine = engineFor(MockClient(entry.value));
        await expectLater(
          engine.write(systemPrompt: 's', userText: 'u', jobId: 'j'),
          throwsA(code(entry.key)),
          reason: entry.key,
        );
      }
      // 403 is a key without access, the same fix as a wrong key.
      await expectLater(
        engineFor(
          MockClient((_) async => http.Response('', 403)),
        ).write(systemPrompt: 's', userText: 'u', jobId: 'j'),
        throwsA(code('smart_write_openai_invalid_key')),
      );
    });

    test('waits 30 s before it times out', () {
      fakeAsync((async) {
        final engine = engineFor(
          MockClient((_) => Completer<http.Response>().future),
        );
        Object? error;
        unawaited(
          engine
              .write(systemPrompt: 's', userText: 'u', jobId: 'j')
              .then<void>((_) {}, onError: (Object e) => error = e),
        );
        async.elapse(const Duration(seconds: 25));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 6));
        expect(error, code('smart_write_openai_timeout'));
      });
    });

    test('cancelWrite aborts exactly its job', () async {
      final engine = engineFor(
        MockClient((_) => Completer<http.Response>().future),
      );
      Object? error;
      final run = engine
          .write(systemPrompt: 's', userText: 'u', jobId: 'mine')
          .then<void>((_) {}, onError: (Object e) => error = e);
      await Future<void>.delayed(Duration.zero);

      engine.cancelWrite('someone-else');
      await Future<void>.delayed(Duration.zero);
      expect(error, isNull);

      engine.cancelWrite('mine');
      await run;
      expect(error, code(smartWriteCancelledCode));
    });
  });
}
