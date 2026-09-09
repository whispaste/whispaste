/// Unit tests for the automation-API route registry — no real HTTP socket,
/// just the [Handler] built from [buildAutomationApiRouter].
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';

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
}
