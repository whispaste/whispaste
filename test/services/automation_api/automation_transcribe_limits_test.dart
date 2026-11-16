/// `POST /v1/transcriptions` limits (ticket A-M5): one transcription at a
/// time, a timeout for a hung backend, and the slot stays taken until the
/// backend really returned, so two runs never share the transcriber.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_transcribe_routes.dart';

Uint8List _wav() => encodePcm16MonoWav(Int16List(1600));

Future<Response> _post(Handler handler) async => handler(
  Request(
    'POST',
    Uri.parse('http://127.0.0.1:8765/v1/transcriptions'),
    body: _wav(),
    headers: {'content-type': 'audio/wav'},
  ),
);

void main() {
  test('a second upload while one is running answers 409 busy', () async {
    final gate = Completer<String>();
    final handler = buildAutomationApiRouter([
      automationTranscribeRoutes(transcribe: (_) => gate.future),
    ]).handler;

    final first = _post(handler);
    final second = await _post(handler);

    expect(second.statusCode, 409);
    gate.complete('eins');
    expect((await first).statusCode, 200);
  });

  test(
    'a hung backend times out with 504 and keeps the slot until it ends',
    () {
      fakeAsync((time) {
        final gate = Completer<String>();
        final handler = buildAutomationApiRouter([
          automationTranscribeRoutes(
            transcribe: (_) => gate.future,
            timeoutFor: (_) => const Duration(milliseconds: 20),
          ),
        ]).handler;

        Response? response;
        _post(handler).then((value) => response = value);
        time.elapse(const Duration(milliseconds: 19));
        expect(response, isNull);
        time.elapse(const Duration(milliseconds: 1));
        expect(response!.statusCode, 504);

        // A timeout does not release the still-running backend's slot.
        _post(handler).then((value) => response = value);
        time.flushMicrotasks();
        expect(response!.statusCode, 409);

        gate.complete('fertig');
        time.flushMicrotasks();
        _post(handler).then((value) => response = value);
        time.flushMicrotasks();
        expect(response!.statusCode, 200);
      });
    },
  );
}
