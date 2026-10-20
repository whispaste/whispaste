/// Integration tests for [AutomationApiController] — real HTTP requests
/// against a real, loopback-bound server started/stopped through the
/// controller, exactly the way `app.dart` and the settings section drive it.
///
/// Ephemeral ports (`port: 0`, injected via the constructor) so parallel
/// test runs never collide on `kAutomationApiDefaultPort`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/history/data/history_pin.dart';
import 'package:whispaste/core/recording/recording_state.dart'
    show RecordingPhase, recordingPhaseProvider, recordingProvider;
import 'package:whispaste/services/automation_api/multiline_paste_confirmation.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart'
    show DictationTriggerResult;
import 'package:whispaste/services/automation_api/automation_api_server.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

/// Delays only the *first-ever* call to [start] before delegating to the
/// real bind logic — used to deterministically reproduce the race where a
/// second, concurrent `_start()` reaches the real bind well before the
/// first one (which is what actually happened in production: the first
/// call's token-store read was slow, giving a second, redundant
/// `syncWithSettings` call time to win the real bind first).
class _FirstCallDelayedServer extends AutomationApiServer {
  bool _delayedOnce = false;

  @override
  Future<int> start({required int port, required Handler handler}) async {
    if (!_delayedOnce) {
      _delayedOnce = true;
      await Future.delayed(const Duration(milliseconds: 30));
    }
    return super.start(port: port, handler: handler);
  }
}

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> store = {};

  @override
  Future<String?> readKey(String key) async => store[key];

  @override
  Future<void> writeKey(String key, String value) async => store[key] = value;

  @override
  Future<void> deleteKey(String key) async => store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => Map.of(store);
}

/// Hand-rolled fake — same style as `paste_capability_notifier_test.dart`'s
/// `_FakePaster`. [paste] always reports [nextOutcome] and records the
/// pasted [texts], regardless of `prime()` ever being called (the
/// automation API's snippet-insert path never primes — see
/// `SnippetPickerService`'s doc comment on why).
class _FakePaster implements Paster {
  PasteOutcome nextOutcome = PasteOutcome.success;
  final List<String> texts = [];

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    texts.add(text);
    return nextOutcome;
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async {
    texts.add(text);
    return nextOutcome;
  }

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async {
    return const PasteCapability(status: PasteCapabilityStatus.ready);
  }

  @override
  Future<String?> getTargetBundleId() async => null;
}

Future<HttpClientResponse> _get(
  int port, {
  String path = '/',
  String? bearer,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  final request = await client.get('127.0.0.1', port, path);
  if (bearer != null) {
    request.headers.set('authorization', 'Bearer $bearer');
  }
  return request.close();
}

Future<HttpClientResponse> _post(
  int port, {
  String path = '/v1/dictation/trigger',
  String? bearer,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  final request = await client.post('127.0.0.1', port, path);
  if (bearer != null) {
    request.headers.set('authorization', 'Bearer $bearer');
  }
  return request.close();
}

/// A valid 16 kHz mono 16-bit WAV header with 32 bytes of silence.
final _tinyWav = <int>[
  ...'RIFF'.codeUnits,
  68,
  0,
  0,
  0,
  ...'WAVE'.codeUnits,
  ...'fmt '.codeUnits,
  16,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0x80,
  0x3e,
  0,
  0,
  0,
  0x7d,
  0,
  0,
  2,
  0,
  16,
  0,
  ...'data'.codeUnits,
  32,
  0,
  0,
  0,
  ...List<int>.filled(32, 0),
];

Future<HttpClientResponse> _postWav(
  int port,
  List<int> wav, {
  String? bearer,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  final request = await client.post('127.0.0.1', port, '/v1/transcriptions');
  request.headers.contentType = ContentType('audio', 'wav');
  if (bearer != null) {
    request.headers.set('authorization', 'Bearer $bearer');
  }
  request.add(wav);
  return request.close();
}

Future<Object?> _readJson(HttpClientResponse response) async =>
    jsonDecode(await utf8.decodeStream(response));

class _FakeTranscriber implements Transcriber {
  int calls = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    return 'fake transcript';
  }

  @override
  void release() {}
}

Future<HttpClientResponse> _postJson(
  int port,
  String path,
  Object? body, {
  String? bearer,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (bearer != null) {
    request.headers.set('authorization', 'Bearer $bearer');
  }
  request.write(jsonEncode(body));
  return request.close();
}

void main() {
  late ProviderContainer container;
  var triggerCallCount = 0;
  bool? lastTriggerWait;
  String? lastTriggerLanguage;
  String? lastTriggerSmartModePreset;
  double? lastTriggerSilenceTimeout;
  var triggerResult = const DictationTriggerResult(recording: true);

  ProviderContainer buildContainer({
    List<Override> extra = const [],
    HistoryDatabase? db,
    _FakePaster? paster,
    // Ephemeral (OS-assigned) by default, same as every other test in this
    // file. Port-fallback tests below override it with a specific,
    // deliberately pre-occupied port.
    int port = 0,
    AutomationApiServer? server,
  }) {
    triggerCallCount = 0;
    lastTriggerWait = null;
    lastTriggerLanguage = null;
    lastTriggerSmartModePreset = null;
    lastTriggerSilenceTimeout = null;
    triggerResult = const DictationTriggerResult(recording: true);
    return ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
        if (db != null)
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        if (paster != null) pasterProvider.overrideWithValue(paster),
        ...extra,
        automationApiControllerProvider.overrideWith(
          () => AutomationApiController(
            port: port,
            server: server,
            triggerDictation:
                (
                  ref, {
                  wait = false,
                  language,
                  smartModePreset,
                  silenceTimeout,
                }) async {
                  triggerCallCount++;
                  lastTriggerWait = wait;
                  lastTriggerLanguage = language;
                  lastTriggerSmartModePreset = smartModePreset;
                  lastTriggerSilenceTimeout = silenceTimeout;
                  return triggerResult;
                },
          ),
        ),
      ],
    );
  }

  tearDown(() {
    container.dispose();
  });

  test(
    'settings.automationApi.enabled == false (the default) → no port listens',
    () async {
      container = buildContainer();
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );

      await controller.syncWithSettings(AppSettings.defaults);

      final state = container.read(automationApiControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.port, isNull);
    },
  );

  test('enabling starts a real server, generates a token, and the settings '
      'state reflects the bound port', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);

    await controller.syncWithSettings(
      AppSettings.defaults.copyWithSections(
        automationApi: const AutomationApiSettings(enabled: true),
      ),
    );

    final state = container.read(automationApiControllerProvider);
    expect(state.isRunning, isTrue);
    expect(state.port, isNotNull);
    expect(state.token, isNotEmpty);

    final response = await _post(state.port!, bearer: state.token);
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(body['status'], 'triggered');
    expect(body['recording'], isTrue);
    expect(triggerCallCount, 1);
  });

  test('a request with no token → 401, the use case is never called', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);
    await controller.syncWithSettings(
      AppSettings.defaults.copyWithSections(
        automationApi: const AutomationApiSettings(enabled: true),
      ),
    );
    final port = container.read(automationApiControllerProvider).port!;

    final response = await _post(port);

    expect(response.statusCode, 401);
    expect(triggerCallCount, 0);
  });

  test('a request with a wrong token → 401 — no "localhost is trusted" '
      'exception even though the request originates from 127.0.0.1', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);
    await controller.syncWithSettings(
      AppSettings.defaults.copyWithSections(
        automationApi: const AutomationApiSettings(enabled: true),
      ),
    );
    final port = container.read(automationApiControllerProvider).port!;

    final response = await _post(port, bearer: 'definitely-wrong');

    expect(response.statusCode, 401);
    expect(triggerCallCount, 0);
  });

  test('disabling stops the server — the port no longer accepts '
      'connections', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);
    await controller.syncWithSettings(
      AppSettings.defaults.copyWithSections(
        automationApi: const AutomationApiSettings(enabled: true),
      ),
    );
    final port = container.read(automationApiControllerProvider).port!;

    await controller.syncWithSettings(AppSettings.defaults);

    final state = container.read(automationApiControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.port, isNull);

    var refused = false;
    try {
      await _get(port);
    } on SocketException {
      refused = true;
    }
    expect(refused, isTrue);
  });

  test('regenerateToken() invalidates the old token immediately — old '
      '401s, new succeeds', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);
    await controller.syncWithSettings(
      AppSettings.defaults.copyWithSections(
        automationApi: const AutomationApiSettings(enabled: true),
      ),
    );
    final port = container.read(automationApiControllerProvider).port!;
    final oldToken = container.read(automationApiControllerProvider).token!;

    final newToken = await controller.regenerateToken();
    expect(newToken, isNot(oldToken));

    final oldResponse = await _post(port, bearer: oldToken);
    expect(oldResponse.statusCode, 401);

    final newResponse = await _post(port, bearer: newToken);
    expect(newResponse.statusCode, 200);
  });

  test('syncWithSettings is idempotent — calling it twice with the same '
      'enabled value does not throw or restart the server', () async {
    container = buildContainer();
    final controller = container.read(automationApiControllerProvider.notifier);
    final enabledSettings = AppSettings.defaults.copyWithSections(
      automationApi: const AutomationApiSettings(enabled: true),
    );

    await controller.syncWithSettings(enabledSettings);
    final firstPort = container.read(automationApiControllerProvider).port;

    await controller.syncWithSettings(enabledSettings);
    final secondPort = container.read(automationApiControllerProvider).port;

    expect(firstPort, secondPort);
  });

  // XP-2-08: the stop log named its caller with a captured stack trace, which
  // read like a crash in every SIGTERM shutdown log.
  group('stop logging names the reason, without a stack trace', () {
    late List<LogRecord> stopLogs;
    late StreamSubscription<LogRecord> logSub;
    late Level previousLevel;

    setUp(() {
      previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      stopLogs = [];
      logSub = Logger.root.onRecord
          .where((r) => r.message.startsWith('_stop:'))
          .listen(stopLogs.add);
    });

    tearDown(() async {
      await logSub.cancel();
      Logger.root.level = previousLevel;
    });

    test('shutdown() of a server that never ran', () async {
      container = buildContainer();
      await container.read(automationApiControllerProvider.notifier).shutdown();

      expect(stopLogs, hasLength(1));
      expect(stopLogs.single.message, contains('app shutdown'));
      expect(stopLogs.single.stackTrace, isNull);
      expect(
        container.read(automationApiControllerProvider).runState,
        AutomationApiRunState.stopped,
      );
    });

    test('shutdown() of a running server stops it', () async {
      container = buildContainer();
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );

      await controller.shutdown();

      expect(
        container.read(automationApiControllerProvider).isRunning,
        isFalse,
      );
      expect(stopLogs.single.message, contains('app shutdown'));
      expect(stopLogs.single.stackTrace, isNull);
    });

    test('disabling in the settings', () async {
      container = buildContainer();
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );

      await controller.syncWithSettings(AppSettings.defaults);

      expect(stopLogs.single.message, contains('settings disabled'));
      expect(stopLogs.single.stackTrace, isNull);
    });
  });

  group('port fallback (port robustness ticket)', () {
    test('the target port is already bound → the controller falls back to '
        'the next free port and reports both the actual and requested port '
        'in state', () async {
      // Hold a real socket open on a port the controller will then be
      // asked to target, forcing its first bind attempt to fail exactly
      // the way a real EADDRINUSE would.
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final occupiedPort = blocker.port;
      addTearDown(blocker.close);

      container = buildContainer(port: occupiedPort);
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );

      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: AutomationApiSettings(
            enabled: true,
            customPort: occupiedPort,
          ),
        ),
      );

      final state = container.read(automationApiControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.requestedPort, occupiedPort);
      expect(state.port, isNot(occupiedPort));
      expect(state.port! > occupiedPort, isTrue);
    });

    test(
      'the target port and every fallback candidate are all bound → '
      'error state with the requested port (not just an actual bound one)',
      () async {
        // Occupy the target port and every port the fallback loop would
        // try after it (kAutomationApiPortFallbackAttempts consecutive
        // ports), so every single bind attempt fails.
        final blockers = await _bindConsecutivePorts(
          kAutomationApiPortFallbackAttempts,
        );
        final basePort = blockers.first.port;
        addTearDown(() async {
          for (final blocker in blockers) {
            await blocker.close();
          }
        });

        container = buildContainer(port: basePort);
        final controller = container.read(
          automationApiControllerProvider.notifier,
        );

        await controller.syncWithSettings(
          AppSettings.defaults.copyWithSections(
            automationApi: AutomationApiSettings(
              enabled: true,
              customPort: basePort,
            ),
          ),
        );

        final state = container.read(automationApiControllerProvider);
        expect(state.runState, AutomationApiRunState.error);
        expect(state.port, isNull);
        expect(state.requestedPort, basePort);
      },
    );

    test('disabling after an all-ports-occupied failure actually clears the '
        'error state — syncWithSettings must not compare shouldRun only '
        'against _server.isRunning, since a failed start never set that to '
        'true in the first place', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final basePort = probe.port;
      await probe.close();

      final blockers = <ServerSocket>[];
      for (var i = 0; i < kAutomationApiPortFallbackAttempts; i++) {
        blockers.add(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, basePort + i),
        );
      }
      addTearDown(() async {
        for (final blocker in blockers) {
          await blocker.close();
        }
      });

      container = buildContainer(port: basePort);
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );

      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: AutomationApiSettings(
            enabled: true,
            customPort: basePort,
          ),
        ),
      );
      expect(
        container.read(automationApiControllerProvider).runState,
        AutomationApiRunState.error,
      );

      // Turn the setting off again — the underlying server never bound
      // anything, so _server.isRunning was false both before and after
      // this call. If syncWithSettings short-circuits on that comparison
      // alone, the error state survives the toggle.
      await controller.syncWithSettings(AppSettings.defaults);

      final state = container.read(automationApiControllerProvider);
      expect(state.runState, AutomationApiRunState.stopped);
      expect(state.port, isNull);
      expect(state.requestedPort, isNull);
    });

    test('a second syncWithSettings firing while the first is still starting '
        '(e.g. an unrelated settings write racing the toggle) must not '
        'clobber the successful "running" state with a false "error" — '
        'mirrors the real app.dart settings listener firing twice for one '
        'toggle', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final targetPort = probe.port;
      await probe.close();

      // The delayed server deterministically reproduces the production
      // timing: the first `_start()` call's real bind is slow (in
      // production this was the token-store/keychain read), giving a
      // second, concurrent call time to reach the real bind first.
      container = buildContainer(
        port: targetPort,
        server: _FirstCallDelayedServer(),
      );
      final controller = container.read(
        automationApiControllerProvider.notifier,
      );

      final settings = AppSettings.defaults.copyWithSections(
        automationApi: AutomationApiSettings(
          enabled: true,
          customPort: targetPort,
        ),
      );

      // Neither call is awaited before the next starts — both run their
      // synchronous prelude (reading `state`/`_server.isRunning`) before
      // either's first `await` resumes, exactly like two settings-changed
      // notifications firing back-to-back in app.dart.
      final first = controller.syncWithSettings(settings);
      final second = controller.syncWithSettings(settings);
      await Future.wait([first, second]);

      final state = container.read(automationApiControllerProvider);
      expect(state.runState, AutomationApiRunState.running);
      expect(state.port, targetPort);
      expect(state.requestedPort, targetPort);
    });
  });

  group('POST /v1/transcriptions — dictation has priority', () {
    Future<int> startEnabled(ProviderContainer c) async {
      await c
          .read(automationApiControllerProvider.notifier)
          .syncWithSettings(
            AppSettings.defaults.copyWithSections(
              automationApi: const AutomationApiSettings(enabled: true),
            ),
          );
      return c.read(automationApiControllerProvider).port!;
    }

    test('while a recording runs, the route answers 409 busy and the '
        'transcriber is never used', () async {
      final transcriber = _FakeTranscriber();
      container = buildContainer(
        extra: [
          recordingPhaseProvider.overrideWithValue(RecordingPhase.recording),
          transcriberProvider.overrideWithValue(transcriber),
        ],
      );
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postWav(port, _tinyWav, bearer: token);

      expect(response.statusCode, 409);
      expect(await _readJson(response), {'error': 'busy'});
      expect(transcriber.calls, 0);
    });

    test(
      'while a dictation is being transcribed, the route is also busy',
      () async {
        final transcriber = _FakeTranscriber();
        container = buildContainer(
          extra: [
            recordingPhaseProvider.overrideWithValue(
              RecordingPhase.transcribing,
            ),
            transcriberProvider.overrideWithValue(transcriber),
          ],
        );
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final response = await _postWav(port, _tinyWav, bearer: token);

        expect(response.statusCode, 409);
        expect(transcriber.calls, 0);
      },
    );

    for (final phase in [RecordingPhase.done, RecordingPhase.error]) {
      test('an end state of ${phase.name} does not block the route', () async {
        final transcriber = _FakeTranscriber();
        container = buildContainer(
          extra: [
            recordingPhaseProvider.overrideWithValue(phase),
            transcriberProvider.overrideWithValue(transcriber),
          ],
        );
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final response = await _postWav(port, _tinyWav, bearer: token);

        expect(response.statusCode, 200);
        expect(transcriber.calls, 1);
      });

      test('status for ${phase.name} agrees: busy false', () async {
        container = buildContainer(
          extra: [recordingPhaseProvider.overrideWithValue(phase)],
        );
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final response = await _get(port, path: '/v1/status', bearer: token);
        final json = await _readJson(response) as Map;

        expect((json['dictation'] as Map)['busy'], isFalse);
      });
    }

    test(
      'status for transcribing agrees: busy true, and the route gives 409',
      () async {
        container = buildContainer(
          extra: [
            recordingPhaseProvider.overrideWithValue(
              RecordingPhase.transcribing,
            ),
          ],
        );
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final status =
            await _readJson(await _get(port, path: '/v1/status', bearer: token))
                as Map;
        final upload = await _postWav(port, _tinyWav, bearer: token);

        expect((status['dictation'] as Map)['busy'], isTrue);
        expect(upload.statusCode, 409);
      },
    );

    test(
      'when idle, the WAV is transcribed and the transcript returned',
      () async {
        final transcriber = _FakeTranscriber();
        container = buildContainer(
          extra: [
            recordingPhaseProvider.overrideWithValue(RecordingPhase.idle),
            transcriberProvider.overrideWithValue(transcriber),
          ],
        );
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final response = await _postWav(port, _tinyWav, bearer: token);

        expect(response.statusCode, 200);
        expect(await _readJson(response), {'transcript': 'fake transcript'});
        expect(transcriber.calls, 1);
      },
    );
  });

  group('POST /v1/dictation/trigger — wait & language', () {
    Future<int> startEnabled(ProviderContainer c) async {
      final controller = c.read(automationApiControllerProvider.notifier);
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );
      return c.read(automationApiControllerProvider).port!;
    }

    test('an empty body behaves exactly like no body — wait defaults to '
        'false, language defaults to null', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(
        port,
        '/v1/dictation/trigger',
        {},
        bearer: token,
      );

      expect(response.statusCode, 200);
      expect(lastTriggerWait, isFalse);
      expect(lastTriggerLanguage, isNull);
    });

    test('a valid language code is forwarded to the trigger callback and '
        'echoed back as `recording: true` for a starting call', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;
      triggerResult = const DictationTriggerResult(recording: true);

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'language': 'en',
      }, bearer: token);

      expect(response.statusCode, 200);
      expect(lastTriggerLanguage, 'en');
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['recording'], isTrue);
      expect(body.containsKey('transcript'), isFalse);
    });

    test('"auto" is accepted as a language code even though it is not in '
        'whisperLanguageCodes', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'language': 'auto',
      }, bearer: token);

      expect(response.statusCode, 200);
      expect(lastTriggerLanguage, 'auto');
    });

    test('a valid smart_mode_preset is forwarded to the trigger callback '
        '(discussion #147)', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'smart_mode_preset': 'cleanup',
      }, bearer: token);

      expect(response.statusCode, 200);
      expect(lastTriggerSmartModePreset, 'cleanup');
    });

    test('an unrecognised smart_mode_preset → 400 invalid_request, the use '
        'case is never called', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'smart_mode_preset': 'not-a-real-preset',
      }, bearer: token);

      expect(response.statusCode, 400);
      expect(triggerCallCount, 0);
    });

    test('a valid silence_timeout is forwarded to the trigger callback '
        '(discussion #147)', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'silence_timeout': 12.5,
      }, bearer: token);

      expect(response.statusCode, 200);
      expect(lastTriggerSilenceTimeout, 12.5);
    });

    test('silence_timeout: 0 disables auto-stop and is still forwarded '
        '(not treated as absent)', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'silence_timeout': 0,
      }, bearer: token);

      expect(response.statusCode, 200);
      expect(lastTriggerSilenceTimeout, 0.0);
    });

    test('a negative silence_timeout → 400 invalid_request, the use case is '
        'never called', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'silence_timeout': -1,
      }, bearer: token);

      expect(response.statusCode, 400);
      expect(triggerCallCount, 0);
    });

    test('an unrecognised language code → 400 invalid_request, the use case '
        'is never called', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'language': 'not-a-real-code',
      }, bearer: token);

      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['error'], 'invalid_request');
      expect(triggerCallCount, 0);
    });

    test('a non-boolean `wait` field → 400 invalid_request', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'wait': 'yes',
      }, bearer: token);

      expect(response.statusCode, 400);
      expect(triggerCallCount, 0);
    });

    test('a JSON body that is not an object → 400 invalid_request', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/dictation/trigger', [
        1,
        2,
      ], bearer: token);

      expect(response.statusCode, 400);
      expect(triggerCallCount, 0);
    });

    test('`wait: true` on a call that stops a recording includes the '
        'finished transcript in the response', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;
      triggerResult = const DictationTriggerResult(
        recording: false,
        transcript: 'the finished transcript',
      );

      final response = await _postJson(port, '/v1/dictation/trigger', {
        'wait': true,
      }, bearer: token);

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['recording'], isFalse);
      expect(body['transcript'], 'the finished transcript');
    });

    test('`wait: false` (the default) on a call that stops a recording '
        'omits the transcript from the response', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;
      triggerResult = const DictationTriggerResult(
        recording: false,
        transcript: 'the finished transcript',
      );

      final response = await _postJson(
        port,
        '/v1/dictation/trigger',
        {},
        bearer: token,
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['recording'], isFalse);
      expect(body.containsKey('transcript'), isFalse);
    });
  });

  group('GET /v1/dictation/status', () {
    Future<int> startEnabled(ProviderContainer c) async {
      final controller = c.read(automationApiControllerProvider.notifier);
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );
      return c.read(automationApiControllerProvider).port!;
    }

    test('idle (no recording in progress) → phase idle, busy false', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _get(
        port,
        path: '/v1/dictation/status',
        bearer: token,
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['phase'], 'idle');
      expect(body['busy'], isFalse);
    });

    test('a recording in progress → phase recording, busy true', () async {
      container = buildContainer();
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;
      container.read(recordingProvider.notifier).startRecording();

      final response = await _get(
        port,
        path: '/v1/dictation/status',
        bearer: token,
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['phase'], 'recording');
      expect(body['busy'], isTrue);
    });

    test('a request with no token → 401', () async {
      container = buildContainer();
      final port = await startEnabled(container);

      final response = await _get(port, path: '/v1/dictation/status');

      expect(response.statusCode, 401);
    });
  });

  group('GET /v1/history/latest', () {
    Future<int> startEnabled(ProviderContainer c) async {
      final controller = c.read(automationApiControllerProvider.notifier);
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );
      return c.read(automationApiControllerProvider).port!;
    }

    test('returns the most-recently-transcribed entry, authenticated the same '
        'way as the dictation-trigger endpoint', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'older',
          content: const Value('older transcript'),
          title: const Value('Older'),
          timestamp: DateTime.utc(2026, 9, 1),
        ),
      );
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'newer',
          content: const Value('newer transcript'),
          title: const Value('Newer'),
          timestamp: DateTime.utc(2026, 9, 9),
        ),
      );

      container = buildContainer(db: db);
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _get(
        port,
        path: '/v1/history/latest',
        bearer: token,
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['id'], 'newer');
      expect(body['content'], 'newer transcript');
    });

    test('no history entry exists yet → 404 no_history_entry (a clear, '
        'specific response, not a generic error)', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = buildContainer(db: db);
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _get(
        port,
        path: '/v1/history/latest',
        bearer: token,
      );

      expect(response.statusCode, 404);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['error'], 'no_history_entry');
    });

    test('a PIN-locked history → 423 history_locked, served again once '
        'unlocked (.scratch/history-pin-lock)', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'secret',
          content: const Value('secret transcript'),
          timestamp: DateTime.utc(2026, 9, 9),
        ),
      );
      await db.writeAppSettings({
        'history_hide_on_open': 'true',
        'history_pin': hashHistoryPin('4711', iterations: 10),
      });
      container = buildContainer(db: db);
      await container.read(settingsProvider.future);
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final locked = await _get(
        port,
        path: '/v1/history/latest',
        bearer: token,
      );
      expect(locked.statusCode, 423);
      final body =
          jsonDecode(await locked.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['error'], 'history_locked');

      await container
          .read(historyRevealedProvider.notifier)
          .unlockWithPin('4711');
      final unlocked = await _get(
        port,
        path: '/v1/history/latest',
        bearer: token,
      );
      expect(unlocked.statusCode, 200);
      await unlocked.drain<void>();
    });

    test('a request with no token → 401', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = buildContainer(db: db);
      final port = await startEnabled(container);

      final response = await _get(port, path: '/v1/history/latest');

      expect(response.statusCode, 401);
    });

    test(
      'a PIN-locked history also locks the notes routes → 423 '
      'history_locked, nothing written, served again once unlocked (GS-149)',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.writeAppSettings({
          'history_hide_on_open': 'true',
          'history_pin': hashHistoryPin('4711', iterations: 10),
        });
        container = buildContainer(db: db);
        await container.read(settingsProvider.future);
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final locked = await _get(port, path: '/v1/notes', bearer: token);
        expect(locked.statusCode, 423);
        expect(
          (jsonDecode(await locked.transform(utf8.decoder).join())
              as Map<String, dynamic>)['error'],
          'history_locked',
        );

        final write = await _postJson(port, '/v1/notes', {
          'content': 'geheim',
        }, bearer: token);
        expect(write.statusCode, 423);
        await write.drain<void>();

        await container
            .read(historyRevealedProvider.notifier)
            .unlockWithPin('4711');
        final unlocked = await _get(port, path: '/v1/notes', bearer: token);
        expect(unlocked.statusCode, 200);
        final body =
            jsonDecode(await unlocked.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        expect(body['notes'], isEmpty);
      },
    );

    test('succeeds against a real background-isolate database — '
        'in-memory tests\' single-isolate DB round-trips too fast to expose '
        'this, but production hit exactly this timing: historyDetailProvider '
        'is autoDispose and nothing else in this headless path was watching '
        'it, so a bare `ref.read(...future)` let it get disposed between its '
        'own two internal DB awaits (build() reads getEntry, then '
        'tagsForEntry) — surfacing as a 500 with a disposed-Ref error logged '
        'behind it', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'wp_automation_api_history_test',
      );
      // Retried: even after the explicit shutdown()/close() below genuinely
      // await their own async work, Windows can lag a moment longer before
      // the OS actually releases the native sqlite3 file handle that the
      // background isolate held — a handle-release timing gap below the
      // Dart-level close, not something any amount of extra awaiting inside
      // this process can close. POSIX silently allows deleting a still-open
      // file, so this only ever surfaced on Windows CI.
      addTearDown(() async {
        for (var attempt = 1; attempt <= 5; attempt++) {
          try {
            tempDir.deleteSync(recursive: true);
            return;
          } on PathAccessException {
            if (attempt == 5) rethrow;
            await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
          }
        }
      });
      final db = HistoryDatabase.forTesting(
        NativeDatabase.createInBackground(
          File(p.join(tempDir.path, 'history.db')),
        ),
      );
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'bg-entry',
          content: const Value('background-isolate transcript'),
          title: const Value('Background'),
          timestamp: DateTime.utc(2026, 9, 9),
        ),
      );

      container = buildContainer(db: db);
      // Registered after the tempDir cleanup above, so it runs first (LIFO)
      // — and, unlike a bare `container.dispose` (whose own onDispose hooks
      // stop the server / close db with `unawaited(...)`, see
      // AutomationApiController.build() and buildContainer's
      // historyDatabaseProvider override), this genuinely awaits both steps
      // before returning. On Windows (unlike POSIX), deleting a file that's
      // still open fails, so the tempDir delete must not run until the
      // background isolate has actually released its handle on it. The
      // group-level `tearDown(() => container.dispose())` below then becomes
      // a safe no-op (ProviderContainer.dispose() is idempotent).
      addTearDown(() async {
        await container
            .read(automationApiControllerProvider.notifier)
            .shutdown();
        container.dispose();
        await db.close();
      });
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _get(
        port,
        path: '/v1/history/latest',
        bearer: token,
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['id'], 'bg-entry');
      expect(body['content'], 'background-isolate transcript');
    });
  });

  group('POST /v1/snippets/insert', () {
    Future<int> startEnabled(ProviderContainer c) async {
      final controller = c.read(automationApiControllerProvider.notifier);
      await controller.syncWithSettings(
        AppSettings.defaults.copyWithSections(
          automationApi: const AutomationApiSettings(enabled: true),
        ),
      );
      return c.read(automationApiControllerProvider).port!;
    }

    test(
      'inserts an existing static snippet via the Snippet-Picker service, '
      'authenticated the same way as the dictation-trigger endpoint',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.upsertSnippet(
          id: 'sig-1',
          title: 'Signature',
          body: 'Best regards, Silvio',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        final paster = _FakePaster();

        container = buildContainer(db: db, paster: paster);
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final response = await _postJson(port, '/v1/snippets/insert', {
          'name': 'Signature',
        }, bearer: token);

        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        expect(body['status'], 'inserted');
        expect(paster.texts, ['Best regards, Silvio']);
      },
    );

    Future<void> seedMultilineSnippet(HistoryDatabase db) => db.upsertSnippet(
      id: 'sig-2',
      title: 'Address',
      body: 'Line one\nLine two',
      createdAt: DateTime.utc(2026, 9, 1),
    );

    /// Waits until the multiline preview is open, then answers it.
    Future<void> answerPreview(
      ProviderContainer c, {
      required bool confirm,
    }) async {
      while (c.read(multilinePasteConfirmationProvider) == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final notifier = c.read(multilinePasteConfirmationProvider.notifier);
      confirm ? notifier.confirm() : notifier.cancel();
    }

    test(
      'a multiline snippet waits for the preview and pastes once confirmed',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await seedMultilineSnippet(db);
        final paster = _FakePaster();

        container = buildContainer(db: db, paster: paster);
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final pending = _postJson(port, '/v1/snippets/insert', {
          'name': 'Address',
        }, bearer: token);
        await answerPreview(container, confirm: true);
        final response = await pending;

        expect(response.statusCode, 200);
        expect(paster.texts, ['Line one\nLine two']);
      },
    );

    test(
      'a multiline snippet the user cancels returns 409 and pastes nothing',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await seedMultilineSnippet(db);
        final paster = _FakePaster();

        container = buildContainer(db: db, paster: paster);
        final port = await startEnabled(container);
        final token = container.read(automationApiControllerProvider).token!;

        final pending = _postJson(port, '/v1/snippets/insert', {
          'name': 'Address',
        }, bearer: token);
        await answerPreview(container, confirm: false);
        final response = await pending;

        expect(response.statusCode, 409);
        final body =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        expect(body['error'], 'preview_cancelled');
        expect(paster.texts, isEmpty);
      },
    );

    test('an unknown snippet name returns a clear 404 error, not a generic '
        'failure', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final paster = _FakePaster();
      container = buildContainer(db: db, paster: paster);
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/snippets/insert', {
        'name': 'does-not-exist',
      }, bearer: token);

      expect(response.statusCode, 404);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['error'], 'snippet_not_found');
      expect(paster.texts, isEmpty);
    });

    test('an interactive snippet name returns a clear 409 error', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertSnippetWithFields(
        id: 'interview-1',
        title: 'Interview',
        body: '{{answer}}',
        createdAt: DateTime.utc(2026, 9, 1),
        kind: 'interactive',
        fieldNames: const ['answer'],
      );
      final paster = _FakePaster();
      container = buildContainer(db: db, paster: paster);
      final port = await startEnabled(container);
      final token = container.read(automationApiControllerProvider).token!;

      final response = await _postJson(port, '/v1/snippets/insert', {
        'name': 'Interview',
      }, bearer: token);

      expect(response.statusCode, 409);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['error'], 'snippet_not_static');
      expect(paster.texts, isEmpty);
    });

    test('a request with no token → 401, nothing is pasted', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertSnippet(
        id: 'sig-1',
        title: 'Signature',
        body: 'Best regards,\nSilvio',
        createdAt: DateTime.utc(2026, 9, 1),
      );
      final paster = _FakePaster();
      container = buildContainer(db: db, paster: paster);
      final port = await startEnabled(container);

      final response = await _postJson(port, '/v1/snippets/insert', {
        'name': 'Signature',
      });

      expect(response.statusCode, 401);
      expect(paster.texts, isEmpty);
    });
  });
}

/// Binds [count] consecutive loopback ports. Parallel test processes may
/// already hold any port after a free probe port, so a range with a taken
/// port is released and another one is tried.
Future<List<ServerSocket>> _bindConsecutivePorts(int count) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = [probe];
    try {
      for (var i = 1; i < count; i++) {
        sockets.add(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, probe.port + i),
        );
      }
      return sockets;
    } on SocketException {
      for (final socket in sockets) {
        await socket.close();
      }
    }
  }
  throw StateError('no $count consecutive free loopback ports found');
}
