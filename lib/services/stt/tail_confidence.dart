/// Shadow-mode protocol for token confidence at the end of a transcript (#573).
///
/// Question: can a cheap post-filter on the decoder's own token
/// probabilities catch hallucinated tails that the silence detection lets
/// through? This file only *measures*. Nothing here changes, strips or
/// delays a transcript; the filter stays off until the report
/// (`tool/tail_confidence_report.dart`) shows zero false positives over at
/// least [kTailConfidenceMinDictations] real dictations.
///
/// Privacy: the protocol is a local JSONL file and carries numbers only —
/// no transcript text, no audio, no hash of either. Dictations are matched to
/// history entries by timestamp, locally.
///
/// Pure Dart on purpose (#1754): no Flutter or app-logger import, so the
/// report tool runs with plain `dart run`. Callers log write failures.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Dictations needed before the shadow result counts (issue #573).
const int kTailConfidenceMinDictations = 500;

/// How many trailing text tokens of the last segment a sample keeps.
const int kTailConfidenceTokenCount = 8;

/// Size at which the protocol file rotates to `<name>.1` (one generation).
const int kTailConfidenceMaxBytes = 2 * 1024 * 1024;

/// Protocol file name inside the app data directory.
const String kTailConfidenceFileName = 'tail-confidence.jsonl';

/// What the engine measured for the last transcription: probabilities of the
/// final text tokens and the no-speech probability of the last segment that
/// carried text. Plain data so it crosses the isolate boundary.
class TailConfidenceSample {
  const TailConfidenceSample({
    required this.tokenProbs,
    required this.noSpeechProb,
    required this.segmentCount,
    required this.tailSegmentTokenCount,
  });

  /// Probabilities (0–1) of the last [kTailConfidenceTokenCount] text tokens
  /// (special and timestamp tokens excluded), oldest first.
  final List<double> tokenProbs;

  /// whisper.cpp's no-speech probability of the last text segment, if known.
  final double? noSpeechProb;

  /// Number of segments in the transcription.
  final int segmentCount;

  /// Text tokens in the last text segment (before the tail cut).
  final int tailSegmentTokenCount;
}

/// Builds the [TailConfidenceSample] of a whole transcription from its
/// per-segment text-token probabilities and no-speech probabilities. Looks at
/// the last segment that has text tokens. `null` if there is none.
TailConfidenceSample? tailConfidenceFromSegments(
  List<List<double>> segmentTokenProbs,
  List<double?> segmentNoSpeechProbs,
) {
  for (var i = segmentTokenProbs.length - 1; i >= 0; i--) {
    final probs = segmentTokenProbs[i];
    if (probs.isEmpty) continue;
    final start = probs.length > kTailConfidenceTokenCount
        ? probs.length - kTailConfidenceTokenCount
        : 0;
    return TailConfidenceSample(
      tokenProbs: List.unmodifiable(probs.sublist(start)),
      noSpeechProb: segmentNoSpeechProbs[i],
      segmentCount: segmentTokenProbs.length,
      tailSegmentTokenCount: probs.length,
    );
  }
  return null;
}

/// One line of the protocol. Numbers only, see the library doc.
class TailConfidenceRecord {
  const TailConfidenceRecord({
    required this.timestamp,
    required this.audioMs,
    required this.textChars,
    required this.words,
    required this.segments,
    required this.tailSegmentTokens,
    required this.tailMinP,
    required this.tailMeanP,
    required this.lastTokenP,
    required this.noSpeechP,
    required this.knownPhrase,
  });

  /// Builds a record from [sample] and the finished [text]; `null` when the
  /// sample holds no text token (nothing to judge).
  static TailConfidenceRecord? fromSample({
    required TailConfidenceSample sample,
    required String text,
    required int audioMs,
    required DateTime now,
    required bool knownPhrase,
  }) {
    final probs = sample.tokenProbs;
    if (probs.isEmpty) return null;
    var min = probs.first;
    var sum = 0.0;
    for (final v in probs) {
      if (v < min) min = v;
      sum += v;
    }
    final trimmed = text.trim();
    return TailConfidenceRecord(
      timestamp: now.toUtc(),
      audioMs: audioMs,
      textChars: trimmed.length,
      words: trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length,
      segments: sample.segmentCount,
      tailSegmentTokens: sample.tailSegmentTokenCount,
      tailMinP: min,
      tailMeanP: sum / probs.length,
      lastTokenP: probs.last,
      noSpeechP: sample.noSpeechProb,
      knownPhrase: knownPhrase,
    );
  }

  factory TailConfidenceRecord.fromJson(Map<String, Object?> json) {
    double num_(String k) => (json[k] as num).toDouble();
    return TailConfidenceRecord(
      timestamp: DateTime.parse(json['ts'] as String),
      audioMs: (json['audioMs'] as num).toInt(),
      textChars: (json['chars'] as num).toInt(),
      words: (json['words'] as num).toInt(),
      segments: (json['segments'] as num).toInt(),
      tailSegmentTokens: (json['tailSegTokens'] as num).toInt(),
      tailMinP: num_('tailMinP'),
      tailMeanP: num_('tailMeanP'),
      lastTokenP: num_('lastP'),
      noSpeechP: (json['noSpeechP'] as num?)?.toDouble(),
      knownPhrase: json['knownPhrase'] == true,
    );
  }

  final DateTime timestamp;
  final int audioMs;
  final int textChars;
  final int words;
  final int segments;
  final int tailSegmentTokens;
  final double tailMinP;
  final double tailMeanP;
  final double lastTokenP;
  final double? noSpeechP;

  /// The existing phrase filter already drops this transcript, so it is not a
  /// case the new filter would have to catch.
  final bool knownPhrase;

  Map<String, Object?> toJson() => {
    'ts': timestamp.toIso8601String(),
    'audioMs': audioMs,
    'chars': textChars,
    'words': words,
    'segments': segments,
    'tailSegTokens': tailSegmentTokens,
    'tailMinP': _round(tailMinP),
    'tailMeanP': _round(tailMeanP),
    'lastP': _round(lastTokenP),
    'noSpeechP': noSpeechP == null ? null : _round(noSpeechP!),
    'knownPhrase': knownPhrase,
  };

  String toLine() => jsonEncode(toJson());

  static double _round(double v) => (v * 10000).round() / 10000;
}

/// Appends [record] to the protocol in [dir]. Never throws: the shadow mode
/// must not be able to fail a dictation. Write failures go to [onError].
void appendTailConfidenceRecord(
  String dir,
  TailConfidenceRecord record, {
  void Function(Object error)? onError,
}) {
  try {
    final file = File(p.join(dir, kTailConfidenceFileName));
    if (file.existsSync() && file.lengthSync() >= kTailConfidenceMaxBytes) {
      file.renameSync('${file.path}.1');
    }
    file.writeAsStringSync('${record.toLine()}\n', mode: FileMode.append);
  } on Object catch (e) {
    // Best effort by design: report and carry on.
    onError?.call(e);
  }
}

/// A candidate rule for the later filter: the last segment's tail is
/// suspicious when its weakest tail token is below [minP] and/or the very
/// last text token is below [lastP]. A `null` bound is not checked; every set
/// bound must hold.
///
/// whisper.cpp's `noSpeechP` is deliberately not part of any rule (#1742):
/// v1.9.5 reads the `<|nospeech|>` probability after the whole prompt
/// (language, task, `<|notimestamps|>`), not at `<|startoftranscript|>` as
/// the reference implementation does, so it is ~0 even for pure silence and
/// noise (measured with the production engine: 0.000 every time, and 0.0 in
/// all 444 rows of the 1.5.0 protocol). It stays in the protocol as data.
class TailRule {
  const TailRule({this.minP, this.lastP})
    : assert(minP != null || lastP != null, 'a rule needs a bound');

  /// Upper bound (exclusive) for [TailConfidenceRecord.tailMinP].
  final double? minP;

  /// Upper bound (exclusive) for [TailConfidenceRecord.lastTokenP].
  final double? lastP;

  bool flags(TailConfidenceRecord r) =>
      !r.knownPhrase &&
      (minP == null || r.tailMinP < minP!) &&
      (lastP == null || r.lastTokenP < lastP!);

  String get label => [
    if (minP != null) 'tailMinP<$minP',
    if (lastP != null) 'lastP<$lastP',
  ].join(' & ');
}

/// Candidate rules the report evaluates, from lenient to strict. Chosen so
/// each one fires at all on real dictations (1.5.0 protocol, 444 rows:
/// 15, 11, 5 and 2 hits); whether the hits are hallucinations is what the
/// 500-dictation review decides.
const List<TailRule> kTailRules = [
  TailRule(minP: 0.40),
  TailRule(lastP: 0.50),
  TailRule(minP: 0.30),
  TailRule(minP: 0.40, lastP: 0.60),
];

/// Outcome of one [TailRule] over a protocol.
class TailRuleResult {
  const TailRuleResult(this.rule, this.flagged, this.falsePositives);
  final TailRule rule;

  /// Timestamps the rule would have cut.
  final List<DateTime> flagged;

  /// Flagged timestamps not confirmed as hallucination by the reviewer.
  final List<DateTime> falsePositives;
}

/// Evaluates every rule in [kTailRules] over [records]. [confirmed] holds the
/// timestamps (UTC ISO) a human checked against the history and confirmed as
/// real hallucinations; every other flagged dictation counts as a false
/// positive. Activation needs zero of them.
List<TailRuleResult> evaluateTailRules(
  List<TailConfidenceRecord> records,
  Set<DateTime> confirmed,
) {
  return [
    for (final rule in kTailRules)
      () {
        final flagged = [
          for (final r in records)
            if (rule.flags(r)) r.timestamp,
        ];
        return TailRuleResult(rule, flagged, [
          for (final t in flagged)
            if (!confirmed.contains(t)) t,
        ]);
      }(),
  ];
}

/// Parses protocol lines, skipping damaged ones.
List<TailConfidenceRecord> parseTailConfidenceLines(Iterable<String> lines) {
  final out = <TailConfidenceRecord>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    try {
      out.add(
        TailConfidenceRecord.fromJson(
          (jsonDecode(line) as Map).cast<String, Object?>(),
        ),
      );
    } on Object {
      continue;
    }
  }
  return out;
}
