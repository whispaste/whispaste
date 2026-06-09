/// HTTP-based health probe for the whisper-server.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// Probes `GET http://<host>:<port>/health` to check if the whisper-server is
/// ready to accept inference requests.
///
/// An injectable [http.Client] is accepted so tests can supply a mock without
/// spinning up a real HTTP server.
class SttHealthProbe {
  const SttHealthProbe({required this._client});

  final http.Client _client;

  /// Performs a single health-check request.
  ///
  /// Returns `true` when the server responds with HTTP 200; `false` on any
  /// other response or network error.
  Future<bool> checkOnce(String host, int port) async {
    try {
      final uri = Uri.parse('http://$host:$port/health');
      final response = await _client
          .get(uri)
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  /// Polls [checkOnce] on a fixed [interval] until it returns `true` or
  /// [timeout] elapses, yielding `true`/`false` after each poll.
  ///
  /// Useful for startup health-watching loops. The stream completes when
  /// `true` is yielded or [timeout] elapses (in which case `false` is the
  /// final value).
  Stream<bool> watchUntilReady(
    String host,
    int port, {
    Duration interval = const Duration(milliseconds: 200),
    Duration timeout = const Duration(seconds: 30),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ok = await checkOnce(host, port);
      yield ok;
      if (ok) return;
      await Future<void>.delayed(interval);
    }
    yield false;
  }
}
