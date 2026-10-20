/// WP-43a C-H-1: the fuzzy pass must still work at dictionary scale. A
/// wall-clock budget dropped it silently after a few rules, so a fuzzy entry in
/// the middle of a 5000-entry list never applied. The budget is now a
/// deterministic work count and the scoring skips windows that cannot reach
/// the threshold.
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

List<TextReplacementRule> _fuzzyRules(int count) => [
  for (var i = 0; i < count; i++)
    TextReplacementRule(
      triggers: ['zzfuzzy$i begriff'],
      replacement: 'Ersatz$i',
      matchMode: TextReplacementMatchMode.fuzzy,
      fuzzyThreshold: 0.85,
    ),
];

void main() {
  test('a fuzzy entry late in a 200-entry list still applies', () {
    final compiled = CompiledTextReplacements(_fuzzyRules(200));
    final text = '${_transcript()} zzfuzzy150 begrif';

    final result = compiled.apply(text);

    expect(result, contains('Ersatz150'));
    expect(compiled.fuzzyBudgetExceeded, isFalse);
  });

  test('an overrun of the window budget is reported, not silent', () {
    final compiled = CompiledTextReplacements(_fuzzyRules(5000));
    compiled.apply('${_transcript()} zzfuzzy4000 begrif');
    expect(compiled.fuzzyBudgetExceeded, isTrue);
  });

  test('the same input gives the same output on every run', () {
    final compiled = CompiledTextReplacements(_fuzzyRules(5000));
    final text = '${_transcript()} zzfuzzy4000 begrif zzfuzzy12 begriff';

    final first = compiled.apply(text);
    final second = compiled.apply(text);

    expect(second, first);
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
