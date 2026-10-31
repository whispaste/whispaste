/// Route-level tests for the ticket endpoints: status, notes, snippet catalog
/// and render, and WAV transcription. Each route group gets fakes injected,
/// so these run without a database, a socket or the recording pipeline.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_notes_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_snippet_list_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_status_routes.dart';
import 'package:whispaste/services/automation_api/automation_api_transcribe_routes.dart';
import 'package:whispaste/services/automation_api/automation_snippet_render.dart';
import 'package:whispaste/services/automation_api/wav_format.dart';

import '../../test_helpers/wav_bytes.dart';

Request _get(String path) => Request('GET', Uri.parse('http://localhost$path'));

Request _post(String path, Object body) => Request(
  'POST',
  Uri.parse('http://localhost$path'),
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, dynamic>;

void main() {
  group('GET /v1/status', () {
    test('reports api version and the readStatus payload', () async {
      final handler = buildAutomationApiRouter([
        automationStatusRoutes(readStatus: () => {'dictation': 'idle'}),
      ]).handler;
      final response = await handler(_get('/v1/status'));
      expect(response.statusCode, 200);
      final body = await _json(response);
      expect(body['api_version'], 1);
      expect(body['dictation'], 'idle');
    });
  });

  group('notes routes', () {
    final stored = <Map<String, Object?>>[];
    Handler handler() => buildAutomationApiRouter([
      automationNotesRoutes(
        listNotes: (limit) async => stored.take(limit).toList(),
        createNote: (content) async {
          final note = {
            'id': 'n${stored.length + 1}',
            'content': content,
            'pinned': false,
            'updated_at': '2026-10-17T10:00:00.000',
          };
          stored.insert(0, note);
          return note;
        },
      ),
    ]).handler;

    setUp(stored.clear);

    test('GET lists notes with a default limit', () async {
      stored.addAll([
        {'id': 'a', 'content': 'one'},
        {'id': 'b', 'content': 'two'},
      ]);
      final body = await _json(await handler()(_get('/v1/notes')));
      expect((body['notes'] as List).length, 2);
    });

    test('GET honours limit and rejects out-of-range values', () async {
      stored.addAll([
        for (var i = 0; i < 5; i++) {'id': '$i', 'content': 'c'},
      ]);
      final limited = await _json(await handler()(_get('/v1/notes?limit=2')));
      expect((limited['notes'] as List).length, 2);

      for (final bad in ['0', '201', 'abc', '-1']) {
        final r = await handler()(_get('/v1/notes?limit=$bad'));
        expect(r.statusCode, 400, reason: 'limit=$bad');
      }
    });

    test('POST creates a note and returns 201 with the note', () async {
      final r = await handler()(_post('/v1/notes', {'content': 'Milch'}));
      expect(r.statusCode, 201);
      expect((await _json(r))['content'], 'Milch');
      expect(stored.single['content'], 'Milch');
    });

    test('POST rejects a missing, blank or non-string content', () async {
      for (final body in <Object>[
        <String, Object?>{},
        {'content': '   '},
        {'content': 42},
        ['not', 'an', 'object'],
      ]) {
        final r = await handler()(_post('/v1/notes', body));
        expect(r.statusCode, 400, reason: jsonEncode(body));
      }
      expect(stored, isEmpty);
    });

    test('POST rejects content above the length cap', () async {
      final r = await handler()(
        _post('/v1/notes', {'content': 'x' * (kAutomationApiNoteMaxChars + 1)}),
      );
      expect(r.statusCode, 400);
      expect((await _json(r))['error'], 'content_too_long');
    });

    test('a thrown storage error is a 500 without leaking detail', () async {
      final failing = buildAutomationApiRouter([
        automationNotesRoutes(
          listNotes: (_) async => throw StateError('disk'),
          createNote: (_) async => throw StateError('disk'),
        ),
      ]).handler;
      final r = await failing(_get('/v1/notes'));
      expect(r.statusCode, 500);
      expect((await _json(r))['error'], 'notes_failed');
    });
  });

  group('snippet catalog routes', () {
    Handler handler({
      Future<SnippetRenderOutcome?> Function(String, Map<String, String>)?
      render,
    }) => buildAutomationApiRouter([
      automationSnippetCatalogRoutes(
        listSnippets: () async => [
          {'name': 'Greeting', 'kind': 'static', 'fields': <String>[]},
          {
            'name': 'Letter',
            'kind': 'interactive',
            'fields': ['recipient'],
          },
        ],
        renderSnippet:
            render ??
            (name, values) async {
              if (name != 'Letter') return null;
              return renderSnippetBody(
                kind: 'interactive',
                body: 'Hi {{recipient}}',
                fieldNames: const ['recipient'],
                values: values,
              );
            },
      ),
    ]).handler;

    test('GET lists snippets with their kind and field names', () async {
      final body = await _json(await handler()(_get('/v1/snippets')));
      final list = body['snippets'] as List;
      expect(list.first, {'name': 'Greeting', 'kind': 'static', 'fields': []});
      expect((list.last as Map)['fields'], ['recipient']);
    });

    test('POST render returns the text and does not insert anything', () async {
      final r = await handler()(
        _post('/v1/snippets/render', {
          'name': 'Letter',
          'values': {'recipient': 'Ada'},
        }),
      );
      expect(r.statusCode, 200);
      expect(await _json(r), {'name': 'Letter', 'text': 'Hi Ada'});
    });

    test('POST render: unknown snippet is 404', () async {
      final r = await handler()(_post('/v1/snippets/render', {'name': 'Nope'}));
      expect(r.statusCode, 404);
      expect((await _json(r))['error'], 'snippet_not_found');
    });

    test(
      'POST render: missing and unknown fields are 400 with the names',
      () async {
        final missing = await handler()(
          _post('/v1/snippets/render', {'name': 'Letter', 'values': {}}),
        );
        expect(missing.statusCode, 400);
        expect((await _json(missing))['fields'], ['recipient']);

        final unknown = await handler()(
          _post('/v1/snippets/render', {
            'name': 'Letter',
            'values': {'recipient': 'a', 'extra': 'b'},
          }),
        );
        expect(unknown.statusCode, 400);
        expect((await _json(unknown))['fields'], ['extra']);
      },
    );

    test('POST render: values must be an object of strings', () async {
      for (final body in <Map<String, Object?>>[
        {'name': 'Letter', 'values': 'x'},
        {
          'name': 'Letter',
          'values': {'recipient': 1},
        },
        {'name': ''},
        {'values': {}},
      ]) {
        final r = await handler()(_post('/v1/snippets/render', body));
        expect(r.statusCode, 400, reason: jsonEncode(body));
      }
    });
  });

  group('POST /v1/transcriptions', () {
    Handler handler(Future<String> Function(List<int>) transcribe) =>
        buildAutomationApiRouter([
          automationTranscribeRoutes(transcribe: transcribe),
        ]).handler;

    Request wav(List<int> bytes, {String type = 'audio/wav'}) => Request(
      'POST',
      Uri.parse('http://localhost/v1/transcriptions'),
      body: bytes,
      headers: {'content-type': type},
    );

    test('a 16 kHz mono 16-bit WAV is transcribed', () async {
      var seen = 0;
      final r = await handler((bytes) async {
        seen = bytes.length;
        return 'hallo welt';
      })(wav(buildWavBytes()));
      expect(r.statusCode, 200);
      expect((await _json(r))['transcript'], 'hallo welt');
      expect(seen, buildWavBytes().length);
    });

    test(
      'a file that is not an accepted WAV is refused with 415 and a reason',
      () async {
        final r = await handler((_) async => fail('must not transcribe'))(
          wav(buildWavBytes(sampleRate: 44100)),
        );
        expect(r.statusCode, 415);
        final body = await _json(r);
        expect(body['error'], 'unsupported_format');
        expect(
          body['reason'],
          checkWav16kMono16(buildWavBytes(sampleRate: 44100)),
        );
      },
    );

    test('an empty body is a 400, not a 415', () async {
      final r = await handler((_) async => '')(wav(const []));
      expect(r.statusCode, 400);
    });

    test('a thrown transcriber error is a 500 without detail', () async {
      final r = await handler((_) async => throw StateError('boom'))(
        wav(buildWavBytes()),
      );
      expect(r.statusCode, 500);
      expect((await _json(r))['error'], 'transcribe_failed');
    });
  });
}
