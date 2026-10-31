/// Generates placeholder reference WAV files for the GPU probe tool.
///
/// Output: `assets/reference_short.wav` (~5 s) and
///         `assets/reference_long.wav`  (~60 s).
///
/// Format: 16 kHz, mono, 16-bit PCM, 440 Hz sine tone.
///
/// These are PLACEHOLDER files. Replace with real curated German audio before
/// any meaningful live probe run.
///
/// Run from the package root:
///   dart run tools/gen_reference_wavs.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 16000;
const _frequency = 440.0; // A4

void main() {
  final scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  final assetsDir = Directory('$scriptDir/assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  _writeWav('${assetsDir.path}/reference_short.wav', durationSeconds: 5);
  _writeWav('${assetsDir.path}/reference_long.wav', durationSeconds: 60);

  stdout.writeln('Done. Generated:');
  stdout.writeln('  ${assetsDir.path}/reference_short.wav');
  stdout.writeln('  ${assetsDir.path}/reference_long.wav');
}

void _writeWav(String path, {required int durationSeconds}) {
  final numSamples = _sampleRate * durationSeconds;
  final samples = _generateSine(numSamples);
  final bytes = _buildWav(samples);
  File(path).writeAsBytesSync(bytes);
  final kb = (bytes.length / 1024).round();
  stdout.writeln('  Wrote $path ($kb KB, ${durationSeconds}s)');
}

/// Generates [numSamples] of a 440 Hz sine wave at amplitude ~50 % of max.
Int16List _generateSine(int numSamples) {
  final samples = Int16List(numSamples);
  const amplitude = 16000; // ~50 % of 32767
  for (var i = 0; i < numSamples; i++) {
    final t = i / _sampleRate;
    samples[i] = (amplitude * sin(2 * pi * _frequency * t)).round();
  }
  return samples;
}

/// Builds a valid RIFF/WAVE PCM byte buffer from the given [samples].
Uint8List _buildWav(Int16List samples) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = _sampleRate * numChannels * (bitsPerSample ~/ 8);
  const blockAlign = numChannels * (bitsPerSample ~/ 8);

  final dataSize = samples.length * (bitsPerSample ~/ 8);
  final totalSize = 36 + dataSize; // 36 = 4 (WAVE) + 8+16 (fmt) + 8 (data hdr)

  final buffer = ByteData(8 + totalSize); // 8 = 'RIFF' + 4-byte size
  var offset = 0;

  // RIFF chunk descriptor
  _writeAscii(buffer, offset, 'RIFF');
  offset += 4;
  buffer.setUint32(offset, totalSize, Endian.little);
  offset += 4;
  _writeAscii(buffer, offset, 'WAVE');
  offset += 4;

  // fmt sub-chunk
  _writeAscii(buffer, offset, 'fmt ');
  offset += 4;
  buffer.setUint32(offset, 16, Endian.little); // sub-chunk size for PCM
  offset += 4;
  buffer.setUint16(offset, 1, Endian.little); // AudioFormat = PCM
  offset += 2;
  buffer.setUint16(offset, numChannels, Endian.little);
  offset += 2;
  buffer.setUint32(offset, _sampleRate, Endian.little);
  offset += 4;
  buffer.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  buffer.setUint16(offset, blockAlign, Endian.little);
  offset += 2;
  buffer.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;

  // data sub-chunk header
  _writeAscii(buffer, offset, 'data');
  offset += 4;
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  // PCM samples (16-bit signed LE)
  for (final sample in samples) {
    buffer.setInt16(offset, sample, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

void _writeAscii(ByteData buf, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    buf.setUint8(offset + i, s.codeUnitAt(i));
  }
}
