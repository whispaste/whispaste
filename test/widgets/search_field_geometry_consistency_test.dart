/// Cross-area geometry guard for [WpSearchField].
///
/// `ce228ca7` dropped the `raised` variant so all four list toolbars and
/// Settings would share one look. The maintainer still read the Settings field
/// as "noticeably more padded inside" than the Replacements one afterwards, so
/// this test settles the question by measurement rather than by reading
/// `contentPadding` out of the component: it renders all four real call sites
/// at the same window size and compares the *rendered* box, the glyph slot and
/// the `EditableText`'s insets inside that box.
///
/// The assertions are **equalities between call sites**, not pinned magic
/// numbers. A deliberate future change to the field's padding should move all
/// four together and keep this test green; only a call site that drifts away
/// from its siblings — the failure this family has actually had, six times —
/// turns it red.
///
/// Both text scales are covered on purpose. The component's own comment says
/// its vertical padding "is the breathing room the field grows into once an
/// accessibility text size pushes the line past the 48 dp floor", i.e. the
/// padding only starts deciding anything above 1.0x. Two fields that agree at
/// 1.0x can therefore still diverge at 1.5x, which is the size the maintainer's
/// own UI checks run at.
///
/// ## Width
///
/// Width used to be the one axis excluded here, because it was set by whatever
/// shared the toolbar row. That was the remaining drift: History and Settings
/// have no neighbour and took the whole content column (980 dp at the default
/// 1100 dp window), Notes and Replacements/Snippets were ~200 dp narrower
/// because an Add button was subtracted from the same row — one control, two
/// readings of how padded it is. `WpSearchField.maxWidth` ends that, so width
/// is now pinned alongside everything else.
///
/// It is pinned at *two* window sizes on purpose, because the cap and the
/// neighbour trade places between them:
///
/// * At a roomy window every call site reaches the cap and the record —
///   width included — is identical everywhere.
/// * At the 800 dp minimum window the Add button leaves its row less than
///   560 dp, so Notes and Replacements/Snippets come out narrower. That is
///   the one sanctioned exception: a structural neighbour may take width
///   *from* the field, never give width *to* it. The second test pins that
///   direction, so a call site can still not drift back to "full row".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/features/notes/data/providers.dart';
import 'package:whispaste/features/notes/widgets/notes_search_bar.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/widgets/page_shell.dart';
import 'package:whispaste/widgets/searchable_list_page.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// Everything about a rendered search field that "how padded does it look"
/// actually depends on — width included, ever since the field caps itself
/// instead of taking whatever its row has left over.
typedef _FieldGeometry = ({
  double boxHeight,
  double boxWidth,
  double boxLeft,
  double boxTop,
  double glyphLeftInset,
  double textLeftInset,
  double textTopInset,
  double textBottomInset,
});

Rect _rect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

_FieldGeometry _measure(WidgetTester tester) {
  final box = _rect(
    tester,
    find
        .descendant(
          of: find.byType(WpSearchField),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  final text = _rect(
    tester,
    find.descendant(
      of: find.byType(WpSearchField),
      matching: find.byType(EditableText),
    ),
  );
  final glyph = _rect(
    tester,
    find.descendant(
      of: find.byType(WpSearchField),
      matching: find.byIcon(LucideIcons.search),
    ),
  );
  return (
    boxHeight: box.height,
    boxWidth: box.width,
    boxLeft: box.left,
    boxTop: box.top,
    glyphLeftInset: glyph.left - box.left,
    textLeftInset: text.left - box.left,
    textTopInset: text.top - box.top,
    textBottomInset: box.bottom - text.bottom,
  );
}

/// Applies [scale] on top of whatever [makeTestable] already provides.
Widget _scaled(Widget child, double scale) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

// ---------------------------------------------------------------------------
// The four real call sites
// ---------------------------------------------------------------------------

/// Settings — the field rides `WpPageShell`'s sticky header slot, which makes
/// it a *loosely* constrained child of a Column rather than an `Expanded` one.
/// That difference in constraint shape is the reason this is measured rather
/// than reasoned about.
Widget _settings() => const WpPageShell(
  scrollable: false,
  header: SettingsSearchField(),
  child: SizedBox.shrink(),
);

/// Replacements/Snippets — both run through this shared scaffold, so one probe
/// covers the pair.
Widget _searchableList() => WpSearchableListPage<String>(
  asyncAll: const AsyncValue.data(['item']),
  searchMatches: (item, query) => true,
  searchHint: 'Search',
  addLabel: 'Add',
  onAdd: () {},
  onRetry: () {},
  emptyIcon: LucideIcons.plus,
  emptyTitle: 'empty',
  emptyHint: 'empty',
  emptyActionLabel: 'add',
  noMatchesTitle: 'none',
  noMatchesHint: 'none',
  itemBuilder: (_, _, _) => const SizedBox(height: 40),
);

/// Renders all four call sites one after another at [scale] and returns what
/// each one measured, keyed by area.
///
/// `neighbourGap` is the distance from the field's right edge to the toolbar
/// button beside it, for the two areas that have one. It answers the question
/// a raw width can't: whether a field narrower than the cap is narrow
/// *because* its neighbour needed the room, or just sloppily sized.
Future<
  ({Map<String, _FieldGeometry> geometry, Map<String, double> neighbourGap})
>
_measureAllAreas(WidgetTester tester, double scale) async {
  final measured = <String, _FieldGeometry>{};
  final gaps = <String, double>{};

  Future<void> probe(String area, Widget Function() build) async {
    await tester.pumpWidget(makeTestable(_scaled(build(), scale)));
    await tester.pump();
    measured[area] = _measure(tester);
    final button = find.byType(WpButton);
    if (button.evaluate().isNotEmpty) {
      gaps[area] =
          _rect(tester, button.first).left -
          _rect(
            tester,
            find
                .descendant(
                  of: find.byType(WpSearchField),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          ).right;
    }
  }

  await probe('settings', _settings);
  await probe('replacements/snippets', _searchableList);

  final notesController = TextEditingController();
  final notesFocus = FocusNode();
  addTearDown(notesController.dispose);
  addTearDown(notesFocus.dispose);
  await probe(
    'notes',
    () => Align(
      alignment: Alignment.topCenter,
      child: NotesSearchBar(
        currentFilter: NotesFilter.active,
        onFilterChanged: (_) {},
        isDark: true,
        searchController: notesController,
        searchFocusNode: notesFocus,
        onSearchChanged: () {},
        resultCount: 0,
        showResultCount: false,
        onCreate: () {},
      ),
    ),
  );

  final historyController = TextEditingController();
  addTearDown(historyController.dispose);
  await probe(
    'history',
    () => Align(
      alignment: Alignment.topCenter,
      child: HistorySearchFilterBar(
        controller: historyController,
        activeFilter: HistoryFilter.all,
        isDark: true,
        onFilterChanged: (_) {},
        onSearchChanged: () {},
        resultCount: 0,
        viewMode: HistoryViewMode.list,
        onViewModeChanged: (_) {},
        multiSelectMode: false,
        onToggleMultiSelect: () {},
        sortOrder: HistorySortOrder.newest,
        onSortOrderChanged: (_) {},
      ),
    ),
  );

  return (geometry: measured, neighbourGap: gaps);
}

/// Layout width the app's content column has at a given window width: the
/// window minus the fixed sidebar. The bars bring their own `xl` side padding.
double _contentWidth(double windowWidth) => windowWidth - WpLayout.sidebarWidth;

void main() {
  for (final scale in const [1.0, 1.5]) {
    final at = scale == 1.0 ? 'normal text size' : 'accessibility text size';

    testWidgets('search field renders identically in all four areas at $at', (
      tester,
    ) async {
      // The default 1100 dp window: every row has more than
      // `WpSearchField.maxWidth` to give, so the cap — not the neighbour —
      // decides everywhere and width can be pinned like every other value.
      await tester.binding.setSurfaceSize(Size(_contentWidth(1100), 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final measured = (await _measureAllAreas(tester, scale)).geometry;

      final reference = measured['settings']!;
      for (final entry in measured.entries) {
        expect(
          entry.value,
          reference,
          reason:
              'The search field must look the same in every area — the '
              'sidebar entry the user clicked may change what sits *beside* '
              'the field, never the field itself. "${entry.key}" drifted from '
              '"settings" at $at.\n'
              '  settings:      $reference\n'
              '  ${entry.key}: ${entry.value}',
        );
      }

      expect(
        reference.boxWidth,
        WpSearchField.maxWidth,
        reason:
            'the one width is WpSearchField.maxWidth itself — if this is the '
            'full content column again, the cap stopped being applied',
      );
    });

    testWidgets('at the 800 dp minimum window a toolbar neighbour may take '
        'width from the field, never give width to it, at $at', (tester) async {
      // The narrowest window the app can be resized to. Notes and
      // Replacements/Snippets share their row with an Add button that leaves
      // less than the cap here, so they come out narrower — the one sanctioned
      // width exception (see the library docs of WpSearchField).
      await tester.binding.setSurfaceSize(Size(_contentWidth(800), 550));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final probed = await _measureAllAreas(tester, scale);
      final measured = probed.geometry;

      for (final entry in measured.entries) {
        expect(
          entry.value.boxWidth,
          lessThanOrEqualTo(WpSearchField.maxWidth),
          reason:
              '"${entry.key}" is wider than the cap at $at — no area may go '
              'back to taking the whole row',
        );
      }
      for (final area in const ['settings', 'history']) {
        expect(
          measured[area]!.boxWidth,
          WpSearchField.maxWidth,
          reason:
              '"$area" has no toolbar neighbour, so nothing may keep it from '
              'reaching the cap even at the minimum window',
        );
      }
      for (final area in const ['notes', 'replacements/snippets']) {
        // Deliberately not `lessThan(maxWidth)`: how far under the cap these
        // land is a function of the Add button's label, which any wording
        // change moves. What must hold is *why* they are under it — the field
        // grew until it hit its neighbour's gap, so nothing but the button
        // kept it from the cap.
        expect(
          probed.neighbourGap[area],
          closeTo(WpSpacing.sm, 0.01),
          reason:
              '"$area" shares its row with an Add button. At the minimum '
              'window the field must run right up to that button, i.e. be '
              'stopped by the neighbour rather than be idly narrow',
        );
      }
    });
  }

  testWidgets('the field grows into its vertical padding above 1.0x, rather '
      'than staying pinned to the 48 dp icon-slot floor', (tester) async {
    Future<_FieldGeometry> at(double scale) async {
      await tester.pumpWidget(makeTestable(_scaled(_settings(), scale)));
      await tester.pump();
      return _measure(tester);
    }

    final normal = await at(1.0);
    final large = await at(1.5);

    expect(
      normal.boxHeight,
      48.0,
      reason:
          'at 1.0x the 48 dp prefix/suffix icon slot is the tallest thing in '
          'the box, so it — not contentPadding — sets the height',
    );
    expect(
      large.boxHeight,
      greaterThan(normal.boxHeight),
      reason:
          'once the text line outgrows the icon slot the vertical '
          'contentPadding starts deciding, and the box has to grow with it '
          'instead of clipping the line',
    );
    expect(
      large.textTopInset,
      lessThan(normal.textTopInset),
      reason:
          'the taller line eats into the slack the icon slot used to leave '
          'above it — the text must not be pushed out of the box instead',
    );
  });
}
