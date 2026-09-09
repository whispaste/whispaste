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
          header == 'Bearer $expected';
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
