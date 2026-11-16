/// Widget tests for the Dictionary actions: favourite, duplicate badge,
/// accepting and rejecting learned suggestions, and the CSV review page with
/// duplicates and broken lines.
library;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_preview_page.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_import_plan.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import 'package:whispaste/widgets/wp_favourite_star.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

/// Keeps settings changes in memory so a test can read what a control wrote.
class _MemorySettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.requireValue));
  }
}

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<HistoryDatabase> seed(List<(String, String)> rows) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    for (final (i, row) in rows.indexed) {
      await db.upsertReplacementWithTriggers(
        id: 'r$i',
        triggers: [row.$1],
        replacement: row.$2,
        createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }
    return db;
  }

  Future<void> openReplacementsTab(
    WidgetTester tester, {
    List overrides = const [],
    HistoryDatabase? db,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: db,
        overrides: [
          settingsProvider.overrideWith(_FakeSettingsNotifier.new),
          ...overrides,
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dictionaryTabReplacements));
    await tester.pumpAndSettle();
  }

  group('replacements tab', () {
    testWidgets('tapping the star marks the entry as a favourite', (
      tester,
    ) async {
      // The default 800x600 view puts the row's star below the fold.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = await seed([('mfg', 'Manufacturing')]);
      await openReplacementsTab(tester, db: db);

      // The row actions appear on hover, so hover the row before the star.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('mfg')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WpFavouriteStar).first);
      await tester.pump();
      // The toggle writes through the database off the fake clock: wait for
      // the row to change (bounded by a deadline), not for a fixed time.
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline)) {
          if ((await db.readAllReplacements()).single.row.isFavorite) break;
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();

      final rows = await tester.runAsync(db.readAllReplacements);
      expect(rows!.single.row.isFavorite, isTrue);
    });

    testWidgets('two entries with the same trigger are both badged', (
      tester,
    ) async {
      final db = await seed([('mfg', 'Manufacturing'), ('MFG', 'Factory')]);
      await openReplacementsTab(tester, db: db);

      // Both collide on the same normalised trigger, so both carry the badge
      // (see replacement_duplicates.dart). The earlier test passed only
      // because the old 48 px list strip built just the first row.
      expect(find.text(l10n.dictionaryDuplicateBadge), findsNWidgets(2));
    });
  });

  group('suggestions tab', () {
    const candidate = CorrectionCandidate(
      id: 'c1',
      sourceText: 'kubernets',
      targetText: 'Kubernetes',
      occurrenceCount: 2,
    );

    Future<void> openSuggestionsTab(
      WidgetTester tester,
      HistoryDatabase db, {
      List<CorrectionCandidate> candidates = const [],
    }) async {
      await tester.pumpWidget(
        makeTestable(
          const DictionaryPage(),
          db: db,
          overrides: [
            settingsProvider.overrideWith(_MemorySettingsNotifier.new),
            pendingCorrectionCandidatesProvider.overrideWith(
              (ref) async => candidates,
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictionary-tab-suggestions')),
      );
      await tester.pumpAndSettle();
    }

    AppSettings settingsOf(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(DictionaryPage)),
    ).read(settingsProvider).requireValue;

    testWidgets('the learning switch turns correction learning off', (
      tester,
    ) async {
      final db = await seed([]);
      await openSuggestionsTab(tester, db);
      expect(settingsOf(tester).behavior.correctionLearningEnabled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestions-learning-toggle')),
      );
      await tester.pumpAndSettle();

      expect(settingsOf(tester).behavior.correctionLearningEnabled, isFalse);
    });

    testWidgets('keeping a suggestion as a term writes it into the own '
        'vocabulary', (tester) async {
      final db = await seed([]);
      await tester.runAsync(
        () => db.upsertCorrectionObservation(
          id: candidate.id,
          normalizedKey: 'kubernets => kubernetes',
          sourceText: candidate.sourceText,
          targetText: candidate.targetText,
          occurrenceCount: 2,
          status: 'pending',
          source: 'manualEdit',
          unit: 'word',
          firstSeenAt: DateTime(2026, 1, 1),
          lastSeenAt: DateTime(2026, 1, 2),
        ),
      );
      await openSuggestionsTab(tester, db, candidates: [candidate]);

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestion-term-c1')),
      );
      await tester.pumpAndSettle();

      expect(settingsOf(tester).stt.customVocabulary, contains('Kubernetes'));
    });

    testWidgets('accepting a suggestion confirms it', (tester) async {
      final db = await seed([]);
      await tester.pumpWidget(
        makeTestable(
          const DictionaryPage(),
          db: db,
          overrides: [
            settingsProvider.overrideWith(_FakeSettingsNotifier.new),
            pendingCorrectionCandidatesProvider.overrideWith(
              (ref) async => [candidate],
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictionary-tab-suggestions')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestion-replace-c1')),
      );
      await tester.pumpAndSettle();
      // Success is not announced as a toast or notice, and nothing failed.
      expect(find.text(l10n.dictionarySuggestionAccepted), findsNothing);
      expect(
        find.byKey(const ValueKey('page-notice-suggestion-failed')),
        findsNothing,
      );
    });

    testWidgets('rejecting a suggestion shows no failure notice', (
      tester,
    ) async {
      final db = await seed([]);
      await tester.pumpWidget(
        makeTestable(
          const DictionaryPage(),
          db: db,
          overrides: [
            settingsProvider.overrideWith(_FakeSettingsNotifier.new),
            pendingCorrectionCandidatesProvider.overrideWith(
              (ref) async => [candidate],
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictionary-tab-suggestions')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestion-reject-c1')),
      );
      await tester.pumpAndSettle();
      // The quiet "rejected" notice with undo is intended (#321); only a
      // failure notice would be wrong.
      expect(
        find.byKey(const ValueKey('page-notice-suggestion-failed')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    });
  });

  group('CSV review page', () {
    testWidgets('skips duplicates, lists broken lines, adds only the rest', (
      tester,
    ) async {
      const result = ReplacementCsvParseResult(
        rows: [
          ReplacementCsvRow(triggers: ['mfg'], replacement: 'Manufacturing'),
          ReplacementCsvRow(triggers: ['lg'], replacement: 'Large'),
        ],
        errors: [
          ReplacementCsvError(
            line: 4,
            reason: ReplacementCsvErrorReason.emptyReplacement,
          ),
        ],
      );
      ReplacementImportPlan? confirmed;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await Navigator.of(context)
                    .push<ReplacementImportPlan>(
                      MaterialPageRoute(
                        builder: (_) => const DictionaryCsvPreviewPage(
                          result: result,
                          existing: [
                            ReplacementImportExisting(
                              id: 'e1',
                              triggers: ['MFG'],
                              replacement: 'Anderer Text',
                            ),
                          ],
                        ),
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.dictionaryCsvStatusConflictSkipped),
        findsOneWidget,
      );
      expect(find.text(l10n.dictionaryCsvStatusAdded), findsOneWidget);
      expect(
        find.text(
          l10n.dictionaryCsvLineError(
            4,
            l10n.dictionaryCsvReasonEmptyReplacement,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.dictionaryCsvPreviewAddCount(1)), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('dictionary-csv-preview-import')),
      );
      await tester.pumpAndSettle();

      expect(confirmed!.writeCount, 1);
      expect(confirmed!.inserts.single.replacement, 'Large');
    });

    testWidgets('choosing a conflict strategy updates the counts and hint', (
      tester,
    ) async {
      const result = ReplacementCsvParseResult(
        rows: [
          ReplacementCsvRow(triggers: ['mfg'], replacement: 'Mit Grüßen'),
        ],
        errors: [],
      );
      await tester.pumpWidget(
        makeTestable(
          const DictionaryCsvPreviewPage(
            result: result,
            existing: [
              ReplacementImportExisting(
                id: 'e1',
                triggers: ['mfg', 'mahlzeit'],
                replacement: 'Gruß',
              ),
            ],
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Default is skip: nothing is written, so the button is disabled.
      expect(find.text(l10n.dictionaryCsvStrategySkipHint), findsOneWidget);
      expect(find.text(l10n.dictionaryCsvPreviewAddCount(0)), findsOneWidget);

      await tester.tap(find.text(l10n.dictionaryCsvStrategyOverwrite));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.dictionaryCsvStrategyOverwriteHint(1)),
        findsOneWidget,
      );
      expect(find.text(l10n.dictionaryCsvPreviewAddCount(1)), findsOneWidget);
      expect(
        find.text(l10n.dictionaryCsvStatusConflictReplaced),
        findsOneWidget,
      );
    });

    testWidgets(
      'a package whose entries all exist says so and writes nothing',
      (tester) async {
        const result = ReplacementCsvParseResult(
          rows: [
            ReplacementCsvRow(triggers: ['mfg'], replacement: 'Gruß'),
          ],
          errors: [],
        );
        await tester.pumpWidget(
          makeTestable(
            const DictionaryCsvPreviewPage(
              result: result,
              existing: [
                ReplacementImportExisting(
                  id: 'e1',
                  triggers: ['mfg'],
                  replacement: 'Gruß',
                ),
              ],
            ),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('dictionary-csv-preview-all-present')),
          findsOneWidget,
        );
        expect(find.text(l10n.dictionaryCsvAllPresent), findsOneWidget);
        expect(find.text(l10n.dictionaryCsvPreviewAddCount(0)), findsOneWidget);
      },
    );
  });
}
