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
/// The four values [AutomationApiRouteGroup]'s `smart_mode_preset` field
/// accepts — mirrors `SmartModeSettings.standardPreset`'s stored strings
/// (`smart_mode_presets.dart`), kept as raw strings here rather than
/// importing the enum so this HTTP-layer file doesn't pull in the Smart
/// Mode engine.
const _validSmartModePresets = {'off', 'cleanup', 'concise', 'translate'};

/// Validated fields of a `POST /v1/dictation/trigger` request body.
class _TriggerRequestParams {
  const _TriggerRequestParams({
    this.wait = false,
    this.language,
    this.smartModePreset,
    this.silenceTimeout,
  });

  final bool wait;
  final String? language;
  final String? smartModePreset;
  final double? silenceTimeout;
}

/// Validates and extracts the optional trigger-request fields from
/// [decoded]. Returns `null` when any present field fails validation —
/// the caller turns that into the 400 `invalid_request` response.
_TriggerRequestParams? _parseTriggerRequest(Map<String, dynamic> decoded) {
  var wait = false;
  String? language;
  String? smartModePreset;
  double? silenceTimeout;

  if (decoded.containsKey('wait')) {
    final candidate = decoded['wait'];
    if (candidate is! bool) return null;
    wait = candidate;
  }
  if (decoded.containsKey('language')) {
    final candidate = decoded['language'];
    if (candidate is! String ||
        (candidate != 'auto' && !whisperLanguageCodes.contains(candidate))) {
      return null;
    }
    language = candidate;
  }
  if (decoded.containsKey('smart_mode_preset')) {
    final candidate = decoded['smart_mode_preset'];
    if (candidate is! String || !_validSmartModePresets.contains(candidate)) {
      return null;
    }
    smartModePreset = candidate;
  }
  if (decoded.containsKey('silence_timeout')) {
    final candidate = decoded['silence_timeout'];
    if (candidate is! num || candidate < 0) return null;
    silenceTimeout = candidate.toDouble();
  }

  return _TriggerRequestParams(
    wait: wait,
    language: language,
    smartModePreset: smartModePreset,
    silenceTimeout: silenceTimeout,
  );
}

/// **Request body** (optional; omit entirely for the original
/// fire-and-forget behaviour):
/// ```json
/// { "wait": true, "language": "en", "smart_mode_preset": "cleanup", "silence_timeout": 5.0 }
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
/// - `smart_mode_preset` (one of `"off"`, `"cleanup"`, `"concise"`,
///   `"translate"`): overrides `settings.smartMode.standardPreset` for the
///   recording this call starts — same override seam the Smart-Mode hotkey
///   uses (`RecordingOrchestrator.startRecording`'s `forcedSmartModePreset`).
///   Only meaningful when this call starts a new recording. An unrecognised
///   value is a 400 `invalid_request`.
/// - `silence_timeout` (number, seconds, `>= 0`): overrides
///   `settings.recordingSafety.autoStopSilence` for the recording this call
///   starts — `0` disables auto-stop-on-silence entirely for that one
///   recording. Only meaningful when this call starts a new recording. A
///   negative or non-numeric value is a 400 `invalid_request`.
///
/// A thrown exception surfaces as a 500 with `error: trigger_failed`;
/// success is a 200 with `status: triggered`, `recording` (whether this
/// call started or stopped one), and — only when `wait: true` and this call
/// stopped a recording — `transcript`.
AutomationApiRouteGroup dictationTriggerRoutes({
  required Future<DictationTriggerResult> Function({
    bool wait,
    String? language,
    String? smartModePreset,
    double? silenceTimeout,
  })
  triggerDictation,
}) {
  return (router) {
    router.add('POST', '/v1/dictation/trigger', (Request request) async {
      var params = const _TriggerRequestParams();
      try {
        final rawBody = await request.readAsString();
        if (rawBody.trim().isNotEmpty) {
          final decoded = jsonDecode(rawBody);
          if (decoded is! Map<String, dynamic>) {
            return _jsonResponse(400, {'error': 'invalid_request'});
          }
          final parsed = _parseTriggerRequest(decoded);
          if (parsed == null) {
            return _jsonResponse(400, {'error': 'invalid_request'});
          }
          params = parsed;
        }
      } catch (_) {
        return _jsonResponse(400, {'error': 'invalid_request'});
      }

      try {
        final result = await triggerDictation(
          wait: params.wait,
          language: params.language,
          smartModePreset: params.smartModePreset,
          silenceTimeout: params.silenceTimeout,
        );
        final body = <String, Object?>{
          'status': 'triggered',
          'recording': result.recording,
        };
        if (params.wait && !result.recording) {
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
