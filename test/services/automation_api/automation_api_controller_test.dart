/// Integration tests for [AutomationApiController] — real HTTP requests
/// against a real, loopback-bound server started/stopped through the
/// controller, exactly the way `app.dart` and the settings section drive it.
///
/// Ephemeral ports (`port: 0`, injected via the constructor) so parallel
/// test runs never collide on `kAutomationApiDefaultPort`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/recording/recording_state.dart'
    show recordingProvider;
import 'package:whispaste/services/automation_api/automation_api_controller.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart'
    show DictationTriggerResult;
import 'package:whispaste/services/automation_api/automation_api_server.dart';
import 'package:whispaste/services/paste/paster.dart';

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
  var triggerResult = const DictationTriggerResult(recording: true);

  ProviderContainer buildContainer({
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
        automationApiControllerProvider.overrideWith(
          () => AutomationApiController(
            port: port,
            server: server,
            triggerDictation: (ref, {wait = false, language}) async {
              triggerCallCount++;
              lastTriggerWait = wait;
              lastTriggerLanguage = language;
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

    test('a request with no token → 401', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = buildContainer(db: db);
      final port = await startEnabled(container);

      final response = await _get(port, path: '/v1/history/latest');

      expect(response.statusCode, 401);
    });

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
      addTearDown(() => tempDir.deleteSync(recursive: true));
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
          body: 'Best regards,\nSilvio',
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
        expect(paster.texts, ['Best regards,\nSilvio']);
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
