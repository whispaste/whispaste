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

import '../../core/recording/transcription_budget.dart';
import '../audio/pcm_wav_codec.dart';
import '../transcription/transcript_seam.dart';

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

/// One encoder pass as a sample range `[start, end)` of the recording, and
/// whether it starts with audio the previous range already ends with
/// ([overlapsPrevious]); see [ParakeetChunk].
class ParakeetChunkRange {
  const ParakeetChunkRange(
    this.start,
    this.end, {
    this.overlapsPrevious = false,
  });

  final int start;
  final int end;
  final bool overlapsPrevious;
}

/// Reads samples `[start, end)` as float32. The list may be reused by the
/// next call.
typedef ParakeetSampleReader = Float32List Function(int start, int end);

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
}) => [
  for (final range in parakeetChunkRanges(
    samples.length,
    sampleRate: sampleRate,
    read: (start, end) => Float32List.sublistView(samples, start, end),
  ))
    ParakeetChunk(
      Float32List.sublistView(samples, range.start, range.end),
      overlapsPrevious: range.overlapsPrevious,
    ),
];

/// The cuts of [splitForParakeet] for a recording of [length] samples, read
/// through [read] (#1665). Only the search span before each cut (at most
/// [_searchSeconds]) is read, so a recording read from its WAV file is never
/// held whole as float32.
List<ParakeetChunkRange> parakeetChunkRanges(
  int length, {
  required int sampleRate,
  required ParakeetSampleReader read,
}) {
  final maxLen = parakeetMaxChunkSeconds * sampleRate;
  final minLen = _minChunkSeconds * sampleRate;
  final overlap = _seamOverlapSeconds * sampleRate;
  if (length <= maxLen) return [ParakeetChunkRange(0, length)];

  final window = math.max(1, sampleRate * _windowMs ~/ 1000);
  final chunks = <ParakeetChunkRange>[];
  var start = 0;
  var overlaps = false;
  while (length - start > maxLen) {
    // The cut must leave at least minLen for the remainder. A hard cut moves
    // the next start back by [overlap], so the cut must lie beyond it.
    final hi = math.min(start + maxLen, length - minLen);
    final lo = math.max(
      start + minLen + overlap,
      hi - _searchSeconds * sampleRate,
    );
    final quiet = _quietestCut(
      lo < hi ? read(lo, hi) : Float32List(0),
      lo,
      hi,
      window,
    );
    chunks.add(
      ParakeetChunkRange(start, quiet.cut, overlapsPrevious: overlaps),
    );
    overlaps = !quiet.pause;
    start = quiet.pause ? quiet.cut : quiet.cut - overlap;
  }
  chunks.add(ParakeetChunkRange(start, length, overlapsPrevious: overlaps));
  return chunks;
}

/// Decodes [pcm] one chunk of [parakeetChunkRanges] at a time with [decode]
/// and joins the texts at their seams (#1665). Only the current chunk is
/// float32 (at most [parakeetMaxChunkSeconds], under 2 MB), in one buffer
/// reused for every chunk, so a recording read from its WAV file is never
/// held whole. [beforeChunk] runs before each chunk (an abort check may
/// throw there). Empty chunks are skipped: an empty buffer must never reach
/// a native decoder.
String transcribePcmInParakeetChunks(
  Pcm16WavView pcm, {
  required int sampleRate,
  required String Function(Float32List chunk) decode,
  void Function()? beforeChunk,
}) {
  if (pcm.sampleCount == 0) return '';
  final maxLen = parakeetMaxChunkSeconds * sampleRate;
  var search = Float32List(0);
  final ranges = parakeetChunkRanges(
    pcm.sampleCount,
    sampleRate: sampleRate,
    read: (start, end) {
      if (search.length < end - start) search = Float32List(end - start);
      return pcm.toFloat32Into(start, end, search);
    },
  );
  final buffer = Float32List(math.min(pcm.sampleCount, maxLen));
  final texts = <String>[];
  final overlaps = <bool>[];
  for (final range in ranges) {
    if (range.end <= range.start) continue;
    beforeChunk?.call();
    final chunk = pcm.toFloat32Into(range.start, range.end, buffer);
    texts.add(decode(chunk).trim());
    overlaps.add(range.overlapsPrevious);
  }
  return joinSeamTexts(texts, overlaps);
}

/// Where to cut: the start of the lowest-energy window in `[lo, hi)`, and
/// whether that window is a pause. Without a full window in range the cut is
/// `hi` and not a pause. [s] holds the samples `[lo, hi)`.
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
    for (var i = w - lo; i < w - lo + window; i++) {
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

/// Time budget for transcribing [audio]: the one local budget shared with
/// whisper.cpp (#1639, [localTranscriptionBudget]), from the benchmark RTF
/// [measuredRtf] and the overrun [boost].
Duration parakeetTranscribeTimeout(
  Duration audio, {
  double? measuredRtf,
  int boost = 1,
}) => localTranscriptionBudget(audio, measuredRtf: measuredRtf, boost: boost);
