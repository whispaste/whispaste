/// Request-size limit for the local automation API (WP-38 / 8.1).
///
/// Runs after the bearer-token check, so unauthenticated callers never get
/// a body read. A declared `Content-Length` above the limit is refused
/// before any byte is read; a chunked body is counted while it is read and
/// refused before the chunk that would exceed the limit is buffered. The handler
/// then receives the body as a packed `Uint8List`, so no route has to repeat
/// the check.
library;

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
Middleware automationBodyLimit({required int Function(Request) maxBytesFor}) {
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
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in request.read()) {
        if (buffer.length + chunk.length > limit) {
          return _tooLarge();
        }
        buffer.add(chunk);
      }
      return innerHandler(request.change(body: buffer.takeBytes()));
    };
  };
}

Response _tooLarge() => Response(
  413,
  body: jsonEncode({'error': 'payload_too_large'}),
  headers: {'content-type': 'application/json'},
);
