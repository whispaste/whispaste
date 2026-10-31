/// Wall-clock budgets for the replacement matcher at dictionary scale: 1000
/// entries and a ~300 character transcript, the size of one dictation.
///
/// The asserted bounds are deliberately generous, so this catches regressions
/// such as recompiling every pattern per call. The logic of the same matcher
/// stays in test/services/replacements/text_replacement_matcher_test.dart.
///
/// Not part of a test run: see benchmarks/README.md.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

String _transcript() {
  const sentence = 'Das ist ein ganz normaler Satz mit Wörtern zur Prüfung. ';
  final buffer = StringBuffer();
  while (buffer.length < 300) {
    buffer.write(sentence);
  }
  return buffer.toString();
}

List<TextReplacementRule> _exactRules(int count) => [
  for (var i = 0; i < count; i++)
    TextReplacementRule(triggers: ['zzterm$i'], replacement: 'Ersatz$i'),
];

List<TextReplacementRule> _fuzzyRules(int count) => [
  for (var i = 0; i < count; i++)
    TextReplacementRule(
      triggers: ['zzfuzzy$i begriff'],
      replacement: 'Ersatz$i',
      matchMode: TextReplacementMatchMode.fuzzy,
      fuzzyThreshold: 0.85,
    ),
];

double _averageMillis(void Function() body, {int runs = 30}) {
  body(); // warm up, so the first JIT pass is not measured
  final sw = Stopwatch()..start();
  for (var r = 0; r < runs; r++) {
    body();
  }
  return sw.elapsedMicroseconds / runs / 1000;
}

void main() {
  test('exact pass, 1000 entries, 300 chars: cached compile stays fast', () {
    final text = _transcript();
    final compiled = CompiledTextReplacements(_exactRules(1000));
    final ms = _averageMillis(() => compiled.apply(text));
    // ignore: avoid_print
    print(
      'PERF exact miss 1000 entries, ${text.length} chars: '
      '${ms.toStringAsFixed(2)} ms (debug, cached compile)',
    );
    expect(ms, lessThan(100));
  });

  test('exact pass with hit counting stays within the same bound', () {
    final text = _transcript();
    final rules = _exactRules(1000);
    final compiled = CompiledTextReplacements(rules);
    final hits = List<int>.filled(rules.length, 0);
    final ms = _averageMillis(() => compiled.apply(text, hits: hits));
    // ignore: avoid_print
    print(
      'PERF exact miss with hits 1000 entries: ${ms.toStringAsFixed(2)} ms',
    );
    expect(ms, lessThan(100));
  });

  test('5000 fuzzy entries over a 300 character transcript stay fast', () {
    final compiled = CompiledTextReplacements(_fuzzyRules(5000));
    final text = _transcript();
    final sw = Stopwatch()..start();
    compiled.apply(text);
    sw.stop();
    // Generous bound: Debug build, and the machine is shared with parallel
    // test runs. It catches unbounded growth, not a few hundred milliseconds.
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('1000 exact entries over a 300 character transcript: under 20 ms', () {
    final rules = [
      for (var i = 0; i < 1000; i++)
        TextReplacementRule(triggers: ['zzterm$i'], replacement: 'Ersatz$i'),
    ];
    final compiled = CompiledTextReplacements(rules);
    final text = _transcript();
    compiled.applyExactOnly(text); // warm up
    const runs = 20;
    final sw = Stopwatch()..start();
    for (var r = 0; r < runs; r++) {
      compiled.applyExactOnly(text);
    }
    sw.stop();
    expect(sw.elapsedMicroseconds / runs / 1000, lessThan(20));
  });
}
