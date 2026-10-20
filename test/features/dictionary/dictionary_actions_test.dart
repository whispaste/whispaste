/// Widget tests for the Dictionary actions: favourite, duplicate badge,
/// accepting and rejecting learned suggestions, and the CSV review page with
/// duplicates and broken lines.
library;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_preview_page.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_duplicates.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import 'package:whispaste/widgets/wp_favourite_star.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      final rows = await tester.runAsync(db.readAllReplacements);
      // ignore: avoid_print
      print(
        'DEBUG rows=${rows!.map((r) => '${r.row.id}:${r.row.isFavorite}').toList()}',
      );
      expect(rows.single.row.isFavorite, isTrue);
    });

    testWidgets(
      'two entries with the same trigger is badged on the later entry only',
      (tester) async {
        final db = await seed([('mfg', 'Manufacturing'), ('MFG', 'Factory')]);
        await openReplacementsTab(tester, db: db);

        // The entry listed first applies, so only the later one is badged.
        expect(find.text(l10n.dictionaryDuplicateBadge), findsOneWidget);
      },
    );
  });

  group('suggestions tab', () {
    const candidate = CorrectionCandidate(
      id: 'c1',
      sourceText: 'kubernets',
      targetText: 'Kubernetes',
      occurrenceCount: 2,
    );

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
      await tester.tap(find.text(l10n.dictionaryTabSuggestions));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestion-accept-c1')),
      );
      // The toast auto-dismisses after 3 s; read it before that, then drain.
      await tester.pump();
      expect(find.text(l10n.dictionarySuggestionAccepted), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('rejecting a suggestion reports it as rejected', (
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
      await tester.tap(find.text(l10n.dictionaryTabSuggestions));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dictionary-suggestion-reject-c1')),
      );
      await tester.pump();
      expect(find.text(l10n.dictionarySuggestionRejected), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
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
      List<ReplacementCsvRow>? confirmed;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await Navigator.of(context)
                    .push<List<ReplacementCsvRow>>(
                      MaterialPageRoute(
                        builder: (_) => DictionaryCsvPreviewPage(
                          result: result,
                          existingTriggerKeys: {normalizeTriggerKey('MFG')},
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

      expect(find.text(l10n.dictionaryCsvRowSkipped), findsOneWidget);
      expect(find.text(l10n.dictionaryCsvRowWillAdd), findsOneWidget);
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

      expect(confirmed, hasLength(1));
      expect(confirmed!.single.replacement, 'Large');
    });
  });
}
