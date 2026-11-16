/// Benchmark helper: the audio used to measure a whisper engine's real-time
/// factor (RTF = processing_time_ms / audio_duration_ms).
///
/// The measurement transcribes a spoken German sentence
/// ([referenceWav]), so the decoder's work counts as in a real dictation;
/// silence measured only the encoder and called slow machines fluent
/// (maintainer decision 2a, 2026-10-30). The silent WAV stays as the
/// fallback when the asset cannot be read, e.g. headless without a bundle.
///
/// The actual timing (`Stopwatch` around `WhisperEngine.transcribe`) happens
/// at the call site against the in-process engine seam — see
/// `SttServerStateNotifier._runBenchmark`. This class only owns the shared
/// benchmark input, also reused by the Parakeet engine so both engines'
/// RTF numbers are measured against the same audio.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// The spoken reference clip, see `assets/benchmark/NOTICE.md`.
const kBenchmarkReferenceAsset = 'assets/benchmark/reference-de.wav';

class SttBenchmark {
  const SttBenchmark();

  /// The spoken reference clip, or the silent WAV when it cannot be loaded.
  static Future<Uint8List> referenceWav() async {
    try {
      final data = await rootBundle.load(kBenchmarkReferenceAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return generateBenchmarkWav();
    }
  }

  /// Length of a 16 kHz mono 16-bit PCM [wav] with a 44-byte header, in ms.
  static int durationMs(Uint8List wav) =>
      ((wav.length - 44).clamp(0, wav.length) * 1000) ~/ (16000 * 2);

  /// Generates a 3-second silent WAV (16 kHz, mono, 16-bit PCM).
  static Uint8List generateBenchmarkWav() {
    const sampleRate = 16000;
    const durationSeconds = 3;
    const durationSamples = sampleRate * durationSeconds;
    const bitsPerSample = 16;
    const numChannels = 1;
    const bytesPerSample = bitsPerSample ~/ 8;
    const dataSize = durationSamples * numChannels * bytesPerSample;
    const headerSize = 44;

    final buffer = Uint8List(headerSize + dataSize);
    final data = ByteData.sublistView(buffer);

    // RIFF header
    buffer[0] = 0x52; // R
    buffer[1] = 0x49; // I
    buffer[2] = 0x46; // F
    buffer[3] = 0x46; // F
    data.setUint32(4, headerSize + dataSize - 8, Endian.little);
    buffer[8] = 0x57; // W
    buffer[9] = 0x41; // A
    buffer[10] = 0x56; // V
    buffer[11] = 0x45; // E

    // fmt chunk
    buffer[12] = 0x66; // f
    buffer[13] = 0x6D; // m
    buffer[14] = 0x74; // t
    buffer[15] = 0x20; // ' '
    data.setUint32(16, 16, Endian.little); // chunk size
    data.setUint16(20, 1, Endian.little); // PCM format
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, numChannels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer[36] = 0x64; // d
    buffer[37] = 0x61; // a
    buffer[38] = 0x74; // t
    buffer[39] = 0x61; // a
    data.setUint32(40, dataSize, Endian.little);
    // Remaining bytes are 0 (silence).

    return buffer;
  }
}
