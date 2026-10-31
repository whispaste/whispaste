/// Builds WAV test fixtures with a controllable header.
library;

import 'dart:typed_data';

Uint8List buildWavBytes({
  String riff = 'RIFF',
  String wave = 'WAVE',
  int audioFormat = 1,
  int channels = 1,
  int sampleRate = 16000,
  int bits = 16,
  int dataBytes = 32,
  bool withData = true,
}) {
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  str(riff);
  u32(36 + dataBytes);
  str(wave);
  str('fmt ');
  u32(16);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  if (withData) {
    str('data');
    u32(dataBytes);
    b.add(List<int>.filled(dataBytes, 0));
  }
  return b.toBytes();
}
