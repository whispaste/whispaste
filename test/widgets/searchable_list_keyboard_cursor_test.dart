/// Arrow-key cursor of `WpSearchableListPage` — Snippets and Replacements,
/// driven by the keyboard and nothing else (ticket 05).
///
/// Every test here reaches its rows the way the ticket's user does: the page
/// opens, keys are sent, nothing is tapped. Seeding goes through the feature's
/// own notifier rather than through the Add dialog, so a failure points at the
/// cursor rather than at the dialog that filled the list.
///
/// The two pages are exercised through one table because the model under test
/// lives in the shared shell: a divergence between them is a defect, and a
/// per-page copy of these tests would be the place it could hide.
library;

import 'dart:io' show Platform;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

import '../fixtures/test_helpers.dart';

late L10n l10n;

// ---------------------------------------------------------------------------
// The two pages under test
// ---------------------------------------------------------------------------

/// One searchable-list feature, described by what its rows say on screen and
/// what opening / deleting one of them puts in front of the user.
class _Page {
  const _Page({
    required this.name,
    required this.build,
    required this.seed,
    required this.rowTexts,
    required this.query,
    required this.queryMatch,
    required this.editTitle,
    required this.deleteTitle,
  });

  final String name;
  final Widget Function() build;

  /// Fills the list through the feature's notifier. Replacements seeds itself
  /// (three samples on an empty DB), so there it is a no-op.
  final Future<void> Function(ProviderContainer) seed;

  /// Texts rendered by three different rows. Which one is *first* is read off
  /// the screen rather than assumed — see [_rowsInVisualOrder].
  final List<String> rowTexts;

  /// A query that leaves exactly [queryMatch] visible.
  final String query;
  final String queryMatch;

  final String Function(L10n) editTitle;
  final String Function(L10n) deleteTitle;
}

final _pages = <_Page>[
  _Page(
    name: 'Snippets',
    build: SnippetsPage.new,
    seed: (container) async {
      final notifier = container.read(snippetsProvider.notifier);
      await notifier.add('Alpha', 'First body');
      await notifier.add('Bravo', 'Second body');
      await notifier.add('Charlie', 'Third body');
    },
    rowTexts: const ['Alpha', 'Bravo', 'Charlie'],
    query: 'Brav',
    queryMatch: 'Bravo',
    editTitle: (l) => l.snippetsEditSnippet,
    deleteTitle: (l) => l.snippetsDeleteTitle,
  ),
  _Page(
    name: 'Replacements',
    build: ReplacementsPage.new,
    // The three sample shortcuts a fresh database is seeded with.
    seed: (_) async {},
    rowTexts: const ['mfg', 'lg', 'tel'],
    // Matches the 'tel' row through its *replacement* text, not its trigger:
    // a query equal to a row's own text would make `find.text` ambiguous
    // between the row and the search field that now contains the same string.
    query: '+49',
    queryMatch: 'tel',
    editTitle: (l) => l.replacementsEditShortcut,
    deleteTitle: (l) => l.replacementsDeleteTitle,
  ),
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<ProviderContainer> _pumpPage(WidgetTester tester, _Page page) async {
  final widget = page.build();
  await tester.pumpWidget(makeTestable(widget, locale: const Locale('en')));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byWidget(widget)),
  );
  await page.seed(container);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The row texts that are on screen, top to bottom. Read from the layout so
/// no test has to know how a feature's DB orders its rows.
List<String> _rowsInVisualOrder(WidgetTester tester, _Page page) {
  final present = page.rowTexts
      .where((t) => find.text(t).evaluate().isNotEmpty)
      .toList();
  present.sort(
    (a, b) => tester
        .getTopLeft(find.text(a))
        .dy
        .compareTo(tester.getTopLeft(find.text(b)).dy),
  );
  return present;
}

/// The tile envelope of the row that renders [text] — the single place the
/// ticket allows the cursor to become visible.
WpListTileSurface _surfaceOf(WidgetTester tester, String text) =>
    tester.widget<WpListTileSurface>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(WpListTileSurface),
      ),
    );

/// Whether a screen reader would announce the row as selected. `getSemantics`
/// on the rendered text resolves to the row's merged node, exactly as
/// `no_double_announcement_test.dart` does it.
///
/// The flag is a [Tristate]: `none` means "this node has no selected state at
/// all", which is what a row that is not the cursor reports — distinct from
/// an explicit "not selected". Both count as "not announced as selected".
bool _announcedSelected(WidgetTester tester, String text) =>
    tester
        .getSemantics(find.text(text))
        .getSemanticsData()
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

/// Asserts that [text]'s row — and only it — is the cursor, in both outlets
/// at once: the shared tile envelope and the semantics tree.
void _expectCursorOn(WidgetTester tester, _Page page, String text) {
  for (final candidate in page.rowTexts) {
    if (find.text(candidate).evaluate().isEmpty) continue;
    final isCursor = candidate == text;
    expect(
      _surfaceOf(tester, candidate).isFocused,
      isCursor,
      reason:
          '${page.name}: the cursor is drawn by WpListTileSurface.isFocused, '
          'so "$candidate" should ${isCursor ? '' : 'not '}carry it',
    );
    expect(
      _announcedSelected(tester, candidate),
      isCursor,
      reason:
          '${page.name}: a screen reader learns about the cursor from the '
          'row\'s selected flag, so "$candidate" should '
          '${isCursor ? '' : 'not '}report it',
    );
  }
}

void _expectNoCursor(WidgetTester tester, _Page page) {
  for (final candidate in page.rowTexts) {
    if (find.text(candidate).evaluate().isEmpty) continue;
    expect(_surfaceOf(tester, candidate).isFocused, isFalse);
    expect(_announcedSelected(tester, candidate), isFalse);
  }
}

/// The search field's own focus node, identified by the debug label the shell
/// gives it. Asserting on the node rather than on "some text field has focus"
/// keeps the Snippets case honest, where a second field (the picker trigger)
/// sits above the search field on macOS.
bool _searchFieldHasFocus() =>
    FocusManager.instance.primaryFocus?.debugLabel ==
    'WpSearchableListPage search';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Semantics stays on for the whole file rather than per test: every
  // assertion here reads the tree, and a handle taken inside a test body has
  // to be disposed before the body ends — which a failing expectation skips,
  // burying the real failure under a handle-leak assertion.
  late SemanticsHandle semantics;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    semantics = TestWidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  });

  tearDownAll(() => semantics.dispose());

  for (final page in _pages) {
    group('${page.name} — keyboard cursor', () {
      testWidgets('ArrowDown enters the list at the first row, in both the '
          'tile envelope and the semantics tree', (tester) async {
        await _pumpPage(tester, page);
        final rows = _rowsInVisualOrder(tester, page);
        expect(rows, hasLength(3), reason: 'all three rows are seeded');
        _expectNoCursor(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);

        _expectCursorOn(tester, page, rows.first);
      });

      testWidgets('ArrowDown/ArrowUp walk the list and stop at both ends', (
        tester,
      ) async {
        await _pumpPage(tester, page);
        final rows = _rowsInVisualOrder(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        _expectCursorOn(tester, page, rows[1]);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        _expectCursorOn(
          tester,
          page,
          rows.last,
          // Clamping, not wrapping — the same choice Verlauf/Notizen made.
        );

        await _press(tester, LogicalKeyboardKey.arrowUp);
        _expectCursorOn(tester, page, rows[1]);

        await _press(tester, LogicalKeyboardKey.arrowUp);
        await _press(tester, LogicalKeyboardKey.arrowUp);
        _expectCursorOn(tester, page, rows.first);
      });

      testWidgets('Enter opens the cursor row', (tester) async {
        await _pumpPage(tester, page);
        final rows = _rowsInVisualOrder(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.enter);

        expect(find.text(page.editTitle(l10n)), findsOneWidget);
        expect(
          find.text(rows[1]),
          findsWidgets,
          reason: 'the dialog is pre-filled from the row the cursor stood on',
        );
      });

      testWidgets('Escape hands the caret back to the search field and drops '
          'the cursor', (tester) async {
        await _pumpPage(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        expect(_searchFieldHasFocus(), isFalse);

        await _press(tester, LogicalKeyboardKey.escape);

        expect(
          _searchFieldHasFocus(),
          isTrue,
          reason: 'Escape is the one way back out of the list',
        );
        _expectNoCursor(tester, page);
      });

      testWidgets('Ctrl/Cmd+F still focuses the search field, cursor or not', (
        tester,
      ) async {
        await _pumpPage(tester, page);
        await _press(tester, LogicalKeyboardKey.arrowDown);

        // `Platform.isMacOS`, not `defaultTargetPlatform` — the shell binds
        // the chord off the host platform, so the test has to ask the same
        // question it does.
        final modifier = Platform.isMacOS
            ? LogicalKeyboardKey.meta
            : LogicalKeyboardKey.control;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();

        expect(_searchFieldHasFocus(), isTrue);
        _expectNoCursor(tester, page);
      });

      testWidgets('the cursor walks the filtered list, not the full one', (
        tester,
      ) async {
        await _pumpPage(tester, page);
        // Typing into the field is the only pointer-free way to filter; the
        // shell's search field is the one that carries the shell's own node.
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.focusNode?.debugLabel == 'WpSearchableListPage search',
          ),
          page.query,
        );
        await tester.pumpAndSettle();

        final rows = _rowsInVisualOrder(tester, page);
        expect(rows, [page.queryMatch]);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        _expectCursorOn(tester, page, page.queryMatch);

        // Down again cannot leave the one match — the filtered list is the
        // whole world the cursor knows about.
        await _press(tester, LogicalKeyboardKey.arrowDown);
        _expectCursorOn(tester, page, page.queryMatch);

        await _press(tester, LogicalKeyboardKey.enter);
        expect(find.text(page.editTitle(l10n)), findsOneWidget);
      });

      testWidgets('the cursor row reveals its delete action and Delete opens '
          'the confirmation', (tester) async {
        await _pumpPage(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        expect(
          find.byIcon(LucideIcons.trash2),
          findsOneWidget,
          reason:
              'the icon and the key appear together — a visible trash icon '
              'the Delete key cannot reach is the state this must not ship in',
        );

        await _press(tester, LogicalKeyboardKey.delete);
        expect(find.text(page.deleteTitle(l10n)), findsOneWidget);
      });

      testWidgets('the cursor survives opening and closing a row, so the list '
          'is not re-entered from the top', (tester) async {
        await _pumpPage(tester, page);
        final rows = _rowsInVisualOrder(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.enter);
        expect(find.text(page.editTitle(l10n)), findsOneWidget);

        await _press(tester, LogicalKeyboardKey.escape);
        expect(find.text(page.editTitle(l10n)), findsNothing);

        _expectCursorOn(tester, page, rows[1]);
      });

      testWidgets('Tab moves real focus into a row and the cursor stops '
          'painting — one highlight at a time', (tester) async {
        await _pumpPage(tester, page);
        final rows = _rowsInVisualOrder(tester, page);

        await _press(tester, LogicalKeyboardKey.arrowDown);
        _expectCursorOn(tester, page, rows.first);

        await _press(tester, LogicalKeyboardKey.tab);

        expect(
          _announcedSelected(tester, rows.first),
          isFalse,
          reason:
              'the page-level cursor gives way to the row that now really '
              'holds focus, so exactly one row is ever marked',
        );
      });
    });
  }

  // The one place this model deliberately parts ways with its Verlauf/Notizen
  // template, so the one place a test has to exist for: a panel list gets
  // away with never scrolling its cursor, a full-width page list of 40 rows
  // does not. Snippets stands in for both — the mechanism is in the shared
  // shell, not in either tile.
  testWidgets('the cursor scrolls itself into view on a list taller than the '
      'viewport', (tester) async {
    const page = SnippetsPage();
    await tester.pumpWidget(makeTestable(page, locale: const Locale('en')));
    await tester.pumpAndSettle();
    final notifier = ProviderScope.containerOf(
      tester.element(find.byWidget(page)),
    ).read(snippetsProvider.notifier);
    for (var i = 0; i < 30; i++) {
      await notifier.add('Item ${i.toString().padLeft(2, '0')}', 'body $i');
    }
    await tester.pumpAndSettle();

    for (var i = 0; i < 20; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }

    final cursorRow = find.byWidgetPredicate(
      (w) => w is WpListTileSurface && w.isFocused,
    );
    expect(
      cursorRow,
      findsOneWidget,
      reason:
          'a cursor 20 rows down is outside the viewport and its cache '
          'extent — if it is not built at all, it was never scrolled to',
    );

    final row = tester.getRect(cursorRow);
    final viewport = tester.getRect(find.byType(ListView));
    expect(
      row.top >= viewport.top - 0.5 && row.bottom <= viewport.bottom + 0.5,
      isTrue,
      reason: 'the cursor row sits inside the viewport, not past its edge',
    );
  });
}
