import 'dart:typed_data';

import 'package:whispaste/services/audio/import/pcm_decoder.dart';

/// [pcmBytes] of loud PCM (a constant 8000 counts as speech, RMS about
/// 0.24), with the byte ranges in [pauses] set to digital silence.
Uint8List wavWithPauses(int pcmBytes, List<(int, int)> pauses) {
  const secondBytes = 32000;
  final wav = Uint8List(44 + pcmBytes)
    ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
  final tile = Uint8List(secondBytes);
  for (var i = 0; i < tile.length; i += 2) {
    tile[i] = 0x40;
    tile[i + 1] = 0x1F;
  }
  for (var at = 0; at < pcmBytes; at += secondBytes) {
    final end = at + secondBytes <= pcmBytes ? at + secondBytes : pcmBytes;
    wav.setRange(44 + at, 44 + end, tile);
  }
  for (final (start, end) in pauses) {
    wav.fillRange(44 + start, 44 + end, 0);
  }
  return wav;
}
