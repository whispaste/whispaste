/// Route registry for the local automation API (ticket 03,
/// `.scratch/local-automation-api/`).
///
/// Deliberately hand-rolled instead of pulling in `shelf_router`: this
/// ticket registers exactly one route, and ticket 04 (reading the last
/// history entry, inserting a snippet) adds at most two more — not enough
/// route surface to justify a second routing package on top of `shelf`.
/// [AutomationApiRouteGroup] is the seam ticket 04 hangs its routes on
/// without touching this file or the dictation-trigger route below.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../core/config/whisper_languages.dart';
import '../../core/logging/app_logger.dart';

final _log = AppLogger('AutomationApiRouter');

/// One unit of route registrations, added to the router built by
/// [buildAutomationApiRouter].
typedef AutomationApiRouteGroup = void Function(AutomationApiRouter router);

/// Minimal method+path router: a request is dispatched to the handler
/// registered for its exact method and path, or 404 otherwise.
class AutomationApiRouter {
  final Map<String, Map<String, Handler>> _routesByMethod = {};

  void add(String method, String path, Handler handler) {
    _routesByMethod.putIfAbsent(
      method.toUpperCase(),
      () => {},
    )[_normalize(path)] = handler;
  }

  static String _normalize(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  /// The combined [Handler] shelf_io serves — resolves every request against
  /// the registered routes, 404-ing anything unmatched.
  Handler get handler => (Request request) {
    final methodRoutes = _routesByMethod[request.method.toUpperCase()];
    final routeHandler = methodRoutes?[_normalize(request.url.path)];
    if (routeHandler == null) {
      return _jsonResponse(404, {'error': 'not_found'});
    }
    return routeHandler(request);
  };
}

/// Builds a router from an ordered list of [AutomationApiRouteGroup]s —
/// ticket 04 appends its own groups to this list at the call site instead of
/// editing this function.
AutomationApiRouter buildAutomationApiRouter(
  List<AutomationApiRouteGroup> routeGroups,
) {
  final router = AutomationApiRouter();
  for (final group in routeGroups) {
    group(router);
  }
  return router;
}

/// Outcome of one [dictationTriggerRoutes] call, reported back by the
/// injected `triggerDictation` callback. Dictation is a toggle (see
/// `RecordingOrchestrator.toggleRecording`) — a single trigger either
/// starts a new recording ([recording] true, nothing to report yet) or
/// stops an in-progress one ([recording] false, [transcript] holding the
/// finished text once the pipeline completes).
class DictationTriggerResult {
  const DictationTriggerResult({required this.recording, this.transcript});

  final bool recording;
  final String? transcript;
}

/// Route group: a single endpoint that triggers dictation.
///
/// Pure orchestration — [triggerDictation] is the existing
/// recording-orchestrator use case (the same one the main hotkey calls); no
/// dictation logic lives in this file.
///
/// **Request body** (optional; omit entirely for the original
/// fire-and-forget behaviour):
/// ```json
/// { "wait": true, "language": "en" }
/// ```
/// - `wait` (bool, default `false`): when this call stops an in-progress
///   recording, include the finished `transcript` in the response instead
///   of just `{"status": "triggered"}`. The HTTP response for a stopping
///   call already doesn't return until the transcription pipeline finishes
///   either way (`toggleRecording` awaits it) — `wait` only controls
///   whether the result is *reported back*, not how long the call takes.
///   Has no additional effect when this call starts a new recording (there
///   is nothing to wait for yet).
/// - `language` (ISO 639-1 code, e.g. `"en"`, or `"auto"`): overrides the
///   configured STT language for the recording this call starts. Only
///   meaningful when this call starts a new recording; ignored when it
///   stops one (nothing starts in that case). An unrecognised code is a 400
///   `invalid_request`, not silently dropped.
///
/// A thrown exception surfaces as a 500 with `error: trigger_failed`;
/// success is a 200 with `status: triggered`, `recording` (whether this
/// call started or stopped one), and — only when `wait: true` and this call
/// stopped a recording — `transcript`.
AutomationApiRouteGroup dictationTriggerRoutes({
  required Future<DictationTriggerResult> Function({
    bool wait,
    String? language,
  })
  triggerDictation,
}) {
  return (router) {
    router.add('POST', '/v1/dictation/trigger', (Request request) async {
      var wait = false;
      String? language;
      try {
        final rawBody = await request.readAsString();
        if (rawBody.trim().isNotEmpty) {
          final decoded = jsonDecode(rawBody);
          if (decoded is! Map<String, dynamic>) {
            return _jsonResponse(400, {'error': 'invalid_request'});
          }
          if (decoded.containsKey('wait')) {
            final candidate = decoded['wait'];
            if (candidate is! bool) {
              return _jsonResponse(400, {'error': 'invalid_request'});
            }
            wait = candidate;
          }
          if (decoded.containsKey('language')) {
            final candidate = decoded['language'];
            if (candidate is! String ||
                (candidate != 'auto' &&
                    !whisperLanguageCodes.contains(candidate))) {
              return _jsonResponse(400, {'error': 'invalid_request'});
            }
            language = candidate;
          }
        }
      } catch (_) {
        return _jsonResponse(400, {'error': 'invalid_request'});
      }

      try {
        final result = await triggerDictation(wait: wait, language: language);
        final body = <String, Object?>{
          'status': 'triggered',
          'recording': result.recording,
        };
        if (wait && !result.recording) {
          body['transcript'] = result.transcript;
        }
        return _jsonResponse(200, body);
      } catch (e, st) {
        _log.warning(
          'POST /v1/dictation/trigger: triggerDictation threw',
          e,
          st,
        );
        return _jsonResponse(500, {'error': 'trigger_failed'});
      }
    });
  };
}

Response _jsonResponse(int statusCode, Map<String, Object?> body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
