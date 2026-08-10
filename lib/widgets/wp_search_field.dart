/// WpSearchField — the app's single search input.
///
/// One component, one look: every place that lets the user *narrow a list by
/// typing* routes through here — the Replacements/Snippets toolbar, Notes,
/// History, Settings, the snippet picker overlay. Fields that capture a
/// *value* rather than a query (the feedback form, note bodies, the tag input
/// inside [WpTagInput]) are a different interaction and deliberately stay
/// separate.
///
/// ## Why this exists
///
/// Six search fields had drifted into four visibly different treatments and
/// three mutually exclusive theories of what a resting search field looks
/// like: no border at all (the global `inputDecorationTheme`), a borderless
/// capsule lifted by [WpShadows.subtle], and a fully round pill with a
/// hairline that eased to accent while focused. Radius came out as `sm`, `md`
/// and `full` — three accidents rather than three decisions.
///
/// Worse than the drift: a real accessibility bug lived through it. An
/// `IconButton(tooltip:)` publishes a Semantics *hint*, not a *label*, so a
/// screen reader announces the clear button as an unnamed button. Notes tried
/// to fix that with a `Semantics(label:)` wrapper around the button — and
/// History and Settings, which carry the same button, never even got that far.
/// Settings labelled its clear button with `historyClearSearch`, a string from
/// another feature. Both classes of problem are structural: they can only
/// happen when the same control is built N times.
///
/// The wrapper, it turns out, didn't work either. `IconButton` builds its own
/// *container* semantics node, so annotations from a `Semantics` ancestor land
/// on a node above it rather than merging in — the button node kept its
/// tooltip and stayed label-less, which a widget test in
/// `wp_search_field_test.dart` now pins. The label belongs on
/// `Icon(semanticLabel:)` *inside* the button, where it merges into the
/// button's own node; that is also what Flutter's own `IconButton` docs
/// prescribe. So the fix this component generalises is a step better than the
/// one it generalises *from*.
///
/// ## The one axis
///
/// [WpSearchFieldVariant] is *how the field seats itself on its surface* —
/// flat inside the window, floating in an overlay. It is the only axis, and it
/// carries the radius with it rather than exposing a free radius parameter,
/// because a free radius would reproduce exactly the "three accidents" this
/// component exists to end.
///
/// It used to have a third value, `raised`: no resting border, a
/// [WpShadows.subtleFor] lift and a 12 dp radius, "for a field that floats
/// above the list it filters". The rule didn't survive contact with its own
/// cases — Replacements and Snippets filter a list too and were `outlined`, so
/// the same control rendered with a different radius and a different resting
/// stroke depending on which sidebar entry the user had clicked, with nothing
/// but the call site deciding. `lib/DESIGN.md` never sanctioned it either: it
/// knows exactly one field style (filled, 8 dp radius, 1 dp `borderSubtle`,
/// accent focus, no glow). So all four list toolbars — History, Notes,
/// Replacements, Snippets — plus Settings now share [outlined], and the
/// sidebar switch no longer moves the field's geometry under the cursor.
/// [capsule] stays, because it answers a different question: not "which list is
/// below me" but "am I inside the window at all".
///
/// There is deliberately no size axis: all five migrated call sites run at the
/// same density today. An enum with one value is speculative stock; it can be
/// added the day a second density is actually needed.
///
/// ## Full width, always
///
/// The field takes the whole width its parent offers, and nothing about it
/// says otherwise: no cap, no preferred width, no start-alignment inside a
/// wider slot. Where the row holds nothing else it spans the entire content
/// column; where a toolbar button shares the row — Notes' "New note", the
/// Replacements/Snippets "Add" — the `Expanded` around it already ends at
/// that button's gap, and the field now runs right up to it. Width is the one
/// axis that answers to the window rather than to this component.
///
/// This replaces a 560 dp cap the component used to apply to itself. The cap
/// came out of an equal-width argument: a wide field with a short placeholder
/// reads as "more air inside" than a narrow one, so History and Settings (no
/// neighbour, whole column) looked differently padded from Notes and
/// Replacements/Snippets (~200 dp narrower because an Add button was
/// subtracted from the same row). The maintainer asked for the opposite rule
/// — the field grows and shrinks with the room to its right, and where a
/// button sits there it runs up to that button — while every field in the app
/// stays consistent on the axes that aren't width. So the cap went, and the
/// consistency it was standing in for is asserted where it can actually be
/// checked: `search_field_geometry_consistency_test.dart` pins height, offsets,
/// glyph slot and text insets as equalities across all four areas, at three
/// window widths and both text scales, and pins each area's *width* against the
/// room that area's own row has.
///
/// The stretch is applied inside the component so no call site has to opt in,
/// and it holds under both constraint shapes: the tight width of an `Expanded`
/// is filled by definition, and the loose width of a start-aligned `Column` is
/// taken in full by the `SizedBox(width: double.infinity)`. The shape it does
/// *not* survive is an unbounded width — a horizontal scroller or an
/// unconstrained `Row` slot asserts instead of shrink-wrapping, where the old
/// [Align] would have silently sized to the placeholder. That is the right
/// trade: a search field with no width to answer to has no width worth
/// guessing.
///
/// Anything a caller glues *under* the field — History's suggestion panel and
/// operator hint, Settings' suggestion dropdown — still has to end where the
/// field ends. That rule didn't change, only the field's end did: those
/// siblings now stretch to the full column too (`minWidth: double.infinity`)
/// instead of repeating a shared width constant.
///
/// ## One highlight per state
///
/// The [WpDropdown] lesson again. The **border is the only focus signal** —
/// there is no [WpFocusRing] around this control, unlike [WpButton]. A text
/// field, unlike a button, already draws a contour of its own; a ring 2 dp
/// outside it would be two markings for one state, which is the bug the
/// dropdown refactor was originally about.
///
/// The border is painted by an [AnimatedContainer]'s `foregroundDecoration`
/// rather than by [InputDecoration], for two reasons. `foregroundDecoration`
/// paints *over* the child without insetting it, so growing the stroke from
/// 1 to 1.5 dp on focus costs no layout shift. And the transition then runs on
/// [WpMotion.durationFor], which collapses to zero under the system's
/// "Reduce Motion" flag — `InputDecorator`'s built-in border animation is a
/// hard-coded 200 ms that consults nothing. The snippet-picker pill respected
/// reduced motion before this refactor; now all five fields do.
///
/// ## The clear button
///
/// Present in every variant as soon as the field has text, and always named —
/// see above. Appearing and disappearing must not resize the field, which is
/// what `prefixIconConstraints`/`suffixIconConstraints` in `build` are for.
///
/// They used to be absent, on the theory that "a `prefixIcon` already holds
/// both fields at Material's 48 dp icon-slot floor, which the suffix then
/// shares". Measured in the running app, that was wrong twice over, and the
/// widget tests couldn't see either half. Flutter's default for an unset slot
/// constraint is not the 48 dp floor but
/// `visualDensity.effectiveConstraints(…48…)`, and `ThemeData.visualDensity`
/// is unset here, so it resolves to `adaptivePlatformDensity` — which on this
/// app's *only* platforms (macOS, Windows, Linux) is `VisualDensity.compact`
/// and shrinks that floor to **40 dp**. So:
///
/// * A bare `Icon` in the prefix slot has no size of its own beyond the glyph,
///   so a field with no suffix rested at 40 dp, not 48.
/// * An `IconButton` in the suffix slot does have one, and it is 48: this
///   app's `iconButtonTheme` sets `minimumSize` to [WpLayout.minTouchTarget],
///   and `IconButton` resolves its *own* `visualDensity` to
///   `VisualDensity.standard` on every platform under Material 3 (see
///   `icon_button.dart`'s class docs), so the ambient `compact` never shrinks
///   that 48 the way it shrank the slot's inherited minimum. The slot
///   constraint being only a *minimum*, the button pushed the whole box to
///   48 dp. History, whose `suffix` is always populated, was permanently 8 dp
///   taller than its siblings; everywhere else the box jumped 8 dp on the
///   first keystroke and back on clear, carrying the filter-chip row with it.
///
/// It is specifically *not* `MaterialTapTargetSize.padded` inflating a 40 dp
/// button into a 48 dp tap target — the mechanism the `_buttonBox()` comment
/// in the geometry test documents for [WpButton]. `ThemeData` defaults
/// `materialTapTargetSize` to `shrinkWrap` on the three desktops and this app
/// never overrides it, so on the only platforms WhisPaste ships on that
/// padding does not exist. Measured, not reasoned: the clear button's layout
/// box and its painted `Material` are both 48×48 there, with no gap between
/// them for a tap target to live in.
///
/// Both are gone now that the slots state their own size instead of inheriting
/// a platform-dependent one. Note that a widget test cannot see any of this on
/// its own: `flutter test` forces `defaultTargetPlatform` to Android, where
/// `adaptivePlatformDensity` *is* standard, so the whole drift disappears in
/// the harness. `search_field_geometry_consistency_test.dart` therefore runs
/// its height assertions under an explicit `TargetPlatformVariant.desktop()`
/// — without that they pass just as happily on the broken component.
///
/// ## Secondary engines
///
/// This field resolves its own strings via `L10n.of(context)`, which needs a
/// `Localizations` ancestor for [L10n]. The main window's `MaterialApp`
/// (`app.dart`) always provides one; WhisPaste's secondary Flutter engines
/// (floating button, recording overlay, snippet picker) historically don't,
/// since they resolve locale manually instead of through ambient
/// `Localizations`. Any secondary-engine `MaterialApp` that mounts this field
/// — as the snippet picker does, `capsule` variant — must set
/// `localizationsDelegates`/`supportedLocales`/`locale` itself, or the very
/// first build throws a null-check on `Localizations.of<L10n>`.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Axis
// ---------------------------------------------------------------------------

/// How the field seats itself on the surface behind it.
enum WpSearchFieldVariant {
  /// Flat field with a visible resting hairline — the one in-window look, for
  /// every search inside the main window: the four list toolbars (History,
  /// Notes, Replacements, Snippets) and Settings alike. See the library docs
  /// for why filtering a list is *not* a reason to look different.
  outlined,

  /// Fully round, tinted pill. For the overlay/HUD context, where the app's
  /// rectangular form language would read as a window inside a window
  /// (snippet picker).
  capsule,
}

// ---------------------------------------------------------------------------
// Field
// ---------------------------------------------------------------------------

class WpSearchField extends StatefulWidget {
  const WpSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.variant,
    this.focusNode,
    this.onChanged,
    this.onClear,
    this.onSubmitted,
    this.clearTooltip,
    this.suffix,
    this.semanticsLabel,
    this.autofocus = false,
  });

  /// Owned by the caller — every call site already holds one to read the query
  /// from, and several wire a listener to it.
  final TextEditingController controller;

  /// Already localized placeholder.
  final String hintText;

  /// No default on purpose — see the library docs.
  final WpSearchFieldVariant variant;

  /// Optional external node, for parents that wire Ctrl+F / Cmd+F focus or
  /// install their own `onKeyEvent` handler (Settings drives its suggestion
  /// dropdown that way). Omitted, the field creates and disposes its own.
  final FocusNode? focusNode;

  /// Fired on every keystroke **and once with `''` when the clear button is
  /// pressed**, so call sites that filter from the callback rather than from a
  /// controller listener don't need to handle clearing separately.
  final ValueChanged<String>? onChanged;

  /// Extra work after clearing, for state the controller doesn't reach — the
  /// History bar closes its suggestion panel here. The component has already
  /// emptied the controller and fired [onChanged] by then.
  final VoidCallback? onClear;

  final ValueChanged<String>? onSubmitted;

  /// Tooltip **and** screen-reader label of the clear button. Defaults to
  /// `l10n.actionClearSearch`; pass one only where the feature has genuinely
  /// different wording, never to restate the same sentence.
  final String? clearTooltip;

  /// Trailing slot, right of the clear button — History's search-syntax help
  /// button. A slot rather than a hard-wired button, so the component stays
  /// ignorant of any one feature's extras.
  ///
  /// A suggestion dropdown is *not* this: it belongs below the field, as a
  /// sibling in the caller's `Column`, which is where Settings and History
  /// already put theirs.
  final Widget? suffix;

  /// Names the field itself for screen readers, where the placeholder alone
  /// isn't a sufficient name.
  final String? semanticsLabel;

  final bool autofocus;

  @override
  State<WpSearchField> createState() => _WpSearchFieldState();
}

class _WpSearchFieldState extends State<WpSearchField> {
  FocusNode? _ownedNode;
  FocusNode get _focusNode => widget.focusNode ?? _ownedNode!;

  /// Mirrors of the two things the box's appearance depends on. Tracked here
  /// so the field redraws its border and shows/hides its clear button on its
  /// own — call sites shouldn't have to rebuild it to keep it honest.
  bool _hasFocus = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedNode = FocusNode(debugLabel: 'WpSearchField');
    }
    _hasFocus = _focusNode.hasFocus;
    _hasText = widget.controller.text.isNotEmpty;
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(WpSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _hasText = widget.controller.text.isNotEmpty;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedNode)?.removeListener(_onFocusChanged);
      if (widget.focusNode != null) {
        _ownedNode?.dispose();
        _ownedNode = null;
      } else {
        _ownedNode ??= FocusNode(debugLabel: 'WpSearchField');
      }
      _focusNode.addListener(_onFocusChanged);
      _hasFocus = _focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _ownedNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted || _hasFocus == _focusNode.hasFocus) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  void _onTextChanged() {
    final next = widget.controller.text.isNotEmpty;
    if (!mounted || _hasText == next) return;
    setState(() => _hasText = next);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final brightness = Theme.of(context).brightness;
    final palette = _WpSearchFieldPalette.of(brightness);
    final spec = _WpSearchFieldSpec.of(widget.variant);
    final clearLabel = widget.clearTooltip ?? l10n.actionClearSearch;

    final Widget? clearButton = _hasText
        ? IconButton(
            icon: Icon(
              LucideIcons.x,
              size: WpIconSize.sm,
              color: palette.textMuted,
              // The label goes *here*, not on a Semantics wrapper around the
              // button — see the library docs: the wrapper lands on an
              // ancestor node the button never merges into.
              semanticLabel: clearLabel,
            ),
            tooltip: clearLabel,
            onPressed: _clear,
          )
        : null;

    final Widget? suffixIcon = clearButton == null && widget.suffix == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [?clearButton, ?widget.suffix],
          );

    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      // The icon slots hold the box at 48 dp — see the constraints below,
      // which is what makes that true rather than platform-dependent. 48 is
      // taller than the text row's own padded height, so without this the
      // input keeps its top-aligned box and the text rides 4 dp above the
      // search glyph and the clear button, both of which *are* centred.
      textAlignVertical: TextAlignVertical.center,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(fontSize: WpTypography.body, color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: Icon(
          LucideIcons.search,
          size: WpIconSize.sm,
          color: palette.textMuted,
        ),
        suffixIcon: suffixIcon,
        // Both icon slots are pinned to the touch target rather than left to
        // Flutter's default, which is `visualDensity.effectiveConstraints` of
        // a 48 dp floor — and on desktop that default is *not* 48. See "The
        // clear button" in the library docs for the two bugs this closes.
        //
        // The prefix is a single 16 dp glyph, so its width is knowable and
        // tight: that is what puts the same 16 dp in front of the glyph that
        // `contentPadding` puts in front of the text below.
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: WpLayout.minTouchTarget,
          height: WpLayout.minTouchTarget,
        ),
        // The suffix holds a *Row* — the clear button, plus whatever the
        // caller passed in `suffix` (History stacks its help button there).
        // Its width therefore has to stay free to grow, or that Row overflows
        // the slot it was given.
        //
        // Its height is belt-and-braces rather than the working mechanism:
        // every suffix that exists today is 48 dp on its own, and the prefix
        // above already pins the box, so taking this line back out changes
        // nothing measurable — the geometry test stays green without it. What
        // it buys is the *next* suffix: a taller child would otherwise push
        // the box past 48 and reintroduce the same drift from the other slot.
        // The trade is deliberate — a suffix that outgrows the touch target
        // gets clamped here rather than silently resizing every search bar in
        // the app — so anything taller than [WpLayout.minTouchTarget] belongs
        // beside the field, not inside it.
        suffixIconConstraints: const BoxConstraints(
          minWidth: WpLayout.minTouchTarget,
          minHeight: WpLayout.minTouchTarget,
          maxHeight: WpLayout.minTouchTarget,
        ),
        isDense: true,
        // Horizontal: matches the 16 dp the 48 dp prefix slot already puts in
        // front of its 16 dp glyph, so a field without a trailing button ends
        // its text at the same inset the search icon starts at.
        // Vertical: below the 48 dp floor at normal text size, so it decides
        // nothing there — it is the breathing room the field grows *into*
        // once an accessibility text size pushes the line past the floor.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xs + 2,
        ),
        // Fill, border and radius all live on the box below — the decoration
        // would otherwise paint a second, differently-timed border under the
        // one the box already animates.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );

    if (widget.semanticsLabel != null) {
      // `Semantics(label:)` alone, without a boundary, doesn't attach the
      // label to the field: it merges into whatever ancestor node happens to
      // be collecting descendants — on the Replacements screen that was the
      // header switch's own node, so the two announced as one. A plain
      // `container: true` fixes the upward merge but creates the opposite
      // split: the field's own node (focus/tap actions, `isTextField`) then
      // sits *below* this one as a child instead of carrying the label
      // itself, so a reader would land on an unlabelled, unfocusable node
      // first. `MergeSemantics` folds the two back into one node — this
      // label plus the field's own actions and state — and, per
      // `toStringDeep()`'s "merge boundary", also blocks the upward merge
      // this fix started from.
      //
      // The field's own `hintText` already lands on that merged node as its
      // label — `InputDecoration.hintText` does that on its own once there's
      // no separate `labelText`. Every current caller passes `semanticsLabel`
      // as the hint's own wording minus its trailing ellipsis, so stacking a
      // second `Semantics(label:)` here would announce the same sentence
      // twice ("Search notes, Search notes…"). Only add an explicit label
      // when it actually says something the hint doesn't — `MergeSemantics`
      // alone still gets applied either way, since the boundary is what
      // stops the upward merge, independent of whether the text differs.
      final restatesHint =
          widget.semanticsLabel!.trim() ==
          widget.hintText.trim().replaceAll(RegExp('…+\$'), '').trim();
      field = MergeSemantics(
        child: restatesHint
            ? field
            : Semantics(label: widget.semanticsLabel!, child: field),
      );
    }

    final Widget box = AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      curve: WpMotion.defaultCurve,
      // No shadow in any variant: the field is flat on its surface, and the
      // border below is the only thing that marks its edge.
      decoration: BoxDecoration(
        color: spec.fill(palette),
        borderRadius: spec.radius,
      ),
      // Painted over the child, so the stroke can thicken on focus without
      // moving a single pixel of text. See the library docs.
      foregroundDecoration: BoxDecoration(
        borderRadius: spec.radius,
        border: Border.all(
          color: _hasFocus ? palette.accent : spec.restingBorder(palette),
          width: _hasFocus ? 1.5 : 1,
        ),
      ),
      child: field,
    );

    // Takes the whole width the parent offers — tight from an `Expanded`
    // (Notes, Replacements/Snippets), loose from a start-aligned `Column`
    // (History, Settings, the snippet picker). See "Full width, always" in
    // the library docs, including why an unbounded width is an assert here
    // rather than a shrink-wrap.
    //
    // Height is deliberately left off, and that is measured rather than
    // assumed: the geometry test reads the constraints each of the four
    // in-window call sites hands in, and every one of them is loose in the
    // vertical (`0.0<=h<=Infinity`), so the box keeps its intrinsic 48 dp
    // without needing a `heightFactor` to stop it from stretching into a
    // taller slot. A call site that ever handed down a *bounded* height would
    // need one — hence that assertion, and the cross-area height equality
    // beside it.
    return SizedBox(width: double.infinity, child: box);
  }
}

// ---------------------------------------------------------------------------
// Resolved tokens
// ---------------------------------------------------------------------------

/// The field's colours for one theme, resolved once instead of ternary by
/// ternary inside `build`.
@immutable
class _WpSearchFieldPalette {
  const _WpSearchFieldPalette({
    required this.surface,
    required this.mutedFill,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
  });

  /// Fill of the in-window variant, [WpSearchFieldVariant.outlined].
  final Color surface;

  /// Fill of [WpSearchFieldVariant.capsule] — translucent on purpose, so the
  /// overlay's blurred backdrop stays readable through the pill.
  final Color mutedFill;

  final Color border;
  final Color textPrimary;
  final Color textMuted;

  /// The focused border, in every variant — the single focus signal.
  final Color accent;

  static const _dark = _WpSearchFieldPalette(
    surface: WpColorsDark.surfaceVariant,
    mutedFill: WpColorsDark.surfaceMutedFill,
    border: WpColorsDark.borderSubtle,
    textPrimary: WpColorsDark.textPrimary,
    textMuted: WpColorsDark.textMuted,
    accent: WpColorsDark.accent,
  );

  static const _light = _WpSearchFieldPalette(
    surface: WpColorsLight.surfaceVariant,
    mutedFill: WpColorsLight.surfaceMutedFill,
    border: WpColorsLight.borderSubtle,
    textPrimary: WpColorsLight.textPrimary,
    textMuted: WpColorsLight.textMuted,
    accent: WpColorsLight.accent,
  );

  static _WpSearchFieldPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;
}

/// Everything [WpSearchFieldVariant] actually decides.
@immutable
class _WpSearchFieldSpec {
  const _WpSearchFieldSpec({
    required this.radius,
    required this.tinted,
    required this.bordered,
  });

  final BorderRadius radius;

  /// Uses the translucent muted fill rather than the opaque surface one.
  final bool tinted;

  /// Shows a hairline while unfocused. `false` leaves the resting border
  /// *transparent* rather than absent, so the focus transition animates a
  /// colour instead of appearing out of nothing. Both surviving variants say
  /// `true` today — the flag stays because it is what makes the resting
  /// stroke a property of the variant rather than a hardcode, which is the
  /// shape the next variant would need.
  final bool bordered;

  Color fill(_WpSearchFieldPalette p) => tinted ? p.mutedFill : p.surface;

  Color restingBorder(_WpSearchFieldPalette p) =>
      bordered ? p.border : Colors.transparent;

  static final _outlined = _WpSearchFieldSpec(
    radius: WpRadius.borderSm,
    tinted: false,
    bordered: true,
  );

  static final _capsule = _WpSearchFieldSpec(
    radius: WpRadius.borderFull,
    tinted: true,
    bordered: true,
  );

  static _WpSearchFieldSpec of(WpSearchFieldVariant variant) =>
      switch (variant) {
        WpSearchFieldVariant.outlined => _outlined,
        WpSearchFieldVariant.capsule => _capsule,
      };
}
