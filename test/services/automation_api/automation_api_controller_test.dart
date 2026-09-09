/// Integration tests for [AutomationApiController] — real HTTP requests
/// against a real, loopback-bound server started/stopped through the
/// controller, exactly the way `app.dart` and the settings section drive it.
///
/// Ephemeral ports (`port: 0`, injected via the constructor) so parallel
/// test runs never collide on `kAutomationApiDefaultPort`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';

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

void main() {
  late ProviderContainer container;
  var triggerCallCount = 0;

  ProviderContainer buildContainer() {
    triggerCallCount = 0;
    return ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
        automationApiControllerProvider.overrideWith(
          () => AutomationApiController(
            port: 0,
            triggerDictation: (ref) async {
              triggerCallCount++;
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
}
