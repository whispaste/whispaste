/// Loopback-only HTTP transport for the local automation API (ticket 03,
/// `.scratch/local-automation-api/`).
///
/// Binds exclusively to IPv4 and IPv6 loopback (`127.0.0.1` / `::1`) — never
/// to a wildcard/public interface, and never configurable to one. The IPv6
/// bind is best-effort: some CI/sandboxed environments disable IPv6 loopback
/// entirely, and the IPv4 bind alone already satisfies "reachable only from
/// this machine".
library;

import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class AutomationApiServer {
  HttpServer? _v4;
  HttpServer? _v6;

  /// Whether the server is currently accepting connections.
  bool get isRunning => _v4 != null;

  /// The bound port, or `null` when not running.
  int? get port => _v4?.port;

  /// Starts serving [handler] on [port] (pass `0` for an OS-assigned
  /// ephemeral port — used by tests). Returns the actual bound port.
  ///
  /// Throws if already running, or if the IPv4 loopback bind itself fails
  /// (e.g. the port is already in use) — the caller decides how to surface
  /// that (see `AutomationApiController`).
  Future<int> start({required int port, required Handler handler}) async {
    if (_v4 != null) {
      throw StateError('AutomationApiServer is already running');
    }
    final v4 = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      port,
    );
    v4.autoCompress = false;
    _v4 = v4;

    try {
      final v6 = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv6,
        v4.port,
      );
      v6.autoCompress = false;
      _v6 = v6;
    } catch (_) {
      // Non-fatal — see the library doc comment above.
      _v6 = null;
    }

    return v4.port;
  }

  /// Stops both sockets. Safe to call when not running.
  Future<void> stop() async {
    final v4 = _v4;
    final v6 = _v6;
    _v4 = null;
    _v6 = null;
    await v4?.close(force: true);
    await v6?.close(force: true);
  }
}
