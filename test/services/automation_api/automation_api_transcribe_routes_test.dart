/// Route tests for `POST /v1/transcriptions` (ticket / 8.2).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_transcribe_routes.dart';

/// A 16 kHz mono 16-bit WAV with [dataBytes] of silence after the header.
Uint8List _wav(int dataBytes) {
  final out = BytesBuilder();
  void u32(int v) =>
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  out.add('RIFF'.codeUnits);
  u32(36 + dataBytes);
  out.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(16000);
  u32(32000);
  u16(2);
  u16(16);
  out.add('data'.codeUnits);
  u32(dataBytes);
  out.add(List<int>.filled(dataBytes, 0));
  return out.takeBytes();
}

Handler _route(Future<String> Function(List<int>) transcribe) {
  return buildAutomationApiRouter([
    automationTranscribeRoutes(transcribe: transcribe),
  ]).handler;
}

Request _upload(List<int> bytes) => Request(
  'POST',
  Uri.parse('http://127.0.0.1/v1/transcriptions'),
  headers: {'content-type': 'audio/wav'},
  body: bytes,
);

void main() {
  test('the WAV bytes reach the transcriber unchanged', () async {
    late List<int> seen;
    final wav = _wav(320);
    final response = await _route((bytes) async {
      seen = bytes;
      return 'ok';
    })(_upload(wav));

    expect(response.statusCode, 200);
    expect(seen, wav);
  });

  test('a transcriber that reports busy answers 409 with error busy', () async {
    final response = await _route(
      (_) async => throw const AutomationTranscriptionBusyException(),
    )(_upload(_wav(320)));

    expect(response.statusCode, 409);
    expect(jsonDecode(await response.readAsString()), {'error': 'busy'});
  });
}
