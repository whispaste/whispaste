import 'package:flutter/material.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/locale_native_name.dart';
import 'wp_dropdown.dart';

/// Dropdown for switching between [L10n.supportedLocales].
///
/// Replaces the older segmented pill row that paired each language with a
/// flag SVG: the flag asymmetry (US/DE flags vs. no clean flag for עברית)
/// and the always-full-width pill row both broke down as more locales got
/// added.  This renders native names only and scales to any number of
/// locales.
///
/// Locale-specific wrapper around [WpDropdown] — the app's single dropdown
/// component — so onboarding, Settings → Interface and the feedback form all
/// share one list rendering and one selection treatment.  Used in three
/// places, which is why the endonym mapping and the defensive fallback stay
/// behind this name instead of being repeated at each call site.
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
    const locales = L10n.supportedLocales;

    final resolvedLocale = locales.firstWhere(
      (l) => l.languageCode == currentLocale,
      orElse: () => locales.first,
    );

    return WpDropdown<String>(
      value: resolvedLocale.languageCode,
      expanded: true,
      items: [
        for (final locale in locales)
          WpDropdownItem<String>(
            value: locale.languageCode,
            label: localeNativeName(locale),
            // Stable key on the selected row so tests can pin the active-row
            // treatment independently of its exact styling.
            activeKey: ValueKey(
              'LanguageSelector.active.${locale.languageCode}',
            ),
          ),
      ],
      onChanged: (code) {
        if (code == null) return;
        onChanged(code);
      },
    );
  }
}
