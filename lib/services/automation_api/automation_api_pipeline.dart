/// Assembles the automation API request pipeline (ticket).
///
/// Order matters: the Host check, the bearer check and the scope check run
/// before any body is read, so an unauthenticated caller (or one with the
/// wrong scope) can never make the app buffer a request body. The size limit
/// comes next, then routing.
library;

import 'package:shelf/shelf.dart';

import 'automation_api_auth_middleware.dart';
import 'automation_api_host_guard.dart';
import 'automation_api_router.dart';
import 'automation_api_scope_middleware.dart';
import 'automation_body_limit.dart';

/// Path of the one endpoint that takes a large (WAV) body.
const _audioPath = 'v1/transcriptions';

Handler buildAutomationApiHandler({
  required Future<String?> Function() currentToken,
  required List<AutomationApiRouteGroup> routeGroups,
  Future<String?> Function()? currentWriteToken,
}) {
  final router = buildAutomationApiRouter(routeGroups);
  return const Pipeline()
      .addMiddleware(loopbackHostGuard())
      .addMiddleware(
        bearerTokenAuth(
          currentToken: currentToken,
          currentWriteToken: currentWriteToken,
        ),
      )
      .addMiddleware(automationScopeGuard())
      .addMiddleware(
        automationBodyLimit(
          maxBytesFor: (request) => _pathOf(request) == _audioPath
              ? kAutomationApiAudioMaxBodyBytes
              : kAutomationApiDefaultMaxBodyBytes,
        ),
      )
      .addHandler(router.handler);
}

String _pathOf(Request request) =>
    request.url.path.replaceFirst(RegExp(r'^/'), '');
