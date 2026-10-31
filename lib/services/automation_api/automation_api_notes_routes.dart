/// Route group: list and create notes (ticket / 8.1).
///
/// Creating a note never pastes or types anything; it only writes to the
/// Notizen store. The controller decides whether the write fires a hook.
library;

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_responses.dart';
import 'automation_api_router.dart';

final _log = AppLogger('AutomationApiNotesRoutes');

/// Longest note body the API accepts, in characters.
const kAutomationApiNoteMaxChars = 100000;

const _defaultListLimit = 50;
const _maxListLimit = 200;

/// While [isHistoryLocked] reports a PIN-locked history, every notes route
/// answers 423 with `error: history_locked` and never reads or writes notes.
AutomationApiRouteGroup automationNotesRoutes({
  required Future<List<Map<String, Object?>>> Function(int limit) listNotes,
  required Future<Map<String, Object?>> Function(String content) createNote,
  bool Function()? isHistoryLocked,
}) {
  return (router) {
    router.add('GET', '/v1/notes', (Request request) async {
      if (isHistoryLocked?.call() ?? false) {
        return jsonResponse(423, {'error': 'history_locked'});
      }
      final raw = request.url.queryParameters['limit'];
      final int limit;
      if (raw == null) {
        limit = _defaultListLimit;
      } else {
        final parsed = int.tryParse(raw);
        if (parsed == null || parsed < 1 || parsed > _maxListLimit) {
          return jsonResponse(400, {'error': 'invalid_request'});
        }
        limit = parsed;
      }
      try {
        return jsonResponse(200, {'notes': await listNotes(limit)});
      } catch (e, st) {
        _log.warning('GET /v1/notes failed', e, st);
        return jsonResponse(500, {'error': 'notes_failed'});
      }
    });

    router.add('POST', '/v1/notes', (Request request) async {
      if (isHistoryLocked?.call() ?? false) {
        return jsonResponse(423, {'error': 'history_locked'});
      }
      final body = await readJsonObject(request.read());
      final content = body?['content'];
      if (content is! String || content.trim().isEmpty) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      if (content.length > kAutomationApiNoteMaxChars) {
        return jsonResponse(400, {'error': 'content_too_long'});
      }
      try {
        final note = await createNote(content);
        return jsonResponse(201, note);
      } catch (e, st) {
        _log.warning('POST /v1/notes failed', e, st);
        return jsonResponse(500, {'error': 'notes_failed'});
      }
    });
  };
}
