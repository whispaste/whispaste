/// Micro-benchmark for the replacement pass (`CompiledTextReplacements.apply`)
/// on the Hotkey -> text path. Compiles the rule list once (as
/// `CompiledRulesCache` does for dictations) and times `apply` on a dictation
/// of realistic length. Skipped in the default sweep. Run with:
///
/// ```sh
/// flutter test test/benchmark/replacements_apply_bench_test.dart \
///   --dart-define=WP_BENCH=true --dart-define=RULES=40 --dart-define=REPEAT=400
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

const _enabled = bool.fromEnvironment('WP_BENCH');
const _rules = int.fromEnvironment('RULES', defaultValue: 40);
const _repeat = int.fromEnvironment('REPEAT', defaultValue: 400);

const _words = [
  'the',
  'meeting',
  'with',
  'Anna',
  'about',
  'the',
  'release',
  'plan',
  'and',
  'budget',
  'we',
  'need',
  'to',
  'review',
  'open',
  'items',
  'before',
  'friday',
  'please',
  'send',
  'notes',
  'to',
  'the',
  'team',
  'today',
  'thanks',
  'a',
  'lot',
];

void main() {
  test(
    'replacement apply per dictation',
    skip: _enabled ? false : 'set --dart-define=WP_BENCH=true to run',
    () {
      final rules = [
        for (var i = 0; i < _rules; i++)
          TextReplacementRule(
            triggers: ['trigger phrase $i', 'alt $i'],
            replacement: i.isEven ? 'replacement $i.\n' : 'replacement $i',
          ),
      ];
      final compiled = CompiledRulesCache().forRules(rules);
      // ~700 characters of dictation with a few triggers in it.
      final buffer = StringBuffer();
      var w = 0;
      while (buffer.length < 700) {
        buffer.write(_words[w % _words.length]);
        buffer.write(w % 37 == 5 ? ' trigger phrase 3 ' : ' ');
        w++;
      }
      final text = buffer.toString();

      final timesUs = <int>[];
      var sink = 0;
      for (var i = 0; i < _repeat; i++) {
        final sw = Stopwatch()..start();
        sink += compiled.apply(text).length;
        sw.stop();
        timesUs.add(sw.elapsedMicroseconds);
      }
      timesUs.sort();
      int pct(double p) => timesUs[((timesUs.length - 1) * p).round()];
      print(
        'replacements.apply rules=$_rules repeat=$_repeat chars=${text.length} '
        'median=${pct(0.5)}us p90=${pct(0.9)}us p99=${pct(0.99)}us '
        'checksum=$sink',
      );
      expect(timesUs, isNotEmpty);
    },
  );
}
