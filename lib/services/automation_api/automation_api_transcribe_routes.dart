/// Route group: transcribe an uploaded WAV file (ticket / 8.2).
///
/// The body is the raw WAV file. Only the format the existing transcription
/// path accepts gets through ([checkWav16kMono16]); anything else is a 415
/// with the reason, never a guess. The transcript is returned to the caller
/// and not pasted anywhere. While a dictation is running or being
/// transcribed, the route answers 409 `busy`: the dictation has priority.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../../core/logging/app_logger.dart';
import 'automation_api_responses.dart';
import 'automation_api_router.dart';
import 'wav_format.dart';

final _log = AppLogger('AutomationApiTranscribeRoutes');

/// Thrown by the transcribe callback when a dictation holds the transcriber.
class AutomationTranscriptionBusyException implements Exception {
  const AutomationTranscriptionBusyException();
}

/// Upper bound for one transcription: 60 s plus twice the audio length, the
/// same shape as the hotkey pipeline's timeout. Audio is 16 kHz mono 16-bit.
Duration _defaultTranscribeTimeout(int wavBytes) {
  final audioMs = (wavBytes - 44).clamp(0, 1 << 40) * 1000 ~/ 32000;
  return Duration(milliseconds: 60000 + 2 * audioMs);
}

AutomationApiRouteGroup automationTranscribeRoutes({
  required Future<String> Function(List<int> wavBytes) transcribe,
  Duration Function(int wavBytes) timeoutFor = _defaultTranscribeTimeout,
}) {
  return (router) {
    // One transcription at a time. Set and checked without an await in
    // between, so the check and the claim are one step in the event loop.
    var running = false;
    router.add('POST', '/v1/transcriptions', (Request request) async {
      final bytes = await _readPacked(request);
      if (bytes.isEmpty) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      final reason = checkWav16kMono16(bytes);
      if (reason != null) {
        return jsonResponse(415, {
          'error': 'unsupported_format',
          'reason': reason,
        });
      }
      if (running) return jsonResponse(409, {'error': 'busy'});
      running = true;
      final Future<String> call;
      try {
        call = transcribe(bytes);
      } on Object {
        running = false;
        rethrow;
      }
      // The slot is released when the backend really finishes, even after a
      // timeout: a hung run must not be joined by a second one.
      unawaited(
        call.then<void>(
          (_) => running = false,
          onError: (_) => running = false,
        ),
      );
      try {
        final transcript = await call.timeout(timeoutFor(bytes.length));
        return jsonResponse(200, {'transcript': transcript});
      } on TimeoutException {
        return jsonResponse(504, {'error': 'timeout'});
      } on AutomationTranscriptionBusyException {
        return jsonResponse(409, {'error': 'busy'});
      } catch (e, st) {
        _log.warning(
          'POST /v1/transcriptions failed: ${errorKind(e)}',
          null,
          st,
        );
        return jsonResponse(500, {'error': 'transcribe_failed'});
      }
    });
  };
}

/// Collects the body into one packed buffer. A `List<int>` of boxed bytes
/// would take about eight times the upload size in memory.
Future<Uint8List> _readPacked(Request request) async {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    buffer.add(chunk);
  }
  return buffer.takeBytes();
}
