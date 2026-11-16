/// #1004: rules either build on each other in list order (cascade, default)
/// or each match only the dictated original.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  const aToB = TextReplacementRule(triggers: ['alpha'], replacement: 'beta');
  const bToC = TextReplacementRule(triggers: ['beta'], replacement: 'gamma');

  group('cascade on', () {
    test('a later rule rewrites what an earlier one inserted', () {
      expect(applyTextReplacements('alpha', [aToB, bToC]), 'gamma');
    });

    test('a changed order changes the result', () {
      // b→c runs first and finds nothing, then a→b inserts "beta".
      expect(applyTextReplacements('alpha', [bToC, aToB]), 'beta');
    });
  });

  group('cascade off', () {
    test('each rule only sees the dictated text', () {
      expect(
        applyTextReplacements('alpha', [aToB, bToC], cascade: false),
        'beta',
      );
      expect(
        applyTextReplacements('alpha', [bToC, aToB], cascade: false),
        'beta',
      );
    });

    test('rules still replace their own words side by side', () {
      expect(
        applyTextReplacements('alpha und beta', [aToB, bToC], cascade: false),
        'beta und gamma',
      );
    });

    test(
      'on overlapping triggers the longest trigger wins in either order',
      () {
        const long = TextReplacementRule(
          triggers: ['mit freundlichen'],
          replacement: 'MF',
        );
        const short = TextReplacementRule(
          triggers: ['freundlichen'],
          replacement: 'FR',
        );
        expect(
          applyTextReplacements('mit freundlichen Grüßen', [
            long,
            short,
          ], cascade: false),
          'MF Grüßen',
        );
        expect(
          applyTextReplacements('mit freundlichen Grüßen', [
            short,
            long,
          ], cascade: false),
          'MF Grüßen',
        );
      },
    );

    test('fuzzy rules apply to the original, and hits are counted', () {
      const fuzzy = TextReplacementRule(
        triggers: ['Kubernetes'],
        replacement: 'Kubernetes',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: fuzzyThresholdStandard,
      );
      final hits = [0, 0, 0];
      expect(
        applyTextReplacements(
          'alpha auf Kubernets',
          [aToB, bToC, fuzzy],
          cascade: false,
          hits: hits,
        ),
        'beta auf Kubernetes',
      );
      expect(hits, [1, 0, 1]);
    });
  });
}
