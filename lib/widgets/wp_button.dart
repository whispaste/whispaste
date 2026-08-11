/// WpButton — the app's single push-button.
///
/// One component, one look: every place that lets the user *trigger an action*
/// routes through here — dialog footers, settings rows, empty-state CTAs,
/// toolbars. The gradient hero CTA ([WpHeroButton]) stays a separate, louder
/// step above this ladder; icon-only affordances stay [IconButton].
///
/// ## Why this exists
///
/// The app used to place raw `ElevatedButton` / `FilledButton` /
/// `OutlinedButton` / `TextButton` instances directly, each patching its own
/// `styleFrom(...)` where the theme didn't fit. That produced four dialects of
/// the same three sentences: two different red alphas for "destructive", a
/// hand-built spinner-instead-of-icon in one place and a spinner *next to* the
/// label in another (which makes the button jump in width while it works), and
/// disabled states that were sometimes a token swap and sometimes a blanket
/// opacity.
///
/// ## The three axes
///
/// [WpButtonVariant] is *hierarchy* (how loud), [WpButtonTone] is *meaning*
/// (which colour), [WpButtonSize] is *density* (which slot). They are
/// deliberately orthogonal rather than nine named classes: `oom_recovery_dialog`
/// already switches hierarchy at runtime, and with separate classes that needs
/// a ternary over two widget trees.
///
/// ## One highlight per state
///
/// This is the [WpDropdown] lesson read backwards. Material draws its own wash
/// for hover, press *and* focus; the app draws focus itself with a [WpFocusRing]
/// outside the control. Left alone the two stack up and a focused button carries
/// two markings for one state. So the button's `overlayColor` answers for hover
/// and press only and returns transparent for focus — the ring, sharing the very
/// same [FocusNode], is the single focus signal.
///
/// Hover and press are the *same* 6 % / 12 % tint steps the accent tokens use
/// everywhere else. On the filled [WpButtonVariant.primary] the wash is keyed to
/// the foreground colour instead of the tone: a tone-tinted wash on a
/// tone-coloured fill would be invisible.
///
/// The same "invisible on its own fill" problem hits the ring, one step harder.
/// [WpFocusRing] paints the accent by default, which is right for everything
/// that wraps an *unfilled* control — a row, a chip, an outlined trigger. A
/// filled button is a solid block of its tone, so an accent ring 2 dp off an
/// accent fill stops reading as focus and starts reading as a second border:
/// two concentric outlines, a target rather than an indicator. So
/// [WpButtonVariant.primary] — and only it — overrides the ring to
/// `textPrimary`, the one colour that is neither any tone's fill nor the page
/// behind it, and is therefore unambiguous on cyan, on grey and on red in both
/// themes. [WpButtonVariant.secondary] and [WpButtonVariant.ghost] keep the
/// accent ring: they have no fill for it to collide with.
///
/// Disabled is a token change (`textMuted` on `surfaceVariant`, outline back to
/// `borderSubtle`), never an opacity veil over live colours — the same rule the
/// dropdown's unselectable rows follow. ([WpHeroButton] keeps its own 50 %
/// opacity language; it is a different, louder component.)
///
/// That swap on its own leaves the filled variant without a shape, though.
/// Cards across the app are tinted with the very `surfaceVariant` the disabled
/// fill uses (`paste_capability_indicator` and friends run it at 50 %), and on
/// light that puts fill and card 1.01:1 apart: the block dissolves and only the
/// muted label floats there. [isLoading] takes the same path, so it is not only
/// barred buttons that vanish — a submit button disappears at the moment it
/// starts working. Hence the disabled outline is not the secondary variant's
/// alone: [WpButtonVariant.primary] borrows it while disabled and keeps a
/// contour on whatever surface it was dropped onto. Darkening the disabled fill
/// was the alternative and costs more than it pays — it would spend label
/// contrast (`textMuted` falls from 4.9:1 to 4.2:1 on light's next step up) and
/// hand a disabled button the neutral tone's *enabled* fill.
/// [WpButtonVariant.ghost] stays boxless: it has no silhouette to lose.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

// ---------------------------------------------------------------------------
// Axes
// ---------------------------------------------------------------------------

/// How loud the button is — the visual weight of the action it triggers.
enum WpButtonVariant {
  /// Filled. The one action a surface wants you to take.
  primary,

  /// Outlined. A real alternative to the primary action, not a footnote.
  secondary,

  /// Label only. Dismissals, "later", inline extras.
  ghost,
}

/// What the button *means* — orthogonal to [WpButtonVariant].
enum WpButtonTone {
  /// Brand cyan. The default: an ordinary action.
  accent,

  /// Off-brand grey, for a secondary action sitting next to an accent one
  /// where a second brand-coloured control would flatten the hierarchy.
  neutral,

  /// Destructive. Deletes, resets, quits.
  danger,
}

/// Which slot the button sits in.
enum WpButtonSize {
  /// 48px control (dialog footers, page CTAs, forms, toolbars).
  ///
  /// 48 because that is what everything a button stands *beside* already is:
  /// [WpSearchField] settles there, `WpTextFieldVariant.form` is held open
  /// there by its own padding, `WpDropdown` declares it outright, and all
  /// three of them cite `WpLayout.minTouchTarget` for it. This button
  /// was the one control in the family still painting 40 and letting
  /// Material's tap-target padding claim the last 8 — which is a hit target,
  /// not a silhouette. Every row that put a button next to a field centred
  /// that difference into 4px of air above and below the button, and it read
  /// as a button that came out undersized rather than as a decision.
  standard,

  /// 32px control for a *secondary, inline* action: a ghost link under a
  /// field list, a toast's action, a footer reset, a hint's "fix this".
  /// Hit target equals its visual box.
  ///
  /// Never for a control that shares a line with a field, a search box or
  /// another button — those all stand at [standard], and a 32 next to a 48
  /// reads as a mistake rather than as a hierarchy. The call sites that pass
  /// this all sit on a line of their own.
  dense,
}

// ---------------------------------------------------------------------------
// Button
// ---------------------------------------------------------------------------

class WpButton extends StatefulWidget {
  const WpButton({
    super.key,
    required this.label,
    required this.variant,
    required this.onPressed,
    this.tone = WpButtonTone.accent,
    this.size = WpButtonSize.standard,
    this.icon,
    this.isLoading = false,
    this.expanded = false,
    this.autofocus = false,
    this.disabledTooltip,
  });

  /// Already localized, single-line. Long labels ellipsize rather than wrap:
  /// a button that grows a second line has outgrown being a button.
  final String label;

  /// No default on purpose — hierarchy is a decision, not a fallback.
  final WpButtonVariant variant;

  /// `null` disables the button.
  final VoidCallback? onPressed;

  final WpButtonTone tone;
  final WpButtonSize size;

  /// Leading glyph. [IconData] rather than a [Widget] so size and colour stay
  /// the component's business and can't drift per call site.
  final IconData? icon;

  /// Shows a spinner **in place of** [icon] and disables the button.
  ///
  /// Replacing rather than adding keeps the button's width fixed while it
  /// works; an extra slot would make it jump the moment work starts. Without
  /// an [icon] the spinner still takes the leading slot, so the label shifts
  /// once — that is the honest cost of announcing work at all.
  final bool isLoading;

  /// Fills the parent's width — replaces wrapping call sites in
  /// `SizedBox(width: double.infinity)`.
  final bool expanded;

  final bool autofocus;

  /// Explains *why* a disabled button can't be pressed. Shown only while the
  /// button is actually disabled, like [WpDropdownItem.disabledTooltip].
  final String? disabledTooltip;

  @override
  State<WpButton> createState() => _WpButtonState();
}

class _WpButtonState extends State<WpButton> {
  /// Shared with [WpFocusRing] in external-node mode: the ring only *listens*,
  /// so the button keeps its single focus stop and Material's own Enter/Space
  /// activation.
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpButton');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isDisabled => widget.onPressed == null || widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = _WpButtonPalette.of(Theme.of(context).brightness);
    final spec = _WpButtonSpec.of(widget.size);
    final tone = palette.toneOf(widget.tone);

    final isPrimary = widget.variant == WpButtonVariant.primary;
    final contentColor = _isDisabled
        ? palette.disabledContent
        : (isPrimary ? tone.onFill : tone.content);

    // On a filled button the wash has to key off the *foreground*: 6 % of the
    // fill's own hue on top of that fill is no signal at all.
    final hoverWash = isPrimary
        ? contentColor.withValues(alpha: 0.06)
        : tone.hoverWash;
    final pressedWash = isPrimary
        ? contentColor.withValues(alpha: 0.12)
        : tone.pressedWash;

    // The outline is the secondary variant's whole shape — and a disabled
    // filled button's only one, because its `surfaceVariant` fill is a whisper
    // away from the surfaces the app puts it on. See the library docs for why
    // the contour carries this rather than a darker fill.
    final BorderSide? side = switch (widget.variant) {
      WpButtonVariant.secondary => BorderSide(
        color: _isDisabled ? palette.disabledBorder : tone.border,
      ),
      WpButtonVariant.primary when _isDisabled => BorderSide(
        color: palette.disabledBorder,
      ),
      _ => null,
    };

    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        isPrimary
            ? (_isDisabled ? palette.disabledFill : tone.fill)
            : Colors.transparent,
      ),
      foregroundColor: WidgetStatePropertyAll(contentColor),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return pressedWash;
        if (states.contains(WidgetState.hovered)) return hoverWash;
        // Focus deliberately falls through to transparent — WpFocusRing owns
        // it. See the library docs.
        return Colors.transparent;
      }),
      // Left null where the variant has no outline to resolve at all, rather
      // than pinning it to an explicit "none".
      side: side == null ? null : WidgetStatePropertyAll(side),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: spec.radius),
      ),
      padding: WidgetStatePropertyAll(spec.paddingFor(widget.variant)),
      textStyle: WidgetStatePropertyAll(spec.textStyle),
      // Width floor of 0 instead of Material's 64: a dense button in a settings
      // row is as wide as its label, and `expanded` handles the other extreme.
      minimumSize: WidgetStatePropertyAll(Size(0, spec.height)),
      // Both heights are fixed numbers in this file; the platform's density
      // adjustment would silently shave 4px off them on desktop.
      visualDensity: VisualDensity.standard,
      tapTargetSize: spec.tapTargetSize,
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: WpMotion.durationFor(context, WpMotion.fast),
    );

    final content = _WpButtonContent(
      label: widget.label,
      icon: widget.icon,
      isLoading: widget.isLoading,
      color: contentColor,
      spec: spec,
    );

    final onPressed = _isDisabled ? null : widget.onPressed;

    final button = switch (widget.variant) {
      WpButtonVariant.primary => FilledButton(
        onPressed: onPressed,
        style: style,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        child: content,
      ),
      WpButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        style: style,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        child: content,
      ),
      WpButtonVariant.ghost => TextButton(
        onPressed: onPressed,
        style: style,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        child: content,
      ),
    };

    Widget result = WpFocusRing(
      focusNode: _focusNode,
      radius: spec.ringRadius,
      // Only the filled variant needs its own ring colour — see the library
      // docs; `null` keeps WpFocusRing's accent default everywhere else.
      ringColor: isPrimary ? palette.focusRing : null,
      insets: spec.ringInsets,
      child: button,
    );

    if (widget.expanded) {
      result = SizedBox(width: double.infinity, child: result);
    }

    if (_isDisabled && widget.disabledTooltip != null) {
      // Outside everything else: a disabled button swallows no pointer events,
      // so the tooltip's own MouseRegion is what makes the explanation
      // reachable at all.
      result = Tooltip(message: widget.disabledTooltip!, child: result);
    }

    return result;
  }
}

// ---------------------------------------------------------------------------
// Label row
// ---------------------------------------------------------------------------

/// The leading slot plus the label.
///
/// Split out so the spinner/icon swap is one expression instead of three
/// branches inlined into every variant's `child`.
class _WpButtonContent extends StatelessWidget {
  const _WpButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.color,
    required this.spec,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final Color color;
  final _WpButtonSpec spec;

  @override
  Widget build(BuildContext context) {
    final Widget? leading = isLoading
        ? SizedBox.square(
            dimension: spec.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: spec.spinnerStroke,
              color: color,
            ),
          )
        : (icon == null ? null : Icon(icon, size: spec.iconSize, color: color));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, SizedBox(width: spec.gap)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resolved tokens
// ---------------------------------------------------------------------------

/// One [WpButtonTone] resolved to colours.
@immutable
class _WpButtonToneColors {
  const _WpButtonToneColors({
    required this.fill,
    required this.onFill,
    required this.content,
    required this.border,
    required this.hoverWash,
    required this.pressedWash,
  });

  /// Background of the [WpButtonVariant.primary] button.
  final Color fill;

  /// Label/icon colour on top of [fill].
  final Color onFill;

  /// Label/icon colour of the unfilled variants.
  final Color content;

  /// Outline of [WpButtonVariant.secondary].
  ///
  /// Only [WpButtonTone.danger] tints it. Accent and neutral keep the neutral
  /// `borderSubtle` the outlined buttons already use across the app: a cyan
  /// outline on every secondary button would spend the accent on structure
  /// instead of on meaning, whereas a destructive control has to be legible as
  /// destructive before its label is read.
  final Color border;

  final Color hoverWash;
  final Color pressedWash;
}

/// The button's colours for one theme, resolved once instead of ternary by
/// ternary inside `build`.
@immutable
class _WpButtonPalette {
  const _WpButtonPalette({
    required this.disabledContent,
    required this.disabledFill,
    required this.disabledBorder,
    required this.focusRing,
    required this.accent,
    required this.neutral,
    required this.danger,
  });

  /// Disabled is a token swap, not a veil — see the library docs.
  final Color disabledContent;
  final Color disabledFill;

  /// Worn by every disabled variant that has a box: the secondary one, which
  /// had an outline to begin with, *and* the primary one, whose [disabledFill]
  /// is too close to the app's tinted cards to draw its own edge.
  final Color disabledBorder;

  /// Focus ring of the filled variant, one colour for all three tones.
  ///
  /// Deliberately *not* per tone: a ring that changed hue with the button
  /// would be a second tone signal, and on a red or grey fill it would have to
  /// solve the same collision again. `textPrimary` sits far from every fill
  /// (cyan / slate / salmon in dark, teal / light grey / red in light) and far
  /// from the page behind the button, so one value answers all six cases.
  final Color focusRing;

  final _WpButtonToneColors accent;
  final _WpButtonToneColors neutral;
  final _WpButtonToneColors danger;

  _WpButtonToneColors toneOf(WpButtonTone tone) => switch (tone) {
    WpButtonTone.accent => accent,
    WpButtonTone.neutral => neutral,
    WpButtonTone.danger => danger,
  };

  static const _dark = _WpButtonPalette(
    disabledContent: WpColors.textMuted,
    disabledFill: WpColors.surfaceVariant,
    disabledBorder: WpColors.borderSubtle,
    focusRing: WpColors.textPrimary,
    accent: _WpButtonToneColors(
      fill: WpColors.accent,
      // The theme's `onPrimary` — deep navy on cyan, ~11:1. Several call sites
      // hand-set white here today, which is ~1.9:1 on this accent.
      onFill: WpColors.background,
      content: WpColors.accent,
      border: WpColors.borderSubtle,
      hoverWash: WpColors.accentRowHover,
      pressedWash: WpColors.accentActiveFill,
    ),
    neutral: _WpButtonToneColors(
      // A step above `surfaceVariant`, which is what disabled fills use — so a
      // neutral primary still reads as enabled.
      fill: WpColors.active,
      onFill: WpColors.textPrimary,
      content: WpColors.textSecondary,
      border: WpColors.borderSubtle,
      hoverWash: WpColors.mutedRowHover,
      pressedWash: WpColors.mutedActiveFill,
    ),
    danger: _WpButtonToneColors(
      fill: WpColors.error,
      onFill: WpColors.background,
      content: WpColors.error,
      border: WpColors.errorBorder30,
      hoverWash: WpColors.errorRowHover,
      pressedWash: WpColors.errorActiveFill,
    ),
  );

  static const _light = _WpButtonPalette(
    disabledContent: WpColors.textMuted,
    disabledFill: WpColors.surfaceVariant,
    disabledBorder: WpColors.borderSubtle,
    focusRing: WpColors.textPrimary,
    accent: _WpButtonToneColors(
      fill: WpColors.accent,
      onFill: Color(0xFFFFFFFF),
      content: WpColors.accent,
      border: WpColors.borderSubtle,
      hoverWash: WpColors.accentRowHover,
      pressedWash: WpColors.accentActiveFill,
    ),
    neutral: _WpButtonToneColors(
      fill: WpColors.active,
      onFill: WpColors.textPrimary,
      content: WpColors.textSecondary,
      border: WpColors.borderSubtle,
      hoverWash: WpColors.mutedRowHover,
      pressedWash: WpColors.mutedActiveFill,
    ),
    danger: _WpButtonToneColors(
      fill: WpColors.error,
      onFill: Color(0xFFFFFFFF),
      content: WpColors.error,
      border: WpColors.errorBorder30,
      hoverWash: WpColors.errorRowHover,
      pressedWash: WpColors.errorActiveFill,
    ),
  );

  static _WpButtonPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;
}

/// Everything [WpButtonSize] actually decides.
@immutable
class _WpButtonSpec {
  const _WpButtonSpec({
    required this.height,
    required this.radius,
    required this.ringRadius,
    required this.fontSize,
    required this.fontWeight,
    required this.iconSize,
    required this.gap,
    required this.spinnerStroke,
    required this.paddingX,
    required this.ghostPaddingX,
    required this.paddingY,
    required this.tapTargetSize,
    required this.ringInsets,
  });

  final double height;
  final BorderRadius radius;
  final double ringRadius;
  final double fontSize;
  final FontWeight fontWeight;
  final double iconSize;

  /// Between the leading slot and the label.
  final double gap;
  final double spinnerStroke;

  final double paddingX;

  /// A ghost button has no box, so the wide inset that gives a filled button
  /// its shape only spaces it away from its neighbours here.
  final double ghostPaddingX;
  final double paddingY;

  final MaterialTapTargetSize tapTargetSize;

  /// What [tapTargetSize] adds to the button's *reported* size without
  /// painting it — [WpFocusRing.insets].
  ///
  /// [MaterialTapTargetSize.padded] grows the reported box to 48 dp in any
  /// dimension below it, so a 40 dp-high button hands the ring a 48 dp box and
  /// the glow drifts 4 dp further out top and bottom than left and right (the
  /// label already carries the width past 48). Declaring the difference here
  /// puts the ring back on the visible contour.
  final EdgeInsets ringInsets;

  EdgeInsets paddingFor(WpButtonVariant variant) => EdgeInsets.symmetric(
    horizontal: variant == WpButtonVariant.ghost ? ghostPaddingX : paddingX,
    vertical: paddingY,
  );

  /// `fontFamily` is spelled out because `_ButtonStyleButton` replaces the
  /// ambient [DefaultTextStyle] wholesale, which severs `ThemeData.fontFamily`
  /// — the same reason `theme.dart`'s button themes name it.
  TextStyle get textStyle => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: -0.1,
    fontFamily: 'Inter',
  );

  /// Vertical inset re-derived for the taller box; horizontal inset
  /// deliberately not.
  ///
  /// 14 dp is what `WpTextFieldVariant.form` uses to hold a single line open
  /// at exactly 48, so the button and the field a user meets on the same
  /// screen now space their content the same way rather than one of them
  /// wearing the other's number. Keeping `sm` (12) would have been the taller
  /// box with the old padding poured into it — the label would sit in a
  /// looser box without the box's own rhythm changing with it.
  ///
  /// `paddingX` stays at `xl` on purpose, and that is not the same omission:
  /// it is the *width* of every button in the app, and 48 is a claim about
  /// heights lining up with fields, not about buttons needing more room
  /// sideways. Widening ~60 call sites — several of them in dialogs with two
  /// buttons on one line — would risk overflow to fix nothing anyone
  /// reported.
  static final _standard = _WpButtonSpec(
    height: WpLayout.minTouchTarget,
    radius: WpRadius.borderSm,
    ringRadius: WpRadius.sm,
    fontSize: WpTypography.body,
    fontWeight: FontWeight.w600,
    iconSize: WpIconSize.sm,
    gap: WpSpacing.xs,
    spinnerStroke: 2,
    paddingX: WpSpacing.xl,
    ghostPaddingX: WpSpacing.md,
    paddingY: 14,
    // Kept for the one thing it still does: a very short label ("OK") can
    // leave the button under 48 dp *wide*, and this pads the hit box out.
    // Vertically it is now a no-op — the painted box is already the minimum.
    tapTargetSize: MaterialTapTargetSize.padded,
    // Zero, because `padded` no longer inflates the height: the box paints
    // the 48 it reports. The 4 dp this used to subtract was exactly that
    // inflation ((48 - 40) / 2), and leaving it would now pull the focus ring
    // *inside* the button's contour on every button in the app.
    ringInsets: EdgeInsets.zero,
  );

  static final _dense = _WpButtonSpec(
    // The shared height of everything that stands in a row's trailing slot —
    // key caps and the mic-permission chip carry the same token.
    height: WpLayout.denseControlHeight,
    radius: WpRadius.borderSm,
    ringRadius: WpRadius.sm,
    fontSize: WpTypography.small,
    fontWeight: FontWeight.w600,
    iconSize: WpIconSize.xs,
    gap: WpSpacing.xxs,
    spinnerStroke: 1.6,
    paddingX: WpSpacing.sm,
    ghostPaddingX: WpSpacing.xs,
    paddingY: WpSpacing.xxs,
    // Padding the hit box back to 48 would make a 32px control claim the
    // height of a standard one and break the row it was made to fit.
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // shrinkWrap reports exactly what it paints.
    ringInsets: EdgeInsets.zero,
  );

  static _WpButtonSpec of(WpButtonSize size) => switch (size) {
    WpButtonSize.standard => _standard,
    WpButtonSize.dense => _dense,
  };
}
