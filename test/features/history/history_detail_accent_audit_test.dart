/// The executable half of **The Two Accent, Two Jobs Rule** on the one screen
/// Ticket 32's re-critique counted by eye: the history detail view (finding
/// B6, "Violett-Inflation auf dem Verlaufs-Detailscreen", disposition (b) →
/// Ticket 13).
///
/// ## An audited set, not a threshold
///
/// Same idiom as the `Two accents, two jobs – token usage` group in
/// `wcag_contrast_test.dart`: the test does not assert "at most N accents". It
/// pumps the screen, collects **every element whose fill, edge or glyph
/// resolves to a generic-accent token**, labels each by the component it
/// belongs to, and compares the resulting tally against the set written out
/// below. A threshold would let a new accent surface slip in wherever an old
/// one had been removed; a named set makes every addition *and* every removal
/// a failure that has to be argued for in this file. That is the point — the
/// accent's job is "you can act on this", and each new place it appears is a
/// classification decision, not a colour choice.
///
/// ## What counts as an accent surface
///
/// A colour counts when its RGB equals one of the generic-accent tokens in
/// `colors.dart` (the whole tint ladder shares one RGB, so `.withValues(alpha:
/// …)` derivations are caught too) and its alpha is non-zero. Fully
/// transparent accent is excluded on purpose: `WpListTileSurface` gives every
/// resting panel row a `accent.withValues(alpha: 0)` border so the selection
/// stroke can fade in without a width jump (see that file's "Why the border is
/// never null"), and counting an invisible border would make the tally a
/// measure of the list's length.
///
/// Fills, edges *and* glyph colours are collected. The rule's own wording says
/// "fill or edge", but three of the elements Ticket 32 counted carry their
/// accent as an icon rather than as a plate; excluding glyphs would make the
/// audit blind to exactly the surfaces the finding was about.
///
/// One element per painted box: `Container` and `AnimatedContainer` both build
/// a `DecoratedBox`, so only the `DecoratedBox`/`ColoredBox`/`Material` level
/// is collected and a single visual box counts once.
///
/// ## How this set relates to Ticket 32's eight
///
/// B6 named eight elements that resolve to an accent token. Measured here,
/// against the shipped code rather than against a screenshot, the tally is
/// **thirteen**, and the deltas are all explainable:
///
///  * **"Transkript bearbeiten" is no longer among them.** At rest that
///    control is `surfaceMutedFill` + `textMuted` and only turns accent while
///    the transcript is actually being edited
///    (`history_detail_panel.dart`, `_TranscriptEditBar`). B6 measured a
///    screenshot; the resting screen this test pumps does not show it.
///  * **The active nav item is two boxes, not one** — the pill and the
///    indicator bar beside it. B6 counted the perceived element.
///  * **The active view-mode segment was missed by B6** (fill + glyph). It is
///    a genuine selected state on the same rung as the filter chip next to it
///    and stays.
///  * **The detail panel's tag chips *do* resolve to an accent token.** B6
///    excluded tag chips on the grounds that they run through
///    `categorySlotForTag` — true of the chips on the *list rows*
///    (`_EntryTagChip`), not of the chips inside `WpTagInput`, which are
///    `accentChipFill`. They are counted here and left alone: re-hueing a
///    shared input's chips is Ticket 32's B1/B8 work, not this ticket's.
///  * **Two decorative section glyphs were removed by this ticket** — the
///    tags icon and the notes sticky-note icon. Both labelled a section
///    without triggering anything, which is the same misuse Ticket 08 fixed
///    at the settings section heads (B3).
///
/// The category-hued surfaces B6 also counted — the avatar discs
/// (`WpCategorySlot`) and the list rows' tag chips (`categorySlotForTag`) —
/// are not accent tokens and therefore never enter this tally at all. They do
/// not need excluding by subtree; they simply do not match.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';

import '../../screenshots/screenshot_shell.dart';

/// The generic-accent tokens of `colors.dart`, reduced to their RGB triples.
///
/// Reduced rather than compared whole because the tint ladder is one hue at a
/// dozen alphas, and every component reaches for a different rung — plus
/// `accent.withValues(alpha: …)` at four call sites, which is the same colour
/// with an alpha the token list never names.
final _accentRgb = <int>{
  for (final c in <Color>[
    WpColors.accent,
    WpColors.accentHover,
    WpColors.accentSubtle,
    WpColors.accentChipFill,
    WpColors.accentChipFillHover,
    WpColors.accentMiniTagFill,
    WpColors.accentBorder30,
    WpColors.accentButtonFill,
    WpColors.accentActiveFill,
    WpColors.accentBadgeFill,
    WpColors.accentBorder20,
    WpColors.accentRowHover,
    WpColors.accentLocatorRing,
    WpColors.decorativeGlyphWash,
  ])
    c.toARGB32() & 0x00FFFFFF,
};

bool _isAccent(Color c) {
  final argb = c.toARGB32();
  if ((argb >> 24) & 0xFF == 0) return false; // painted nothing
  return _accentRgb.contains(argb & 0x00FFFFFF);
}

/// Widget runtime type → the label its accent surfaces are tallied under.
///
/// Looked up on the *nearest* matching ancestor, so a chip inside a tag input
/// is attributed to the chip rather than to the input.
const _anchors = <String, String>{
  '_NavItemWidget': 'app chrome — sidebar: the active nav item',
  '_NewRecordingButton': 'history toolbar — the primary "New recording" button',
  'WpFilterChip': 'history toolbar — the active filter chip',
  '_HistoryViewModeButton': 'history toolbar — the active view-mode segment',
  'HistoryEntryRow': 'history list — the selected row',
  '_TagChip': 'detail panel — a tag chip (one per tag on the entry)',
  '_AddTagTrigger': 'detail panel — the add-tag trigger',
  'VoiceNoteButton': 'detail panel — the voice-note microphone button',
  'HistoryNotesSection': 'detail panel — the add-note "+" button',
};

/// The set. Every entry is a decision; the numbers are surfaces, not
/// components, so adding a second accent plate inside a component that is
/// already listed still fails here.
const _auditedAccentSurfaces = <String, int>{
  // Chrome. The pill and the indicator bar beside it. Outside this ticket's
  // files, counted because B6 counted it and because it shares the screen.
  'app chrome — sidebar: the active nav item': 2,

  // The one loud action of the screen. Its fill *is* the accent.
  'history toolbar — the primary "New recording" button': 1,

  // Two selected states in the toolbar, both on the `accentActiveFill` rung:
  // which slice of the history is shown, and in which layout.
  'history toolbar — the active filter chip': 1,
  'history toolbar — the active view-mode segment': 2,

  // Which row the detail panel is showing — fill and stroke on one box.
  'history list — the selected row': 1,

  // The detail panel's two operable tag controls. The chip count follows the
  // fixture: `_seed` puts exactly one tag on the opened entry, and that chip
  // paints a fill plus a remove glyph.
  'detail panel — a tag chip (one per tag on the entry)': 2,
  'detail panel — the add-tag trigger': 2,

  // The two ways to attach a note, side by side on the section's own line.
  'detail panel — the voice-note microphone button': 1,
  'detail panel — the add-note "+" button': 1,
};

void main() {
  testWidgets('the history detail screen paints exactly the audited accents', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(_harness(db));
    await tester.pumpAndSettle();

    // Open the detail panel on the entry that carries the tag, so the tag
    // section is populated rather than empty.
    await tester.tap(find.text(_taggedEntryTitle).first);
    await tester.pumpAndSettle();

    final found = <String, int>{};
    for (final element in tester.allElements) {
      final paints = _paintedColors(element.widget).where(_isAccent);
      if (paints.isEmpty) continue;
      found.update(_label(element), (n) => n + 1, ifAbsent: () => 1);
    }

    expect(
      found,
      _auditedAccentSurfaces,
      reason:
          'The history detail screen paints a different set of accent '
          'surfaces than the audited one.\n'
          '  found:   $found\n'
          '  audited: $_auditedAccentSurfaces\n'
          'The accent means "you can act on this" and nothing else. A new '
          'entry here is a claim that a new element is operable and is the '
          'most important thing on the screen — decide that deliberately and '
          'write the reason next to the row, or reach for `textSecondary` / '
          '`textMuted` / the card material instead. A `UNCLASSIFIED` label '
          'means the surface sits in a component this audit has no name for; '
          'add it to `_anchors` before deciding anything else.',
    );

    // Drift's stream queries schedule a cleanup timer when their last listener
    // goes away, and Riverpod drops those listeners while the tree is being
    // unmounted — too late for flutter_test, which checks for pending timers
    // straight after the body. Tear the tree down inside the body instead and
    // pump once, so the cleanup runs while the fake clock is still turning.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('the audit is not vacuous: the accent tokens still share one hue', () {
    // The RGB reduction above is the whole matcher. If the ladder ever splits
    // into two hues, half the tokens stop matching and the audit quietly
    // starts counting fewer surfaces than exist.
    expect(
      _accentRgb.length,
      lessThanOrEqualTo(2),
      reason:
          'the generic-accent tokens resolved to ${_accentRgb.length} '
          'different RGB triples — the ladder has split, and this audit now '
          'sees only part of it',
    );
    expect(
      _accentRgb,
      contains(WpColors.accent.toARGB32() & 0x00FFFFFF),
      reason: 'the flat accent is not among the RGBs the audit matches on',
    );
  });
}

/// Label an accent-painting element by the nearest ancestor this audit knows.
String _label(Element element) {
  String? label;
  element.visitAncestorElements((ancestor) {
    final name = ancestor.widget.runtimeType.toString();
    final match = _anchors[name];
    if (match == null) return true;
    label = match;
    return false;
  });
  return label ?? 'UNCLASSIFIED: ${element.debugGetCreatorChain(12)}';
}

/// The colours a single widget paints as a fill, an edge, or a glyph.
///
/// Deliberately narrow: only the widgets that *are* the paint. `Container` and
/// `AnimatedContainer` delegate to `DecoratedBox`/`ColoredBox`, so collecting
/// them too would count one visual box three times.
Iterable<Color> _paintedColors(Widget w) sync* {
  if (w is DecoratedBox) {
    if (w.decoration case final BoxDecoration d) yield* _boxColors(d);
  } else if (w is ColoredBox) {
    yield w.color;
  } else if (w is Material) {
    if (w.color != null) yield w.color!;
  } else if (w is Icon) {
    if (w.color != null) yield w.color!;
  }
}

Iterable<Color> _boxColors(BoxDecoration d) sync* {
  if (d.color != null) yield d.color!;
  // A gradient fill is a fill: the active nav pill's is three accent stops.
  if (d.gradient case final Gradient g) yield* g.colors;
  final border = d.border;
  if (border != null) {
    for (final side in <BorderSide>[
      if (border is Border) ...[
        border.top,
        border.right,
        border.bottom,
        border.left,
      ] else
        border.top,
    ]) {
      if (side.style != BorderStyle.none) yield side.color;
    }
  }
}

Widget _harness(HistoryDatabase db) {
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWithValue(db),
      // Prevent real GPU detection (spawns a subprocess → pending timers).
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // The full window, not the bare page: two of the audited surfaces (the
      // nav pill and its indicator bar) live in the chrome, and the finding
      // this test answers was made on a full-window screenshot.
      home: const MediaQuery(
        data: MediaQueryData(size: Size(1280, 800)),
        child: WpScreenshotShell(activePageId: 'history', child: HistoryPage()),
      ),
    ),
  );
}

const _taggedEntryTitle = 'Weekly standup notes';

Future<void> _seed(HistoryDatabase db) async {
  final now = DateTime.now();
  await db
      .into(db.tags)
      .insert(
        TagsCompanion(
          id: const Value('tag-work'),
          name: const Value('Work'),
          createdAt: Value(now),
        ),
      );
  const titles = <String>[_taggedEntryTitle, 'Podcast outline', 'Bug report'];
  for (final (i, title) in titles.indexed) {
    await db
        .into(db.historyEntries)
        .insert(
          HistoryEntriesCompanion(
            id: Value('demo-$i'),
            title: Value(title),
            content: Value('$title — transcript body for the audit fixture.'),
            timestamp: Value(now.subtract(Duration(minutes: 5 * (i + 1)))),
            durationSec: const Value(12.0),
            processingDurationSec: const Value(0.8),
            language: const Value('en'),
            model: const Value('whisper-small'),
            isLocal: const Value(true),
            source: const Value('dictation'),
            colorSlot: Value(i),
          ),
        );
  }
  // Exactly one tag on the opened entry — the audited chip count follows it.
  await db
      .into(db.entryTags)
      .insert(
        const EntryTagsCompanion(
          entryId: Value('demo-0'),
          tagId: Value('tag-work'),
        ),
      );
}
