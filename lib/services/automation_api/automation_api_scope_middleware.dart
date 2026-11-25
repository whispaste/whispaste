/// Scope check of the local automation API (#255, ADR 0015 D17).
///
/// Runs after `bearerTokenAuth`, which records which token matched. The
/// write token opens only the write routes; the standard token opens every
/// other route but never writing. A mismatch is a 403, so a client learns
/// its token is valid but not meant for this route.
library;

import 'package:shelf/shelf.dart';

import 'automation_api_auth_middleware.dart';
import 'automation_api_responses.dart';

/// Paths (without leading slash) only the write token may call.
const kAutomationWritePaths = {'v1/write', 'v1/write/status'};

bool isAutomationWritePath(String path) =>
    kAutomationWritePaths.contains(path.replaceFirst(RegExp(r'^/'), ''));

Middleware automationScopeGuard() {
  return (Handler innerHandler) {
    return (Request request) {
      final scope = request.context[kAutomationScopeContextKey];
      final needed = isAutomationWritePath(request.url.path)
          ? AutomationTokenScope.write
          : AutomationTokenScope.standard;
      if (scope != needed) {
        return jsonResponse(403, {'error': 'insufficient_scope'});
      }
      return innerHandler(request);
    };
  };
}
