/// Unit tests for the automation-API route registry — no real HTTP socket,
/// just the [Handler] built from [buildAutomationApiRouter].
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_dictation_status_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_history_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_snippet_routes.dart';

Request _request(String method, String path) =>
    Request(method, Uri.parse('http://localhost$path'));

void main() {
  group('AutomationApiRouter', () {
    test('dispatches to the handler registered for method+path', () async {
      final router = AutomationApiRouter();
      router.add('GET', '/ping', (Request request) => Response.ok('pong'));

      final response = await router.handler(_request('GET', '/ping'));

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'pong');
    });

    test('returns 404 json for an unregistered path', () async {
      final router = AutomationApiRouter();

      final response = await router.handler(_request('GET', '/nope'));

      expect(response.statusCode, 404);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'not_found');
    });

    test('is method-sensitive: same path, different method → 404', () async {
      final router = AutomationApiRouter();
      router.add('POST', '/only-post', (Request request) => Response.ok(''));

      final response = await router.handler(_request('GET', '/only-post'));

      expect(response.statusCode, 404);
    });
  });

  group('dictationTriggerRoutes', () {
    Request postJson(String path, Object? body) => Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

    test('POST /v1/dictation/trigger with no body calls triggerDictation with '
        'wait=false, language=null, and returns 200', () async {
      var called = false;
      bool? receivedWait;
      String? receivedLanguage;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                called = true;
                receivedWait = wait;
                receivedLanguage = language;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        _request('POST', '/v1/dictation/trigger'),
      );

      expect(called, isTrue);
      expect(receivedWait, isFalse);
      expect(receivedLanguage, isNull);
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], 'triggered');
      expect(body['recording'], isTrue);
    });

    test('a valid `language` field is forwarded to triggerDictation', () async {
      String? receivedLanguage;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                receivedLanguage = language;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'language': 'en'}),
      );

      expect(receivedLanguage, 'en');
      expect(response.statusCode, 200);
    });

    test('"auto" is accepted as a `language` value', () async {
      String? receivedLanguage;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                receivedLanguage = language;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'language': 'auto'}),
      );

      expect(receivedLanguage, 'auto');
      expect(response.statusCode, 200);
    });

    test('an unrecognised `language` value → 400 invalid_request, '
        'triggerDictation is never called', () async {
      var called = false;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                called = true;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'language': 'not-a-real-code'}),
      );

      expect(called, isFalse);
      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'invalid_request');
    });

    test('each of the four `smart_mode_preset` values is forwarded to '
        'triggerDictation (discussion #147)', () async {
      for (final preset in ['off', 'cleanup', 'concise', 'translate']) {
        String? received;
        final router = buildAutomationApiRouter([
          dictationTriggerRoutes(
            triggerDictation:
                ({
                  wait = false,
                  language,
                  smartModePreset,
                  silenceTimeout,
                }) async {
                  received = smartModePreset;
                  return const DictationTriggerResult(recording: true);
                },
          ),
        ]);

        final response = await router.handler(
          postJson('/v1/dictation/trigger', {'smart_mode_preset': preset}),
        );

        expect(received, preset);
        expect(response.statusCode, 200);
      }
    });

    test('an unrecognised `smart_mode_preset` value → 400 invalid_request, '
        'triggerDictation is never called', () async {
      var called = false;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                called = true;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {
          'smart_mode_preset': 'not-a-real-preset',
        }),
      );

      expect(called, isFalse);
      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'invalid_request');
    });

    test('a valid `silence_timeout` value is forwarded to triggerDictation '
        '(discussion #147)', () async {
      double? received;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                received = silenceTimeout;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'silence_timeout': 7}),
      );

      expect(received, 7.0);
      expect(response.statusCode, 200);
    });

    test('`silence_timeout: 0` is forwarded (disables auto-stop, not '
        'treated as absent)', () async {
      double? received;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                received = silenceTimeout;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'silence_timeout': 0}),
      );

      expect(received, 0.0);
      expect(response.statusCode, 200);
    });

    test('a negative `silence_timeout` value → 400 invalid_request, '
        'triggerDictation is never called', () async {
      var called = false;
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                called = true;
                return const DictationTriggerResult(recording: true);
              },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'silence_timeout': -1}),
      );

      expect(called, isFalse);
      expect(response.statusCode, 400);
    });

    test(
      'a non-numeric `silence_timeout` value → 400 invalid_request',
      () async {
        final router = buildAutomationApiRouter([
          dictationTriggerRoutes(
            triggerDictation:
                ({
                  wait = false,
                  language,
                  smartModePreset,
                  silenceTimeout,
                }) async => const DictationTriggerResult(recording: true),
          ),
        ]);

        final response = await router.handler(
          postJson('/v1/dictation/trigger', {'silence_timeout': 'soon'}),
        );

        expect(response.statusCode, 400);
      },
    );

    test('a non-boolean `wait` field → 400 invalid_request', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async => const DictationTriggerResult(recording: true),
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'wait': 'yes'}),
      );

      expect(response.statusCode, 400);
    });

    test('a malformed (non-JSON) body → 400 invalid_request', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async => const DictationTriggerResult(recording: true),
        ),
      ]);

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/dictation/trigger'),
          body: 'not json',
        ),
      );

      expect(response.statusCode, 400);
    });

    test('`wait: true` on a call that stops a recording includes the '
        'transcript in the response', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async => const DictationTriggerResult(
                recording: false,
                transcript: 'hello world',
              ),
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/dictation/trigger', {'wait': true}),
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['recording'], isFalse);
      expect(body['transcript'], 'hello world');
    });

    test('`wait: false` (the default) on a call that stops a recording '
        'omits the transcript from the response', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async => const DictationTriggerResult(
                recording: false,
                transcript: 'hello world',
              ),
        ),
      ]);

      final response = await router.handler(
        _request('POST', '/v1/dictation/trigger'),
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['recording'], isFalse);
      expect(body.containsKey('transcript'), isFalse);
    });

    test('surfaces a thrown exception from the use case as 500', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                throw StateError('boom');
              },
        ),
      ]);

      final response = await router.handler(
        _request('POST', '/v1/dictation/trigger'),
      );

      expect(response.statusCode, 500);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'trigger_failed');
    });

    test('does not register any route by itself when not added', () async {
      final router = buildAutomationApiRouter(const []);

      final response = await router.handler(
        _request('POST', '/v1/dictation/trigger'),
      );

      expect(response.statusCode, 404);
    });
  });

  group('dictationStatusRoutes', () {
    test(
      'GET /v1/dictation/status returns 200 with the given status',
      () async {
        final router = buildAutomationApiRouter([
          dictationStatusRoutes(
            readStatus: () => {'phase': 'recording', 'busy': true},
          ),
        ]);

        final response = await router.handler(
          _request('GET', '/v1/dictation/status'),
        );

        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['phase'], 'recording');
        expect(body['busy'], isTrue);
      },
    );
  });

  group('historyLatestRoutes', () {
    test('GET /v1/history/latest returns 200 with the entry payload', () async {
      final router = buildAutomationApiRouter([
        historyLatestRoutes(
          fetchLatestEntry: () async => {
            'id': 'entry-1',
            'title': 'Meeting notes',
            'content': 'hello world',
            'timestamp': '2026-09-09T10:00:00.000Z',
            'tags': <String>['work'],
          },
        ),
      ]);

      final response = await router.handler(
        _request('GET', '/v1/history/latest'),
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['id'], 'entry-1');
      expect(body['content'], 'hello world');
      expect(body['tags'], ['work']);
    });

    test('GET /v1/history/latest returns 404 no_history_entry when there is '
        'no history entry yet', () async {
      final router = buildAutomationApiRouter([
        historyLatestRoutes(fetchLatestEntry: () async => null),
      ]);

      final response = await router.handler(
        _request('GET', '/v1/history/latest'),
      );

      expect(response.statusCode, 404);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'no_history_entry');
    });

    test('surfaces a thrown exception from the query as 500', () async {
      final router = buildAutomationApiRouter([
        historyLatestRoutes(
          fetchLatestEntry: () async => throw StateError('boom'),
        ),
      ]);

      final response = await router.handler(
        _request('GET', '/v1/history/latest'),
      );

      expect(response.statusCode, 500);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'fetch_failed');
    });
  });

  group('snippetInsertRoutes', () {
    Request postJson(String path, Object? body) => Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

    test('POST /v1/snippets/insert calls insertSnippetByName with the given '
        'name and returns 200 on success', () async {
      String? receivedName;
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async {
            receivedName = name;
            return AutomationApiSnippetInsertOutcome.success;
          },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', {'name': 'Signature'}),
      );

      expect(receivedName, 'Signature');
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], 'inserted');
    });

    test('an unknown snippet name returns a clear 404 error', () async {
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async =>
              AutomationApiSnippetInsertOutcome.notFound,
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', {'name': 'does-not-exist'}),
      );

      expect(response.statusCode, 404);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'snippet_not_found');
    });

    test('an interactive snippet returns a clear 409 error', () async {
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async =>
              AutomationApiSnippetInsertOutcome.interactiveNotSupported,
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', {'name': 'Interview snippet'}),
      );

      expect(response.statusCode, 409);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'snippet_not_static');
    });

    test('a failed paste returns a 500 insert_failed error', () async {
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async =>
              AutomationApiSnippetInsertOutcome.pasteFailed,
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', {'name': 'Signature'}),
      );

      expect(response.statusCode, 500);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'insert_failed');
    });

    test('a missing "name" field returns 400 invalid_request', () async {
      var called = false;
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async {
            called = true;
            return AutomationApiSnippetInsertOutcome.success;
          },
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', <String, Object?>{}),
      );

      expect(called, isFalse);
      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'invalid_request');
    });

    test('a malformed (non-JSON) body returns 400 invalid_request', () async {
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async =>
              AutomationApiSnippetInsertOutcome.success,
        ),
      ]);

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/snippets/insert'),
          body: 'not json',
        ),
      );

      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'invalid_request');
    });

    test('surfaces a thrown exception from the use case as 500', () async {
      final router = buildAutomationApiRouter([
        snippetInsertRoutes(
          insertSnippetByName: (name) async => throw StateError('boom'),
        ),
      ]);

      final response = await router.handler(
        postJson('/v1/snippets/insert', {'name': 'Signature'}),
      );

      expect(response.statusCode, 500);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'insert_failed');
    });
  });
}
