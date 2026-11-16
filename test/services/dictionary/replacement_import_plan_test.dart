import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_import_plan.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

ReplacementCsvRow row(
  List<String> triggers,
  String replacement, {
  TextReplacementMatchMode mode = TextReplacementMatchMode.exact,
  double? threshold,
}) => ReplacementCsvRow(
  triggers: triggers,
  replacement: replacement,
  matchMode: mode,
  fuzzyThreshold: threshold,
);

ReplacementImportExisting existing(
  String id,
  List<String> triggers,
  String replacement, {
  TextReplacementMatchMode mode = TextReplacementMatchMode.exact,
  double? threshold,
}) => ReplacementImportExisting(
  id: id,
  triggers: triggers,
  replacement: replacement,
  matchMode: mode,
  fuzzyThreshold: threshold,
);

ReplacementImportPlan plan(
  List<ReplacementCsvRow> rows,
  List<ReplacementImportExisting> current,
  ReplacementImportStrategy strategy,
) => planReplacementImport(rows: rows, existing: current, strategy: strategy);

void main() {
  const skip = ReplacementImportStrategy.skip;
  const overwrite = ReplacementImportStrategy.overwrite;
  const keepBoth = ReplacementImportStrategy.keepBoth;

  group('no collision', () {
    test('a new trigger is added in every strategy', () {
      for (final strategy in ReplacementImportStrategy.values) {
        final result = plan(
          [
            row(['mfg'], 'Mit freundlichen Grüßen'),
          ],
          [
            existing('e1', ['lg'], 'Liebe Grüße'),
          ],
          strategy,
        );
        expect(result.statuses, [
          ReplacementImportStatus.added,
        ], reason: '$strategy');
        expect(result.inserts.single.triggers, ['mfg']);
        expect(result.updates, isEmpty);
        expect(result.deleteIds, isEmpty);
      }
    });
  });

  group('duplicates', () {
    test(
      'same trigger and same replacement exist: duplicate, never written',
      () {
        for (final strategy in ReplacementImportStrategy.values) {
          final result = plan(
            [
              row(['mfg'], 'Gruß'),
            ],
            [
              existing('e1', ['mfg'], 'Gruß'),
            ],
            strategy,
          );
          expect(result.statuses, [
            ReplacementImportStatus.duplicate,
          ], reason: '$strategy');
          expect(result.writeCount, 0);
          expect(result.changedExistingCount, 0);
          expect(result.conflictCount, 0);
        }
      },
    );

    test('trigger case and spacing do not matter', () {
      final result = plan(
        [
          row(['  MFG  '], 'Gruß'),
        ],
        [
          existing('e1', ['mfg'], 'Gruß'),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.duplicate]);
    });

    test(
      'a replacement that differs only by surrounding spaces is a duplicate',
      () {
        final result = plan(
          [
            row(['mfg'], '  Gruß '),
          ],
          [
            existing('e1', ['mfg'], 'Gruß'),
          ],
          skip,
        );
        expect(result.statuses, [ReplacementImportStatus.duplicate]);
      },
    );

    test('an entry with more triggers still covers a row with a subset', () {
      final result = plan(
        [
          row(['mfg'], 'Gruß'),
        ],
        [
          existing('e1', ['mfg', 'mfg gruss'], 'Gruß'),
        ],
        overwrite,
      );
      expect(result.statuses, [ReplacementImportStatus.duplicate]);
      expect(result.changedExistingCount, 0);
    });

    test('the same row twice in one file: the second is a duplicate', () {
      final result = plan(
        [
          row(['mfg'], 'Gruß'),
          row(['mfg'], 'Gruß'),
        ],
        const [],
        skip,
      );
      expect(result.statuses, [
        ReplacementImportStatus.added,
        ReplacementImportStatus.duplicate,
      ]);
      expect(result.writeCount, 1);
    });
  });

  group('conflicts: same trigger, other content', () {
    final rows = [
      row(['mfg'], 'Mit freundlichen Grüßen'),
    ];
    final current = [
      existing('e1', ['mfg'], 'Gruß'),
    ];

    test('skip: row left out, nothing changes', () {
      final result = plan(rows, current, skip);
      expect(result.statuses, [ReplacementImportStatus.conflictSkipped]);
      expect(result.writeCount, 0);
      expect(result.changedExistingCount, 0);
      expect(result.conflictCount, 1);
    });

    test('keep both: row added, existing entry untouched', () {
      final result = plan(rows, current, keepBoth);
      expect(result.statuses, [ReplacementImportStatus.conflictKept]);
      expect(result.inserts.single.replacement, 'Mit freundlichen Grüßen');
      expect(result.changedExistingCount, 0);
      expect(result.conflictCount, 1);
    });

    test('overwrite: the existing entry loses the trigger and is deleted', () {
      final result = plan(rows, current, overwrite);
      expect(result.statuses, [ReplacementImportStatus.conflictReplaced]);
      expect(result.deleteIds, ['e1']);
      expect(result.updates, isEmpty);
      expect(result.inserts.single.triggers, ['mfg']);
      expect(result.inserts.single.replacement, 'Mit freundlichen Grüßen');
    });

    test('overwrite keeps the other triggers of the existing entry', () {
      final result = plan(rows, [
        existing('e1', ['mfg', 'mahlzeit'], 'Gruß'),
      ], overwrite);
      expect(result.deleteIds, isEmpty);
      expect(result.updates.single.id, 'e1');
      expect(result.updates.single.triggers, ['mahlzeit']);
      expect(result.inserts.single.triggers, ['mfg']);
    });
  });

  group('conflicts: what counts as different', () {
    test('a different match mode is a conflict', () {
      final result = plan(
        [
          row(
            ['mfg'],
            'Gruß',
            mode: TextReplacementMatchMode.fuzzy,
            threshold: fuzzyThresholdStrict,
          ),
        ],
        [
          existing('e1', ['mfg'], 'Gruß'),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.conflictSkipped]);
    });

    test('a different threshold is a conflict', () {
      final result = plan(
        [
          row(
            ['mfg'],
            'Gruß',
            mode: TextReplacementMatchMode.fuzzy,
            threshold: fuzzyThresholdTolerant,
          ),
        ],
        [
          existing(
            'e1',
            ['mfg'],
            'Gruß',
            mode: TextReplacementMatchMode.fuzzy,
            threshold: fuzzyThresholdStrict,
          ),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.conflictSkipped]);
    });

    test('the same fuzzy settings are a duplicate', () {
      final result = plan(
        [
          row(
            ['mfg'],
            'Gruß',
            mode: TextReplacementMatchMode.fuzzy,
            threshold: fuzzyThresholdStrict,
          ),
        ],
        [
          existing(
            'e1',
            ['mfg'],
            'Gruß',
            mode: TextReplacementMatchMode.fuzzy,
            threshold: fuzzyThresholdStrict,
          ),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.duplicate]);
    });

    test('a replacement that differs in case is a conflict', () {
      final result = plan(
        [
          row(['gmbh'], 'Gmbh'),
        ],
        [
          existing('e1', ['gmbh'], 'GmbH'),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.conflictSkipped]);
    });

    test('an extra trigger on an otherwise identical row is a conflict', () {
      final result = plan(
        [
          row(['mfg', 'mfg gruß'], 'Gruß'),
        ],
        [
          existing('e1', ['mfg'], 'Gruß'),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.conflictSkipped]);
    });

    test('overwrite with an extra trigger takes over the shared one', () {
      final result = plan(
        [
          row(['mfg', 'mfg gruß'], 'Gruß'),
        ],
        [
          existing('e1', ['mfg'], 'Gruß'),
        ],
        overwrite,
      );
      expect(result.statuses, [ReplacementImportStatus.conflictReplaced]);
      expect(result.deleteIds, ['e1']);
      expect(result.inserts.single.triggers, ['mfg', 'mfg gruß']);
    });
  });

  group('conflicts within one file', () {
    test('overwrite supersedes the earlier row of the same file', () {
      final result = plan(
        [
          row(['x'], 'Erste'),
          row(['x'], 'Zweite'),
        ],
        const [],
        overwrite,
      );
      expect(result.statuses, [
        ReplacementImportStatus.supersededInFile,
        ReplacementImportStatus.conflictReplaced,
      ]);
      expect(result.inserts.map((i) => i.replacement), ['Zweite']);
      expect(result.conflictCount, 2);
    });

    test('keep both writes both rows', () {
      final result = plan(
        [
          row(['x'], 'Erste'),
          row(['x'], 'Zweite'),
        ],
        const [],
        keepBoth,
      );
      expect(result.statuses, [
        ReplacementImportStatus.added,
        ReplacementImportStatus.conflictKept,
      ]);
      expect(result.inserts.map((i) => i.replacement), ['Erste', 'Zweite']);
    });

    test('skip keeps the first row and leaves the second out', () {
      final result = plan(
        [
          row(['x'], 'Erste'),
          row(['x'], 'Zweite'),
        ],
        const [],
        skip,
      );
      expect(result.statuses, [
        ReplacementImportStatus.added,
        ReplacementImportStatus.conflictSkipped,
      ]);
      expect(result.inserts.map((i) => i.replacement), ['Erste']);
    });
  });

  group('loops', () {
    test('a two-step loop in the new rows: both rows are circular', () {
      for (final strategy in ReplacementImportStrategy.values) {
        final result = plan(
          [
            row(['a'], 'b'),
            row(['b'], 'a'),
          ],
          const [],
          strategy,
        );
        expect(result.statuses, [
          ReplacementImportStatus.circular,
          ReplacementImportStatus.circular,
        ], reason: '$strategy');
        expect(result.writeCount, 0);
      }
    });

    test('a new row that closes a loop with an existing entry is circular', () {
      final result = plan(
        [
          row(['kaffee'], 'ka'),
        ],
        [
          existing('e1', ['ka'], 'kaffee'),
        ],
        overwrite,
      );
      expect(result.statuses, [ReplacementImportStatus.circular]);
      expect(result.writeCount, 0);
      expect(result.changedExistingCount, 0);
    });

    test('a chain without a loop is fine', () {
      final result = plan(
        [
          row(['a'], 'b'),
          row(['b'], 'c'),
        ],
        const [],
        skip,
      );
      expect(result.statuses, [
        ReplacementImportStatus.added,
        ReplacementImportStatus.added,
      ]);
    });

    test('a self reference is allowed (case fix)', () {
      final result = plan(
        [
          row(['gmbh'], 'GmbH'),
        ],
        const [],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.added]);
    });

    test('an existing loop does not mark a new unrelated row', () {
      final result = plan(
        [
          row(['sig'], 'Signatur'),
        ],
        [
          existing('e1', ['a'], 'b'),
          existing('e2', ['b'], 'a'),
        ],
        skip,
      );
      expect(result.statuses, [ReplacementImportStatus.added]);
    });
  });

  group('triggers without letters or digits', () {
    test('survive an overwrite of their entry', () {
      final result = plan(
        [
          row(['mfg'], 'Gruß'),
        ],
        [
          existing('e1', ['mfg', '…'], 'Gruß alt'),
        ],
        overwrite,
      );
      expect(result.deleteIds, isEmpty);
      expect(result.updates.single.triggers, ['…']);
    });
  });

  group('counts', () {
    test('a mixed file adds up to one status per row', () {
      final rows = [
        row(['neu'], 'A'),
        row(['mfg'], 'Gruß'),
        row(['mfg'], 'Anders'),
        row(['neu'], 'A'),
      ];
      final result = plan(rows, [
        existing('e1', ['mfg'], 'Gruß'),
      ], skip);
      expect(result.statuses, [
        ReplacementImportStatus.added,
        ReplacementImportStatus.duplicate,
        ReplacementImportStatus.conflictSkipped,
        ReplacementImportStatus.duplicate,
      ]);
      expect(result.count(ReplacementImportStatus.added), 1);
      expect(result.writeCount, 1);
      expect(result.conflictCount, 1);
    });
  });
}
