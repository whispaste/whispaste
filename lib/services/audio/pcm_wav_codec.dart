/// Shared PCM/WAV codec for WhisPaste's on-device STT engines.
///
/// Both whisper.cpp (`whisper_full`) and sherpa_onnx expect the SAME input —
/// normalized `[-1, 1]` float32 samples, 16 kHz mono. WhisPaste's recorder
/// already captures 16 kHz mono 16-bit PCM (`audio_service.dart`), so decoding
/// is only a 44-byte header skip plus int16-LE → float32; **no resampling** is
/// required.
library;

import 'dart:typed_data';

/// Decodes WhisPaste's canonical 44-byte-header, 16 kHz mono, 16-bit PCM WAV
/// bytes (see `wav_file_writer.dart`) into normalized `[-1, 1]` float samples.
///
/// Returns an empty list for header-only or truncated input.
Float32List pcm16WavBytesToFloat32(List<int> wavBytes) {
  const headerSize = 44;
  if (wavBytes.length <= headerSize) return Float32List(0);

  final bytes = wavBytes is Uint8List ? wavBytes : Uint8List.fromList(wavBytes);
  return pcm16BytesToFloat32(Uint8List.sublistView(bytes, headerSize));
}

/// Decodes raw, HEADER-LESS 16-bit mono PCM bytes (little-endian) into
/// normalized `[-1, 1]` float samples — the same conversion
/// [pcm16WavBytesToFloat32] does after skipping the WAV header, split out so
/// callers that never had a WAV header in the first place (the live-preview
/// streaming path, which reads directly off `AudioRecorder.startStream`'s
/// raw PCM chunks) don't need to fabricate one just to reuse this logic.
///
/// Returns an empty list for a trailing odd byte (incomplete sample).
Float32List pcm16BytesToFloat32(Uint8List pcmBytes) {
  final byteData = ByteData.sublistView(pcmBytes);
  final sampleCount = byteData.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}
