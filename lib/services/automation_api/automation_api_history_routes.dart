/// Route group: read the most-recently-transcribed history entry (ticket
/// 04, `.scratch/local-automation-api/`).
///
/// A new file rather than an addition to `automation_api_router.dart` — that
/// file's doc comment defines [AutomationApiRouteGroup] as the seam this
/// ticket hangs its routes on precisely so it never needs to be touched.
/// Pure orchestration, same as `dictationTriggerRoutes`: [fetchLatestEntry]
/// is supplied by `AutomationApiController`, which builds it from the
/// existing `historyEntriesProvider` (recency ordering) and
/// `historyDetailProvider` (the entry's full detail) — no history query
/// logic is duplicated here.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_router.dart';

final _log = AppLogger('AutomationApiHistoryRoutes');

/// Route group: fetches the most-recently-transcribed history entry.
///
/// [fetchLatestEntry] returns `null` when there is no history entry yet —
/// surfaced as 404 with `error: no_history_entry` (a clear, specific
/// response, not a generic failure), matching "no history entry exists yet"
/// as a legitimate, expected outcome rather than a server error. A thrown
/// exception surfaces as a 500 with `error: fetch_failed`.
AutomationApiRouteGroup historyLatestRoutes({
  required Future<Map<String, Object?>?> Function() fetchLatestEntry,
}) {
  return (router) {
    router.add('GET', '/v1/history/latest', (Request request) async {
      try {
        final entry = await fetchLatestEntry();
        if (entry == null) {
          return _jsonResponse(404, {'error': 'no_history_entry'});
        }
        return _jsonResponse(200, entry);
      } catch (e, st) {
        _log.warning('GET /v1/history/latest: fetchLatestEntry threw', e, st);
        return _jsonResponse(500, {'error': 'fetch_failed'});
      }
    });
  };
}

Response _jsonResponse(int statusCode, Map<String, Object?> body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
