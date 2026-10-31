import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/transcription/openai_transcriber.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

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

ProviderContainer _makeContainer(
  Map<String, String> keys, {
  AppSettings? settings,
}) {
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore(keys)),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(settings ?? AppSettings.defaults),
      ),
    ],
  );
}

List<int> _silentWav() => List.filled(44, 0); // minimal WAV bytes

void main() {
  // Deliberately no TestWidgetsFlutterBinding.ensureInitialized() here: it
  // installs a fake HttpOverrides that makes every dart:io-backed HTTP
  // request return a synthetic 400 without touching the network (see
  // flutter_test's own warning), which silently broke the (live-smoke) and
  // (canary) groups below whenever they were actually exercised with a real
  // client. Nothing above uses MockClient, which bypasses dart:io/
  // HttpOverrides entirely and is unaffected either way.

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

    test('sends customVocabulary as the prompt field', () async {
      String? capturedPrompt;
      final client = MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        capturedPrompt = multipart.fields['prompt'];
        final body = jsonEncode({'text': 'ok'});
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final settings = AppSettings.defaults.copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          customVocabulary: 'WhisPaste, Kubernetes',
        ),
      );
      final container = _makeContainer({
        'wp_openai_api_key': 'sk-test',
      }, settings: settings);
      addTearDown(container.dispose);
      // AsyncNotifier.build() resolves on a microtask even for a trivially
      // synchronous fake — await the initial future so settingsProvider is
      // AsyncData before transcribe() reads it, otherwise .value is still
      // null (AsyncLoading) and the prompt field is silently skipped.
      await container.read(settingsProvider.future);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav());

      expect(capturedPrompt, 'WhisPaste, Kubernetes');
    });

    test('omits the prompt field when customVocabulary is empty', () async {
      var sawPromptField = false;
      final client = MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        sawPromptField = multipart.fields.containsKey('prompt');
        final body = jsonEncode({'text': 'ok'});
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav());

      expect(sawPromptField, isFalse);
    });
  });

  group('OpenAiTranscriber (live-smoke)', () {
    // Auto-skipped when OPENAI_API_KEY dart-define is absent. Mirrors
    // DeepgramTranscriber's live-smoke group.
    const apiKey = String.fromEnvironment('OPENAI_API_KEY');

    test(
      'live: transcribes WAV fixture and returns non-empty string',
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
              _FakeSecureKeyStore({'wp_openai_api_key': apiKey}),
            ),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(AppSettings.defaults),
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
          reason: 'Live OpenAI response should have a non-empty transcript',
        );
      },
      tags: ['live'],
    );
  });

  group('OpenAiTranscriber (canary)', () {
    // Provider-drift canary: no API key needed. Asserts OpenAI still rejects
    // bad credentials with the HTTP 401 + JSON body shape
    // OpenAiTranscriber.transcribe() parses as authError — catches a silent
    // upstream API change before a user's cloud transcription does. Makes a
    // real network call unconditionally, so it's excluded from the default
    // gate via the `canary` tag (see .github/workflows/ci.yml's
    // `--exclude-tags=golden,canary`) and instead run weekly by
    // .github/workflows/provider-drift-canary.yml.
    test('rejects an invalid API key against the real endpoint', () async {
      final wavFile = File(
        '${Directory.current.path}/test/fixtures/hello_world.wav',
      );
      final wavBytes = await wavFile.readAsBytes();

      final container = _makeContainer({
        'wp_openai_api_key': 'sk-canary-invalid',
      });
      addTearDown(container.dispose);

      final realClient = http.Client();
      final transcriber = container.read(_testTranscriberProvider(realClient));
      addTearDown(transcriber.release);

      await transcriber.prepare();

      await expectLater(
        transcriber.transcribe(wavBytes.toList()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.authError,
          ),
        ),
      );
    }, tags: ['canary']);
  });
}
