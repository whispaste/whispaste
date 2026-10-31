/// Request-size limit for the local automation API (WP-38 / 8.1).
///
/// Runs after the bearer-token check, so unauthenticated callers never get
/// a body read. A declared `Content-Length` above the limit is refused
/// before any byte is read; a chunked body is counted while it is read and
/// refused before the chunk that would exceed the limit is buffered. The handler
/// then receives the body as a packed `Uint8List`, so no route has to repeat
/// the check.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Default limit for JSON bodies. Every current endpoint except the audio
/// upload fits comfortably below this.
const kAutomationApiDefaultMaxBodyBytes = 64 * 1024;

/// Limit for `POST /v1/transcriptions` (WAV upload). Sized for roughly ten
/// minutes of 16 kHz mono 16-bit audio.
const kAutomationApiAudioMaxBodyBytes = 64 * 1024 * 1024;

/// Builds the body-limit [Middleware]. [maxBytesFor] returns the limit for
/// each request, so a route can ask for a larger allowance than the default.
Middleware automationBodyLimit({
  required int Function(Request) maxBytesFor,
  Duration readTimeout = kAutomationApiBodyReadTimeout,
  Duration totalReadTimeout = kAutomationApiBodyTotalTimeout,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final limit = maxBytesFor(request);
      final declared = request.contentLength;
      if (declared != null && declared > limit) {
        return _tooLarge();
      }

      // Checked before each append, so the buffer never holds more than the
      // limit. BytesBuilder keeps the bytes packed (a List<int> spends about
      // eight bytes per byte), and takeBytes hands them over as a Uint8List.
      // The timeout is idle time between chunks: a client that goes silent
      // mid-body must not hold the request, and its token-guarded handler,
      // open indefinitely.
      // The idle timeout alone lets a client that sends one chunk every few
      // seconds hold the request for as long as it likes, so the whole read
      // also has a deadline. Past it the request is abandoned with 408.
      final buffer = BytesBuilder(copy: false);
      final outcome = await _readBody(
        request.read(),
        buffer,
        limit,
        readTimeout,
        totalReadTimeout,
      );
      switch (outcome) {
        case _ReadOutcome.tooLarge:
          return _tooLarge();
        case _ReadOutcome.timedOut:
          return _requestTimeout();
        case _ReadOutcome.complete:
          break;
      }
      return innerHandler(request.change(body: buffer.takeBytes()));
    };
  };
}

/// Idle time allowed between two body chunks before the request is abandoned.
const kAutomationApiBodyReadTimeout = Duration(seconds: 10);

/// Total time allowed for reading the whole request body.
const kAutomationApiBodyTotalTimeout = Duration(seconds: 30);

enum _ReadOutcome { complete, tooLarge, timedOut }

/// Appends the chunks of [body] to [buffer] until the body ends, the limit
/// would be passed, or a deadline expires. On a timeout the subscription is
/// cancelled, so no further chunk is read after the 408.
Future<_ReadOutcome> _readBody(
  Stream<List<int>> body,
  BytesBuilder buffer,
  int limit,
  Duration idle,
  Duration total,
) {
  final done = Completer<_ReadOutcome>();
  late final StreamSubscription<List<int>> sub;
  Timer? idleTimer;
  late final Timer totalTimer;

  void finish(_ReadOutcome outcome) {
    if (done.isCompleted) return;
    idleTimer?.cancel();
    totalTimer.cancel();
    unawaited(sub.cancel());
    done.complete(outcome);
  }

  void resetIdle() {
    idleTimer?.cancel();
    idleTimer = Timer(idle, () => finish(_ReadOutcome.timedOut));
  }

  totalTimer = Timer(total, () => finish(_ReadOutcome.timedOut));
  sub = body.listen(
    (chunk) {
      resetIdle();
      if (buffer.length + chunk.length > limit) {
        finish(_ReadOutcome.tooLarge);
        return;
      }
      buffer.add(chunk);
    },
    onError: (Object e, StackTrace st) {
      if (done.isCompleted) return;
      idleTimer?.cancel();
      totalTimer.cancel();
      done.completeError(e, st);
    },
    onDone: () => finish(_ReadOutcome.complete),
    cancelOnError: true,
  );
  resetIdle();
  return done.future;
}

Response _requestTimeout() => Response(
  408,
  body: jsonEncode({'error': 'request_timeout'}),
  headers: {'content-type': 'application/json'},
);

Response _tooLarge() => Response(
  413,
  body: jsonEncode({'error': 'payload_too_large'}),
  headers: {'content-type': 'application/json'},
);
