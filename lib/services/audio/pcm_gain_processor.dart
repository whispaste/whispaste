/// Pure-logic multiplier for 16-bit signed little-endian PCM chunks.
///
/// The manual input volume (#1611, "Eingangslautstärke"): scales every sample
/// in an incoming [Uint8List] by a fixed [gain] factor and passes it through
/// the soft limiter of `speech_leveler.dart`, so loud parts bend below
/// -1 dBFS instead of being cut off at the int16 limits. [clippedSamples]
/// counts samples that would have left the int16 range without the limiter,
/// [sampleCount] all samples, so callers can warn about a noticeable share.
///
/// Pure-data: no Riverpod, no platform channels, no I/O. Used by
/// `AudioService` between the raw PCM stream and the WAV writer / live
/// preview, only while the automatic level is off.
library;

import 'dart:typed_data';

import 'speech_leveler.dart';

/// Multiplies signed 16-bit little-endian PCM samples by a fixed gain factor.
///
/// Identity-fast-path: a `gain` of exactly `1.0` returns the input chunk
/// unchanged (same reference) and never increments [clippedSamples].
class PcmGainProcessor {
  PcmGainProcessor({required this.gain});

  /// Multiplicative scale applied to every sample. `1.0` is identity.
  final double gain;

  /// Samples since construction whose scaled value exceeded the int16 range
  /// (and were bent back by the limiter).
  int get clippedSamples => _clippedSamples;
  int _clippedSamples = 0;

  /// Samples processed since construction.
  int get sampleCount => _sampleCount;
  int _sampleCount = 0;

  /// Scales [chunk] by [gain] and returns a new [Uint8List] of equal length.
  ///
  /// When [gain] is exactly `1.0` the original chunk is returned without
  /// allocation. A trailing odd byte is copied verbatim.
  Uint8List process(Uint8List chunk) {
    _sampleCount += chunk.length ~/ 2;
    if (gain == 1.0) return chunk;
    final out = Uint8List.fromList(chunk);
    _clippedSamples += applyGainWithSoftLimit(ByteData.sublistView(out), gain);
    return out;
  }
}
