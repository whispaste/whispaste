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
/// ## Height stays a strict equality
///
/// Height never left [_shape] and this rewrite doesn't loosen it. History is
/// the one area whose field carries a `suffix` (the search-syntax help button)
/// that no other area has, so it is also the one area where a stray touch
/// target could push the box past the 48 dp icon-slot floor while every
/// sibling stays at it. The equality below is what keeps that from happening
/// silently — measured, at three window widths and both text scales.
///
/// The constraints each area hands *in* are pinned beside it, because the
/// component answers for its width and leaves height to its intrinsic 48 dp.
/// That is only safe while every call site keeps the vertical loose; a bounded
/// height would stretch the box into whatever slot it was given. The equality
/// is the symptom, `hasBoundedHeight` is the cause — both are asserted, so a
/// failure says which of the two happened.
///
/// ## Width is deliberately *not* one of the equalities
///
/// This file briefly pinned width too, back when the component capped itself
/// at 560 dp so that History and Settings (no toolbar neighbour) couldn't read
/// as roomier than Notes and Replacements/Snippets (an Add button subtracted
/// from the same row). The maintainer asked for the opposite rule, for every
/// search field in the app: take the room the row actually has — the whole
/// content column where nothing sits to the right, up to the neighbour where
/// something does — and stay consistent on every *other* axis while doing it.
/// The cap is gone, and with it the idea that width is a property of the
/// component.
///
/// So width gets the opposite treatment from every other axis here. The
/// equality assertions run over [_shape] — height, offsets, glyph slot and
/// text insets — while width is asserted per area against *the room that area
/// actually has*:
///
/// * No toolbar neighbour (Settings): the box spans from its left inset to
///   the mirror-image right inset, i.e. the whole content column. Asserted
///   against the measured surface rather than against a padding token, so it
///   holds for `WpPageShell`'s header slot and a hand-rolled `Padding` bar
///   alike.
/// * A toolbar neighbour (Notes' "new note", Replacements/Snippets' "Add",
///   History's "new recording"): the box runs up to exactly `WpSpacing.sm`
///   short of that button. Not "narrower than X" — how much the button takes
///   is a function of its label, which any wording change moves. What must
///   hold is that nothing *but* the button stops the field.
///
/// Both hold at every window size, which is the point: three sizes are probed
/// (the 800 dp minimum, the 1100 dp default, and a roomy 1800 dp) and a
/// dedicated test pins that every dp the window gains reaches the field
/// instead of pooling beside it — the direct proof that the old cap is gone.
///
/// ## And what hangs under the field
///
/// History's suggestion panel and Settings' suggestion dropdown used to repeat
/// the field's `maxWidth` so they'd end where it ends.
/// With the cap gone they answer to their row instead, which is asserted here
/// directly — measured edge against measured edge, at the same three window
/// widths — rather than through a shared constant:
///
/// * Settings has no button in its row, so field and row end together and the
///   dropdown ends there too.
/// * History has one, and its panel spans the whole bar: it starts at the
///   field's left edge and ends flush with the button's right edge. The
///   alternative — nesting them in the field's own `Expanded` — aligns them
///   with the field but puts the suggestion panel's `AnimatedSize` inside a
///   flex child, where it is laid out twice in a frame and restarts its
///   animation from inside its own `performLayout`. That is a hard Flutter
///   assert, and the store screenshot goldens catch it.
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
import 'package:whispaste/widgets/wp_discoverability_hint.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// Everything about a rendered search field that "how padded does it look"
/// actually depends on. Width is in here to be *reported* — the per-area width
/// assertions read it — but it is excluded from the cross-area equality by
/// [_shape]; see the library docs.
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

/// The same record minus width: the axes that must be identical in every area.
typedef _FieldShape = ({
  double boxHeight,
  double boxLeft,
  double boxTop,
  double glyphLeftInset,
  double textLeftInset,
  double textTopInset,
  double textBottomInset,
});

_FieldShape _shape(_FieldGeometry g) => (
  boxHeight: g.boxHeight,
  boxLeft: g.boxLeft,
  boxTop: g.boxTop,
  glyphLeftInset: g.glyphLeftInset,
  textLeftInset: g.textLeftInset,
  textTopInset: g.textTopInset,
  textBottomInset: g.textBottomInset,
);

Rect _rect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The field's painted box — the [AnimatedContainer] that carries fill and
/// border, i.e. exactly what the maintainer sees an edge of.
Finder _fieldBox() => find
    .descendant(
      of: find.byType(WpSearchField),
      matching: find.byType(AnimatedContainer),
    )
    .first;

/// A [WpButton]'s *painted* box.
///
/// Not the widget's own rect: [MaterialTapTargetSize.padded] reports 48 dp
/// around a box it paints at 40, so measuring the widget would have this test
/// pass on a tree where the button visibly falls 8 dp short of the field. The
/// `Material` the button style paints into is the contour someone actually
/// sees an edge of, which is what has to line up.
Finder _buttonBox(Finder button) =>
    find.descendant(of: button, matching: find.byType(Material)).first;

_FieldGeometry _measure(WidgetTester tester) {
  final box = _rect(tester, _fieldBox());
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
  searchMatches: (_, _) => true,
  searchHint: 'Search',
  searchFieldLabel: 'Search items',
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

Widget _notes(TextEditingController controller, FocusNode focus) =>
    NotesSearchBar(
      currentFilter: NotesFilter.active,
      onFilterChanged: (_) {},
      isDark: true,
      searchController: controller,
      searchFocusNode: focus,
      onSearchChanged: () {},
      resultCount: 0,
      showResultCount: false,
      onCreate: () {},
    );

Widget _history(TextEditingController controller) => HistorySearchFilterBar(
  controller: controller,
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
);

/// Renders all four call sites one after another at [scale] and returns what
/// each one measured, keyed by area.
///
/// `neighbourGap` is the distance from the field's right edge to the toolbar
/// button beside it, for the two areas that have one — the assertion that a
/// narrower field is narrow *because* its neighbour needed the room, rather
/// than idly sized. `surfaceWidth` is the rendered width of the whole probe
/// surface, which is what the two neighbourless areas are measured against.
Future<
  ({
    Map<String, _FieldGeometry> geometry,
    Map<String, double> neighbourGap,
    Map<String, double> neighbourHeight,
    Map<String, BoxConstraints> incoming,
    double surfaceWidth,
  })
>
_measureAllAreas(WidgetTester tester, double scale) async {
  final measured = <String, _FieldGeometry>{};
  final gaps = <String, double>{};
  final neighbourHeights = <String, double>{};
  final incoming = <String, BoxConstraints>{};
  var surfaceWidth = 0.0;

  Future<void> probe(String area, Widget Function() build) async {
    await tester.pumpWidget(makeTestable(_scaled(build(), scale)));
    await tester.pump();
    measured[area] = _measure(tester);
    incoming[area] = tester
        .renderObject<RenderBox>(find.byType(WpSearchField))
        .constraints;
    surfaceWidth = _rect(tester, find.byType(MaterialApp)).width;
    final button = find.byType(WpButton);
    if (button.evaluate().isNotEmpty) {
      gaps[area] =
          _rect(tester, button.first).left - _rect(tester, _fieldBox()).right;
      neighbourHeights[area] = _rect(tester, _buttonBox(button.first)).height;
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
      child: _notes(notesController, notesFocus),
    ),
  );

  final historyController = TextEditingController();
  addTearDown(historyController.dispose);
  await probe(
    'history',
    () => Align(
      alignment: Alignment.topCenter,
      child: _history(historyController),
    ),
  );

  return (
    geometry: measured,
    neighbourGap: gaps,
    neighbourHeight: neighbourHeights,
    incoming: incoming,
    surfaceWidth: surfaceWidth,
  );
}

/// Layout width the app's content column has at a given window width: the
/// window minus the fixed sidebar. The bars bring their own `xl` side padding.
double _contentWidth(double windowWidth) => windowWidth - WpLayout.sidebarWidth;

/// The 800 dp minimum window, the 1100 dp default, and a roomy one.
const _windows = [800.0, 1100.0, 1800.0];

/// Nothing shares their toolbar row, so the whole content column is theirs.
const _neighbourless = ['settings'];

/// A primary button sits at the end of their row — "new note" on Notes, "Add"
/// on Replacements/Snippets, "new recording" on History.
const _withNeighbour = ['notes', 'replacements/snippets', 'history'];

void main() {
  for (final scale in const [1.0, 1.5]) {
    final at = scale == 1.0 ? 'normal text size' : 'accessibility text size';

    testWidgets('search field renders identically in all four areas at $at', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final window in _windows) {
        await tester.binding.setSurfaceSize(Size(_contentWidth(window), 700));

        final probed = await _measureAllAreas(tester, scale);
        final measured = probed.geometry;
        final reference = _shape(measured['settings']!);

        for (final entry in probed.incoming.entries) {
          // The component sizes itself horizontally and leaves height to its
          // intrinsic 48 dp — which only holds while no call site hands it a
          // bounded height. If one ever does, the box stretches into that
          // slot and the equality below is the symptom; this is the cause,
          // named. (`WpSearchField` re-derives nothing from this — see the
          // build-method comment.)
          expect(
            entry.value.hasBoundedHeight,
            isFalse,
            reason:
                '"${entry.key}" hands the search field a bounded height '
                '(${entry.value}) at $at in a ${window.toInt()} dp window. '
                'The field has no heightFactor, so it will stretch to fill it '
                'instead of keeping the height every other area has',
          );
        }

        for (final entry in measured.entries) {
          expect(
            _shape(entry.value),
            reference,
            reason:
                'The search field must look the same in every area — the '
                'sidebar entry the user clicked may change what sits *beside* '
                'the field, never the field itself. "${entry.key}" drifted '
                'from "settings" at $at in a ${window.toInt()} dp window.\n'
                '  settings:      $reference\n'
                '  ${entry.key}: ${_shape(entry.value)}',
          );
        }
      }
    });

    testWidgets('every field takes exactly the room its own row has, at $at', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final window in _windows) {
        await tester.binding.setSurfaceSize(Size(_contentWidth(window), 700));

        final probed = await _measureAllAreas(tester, scale);
        final w = window.toInt();

        for (final area in _neighbourless) {
          final g = probed.geometry[area]!;
          expect(
            probed.surfaceWidth - (g.boxLeft + g.boxWidth),
            closeTo(g.boxLeft, 0.01),
            reason:
                '"$area" has nothing to the right of its field, so the field '
                'must run to the mirror image of its own left inset — i.e. '
                'the whole content column. It stopped '
                '${(probed.surfaceWidth - (g.boxLeft + g.boxWidth)).toStringAsFixed(1)} dp '
                'short instead of ${g.boxLeft.toStringAsFixed(1)} dp, at $at '
                'in a $w dp window',
          );
        }

        for (final area in _withNeighbour) {
          expect(
            probed.neighbourGap[area],
            closeTo(WpSpacing.sm, 0.01),
            reason:
                '"$area" shares its row with a toolbar button, so the field '
                'must grow until exactly one WpSpacing.sm gap is left before '
                'that button — no more (dead space), no less (a collision). '
                'At $at in a $w dp window',
          );
        }
      }
    });

    testWidgets('the button beside the field is as tall as the field, at $at', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final window in _windows) {
        await tester.binding.setSurfaceSize(Size(_contentWidth(window), 700));

        final probed = await _measureAllAreas(tester, scale);
        final w = window.toInt();

        for (final area in _withNeighbour) {
          final field = probed.geometry[area]!.boxHeight;
          final button = probed.neighbourHeight[area]!;

          // One dp of tolerance, and only above 1.0x: the field's height
          // comes from its text plus its own vertical padding and lands on 49
          // at 1.5x, while the button's comes from the 48 dp floor its
          // padding has not yet outgrown. Half a dp of type metrics is not
          // what this test is about; eight dp of "the button is a different
          // size" is.
          expect(
            button,
            closeTo(field, scale == 1.0 ? 0.01 : 1.0),
            reason:
                'On "$area" the search field and the button beside it are one '
                'row, so they must read as one control strip: a shorter '
                'button centres itself in the leftover height and looks '
                'undersized rather than deliberate. The field paints '
                '${field.toStringAsFixed(1)} dp, the button '
                '${button.toStringAsFixed(1)} dp, at $at in a $w dp window. '
                'These rows are only the cheapest place to catch it — what '
                'holds them equal is app-wide: WpSearchField, '
                'WpTextFieldVariant.form, WpDropdownSize.standard and '
                'WpButtonSize.standard are all WpLayout.minTouchTarget',
          );
        }
      }
    });
  }

  testWidgets('every dp the window gains reaches the field, in every area', (
    tester,
  ) async {
    // The direct proof that the field no longer caps itself: between the
    // default window and a roomy one, all four fields grow by the full 700 dp
    // the window grew by. A cap of any size — or a re-introduced "preferred
    // width" — shows up here as a growth of less than that.
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(Size(_contentWidth(1100), 700));
    final narrow = (await _measureAllAreas(tester, 1.0)).geometry;
    await tester.binding.setSurfaceSize(Size(_contentWidth(1800), 700));
    final wide = (await _measureAllAreas(tester, 1.0)).geometry;

    for (final area in narrow.keys) {
      expect(
        wide[area]!.boxWidth - narrow[area]!.boxWidth,
        closeTo(700, 0.01),
        reason:
            '"$area" kept ${(700 - (wide[area]!.boxWidth - narrow[area]!.boxWidth)).toStringAsFixed(1)} dp '
            'of the 700 dp the window gained out of the field — the field is '
            'capped or preferred-width again instead of answering to the '
            'window',
      );
    }
  });

  testWidgets('the whole search bar is the same height on History as on Notes', (
    tester,
  ) async {
    // The field box is only half of what "the search" means to someone
    // looking at the page: the bar around it — same `xl/sm` padding, same two
    // stacked rows (search, then filter chips) — is what the eye measures.
    // History's was 132 dp against Notes' 128 dp because it separated the two
    // rows with `sm` where Notes uses `xs`; that 4 dp is one half of what this
    // pins. The other half was a one-time operator hint that stood in the bar
    // until someone dismissed it, 21 dp of it — the equality below needed a
    // "pretend it is dismissed" fixture to hold at all. The hint has since
    // moved into the field's help popover, so the equality is now
    // unconditional: no fixture, true from the very first frame a new user
    // sees.
    await tester.binding.setSurfaceSize(Size(_contentWidth(1100), 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final notesController = TextEditingController();
    final notesFocus = FocusNode();
    addTearDown(notesController.dispose);
    addTearDown(notesFocus.dispose);
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.topCenter,
          child: _notes(notesController, notesFocus),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final notesBar = _rect(tester, find.byType(NotesSearchBar)).height;

    final historyController = TextEditingController();
    addTearDown(historyController.dispose);
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.topCenter,
          child: _history(historyController),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(WpDiscoverabilityHint),
      findsNothing,
      reason:
          'the search bar carries no discoverability line any more — the '
          'operator help lives in the field\'s info popover, which is what '
          'makes the height equality below unconditional',
    );
    final historyBar = _rect(
      tester,
      find.byType(HistorySearchFilterBar),
    ).height;

    expect(
      historyBar,
      closeTo(notesBar, 0.01),
      reason:
          'History\'s search bar is $historyBar dp against Notes\' $notesBar dp. '
          'Both stack a search row and a filter-chip row inside the same '
          'padding, so anything but an equal height is drift — the search '
          'area must not change size when the sidebar entry changes',
    );
  });

  testWidgets('what hangs under the field ends where the field ends', (
    tester,
  ) async {
    // A suggestion panel belongs to the *field*, not to the content column.
    // This used to be expressed by repeating the field's own max width at each
    // call site; with the cap gone it is asserted directly, edge against edge,
    // so no shared constant has to stay in sync.
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final window in _windows) {
      await tester.binding.setSurfaceSize(Size(_contentWidth(window), 700));
      final w = window.toInt();

      // ── History: the suggestion panel ───────────────────────────────────
      final historyController = TextEditingController();
      addTearDown(historyController.dispose);
      await tester.pumpWidget(
        makeTestable(
          Align(
            alignment: Alignment.topCenter,
            child: _history(historyController),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // History is the one area whose search row has a button in it, so its
      // panel answers to the *row*: it starts at the field's left edge and
      // ends flush with the button's right edge, spanning the whole bar.
      // (Nesting it inside the field's `Expanded` to align it with the field
      // alone is what the production comment there rules out: it puts the
      // panel's AnimatedSize inside a flex child, where it re-lays out itself
      // mid-layout.) Asserted against the button's measured edge, so a panel
      // that stops short *or* overflows the bar both turn this red.
      final historyRowEnd = _rect(tester, find.byType(WpButton).first).right;

      // `lang:` opens the panel without needing a database.
      await tester.enterText(
        find.descendant(
          of: find.byType(WpSearchField),
          matching: find.byType(EditableText),
        ),
        'lang:',
      );
      await tester.pumpAndSettle();

      var box = _rect(tester, _fieldBox());
      final historyPanel = _rect(
        tester,
        find
            .descendant(
              of: find.byType(AnimatedSize),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        historyPanel.right,
        closeTo(historyRowEnd, 0.01),
        reason:
            "History's suggestion panel must reach the end of the search bar "
            'in a $w dp window — its `minWidth: double.infinity` has to be '
            "clamped to the bar's width, not to something narrower",
      );
      expect(historyPanel.left, closeTo(box.left, 0.01));

      // ── Settings: the suggestion dropdown ────────────────────────────────
      await tester.pumpWidget(makeTestable(_settings()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(WpSearchField),
          matching: find.byType(EditableText),
        ),
        'a',
      );
      await tester.pumpAndSettle();

      box = _rect(tester, _fieldBox());
      final settingsPanel = _rect(
        tester,
        find
            .descendant(
              of: find.byType(AnimatedSize),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        settingsPanel.right,
        closeTo(box.right, 0.01),
        reason:
            "Settings' suggestion dropdown must end where the field ends in "
            'a $w dp window',
      );
      expect(settingsPanel.left, closeTo(box.left, 0.01));
    }
  });

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

  testWidgets(
    'every in-window search field carries an explicit semanticsLabel',
    (tester) async {
      // hintText alone is not enough — see WpSearchField's library docs: an
      // InputDecoration hint publishes as a Semantics *hint*, not a *label*,
      // so a screen reader needs semanticsLabel to announce the field at all
      // (the same class of bug this component already fixed once for the
      // clear button's IconButton tooltip). The snippet picker isn't probed
      // here — it lives in a secondary Flutter engine this harness can't
      // mount — but its call site sets the same parameter.
      Future<void> expectLabelled(String area, Widget Function() build) async {
        await tester.pumpWidget(makeTestable(build()));
        await tester.pump();
        final field = tester.widget<WpSearchField>(find.byType(WpSearchField));
        expect(
          field.semanticsLabel,
          isNotNull,
          reason: '"$area" search field has no semanticsLabel',
        );
        expect(field.semanticsLabel, isNotEmpty);
      }

      await expectLabelled('settings', _settings);
      await expectLabelled('replacements/snippets', _searchableList);

      final notesController = TextEditingController();
      final notesFocus = FocusNode();
      addTearDown(notesController.dispose);
      addTearDown(notesFocus.dispose);
      await expectLabelled('notes', () => _notes(notesController, notesFocus));

      final historyController = TextEditingController();
      addTearDown(historyController.dispose);
      await expectLabelled('history', () => _history(historyController));
    },
  );
}
