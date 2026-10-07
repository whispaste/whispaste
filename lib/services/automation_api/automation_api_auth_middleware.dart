/// Bearer-token authentication middleware for the local automation API
/// (ticket 03, `.scratch/local-automation-api/`).
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

/// Builds the auth [Middleware].
///
/// [currentToken] is invoked on every request (never captured once) so a
/// token regenerated or revoked via settings takes effect on the very next
/// request — no server restart required.
Middleware bearerTokenAuth({required Future<String?> Function() currentToken}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final expected = await currentToken();
      final header = request.headers['authorization'];
      final isValid =
          expected != null &&
          expected.isNotEmpty &&
          constantTimeEquals(header, 'Bearer $expected');
      if (!isValid) {
        return Response(
          401,
          body: jsonEncode({'error': 'unauthorized'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return innerHandler(request);
    };
  };
}

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
