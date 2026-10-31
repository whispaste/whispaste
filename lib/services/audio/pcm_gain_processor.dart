/// Pure-logic multiplier for 16-bit signed little-endian PCM chunks.
///
/// Scales every sample in an incoming [Uint8List] by a fixed [gain] factor
/// and clamps the result into the int16 range `[-32768, 32767]`. Each clamp
/// increments an observable [clippedSamples] counter so callers can warn the
/// user when the configured gain over-drove the recording.
///
/// Pure-data: no Riverpod, no platform channels, no I/O. The processor holds
/// only the running clipping counter; the scaling itself is stateless across
/// chunks. Used by `AudioService` between the raw PCM stream and the WAV-writer
/// /amplitude-meter fork.
library;

import 'dart:typed_data';

/// Multiplies signed 16-bit little-endian PCM samples by a fixed gain factor.
///
/// Usage:
/// ```dart
/// final processor = PcmGainProcessor(gain: 1.5);
/// final scaled = processor.process(chunk);
/// // ... feed [scaled] into the next pipeline stage ...
/// final clipped = processor.clippedSamples;
/// ```
///
/// Identity-fast-path: a `gain` of exactly `1.0` returns the input chunk
/// unchanged (same reference) and never increments [clippedSamples].
class PcmGainProcessor {
  PcmGainProcessor({required this.gain});

  /// Multiplicative scale applied to every sample. `1.0` is identity.
  final double gain;

  /// Total number of int16 samples that saturated to `[-32768, 32767]` since
  /// construction. One sample whose scaled value would exceed the int16 range
  /// counts as one clip — multi-sample chunks contribute one increment per
  /// clipped sample.
  int get clippedSamples => _clippedSamples;
  int _clippedSamples = 0;

  /// Scales [chunk] by [gain] and returns a new [Uint8List] of equal length.
  ///
  /// When [gain] is exactly `1.0` the original chunk is returned without
  /// allocation. Otherwise every two-byte sample is read as little-endian
  /// signed int16, multiplied, clamped to the int16 range, and written back.
  Uint8List process(Uint8List chunk) {
    if (gain == 1.0) return chunk;

    final length = chunk.length;
    // Chunks should always be a whole number of int16 samples (2 bytes each).
    // A trailing odd byte is preserved as-is — the next chunk completes the
    // sample on its own (16-bit PCM streams from `record` never split a
    // sample mid-byte in practice).
    final out = Uint8List(length);
    final view = ByteData.sublistView(chunk);
    final outView = ByteData.sublistView(out);

    final sampleCount = length ~/ 2;
    for (var i = 0; i < sampleCount; i++) {
      final byteOffset = i * 2;
      final sample = view.getInt16(byteOffset, Endian.little);
      // Scale in double precision so 0.5 * 1 still rounds toward zero in the
      // expected direction; `.round()` is half-away-from-zero which matches
      // standard PCM resampling conventions.
      final scaled = (sample * gain).round();
      int clamped;
      if (scaled > 32767) {
        clamped = 32767;
        _clippedSamples++;
      } else if (scaled < -32768) {
        clamped = -32768;
        _clippedSamples++;
      } else {
        clamped = scaled;
      }
      outView.setInt16(byteOffset, clamped, Endian.little);
    }

    // Copy a trailing odd byte verbatim (defensive — should never happen on
    // a 16-bit PCM stream, but avoids dropping data if it does).
    if (length.isOdd) {
      out[length - 1] = chunk[length - 1];
    }

    return out;
  }
}
