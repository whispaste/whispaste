/// Host-header guard for the local automation API (ticket 03,
/// `.scratch/local-automation-api/`).
///
/// The server only listens on loopback, but a browser page on any other
/// origin can still reach `127.0.0.1` through DNS rebinding: the request
/// then carries `Host: attacker.example:8765`. Accepting only the loopback
/// host names closes that path. Runs before the bearer-token check.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

const _allowedHostNames = {'127.0.0.1', 'localhost', '[::1]'};

/// Builds the guard [Middleware]. Requests whose `Host` header is not a
/// loopback name (optionally with a port) get 403 and never reach the handler.
Middleware loopbackHostGuard() {
  return (Handler innerHandler) {
    return (Request request) {
      if (!isAllowedLoopbackHost(request.headers['host'])) {
        return Response(
          403,
          body: jsonEncode({'error': 'forbidden_host'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return innerHandler(request);
    };
  };
}

/// Whether a `Host` header value names the loopback interface:
/// `127.0.0.1`, `localhost` or `[::1]`, each optionally followed by `:port`.
/// A missing or empty header is rejected.
bool isAllowedLoopbackHost(String? hostHeader) {
  if (hostHeader == null || hostHeader.isEmpty) return false;

  final String name;
  final String? port;
  if (hostHeader.startsWith('[')) {
    final end = hostHeader.indexOf(']');
    if (end < 0) return false;
    name = hostHeader.substring(0, end + 1);
    final rest = hostHeader.substring(end + 1);
    if (rest.isEmpty) {
      port = null;
    } else if (rest.startsWith(':')) {
      port = rest.substring(1);
    } else {
      return false;
    }
  } else {
    final colon = hostHeader.indexOf(':');
    if (colon < 0) {
      name = hostHeader;
      port = null;
    } else {
      name = hostHeader.substring(0, colon);
      port = hostHeader.substring(colon + 1);
      // A second colon means an unbracketed IPv6 literal: not allowed.
      if (port.contains(':')) return false;
    }
  }

  if (port != null && !_isValidPort(port)) return false;
  return _allowedHostNames.contains(name.toLowerCase());
}

bool _isValidPort(String port) {
  if (!RegExp(r'^\d{1,5}$').hasMatch(port)) return false;
  final value = int.parse(port);
  return value >= 1 && value <= 65535;
}
