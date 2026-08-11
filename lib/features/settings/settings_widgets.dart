/// Reusable setting widgets shared across all settings sections.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_labels.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_dropdown.dart';
import '../../widgets/wp_text_field.dart';

// ---------------------------------------------------------------------------
// SettingRow — single row with icon, label, optional subtitle, and control
// ---------------------------------------------------------------------------

/// Horizontal padding [SettingRow] applies inside its own hover surface.
/// Exposed so callers that render a heading above a bare, frameless row can
/// put it on the same start edge instead of guessing the value.
const double kSettingRowInset = WpSpacing.sm;

class SettingRow extends StatefulWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    this.subtitle,
    // When the row hosts a toggle, pass the current on/off state here so
    // screen-readers announce "on" / "off" alongside the label.
    this.semanticToggledValue,
    this.trailingHugsLabel = false,
    this.iconSize = WpIconSize.sm,
  });

  final IconData icon;
  final String label;
  final Widget trailing;
  final String? subtitle;

  /// Lets [trailing] follow the label instead of being pinned to the row's far
  /// end.
  ///
  /// The settings page is a narrow column where a full-width label and a
  /// right-pinned control are the same thing; onboarding puts the identical row
  /// into a much wider frame, where the two drift apart — measured 153–349 px
  /// of empty run on the privacy page and 425 px on the hotkey page, i.e. a
  /// label and the switch that belongs to it separated by more than the label
  /// itself is wide. The row then reads as two unrelated columns.
  ///
  /// `false` (the default, and what the settings page keeps) gives the label
  /// column an [Expanded]; `true` gives it a loose [Flexible], so it takes its
  /// intrinsic width and no more. A label long enough to wrap still fills the
  /// row and the control lands exactly where it does today — the flag only
  /// removes space that had nothing in it.
  final bool trailingHugsLabel;

  /// Size of the leading [icon].
  ///
  /// `sm` (16) is right in the settings column, where a row is one of a dozen
  /// and the icons are a quiet index down the left edge. On an onboarding page
  /// the same row is one of two, standing alone under a 22-px heading, and 16
  /// px next to a 13-px label and a 32-px control reads as three unrelated
  /// scales rather than one line — see the ticket's P5.
  final double iconSize;

  /// When non-null, the Semantics node carries `toggled: semanticToggledValue`.
  /// Pass this for every row whose [trailing] is a toggle switch.
  final bool? semanticToggledValue;

  @override
  State<SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<SettingRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Subtitle style: use the theme bodySmall token but substitute textMuted
    // for slightly softer contrast (both textMuted and cs.secondary pass WCAG AA).
    final subtitleStyle = tt.bodySmall?.copyWith(color: WpColors.textMuted);

    // The label and hint stay on the wrapper, but the rendered title and
    // subtitle are excluded from the semantics tree below (see the
    // `ExcludeSemantics` further down). A `label:` does not replace the
    // subtree's own text, it is prepended to it, and `hint:` is announced on
    // top of that — so before this the row read "Label, Label, Untertitel"
    // and then repeated the subtitle a third time as the hint.
    //
    // `ExcludeSemantics` rather than the `MergeSemantics` idiom the
    // single-target controls use, because `trailing` is arbitrary here: a
    // Switch, a dropdown, a slider, a text field, or a Row of two buttons.
    // Merging would swallow all of those into the row node; dropping the
    // label instead and letting the text speak for itself would leave a
    // dropdown announced as a bare "Deutsch" with no clue which setting it
    // belongs to. Excluding only the text keeps the row a named group *and*
    // every trailing control independently reachable — verified across all
    // four trailing shapes.
    return Semantics(
      label: widget.label,
      hint: widget.subtitle,
      toggled: widget.semanticToggledValue,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WpLayout.minTouchTarget),
          child: AnimatedContainer(
            duration: WpMotion.durationFor(context, WpMotion.hoverIn),
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: kSettingRowInset,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (WpColors.hover)
                  : (WpColors.hoverTransparent),
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: widget.iconSize, color: cs.secondary),
                const SizedBox(width: WpSpacing.sm),
                Flexible(
                  fit: widget.trailingHugsLabel ? FlexFit.loose : FlexFit.tight,
                  // Excluded because the wrapping Semantics above already
                  // states both strings, as label and hint. Without this the
                  // row announced each of them twice.
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label, style: tt.bodyLarge),
                        if (widget.subtitle != null)
                          Padding(
                            // 2px title-subtitle gap: tighter than
                            // WpSpacing.xxs so the pair reads as one unit.
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(widget.subtitle!, style: subtitleStyle),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                widget.trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HotkeyDisplay — styled key cap chips
// ---------------------------------------------------------------------------

class HotkeyDisplay extends StatelessWidget {
  const HotkeyDisplay({
    super.key,
    required this.hotkeyKey,
    required this.hotkeyModifiers,
    this.hotkeyKeyDisplay = '',
  });

  final String hotkeyKey;
  final String hotkeyModifiers;
  final String hotkeyKeyDisplay;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final parts = hotkeyDisplayParts(
      hotkeyModifiers,
      hotkeyKey,
      l10n: l10n,
      displayOverride: hotkeyKeyDisplay,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w500,
                  color: WpColors.textMuted,
                ),
              ),
            ),
          Container(
            // A key cap stands beside a dense "Change" button in every place
            // it is used, so it takes that height rather than whatever its
            // padding and border happen to add up to (30 px, i.e. two pixels
            // short and one pixel off the button's centre line).
            constraints: const BoxConstraints(
              minHeight: WpLayout.denseControlHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: WpColors.surfaceVariant,
              borderRadius: WpRadius.borderSm,
              border: Border.all(color: WpColors.borderSubtle),
            ),
            // `widthFactor: 1` so the cap centres its glyph in the taller box
            // without also claiming the width the row has left over.
            child: Center(
              widthFactor: 1,
              child: Text(
                parts[i],
                style: const TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: WpColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared control builders
// ---------------------------------------------------------------------------

/// Themed dropdown for settings — [WpDropdown], the app's single
/// value-selection dropdown, at the one size it has.
///
/// It used to ask for a 32 dp `dense` trigger here, which made every settings
/// row that carries a dropdown shorter than the search fields, form fields
/// and buttons on every other page — and shorter than the API-key and text
/// rows in Settings itself. There is one control height in this app now.
///
/// Kept as a helper because the settings sections address their options as
/// two parallel lists (values + localized labels) rather than as item
/// objects; it is the only adapter between that shape and [WpDropdownItem].
///
/// [disabledItems] marks item values that are shown but not selectable (e.g.
/// a feature unavailable in the current build/platform); [disabledTooltip]
/// explains why when hovered. A `null` [value] shows the muted [hint] instead
/// of a selection (e.g. a picker with no choice made yet); [expanded] makes
/// the dropdown fill its parent's width and ellipsize long labels, for use
/// inside an [Expanded] row slot rather than a trailing settings slot.
Widget settingsDropdown({
  required BuildContext context,
  required String? value,
  required List<String> items,
  List<String>? labels,
  required ValueChanged<String?> onChanged,
  Set<String>? disabledItems,
  String? disabledTooltip,
  String? hint,
  bool expanded = false,
}) {
  return WpDropdown<String>(
    value: value,
    expanded: expanded,
    hint: hint,
    items: [
      for (final (index, item) in items.indexed)
        WpDropdownItem<String>(
          value: item,
          label: labels != null ? labels[index] : item,
          enabled: !(disabledItems?.contains(item) ?? false),
          disabledTooltip: disabledTooltip,
        ),
    ],
    onChanged: onChanged,
  );
}

/// Themed slider with value label for settings.
Widget settingsSlider({
  required BuildContext context,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required String valueLabel,
  required ValueChanged<double> onChanged,
  ValueChanged<double>? onChangeEnd,
}) {
  const accent = WpColors.accent;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 180,
        child: SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: WpColors.surfaceVariant,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
      const SizedBox(width: WpSpacing.xs),
      SizedBox(
        width: 52,
        child: Text(
          valueLabel,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: WpTypography.body,
            fontWeight: FontWeight.w500,
            color: WpColors.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}

/// Standard toggle switch for settings.
///
/// [onChanged] is nullable on purpose: `null` is Material's own "disabled"
/// signal for [Switch], and two call sites gate the toggle on a platform
/// capability (Push-to-Talk needs key-up events) rather than hiding it.
///
/// [key] is forwarded onto the [Switch] itself, not onto a wrapper — tests
/// look the toggle up with `tester.widget<Switch>(find.byKey(...))`, which a
/// wrapper node would break.
///
/// Deliberately **not** sized into the app's 48 dp control family. Buttons,
/// search fields, form fields and dropdown triggers all settle at
/// `WpLayout.minTouchTarget` because they are boxes that line up with each
/// other on the same line. A switch is not one of those: it is a track with a
/// thumb, and both Material and the HIG keep it at its own compact size and
/// centre it in whatever row it sits in — inflating it to 48 would read as a
/// cartoon of a switch, not as consistency. The 48 belongs to the *row*
/// around it, which [SettingRow] already carries.
Widget settingsToggle({
  required bool value,
  required ValueChanged<bool>? onChanged,
  Key? key,
}) {
  return Switch(key: key, value: value, onChanged: onChanged);
}

/// Password / API key field with visibility toggle.
///
/// [semanticLabel] names the field's purpose for screen readers (e.g. "OpenAI
/// API Key") — the visible [SettingRow] label sits beside the field, not
/// inside its own Semantics node, so without this the field announces only
/// as an unlabeled text field.
Widget settingsApiKeyField({
  required BuildContext context,
  required TextEditingController controller,
  required bool obscure,
  required VoidCallback onToggle,
  ValueChanged<String>? onChanged,
  String? semanticLabel,
}) {
  // The reveal toggle rides the field's own trailing slot, which is 48 dp
  // tall because the field is — so the button meets WpLayout.minTouchTarget
  // without the field having to be pinned to a shorter fixed height and
  // without the text ever running underneath the icon.
  return SizedBox(
    width: 280,
    child: WpTextField(
      controller: controller,
      variant: WpTextFieldVariant.form,
      semanticsLabel: semanticLabel,
      hintText: 'sk-...',
      obscureText: obscure,
      onChanged: onChanged,
      suffix: Semantics(
        label: L10n.of(context).settingsToggleApiKeyVisibility,
        button: true,
        child: IconButton(
          icon: Icon(
            obscure ? LucideIcons.eye : LucideIcons.eyeOff,
            size: WpIconSize.sm,
            color: WpColors.textMuted,
          ),
          onPressed: onToggle,
          tooltip: L10n.of(context).settingsToggleApiKeyVisibility,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: WpLayout.minTouchTarget,
            minHeight: WpLayout.minTouchTarget,
          ),
        ),
      ),
    ),
  );
}

/// Text input field for settings.
///
/// [semanticLabel] names the field's purpose for screen readers — see
/// [settingsApiKeyField] for why this is needed alongside a [SettingRow].
Widget settingsTextField({
  required BuildContext context,
  required TextEditingController controller,
  String? hintText,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
  String? semanticLabel,
}) {
  return SizedBox(
    width: maxLines > 1 ? double.infinity : 240,
    child: WpTextField(
      controller: controller,
      variant: WpTextFieldVariant.form,
      semanticsLabel: semanticLabel,
      hintText: hintText,
      maxLines: maxLines,
      onChanged: onChanged,
    ),
  );
}

/// Horizontal divider between settings sections.
Widget settingsSectionDivider(BuildContext context) {
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: WpSpacing.xs),
    child: Divider(color: WpColors.borderSubtle),
  );
}

/// Thin divider between conditional sub-groups *within* one settings
/// section (e.g. local- vs. cloud-mode STT fields, or an overlay section's
/// conditionally-shown size/preview rows) — a tighter, lower-profile sibling
/// of [settingsSectionDivider], which separates whole top-level sections.
Widget settingsInlineDivider(BuildContext context) {
  return const Divider(height: 1, color: WpColors.borderSubtle);
}

// ---------------------------------------------------------------------------
// Inline notice
// ---------------------------------------------------------------------------

/// The settings page's one inline notice: a warning-tinted block that says
/// something the rows above it cannot say for themselves — a sync that failed,
/// a microphone that is clipping, a beta you can step back out of.
///
/// There were three of these in two geometries, and a doc comment on one of
/// them claiming it followed the pattern of another it did not actually match:
/// 16 px padding against 12/8, border alpha 0.4 against 0.35, a 12 px icon gap
/// against 8, body text in `textPrimary` against warning-coloured `small`, and
/// the same glyph imported under two different Lucide aliases. None of those
/// differences carried meaning; they were just three people solving one
/// problem.
///
/// The resolved version takes the majority geometry, and `textPrimary` for the
/// message: warning-coloured text on a warning-tinted fill was the weakest
/// contrast of the three, and the tint plus the icon already carry the tone.
///
/// [margin] is the one real variation — the clipping banner sits flush under
/// the gain slider it annotates, so it needs a zero top edge.
Widget settingsInlineNotice({
  required BuildContext context,
  required String message,

  /// Rendered under [message], inside the same block — used by the
  /// stable-revert hint for its link.
  Widget? action,
  VoidCallback? onDismiss,
  String? dismissTooltip,
  EdgeInsets margin = const EdgeInsets.symmetric(
    horizontal: WpSpacing.sm,
    vertical: WpSpacing.xs,
  ),
}) {
  const warning = WpColors.warning;
  const textPrimary = WpColors.textPrimary;

  return Container(
    margin: margin,
    padding: const EdgeInsets.all(WpSpacing.md),
    decoration: BoxDecoration(
      color: warning.withValues(alpha: 0.12),
      borderRadius: WpRadius.borderMd,
      border: Border.all(color: warning.withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          LucideIcons.triangleAlert,
          size: WpIconSize.sm,
          color: warning,
        ),
        const SizedBox(width: WpSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: textPrimary),
              ),
              if (action != null) ...[
                const SizedBox(height: WpSpacing.xxs),
                action,
              ],
            ],
          ),
        ),
        if (onDismiss != null)
          IconButton(
            icon: const Icon(
              LucideIcons.x,
              size: WpIconSize.sm,
              color: warning,
            ),
            tooltip: dismissTooltip,
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: WpLayout.minTouchTarget,
              minHeight: WpLayout.minTouchTarget,
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Format helpers
// ---------------------------------------------------------------------------

String fmtSeconds(BuildContext context, double v) {
  if (v == 0) return L10n.of(context).settingsOff;
  return '${v.round()}s';
}

String fmtDuration(BuildContext context, int seconds) {
  if (seconds == 0) return L10n.of(context).settingsMaxRecordDurationUnlimited;
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

/// Syncs a [TextEditingController] with a settings value without losing cursor.
void syncController(TextEditingController controller, String value) {
  if (controller.text == value) return;
  controller.value = controller.value.copyWith(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
    composing: TextRange.empty,
  );
}
