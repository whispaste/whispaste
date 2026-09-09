/// Unit tests for the automation-API route registry — no real HTTP socket,
/// just the [Handler] built from [buildAutomationApiRouter].
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
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
    test(
      'POST /v1/dictation/trigger calls triggerDictation and returns 200',
      () async {
        var called = false;
        final router = buildAutomationApiRouter([
          dictationTriggerRoutes(
            triggerDictation: () async {
              called = true;
            },
          ),
        ]);

        final response = await router.handler(
          _request('POST', '/v1/dictation/trigger'),
        );

        expect(called, isTrue);
        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], 'triggered');
      },
    );

    test('surfaces a thrown exception from the use case as 500', () async {
      final router = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation: () async {
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
