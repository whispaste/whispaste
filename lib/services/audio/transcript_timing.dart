/// Sentence time marks for a transcript with retained audio (#672).
///
/// No speech engine hands WhisPaste timestamps on the dictation path, and
/// asking for them would slow every dictation down. So the marks are
/// estimated afterwards from the retained recording itself: the spoken parts
/// of the audio (frame energy) are shared out over the sentences of the
/// transcript in proportion to their length, and every start is pulled to the
/// nearest pause. That works for every engine, for imported audio and for
/// recordings made before this feature.
///
/// The marks belong to the text the audio was transcribed into (the basis).
/// The current text may have been edited since; [alignTranscriptToBasis]
/// maps each current sentence to the basis sentence it came from, in order,
/// and leaves a sentence without a mark when none fits. The caller shows that
/// openly, so an edit never silently plays the wrong place.
///
/// Pure Dart: the caller reads the audio, this file only computes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One sentence of a transcript: its text and where it sits in the text.
class TranscriptSentence {
  const TranscriptSentence({
    required this.text,
    required this.start,
    required this.end,
  });

  /// The sentence, whitespace collapsed and Markdown list or heading marks
  /// stripped, as it is shown in the sentence list.
  final String text;

  /// Offset of its first character in the source text.
  final int start;

  /// Offset just after its last character in the source text.
  final int end;

  @override
  String toString() => 'TranscriptSentence($start-$end: $text)';
}

final RegExp _lineMarks = RegExp(r'^\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s*)');
final RegExp _inlineMarks = RegExp(r'[*_`~]+');
final RegExp _spaces = RegExp(r'\s+');

/// Sentences of [text]: ended by `.`, `!`, `?` or `…` followed by space (or
/// the end), by the full-width `。！？`, and by every line break. Empty
/// pieces are dropped.
List<TranscriptSentence> splitTranscriptSentences(String text) {
  final out = <TranscriptSentence>[];
  var start = 0;
  void emit(int end) {
    final raw = text.substring(start, end);
    final cleaned = raw
        .replaceFirst(_lineMarks, '')
        .replaceAll(_inlineMarks, '')
        .replaceAll(_spaces, ' ')
        .trim();
    if (cleaned.isNotEmpty && _hasWordChar(cleaned)) {
      // Trim the offsets to the visible part, so a caret on the leading
      // space of a line still belongs to the sentence before it.
      var s = start;
      var e = end;
      while (s < e && _isSpace(text.codeUnitAt(s))) {
        s++;
      }
      while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
        e--;
      }
      out.add(TranscriptSentence(text: cleaned, start: s, end: e));
    }
    start = end;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '\n') {
      emit(i);
      start = i + 1;
      continue;
    }
    if (c == '。' || c == '！' || c == '？') {
      // Full-width stops (Chinese, Japanese) end a sentence without a space.
      var j = i + 1;
      while (j < text.length && '。！？”」』）'.contains(text[j])) {
        j++;
      }
      emit(j);
      i = j - 1;
      continue;
    }
    if (c == '.' || c == '!' || c == '?' || c == '…') {
      // Runs like "?!" or "..." end once.
      var j = i + 1;
      while (j < text.length && '.!?…"»“”\')'.contains(text[j])) {
        j++;
      }
      if ((j >= text.length || _isSpace(text.codeUnitAt(j))) &&
          !(c == '.' && _isListNumber(text, start, i))) {
        emit(j);
        i = j - 1;
      }
    }
  }
  if (start < text.length) emit(text.length);
  return out;
}

/// Whether `text[from, dot)` is only a list number such as "1" or "12".
bool _isListNumber(String text, int from, int dot) {
  final head = text.substring(from, dot).trim();
  return head.isNotEmpty && RegExp(r'^\d{1,3}$').hasMatch(head);
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _hasWordChar(String s) {
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (ch.toLowerCase() != ch.toUpperCase() || (r >= 0x30 && r <= 0x39)) {
      return true;
    }
    // Scripts without case (CJK and others) count as words too.
    if (r > 0x2E80) return true;
  }
  return false;
}

/// Index of the sentence in [sentences] that holds [offset] (a caret in the
/// source text): the one it lies in, else the next one, else the last one.
/// Null when there are no sentences.
int? sentenceIndexAt(List<TranscriptSentence> sentences, int offset) {
  if (sentences.isEmpty) return null;
  for (var i = 0; i < sentences.length; i++) {
    if (offset <= sentences[i].end) return i;
  }
  return sentences.length - 1;
}

// ── Audio ────────────────────────────────────────────────────────────────

/// Length of one analysis frame.
const Duration speechFrame = Duration(milliseconds: 20);

/// Frame RMS (samples in `[-1, 1]`) below this counts as silence; the same
/// level the pause split of long uploads uses.
const double speechFrameSilenceRms = 0.015;

/// Which 20 ms frames of a recording hold sound, and how long it is.
class SpeechActivity {
  const SpeechActivity({required this.frames, required this.length});

  /// One entry per [speechFrame]: 1 = sound, 0 = silence.
  final Uint8List frames;

  /// Length of the whole recording.
  final Duration length;

  /// A recording with no frames (unreadable or empty).
  static final SpeechActivity empty = SpeechActivity(
    frames: Uint8List(0),
    length: Duration.zero,
  );
}

/// Reads a 16-bit PCM WAV (any rate, any channel count; the first channel
/// counts) and marks its sounding frames. A file it cannot read yields
/// [SpeechActivity.empty]. Runs in an isolate for long recordings.
SpeechActivity analyzeSpeechActivity(Uint8List wav) {
  final format = _readWavFormat(wav);
  if (format == null) return SpeechActivity.empty;
  final data = ByteData.sublistView(wav);
  final frameSamples = math.max(1, format.sampleRate * 20 ~/ 1000);
  final stride = format.channels * 2;
  final sampleCount = (format.dataEnd - format.dataStart) ~/ stride;
  final frameCount = sampleCount ~/ frameSamples;
  final frames = Uint8List(frameCount);
  const level = speechFrameSilenceRms * 32768;
  final silentSum = level * level * frameSamples;
  for (var f = 0; f < frameCount; f++) {
    var sum = 0.0;
    var at = format.dataStart + f * frameSamples * stride;
    for (var s = 0; s < frameSamples; s++) {
      final v = data.getInt16(at, Endian.little);
      sum += v * v;
      at += stride;
    }
    frames[f] = sum >= silentSum ? 1 : 0;
  }
  return SpeechActivity(
    frames: frames,
    length: Duration(microseconds: sampleCount * 1000000 ~/ format.sampleRate),
  );
}

class _WavFormat {
  const _WavFormat(
    this.sampleRate,
    this.channels,
    this.dataStart,
    this.dataEnd,
  );
  final int sampleRate;
  final int channels;
  final int dataStart;
  final int dataEnd;
}

_WavFormat? _readWavFormat(Uint8List wav) {
  if (wav.length < 12) return null;
  String tag(int at) => String.fromCharCodes(wav, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  final data = ByteData.sublistView(wav);
  int? rate;
  int? channels;
  int? bits;
  var at = 12;
  while (at + 8 <= wav.length) {
    final id = tag(at);
    final size = data.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ' && body + 16 <= wav.length) {
      final audioFormat = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      // 1 = PCM, 0xFFFE = extensible (PCM inside for what the app writes).
      if (audioFormat != 1 && audioFormat != 0xFFFE) return null;
    } else if (id == 'data') {
      if (rate == null || channels == null || bits != 16) return null;
      if (rate <= 0 || channels <= 0) return null;
      // A size field that was never patched (0 or too large) means "to the
      // end of the file", as the recorder may leave it after a crash.
      final end = size == 0 || body + size > wav.length
          ? wav.length
          : body + size;
      return _WavFormat(rate, channels, body, end);
    }
    at = body + size + (size.isOdd ? 1 : 0);
    if (size == 0 && id != 'data') at = body;
  }
  return null;
}

/// Shortest silence that counts as a pause between sentences: 200 ms.
const int _pauseFrames = 10;

/// How far a start may move to reach a pause: 1.5 s either way.
const int _snapFrames = 75;

/// Sound kept before a sentence start, so the first syllable is not cut.
const int _leadFrames = 8;

/// Estimated start of every sentence in [sentences] within [activity].
/// Empty when the recording has no sound at all. Starts never decrease.
List<Duration> estimateSentenceStarts(
  List<TranscriptSentence> sentences,
  SpeechActivity activity,
) {
  final frames = activity.frames;
  if (sentences.isEmpty) return const [];
  final spoken = <int>[];
  for (var f = 0; f < frames.length; f++) {
    if (frames[f] == 1) spoken.add(f);
  }
  if (spoken.isEmpty) return const [];

  // Sentence weights: letters and digits, at least one.
  final weights = [for (final s in sentences) math.max(1, _weight(s.text))];
  final total = weights.fold<int>(0, (a, b) => a + b);

  // Ends of pauses: frames where sound starts after enough silence.
  final pauseEnds = <int>[];
  var silentRun = 0;
  for (var f = 0; f < frames.length; f++) {
    if (frames[f] == 0) {
      silentRun++;
    } else {
      if (silentRun >= _pauseFrames) pauseEnds.add(f);
      silentRun = 0;
    }
  }

  final starts = <Duration>[];
  var before = 0;
  var lastFrame = 0;
  for (var i = 0; i < sentences.length; i++) {
    int frame;
    if (i == 0) {
      frame = spoken.first;
    } else {
      final share = before / total;
      frame =
          spoken[math.min(spoken.length - 1, (share * spoken.length).floor())];
      final snapped = _nearest(pauseEnds, frame);
      if (snapped != null && (snapped - frame).abs() <= _snapFrames) {
        frame = snapped;
      }
    }
    frame = math.max(frame - _leadFrames, 0);
    frame = math.max(frame, lastFrame);
    lastFrame = frame;
    starts.add(speechFrame * frame);
    before += weights[i];
  }
  return starts;
}

int _weight(String s) {
  var n = 0;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (ch.toLowerCase() != ch.toUpperCase() ||
        (r >= 0x30 && r <= 0x39) ||
        r > 0x2E80) {
      n++;
    }
  }
  return n;
}

int? _nearest(List<int> sorted, int value) {
  if (sorted.isEmpty) return null;
  var lo = 0;
  var hi = sorted.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sorted[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final after = sorted[lo];
  if (lo == 0) return after;
  final prior = sorted[lo - 1];
  return (value - prior) <= (after - value) ? prior : after;
}

// ── Mapping an edited text ───────────────────────────────────────────────

/// Least word overlap (Dice over word sets) for a current sentence to keep
/// the time mark of a basis sentence.
const double sentenceMatchThreshold = 0.5;

/// For each sentence of [current], the index of the [basis] sentence it came
/// from, or null when none fits. Matches keep their order (an edit does not
/// swap the audio), each basis sentence is used at most once, and the total
/// overlap is as large as possible.
List<int?> alignTranscriptToBasis(
  List<TranscriptSentence> current,
  List<TranscriptSentence> basis,
) {
  final n = current.length;
  final m = basis.length;
  if (n == 0) return const [];
  if (m == 0) return List<int?>.filled(n, null);
  final cw = [for (final s in current) _words(s.text)];
  final bw = [for (final s in basis) _words(s.text)];
  double sim(int i, int j) => _dice(cw[i], bw[j]);

  // Classic weighted LCS: score[i][j] over current[i..], basis[j..].
  final score = List.generate(n + 1, (_) => Float64List(m + 1));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      var best = math.max(score[i + 1][j], score[i][j + 1]);
      final s = sim(i, j);
      if (s >= sentenceMatchThreshold) {
        best = math.max(best, s + score[i + 1][j + 1]);
      }
      score[i][j] = best;
    }
  }
  final out = List<int?>.filled(n, null);
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    final s = sim(i, j);
    if (s >= sentenceMatchThreshold &&
        (score[i][j] - (s + score[i + 1][j + 1])).abs() < 1e-9) {
      out[i] = j;
      i++;
      j++;
    } else if (score[i + 1][j] >= score[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

final RegExp _wordSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

Set<String> _words(String s) {
  final parts = s.toLowerCase().split(_wordSplit).where((w) => w.isNotEmpty);
  final words = parts.toSet();
  // Scripts without spaces (CJK): compare characters instead.
  if (words.length <= 1 && s.runes.length > 4) {
    return {
      for (final r in s.runes)
        if (r > 0x2E80) String.fromCharCode(r),
      ...words,
    };
  }
  return words;
}

double _dice(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var common = 0;
  for (final w in a) {
    if (b.contains(w)) common++;
  }
  return 2 * common / (a.length + b.length);
}

// ── Result ───────────────────────────────────────────────────────────────

/// A sentence of the current transcript with its place in the audio.
class TimedSentence {
  const TimedSentence({required this.sentence, required this.start});

  final TranscriptSentence sentence;

  /// Where it starts in the audio; null when it has no time mark (new or
  /// rewritten after the transcription).
  final Duration? start;
}

/// The sentences of the current transcript with their time marks.
class TranscriptTiming {
  const TranscriptTiming({required this.sentences, required this.length});

  final List<TimedSentence> sentences;

  /// Length of the recording.
  final Duration length;

  /// Sentences that have no time mark.
  int get unmatchedCount => sentences.where((s) => s.start == null).length;

  /// Index of the sentence playing at [position]: the last one with a mark
  /// at or before it. Null before the first mark.
  int? indexAt(Duration position) {
    int? found;
    for (var i = 0; i < sentences.length; i++) {
      final start = sentences[i].start;
      if (start == null) continue;
      if (start <= position) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }
}

/// Time marks for [current] given the [basis] text the audio was
/// transcribed into and its [activity].
TranscriptTiming timeTranscript({
  required String current,
  required String basis,
  required SpeechActivity activity,
}) {
  final now = splitTranscriptSentences(current);
  final base = splitTranscriptSentences(basis);
  final starts = estimateSentenceStarts(base, activity);
  final map = starts.isEmpty
      ? List<int?>.filled(now.length, null)
      : alignTranscriptToBasis(now, base);
  return TranscriptTiming(
    sentences: [
      for (var i = 0; i < now.length; i++)
        TimedSentence(
          sentence: now[i],
          start: map[i] == null ? null : starts[map[i]!],
        ),
    ],
    length: activity.length,
  );
}
