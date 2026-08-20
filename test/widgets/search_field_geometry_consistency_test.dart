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
/// ## Height stays a strict equality — in two states, on a desktop platform
///
/// Height never left [_shape] and this rewrite doesn't loosen it. History is
/// the one area whose field carries a `suffix` (the search-syntax help button)
/// that no other area has, so it is also the one area whose box can be a
/// different height from every sibling's. The equality below is what keeps
/// that from happening silently — measured, at three window widths and both
/// text scales.
///
/// Two things had to change before it could actually catch that, both learned
/// from a bug this file was already supposed to own. History rendered 48 dp
/// against Notes' and Settings' 40 dp in the running app while every
/// assertion here stayed green:
///
/// * **The platform is named.** `flutter_test` forces
///   `defaultTargetPlatform` to Android whenever `FLUTTER_TEST` is set
///   (`foundation/_platform_io.dart`), whatever host the suite runs on. The
///   icon-slot floor `WpSearchField` used to inherit was
///   `visualDensity.effectiveConstraints(…)` — 48 dp under Android's
///   `adaptivePlatformDensity`, 40 dp under the `VisualDensity.compact` every
///   desktop resolves to. So the harness was measuring a platform this app
///   does not ship on, and reading the drift as absent. Every assertion that
///   measures the *field's own* height now carries [_desktop], which is also
///   the only way this file can go red on the bug it exists to prevent.
///   Deliberately not among them is the History-vs-Notes *bar* comparison
///   further down: both bars put a 48 dp button in the search row, so the row
///   is `max(field, 48)` and a 40 dp field never reaches the bar's height —
///   measured, that one stays green on all three desktops even with the
///   component's icon-slot constraints taken back out. It answers for the
///   bar's padding and row count, not for the field.
/// * **Both states are measured.** Every assertion here used to run on an
///   empty, unfocused field — the one state in which the clear button does not
///   exist. The suffix slot is exactly where the drift lived: the clear
///   `IconButton` carries a 48 dp `minimumSize` that the ambient density does
///   not shrink, so it grew the slot past the density-shrunk minimum and the
///   box jumped 8 dp on the first keystroke and back on clear — on every area
///   *except* History, whose `suffix` is always populated and which was
///   therefore just permanently 8 dp taller. [_measureAllAreas] now probes
///   each area twice, empty and with text, and the equality spans both.
///
/// The fix is `prefixIconConstraints`/`suffixIconConstraints` on the
/// component; these assertions are what keep an inherited default from
/// creeping back in.
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

Finder _editable() => find.descendant(
  of: find.byType(WpSearchField),
  matching: find.byType(EditableText),
);

/// The clear button's glyph — present only while the field has text, which is
/// what makes the "with text" half of the probe non-vacuous.
Finder _clearButton() => find.descendant(
  of: find.byType(WpSearchField),
  matching: find.byIcon(LucideIcons.x),
);

_FieldGeometry _measure(WidgetTester tester) {
  final box = _rect(tester, _fieldBox());
  final text = _rect(tester, _editable());
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

/// The platforms WhisPaste actually ships on — and the reason the tests that
/// measure the field's *own* height carry it. See the library docs for the one
/// height assertion that deliberately doesn't.
///
/// `flutter_test` reports `TargetPlatform.android`, where
/// `ThemeData.visualDensity`'s `adaptivePlatformDensity` default resolves to
/// `VisualDensity.standard`. Every desktop resolves to `VisualDensity.compact`
/// instead, which shrinks Material's own 48 dp icon-slot minimum to 40 — so a
/// field sized off that minimum measures 8 dp differently here than in the app
/// the maintainer is looking at. That is precisely how a `WpSearchField`
/// height drift lived through this file once; see its library docs.
///
/// All three are run rather than macOS alone: `CLAUDE.md` holds the three
/// desktops equal, and this is the cheapest place to prove the field agrees
/// with that.
final _desktop = TargetPlatformVariant.desktop();

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
  searchMatches: (_, __) => true,
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
  onItemActivate: (_) {},
  itemBuilder: (_, _, _) => const SizedBox(height: 40),
);

Widget _notes(TextEditingController controller, FocusNode focus) =>
    NotesSearchBar(
      currentFilter: NotesFilter.active,
      onFilterChanged: (_) {},
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
    Map<String, _FieldGeometry> geometryWithText,
    Map<String, double> neighbourGap,
    Map<String, double> neighbourHeight,
    Map<String, BoxConstraints> incoming,
    double surfaceWidth,
  })
>
_measureAllAreas(WidgetTester tester, double scale) async {
  final measured = <String, _FieldGeometry>{};
  final withText = <String, _FieldGeometry>{};
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

    // The same field once the user has typed into it. Everything above is the
    // *empty* field, which is the one state where the clear button — the
    // `IconButton` whose intrinsic size this component has to stop from
    // deciding the box's height — does not exist. See the library docs.
    //
    // The query is deliberately something no area treats specially: History
    // opens its suggestion panel on an operator like `lang:`, and a panel
    // below the field is not what is being measured here.
    await tester.enterText(_editable(), 'wp');
    await tester.pumpAndSettle();
    expect(
      _clearButton(),
      findsOneWidget,
      reason:
          'the "$area" probe typed into the field but no clear button '
          'appeared, so the state this half of the measurement exists for was '
          'never actually reached',
    );
    withText[area] = _measure(tester);
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
    geometryWithText: withText,
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

    testWidgets(
      'search field renders identically in all four areas at $at',
      (tester) async {
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

          // …and again with text in it, against the very same reference.
          // Typing must not move the field: the clear button appears *inside*
          // the box, and a box that grows with it shoves the filter-chip row
          // below it down on every first keystroke and back up on every clear.
          //
          // [_shape] is compared whole rather than some frame-only subset of
          // it. A narrower invariant looks defensible — the text region does
          // share its row with a clear button now — but it was measured, and
          // nothing in [_shape] moves: the text's *left* inset is set by the
          // prefix slot and `contentPadding`, which the suffix never touches,
          // and its vertical insets can only move if the height does, which is
          // the very thing being pinned. Only `boxWidth` legitimately differs
          // between areas, and that was never in [_shape] to begin with.
          for (final entry in probed.geometryWithText.entries) {
            expect(
              _shape(entry.value),
              reference,
              reason:
                  'The "${entry.key}" search field changed shape between empty '
                  'and typed-into, at $at in a ${window.toInt()} dp window. The '
                  'clear button is a taller intrinsic than the search glyph '
                  'beside it, so the icon slots have to state their own size — '
                  'otherwise the whole bar jumps the moment anyone types.\n'
                  '  empty (settings): $reference\n'
                  '  with text:        ${_shape(entry.value)}',
            );
          }
        }
      },
      variant: _desktop,
    );

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

    testWidgets(
      'the button beside the field is as tall as the field, at $at',
      (tester) async {
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
                  'WpTextFieldVariant.form, WpDropdown and '
                  'WpButtonSize.standard are all WpLayout.minTouchTarget',
            );
          }
        }
      },
      variant: _desktop,
    );
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

  testWidgets('the field rests on the touch target and grows out of it rather '
      'than clipping, as the text size rises', (tester) async {
    // The icon slots put a floor under the box and `contentPadding` is the
    // breathing room above that floor: while the line fits, the floor decides
    // the height; once it doesn't, the padding does and the box grows.
    //
    // This used to compare 1.0x against 1.5x and read the difference as proof
    // of the second half. That comparison was measuring the *drift*, not the
    // rule — the floor it started from was the density-shrunk 40 dp, so 1.5x
    // cleared it easily. With the floor honest at 48 the line only outgrows it
    // near 2.0x, so the scan below asserts the rule at every step instead of
    // pinning the one scale where the old bug happened to show.
    Future<_FieldGeometry> at(double scale) async {
      await tester.pumpWidget(makeTestable(_scaled(_settings(), scale)));
      await tester.pump();
      return _measure(tester);
    }

    const scales = [1.0, 1.3, 1.5, 1.8, 2.0];
    final measured = {for (final s in scales) s: await at(s)};

    expect(
      measured[1.0]!.boxHeight,
      WpLayout.minTouchTarget,
      reason:
          'at 1.0x the icon slots are the tallest thing in the box, so they — '
          'not contentPadding — set the height, and the field rests on exactly '
          'the touch target every other control in a toolbar row rests on',
    );

    for (final scale in scales) {
      final g = measured[scale]!;
      expect(
        g.boxHeight,
        greaterThanOrEqualTo(WpLayout.minTouchTarget),
        reason:
            'the field dropped below the touch target at ${scale}x — the icon '
            'slots are a floor and nothing may pull the box under it',
      );
      // The line must live *inside* the box at every size. Clipping is the
      // failure this whole scan is really about; growth is only how the box
      // avoids it.
      expect(
        g.textTopInset,
        greaterThanOrEqualTo(0),
        reason: 'the text line is clipped at the top at ${scale}x',
      );
      expect(
        g.textBottomInset,
        greaterThanOrEqualTo(0),
        reason: 'the text line is clipped at the bottom at ${scale}x',
      );
    }

    // The slack above the line shrinks monotonically as the line grows: the
    // text eats the room the icon slot was leaving it, rather than being
    // pushed out of the box.
    for (var i = 1; i < scales.length; i++) {
      expect(
        measured[scales[i]]!.textTopInset,
        lessThanOrEqualTo(measured[scales[i - 1]]!.textTopInset),
        reason:
            'the slack above the line grew between ${scales[i - 1]}x and '
            '${scales[i]}x instead of being eaten by the taller line',
      );
    }

    expect(
      measured[2.0]!.boxHeight,
      greaterThan(WpLayout.minTouchTarget),
      reason:
          'by 2.0x the line has outgrown the icon slot, so contentPadding '
          'starts deciding and the box has to grow with it instead of '
          'clipping. A field still pinned to the floor here is one that will '
          'clip at the next size up',
    );
  }, variant: _desktop);

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
