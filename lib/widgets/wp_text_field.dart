/// WpTextField — the app's writing surfaces, in one component.
///
/// Sister to [WpSearchField] and cut the same way. Where that one owns every
/// field that *narrows a list by typing*, this one owns every field that
/// *holds a value the user authors*: the History entry's title, the History
/// transcript in edit mode, the Notes editor. Deliberately **not** part of the
/// family: search inputs (they are [WpSearchField]), and the tag input inside
/// [WpTagInput], which is a value-in-progress committed with Enter and lives
/// width-constrained inside a `Wrap` — a different interaction with a
/// different affordance, already centralised elsewhere.
///
/// ## Why this exists
///
/// The two surfaces on which a user edits a paragraph of text looked like two
/// different programs. The History transcript was **monospace** at 16 dp/1.65
/// in a bordered 12 dp box; the Notes editor was proportional at 14 dp/1.6 on
/// a borderless 24 dp field; the History title brought a third set of insets
/// (8/4) and hand-built its own [OutlineInputBorder] pair. A user reaches both
/// writing surfaces from the same sidebar, often within seconds of each other,
/// so the break was not theoretical — it was visible on every switch.
///
/// The monospace is gone. `lib/DESIGN.md` knows exactly one type family ("one
/// family everywhere"), and no comment, ticket or commit ever recorded a
/// reason for the exception: a dictated transcript is prose, not code, and
/// nothing about it is column-aligned. One family now covers both surfaces.
///
/// ## The one axis
///
/// [WpTextFieldVariant] answers **what is being edited, and what already
/// bounds it** — which is the question that actually decides this control's
/// appearance, and the reason the answer is not "copy one of the two current
/// looks onto the other". The deciding test is whether anything else shares
/// the surface:
///
///  * [WpTextFieldVariant.heading] sits in a document flow among other things
///    — a header row with an avatar, a timestamp and six actions. Nothing
///    there says "this block is a field now" unless the field says it itself,
///    and it appears only when edit mode opens, so the box is also the mode
///    indicator. It is boxed, per `lib/DESIGN.md` ("Inputs / Fields"): filled
///    surface, 8 dp radius, 1 dp subtle hairline.
///  * [WpTextFieldVariant.passage] is a whole paragraph of prose, and since
///    Ticket 09 it is **card material rather than a box** (see "What the
///    surfaces are made of"). A transcript is the one thing on that panel a
///    reader is actually reading; a hairline drawn all the way around it
///    frames the reading itself, and the 8 dp filled rectangle already says
///    "editable region" without one.
///  * [WpTextFieldVariant.form] is the plain 13 dp field a *form* is made of —
///    an API key, a snippet title, a trigger phrase, a feedback comment. It
///    stands alone under its own label with nothing else on its line, so it
///    draws its own box: filled surface, 8 dp radius, 1 dp hairline, and a
///    48 dp resting height, which is both `WpLayout.minTouchTarget` and the
///    height [WpSearchField] settles at — the two field families a user meets
///    on the same screen now agree on one silhouette.
///  * [WpTextFieldVariant.embedded] is the same field with its box taken
///    away, for the one shape where the container is *not* the field's to
///    draw: History's note rows, where one bordered row holds the field **and**
///    its save/cancel buttons. A boxed field there would draw a box inside a
///    box. The host keeps fill and border (and marks the authoring state with
///    them); the field keeps the inset, so the text sits at the same 12/14
///    the row's read view puts it at and does not jump when edit mode opens.
///  * [WpTextFieldVariant.bare] *is* the surface. Nothing else shares the
///    region below the Notes divider, so a resting border would only draw a
///    box inside a box, and the writing area would end up smaller than the
///    space it owns. It keeps the fill — the writing surface is the same
///    material as `passage`'s — and drops the stroke while idle. Only while
///    idle: on focus it takes the same accent stroke as everyone else, see
///    "one highlight per state" below.
///
/// The axis carries typography and inset with it rather than exposing them,
/// because free `fontSize`/`contentPadding` parameters would reproduce exactly
/// the three-different-answers drift the component exists to end. That is also
/// why `heading` and `passage` are two variants and not one boxed variant with
/// a typography knob: a knob would permit "prose at title weight", which is
/// not a decision anyone should be able to take at a call site.
///
/// The line that separates a legitimate parameter from a banned one is
/// **optical vs. functional**: what the field *looks like* is the variant's to
/// decide and is never passed in; what the field *does* — obscure its text,
/// cap its length, grow to at most five lines, carry a reveal button — is the
/// call site's and is passed in. [minLines]/[maxLines] are therefore the one
/// size-adjacent exception, and only on `form`/`embedded`: how much room a
/// value needs is a property of that value (a trigger phrase is one line, a
/// custom vocabulary is several), not of the field family.
///
/// ## What the numbers are
///
/// One inset per variant, measured rather than asserted, pinned in
/// `test/widgets/form_field_geometry_consistency_test.dart`. `form` is 16 dp
/// horizontal / 14 dp vertical, which puts a single line's box at exactly
/// 48 dp at 1.0x without a height constraint — the padding, not a `SizedBox`,
/// is what holds the field open, so an accessibility text size grows the box
/// instead of clipping the line. (The Settings API-key field used to force
/// `height: 34`; at 1.5x its text overflowed the box by 0.3 dp and was cut.)
/// `embedded` is 12 dp / 14 dp: narrower, because its host is a 12 dp-inset
/// list row rather than a standalone field.
///
/// ## What the surfaces are made of
///
/// Two materials, and which one a variant takes is decided by what it stands
/// on (Ticket 09, following Ticket 08's in-plane/floating split):
///
///  * `heading` and `form` keep the **opaque** `surfaceVariant`. Both live in
///    dialogs and header rows on top of already-opaque grounds, where a 3–5 %
///    translucent tint is not a material, it is a rounding error.
///  * `passage` and `bare` take the **card material** — `WpColors.cardFill`,
///    the same translucent tint every other card in the app is made of. Both
///    own a whole region of a panel, and both panels now paint no ground of
///    their own: the page's one ambient shows through the field, which is the
///    One-Atmosphere Rule's whole point. That is also why the fill stays a
///    *single* frost layer rather than a panel card with a field card on top:
///    stacking two rungs drops the hint text (`textMuted`) to 4.43:1 over the
///    lightest ambient stop, below AA. Unstacked it measures 4.76:1.
///  * `embedded` paints nothing at all; its host row already did.
///
/// ### The hover lift
///
/// Dropping `passage`'s resting hairline also drops the "I can write here"
/// affordance that hairline was carrying. The replacement is a **lift of the
/// fill**, not a new contour: `cardFill` → `cardFillElevated` under the
/// pointer, on both card variants. It is the palette's own declared depth
/// source (`colors.dart`: depth is a brightness delta, not a shadow), it uses
/// the existing rungs of the tint ladder rather than a hand-rolled alpha, and
/// it cannot be confused with focus because focus is a *contour* and this is a
/// *surface*. Hover and focus are two different states, so they are allowed to
/// be visible at once — "one highlight per state" counts markings per state,
/// not markings on screen.
///
/// ## Read mode has to match
///
/// Both History fields toggle between a read view and an edit view of the same
/// text. If the two render at different metrics the text jumps size the moment
/// edit mode opens, which reads as a glitch. [WpTextField.styleFor] exposes
/// each variant's style so the read view can render at exactly the field's
/// metrics — the two can no longer drift apart, and the call site still sets
/// no font size of its own.
///
/// ## One highlight per state
///
/// The [WpSearchField] rule, unchanged: **the field's own contour is the only
/// focus signal**. No [WpFocusRing] around the control, no glow — a text field
/// already draws a contour, and a ring outside it would be two markings for
/// one state. Boxed variants therefore move their hairline to the accent at
/// 1.5 dp, and [WpTextFieldVariant.bare], having no hairline to move, grows
/// the same accent stroke from nothing for as long as it holds focus. Both
/// come out of one predicate on the spec ([_WpTextFieldSpec.strokeAt]) and one
/// paint site, so there is no second focus treatment to keep in step with the
/// first.
///
/// [WpTextFieldVariant.passage] is the third case and the reason
/// [_WpFieldRestingStroke] has three values rather than two: it shows no
/// contour at rest, but it still paints a 1 dp stroke in `Colors.transparent`
/// there. That is [WpSearchField]'s idiom — a resting border left transparent
/// rather than absent, so the focus transition animates a *colour* instead of
/// appearing out of nothing. `passage` used to cross-fade `borderSubtle` →
/// accent, and going to a null decoration at rest would have silently
/// downgraded that to `bare`'s snap.
///
/// `bare` used to show focus by the caret alone, on the argument that a stroke
/// there would frame the whole lower half of the Notes panel for as long as
/// the user types. The maintainer decided against that reading: a writing
/// surface the size of a panel is exactly where "is my typing going here" must
/// not be a question, and the rule was never "the contour, where the variant
/// happens to have one". The stroke snaps in and out instead of cross-fading
/// like the boxed variants: [AnimatedContainer] builds the tween fresh on the
/// frame a decoration first appears, so its begin and its target are the same
/// value and the controller never starts. On a focus indicator that reads as
/// immediate rather than as a jump, so it is left alone.
///
/// [WpTextFieldVariant.embedded] is the one variant that still shows nothing
/// of its own, and it follows the same rule from the other side:
/// the one contour on that row belongs to the host, so the host is what turns
/// accent while the note is being authored. Two accents — one on the row, one
/// inside it — would again be two markings for one state.
///
/// The stroke is painted by an [AnimatedContainer]'s `foregroundDecoration`
/// rather than by [InputDecoration], for the reasons spelled out in
/// [WpSearchField]: `foregroundDecoration` paints over the child without
/// insetting it, so growing 1 → 1.5 dp costs no layout shift and no reflow of
/// a paragraph mid-edit; and the transition then runs on [WpMotion.durationFor],
/// which collapses to zero under the system's Reduce-Motion flag, where
/// `InputDecorator`'s built-in 200 ms consults nothing.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Axis
// ---------------------------------------------------------------------------

/// What is being edited — and therefore what the field has to look like.
enum WpTextFieldVariant {
  /// A short title edited in place, inside a row that carries other things
  /// too (History's entry header). Boxed, single-line, and rendered at the
  /// size and weight the title has when it is *not* being edited, so opening
  /// edit mode never resizes the text.
  heading,

  /// A passage of prose that is one section among several on its surface
  /// (History's transcript in edit mode). Multi-line, prose metrics, and a
  /// contour-free card surface: 8 dp of card material, no resting hairline,
  /// a lift under the pointer, the accent contour on focus.
  passage,

  /// A form value under its own label, alone on its line (Settings, the
  /// Snippets/Replacements dialogs, the feedback form). Boxed, 13 dp, 48 dp
  /// tall at rest, and it takes its line count from the call site.
  form,

  /// The same form value inside a container the caller draws because that
  /// container also holds other controls (History's note rows: field plus
  /// save/cancel). No box of its own — no fill, no stroke, no radius — and
  /// the inset that keeps its text on the row's own text line.
  embedded,

  /// The surface *is* the field (the Notes editor). No stroke at rest — it
  /// takes one only while focused — generous inset, and it expands to fill
  /// the box it is given, so it must be given
  /// a bounded one (an `Expanded`, a `SizedBox`), which is the definition of
  /// owning the surface rather than sitting on it.
  bare,
}

// ---------------------------------------------------------------------------
// Scroll-to-end signal
// ---------------------------------------------------------------------------

/// One-way request to a [WpTextField]: "show the end of your content".
///
/// Exists so a call site can ask without owning the field's scroll position.
/// A caller-owned [ScrollController] cannot do the job here: the Notes split
/// view cross-fades between two editor panels, so for the length of that fade
/// two fields are mounted, and a single controller attached to both trips
/// Flutter's one-position assertion. Any number of fields may listen; each
/// scrolls its own.
class WpScrollToEndSignal extends ChangeNotifier {
  /// Requests the jump. Safe to call when no field is listening — the request
  /// is simply dropped, it is not queued.
  void fire() => notifyListeners();
}

// ---------------------------------------------------------------------------
// Field
// ---------------------------------------------------------------------------

class WpTextField extends StatefulWidget {
  const WpTextField({
    super.key,
    required this.controller,
    required this.variant,
    this.focusNode,
    this.hintText,
    this.semanticsLabel,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.minLines,
    this.maxLines,
    this.obscureText = false,
    this.autocorrect = true,
    this.maxLength,
    this.suffix,
    this.scrollToEnd,
  }) : assert(
         minLines == null && maxLines == null ||
             variant == WpTextFieldVariant.form ||
             variant == WpTextFieldVariant.embedded,
         'Only form/embedded take their line count from the call site — the '
         'other variants are one-line or free-growing by definition.',
       ),
       assert(
         suffix == null || variant == WpTextFieldVariant.form,
         'A trailing button needs the boxed 48 dp slot only form provides.',
       );

  /// Owned by the caller. Every call site already holds one — History reads
  /// the edited text back out of it on save, Notes keeps it alive across
  /// panel rebuilds so cursor and IME state survive.
  final TextEditingController controller;

  /// No default on purpose — see the library docs.
  final WpTextFieldVariant variant;

  /// Optional external node, for parents that focus the field from a keyboard
  /// shortcut or share it with a toolbar (History's markdown toolbar inserts
  /// at the caret and needs the same node). Omitted, the field creates and
  /// disposes its own.
  final FocusNode? focusNode;

  /// Already localized placeholder. Rendered at the field's own metrics in
  /// the muted text colour, not at the global 13 dp hint size — a 13 dp
  /// placeholder inside a 16 dp field reads as a different control.
  final String? hintText;

  /// Names the field for screen readers where the placeholder is not a
  /// sufficient name — or where there is no placeholder at all, as on the
  /// transcript.
  final String? semanticsLabel;

  final bool autofocus;

  final ValueChanged<String>? onChanged;

  /// Only ever fires on [WpTextFieldVariant.heading]: the multi-line variants
  /// take Enter as a newline, which is what a writing surface must do. Passed
  /// through unchanged for the ones that do submit.
  final ValueChanged<String>? onSubmitted;

  final VoidCallback? onEditingComplete;

  /// How much room this particular *value* needs — see the library docs on
  /// optical vs. functional parameters. `form`/`embedded` only; a `maxLines`
  /// of 1 (the default) also makes Enter submit rather than insert a newline.
  final int? minLines;
  final int? maxLines;

  /// Functional pass-throughs. None of them change how the field looks; each
  /// exists because exactly one call site cannot work without it: the API key
  /// ([obscureText], [suffix] for the reveal toggle), the feedback contact
  /// address ([autocorrect]) and the feedback comment ([maxLength]).
  final bool obscureText;
  final bool autocorrect;
  final int? maxLength;

  /// A button inside the box's trailing 48 dp slot, the way [WpSearchField]
  /// carries its clear button — not overlaid on the field by the call site,
  /// which is how the API-key toggle used to force a 34 dp field so a 48 dp
  /// button could straddle it.
  final Widget? suffix;

  /// Ask-don't-tell scroll seam: every time this notifies, the field jumps to
  /// the end of its content. Only meaningful on a variant that scrolls at all
  /// ([WpTextFieldVariant.bare] — the Notes editor, which owns its surface),
  /// where the Notizen area uses it to reveal a just-appended quick-note
  /// transcript.
  ///
  /// A signal rather than a caller-owned [ScrollController] on purpose: the
  /// notes split view cross-fades between two editor panels, so for the
  /// length of that fade *two* fields exist, and one controller attached to
  /// both is an assertion error. Each field keeps its own controller and only
  /// listens for the request. Omitted, the field behaves exactly as before —
  /// no controller of its own, Flutter's internal one.
  final Listenable? scrollToEnd;

  /// The text style [variant] renders at, so a read-only view of the same
  /// text can match it exactly. See the library docs.
  static TextStyle styleFor(
    WpTextFieldVariant variant, {
    required Color color,
  }) => _WpTextFieldSpec.of(variant).textStyle(color);

  @override
  State<WpTextField> createState() => _WpTextFieldState();
}

class _WpTextFieldState extends State<WpTextField> {
  FocusNode? _ownedNode;
  FocusNode get _focusNode => widget.focusNode ?? _ownedNode!;

  /// Created only when someone actually asks the field to scroll — every
  /// other call site keeps Flutter's internal controller, unchanged.
  ScrollController? _scrollController;

  /// Mirror of the one thing the box's appearance depends on. Tracked here so
  /// the field redraws its own stroke — call sites shouldn't have to rebuild
  /// it to keep it honest.
  bool _hasFocus = false;

  /// Pointer state, tracked only on the card variants — see [_setHovered].
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedNode = FocusNode(debugLabel: 'WpTextField');
    }
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChanged);
    if (widget.scrollToEnd != null) {
      _scrollController = ScrollController();
      widget.scrollToEnd!.addListener(_jumpToEnd);
    }
  }

  @override
  void didUpdateWidget(WpTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToEnd != widget.scrollToEnd) {
      oldWidget.scrollToEnd?.removeListener(_jumpToEnd);
      widget.scrollToEnd?.addListener(_jumpToEnd);
      // Kept once created: handing the field back Flutter's internal
      // controller mid-life would buy nothing and lose the scroll offset.
      if (widget.scrollToEnd != null) _scrollController ??= ScrollController();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedNode)?.removeListener(_onFocusChanged);
      if (widget.focusNode != null) {
        _ownedNode?.dispose();
        _ownedNode = null;
      } else {
        _ownedNode ??= FocusNode(debugLabel: 'WpTextField');
      }
      _focusNode.addListener(_onFocusChanged);
      _hasFocus = _focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.scrollToEnd?.removeListener(_jumpToEnd);
    _scrollController?.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _ownedNode?.dispose();
    super.dispose();
  }

  /// Post-frame, because `maxScrollExtent` is only known once the (usually
  /// just-changed) text has been laid out — which is also what makes this
  /// correct at enlarged system text sizes: the extent is the measured
  /// height, not an estimate. `jumpTo`, not `animateTo`: the point is that
  /// the end is visible on arrival, not that a movement is shown.
  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      if (!mounted || controller == null || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  void _onFocusChanged() {
    if (!mounted || _hasFocus == _focusNode.hasFocus) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  /// Only ever called on the card variants — the [MouseRegion] is not even
  /// mounted on the others, so an opaque field costs no extra hit-test layer
  /// and can never rebuild for a pointer that changes nothing about it.
  void _setHovered(bool value) {
    if (!mounted || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    const palette = _WpTextFieldPalette._palette;
    final spec = _WpTextFieldSpec.of(widget.variant);
    final style = spec.textStyle(palette.textPrimary);

    // On `form`/`embedded` the call site owns the line count; everywhere else
    // the variant does, and passing either is an assertion error.
    final maxLines = spec.linesFromCallSite
        ? (widget.maxLines ?? 1)
        : (spec.multiline ? null : 1);
    final multiline = spec.linesFromCallSite ? maxLines != 1 : spec.multiline;

    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      autofocus: widget.autofocus,
      minLines: spec.linesFromCallSite ? widget.minLines : null,
      maxLines: spec.fillsItsBox ? null : maxLines,
      expands: spec.fillsItsBox,
      textAlignVertical: spec.fillsItsBox ? TextAlignVertical.top : null,
      keyboardType: multiline ? TextInputType.multiline : null,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      maxLength: widget.maxLength,
      style: style,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: widget.onEditingComplete,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: style.copyWith(color: palette.textMuted),
        suffixIcon: widget.suffix,
        // Drawn below the box instead — see [_counter]. Inside, it would
        // make the one field that counts its characters 21 dp taller than
        // every other form field.
        counterText: '',
        isDense: true,
        contentPadding: spec.padding,
        // Fill, stroke and radius all live on the box below — the decoration
        // would otherwise paint a second, differently-timed border under the
        // one the box already animates.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );

    if (widget.semanticsLabel != null) {
      field = Semantics(
        label: widget.semanticsLabel!,
        textField: true,
        child: field,
      );
    }

    Widget box = AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      curve: WpMotion.defaultCurve,
      decoration: BoxDecoration(
        // `embedded` paints nothing: its host already painted the row. The
        // card variants lift a rung under the pointer; see "the hover lift".
        color: spec.fillAt(hovered: _hovered, palette: palette),
        borderRadius: spec.radius,
      ),
      // Painted over the child, so the stroke can thicken on focus without
      // moving a single pixel of text. See the library docs.
      foregroundDecoration: spec.strokeAt(focused: _hasFocus)
          ? BoxDecoration(
              borderRadius: spec.radius,
              border: Border.all(
                color: spec.strokeColor(focused: _hasFocus, palette: palette),
                width: _hasFocus && spec.focusStroke ? 1.5 : 1,
              ),
            )
          : null,
      child: field,
    );

    if (spec.liftsOnHover) {
      box = MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: box,
      );
    }

    if (widget.maxLength == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [box, _counter(palette)],
    );
  }

  /// The remaining-characters readout, outside the box.
  ///
  /// [InputDecoration]'s own counter renders *inside* the decorated area, so
  /// with the box drawn around it the single field that caps its length
  /// (feedback's comment) stood 69 dp tall against everyone else's 48 and had
  /// its text sitting off-centre. Below the box it reads as what it is — a
  /// note about the field rather than part of it — and the field keeps the
  /// geometry `form_field_geometry_consistency_test.dart` pins.
  Widget _counter(_WpTextFieldPalette palette) => Padding(
    padding: const EdgeInsets.only(top: WpSpacing.xxs),
    // [InputDecorator] announces its own counter as a live region while the
    // field has focus. Moving the readout out of the decoration would have
    // dropped that, so it is restored here: a screen-reader user typing
    // towards the limit still hears the count as it changes.
    child: Semantics(
      container: true,
      liveRegion: _hasFocus,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => Text(
          // Graphemes, the same unit LengthLimitingTextInputFormatter
          // enforces in — so the readout cannot disagree with the limit it
          // reports.
          '${value.text.characters.length}/${widget.maxLength}',
          style: TextStyle(
            fontSize: WpTypography.small,
            color: palette.textMuted,
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Resolved tokens
// ---------------------------------------------------------------------------

/// The field's colours for one theme, resolved once instead of ternary by
/// ternary inside `build`.
@immutable
class _WpTextFieldPalette {
  const _WpTextFieldPalette({
    required this.surface,
    required this.cardFill,
    required this.cardFillHover,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
  });

  /// The opaque writing surface, for the variants that stand on an already
  /// opaque ground (`heading`, `form`).
  final Color surface;

  /// The shared card material, for the variants that own a region of a panel
  /// and let the app's one ambient show through (`passage`, `bare`).
  final Color cardFill;

  /// One rung up the same ladder — the hover lift, and the app's declared
  /// depth source. Never a hand-rolled alpha: both rungs are tokens.
  final Color cardFillHover;

  final Color border;
  final Color textPrimary;
  final Color textMuted;

  /// The focused stroke of every variant that draws one — the single focus
  /// signal.
  final Color accent;

  /// The one palette. Named `_dark` while it had a `_light` twin and an
  /// `of(Brightness)` resolver between them; both went with the light
  /// stack (2026-08-11). The twin was not merely unreachable — it was
  /// wrong for this app, painting white on the accent fill where the
  /// dark palette paints the near-black background colour.
  static const _palette = _WpTextFieldPalette(
    surface: WpColors.surfaceVariant,
    cardFill: WpColors.cardFill,
    cardFillHover: WpColors.cardFillElevated,
    border: WpColors.borderSubtle,
    textPrimary: WpColors.textPrimary,
    textMuted: WpColors.textMuted,
    accent: WpColors.accent,
  );
}

/// What a variant's box is made of.
///
/// The discriminator is Ticket 08's, applied to fields: what does this thing
/// stand on? On an opaque dialog or header, a 3–5 % tint is a rounding error
/// and the field needs a real fill; on a panel that paints no ground of its
/// own, the translucent card material is what lets the app's one ambient show
/// through. See "What the surfaces are made of" in the library docs.
enum _WpFieldMaterial {
  /// `WpColors.surfaceVariant` — `heading`, `form`.
  opaque,

  /// `WpColors.cardFill`, lifting to `cardFillElevated` on hover — `passage`,
  /// `bare`.
  card,

  /// Nothing at all: the host row already painted it — `embedded`.
  none,
}

/// What a variant's contour is while nothing is happening to it.
enum _WpFieldRestingStroke {
  /// A visible 1 dp `borderSubtle` hairline — the box a form field draws
  /// around itself.
  hairline,

  /// A 1 dp stroke painted in `Colors.transparent`: invisible, but present,
  /// so the focus stroke animates a colour instead of appearing out of
  /// nothing. [WpSearchField]'s idiom.
  invisible,

  /// No `foregroundDecoration` at all. The focus stroke, where there is one,
  /// then snaps in rather than fading — deliberate, see the library docs.
  none,
}

/// Everything [WpTextFieldVariant] actually decides.
@immutable
class _WpTextFieldSpec {
  const _WpTextFieldSpec({
    required this.fontSize,
    required this.fontWeight,
    required this.lineHeight,
    required this.padding,
    required this.material,
    required this.restingStroke,
    required this.rounded,
    required this.multiline,
    required this.fillsItsBox,
    this.focusStroke = true,
    this.linesFromCallSite = false,
  });

  final double fontSize;
  final FontWeight fontWeight;

  /// `null` on the single-line variant: a forced line height on a one-line
  /// title only fights the box's own vertical centring.
  final double? lineHeight;

  final EdgeInsets padding;

  /// What the box is filled with — the axis that used to be a `filled` bool
  /// back when there was only one fill to be had.
  final _WpFieldMaterial material;

  /// What the contour is at rest. Decoupled from [rounded] in Ticket 09:
  /// `passage` drops its hairline and keeps its 8 dp corner, which the old
  /// single `bordered` flag made impossible to express.
  final _WpFieldRestingStroke restingStroke;

  /// Square only where the field *is* the surface — a rounded corner there
  /// would imply a card floating on something else.
  final bool rounded;

  /// Takes Enter as a newline rather than as submit. Ignored where
  /// [linesFromCallSite] holds — there the line count decides it.
  final bool multiline;

  /// Expands to the height it is given instead of growing with its content.
  final bool fillsItsBox;

  /// Whether focus is shown by this field's own contour. False only on
  /// `embedded`, where the one contour on the row belongs to the host and a
  /// second accent inside it would be two markings for one state.
  final bool focusStroke;

  /// `minLines`/`maxLines` come from the call site, because how much room a
  /// *value* needs is not a property of the field family. See the library
  /// docs on optical vs. functional parameters.
  final bool linesFromCallSite;

  /// Only the card variants lift under the pointer: the opaque ones still
  /// carry a resting hairline, so they never lost the affordance the lift is
  /// there to replace.
  bool get liftsOnHover => material == _WpFieldMaterial.card;

  BorderRadius get radius => rounded ? WpRadius.borderSm : BorderRadius.zero;

  /// The box's fill in this state — `null` where the host already painted it.
  Color? fillAt({
    required bool hovered,
    required _WpTextFieldPalette palette,
  }) => switch (material) {
    _WpFieldMaterial.opaque => palette.surface,
    _WpFieldMaterial.card => hovered ? palette.cardFillHover : palette.cardFill,
    _WpFieldMaterial.none => null,
  };

  /// Whether a stroke is painted at all in this state — the single source the
  /// one paint site in `build` asks, so the focused look of every variant that
  /// has one is literally the same three lines of code and cannot drift into a
  /// second, parallel focus treatment.
  bool strokeAt({required bool focused}) =>
      restingStroke != _WpFieldRestingStroke.none || (focusStroke && focused);

  /// And what colour that stroke is. `Colors.transparent` is the resting
  /// value of [_WpFieldRestingStroke.invisible] — a real stroke that happens
  /// to be see-through, so [AnimatedContainer] has something to tween from.
  Color strokeColor({
    required bool focused,
    required _WpTextFieldPalette palette,
  }) {
    if (focused && focusStroke) return palette.accent;
    return restingStroke == _WpFieldRestingStroke.hairline
        ? palette.border
        : Colors.transparent;
  }

  TextStyle textStyle(Color color) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: lineHeight,
    color: color,
  );

  /// 16 dp/700, single line, and the tight 8/4 inset that keeps the title on
  /// the same baseline it occupies when idle, inside a header row it shares
  /// with an avatar, a timestamp and six actions.
  static const _heading = _WpTextFieldSpec(
    fontSize: WpTypography.heading,
    fontWeight: FontWeight.w700,
    lineHeight: null,
    padding: EdgeInsets.symmetric(
      horizontal: WpSpacing.xs,
      vertical: WpSpacing.xxs,
    ),
    material: _WpFieldMaterial.opaque,
    restingStroke: _WpFieldRestingStroke.hairline,
    rounded: true,
    multiline: false,
    fillsItsBox: false,
  );

  /// Prose metrics: 16 dp at 1.65, the measure the History panel already caps
  /// at 720 dp (~85 characters) for exactly this size. Card material and no
  /// resting contour since Ticket 09 — a transcript is what the reader came
  /// for, and a hairline all the way around it frames the reading.
  static const _passage = _WpTextFieldSpec(
    fontSize: WpTypography.heading,
    fontWeight: FontWeight.w400,
    lineHeight: 1.65,
    padding: EdgeInsets.all(WpSpacing.sm),
    material: _WpFieldMaterial.card,
    restingStroke: _WpFieldRestingStroke.invisible,
    rounded: true,
    multiline: true,
    fillsItsBox: false,
  );

  /// The same prose metrics and the same material as [_passage] — one writing
  /// surface, one text size, one fill — with the resting stroke gone entirely
  /// and the inset opened up to 24 dp, because here the padding is the only
  /// thing holding the text off the panel edge.
  static const _bare = _WpTextFieldSpec(
    fontSize: WpTypography.heading,
    fontWeight: FontWeight.w400,
    lineHeight: 1.65,
    padding: EdgeInsets.all(WpSpacing.xl),
    material: _WpFieldMaterial.card,
    restingStroke: _WpFieldRestingStroke.none,
    rounded: false,
    multiline: true,
    fillsItsBox: true,
  );

  /// 13 dp, and the inset that *is* the field's height: 14 dp above and below
  /// a 20 dp line puts the resting box at exactly 48 dp — the touch-target
  /// floor and [WpSearchField]'s height — without a `SizedBox` to clip
  /// against once the text scaler grows the line. 16 dp horizontal is the
  /// same inset the search field puts in front of its glyph.
  static const _form = _WpTextFieldSpec(
    fontSize: WpTypography.body,
    fontWeight: FontWeight.w400,
    lineHeight: null,
    padding: EdgeInsets.symmetric(
      horizontal: WpSpacing.md,
      vertical: WpSpacing.sm + 2,
    ),
    material: _WpFieldMaterial.opaque,
    restingStroke: _WpFieldRestingStroke.hairline,
    rounded: true,
    multiline: false,
    fillsItsBox: false,
    linesFromCallSite: true,
  );

  /// [_form] with the box handed back to the host: no fill, no stroke, no
  /// radius. The horizontal inset drops to the 12 dp its host row reads its
  /// own text at, so the note does not shift sideways when edit mode opens;
  /// the vertical inset stays [_form]'s, so the row still stands 48 dp tall
  /// and its save/cancel buttons keep their full touch target.
  static const _embedded = _WpTextFieldSpec(
    fontSize: WpTypography.body,
    fontWeight: FontWeight.w400,
    lineHeight: null,
    padding: EdgeInsets.symmetric(
      horizontal: WpSpacing.sm,
      vertical: WpSpacing.sm + 2,
    ),
    material: _WpFieldMaterial.none,
    restingStroke: _WpFieldRestingStroke.none,
    rounded: false,
    multiline: false,
    fillsItsBox: false,
    focusStroke: false,
    linesFromCallSite: true,
  );

  static _WpTextFieldSpec of(WpTextFieldVariant variant) => switch (variant) {
    WpTextFieldVariant.heading => _heading,
    WpTextFieldVariant.passage => _passage,
    WpTextFieldVariant.form => _form,
    WpTextFieldVariant.embedded => _embedded,
    WpTextFieldVariant.bare => _bare,
  };
}
