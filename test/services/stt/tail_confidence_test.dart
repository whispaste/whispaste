import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/tail_confidence.dart';

TailConfidenceRecord _rec(
  double minP, {
  double? nsp,
  double lastP = 0.9,
  bool known = false,
  int sec = 0,
}) => TailConfidenceRecord(
  timestamp: DateTime.utc(2026, 11, 11, 10, 0, sec),
  audioMs: 5000,
  textChars: 40,
  words: 7,
  segments: 1,
  tailSegmentTokens: 9,
  tailMinP: minP,
  tailMeanP: 0.8,
  lastTokenP: lastP,
  noSpeechP: nsp,
  knownPhrase: known,
);

void main() {
  test('tail sample uses the last segment with text and caps the tail', () {
    final s = tailConfidenceFromSegments(
      [
        [0.9, 0.8],
        List.generate(12, (i) => i / 20),
        <double>[],
      ],
      [0.01, 0.4, 0.9],
    )!;
    expect(s.tokenProbs.length, kTailConfidenceTokenCount);
    expect(s.tokenProbs.last, 11 / 20);
    expect(s.noSpeechProb, 0.4);
    expect(s.tailSegmentTokenCount, 12);
    expect(s.segmentCount, 3);
    expect(tailConfidenceFromSegments([<double>[]], [null]), isNull);
  });

  test('record holds numbers only and round-trips', () {
    const secret = 'streng vertraulicher Satz';
    final r = TailConfidenceRecord.fromSample(
      sample: const TailConfidenceSample(
        tokenProbs: [0.5, 0.25, 0.75],
        noSpeechProb: 0.1,
        segmentCount: 2,
        tailSegmentTokenCount: 3,
      ),
      text: secret,
      audioMs: 4000,
      now: DateTime.utc(2026, 11, 11),
      knownPhrase: false,
    )!;
    final line = r.toLine();
    expect(line, isNot(contains('vertraulich')));
    expect(r.words, 3);
    expect(r.tailMinP, 0.25);
    expect(r.tailMeanP, closeTo(0.5, 1e-9));
    final back = parseTailConfidenceLines([line, 'kaputt', '']).single;
    expect(back.tailMinP, 0.25);
    expect(back.timestamp, DateTime.utc(2026, 11, 11));
  });

  test('rules flag weak tails; unconfirmed hits are false positives', () {
    final records = [
      _rec(0.02, lastP: 0.1, sec: 1),
      _rec(0.02, lastP: 0.1, sec: 2),
      _rec(0.9, lastP: 0.1, sec: 3),
      _rec(0.35, sec: 4),
      _rec(0.02, lastP: 0.1, known: true, sec: 5),
    ];
    final results = evaluateTailRules(records, {
      DateTime.utc(2026, 11, 11, 10, 0, 1),
    });
    final strict = results.last;
    expect(strict.flagged.length, 2);
    expect(strict.falsePositives, [DateTime.utc(2026, 11, 11, 10, 0, 2)]);
    // tailMinP<0.4 alone also takes the record with a strong last token.
    expect(results.first.flagged.length, 3);
  });

  test('no rule depends on noSpeechP, which whisper.cpp leaves at 0', () {
    final weak = [_rec(0.02, lastP: 0.1, nsp: 0.0)];
    for (final r in evaluateTailRules(weak, const {})) {
      expect(r.flagged, hasLength(1), reason: r.rule.label);
    }
    expect(
      kTailRules.map((r) => r.label),
      everyElement(isNot(contains('noSpeech'))),
    );
  });

  test('append rotates at the size limit and never throws', () {
    final dir = Directory.systemTemp.createTempSync('tailconf');
    addTearDown(() => dir.deleteSync(recursive: true));
    appendTailConfidenceRecord(dir.path, _rec(0.5));
    final file = File(p.join(dir.path, kTailConfidenceFileName));
    expect(file.readAsLinesSync().length, 1);
    file.writeAsStringSync('x' * kTailConfidenceMaxBytes);
    appendTailConfidenceRecord(dir.path, _rec(0.4));
    expect(File('${file.path}.1').existsSync(), isTrue);
    expect((jsonDecode(file.readAsLinesSync().single) as Map)['tailMinP'], 0.4);
    Object? reported;
    appendTailConfidenceRecord(
      '/nonexistent/dir',
      _rec(0.4),
      onError: (e) => reported = e,
    );
    expect(reported, isNotNull);
  });

  // The report tool must run with plain `dart run` (#1754): neither it nor
  // the protocol library may pull Flutter (directly or via app code) in.
  test('report tool and protocol library stay Flutter-free', () {
    final allowed = RegExp(
      r"^import '(dart:\w+|package:path/path\.dart|"
      r'package:whispaste/services/stt/tail_confidence\.dart|'
      r"package:whispaste_diagnostics/whispaste_diagnostics\.dart)'",
    );
    for (final path in const [
      'tool/tail_confidence_report.dart',
      'lib/services/stt/tail_confidence.dart',
    ]) {
      final imports = File(
        path,
      ).readAsLinesSync().where((l) => l.startsWith('import ')).toList();
      expect(imports, isNotEmpty, reason: path);
      for (final line in imports) {
        expect(allowed.hasMatch(line), isTrue, reason: '$path: $line');
      }
    }
  });
}
