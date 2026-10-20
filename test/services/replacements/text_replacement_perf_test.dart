/// Performance guard for the replacement matcher at dictionary scale: 1000
/// entries and a ~300 character transcript, the size of one dictation.
///
/// The measured numbers are documented in the commit message and in
/// `docs/agents`-level notes only as a snapshot. The asserted bounds are
/// deliberately generous (Debug build on shared CI), so this catches
/// regressions such as recompiling every pattern per call, not noise.
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

  test('the fuzzy pass stops at its window budget, deterministically', () {
    final text = _transcript();
    final rules = [
      for (var i = 0; i < 1000; i++)
        TextReplacementRule(
          triggers: ['zzfuzzy$i begriff'],
          replacement: 'Ersatz$i',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
    ];
    final compiled = CompiledTextReplacements(rules, fuzzyWindowBudget: 50);
    final first = compiled.applyFuzzyOnly(text);
    expect(compiled.fuzzyBudgetExceeded, isTrue);
    expect(compiled.applyFuzzyOnly(text), first);
  });

  test('a rule can match a word that an earlier rule just inserted', () {
    final compiled = CompiledTextReplacements([
      const TextReplacementRule(triggers: ['alpha'], replacement: 'beta'),
      const TextReplacementRule(triggers: ['beta'], replacement: 'gamma'),
    ]);
    expect(compiled.apply('alpha'), 'gamma');
  });

  test('the cache recompiles only when a rule changes', () {
    final cache = CompiledRulesCache();
    final rules = _exactRules(3);
    final first = cache.forRules(rules);
    expect(identical(cache.forRules(_exactRules(3)), first), isTrue);
    final changed = [...rules]
      ..[1] = const TextReplacementRule(triggers: ['other'], replacement: 'x');
    expect(identical(cache.forRules(changed), first), isFalse);
  });
}
