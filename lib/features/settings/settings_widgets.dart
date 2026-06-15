/// Reusable setting widgets shared across all settings sections.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_labels.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// SettingRow — single row with icon, label, optional subtitle, and control
// ---------------------------------------------------------------------------

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
  });

  final IconData icon;
  final String label;
  final Widget trailing;
  final String? subtitle;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Subtitle style: use the theme bodySmall token but substitute textMuted
    // for slightly softer contrast (both textMuted and cs.secondary pass WCAG AA).
    final subtitleStyle = tt.bodySmall?.copyWith(
      color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
    );

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
            duration: WpMotion.hoverIn,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (isDark ? WpColorsDark.hover : WpColorsLight.hover)
                  : (isDark
                        ? WpColorsDark.hoverTransparent
                        : WpColorsLight.hoverTransparent),
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: WpIconSize.sm, color: cs.secondary),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: tt.bodyLarge),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(widget.subtitle!, style: subtitleStyle),
                        ),
                    ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle,
              ),
            ),
            child: Text(
              parts[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isDark
                    ? WpColorsDark.textPrimary
                    : WpColorsLight.textPrimary,
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

/// Themed dropdown for settings.
Widget settingsDropdown({
  required BuildContext context,
  required String value,
  required List<String> items,
  List<String>? labels,
  required ValueChanged<String?> onChanged,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
    decoration: BoxDecoration(
      color: isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant,
      borderRadius: WpRadius.borderSm,
      border: Border.all(
        color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        items: items
            .asMap()
            .entries
            .map(
              (e) => DropdownMenuItem(
                value: e.value,
                child: Text(labels != null ? labels[e.key] : e.value),
              ),
            )
            .toList(),
        onChanged: onChanged,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary,
        ),
        dropdownColor: isDark
            ? WpColorsDark.surfaceElevated
            : WpColorsLight.surfaceElevated,
        borderRadius: WpRadius.borderSm,
        icon: Padding(
          padding: const EdgeInsetsDirectional.only(start: WpSpacing.xs),
          child: Icon(
            LucideIcons.chevronDown,
            size: WpIconSize.xs,
            color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
          ),
        ),
      ),
    ),
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
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 180,
        child: SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: isDark
                ? WpColorsDark.surfaceVariant
                : WpColorsLight.surfaceVariant,
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? WpColorsDark.textSecondary
                : WpColorsLight.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}

/// Standard toggle switch for settings.
Widget settingsToggle({
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Switch(value: value, onChanged: onChanged);
}

/// Password / API key field with visibility toggle.
Widget settingsApiKeyField({
  required BuildContext context,
  required TextEditingController controller,
  required bool obscure,
  required VoidCallback onToggle,
  ValueChanged<String>? onChanged,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return SizedBox(
    width: 280,
    height: 34,
    child: TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'sk-...',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? LucideIcons.eye : LucideIcons.eyeOff,
            size: WpIconSize.sm,
            color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
          ),
          onPressed: onToggle,
          tooltip: L10n.of(context).settingsToggleApiKeyVisibility,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
    ),
  );
}

/// Text input field for settings.
Widget settingsTextField({
  required BuildContext context,
  required TextEditingController controller,
  String? hintText,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return SizedBox(
    width: maxLines > 1 ? double.infinity : 240,
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
      ),
    ),
  );
}

/// Horizontal divider between settings sections.
Widget settingsSectionDivider(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
    child: Divider(
      color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
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
