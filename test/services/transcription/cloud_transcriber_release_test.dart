import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

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

/// Answers every request with [body] and, like the real IO client, refuses
/// requests once closed.
class _ClosableClient extends http.BaseClient {
  _ClosableClient(this.body);
  final String body;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }

  @override
  void close() => closed = true;
}

final _cases = {
  SttProviderType.openAI: (
    key: 'wp_openai_api_key',
    body: jsonEncode({'text': 'hello'}),
  ),
  SttProviderType.deepgram: (
    key: 'wp_deepgram_api_key',
    body: jsonEncode({
      'results': {
        'channels': [
          {
            'alternatives': [
              {'transcript': 'hello'},
            ],
          },
        ],
      },
    }),
  ),
};

void main() {
  for (final MapEntry(key: type, value: c) in _cases.entries) {
    group('${type.name} transcriber from transcriberProvider', () {
      late List<_ClosableClient> clients;
      late ProviderContainer container;

      setUp(() async {
        clients = [];
        container = ProviderContainer(
          overrides: [
            secureKeyStoreProvider.overrideWithValue(
              _FakeSecureKeyStore({c.key: 'test-key'}),
            ),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttProvider: type.value),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
      });

      Future<String> transcribe() => http.runWithClient(
        () async {
          final transcriber = container.read(transcriberProvider);
          await transcriber.prepare();
          return transcriber.transcribe([0, 1, 2]);
        },
        () {
          final client = _ClosableClient(c.body);
          clients.add(client);
          return client;
        },
      );

      test('stays usable after a caller releases it', () async {
        // An import, a re-transcription or an automation request finishes
        // and releases the shared adapter; the next dictation reuses it.
        expect(await transcribe(), 'hello');
        container.read(transcriberProvider).release();
        expect(await transcribe(), 'hello');
      });

      test('leaves no client open after a request', () async {
        await transcribe();
        expect(clients, isNotEmpty);
        expect(clients.every((c) => c.closed), isTrue);
      });
    });
  }
}
