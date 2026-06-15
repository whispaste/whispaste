/// Benchmark helper: measures whisper-server RTF with a silent WAV.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Sends a 3-second silent WAV to the whisper-server and measures the
/// real-time factor (RTF = processing_time_ms / audio_duration_ms).
///
/// Returns the RTF as a [double], or `null` on failure (network error,
/// server not ready, etc.). Failures are intentionally non-fatal.
class SttBenchmark {
  const SttBenchmark();

  /// Runs the benchmark against `http://<host>:<port>/inference`.
  ///
  /// An optional [client] can be injected for testing; when omitted a
  /// short-lived [http.Client] is created and closed after the request.
  Future<double?> run(
    String host,
    int port,
    String modelId, {
    http.Client? client,
  }) async {
    final owned = client == null;
    final c = client ?? http.Client();
    try {
      final benchmarkWav = generateBenchmarkWav();
      final uri = Uri.parse('http://$host:$port/inference');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            benchmarkWav,
            filename: 'benchmark.wav',
          ),
        )
        ..fields['response_format'] = 'json'
        ..fields['temperature'] = '0.0';

      final sw = Stopwatch()..start();
      final streamed = await c
          .send(request)
          .timeout(const Duration(seconds: 30));
      await streamed.stream.drain<void>();
      sw.stop();

      // Benchmark audio is 3 seconds.
      const audioDurationMs = 3000;
      final rtf = sw.elapsedMilliseconds / audioDurationMs;
      return rtf;
    } on Exception {
      return null;
    } finally {
      if (owned) c.close();
    }
  }

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
