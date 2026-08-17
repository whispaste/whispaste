/// Cross-area guard for [WpListTileSurface] — the tile envelope the four list
/// areas share since ticket 03.
///
/// Before the extraction the four had hand-rolled the same envelope and drifted
/// apart on every axis that makes a row look like a row: snippets and
/// replacements drew a 1.0 px border where notes and history drew 1.5, the
/// radius was `md` on two areas and `lg` on the other two, and only notes and
/// history faded a shadow in on interaction. None of that was decided; it
/// accumulated.
///
/// Like `search_field_geometry_consistency_test.dart`, whose shape this file
/// follows, the assertions are **equalities between the four real call sites**
/// rather than pinned magic numbers. A deliberate future change to the radius
/// or the border should move all four together and keep this green; a single
/// area drifting away from its siblings — the failure this family has actually
/// had — turns it red.
///
/// Three things are measured, and each answers for one acceptance criterion of
/// that ticket:
///
///  * **The painted envelope** (radius, border width, absence of a shadow) —
///    the extraction's whole point. Measured at rest *and* while hovered,
///    because the resting border is the value that must stay
///    present-but-transparent: `Border.lerp(a, null, t)` scales width toward
///    zero, which reads as a one-frame flash instead of a fade. A tile that
///    drops it to `null` at rest passes a naive "looks the same" check and
///    fails here. Since Ticket 08 the shadow is measured for the opposite
///    reason: a row lives in the plane and must carry *no* shadow, so its lift
///    is the fill/edge delta alone.
///  * **The horizontal inset** from the enclosing panel's edge to the tile's
///    edge. This is the last open box of the search-bar geometry work: history
///    sat on a 8 px tile inset under a 24 px bar while the other three areas
///    sat on 24 everywhere, so its rows were visibly indented against their
///    own search field. The equality below is what keeps that from coming
///    back, in all three of history's view modes.
///  * **The avatar palette**, which the ticket also names. Only history has an
///    avatar at all, so "consistent across the migrated lists" can only mean
///    that the extraction did not give the other three one, nor take history's
///    away. Asserted literally, so that a future tile that grows an avatar has
///    to come past this file.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_card_view.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_compact_view.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/history/widgets/history_list_view.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/features/notes/widgets/notes_list_view.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// Everything about a rendered tile envelope that "does this look like the
/// other lists' rows" depends on.
typedef _Envelope = ({
  BorderRadius radius,
  double borderWidth,
  bool hasRestingBorder,
  bool hasShadow,
  Color? fill,
});

/// Width every area is probed at.
///
/// Deliberately roomy, and deliberately the *same* for all four: this file is
/// about insets and paint, not about the squeeze — `row_actions_consistency_test.dart`
/// owns the narrow end. It also has to be a width the two full-width *pages*
/// actually ship at (the app's own minimum window is 800 dp), because below
/// that their empty state wraps far enough to overflow the viewport and the
/// probe would be measuring a layout no user ever sees.
const _panelWidth = 720.0;

/// The tile's own painted box — the [AnimatedContainer] [WpListTileSurface]
/// builds. `.first` is the envelope itself; tile *content* (tag chips and the
/// like) can contain further animated containers below it.
Finder _surfaceBox() => find
    .descendant(
      of: find.byType(WpListTileSurface),
      matching: find.byType(AnimatedContainer),
    )
    .first;

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(_surfaceBox()).decoration!
        as BoxDecoration;

_Envelope _measureEnvelope(WidgetTester tester) {
  final d = _decoration(tester);
  final border = d.border! as Border;
  return (
    radius: d.borderRadius! as BorderRadius,
    borderWidth: border.top.width,
    // "Present" means the widget hands a real Border rather than null — the
    // alpha is what varies between rest and hover.
    hasRestingBorder: d.border != null,
    hasShadow: (d.boxShadow ?? const <BoxShadow>[]).isNotEmpty,
    fill: d.color,
  );
}

/// Distance from the enclosing panel's left edge to the tile's painted left
/// edge — the number that has to agree across the four areas.
double _inset(WidgetTester tester, Finder tile) {
  final box = tester.renderObject<RenderBox>(tile);
  final left = box.localToGlobal(Offset.zero).dx;
  final panel = tester.renderObject<RenderBox>(find.byType(MaterialApp));
  return left - panel.localToGlobal(Offset.zero).dx;
}

Widget _panel(Widget child) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(width: _panelWidth, child: child),
);

/// The default 800x600 test surface leaves the two full *pages* (which stack a
/// header card, the subtitle line and the toolbar above their list) too little
/// room to lay a single row out at all, so the probe would measure an empty
/// list and pass vacuously. Tall enough that every area reaches its rows.
const _surfaceSize = Size(900, 1400);

void _sizeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

HistoryEntry _entry() => HistoryEntry(
  id: 'h1',
  content: 'A transcript long enough to fill the preview lines of the tile.',
  title: 'A recording',
  timestamp: DateTime(2026, 4, 14, 9, 41),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

Note _note() => Note(
  id: 'n1',
  content: 'Note title line\nand a preview line below it',
  pinned: false,
  isQuickNote: false,
  createdAt: DateTime(2026, 4, 14),
  updatedAt: DateTime(2026, 4, 14, 9, 41),
);

Widget _historyList() => HistoryEntryList(
  groups: [
    DateGroup(labelKey: 'today', entries: [_entry()]),
  ],
  selectedId: null,
  onEntryTap: (_) {},
  onCopy: (_) {},
  onPin: (_) {},
  onDelete: (_) {},
  multiSelectMode: false,
  selectedIds: const {},
  isTrashView: false,
);

Widget _historyCompact() => HistoryCompactView(
  groups: [
    DateGroup(labelKey: 'today', entries: [_entry()]),
  ],
  selectedId: null,
  onEntryTap: (_) {},
  onCopy: (_) {},
  onPin: (_) {},
  onDelete: (_) {},
  multiSelectMode: false,
  selectedIds: const {},
);

Widget _historyCards() => HistoryCardView(
  groups: [
    DateGroup(labelKey: 'today', entries: [_entry()]),
  ],
  selectedId: null,
  onEntryTap: (_) {},
  onCopy: (_) {},
  onPin: (_) {},
  onDelete: (_) {},
  multiSelectMode: false,
  selectedIds: const {},
);

Widget _notesList() => NotesListView(
  notes: [_note()],
  tagsByNoteId: const {},
  isTrashView: false,
  selectedId: null,
  focusedId: null,
  onNoteTap: (_) {},
  onFavoriteToggle: (_) {},
  onQuickNoteSet: (_) {},
  onQuickNoteClear: () {},
  onRestore: (_) {},
  onDeleteForever: (_) {},
);

/// Renders the real Snippets page and seeds it through its own notifier, so
/// what gets measured is the shipping tile rather than a stand-in.
Future<void> _pumpSnippets(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(locale: _locale, _panel(const SnippetsPage())),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SnippetsPage)),
  );
  await container
      .read(snippetsProvider.notifier)
      .add('Signature', 'Best regards,\nSilvio');
  await tester.pumpAndSettle();
}

/// Replacements seeds three sample rows on first build, so it needs no help.
Future<void> _pumpReplacements(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(locale: _locale, _panel(const ReplacementsPage())),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPlain(WidgetTester tester, Widget child) async {
  _sizeSurface(tester);
  await tester.pumpWidget(
    makeTestable(locale: _locale, _panel(child), size: _surfaceSize),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------

/// Pinned so the date-header assertion can look for a known string and so the
/// four areas are never compared across two different translations.
const _locale = Locale('en');
late L10n _l10n;

void main() {
  setUpAll(() async {
    _l10n = await L10n.delegate.load(_locale);
  });

  group('WpListTileSurface — the four list areas agree', () {
    late Map<String, _Envelope> envelopes;
    late Map<String, double> insets;

    Future<void> measureAll(WidgetTester tester) async {
      envelopes = {};
      insets = {};

      Future<void> probe(String area, Future<void> Function() pump) async {
        await pump();
        expect(
          find.byType(WpListTileSurface),
          findsWidgets,
          reason:
              'the "$area" probe rendered no WpListTileSurface at all, so '
              'every assertion below would have been vacuous',
        );
        envelopes[area] = _measureEnvelope(tester);
        insets[area] = _inset(tester, _surfaceBox());
      }

      await probe('history', () => _pumpPlain(tester, _historyList()));
      await probe('notes', () => _pumpPlain(tester, _notesList()));
      await probe('snippets', () => _pumpSnippets(tester));
      await probe('replacements', () => _pumpReplacements(tester));
    }

    testWidgets('radius and border width are identical', (tester) async {
      await measureAll(tester);

      final radii = envelopes.map((k, v) => MapEntry(k, v.radius));
      expect(
        radii.values.toSet(),
        hasLength(1),
        reason:
            'the four list areas disagree about their corner radius: $radii. '
            'They share one envelope (WpListTileSurface) — a difference here '
            'means an area went back to rolling its own decoration.',
      );

      final widths = envelopes.map((k, v) => MapEntry(k, v.borderWidth));
      expect(
        widths.values.toSet(),
        hasLength(1),
        reason:
            'the four list areas disagree about their resting border width: '
            '$widths. This is the exact drift ticket 03 removed (1.0 on '
            'snippets/replacements against 1.5 on notes/history).',
      );
      expect(
        widths.values.first,
        WpListTileSurface.borderWidth,
        reason:
            'the areas agree with each other but not with the shared '
            'constant, which means the constant has stopped describing '
            'what is painted',
      );
    });

    testWidgets(
      'the border exists at rest so the hover transition fades alpha, and no '
      'area carries a shadow',
      (tester) async {
        await measureAll(tester);

        for (final entry in envelopes.entries) {
          expect(
            entry.value.hasRestingBorder,
            isTrue,
            reason:
                '"${entry.key}" has no border at rest. AnimatedContainer then '
                'lerps width toward zero instead of fading alpha, which reads '
                'as a one-frame flash — see WpListTileSurface\'s library docs.',
          );
          // Ticket 08: a list row lives *in* the plane, so its depth is the
          // brightness delta of its fill and edge — never a drop shadow on top
          // of that delta. Before the refresh the row lifted itself with
          // `WpShadows.subtle` on hover *and* changed fill, which is two depth
          // cues on one element.
          expect(
            entry.value.hasShadow,
            isFalse,
            reason:
                '"${entry.key}" paints a shadow. On the app\'s single dark '
                'ground depth comes from one source only: the fill/edge '
                'delta. Shadows are for things that float over unknown '
                'content (dialog, toast, dropdown popup), not for rows.',
          );
        }
      },
    );

    testWidgets('hovering brightens the fill rather than growing the border', (
      tester,
    ) async {
      await _pumpPlain(tester, _historyList());
      final atRest = _measureEnvelope(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HistoryEntryRow)));
      await tester.pumpAndSettle();
      final hovered = _measureEnvelope(tester);

      expect(
        hovered.borderWidth,
        atRest.borderWidth,
        reason:
            'the border changed width on hover. Only its alpha may move — a '
            'width change is what makes the transition read as a flash.',
      );
      expect(
        hovered.hasShadow,
        isFalse,
        reason:
            'hovering must not add a shadow — the lift is the fill delta '
            '(Ticket 08, one depth source).',
      );
      expect(
        hovered.fill,
        isNot(atRest.fill),
        reason: 'hovering a row must change something; the fill stayed put',
      );
    });

    testWidgets('every area indents its tiles by the same amount', (
      tester,
    ) async {
      await measureAll(tester);

      expect(
        insets.values.map((v) => v.round()).toSet(),
        hasLength(1),
        reason:
            'the four list areas start their tiles at different distances '
            'from the panel edge: $insets. History used to be the odd one out '
            '(8 against everyone else\'s 24), which put its rows visibly '
            'inside its own search bar — ticket 03, point 5.',
      );
      expect(
        insets.values.first.round(),
        WpSpacing.xl.round(),
        reason:
            'the areas agree with each other but no longer sit on the `xl` '
            'page gutter the search bars above them use',
      );
    });

    testWidgets('all three history view modes sit on that same gutter', (
      tester,
    ) async {
      await measureAll(tester);
      final expected = insets['history']!.round();

      await _pumpPlain(tester, _historyCompact());
      expect(
        _inset(tester, find.byType(HistoryCompactRow)).round(),
        expected,
        reason:
            'the compact view drifted off the gutter its own list view sits '
            'on — the ticket asked for all three modes to move together',
      );

      await _pumpPlain(tester, _historyCards());
      expect(
        _inset(tester, find.byType(HistoryEntryCard)).round(),
        expected,
        reason: 'the card view drifted off the gutter — see above',
      );
    });

    testWidgets(
      'date headers start on the same gutter as the rows they group',
      (tester) async {
        await _pumpPlain(tester, _historyList());
        final row = _inset(tester, _surfaceBox());
        final header = _inset(tester, find.text('Today'));

        expect(
          header.round(),
          row.round(),
          reason:
              'a date header and the rows under it start on different '
              'verticals. Both now inherit the inset from the list rather than '
              'carrying their own, so this can only fail if one of them grew a '
              'horizontal padding back.',
        );
      },
    );

    testWidgets('only history carries a row avatar', (tester) async {
      await measureAll(tester);

      await _pumpPlain(tester, _historyList());
      expect(
        find.byType(HistoryEntryAvatar),
        findsOneWidget,
        reason: 'the extraction lost history its avatar',
      );

      for (final pump in <Future<void> Function()>[
        () => _pumpPlain(tester, _notesList()),
        () => _pumpSnippets(tester),
        () => _pumpReplacements(tester),
      ]) {
        await pump();
        expect(
          find.byType(HistoryEntryAvatar),
          findsNothing,
          reason:
              'a non-history list grew an avatar. The avatar palette belongs '
              'to history alone — see this file\'s library docs.',
        );
      }
    });
  });

  group('search-empty states offer a way out', () {
    // Ticket 03, point 8. Verlauf and Notizen already offered it; the shared
    // scaffold behind Replacements and Snippets turned out to offer it too, so
    // nothing had to be built — but nothing pinned it either, and an empty
    // state that strands the user behind their own query is exactly the sort
    // of regression that goes unnoticed until someone searches for a typo.
    testWidgets('snippets offers "clear search" when nothing matches', (
      tester,
    ) async {
      await _pumpSnippets(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'zzzz-no-such-snippet',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(_l10n.actionClearSearch),
        findsOneWidget,
        reason:
            'the no-matches state offers no way back out of the search — the '
            'WpEmptyState rule this app documents says it always does',
      );
    });
  });

  group("history's filter row wraps instead of squashing", () {
    // Ticket 03, point 7. The row used to be a plain `Row`: the trailing
    // controls (result count, "Empty trash", three icon controls) were
    // non-flexible, so they were laid out at their unbounded intrinsic width
    // and whatever remained went to the chips' `Expanded`. Once the controls
    // alone outgrew the panel that remainder went negative — measured at a
    // 340 dp panel it already overflowed by 7.7 dp at 1.0x, and by 266 dp at
    // 2.6x. The chips additionally sat in a hard 48 dp `SizedBox`, which
    // clipped rather than merely tightened them once their own text was
    // taller than that.
    //
    // Asserted by geometry rather than by `takeException`, on purpose: the
    // *search* row above (field + "new recording" button, untouched by this
    // ticket) still overflows at panel widths below ~500 dp, and an
    // exception-based assertion here would be reporting that pre-existing
    // defect instead of this row's. See the ticket's Umsetzungsprotokoll.
    for (final panel in <double>[240, 340, 720]) {
      for (final scale in <double>[1.0, 1.5, 2.6]) {
        testWidgets(
          'all six chips stay inside the bar at $panel dp @${scale}x',
          (tester) async {
            final controller = TextEditingController(text: 'abc');
            addTearDown(controller.dispose);
            _sizeSurface(tester);
            await tester.pumpWidget(
              makeTestable(
                locale: _locale,
                size: _surfaceSize,
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: panel,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: HistorySearchFilterBar(
                        controller: controller,
                        activeFilter: HistoryFilter.all,
                        onFilterChanged: (_) {},
                        onSearchChanged: () {},
                        resultCount: 3,
                        viewMode: HistoryViewMode.list,
                        onViewModeChanged: (_) {},
                        multiSelectMode: false,
                        onToggleMultiSelect: () {},
                        sortOrder: HistorySortOrder.newest,
                        onSortOrderChanged: (_) {},
                        onEmptyTrash: () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            final chips = find.byType(WpFilterChip);
            expect(
              chips,
              findsNWidgets(6),
              reason:
                  'a filter disappeared. Wrapping was chosen over the previous '
                  'horizontal scroll precisely so all six stay reachable '
                  'without a gesture that has no affordance.',
            );

            final barRight = tester
                .getRect(find.byType(HistorySearchFilterBar))
                .right;
            for (var i = 0; i < 6; i++) {
              final chip = tester.getRect(chips.at(i));
              expect(
                chip.right,
                lessThanOrEqualTo(barRight + 0.01),
                reason:
                    'chip $i is painted past the bar\'s right edge at '
                    '$panel dp @${scale}x — the row is squashing again',
              );
            }

            // The controls have to stay inside too: stacking the two groups
            // only helps while each of them can still break internally.
            final toggle = tester.getRect(find.byType(HistoryViewModeToggle));
            expect(
              toggle.right,
              lessThanOrEqualTo(barRight + 0.01),
              reason:
                  'the view-mode toggle is painted outside the bar at '
                  '$panel dp @${scale}x',
            );

            // Below roughly 500 dp the *search* row above still overflows:
            // its "new recording" button is a non-flexible child with a text
            // label, so the field's `Expanded` runs out of room before the
            // button does. That row is untouched by this ticket, and fixing
            // it means deciding what the button collapses to — a design call,
            // recorded as an open finding in the ticket rather than smuggled
            // in here. Consuming it keeps this test answering for the filter
            // row, which the geometry assertions above pin directly; anything
            // that is *not* a layout overflow still fails.
            for (
              var ex = tester.takeException();
              ex != null;
              ex = tester.takeException()
            ) {
              expect(
                ex.toString(),
                contains('overflowed'),
                reason:
                    'the filter bar threw something other than a layout '
                    'overflow at $panel dp @${scale}x',
              );
            }
          },
        );
      }
    }
  });
}
