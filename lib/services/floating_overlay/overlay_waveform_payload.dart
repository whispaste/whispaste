/// Compact waveform payload for the macOS overlay path (ticket phase 2, plan
/// item 5).
///
/// The 30 Hz waveform push used to send one 8-byte double per bar through two
/// platform-channel hops. The bars are normalised to `[0, 1]` and the pixel
/// height resolution is far coarser than 1/255, so each bar is sent as one
/// byte. [WaveformSendGate] also drops a payload identical to the last one sent
/// (silence and a settled release-out produce many of them).
library;

import 'dart:typed_data';

/// Encodes normalised levels as one byte each (`0 → 0`, `1 → 255`), clamping
/// out-of-range values.
Uint8List encodeWaveformBars(List<double> levels) {
  final out = Uint8List(levels.length);
  for (var i = 0; i < levels.length; i++) {
    final v = levels[i].clamp(0.0, 1.0);
    out[i] = (v * 255).round();
  }
  return out;
}

/// Decodes a payload back to normalised levels. Accepts the byte form from
/// [encodeWaveformBars] and a plain list of numbers (the form other platforms
/// still send). Anything else decodes to an empty list.
List<double> decodeWaveformBars(Object? raw) {
  if (raw is Uint8List) {
    return [for (final b in raw) b / 255.0];
  }
  if (raw is List) {
    return [for (final e in raw) (e as num?)?.toDouble() ?? 0.0];
  }
  return const [];
}

/// Suppresses a waveform payload identical to the last one accepted.
class WaveformSendGate {
  Uint8List? _last;

  /// Returns true when [bytes] differs from the last accepted payload (or is
  /// the first). A suppressed payload does not replace the baseline.
  bool accept(Uint8List bytes) {
    final last = _last;
    if (last != null && _sameBytes(last, bytes)) return false;
    _last = bytes;
    return true;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
