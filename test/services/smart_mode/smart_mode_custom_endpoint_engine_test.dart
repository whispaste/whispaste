/// Smart Mode on the user's own OpenAI-compatible server (#1957), at the hand
/// over to the server: what is sent, what comes back into the paste, and when
/// the model is loaded ahead of the dictation.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/smart_mode/smart_mode_openai_engine.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._s);
  final AppSettings _s;

  @override
  Future<AppSettings> build() async => _s;
}

class _Keys implements SecureKeyStore {
  _Keys(this._store);
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

final _engine = Provider.family<SmartModeOpenAiEngine, http.Client>(
  (ref, client) =>
      SmartModeOpenAiEngine.customEndpoint(ref: ref, httpClient: client),
);

http.Response _ok(String content, {String finish = 'stop'}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {
          'content': content,
          'reasoning_content': 'Okay, the user wants me to…',
        },
        'finish_reason': finish,
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<SmartModeOpenAiEngine> _make(
  http.Client client, {
  String url = 'http://127.0.0.1:11434',
  Map<String, String> keys = const {},
}) async {
  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(_Keys(Map.of(keys))),
      settingsProvider.overrideWith(
        () => _Settings(
          AppSettings(
            cloudProvider: CloudProviderSettings(
              customEndpointUrl: url,
              customEndpointSmartModel: 'qwen3:0.6b',
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);
  return container.read(_engine(client));
}

Matcher _code(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(SmartModeOpenAiEngine.resetThinkingOffMemory);

  test('a bare address is sent to /v1, without a key header, thinking off, '
      'with a token limit, and only the answer comes back', () async {
    final requests = <http.Request>[];
    final engine = await _make(
      MockClient((r) async {
        requests.add(r);
        return _ok('<think>hidden</think>\n\nDas Meeting ist morgen.');
      }),
    );

    final text = await engine.run(systemPrompt: 'Clean.', userText: 'ähm');

    expect(text, 'Das Meeting ist morgen.');
    final request = requests.single;
    expect(
      request.url.toString(),
      'http://127.0.0.1:11434/v1/chat/completions',
    );
    expect(request.headers.containsKey('Authorization'), isFalse);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], 'qwen3:0.6b');
    expect(body['reasoning_effort'], 'none');
    expect(body['max_tokens'], 1024);
    expect(body['stream'], false);
  });

  test('a server that refuses reasoning_effort gets the request again '
      'without it, and later requests leave it out', () async {
    final bodies = <Map<String, dynamic>>[];
    final engine = await _make(
      MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        bodies.add(body);
        return body.containsKey('reasoning_effort')
            ? http.Response('{"error":"Unrecognized request argument"}', 400)
            : _ok('Fertig.');
      }),
    );

    expect(await engine.run(systemPrompt: 's', userText: 'a'), 'Fertig.');
    expect(await engine.run(systemPrompt: 's', userText: 'b'), 'Fertig.');

    expect(bodies.map((b) => b.containsKey('reasoning_effort')), [
      true,
      false,
      false,
    ]);
  });

  test('a cut-off answer is a failure, never a pasted half sentence', () async {
    final engine = await _make(
      MockClient((_) async => _ok('Das Meeting ist mor', finish: 'length')),
    );
    expect(
      () => engine.run(systemPrompt: 's', userText: 'u'),
      _code('smart_mode_custom_truncated'),
    );
  });

  test('a stored key is sent as a bearer token', () async {
    final auth = <String?>[];
    final engine = await _make(
      MockClient((r) async {
        auth.add(r.headers['Authorization']);
        return _ok('x');
      }),
      keys: {'wp_custom_endpoint_api_key': 'secret'},
    );
    await engine.run(systemPrompt: 's', userText: 'u');
    expect(auth, ['Bearer secret']);
  });

  group('warmUp', () {
    test('loads the model with a one-token request without dictated text, '
        'at most once a minute', () async {
      final bodies = <Map<String, dynamic>>[];
      final engine = await _make(
        MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return _ok('Hello', finish: 'length');
        }),
      );
      var clock = DateTime(2026, 11, 19, 12);
      engine.now = () => clock;

      await engine.warmUp();
      await engine.warmUp();
      clock = clock.add(const Duration(minutes: 2));
      await engine.warmUp();

      expect(bodies, hasLength(2));
      expect(bodies.first['max_tokens'], 1);
      expect(bodies.first['messages'], [
        {'role': 'user', 'content': 'OK'},
      ]);
    });

    test('a hosted provider is never warmed up', () async {
      var calls = 0;
      final engine = await _make(
        MockClient((_) async {
          calls++;
          return _ok('x');
        }),
        url: 'https://api.example.com/v1',
      );
      await engine.warmUp();
      expect(calls, 0);
    });

    test('a server that is down does not throw', () async {
      final engine = await _make(
        MockClient((_) async => throw http.ClientException('refused')),
      );
      await expectLater(engine.warmUp(), completes);
    });
  });
}
