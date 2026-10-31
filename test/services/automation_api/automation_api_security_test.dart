/// Security tests for the ticket automation surface.
///
/// They run the real pipeline (Host guard, bearer check, body limit, router)
/// with every route group registered, so a new endpoint that is added
/// without going through the pipeline fails here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_dictation_status_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_history_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_notes_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_pipeline.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_snippet_list_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_snippet_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_status_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_transcribe_routes.dart';

import '../../test_helpers/wav_bytes.dart';

const _token =
    'a3f1c9e87b2d4f60a1c3e5b7d9f0a2c4e6b8d0f2a4c6e8b0d2f4a6c8e0b2d4f6';

/// The complete endpoint surface. Adding a route means updating this list on
/// purpose, which forces a review of the new endpoint against the rules
/// (loopback, bearer token, no keystrokes, no shell).
const _expectedRoutes = [
  'GET /v1/dictation/status',
  'GET /v1/history/latest',
  'GET /v1/notes',
  'GET /v1/snippets',
  'GET /v1/status',
  'POST /v1/dictation/trigger',
  'POST /v1/notes',
  'POST /v1/snippets/insert',
  'POST /v1/snippets/render',
  'POST /v1/transcriptions',
];

Handler _handler() => buildAutomationApiHandler(
  currentToken: () async => _token,
  routeGroups: [
    dictationTriggerRoutes(
      triggerDictation:
          ({wait = false, language, smartModePreset, silenceTimeout}) async =>
              const DictationTriggerResult(recording: true),
    ),
    dictationStatusRoutes(readStatus: () => {'phase': 'idle', 'busy': false}),
    historyLatestRoutes(fetchLatestEntry: () async => null),
    snippetInsertRoutes(
      insertSnippetByName: (_) async =>
          AutomationApiSnippetInsertOutcome.notFound,
    ),
    automationStatusRoutes(readStatus: () => {'dictation': 'idle'}),
    automationNotesRoutes(
      listNotes: (_) async => const [],
      createNote: (c) async => {'id': 'x', 'content': c},
    ),
    automationSnippetCatalogRoutes(
      listSnippets: () async => const [],
      renderSnippet: (_, _) async => null,
    ),
    automationTranscribeRoutes(transcribe: (_) async => ''),
  ],
);

Request _req(
  String method,
  String route, {
  String? auth,
  Object? body,
  Map<String, String>? extraHeaders,
}) {
  final path = route.split(' ').last;
  return Request(
    method,
    Uri.parse('http://127.0.0.1:8765$path'),
    body: body,
    headers: {
      'authorization': ?auth,
      'host': '127.0.0.1:8765',
      ...?extraHeaders,
    },
  );
}

String _methodOf(String route) => route.split(' ').first;

void main() {
  test('the endpoint surface is exactly the reviewed list', () {
    final router = buildAutomationApiRouter([
      dictationTriggerRoutes(
        triggerDictation:
            ({wait = false, language, smartModePreset, silenceTimeout}) async =>
                const DictationTriggerResult(recording: true),
      ),
      dictationStatusRoutes(readStatus: () => const {}),
      historyLatestRoutes(fetchLatestEntry: () async => null),
      snippetInsertRoutes(
        insertSnippetByName: (_) async =>
            AutomationApiSnippetInsertOutcome.notFound,
      ),
      automationStatusRoutes(readStatus: () => const {}),
      automationNotesRoutes(
        listNotes: (_) async => const [],
        createNote: (c) async => const {},
      ),
      automationSnippetCatalogRoutes(
        listSnippets: () async => const [],
        renderSnippet: (_, _) async => null,
      ),
      automationTranscribeRoutes(transcribe: (_) async => ''),
    ]);
    final sorted = [..._expectedRoutes]..sort();
    expect(router.registeredRoutes, sorted);
  });

  group('every endpoint requires the bearer token', () {
    for (final route in _expectedRoutes) {
      test(route, () async {
        final handler = _handler();
        final none = await handler(_req(_methodOf(route), route));
        expect(none.statusCode, 401, reason: 'no header');

        final wrong = await handler(
          _req(_methodOf(route), route, auth: 'Bearer not-the-token'),
        );
        expect(wrong.statusCode, 401, reason: 'wrong token');

        final prefixOnly = await handler(
          _req(_methodOf(route), route, auth: _token.substring(0, 20)),
        );
        expect(prefixOnly.statusCode, 401, reason: 'token prefix');

        final basic = await handler(
          _req(_methodOf(route), route, auth: 'Basic $_token'),
        );
        expect(basic.statusCode, 401, reason: 'wrong scheme');
      });
    }
  });

  test('a valid token reaches the status route', () async {
    final response = await _handler()(
      _req('GET', 'GET /v1/status', auth: 'Bearer $_token'),
    );
    expect(response.statusCode, 200);
  });

  test('a request with a foreign Host header is refused before auth', () async {
    final response = await _handler()(
      _req(
        'GET',
        'GET /v1/status',
        auth: 'Bearer $_token',
        extraHeaders: {'host': 'evil.example:8765'},
      ),
    );
    expect(response.statusCode, 403);
  });

  test('an oversized JSON body is refused with 413', () async {
    final big = jsonEncode({'content': 'x' * (70 * 1024)});
    final response = await _handler()(
      _req('POST', 'POST /v1/notes', auth: 'Bearer $_token', body: big),
    );
    expect(response.statusCode, 413);
  });

  test('a declared oversized Content-Length is refused with 413', () async {
    final response = await _handler()(
      _req(
        'POST',
        'POST /v1/notes',
        auth: 'Bearer $_token',
        // A stream body keeps the declared header as sent, the way a real
        // socket would deliver it.
        body: Stream.value(utf8.encode('{}')),
        extraHeaders: {'content-length': '${10 * 1024 * 1024}'},
      ),
    );
    expect(response.statusCode, 413);
  });

  test('the WAV route accepts a file well above the JSON limit', () async {
    final wav = buildWavBytes(dataBytes: 200 * 1024);
    final response = await _handler()(
      _req(
        'POST',
        'POST /v1/transcriptions',
        auth: 'Bearer $_token',
        body: wav,
        extraHeaders: {'content-type': 'audio/wav'},
      ),
    );
    expect(response.statusCode, 200);
  });

  test('new automation source never reaches keystrokes, paste or a shell', () {
    // Only the files this ticket added. The older insert route and the
    // dictation trigger predate ticket and are reviewed separately.
    const newFiles = [
      'lib/services/automation_api/automation_api_pipeline.dart',
      'lib/services/automation_api/automation_api_responses.dart',
      'lib/services/automation_api/automation_api_status_routes.dart',
      'lib/services/automation_api/automation_api_notes_routes.dart',
      'lib/services/automation_api/automation_api_snippet_list_routes.dart',
      'lib/services/automation_api/automation_api_transcribe_routes.dart',
      'lib/services/automation_api/automation_snippet_render.dart',
      'lib/services/automation_api/automation_body_limit.dart',
      'lib/services/automation_api/wav_format.dart',
      'lib/core/config/automation_hooks.dart',
    ];
    const forbidden = [
      'Process.',
      'Process(',
      'paster',
      'Paster',
      'keyboard',
      'Keyboard',
      'hotKey',
      'HotKey',
      'pasteboard',
      'Pasteboard',
      'SnippetPicker',
      'recordingOrchestrator',
      'RecordingOrchestrator',
    ];
    for (final path in newFiles) {
      final source = File(path).readAsStringSync();
      for (final token in forbidden) {
        expect(
          source.contains(token),
          isFalse,
          reason: '$path mentions $token',
        );
      }
    }
  });
}
