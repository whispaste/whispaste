/// WpDropdown — the app's single value-selection dropdown.
///
/// One component, one look: every place that lets the user pick a *value*
/// from a list routes through here (settings rows, the language picker on
/// onboarding / in Settings → Interface, the feedback form). Action menus
/// (`PopupMenuButton`) are a different interaction and deliberately stay
/// separate.
///
/// ## Why this exists
///
/// The app used to carry two independently styled `DropdownButton` wrappers:
/// a 48px standalone one for the language picker and a 32px dense one for
/// settings rows. They drifted apart in radius, chevron size, menu surface
/// and — most visibly — in how the opened menu marked the current selection.
///
/// ## Why there is no size variant
///
/// Merging the two wrappers left a `WpDropdownSize` enum behind, and the
/// 32px `dense` trigger it offered made every settings row shorter than its
/// neighbours. There is now exactly one trigger: [WpShellTokens.controlHeight]
/// (40, WP-14 §4) tall, [WpRadiusTokens.sm] round, [WpTypography.body] text.
/// Buttons (48) and the search field (44) keep their own heights.
///
/// ## What it fixes in the opened menu
///
/// Material lays every menu row out as a 48px slot whose child is *centred*
/// and intrinsically sized (`_DropdownMenuItemContainer`), and it autofocuses
/// the selected row. With the default `ThemeData.focusColor` that produced a
/// full-bleed grey wash across the selected row *plus* — in the old language
/// picker — a smaller cyan pill floating inside it: two misaligned highlights
/// for one state. Here the two roles are separated instead:
///
/// * **selection** is marked inside the row (accent check glyph + semibold
///   label), never by a background of its own;
/// * **focus / hover** are full-bleed row washes drawn by Material's own
///   InkWell, re-tinted to the accent tint tokens so keyboard navigation
///   through the menu stays visible and on-brand.
///
/// Menu rows keep the full 48px touch target ([WpLayout.minTouchTarget]),
/// the same height the trigger stands at.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------
//
// One trigger, one geometry — see the library docs. WP-14 §4 fixes the closed
// trigger's visible box at 40 px with an 8 px radius. Its tap area is the
// 48 px touch target (`WpLayout.minTouchTarget`): the 4 px above and below
// the box are a transparent `WpTouchTarget` ring that opens the menu.

/// Resting height of the closed trigger (WP-14 §4).
const double _kTriggerHeight = WpShellTokens.controlHeight;

/// Chevron glyph — the same [WpIconSize.sm] every other 48px control puts in
/// its icon slot.
const double _kChevronSize = WpIconSize.sm;

/// Weight of the selected menu row's label — one step above the row's own
/// [TextTheme.bodyLarge] (w400), so the check glyph leads and the weight only
/// seconds it.
const FontWeight _kActiveWeight = FontWeight.w600;

/// Width of the leading check column in the opened menu.
///
/// Reserved on *every* row so labels align whether or not they carry the
/// glyph, and compensated for by [_WpDropdownState._menuWidth] so reserving
/// it never costs label width.
const double _kCheckGutter = WpIconSize.sm + WpSpacing.xs;

/// Width of the trigger's outline. It sits inside the box, so it takes space
/// from the label on each side.
const double _kTriggerBorderWidth = 1;

/// Width a trigger needs to show its widest of [labels] in one piece.
///
/// Measures every label in the trigger's own text style at the ambient text
/// scaler, adds the trigger chrome (the horizontal inset, the gap before the
/// chevron and the chevron itself) and rounds up to the 4 px grid. It is not
/// capped: a caller caps it by the space its row has. Used by settings groups,
/// where all dropdowns of one group must share one width.
double wpDropdownFitWidth(BuildContext context, Iterable<String> labels) {
  final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  const chrome =
      (WpSpacing.sm + _kTriggerBorderWidth) * 2 + WpSpacing.xs + _kChevronSize;
  return ((widest + chrome) / 4).ceil() * 4.0;
}

// ---------------------------------------------------------------------------
// Item model
// ---------------------------------------------------------------------------

/// One selectable entry of a [WpDropdown].
@immutable
class WpDropdownItem<T> {
  const WpDropdownItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.disabledTooltip,
    this.activeKey,
    this.itemKey,
  });

  final T value;

  /// Human-readable, already localized label.
  final String label;

  /// Shown-but-unselectable entries (e.g. a feature this build can't offer)
  /// stay in the list so the option is discoverable; [disabledTooltip]
  /// explains why it can't be picked.
  final bool enabled;
  final String? disabledTooltip;

  /// Attached to this entry's row **only while it is the selected one**, so
  /// tests can pin the active-row treatment without a golden.
  final Key? activeKey;

  /// Stable identifier for this entry's menu row, present whether or not it
  /// is selected (e.g. `settings-section-picker-<sectionId>`).
  final Key? itemKey;
}

// ---------------------------------------------------------------------------
// Dropdown
// ---------------------------------------------------------------------------

class WpDropdown<T> extends StatefulWidget {
  const WpDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.expanded = false,
    this.menuMinWidth,
  });

  /// Currently selected value, or `null` for an unset picker (see [hint]).
  final T? value;

  final List<WpDropdownItem<T>> items;

  /// `null` disables the control.
  final ValueChanged<T?>? onChanged;

  /// Muted placeholder shown while [value] is `null`.
  final String? hint;

  /// Fills the parent's width and ellipsizes long labels — for an [Expanded]
  /// slot or a fixed-width [SizedBox], rather than a trailing settings slot.
  final bool expanded;

  /// Lower bound for the opened menu's width, for triggers narrower than
  /// their longest label. The menu still measures from the trigger when that
  /// is already wider.
  final double? menuMinWidth;

  @override
  State<WpDropdown<T>> createState() => _WpDropdownState<T>();
}

class _WpDropdownState<T> extends State<WpDropdown<T>> {
  /// Shared with [WpFocusRing] in external-node mode: the ring only *listens*,
  /// so the dropdown keeps its single focus stop and its built-in keyboard
  /// handling (space/enter to open, arrows to move, enter to pick).
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpDropdown');

  final GlobalKey _buttonKey = GlobalKey();

  /// Menu width, measured from the button and widened by [_kCheckGutter].
  ///
  /// Material sizes the menu to the button and pads every row by a
  /// hard-coded 16px, so a leading check column would otherwise be paid for
  /// out of the label's own width and truncate the longest entry. Adding the
  /// gutter back keeps the text column exactly as wide as it is today — and
  /// a menu that overhangs its trigger by the checkmark column is the native
  /// desktop pattern anyway. `null` until the first frame is laid out, where
  /// Material's own button-width default applies.
  double? _menuWidth;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _measureMenuWidth() {
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final next = renderObject.size.width + _kCheckGutter;
    if (_menuWidth != null && (_menuWidth! - next).abs() < 0.5) return;
    setState(() => _menuWidth = next);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureMenuWidth();
    });

    final theme = Theme.of(context);
    final palette = _WpDropdownPalette.current();

    // `bodyLarge`, not `titleMedium`: the trigger shows a *value*, exactly as
    // a text field does, and 13/w400 is what `WpTextFieldVariant.form` and
    // `WpSearchField` render their own value at. It is also the role
    // `SettingRow` draws its label in, so the two halves of a settings row
    // finally read as one line rather than as a caption beside a heading.
    final labelStyle =
        theme.textTheme.bodyLarge?.copyWith(color: palette.textPrimary) ??
        TextStyle(color: palette.textPrimary);

    final surface = palette.surface;
    final border = palette.border;
    final textSecondary = palette.textSecondary;
    final textMuted = palette.textMuted;
    final accent = palette.accent;
    final menuSurface = palette.menuSurface;
    final focusWash = palette.focusWash;
    final hoverWash = palette.hoverWash;
    final radius = BorderRadius.circular(WpRadiusTokens.sm);

    final dropdown = DropdownButton<T>(
      key: _buttonKey,
      value: widget.value,
      items: [
        for (final item in widget.items)
          DropdownMenuItem<T>(
            key: item.itemKey,
            value: item.value,
            enabled: item.enabled,
            child: _WpDropdownRow(
              key: item.value == widget.value ? item.activeKey : null,
              label: item.label,
              isActive: item.value == widget.value,
              enabled: item.enabled,
              disabledTooltip: item.disabledTooltip,
              style: labelStyle,
              activeWeight: _kActiveWeight,
              accent: accent,
              textMuted: textMuted,
            ),
          ),
      ],
      // Without this the *trigger* would render the menu row itself, check
      // glyph and all. The trigger shows the bare label instead.
      selectedItemBuilder: (context) => [
        for (final item in widget.items)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
      ],
      onChanged: widget.onChanged == null
          ? null
          : (value) {
              HapticFeedback.selectionClick();
              widget.onChanged!(value);
            },
      hint: widget.hint == null
          ? null
          : Text(
              widget.hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(color: textMuted),
            ),
      isExpanded: widget.expanded,
      style: labelStyle,
      // Inset lives on the button, not on the frame around it: Material
      // anchors the menu to the *button's* box, so padding on the frame
      // would leave the frame's own edges peeking out around the open menu
      // — and it would inset the hover/focus ink from the frame as well.
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      itemHeight: WpLayout.minTouchTarget,
      menuWidth: _menuWidth == null
          ? null
          : math.max(_menuWidth!, widget.menuMinWidth ?? 0),
      dropdownColor: menuSurface,
      borderRadius: radius,
      // Keyboard focus is drawn by WpFocusRing outside the control, the way
      // every other custom control in the app draws it.
      focusColor: Colors.transparent,
      focusNode: _focusNode,
      icon: Padding(
        padding: const EdgeInsetsDirectional.only(start: WpSpacing.xs),
        child: Icon(
          LucideIcons.chevronDown,
          size: _kChevronSize,
          color: textSecondary,
        ),
      ),
    );

    // loam-ignore: a11y-interactive-semantics – the wrapped child keeps its own role and label; WpTouchTarget only enlarges the tap area and is excluded from semantics (see wp_touch_target.dart).
    return WpTouchTarget(
      onTap: widget.onChanged == null ? null : _openMenu,
      child: WpFocusRing(
        focusNode: _focusNode,
        radius: WpRadiusTokens.sm,
        child: Container(
          height: _kTriggerHeight,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: radius,
            border: Border.all(color: border, width: _kTriggerBorderWidth),
          ),
          child: DropdownButtonHideUnderline(
            // Re-tints the row washes of the opened menu (Material captures the
            // themes from this context for the menu route) as well as the
            // trigger's own hover ink.
            child: Theme(
              data: theme.copyWith(
                focusColor: focusWash,
                hoverColor: hoverWash,
              ),
              child: dropdown,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the menu from the hit area around the trigger. It runs the same
  /// action the trigger's own InkWell runs for Enter and Space, so the ring
  /// and the trigger cannot drift apart.
  void _openMenu() {
    final context = _focusNode.context;
    if (context == null) return;
    Actions.maybeInvoke<ActivateIntent>(context, const ActivateIntent());
  }
}

// ---------------------------------------------------------------------------
// Resolved tokens
// ---------------------------------------------------------------------------

/// The dropdown's colours for one theme, resolved once instead of ternary by
/// ternary inside `build`.
@immutable
class _WpDropdownPalette {
  const _WpDropdownPalette({
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.menuSurface,
    required this.focusWash,
    required this.hoverWash,
  });

  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color menuSurface;

  /// Full-bleed wash of the keyboard-focused menu row (accent @ 12%) and of a
  /// hovered one (@ 6%) — both inside the 6–30% tint band the design system
  /// allows for accent fills.
  final Color focusWash;
  final Color hoverWash;

  /// The one palette. Named `_dark` while it had a `_light` twin and an
  /// `of(Brightness)` resolver between them; both went with the light
  /// stack (2026-08-11). The twin was not merely unreachable — it was
  /// wrong for this app, painting white on the accent fill where the
  /// dark palette paints the near-black background colour.
  ///
  /// Ticket 08 split the two surfaces apart, because they are not the same
  /// kind of thing. The **trigger** sits in the page plane, so it takes the
  /// translucent frost and lets the ambient run through it; its rim is the
  /// tinted [WpColors.cardEdgeHighlight], which on a translucent fill is what
  /// carries the control's shape. The **menu** is a route overlay floating
  /// over arbitrary content with no ambient underneath, so it takes the
  /// pre-composited [WpColors.floatingSurface] instead.
  static _WpDropdownPalette current() => _WpDropdownPalette(
    surface: WpColors.cardFillElevated,
    border: WpColors.cardEdgeHighlight,
    textPrimary: WpColors.textPrimary,
    textSecondary: WpColors.textSecondary,
    textMuted: WpColors.textMuted,
    accent: WpColors.accent,
    menuSurface: WpColors.floatingSurface,
    focusWash: WpColors.accentActiveFill,
    hoverWash: WpColors.accentRowHover,
  );
}

// ---------------------------------------------------------------------------
// Menu row
// ---------------------------------------------------------------------------

/// One row of the opened menu: a reserved check column plus the label.
///
/// Deliberately carries no background of its own — see the library docs: the
/// row wash belongs to focus/hover, the check glyph and the semibold label
/// carry the selection.
class _WpDropdownRow extends StatelessWidget {
  const _WpDropdownRow({
    super.key,
    required this.label,
    required this.isActive,
    required this.enabled,
    required this.style,
    required this.activeWeight,
    required this.accent,
    required this.textMuted,
    this.disabledTooltip,
  });

  final String label;
  final bool isActive;
  final bool enabled;
  final String? disabledTooltip;
  final TextStyle style;
  final FontWeight activeWeight;
  final Color accent;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        SizedBox(
          width: _kCheckGutter,
          child: isActive
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(
                    LucideIcons.check,
                    size: WpIconSize.sm,
                    color: accent,
                  ),
                )
              : null,
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              // Unselectable entries drop to the muted token rather than to a
              // blanket opacity: still readable enough to explain itself
              // (the tooltip says why), visibly not on offer.
              color: enabled ? style.color : textMuted,
              fontWeight: isActive ? activeWeight : style.fontWeight,
            ),
          ),
        ),
      ],
    );

    if (!enabled && disabledTooltip != null) {
      return Tooltip(message: disabledTooltip!, child: row);
    }
    return row;
  }
}
