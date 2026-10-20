import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/scroll_ownership_frame.dart';
import '../../ux_audit/ux_fixtures.dart';

/// Scroll ownership of the Dictionary's Replacements tab (WP-81, UX-028,
/// UX-029). The list owns the content pane once scrolled, the first paint
/// shows several rows, nothing overflows, and search is keyboard-reachable.
class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

const _sizes = [Size(800, 716), Size(1100, 720), Size(1600, 900)];
const _scales = [1.0, 1.3, 2.0];

Future<HistoryDatabase> _seed() async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  await db.upsertReplacementWithTriggers(
    id: 'seed',
    triggers: ['seed'],
    replacement: 'seed',
    createdAt: DateTime(2026),
  );
  return db;
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required HistoryDatabase db,
}) async {
  final l10n = lookupL10n(const Locale('en'));
  await pumpScrollFrame(
    tester,
    size: size,
    textScale: scale,
    db: db,
    overrides: [settingsProvider.overrideWith(_FakeSettingsNotifier.new)],
    page: const DictionaryPage(),
  );
  await tester.tap(find.text(l10n.dictionaryTabReplacements));
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(
      of: find.byKey(kScrollFramePaneKey),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  setUpAll(() async => loadAppFonts());

  for (final size in _sizes) {
    for (final scale in _scales) {
      final name = '${size.width.toInt()}x${size.height.toInt()} x$scale';

      testWidgets('replacements tab: nothing overflows at $name', (
        tester,
      ) async {
        final db = await tester.runAsync(_seed) ?? (throw StateError('db'));
        await _pumpTab(tester, size: size, scale: scale, db: db);
        expect(tester.takeException(), isNull);

        await tester.drag(_scrollable(), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'replacements tab: the list owns the pane once scrolled at $name',
        (tester) async {
          final db = await tester.runAsync(_seed) ?? (throw StateError('db'));
          await _pumpTab(tester, size: size, scale: scale, db: db);
          await tester.drag(_scrollable(), const Offset(0, -500));
          await tester.pumpAndSettle();

          final m = measureScrollShare(tester);
          expect(
            m.viewportHeight / m.paneHeight,
            greaterThanOrEqualTo(0.60),
            reason: 'list viewport must own at least 60% of the content pane',
          );
        },
      );
    }
  }

  testWidgets(
    'replacements tab: at 1100x720 five rows are visible on first paint',
    (tester) async {
      final db =
          await tester.runAsync(() async {
            final seeded = HistoryDatabase.forTesting(NativeDatabase.memory());
            for (var i = 0; i < 30; i++) {
              await seeded.upsertReplacementWithTriggers(
                id: 'r$i',
                triggers: ['trig-$i'],
                replacement: 'Ersatz $i',
                createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
              );
            }
            return seeded;
          }) ??
          (throw StateError('db'));
      await _pumpTab(tester, size: const Size(1100, 720), scale: 1, db: db);

      expect(countFullyVisibleRows(tester, 'trig-'), greaterThanOrEqualTo(5));
    },
  );

  testWidgets('replacements tab: Escape clears the search', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    final db = await tester.runAsync(_seed) ?? (throw StateError('db'));
    await _pumpTab(tester, size: const Size(1100, 720), scale: 1, db: db);

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

  // UX-029: at larger text the real app composition (sidebar, header, dock)
  // used to overflow the Replacements tab and cut off its bottom. Runs the
  // UX harness screen, so the sidebar and dock are the production ones.
  for (final size in [kUxSizeMinimum, kUxSize1100, kUxSize1440]) {
    for (final scale in [1.3, 2.0]) {
      for (final locale in ['de', 'en', 'he']) {
        testWidgets(
          'replacements tab: no overflow at ${size.width.toInt()}x${size.height.toInt()} '
          'x$scale $locale',
          (tester) async {
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));
            final screen = kUxScreens.firstWhere(
              (s) => s.id == 'dictionary-replacements',
            );
            await pumpUxScreen(
              tester,
              screen: screen,
              db: db,
              size: size,
              scale: scale,
              theme: 'dark',
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 5));
          },
        );
      }
    }
  }
}
