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
///  * [WpTextFieldVariant.heading] and [WpTextFieldVariant.passage] sit in a
///    document flow among other sections — a header row with an avatar,
///    metadata and actions; a panel that also carries tags, notes and a word
///    count. Nothing there says "this block is a field now" unless the field
///    says it itself, and both of them appear only when edit mode opens, so
///    the box is also the mode indicator. They are boxed, per `lib/DESIGN.md`
///    ("Inputs / Fields"): filled surface, 8 dp radius, 1 dp subtle hairline.
///  * [WpTextFieldVariant.bare] *is* the surface. Nothing else shares the
///    region below the Notes divider, so a border would only draw a box
///    inside a box, and the writing area would end up smaller than the space
///    it owns. It keeps the fill — the writing surface is the same colour
///    everywhere — and drops only the stroke.
///
/// The axis carries typography and inset with it rather than exposing them,
/// because free `fontSize`/`contentPadding` parameters would reproduce exactly
/// the three-different-answers drift the component exists to end. That is also
/// why `heading` and `passage` are two variants and not one boxed variant with
/// a typography knob: a knob would permit "prose at title weight", which is
/// not a decision anyone should be able to take at a call site.
///
/// There is deliberately no plain 13 dp form-value variant yet. The feedback
/// form and History's per-entry notes box are the call sites that will want
/// one; they are not migrated yet, and an enum value with no user is
/// speculative stock.
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
/// 1.5 dp, and [WpTextFieldVariant.bare], having no contour to move, shows
/// focus by the caret alone. That is the same rule applied honestly, not a
/// second treatment: adding a stroke to `bare` on focus would frame the whole
/// lower half of the Notes panel in accent for as long as the user types.
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
  /// (History's transcript in edit mode). Boxed, multi-line, prose metrics.
  passage,

  /// The surface *is* the field (the Notes editor). No stroke, generous
  /// inset, and it expands to fill the box it is given — so it must be given
  /// a bounded one (an `Expanded`, a `SizedBox`), which is the definition of
  /// owning the surface rather than sitting on it.
  bare,
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
  });

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

  /// Mirror of the one thing the box's appearance depends on. Tracked here so
  /// the field redraws its own stroke — call sites shouldn't have to rebuild
  /// it to keep it honest.
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedNode = FocusNode(debugLabel: 'WpTextField');
    }
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(WpTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _focusNode.removeListener(_onFocusChanged);
    _ownedNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted || _hasFocus == _focusNode.hasFocus) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = _WpTextFieldPalette.of(brightness);
    final spec = _WpTextFieldSpec.of(widget.variant);
    final style = spec.textStyle(palette.textPrimary);

    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      maxLines: spec.multiline ? null : 1,
      expands: spec.fillsItsBox,
      textAlignVertical: spec.fillsItsBox ? TextAlignVertical.top : null,
      keyboardType: spec.multiline ? TextInputType.multiline : null,
      style: style,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: widget.onEditingComplete,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: style.copyWith(color: palette.textMuted),
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

    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      curve: WpMotion.defaultCurve,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: spec.radius,
      ),
      // Painted over the child, so the stroke can thicken on focus without
      // moving a single pixel of text. See the library docs.
      foregroundDecoration: spec.bordered
          ? BoxDecoration(
              borderRadius: spec.radius,
              border: Border.all(
                color: _hasFocus ? palette.accent : palette.border,
                width: _hasFocus ? 1.5 : 1,
              ),
            )
          : null,
      child: field,
    );
  }
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
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
  });

  /// The writing surface itself — the same fill in every variant, bordered or
  /// not, so the two panels' editing areas read as one material.
  final Color surface;

  final Color border;
  final Color textPrimary;
  final Color textMuted;

  /// The focused stroke of the boxed variants — the single focus signal.
  final Color accent;

  static const _dark = _WpTextFieldPalette(
    surface: WpColorsDark.surfaceVariant,
    border: WpColorsDark.borderSubtle,
    textPrimary: WpColorsDark.textPrimary,
    textMuted: WpColorsDark.textMuted,
    accent: WpColorsDark.accent,
  );

  static const _light = _WpTextFieldPalette(
    surface: WpColorsLight.surfaceVariant,
    border: WpColorsLight.borderSubtle,
    textPrimary: WpColorsLight.textPrimary,
    textMuted: WpColorsLight.textMuted,
    accent: WpColorsLight.accent,
  );

  static _WpTextFieldPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;
}

/// Everything [WpTextFieldVariant] actually decides.
@immutable
class _WpTextFieldSpec {
  const _WpTextFieldSpec({
    required this.fontSize,
    required this.fontWeight,
    required this.lineHeight,
    required this.padding,
    required this.bordered,
    required this.multiline,
    required this.fillsItsBox,
  });

  final double fontSize;
  final FontWeight fontWeight;

  /// `null` on the single-line variant: a forced line height on a one-line
  /// title only fights the box's own vertical centring.
  final double? lineHeight;

  final EdgeInsets padding;

  /// Draws a hairline at rest and moves it to the accent on focus.
  final bool bordered;

  /// Takes Enter as a newline rather than as submit.
  final bool multiline;

  /// Expands to the height it is given instead of growing with its content.
  final bool fillsItsBox;

  /// Square when the field *is* the surface — a rounded corner would imply a
  /// card floating on something else.
  BorderRadius get radius => bordered ? WpRadius.borderSm : BorderRadius.zero;

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
    bordered: true,
    multiline: false,
    fillsItsBox: false,
  );

  /// Prose metrics: 16 dp at 1.65, the measure the History panel already caps
  /// at 720 dp (~85 characters) for exactly this size.
  static const _passage = _WpTextFieldSpec(
    fontSize: WpTypography.heading,
    fontWeight: FontWeight.w400,
    lineHeight: 1.65,
    padding: EdgeInsets.all(WpSpacing.sm),
    bordered: true,
    multiline: true,
    fillsItsBox: false,
  );

  /// The same prose metrics as [_passage] — one writing surface, one text
  /// size — with the stroke dropped and the inset opened up to 24 dp, because
  /// here the padding is the only thing holding the text off the panel edge.
  static const _bare = _WpTextFieldSpec(
    fontSize: WpTypography.heading,
    fontWeight: FontWeight.w400,
    lineHeight: 1.65,
    padding: EdgeInsets.all(WpSpacing.xl),
    bordered: false,
    multiline: true,
    fillsItsBox: true,
  );

  static _WpTextFieldSpec of(WpTextFieldVariant variant) => switch (variant) {
    WpTextFieldVariant.heading => _heading,
    WpTextFieldVariant.passage => _passage,
    WpTextFieldVariant.bare => _bare,
  };
}
