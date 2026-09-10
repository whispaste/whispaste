/// Route group: reports whether a recording/transcription is currently in
/// progress.
///
/// A new file rather than an addition to `automation_api_router.dart` — see
/// `automation_api_history_routes.dart`'s doc comment for why. Pure
/// orchestration: [readStatus] is supplied by `AutomationApiController`,
/// which reads the existing `recordingPhaseProvider` — no recording-state
/// logic is duplicated here.
///
/// Lets automation callers check before triggering — e.g. avoid firing a
/// second `POST /v1/dictation/trigger` that would unexpectedly *stop* an
/// already-running recording instead of starting a new one.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'automation_api_router.dart';

/// Route group: reports the current recording phase.
///
/// **Request body:** none.
///
/// **Response:** always `200` with:
/// ```json
/// { "phase": "idle", "busy": false }
/// ```
/// `phase` is one of `idle`, `recording`, `transcribing`, `refining`,
/// `done`, `error` (mirrors `RecordingPhase`). `busy` is `true` for
/// `recording`, `transcribing`, and `refining` — i.e. `true` whenever a
/// `POST /v1/dictation/trigger` call right now would *stop* the in-progress
/// recording rather than start a new one.
AutomationApiRouteGroup dictationStatusRoutes({
  required Map<String, Object?> Function() readStatus,
}) {
  return (router) {
    router.add(
      'GET',
      '/v1/dictation/status',
      (Request request) async => _jsonResponse(200, readStatus()),
    );
  };
}

Response _jsonResponse(int statusCode, Map<String, Object?> body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
