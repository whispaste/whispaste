/// In-process dBFS calculator over raw 16-bit signed little-endian PCM
/// chunks.
///
/// Replaces `recorder.onAmplitudeChanged()` for the stream-based recording
/// pipeline. The calculator accumulates the peak absolute sample seen across
/// all chunks that arrive within one [pollInterval] and emits a single dBFS
/// value at the end of each interval — matching the polling cadence of the
/// previous file-backed recorder.
///
/// Pure-data: no Riverpod, no platform channels. The output stream is fed
/// straight into the existing [SpeechLevelMapper], which maps dBFS to the
/// 0.0–1.0 visual level used by the floating overlay and safety guard.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// Streams a peak-based dBFS value once per [pollInterval] from raw PCM data
/// pushed through [addChunk].
///
/// Lifecycle:
/// 1. Construct with a polling interval (e.g. 40 ms ≈ 25 Hz).
/// 2. Listen to [stream] for dBFS values.
/// 3. Call [addChunk] for every incoming PCM chunk.
/// 4. Call [dispose] when the recording stops to cancel the timer and close
///    the stream.
class AmplitudeFromPcm {
  AmplitudeFromPcm({required this.pollInterval}) {
    _timer = Timer.periodic(pollInterval, (_) => _flush());
  }

  /// Cadence at which a consolidated dBFS value is emitted on [stream].
  final Duration pollInterval;

  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  /// Maximum absolute sample value seen since the last flush, in the int16
  /// range `[0, 32768]`.
  int _peakAbs = 0;

  /// Whether any chunk arrived since the last flush.
  bool _sawChunk = false;

  /// Time since the last chunk, advanced by one [pollInterval] per empty
  /// tick.
  Duration _sinceChunk = Duration.zero;

  /// Longest gap between chunks that still repeats the last level. Past it
  /// the source has stalled, and reporting silence lets the silence guards
  /// see the stall instead of a level frozen at the last loud value.
  static const Duration maxHold = Duration(milliseconds: 500);

  bool _hadChunk = false;
  Duration _longestChunkGap = Duration.zero;

  /// The longest time between two chunks, at [pollInterval] resolution. A
  /// diagnostic for how far apart the platform delivers its batches, which
  /// [maxHold] must stay above.
  Duration get longestChunkGap => _longestChunkGap;

  /// The value emitted by the last flush that saw a chunk. The platform
  /// delivers PCM in batches longer than [pollInterval], so a tick without
  /// data repeats it instead of reporting silence. Starts silent, so a
  /// stream that never delivers still reads as a dead microphone.
  double _lastDbFs = double.negativeInfinity;

  Timer? _timer;
  bool _disposed = false;

  /// Reciprocal of the int16 full-scale value, used to convert peak samples
  /// to a normalised amplitude before the log10 conversion.
  static const double _int16FullScale = 32768.0;

  /// Output stream — one dBFS value per [pollInterval].
  Stream<double> get stream => _controller.stream;

  /// Feeds a PCM chunk into the calculator.
  ///
  /// [bytes] must be little-endian signed 16-bit PCM. Odd-length chunks are
  /// tolerated by ignoring the trailing byte (defensive — the `record`
  /// plugin emits whole samples).
  void addChunk(Uint8List bytes) {
    if (_disposed) return;
    _sawChunk = true;
    final usable = bytes.length & ~1; // drop trailing byte if odd
    for (var i = 0; i < usable; i += 2) {
      // Manual little-endian int16 decode: bytes[i] is low byte, bytes[i+1]
      // is high byte (signed).
      final low = bytes[i];
      final high = bytes[i + 1];
      var sample = low | (high << 8);
      if ((high & 0x80) != 0) {
        sample -= 0x10000;
      }
      final abs = sample < 0 ? -sample : sample;
      if (abs > _peakAbs) _peakAbs = abs;
    }
  }

  /// Emits the dBFS value for the accumulated peak since the last flush and
  /// resets the accumulator. Without a new chunk it repeats the last value
  /// for up to [maxHold].
  void _flush() {
    if (_controller.isClosed) return;
    if (_sawChunk) {
      final gap = _sinceChunk + pollInterval;
      if (_hadChunk && gap > _longestChunkGap) _longestChunkGap = gap;
      _hadChunk = true;
      _lastDbFs = _peakToDbFs(_peakAbs);
      _peakAbs = 0;
      _sawChunk = false;
      _sinceChunk = Duration.zero;
    } else {
      _sinceChunk += pollInterval;
      if (_sinceChunk > maxHold) _lastDbFs = double.negativeInfinity;
    }
    _controller.add(_lastDbFs);
  }

  /// Converts an int16 peak amplitude to dBFS. Silence (`peak == 0`) is
  /// reported as [double.negativeInfinity] so the downstream mapper clamps
  /// to its floor.
  static double _peakToDbFs(int peakAbs) {
    if (peakAbs <= 0) return double.negativeInfinity;
    final normalised = peakAbs / _int16FullScale;
    return 20 * math.log(normalised) / math.ln10;
  }

  /// Cancels the timer and closes the output stream.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}
