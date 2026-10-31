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

/// One encoder pass: its [samples] (a view, no copy) and whether it starts
/// with audio the previous chunk already ends with ([overlapsPrevious]). Its
/// repeated leading words are removed at the text seam (see
/// `joinSeamTexts` in `transcript_seam.dart`).
class ParakeetChunk {
  const ParakeetChunk(this.samples, {this.overlapsPrevious = false});

  final Float32List samples;
  final bool overlapsPrevious;
}

/// Seconds of audio a hard cut repeats at the start of the next chunk.
const _seamOverlapSeconds = 2;

/// Frame RMS below which a cut counts as a pause (same as the Whisper split).
const _silenceRms = 0.015;

/// Splits [samples] into consecutive chunks of at most
/// [parakeetMaxChunkSeconds], cutting at the quietest point within the last
/// [_searchSeconds] of each chunk.
///
/// A cut in a pause ends the chunk and the next one starts right there. When
/// no pause is found (the quietest window is still speech), the cut is a hard
/// cut: the next chunk starts [_seamOverlapSeconds] earlier, so no word is
/// lost at the seam. The overlap is taken from the start of the next chunk,
/// so every chunk, overlap included, stays within [parakeetMaxChunkSeconds].
List<ParakeetChunk> splitForParakeet(
  Float32List samples, {
  required int sampleRate,
}) {
  final maxLen = parakeetMaxChunkSeconds * sampleRate;
  final minLen = _minChunkSeconds * sampleRate;
  final overlap = _seamOverlapSeconds * sampleRate;
  if (samples.length <= maxLen) return [ParakeetChunk(samples)];

  final window = math.max(1, sampleRate * _windowMs ~/ 1000);
  final chunks = <ParakeetChunk>[];
  var start = 0;
  var overlaps = false;
  while (samples.length - start > maxLen) {
    // The cut must leave at least minLen for the remainder. A hard cut moves
    // the next start back by [overlap], so the cut must lie beyond it.
    final hi = math.min(start + maxLen, samples.length - minLen);
    final lo = math.max(
      start + minLen + overlap,
      hi - _searchSeconds * sampleRate,
    );
    final quiet = _quietestCut(samples, lo, hi, window);
    chunks.add(
      ParakeetChunk(
        Float32List.sublistView(samples, start, quiet.cut),
        overlapsPrevious: overlaps,
      ),
    );
    overlaps = !quiet.pause;
    start = quiet.pause ? quiet.cut : quiet.cut - overlap;
  }
  chunks.add(
    ParakeetChunk(
      Float32List.sublistView(samples, start),
      overlapsPrevious: overlaps,
    ),
  );
  return chunks;
}

/// Where to cut: the start of the lowest-energy window in `[lo, hi)`, and
/// whether that window is a pause. Without a full window in range the cut is
/// `hi` and not a pause.
({int cut, bool pause}) _quietestCut(
  Float32List s,
  int lo,
  int hi,
  int window,
) {
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
  final pause =
      bestEnergy.isFinite && math.sqrt(bestEnergy / window) < _silenceRms;
  return (cut: best, pause: pause);
}

/// Time budget for transcribing [audio]: a 30 s floor for dictations and
/// 1.5× real time for long recordings (CPU Parakeet runs well below 1× RTF).
Duration parakeetTranscribeTimeout(Duration audio) {
  const floor = Duration(seconds: 30);
  final scaled = audio * 1.5;
  return scaled > floor ? scaled : floor;
}
