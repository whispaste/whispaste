/// Route group: `GET /v1/status` (WP-38 / 8.1).
library;

import 'package:shelf/shelf.dart';

import 'automation_api_responses.dart';
import 'automation_api_router.dart';

/// Reports the API version plus whatever [readStatus] supplies (the
/// controller adds the dictation phase and the history lock state). The
/// route itself reads nothing and changes nothing.
AutomationApiRouteGroup automationStatusRoutes({
  required Map<String, Object?> Function() readStatus,
}) {
  return (router) {
    router.add(
      'GET',
      '/v1/status',
      (Request request) async => jsonResponse(200, {
        'api_version': kAutomationApiVersion,
        ...readStatus(),
      }),
    );
  };
}
