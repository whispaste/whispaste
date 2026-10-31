/// Pure-Dart decoding of uncompressed WAV files into WhisPaste's STT input
/// format (16 kHz, mono, 16-bit PCM).
///
/// Covers PCM 8/16/24/32-bit integer and 32-bit float WAV at any sample rate
/// and channel count, including `WAVE_FORMAT_EXTENSIBLE`. Compressed formats
/// (MP3, FLAC, AAC/M4A) are decoded by platform code instead; see
/// `native_audio_decoder.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Target sample rate of every on-device STT engine.
const int kSttSampleRate = 16000;

/// Raised for input this decoder cannot handle (not RIFF/WAVE, unsupported
/// sample layout, truncated header). The message is developer-facing; the
/// import queue maps it to a user-facing "format not supported" state.
class AudioDecodeException implements Exception {
  const AudioDecodeException(this.message);

  final String message;

  @override
  String toString() => 'AudioDecodeException: $message';
}

/// Raised when a file is valid but exceeds an import limit (duration or size).
/// Kept apart from [AudioDecodeException] so the queue can tell the user why.
class AudioInputLimitException implements Exception {
  const AudioInputLimitException(this.message);

  final String message;

  @override
  String toString() => 'AudioInputLimitException: $message';
}

/// Smallest and largest header sample rate accepted for import.
const int kMinImportSampleRate = 8000;
const int kMaxImportSampleRate = 192000;

/// Longest audio accepted for import; long meetings fit comfortably.
const Duration kMaxImportDuration = Duration(hours: 6);

/// Largest input file accepted for import, checked before it is read. Exactly
/// 1 GB (decimal), which is what the user-facing texts say.
const int kMaxImportFileBytes = 1000000000;

/// Mono float samples in `[-1, 1]` at [sampleRate].
class DecodedAudio {
  const DecodedAudio({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// Returns true when [bytes] starts with a RIFF/WAVE signature.
bool isWavBytes(Uint8List bytes) =>
    bytes.length >= 12 && _tag(bytes, 0) == 'RIFF' && _tag(bytes, 8) == 'WAVE';

/// Decodes a WAV file into mono float samples at its native rate.
///
/// Multi-channel input is averaged to mono. Truncated or zero data-chunk
/// sizes (the signature of an unfinished recording) are clamped to the bytes
/// actually present.
DecodedAudio decodeWavBytes(
  Uint8List bytes, {
  Duration maxDuration = kMaxImportDuration,
}) {
  if (!isWavBytes(bytes)) {
    throw const AudioDecodeException('not a RIFF/WAVE file');
  }
  final view = ByteData.sublistView(bytes);

  int? format;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? blockAlign;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      if (body + 16 > bytes.length) {
        throw const AudioDecodeException('truncated fmt chunk');
      }
      format = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      blockAlign = view.getUint16(body + 12, Endian.little);
      bitsPerSample = view.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE) {
        // WAVE_FORMAT_EXTENSIBLE: the real format tag is the first two bytes
        // of the sub-format GUID, which starts at fmt body offset 24.
        if (body + 26 > bytes.length) {
          throw const AudioDecodeException('truncated extensible fmt chunk');
        }
        format = view.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (format == null || channels == null || sampleRate == null) {
        throw const AudioDecodeException('data chunk before fmt chunk');
      }
      final start = body;
      var end = body + size;
      if (size == 0 || end > bytes.length) end = bytes.length;
      return _decodeData(
        bytes: bytes,
        view: view,
        start: start,
        end: end,
        format: format,
        channels: channels,
        sampleRate: sampleRate,
        bitsPerSample: bitsPerSample!,
        blockAlign: blockAlign!,
        maxDuration: maxDuration,
      );
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const AudioDecodeException('no data chunk');
}

DecodedAudio _decodeData({
  required Uint8List bytes,
  required ByteData view,
  required int start,
  required int end,
  required int format,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required int blockAlign,
  required Duration maxDuration,
}) {
  if (channels < 1 || sampleRate < 1) {
    throw const AudioDecodeException('invalid channel count or sample rate');
  }
  if (sampleRate < kMinImportSampleRate || sampleRate > kMaxImportSampleRate) {
    throw AudioDecodeException('unsupported sample rate $sampleRate');
  }
  final isFloat = format == 3;
  if (format != 1 && !isFloat) {
    throw AudioDecodeException('unsupported WAV format tag $format');
  }
  final bytesPerSample = bitsPerSample ~/ 8;
  final expectedBlock = bytesPerSample * channels;
  if (isFloat
      ? bitsPerSample != 32
      : !const {8, 16, 24, 32}.contains(bitsPerSample)) {
    throw AudioDecodeException('unsupported bit depth $bitsPerSample');
  }
  if (blockAlign != expectedBlock) {
    throw const AudioDecodeException('inconsistent block alignment');
  }

  final frames = (end - start) ~/ blockAlign;
  // Checked before the output buffer is allocated.
  final maxFrames = sampleRate * maxDuration.inMilliseconds ~/ 1000;
  if (frames > maxFrames) {
    throw AudioInputLimitException(
      'audio longer than ${maxDuration.inHours} hours',
    );
  }
  final mono = Float32List(frames);
  final scale = 1.0 / channels;
  for (var f = 0; f < frames; f++) {
    var acc = 0.0;
    for (var c = 0; c < channels; c++) {
      final pos = start + f * blockAlign + c * bytesPerSample;
      acc += _readSample(view, pos, bitsPerSample, isFloat);
    }
    mono[f] = acc * scale;
  }
  return DecodedAudio(samples: mono, sampleRate: sampleRate);
}

double _readSample(ByteData view, int pos, int bits, bool isFloat) {
  if (isFloat) return view.getFloat32(pos, Endian.little);
  switch (bits) {
    case 8:
      return (view.getUint8(pos) - 128) / 128.0;
    case 16:
      return view.getInt16(pos, Endian.little) / 32768.0;
    case 24:
      final lo = view.getUint8(pos);
      final mid = view.getUint8(pos + 1);
      final hi = view.getInt8(pos + 2);
      return ((hi << 16) | (mid << 8) | lo) / 8388608.0;
    default:
      return view.getInt32(pos, Endian.little) / 2147483648.0;
  }
}

/// Resamples [input] from [fromRate] to [toRate].
///
/// Downsampling applies a Hann-windowed sinc low-pass at the target Nyquist
/// before interpolation, so content above 8 kHz does not fold back into the
/// speech band. Equal rates return [input] unchanged.
Float32List resampleLinearSinc(Float32List input, int fromRate, int toRate) {
  if (fromRate == toRate || input.isEmpty) return input;
  final ratio = fromRate / toRate;
  final outLength = (input.length * toRate / fromRate).floor();
  final out = Float32List(outLength);
  // Kernel half-width in input samples; wider when downsampling so the
  // low-pass cutoff sits at the target Nyquist.
  final cutoff = math.min(1.0, 1.0 / ratio);
  final halfWidth = math.max(1, (8 * ratio).ceil());
  for (var n = 0; n < outLength; n++) {
    final centre = n * ratio;
    final first = math.max(0, (centre - halfWidth).ceil());
    final last = math.min(input.length - 1, (centre + halfWidth).floor());
    var acc = 0.0;
    var norm = 0.0;
    for (var i = first; i <= last; i++) {
      final x = (i - centre) * cutoff;
      final sinc = x == 0 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
      final window =
          0.5 + 0.5 * math.cos(math.pi * (i - centre) / (halfWidth + 1));
      final w = sinc * window * cutoff;
      acc += input[i] * w;
      norm += w;
    }
    out[n] = norm == 0 ? 0 : acc / norm;
  }
  return out;
}

/// Converts normalized float samples to 16-bit PCM with clipping.
Int16List floatToPcm16(Float32List samples) {
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final scaled = samples[i] * 32767.0;
    // NaN and infinities (from broken float WAVs) would make round() throw.
    if (!scaled.isFinite) {
      out[i] = 0;
      continue;
    }
    final v = scaled.round();
    out[i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
  }
  return out;
}

/// Builds a canonical 44-byte-header WAV (16-bit PCM, mono) around [pcm],
/// the same layout `wav_file_writer.dart` produces for recordings.
Uint8List encodePcm16MonoWav(Int16List pcm, {int sampleRate = kSttSampleRate}) {
  final dataBytes = pcm.lengthInBytes;
  final out = Uint8List(44 + dataBytes)
    ..setRange(0, 44, wavHeaderPcm16Mono(dataBytes, sampleRate: sampleRate))
    ..setRange(44, 44 + dataBytes, pcm.buffer.asUint8List());
  return out;
}

/// The 44-byte RIFF header of a mono 16-bit PCM WAV with [dataBytes] of sample
/// data. Writers that stream samples use it on their own.
Uint8List wavHeaderPcm16Mono(int dataBytes, {int sampleRate = kSttSampleRate}) {
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746D66, Endian.little) // 'fmt '
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // byte rate
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // 'data'
    ..setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

String _tag(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes, offset, offset + 4);
