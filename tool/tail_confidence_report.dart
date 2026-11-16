// Evaluates the shadow-mode protocol for token confidence at the transcript
// end (#573). Reads numbers only; never touches transcript text.
//
//   dart run tool/tail_confidence_report.dart [protocol.jsonl] [--confirmed file]
//
// Default protocol: `tail-confidence.jsonl` in the app data directory.
// `--confirmed` names a text file with one UTC timestamp (as printed by this
// report) per line for each flagged dictation the maintainer checked in the
// history and confirmed as a real hallucination. Everything flagged but not
// confirmed counts as a false positive. The filter may only be activated with
// at least 500 dictations and zero false positives.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whispaste/services/path_service.dart' show appDataDir;
import 'package:whispaste/services/stt/tail_confidence.dart';

void main(List<String> args) {
  String? path;
  String? confirmedPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--confirmed' && i + 1 < args.length) {
      confirmedPath = args[++i];
    } else {
      path = args[i];
    }
  }
  path ??= p.join(appDataDir(), kTailConfidenceFileName);
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No protocol at $path');
    exit(2);
  }
  final rotated = File('$path.1');
  final lines = [
    if (rotated.existsSync()) ...rotated.readAsLinesSync(),
    ...file.readAsLinesSync(),
  ];
  final records = parseTailConfidenceLines(lines);
  final confirmed = <DateTime>{
    if (confirmedPath != null)
      for (final l in File(confirmedPath).readAsLinesSync())
        if (l.trim().isNotEmpty) DateTime.parse(l.trim()).toUtc(),
  };
  final known = records.where((r) => r.knownPhrase).length;
  stdout.writeln(
    'Dictations: ${records.length} (needed: $kTailConfidenceMinDictations), '
    'already caught by phrase filter: $known',
  );
  var anyClean = false;
  for (final r in evaluateTailRules(records, confirmed)) {
    final fp = r.falsePositives.length;
    stdout.writeln(
      '\n${r.rule.label}: flagged ${r.flagged.length}, false positives $fp',
    );
    for (final t in r.falsePositives) {
      stdout.writeln('  review: ${t.toIso8601String()}');
    }
    if (fp == 0 && r.flagged.isNotEmpty) anyClean = true;
  }
  final enough = records.length >= kTailConfidenceMinDictations;
  final verdict = !enough
      ? 'not enough dictations yet'
      : anyClean
      ? 'a rule with hits and 0 false positives exists: activation can be discussed'
      : 'no rule is clean: do not activate';
  stdout.writeln('\nVerdict: $verdict');
}
