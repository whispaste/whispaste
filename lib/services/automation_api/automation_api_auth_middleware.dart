/// Bearer-token authentication middleware for the local automation API.
///
/// Every request without a valid `Authorization: Bearer <token>` header is
/// rejected with 401 — deliberately with **no** "request came from
/// localhost" exception. The server only ever binds to loopback addresses
/// (see `AutomationApiServer`), but that alone does not distinguish
/// WhisPaste's own script user from any other local process/user account,
/// so the token check always runs.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shelf/shelf.dart';

/// Request-context key under which [bearerTokenAuth] records the scope of
/// the token a request carried; read by `automationScopeGuard`.
const kAutomationScopeContextKey = 'wp.automation.scope';

/// What a valid token may do (#255, ADR 0015 D17). The scope is decided by
/// which token matched, never by anything the client sends.
enum AutomationTokenScope {
  /// The original API token: every route except writing.
  standard,

  /// The separate write token: only the write routes.
  write,
}

/// Builds the auth [Middleware].
///
/// [currentToken] is invoked on every request (never captured once) so a
/// token regenerated or revoked via settings takes effect on the very next
/// request — no server restart required. [currentWriteToken] works the same
/// way for the write scope and returns `null` while writing is switched off,
/// so the switch revokes the write token instantly.
Middleware bearerTokenAuth({
  required Future<String?> Function() currentToken,
  Future<String?> Function()? currentWriteToken,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Without a header there is nothing to compare, so the token store (and
      // with it the keyring) is not touched for unauthenticated traffic.
      final header = request.headers['authorization'];
      if (header == null) return _unauthorized();
      final String? expected;
      final String? expectedWrite;
      try {
        expected = await currentToken();
        expectedWrite = await currentWriteToken?.call();
      } on Object {
        // A locked or failing keyring fails closed with a status, not an
        // unhandled error inside the server.
        return Response(
          503,
          body: jsonEncode({'error': 'token_unavailable'}),
          headers: {'content-type': 'application/json'},
        );
      }
      // Both comparisons always run, so the timing does not tell which
      // token a guess came close to.
      final standard = _matches(header, expected);
      final write = _matches(header, expectedWrite);
      if (!standard && !write) return _unauthorized();
      return innerHandler(
        request.change(
          context: {
            kAutomationScopeContextKey: standard
                ? AutomationTokenScope.standard
                : AutomationTokenScope.write,
          },
        ),
      );
    };
  };
}

bool _matches(String header, String? expected) {
  final valid = expected != null && expected.isNotEmpty;
  // Compare against a dummy when there is no token, to keep the work equal.
  return constantTimeEquals(header, 'Bearer ${valid ? expected : '-'}') &&
      valid;
}

Response _unauthorized() => Response(
  401,
  body: jsonEncode({'error': 'unauthorized'}),
  headers: {'content-type': 'application/json'},
);

/// Compares [provided] against [expected] in time that depends only on the
/// lengths of the inputs, never on the position of the first mismatching
/// byte — so a local attacker cannot recover the token byte by byte via
/// response timing. A `null` [provided] (missing header) never matches.
@visibleForTesting
bool constantTimeEquals(String? provided, String expected) {
  if (provided == null) return false;
  final a = utf8.encode(provided);
  final b = utf8.encode(expected);
  // Fold the length difference into the result instead of returning early,
  // and always walk the full expected value.
  var diff = a.length ^ b.length;
  for (var i = 0; i < b.length; i++) {
    diff |= (i < a.length ? a[i] : 0) ^ b[i];
  }
  return diff == 0;
}
