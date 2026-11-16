/// Structural guard for [toNumericOnly] — itn-cad-zahlen Slice 6 (PRD §8.5,
/// P3). Proof against the finished implementation from Slices 1-4, not an
/// intermediate stage. The wall-clock budgets P1/P2 live in benchmarks/.
///
/// Tagged `perf` so the dispatcher and CI keep it out of the shard pool.
@Tags(<String>['perf'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/number_transforms.dart';

void main() {
  group(
    'toNumericOnly — §8.5 P3: structural (no per-call RegExp, no async)',
    () {
      late List<String> engineLines;

      setUpAll(() {
        final file = File('lib/services/number_transforms.dart');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Engine-Datei muss existieren.',
        );
        engineLines = file.readAsLinesSync();
      });

      test(
        'no RegExp( construction outside a top-level/static final declaration',
        () {
          // A legitimate top-level regex declaration looks like
          // `final _fooRegex = RegExp(...)` at column 0 (no leading
          // whitespace) — anything else constructing `RegExp(` is a per-call
          // compilation, the exact pitfall a naive tokenizer falls into.
          final topLevelFinalRegex = RegExp(r'^final _\w+ = RegExp\(');
          final offendingLines = <String>[];
          for (final line in engineLines) {
            if (!line.contains('RegExp(')) continue;
            if (topLevelFinalRegex.hasMatch(line)) continue;
            offendingLines.add(line);
          }
          expect(
            offendingLines,
            isEmpty,
            reason:
                'RegExp( constructed outside a top-level final declaration:\n'
                '${offendingLines.join('\n')}',
          );
        },
      );

      test('no async/await/Future in the engine file', () {
        final offendingLines = engineLines
            .where(
              (line) =>
                  line.contains('async') ||
                  line.contains('await') ||
                  line.contains('Future'),
            )
            .toList();
        expect(
          offendingLines,
          isEmpty,
          reason:
              'async/await/Future found in number_transforms.dart:\n'
              '${offendingLines.join('\n')}',
        );
      });
    },
  );
}
