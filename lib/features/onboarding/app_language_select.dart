import 'package:flutter/widgets.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_native_name.dart';
import 'onboarding_select.dart';

/// The app language as one select row, each language in its own name.
///
/// Shared by the welcome page and the data key start screen (#1461), so the
/// language is picked the same way wherever it can be picked before the
/// settings page is reachable.
class AppLanguageSelect extends StatelessWidget {
  const AppLanguageSelect({
    super.key,
    required this.testId,
    required this.locale,
    required this.onChanged,
  });

  final String testId;
  final String locale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const locales = L10n.supportedLocales;
    final current = locales
        .firstWhere(
          (l) => l.languageCode == locale,
          orElse: () => locales.first,
        )
        .languageCode;
    return OnboardingSelect<String>(
      testId: testId,
      label: l10n.onboardingSelectAppLanguage,
      valueText: localeNativeName(Locale(current)),
      selected: current,
      options: [
        for (final l in locales)
          OnboardingSelectOption(
            value: l.languageCode,
            id: l.languageCode,
            title: localeNativeName(l),
          ),
      ],
      onSelected: onChanged,
    );
  }
}
