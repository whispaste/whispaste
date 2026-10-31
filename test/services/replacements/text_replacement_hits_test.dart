import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  const rules = [
    TextReplacementRule(
      triggers: ['mfg'],
      replacement: 'Mit freundlichen Grüßen',
    ),
    TextReplacementRule(triggers: ['lg', 'l g'], replacement: 'Liebe Grüße'),
    TextReplacementRule(
      triggers: ['Kubernetes'],
      replacement: 'Kubernetes',
      matchMode: TextReplacementMatchMode.fuzzy,
      fuzzyThreshold: fuzzyThresholdStandard,
    ),
  ];

  test('counts every change per rule, in rule order', () {
    final hits = List<int>.filled(rules.length, 0);
    final out = applyTextReplacements(
      'mfg und lg, dann mfg. Kubernets läuft.',
      rules,
      hits: hits,
    );
    expect(
      out,
      'Mit freundlichen Grüßen und Liebe Grüße, dann Mit freundlichen Grüßen. Kubernetes läuft.',
    );
    expect(hits, [2, 1, 1]);
  });

  test('a rule that does not match keeps a zero counter', () {
    final hits = List<int>.filled(rules.length, 0);
    applyTextReplacements('nichts zu sehen', rules, hits: hits);
    expect(hits, [0, 0, 0]);
  });

  test('counting does not change the output', () {
    const text = 'mfg, lg, l g und Kubernets';
    final counted = applyTextReplacements(
      text,
      rules,
      hits: List<int>.filled(rules.length, 0),
    );
    expect(counted, applyTextReplacements(text, rules));
  });

  test('hits accumulate across calls when the caller reuses the list', () {
    final hits = List<int>.filled(rules.length, 0);
    applyTextReplacements('mfg', rules, hits: hits);
    applyTextReplacements('mfg mfg', rules, hits: hits);
    expect(hits[0], 3);
  });
}
