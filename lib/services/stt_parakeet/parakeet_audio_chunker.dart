/// Splits long recordings into encoder-sized pieces for Parakeet.
///
/// The exported Parakeet encoder bakes a fixed-size relative-position
/// embedding; feeding it minutes of audio in one pass makes ONNX Runtime
/// throw a broadcast error inside `self_attn` (Sentry 150092299). That C++
/// exception escapes the sherpa_onnx FFI call and aborts the process, so
/// long audio must never reach the encoder in one piece.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Upper bound for one encoder pass. Kept well below the ~35 s the export's
/// position embedding covers.
const parakeetMaxChunkSeconds = 25;

/// How far back from the limit a cut may move to land in a pause.
const _searchSeconds = 5;

/// Energy window used to find the quietest cut point.
const _windowMs = 20;

/// Smallest chunk allowed — slivers trip ONNX shape errors too.
const _minChunkSeconds = 1;

/// Splits [samples] into consecutive chunks of at most
/// [parakeetMaxChunkSeconds], cutting at the quietest point within the last
/// [_searchSeconds] of each chunk. The chunks cover [samples] exactly.
List<Float32List> splitForParakeet(
  Float32List samples, {
  required int sampleRate,
}) {
  final maxLen = parakeetMaxChunkSeconds * sampleRate;
  final minLen = _minChunkSeconds * sampleRate;
  if (samples.length <= maxLen) return [samples];

  final window = math.max(1, sampleRate * _windowMs ~/ 1000);
  final chunks = <Float32List>[];
  var start = 0;
  while (samples.length - start > maxLen) {
    // The cut must leave at least minLen for the remainder.
    final hi = math.min(start + maxLen, samples.length - minLen);
    final lo = math.max(start + minLen, hi - _searchSeconds * sampleRate);
    final cut = _quietestCut(samples, lo, hi, window);
    chunks.add(Float32List.sublistView(samples, start, cut));
    start = cut;
  }
  chunks.add(Float32List.sublistView(samples, start));
  return chunks;
}

/// Returns the start of the lowest-energy window in `[lo, hi)`; `hi` when the
/// range is shorter than one window.
int _quietestCut(Float32List s, int lo, int hi, int window) {
  var best = hi;
  var bestEnergy = double.infinity;
  for (var w = lo; w + window <= hi; w += window) {
    var e = 0.0;
    for (var i = w; i < w + window; i++) {
      e += s[i] * s[i];
    }
    if (e < bestEnergy) {
      bestEnergy = e;
      best = w;
    }
  }
  return best;
}

/// Time budget for transcribing [audio]: a 30 s floor for dictations and
/// 1.5× real time for long recordings (CPU Parakeet runs well below 1× RTF).
Duration parakeetTranscribeTimeout(Duration audio) {
  const floor = Duration(seconds: 30);
  final scaled = audio * 1.5;
  return scaled > floor ? scaled : floor;
}
