/// Route group: insert a named, existing snippet (ticket 04,
/// `.scratch/local-automation-api/`).
///
/// A new file rather than an addition to `automation_api_router.dart` — see
/// `automation_api_history_routes.dart`'s doc comment for why. Pure
/// orchestration: [insertSnippetByName] is
/// `SnippetPickerService.insertByName`, the exact lookup-and-paste path the
/// Snippet-Picker itself uses for a selection — no snippet-trigger logic is
/// duplicated here.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_router.dart';

final _log = AppLogger('AutomationApiSnippetRoutes');

/// The three JSON-decodable outcomes [insertSnippetByName] can report,
/// kept independent of `SnippetInsertByNameResult` so this file has no
/// Riverpod/snippet-service import — `AutomationApiController` maps the
/// real enum onto this one when wiring the route.
enum AutomationApiSnippetInsertOutcome {
  success,
  notFound,
  interactiveNotSupported,
  pasteFailed,
}

/// Route group: inserts a named, existing, `static` snippet.
///
/// Expects a JSON body `{"name": "<snippet title>"}`. An unknown snippet
/// name is a clear, specific 404 (`error: snippet_not_found`) rather than a
/// generic failure — likewise an `interactive` snippet (which needs the
/// guided multi-field recording sequence, unsupported headlessly) is its own
/// 409 (`error: snippet_not_static`). A malformed request body is a 400
/// (`error: invalid_request`). A thrown exception surfaces as a 500 with
/// `error: insert_failed`.
AutomationApiRouteGroup snippetInsertRoutes({
  required Future<AutomationApiSnippetInsertOutcome> Function(String name)
  insertSnippetByName,
}) {
  return (router) {
    router.add('POST', '/v1/snippets/insert', (Request request) async {
      final String name;
      try {
        final rawBody = await request.readAsString();
        final decoded = jsonDecode(rawBody);
        if (decoded is! Map<String, dynamic> || decoded['name'] is! String) {
          return _jsonResponse(400, {'error': 'invalid_request'});
        }
        final candidate = decoded['name'] as String;
        if (candidate.trim().isEmpty) {
          return _jsonResponse(400, {'error': 'invalid_request'});
        }
        name = candidate;
      } catch (_) {
        return _jsonResponse(400, {'error': 'invalid_request'});
      }

      try {
        final outcome = await insertSnippetByName(name);
        switch (outcome) {
          case AutomationApiSnippetInsertOutcome.success:
            return _jsonResponse(200, {'status': 'inserted'});
          case AutomationApiSnippetInsertOutcome.notFound:
            return _jsonResponse(404, {'error': 'snippet_not_found'});
          case AutomationApiSnippetInsertOutcome.interactiveNotSupported:
            return _jsonResponse(409, {'error': 'snippet_not_static'});
          case AutomationApiSnippetInsertOutcome.pasteFailed:
            return _jsonResponse(500, {'error': 'insert_failed'});
        }
      } catch (e, st) {
        _log.warning('POST /v1/snippets/insert: insertByName threw', e, st);
        return _jsonResponse(500, {'error': 'insert_failed'});
      }
    });
  };
}

Response _jsonResponse(int statusCode, Map<String, Object?> body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
