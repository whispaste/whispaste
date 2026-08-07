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
/// Rows keep the full 48px touch target ([WpLayout.minTouchTarget]) in both
/// sizes — the dense *trigger* is compact, the menu it opens is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

// ---------------------------------------------------------------------------
// Sizing
// ---------------------------------------------------------------------------

/// Trigger size. Only the *closed* control changes — the opened menu is
/// identical in both, because a menu row is a click target, not a table cell.
enum WpDropdownSize {
  /// 48px standalone control (onboarding, form fields, Settings → Interface).
  standard,

  /// 32px control for the trailing slot of a dense settings row.
  dense,
}

/// Width of the leading check column in the opened menu.
///
/// Reserved on *every* row so labels align whether or not they carry the
/// glyph, and compensated for by [_WpDropdownState._menuWidth] so reserving
/// it never costs label width.
const double _kCheckGutter = WpIconSize.sm + WpSpacing.xs;

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
    this.size = WpDropdownSize.standard,
    this.expanded = false,
  });

  /// Currently selected value, or `null` for an unset picker (see [hint]).
  final T? value;

  final List<WpDropdownItem<T>> items;

  /// `null` disables the control.
  final ValueChanged<T?>? onChanged;

  /// Muted placeholder shown while [value] is `null`.
  final String? hint;

  final WpDropdownSize size;

  /// Fills the parent's width and ellipsizes long labels — for an [Expanded]
  /// slot or a fixed-width [SizedBox], rather than a trailing settings slot.
  final bool expanded;

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

  bool get _isDense => widget.size == WpDropdownSize.dense;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureMenuWidth();
    });

    final theme = Theme.of(context);
    final palette = _WpDropdownPalette.of(theme.brightness);
    final spec = _WpDropdownSpec.of(widget.size);

    final labelStyle =
        spec.labelRole(theme.textTheme)?.copyWith(color: palette.textPrimary) ??
        TextStyle(color: palette.textPrimary);

    final surface = palette.surface;
    final border = palette.border;
    final textSecondary = palette.textSecondary;
    final textMuted = palette.textMuted;
    final accent = palette.accent;
    final menuSurface = palette.menuSurface;
    final focusWash = palette.focusWash;
    final hoverWash = palette.hoverWash;
    final radius = spec.radius;

    final dropdown = DropdownButton<T>(
      key: _buttonKey,
      value: widget.value,
      items: [
        for (final item in widget.items)
          DropdownMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: _WpDropdownRow(
              key: item.value == widget.value ? item.activeKey : null,
              label: item.label,
              isActive: item.value == widget.value,
              enabled: item.enabled,
              disabledTooltip: item.disabledTooltip,
              style: labelStyle,
              // One weight step above the row's own — the check glyph carries
              // the selection, the weight only seconds it.
              activeWeight: spec.activeWeight,
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
      isDense: _isDense,
      style: labelStyle,
      // Inset lives on the button, not on the frame around it: Material
      // anchors the menu to the *button's* box, so padding on the frame
      // would leave the frame's own edges peeking out around the open menu
      // — and it would inset the hover/focus ink from the frame as well.
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      itemHeight: WpLayout.minTouchTarget,
      menuWidth: _menuWidth,
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
          size: spec.chevronSize,
          color: textSecondary,
        ),
      ),
    );

    return WpFocusRing(
      focusNode: _focusNode,
      radius: spec.ringRadius,
      child: Container(
        height: spec.height,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: radius,
          border: Border.all(color: border),
        ),
        child: DropdownButtonHideUnderline(
          // Re-tints the row washes of the opened menu (Material captures the
          // themes from this context for the menu route) as well as the
          // trigger's own hover ink.
          child: Theme(
            data: theme.copyWith(focusColor: focusWash, hoverColor: hoverWash),
            child: dropdown,
          ),
        ),
      ),
    );
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

  static const _dark = _WpDropdownPalette(
    surface: WpColorsDark.surfaceVariant,
    border: WpColorsDark.borderSubtle,
    textPrimary: WpColorsDark.textPrimary,
    textSecondary: WpColorsDark.textSecondary,
    textMuted: WpColorsDark.textMuted,
    accent: WpColorsDark.accent,
    menuSurface: WpColorsDark.surfaceElevated,
    focusWash: WpColorsDark.accentActiveFill,
    hoverWash: WpColorsDark.accentRowHover,
  );

  static const _light = _WpDropdownPalette(
    surface: WpColorsLight.surfaceVariant,
    border: WpColorsLight.borderSubtle,
    textPrimary: WpColorsLight.textPrimary,
    textSecondary: WpColorsLight.textSecondary,
    textMuted: WpColorsLight.textMuted,
    accent: WpColorsLight.accent,
    menuSurface: WpColorsLight.surfaceElevated,
    focusWash: WpColorsLight.accentActiveFill,
    hoverWash: WpColorsLight.accentRowHover,
  );

  static _WpDropdownPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;
}

/// Everything [WpDropdownSize] actually decides. The opened menu is absent
/// from this list on purpose: it does not vary by size.
@immutable
class _WpDropdownSpec {
  const _WpDropdownSpec({
    required this.height,
    required this.radius,
    required this.ringRadius,
    required this.chevronSize,
    required this.activeWeight,
    required this.labelRole,
  });

  final double height;
  final BorderRadius radius;
  final double ringRadius;
  final double chevronSize;

  /// Weight of the selected row's label — one step above the row's own.
  final FontWeight activeWeight;

  /// The dense trigger sits inside a settings row at body size; the standard
  /// one is a control in its own right and carries the title role.
  final TextStyle? Function(TextTheme) labelRole;

  static final _standard = _WpDropdownSpec(
    height: WpLayout.minTouchTarget,
    radius: WpRadius.borderMd,
    ringRadius: WpRadius.md,
    chevronSize: WpIconSize.sm,
    activeWeight: FontWeight.w700,
    labelRole: _standardLabelRole,
  );

  static final _dense = _WpDropdownSpec(
    height: 32,
    radius: WpRadius.borderSm,
    ringRadius: WpRadius.sm,
    chevronSize: WpIconSize.xs,
    activeWeight: FontWeight.w600,
    labelRole: _denseLabelRole,
  );

  static TextStyle? _standardLabelRole(TextTheme t) => t.titleMedium;
  static TextStyle? _denseLabelRole(TextTheme t) => t.bodyLarge;

  static _WpDropdownSpec of(WpDropdownSize size) => switch (size) {
    WpDropdownSize.standard => _standard,
    WpDropdownSize.dense => _dense,
  };
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
