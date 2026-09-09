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

/// Route group: a single endpoint that triggers dictation.
///
/// Pure orchestration — [triggerDictation] is the existing
/// recording-orchestrator use case (the same one the main hotkey calls); no
/// dictation logic lives in this file. A thrown exception surfaces as a 500
/// with `error: trigger_failed`; success is a 200 with `status: triggered`.
AutomationApiRouteGroup dictationTriggerRoutes({
  required Future<void> Function() triggerDictation,
}) {
  return (router) {
    router.add('POST', '/v1/dictation/trigger', (Request request) async {
      try {
        await triggerDictation();
        return _jsonResponse(200, {'status': 'triggered'});
      } catch (_) {
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
