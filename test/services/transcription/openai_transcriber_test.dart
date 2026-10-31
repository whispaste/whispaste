import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/transcription/openai_transcriber.dart';
import 'package:whispaste/services/transcription/slice_manifest.dart';
import 'package:whispaste/services/transcription/transcriber.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

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
      (ref, client) =>
          OpenAiTranscriber(ref: ref, httpClient: client, wait: _noWait),
    );

final _testCustomTranscriberProvider =
    Provider.family<OpenAiTranscriber, http.Client>(
      (ref, client) => OpenAiTranscriber.customEndpoint(
        ref: ref,
        httpClient: client,
        wait: _noWait,
      ),
    );

/// Retry waits are skipped in tests; the backoff itself is covered in
/// cloud_retry_test.dart.
Future<void> _noWait(Duration _) async {}

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

    for (final (reply, expected) in [
      ('Thank you for watching.', ''),
      ('(Musik)', ''),
      ('Ich sage (Musik) laut.', 'Ich sage (Musik) laut.'),
    ]) {
      test('drops silence artefacts: "$reply" → "$expected"', () async {
        final client = MockClient(
          (_) async => http.Response(jsonEncode({'text': reply}), 200),
        );
        final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
        addTearDown(container.dispose);

        final transcriber = container.read(_testTranscriberProvider(client));
        await transcriber.prepare();

        expect(await transcriber.transcribe(_silentWav()), expected);
      });
    }

    test('an unexpected API error names the status and the error code, '
        'never the response body', () async {
      const echoed = 'vertrauliches Diktat';
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'message': 'Invalid file: the text was "$echoed"',
              'type': 'invalid_request_error',
              'code': 'invalid_value',
            },
          }),
          400,
        ),
      );
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();

      Object? thrown;
      try {
        await transcriber.transcribe(_silentWav());
      } on TranscriberException catch (e) {
        thrown = e;
      }
      expect(
        thrown,
        isA<TranscriberException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('HTTP 400'),
            contains('invalid_value'),
            isNot(contains(echoed)),
          ),
        ),
      );
    });

    test(
      'the own endpoint rate-limit message names no provider (F35-9)',
      () async {
        final client = MockClient((_) async => http.Response('{}', 429));
        final settings = AppSettings.defaults.copyWithSections(
          cloudProvider: CloudProviderSettings.defaults.copyWith(
            customEndpointUrl: 'http://localhost:1234/v1',
            customEndpointSttModel: 'whisper',
          ),
        );
        final container = _makeContainer({}, settings: settings);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final transcriber = container.read(
          _testCustomTranscriberProvider(client),
        );
        await transcriber.prepare();
        Object? thrown;
        try {
          await transcriber.transcribe(_silentWav());
        } on TranscriberException catch (e) {
          thrown = e;
        }
        expect(
          thrown,
          isA<TranscriberException>()
              .having(
                (e) => e.reason,
                'reason',
                TranscriberFailureReason.rateLimited,
              )
              .having((e) => e.message, 'message', isNot(contains('OpenAI'))),
        );
      },
    );

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

    test('throws rateLimited on HTTP 429 without a billing code', () async {
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
            TranscriberFailureReason.rateLimited,
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
          isA<TranscriberException>()
              .having(
                (e) => e.reason,
                'reason',
                TranscriberFailureReason.authError,
              )
              .having(
                (e) => e.message,
                'message',
                contains('Settings → Speech recognition'),
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

    test(
      'sends gpt-transcribe with the language as languages[] and json output',
      () async {
        late http.MultipartRequest sent;
        final client = MockClient.streaming((request, bodyStream) async {
          sent = request as http.MultipartRequest;
          final body = jsonEncode({'text': 'hallo', 'languages': []});
          return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        });
        final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
        addTearDown(container.dispose);

        final transcriber = container.read(_testTranscriberProvider(client));
        await transcriber.prepare();
        final result = await transcriber.transcribe(
          _silentWav(),
          language: 'de',
        );

        expect(result, 'hallo');
        expect(sent.url.path, '/v1/audio/transcriptions');
        expect(sent.fields['model'], 'gpt-transcribe');
        expect(sent.fields['response_format'], 'json');
        expect(sent.fields['languages[]'], 'de');
        // gpt-transcribe rejects a request that carries both fields.
        expect(sent.fields.containsKey('language'), isFalse);
        expect(sent.files.single.field, 'file');
      },
    );

    test('sends no language field when the language is auto', () async {
      late http.MultipartRequest sent;
      final client = MockClient.streaming((request, bodyStream) async {
        sent = request as http.MultipartRequest;
        final body = jsonEncode({'text': 'ok'});
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav(), language: 'auto');

      expect(sent.fields['model'], 'gpt-transcribe');
      expect(sent.fields.containsKey('languages[]'), isFalse);
      expect(sent.fields.containsKey('language'), isFalse);
    });
  });

  group('OpenAiTranscriber long audio', () {
    // OpenAI rejects uploads above 25 MB with HTTP 413. A 16 kHz mono 16-bit
    // WAV passes that size after about 13 minutes, so a long dictation has to
    // be sent as several uploads that each fit.
    test(
      'sends a 30-minute recording as uploads below the 25 MB limit',
      () async {
        const pcmBytes = 30 * 60 * 32000;
        final wav = Uint8List(44 + pcmBytes)
          ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
        final uploadSizes = <int>[];
        final client = MockClient.streaming((request, bodyStream) async {
          final multipart = request as http.MultipartRequest;
          uploadSizes.add(multipart.files.single.length);
          final body = jsonEncode({'text': 'part ${uploadSizes.length}'});
          return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        });
        final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
        addTearDown(container.dispose);

        final transcriber = container.read(_testTranscriberProvider(client));
        await transcriber.prepare();
        final result = await transcriber.transcribe(wav);

        expect(uploadSizes.length, greaterThan(1));
        for (final size in uploadSizes) {
          expect(size, lessThanOrEqualTo(24 * 1000 * 1000));
        }
        expect(
          result,
          [for (var i = 1; i <= uploadSizes.length; i++) 'part $i'].join(' '),
        );
      },
    );

    test('each slice carries its own header and the original samples', () {
      const pcmBytes = 30 * 60 * 32000;
      final wav = Uint8List(44 + pcmBytes)
        ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
      for (var i = 44; i < wav.length; i += 4099) {
        wav[i] = i & 0xFF;
      }

      final slices = splitWavForUpload(wav);
      final samples = BytesBuilder(copy: false);
      for (final slice in slices) {
        final header = slice.parts.first;
        final pcm = slice.parts.last;
        final view = ByteData.sublistView(header);
        expect(view.getUint32(40, Endian.little), pcm.length);
        expect(slice.length, 44 + pcm.length);
        samples.add(pcm);
      }

      expect(slices.length, greaterThan(1));
      expect(samples.toBytes(), wav.sublist(44));
    });

    test('repairs an unfinished recording before it is uploaded', () async {
      // A recording cut off by a crash: RIFF and data sizes still zero.
      const pcmBytes = 3200;
      final wav = Uint8List(44 + pcmBytes)
        ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
      ByteData.sublistView(wav)
        ..setUint32(4, 0, Endian.little)
        ..setUint32(40, 0, Endian.little);
      Uint8List? uploaded;
      final client = MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        final chunks = await multipart.files.single.finalize().toList();
        uploaded = Uint8List.fromList([for (final c in chunks) ...c]);
        final body = jsonEncode({'text': 'ok'});
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(wav);

      final view = ByteData.sublistView(uploaded!);
      expect(view.getUint32(40, Endian.little), pcmBytes);
      expect(view.getUint32(4, Endian.little), 36 + pcmBytes);
      expect(uploaded!.length, 44 + pcmBytes);
    });

    test('keeps a short recording in a single upload', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'text': 'short'}), 200);
      });
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);

      final transcriber = container.read(_testTranscriberProvider(client));
      await transcriber.prepare();
      await transcriber.transcribe(_silentWav());

      expect(requests, 1);
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
        addTearDown(realClient.close);

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
      addTearDown(realClient.close);

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

  group('OpenAiTranscriber retry and resume', () {
    // Two slices: 19.2 MB and 5.8 MB of PCM.
    Uint8List longWav() {
      const pcm = 25000000;
      return Uint8List.fromList([
        ...wavHeaderPcm16Mono(pcm),
        ...Uint8List(pcm),
      ]);
    }

    OpenAiTranscriber transcriberFor(http.Client client) {
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);
      return container.read(_testTranscriberProvider(client));
    }

    http.Response textReply(String text) =>
        http.Response(jsonEncode({'text': text}), 200);

    test(
      'retries 429 and 503 per request and returns the later reply',
      () async {
        final replies = [
          http.Response('Rate limited', 429),
          http.Response('busy', 503),
          textReply('hallo'),
        ];
        var calls = 0;
        final transcriber = transcriberFor(
          MockClient((_) async => replies[calls++]),
        );
        await transcriber.prepare();

        expect(await transcriber.transcribe(_silentWav()), 'hallo');
        expect(calls, 3);
      },
    );

    test(
      'a 5xx that survives three attempts is a repeatable serverError',
      () async {
        var calls = 0;
        final transcriber = transcriberFor(
          MockClient((_) async {
            calls++;
            return http.Response('boom', 500);
          }),
        );
        await transcriber.prepare();

        await expectLater(
          transcriber.transcribe(_silentWav()),
          throwsA(
            isA<TranscriberException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  TranscriberFailureReason.serverError,
                )
                .having(
                  (e) => transcriptionErrorCode(e),
                  'code',
                  'cloud_server_error',
                ),
          ),
        );
        expect(calls, 3);
      },
    );

    test('a 429 with insufficient_quota is quota and not retried', () async {
      var calls = 0;
      final transcriber = transcriberFor(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'insufficient_quota'},
            }),
            429,
          );
        }),
      );
      await transcriber.prepare();

      await expectLater(
        transcriber.transcribe(_silentWav()),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.quotaExceeded,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('a 401 is not retried', () async {
      var calls = 0;
      final transcriber = transcriberFor(
        MockClient((_) async {
          calls++;
          return http.Response('no', 401);
        }),
      );
      await transcriber.prepare();

      await expectLater(
        transcriber.transcribe(_silentWav()),
        throwsA(isA<TranscriberException>()),
      );
      expect(calls, 1);
    });

    test(
      'a failed later slice keeps the finished slices; a retry sends only the rest',
      () async {
        final wav = longWav();
        var calls = 0;
        final failing = transcriberFor(
          MockClient((_) async {
            calls++;
            return calls == 1 ? textReply('eins') : http.Response('boom', 500);
          }),
        );
        await failing.prepare();

        await expectLater(
          failing.transcribe(wav),
          throwsA(
            isA<TranscriberException>().having(
              (e) => e.completedParts,
              'completedParts',
              ['eins'],
            ),
          ),
        );
        // Slice 1 once, slice 2 three times.
        expect(calls, 4);

        var resumedCalls = 0;
        final resumed = transcriberFor(
          MockClient((_) async {
            resumedCalls++;
            return textReply('zwei');
          }),
        );
        await resumed.prepare();

        expect(
          await resumed.transcribeResumable(
            wav,
            completedParts: const ['eins'],
          ),
          'eins zwei',
        );
        expect(resumedCalls, 1);
      },
    );

    test('cancelling stops before the next slice', () async {
      final wav = longWav();
      var cancelled = false;
      var calls = 0;
      final transcriber = transcriberFor(
        MockClient((_) async {
          calls++;
          cancelled = true;
          return textReply('eins');
        }),
      );
      await transcriber.prepare();

      await expectLater(
        transcriber.transcribeResumable(wav, isCancelled: () => cancelled),
        throwsA(
          isA<TranscriberException>()
              .having(
                (e) => e.reason,
                'reason',
                TranscriberFailureReason.cancelled,
              )
              .having((e) => e.completedParts, 'completedParts', ['eins']),
        ),
      );
      expect(calls, 1);
    });
  });

  group('OpenAiTranscriber slice cuts (LONG-AUDIO T5)', () {
    const sliceLimit = 10 * 60 * 32000;
    const secondBytes = 32000;

    /// [pcmBytes] of loud PCM (a constant 8000 counts as speech, RMS about
    /// 0.24), with the byte ranges in [pauses] set to digital silence.
    Uint8List wavWithPauses(int pcmBytes, List<(int, int)> pauses) {
      final wav = Uint8List(44 + pcmBytes)
        ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
      final tile = Uint8List(secondBytes);
      for (var i = 0; i < tile.length; i += 2) {
        tile[i] = 0x40;
        tile[i + 1] = 0x1F;
      }
      for (var at = 0; at < pcmBytes; at += secondBytes) {
        final end = at + secondBytes <= pcmBytes ? at + secondBytes : pcmBytes;
        wav.setRange(44 + at, 44 + end, tile);
      }
      for (final (start, end) in pauses) {
        wav.fillRange(44 + start, 44 + end, 0);
      }
      return wav;
    }

    OpenAiTranscriber transcriberFor(http.Client client) {
      final container = _makeContainer({'wp_openai_api_key': 'sk-test'});
      addTearDown(container.dispose);
      return container.read(_testTranscriberProvider(client));
    }

    http.Response textReply(String text) =>
        http.Response(jsonEncode({'text': text}), 200);

    http.StreamedResponse streamedText(String text, {int status = 200}) =>
        http.StreamedResponse(
          Stream.value(
            utf8.encode(status == 200 ? jsonEncode({'text': text}) : text),
          ),
          status,
        );

    /// Proves [view] is a view into [wav] (no copy): a write through the
    /// recording shows up in the view. `ByteBuffer` objects are wrappers, so
    /// comparing `.buffer` with `identical` would not tell.
    void expectSharesRecording(Uint8List view, Uint8List wav) {
      final at = view.offsetInBytes - wav.offsetInBytes;
      final original = wav[at];
      wav[at] = original ^ 0xFF;
      expect(view[0], original ^ 0xFF);
      wav[at] = original;
    }

    // 13 minutes: the first cut is at the 10-minute limit.
    const longPcm = 25000000;

    test('cuts at the latest pause before the slice limit', () {
      // A one-second pause at 595 s to 596 s; its middle is 595.5 s.
      final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
      final slices = splitWavForUpload(wav);

      expect(slices.length, 2);
      expect(slices.first.length, 44 + 19056000);
      expect(slices.first.overlapsPrevious, isFalse);
      expect(slices[1].overlapsPrevious, isFalse);
      expect(slices[1].length, 44 + longPcm - 19056000);
    });

    test('a hard cut overlaps the next slice by 2 s and copies nothing', () {
      final wav = wavWithPauses(longPcm, const []);
      final slices = splitWavForUpload(wav);

      expect(slices.length, 2);
      expect(slices.first.length, 44 + sliceLimit);
      expect(slices.first.overlapsPrevious, isFalse);
      expect(slices[1].overlapsPrevious, isTrue);
      const overlapStart = sliceLimit - 64000;
      expect(slices[1].length, 44 + longPcm - overlapStart);
      final samples = slices[1].parts.last;
      expect(samples.offsetInBytes, wav.offsetInBytes + 44 + overlapStart);
      // Views only: every slice shares the recording's buffer.
      for (final slice in slices) {
        expectSharesRecording(slice.parts.last, wav);
      }
    });

    test('joins hard-cut seams without the repeated words only', () {
      final hard = [
        const WavUploadSlice([], 0),
        const WavUploadSlice([], 0, overlapsPrevious: true),
      ];
      final pause = [const WavUploadSlice([], 0), const WavUploadSlice([], 0)];
      const texts = ['wir gehen heute nach Hause.', 'nach Hause und dann'];

      expect(
        joinSliceTexts(texts, hard),
        'wir gehen heute nach Hause. und dann',
      );
      expect(
        joinSliceTexts(texts, pause),
        'wir gehen heute nach Hause. nach Hause und dann',
      );
      expect(joinSliceTexts(['', 'eins'], hard), 'eins');
    });

    test(
      'a retry after a finished slice uses the same cut (manifest compatible)',
      () async {
        // A pause at 595 s to 596 s, so the first slice ends in the pause.
        final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
        final expected = [for (final s in splitWavForUpload(wav)) s.length];
        // Slice 2 fails with a permanent error, so only slice 1 is finished.
        var calls = 0;
        final failing = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            calls++;
            if (calls == 1) return streamedText('eins');
            return streamedText('bad request', status: 400);
          }),
        );
        await failing.prepare();
        await expectLater(
          failing.transcribe(wav),
          throwsA(
            isA<TranscriberException>().having(
              (e) => e.completedParts,
              'completedParts',
              ['eins'],
            ),
          ),
        );

        final retried = <int>[];
        final resumed = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            retried.add((request as http.MultipartRequest).files.single.length);
            return streamedText('zwei');
          }),
        );
        await resumed.prepare();
        expect(
          await resumed.transcribeResumable(
            wav,
            completedParts: const ['eins'],
          ),
          'eins zwei',
        );
        // The retry sends only the unfinished slice, with the same length the
        // split gives it on the first run.
        expect(retried, [expected[1]]);
        expect(expected.length, 2);
        expect(expected[0], 44 + 19056000);
      },
    );

    test(
      'the next slice gets the previous slice text as prompt context',
      () async {
        final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
        final prompts = <String?>[];
        final replies = ['erster Satz', 'zweiter Satz'];
        final transcriber = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            prompts.add((request as http.MultipartRequest).fields['prompt']);
            return streamedText(replies[prompts.length - 1]);
          }),
        );
        await transcriber.prepare();

        expect(await transcriber.transcribe(wav), 'erster Satz zweiter Satz');
        expect(prompts, [null, 'erster Satz']);
      },
    );

    test('a looping slice passes no context on', () async {
      final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
      final prompts = <String?>[];
      final replies = ['danke danke danke danke danke danke', 'weiter'];
      final transcriber = transcriberFor(
        MockClient.streaming((request, bodyStream) async {
          prompts.add((request as http.MultipartRequest).fields['prompt']);
          return streamedText(replies[prompts.length - 1]);
        }),
      );
      await transcriber.prepare();

      await transcriber.transcribe(wav);
      expect(prompts, [null, null]);
    });

    test('a prompt echoed at the start of a slice is removed', () async {
      final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
      final replies = ['erster Satz', 'erster Satz und weiter'];
      var calls = 0;
      final transcriber = transcriberFor(
        MockClient((request) async {
          calls++;
          return textReply(replies[calls - 1]);
        }),
      );
      await transcriber.prepare();

      expect(await transcriber.transcribe(wav), 'erster Satz und weiter');
    });

    test('a retry derives the same context from the stored text', () async {
      final wav = wavWithPauses(longPcm, [(19040000, 19072000)]);
      final prompts = <String?>[];
      final resumed = transcriberFor(
        MockClient.streaming((request, bodyStream) async {
          prompts.add((request as http.MultipartRequest).fields['prompt']);
          return streamedText('zweiter Satz');
        }),
      );
      await resumed.prepare();

      expect(
        await resumed.transcribeResumable(
          wav,
          completedParts: const ['erster Satz'],
        ),
        'erster Satz zweiter Satz',
      );
      expect(prompts, ['erster Satz']);
    });

    test('splits 30 minutes of audio in milliseconds without copying', () {
      final wav = wavWithPauses(30 * 60 * 32000, const []);
      final watch = Stopwatch()..start();
      final slices = splitWavForUpload(wav);
      watch.stop();
      // ignore: avoid_print
      print(
        'splitWavForUpload 30 min: ${watch.elapsedMilliseconds} ms, '
        '${slices.length} slices',
      );

      expect(slices.length, 4);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      for (final slice in slices) {
        expectSharesRecording(slice.parts.last, wav);
      }
    });

    // Three slices: pauses at 595 s and 1190 s, the rest is loud speech.
    const threeSlicePcm = 45000000;
    final threeSliceWavPauses = [(19040000, 19072000), (38040000, 38072000)];

    test(
      'checkpoints each finished slice in order, and only for a split upload',
      () async {
        final wav = wavWithPauses(threeSlicePcm, threeSliceWavPauses);
        expect(splitWavForUpload(wav).length, 3);
        final replies = ['eins', 'zwei', 'drei'];
        var calls = 0;
        final transcriber = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            return streamedText(replies[calls++]);
          }),
        );
        await transcriber.prepare();
        final checkpoints = <List<String>>[];
        final totals = <int>[];

        await transcriber.transcribeResumable(
          wav,
          onSliceDone: (parts, total) async {
            checkpoints.add(List.of(parts));
            totals.add(total);
          },
        );

        expect(checkpoints, [
          <String>[],
          ['eins'],
          ['eins', 'zwei'],
          ['eins', 'zwei', 'drei'],
        ]);
        expect(totals, [3, 3, 3, 3]);

        final short = transcriberFor(
          MockClient.streaming(
            (request, bodyStream) async => streamedText('kurz'),
          ),
        );
        await short.prepare();
        final shortCalls = <(List<String>, int)>[];
        final shortWav = Uint8List.fromList([
          ...wavHeaderPcm16Mono(3200),
          ...Uint8List(3200),
        ]);
        await short.transcribeResumable(
          shortWav,
          onSliceDone: (parts, total) async => shortCalls.add((parts, total)),
        );
        expect(shortCalls, isEmpty);
      },
    );

    test(
      'an interrupted run resumes to the same text and requests as an uninterrupted one',
      () async {
        final wav = wavWithPauses(threeSlicePcm, threeSliceWavPauses);
        final replies = ['erster Satz', 'zweiter Satz', 'dritter Satz'];

        // The reference: one run without interruption.
        final uninterruptedPrompts = <String?>[];
        var calls = 0;
        final uninterrupted = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            uninterruptedPrompts.add(
              (request as http.MultipartRequest).fields['prompt'],
            );
            return streamedText(replies[calls++]);
          }),
        );
        await uninterrupted.prepare();
        final expected = await uninterrupted.transcribe(wav);

        // The interrupted run: slice 3 fails for good, after the manifest was
        // written for slices 1 and 2. The manifest is an in-memory store here.
        final dir = Directory.systemTemp.createTempSync('wp_slice_resume_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final manifestPath = '${dir.path}/entry.slices';
        var failingCalls = 0;
        final interrupted = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            failingCalls++;
            if (failingCalls <= 2) {
              return streamedText(replies[failingCalls - 1]);
            }
            return streamedText('bad request', status: 400);
          }),
        );
        await interrupted.prepare();
        final writer = SliceCheckpointWriter(
          manifest: SliceManifest(manifestPath),
          wavLength: wav.length,
          persisted: 0,
        );
        await expectLater(
          interrupted.transcribeResumable(wav, onSliceDone: writer.call),
          throwsA(isA<TranscriberException>()),
        );
        expect(failingCalls, 3);

        // The resumed run sends only slice 3, with the same prompt context the
        // uninterrupted run gave it.
        final resumedPrompts = <String?>[];
        final resumed = transcriberFor(
          MockClient.streaming((request, bodyStream) async {
            resumedPrompts.add(
              (request as http.MultipartRequest).fields['prompt'],
            );
            return streamedText(replies[2]);
          }),
        );
        await resumed.prepare();
        final result = await transcribeWithSliceManifest(
          resumed,
          wav,
          manifestPath: manifestPath,
        );

        expect(result, expected);
        expect(resumedPrompts, [uninterruptedPrompts[2]]);
        expect(resumedPrompts.single, 'zweiter Satz');
      },
    );
  });
}
