import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/locale_native_name.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Compact dropdown for switching between [L10n.supportedLocales].
///
/// Replaces the older segmented pill row that paired each language with a
/// flag SVG: the flag asymmetry (US/DE flags vs. no clean flag for עברית)
/// and the always-full-width pill row both broke down as more locales got
/// added.  This dropdown renders native names only, scales to any number
/// of locales, and reuses the same surface/border tokens as the rest of
/// the onboarding selectors.
///
/// Public surface kept intentionally small so Slice 07 can drop the same
/// widget into the settings InterfaceSection without further changes.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    required this.currentLocale,
    required this.onChanged,
  });

  /// Active language code (e.g. `'de'`).  When the value is not part of
  /// [L10n.supportedLocales], the widget defensively falls back to the
  /// first supported locale rather than crashing — this should never
  /// happen with a healthy settings store but guards against stale prefs.
  final String currentLocale;

  /// Invoked with the new language code (`'de'`, `'en'`, `'he'`, …) on
  /// selection.  Callers are responsible for persisting the change.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const locales = L10n.supportedLocales;

    final resolvedLocale = locales.firstWhere(
      (l) => l.languageCode == currentLocale,
      orElse: () => locales.first,
    );

    final surfaceColor =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final dropdownSurface = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final activeBackground = (isDark
        ? WpColorsDark.accentSubtle
        : WpColorsLight.accentSubtle);
    final accentColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsetsDirectional.only(
        start: WpSpacing.md,
        end: WpSpacing.sm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: resolvedLocale.languageCode,
          isExpanded: true,
          isDense: false,
          borderRadius: WpRadius.borderMd,
          dropdownColor: dropdownSurface,
          icon: Icon(
            LucideIcons.chevronDown,
            size: WpIconSize.sm,
            color: textSecondary,
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          selectedItemBuilder: (context) {
            return [
              for (final locale in locales)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    localeNativeName(locale),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
            ];
          },
          items: [
            for (final locale in locales)
              DropdownMenuItem<String>(
                value: locale.languageCode,
                child: _LanguageItem(
                  label: localeNativeName(locale),
                  isActive: locale.languageCode == resolvedLocale.languageCode,
                  activeBackground: activeBackground,
                  accentColor: accentColor,
                  textPrimary: textPrimary,
                ),
              ),
          ],
          onChanged: (code) {
            if (code == null) return;
            HapticFeedback.selectionClick();
            onChanged(code);
          },
        ),
      ),
    );
  }
}

/// Single row in the opened dropdown.  Active rows carry a stable
/// [ValueKey] so tests can pin the highlight behaviour and a visual
/// accent (background tint + leading check icon) so users can see the
/// current selection at a glance.
class _LanguageItem extends StatelessWidget {
  const _LanguageItem({
    required this.label,
    required this.isActive,
    required this.activeBackground,
    required this.accentColor,
    required this.textPrimary,
  });

  final String label;
  final bool isActive;
  final Color activeBackground;
  final Color accentColor;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: isActive ? ValueKey('LanguageSelector.active.$_languageCode') : null,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs,
      ),
      decoration: isActive
          ? BoxDecoration(
              color: activeBackground,
              borderRadius: WpRadius.borderSm,
            )
          : null,
      child: Row(
        children: [
          if (isActive)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: WpSpacing.xs),
              child: Icon(
                LucideIcons.check,
                size: WpIconSize.sm,
                color: accentColor,
              ),
            ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Stable suffix for the active-key.  We can't derive the language code
  /// from the label cleanly inside the widget (the label is the endonym),
  /// so we look it up via the bundled supportedLocales list.
  String get _languageCode {
    for (final locale in L10n.supportedLocales) {
      if (localeNativeName(locale) == label) return locale.languageCode;
    }
    return label.toLowerCase();
  }
}
