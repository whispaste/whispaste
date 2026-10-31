/// Tests for [DictionaryPage]: the three tabs, the live replacement test
/// field, the empty suggestions state, the CSV review page, and the test IDs
/// the UI tests address the page by.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_preview_page.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/dictionary/widgets/dictionary_terms_field.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_import_plan.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: db,
        overrides: [settingsProvider.overrideWith(_FakeSettingsNotifier.new)],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DictionaryPage', () {
    testWidgets('shows the three tabs with the terms tab first', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.text(l10n.dictionaryTabTerms), findsOneWidget);
      expect(find.text(l10n.dictionaryTabReplacements), findsOneWidget);
      expect(find.text(l10n.dictionaryTabSuggestions), findsOneWidget);
      expect(find.byType(DictionaryTermsField), findsOneWidget);
    });

    testWidgets('switching to replacements shows the CSV actions', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.text(l10n.dictionaryTabReplacements));
      await tester.pumpAndSettle();

      // CSV import/export and the try-it dialog sit behind the ⋯ menu.
      await tester.tap(find.byKey(const ValueKey('replacements-more')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-csv-import')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dictionary-csv-export')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dictionary-test-open')),
        findsOneWidget,
      );
    });

    testWidgets('test field reports when no replacement applies', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.text(l10n.dictionaryTabReplacements));
      await tester.pumpAndSettle();

      // The try-it dialog opens from the ⋯ menu.
      await tester.tap(find.byKey(const ValueKey('replacements-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dictionary-test-open')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('dictionary-test-input')),
        'nothing to change here',
      );
      await tester.pump();

      expect(find.textContaining(l10n.dictionaryTestNoChange), findsOneWidget);
    });

    testWidgets('suggestions tab shows the empty state without candidates', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.text(l10n.dictionaryTabSuggestions));
      await tester.pumpAndSettle();

      expect(find.text(l10n.dictionarySuggestionsEmpty), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dictionary-suggestions-list')),
        findsNothing,
      );
    });

    testWidgets('replacements tab: Escape clears the search', (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await tester.runAsync(
        () => db.upsertReplacementWithTriggers(
          id: 'seed',
          triggers: ['seed'],
          replacement: 'seed',
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const DictionaryPage(),
          db: db,
          overrides: [settingsProvider.overrideWith(_FakeSettingsNotifier.new)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dictionaryTabReplacements));
      await tester.pumpAndSettle();

      final search = find.descendant(
        of: find.byType(WpSearchField),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'zzz-no-match');
      await tester.pumpAndSettle();
      // Precondition: the filter really produced the no-results state, so the
      // Escape below is what clears it and not a list that never filtered.
      expect(
        find.text(l10n.replacementsNoMatches),
        findsOneWidget,
        reason: 'the search must have emptied the list before Escape',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
    });
  });

  group('DictionaryCsvPreviewPage', () {
    testWidgets('lists rows and skipped lines, and imports only on confirm', (
      tester,
    ) async {
      const result = ReplacementCsvParseResult(
        rows: [
          ReplacementCsvRow(triggers: ['mfg'], replacement: 'Manufacturing'),
        ],
        errors: [
          ReplacementCsvError(
            line: 3,
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
                          existing: [],
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
        find.byKey(const ValueKey('dictionary-csv-preview-row-0')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.dictionaryCsvLineError(
            3,
            l10n.dictionaryCsvReasonEmptyReplacement,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('dictionary-csv-preview-import')),
      );
      await tester.pumpAndSettle();

      expect(confirmed!.writeCount, 1);
      expect(confirmed!.inserts.single.replacement, 'Manufacturing');
    });
  });
}
