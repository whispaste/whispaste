import 'package:flutter/material.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../services/smart_mode/smart_mode_presets.dart';
import 'dialog.dart';

/// Name of a Smart Mode target language as the UI shows it.
String smartModeTargetLanguageLabel(L10n l10n, SmartModeTargetLanguage lang) =>
    lang == SmartModeTargetLanguage.german
    ? l10n.smartModeTargetLanguageGerman
    : lang.languageName;

/// Asks which language to translate into. Only
/// [smartModeValidatedTargetLanguages] are offered; each row carries the
/// testID `smart-mode-language-<code>`. Returns null when cancelled.
///
/// Shared by the retroactive Translate in Recordings and the Smart Mode
/// actions on the selection (#650), so both ask the same way.
Future<SmartModeTargetLanguage?> showWpSmartModeTargetLanguagePicker(
  BuildContext context,
) {
  final l10n = L10n.of(context);
  return showWpDialog<SmartModeTargetLanguage>(
    context: context,
    title: l10n.historySmartModeSelectTargetLanguage,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lang in smartModeValidatedTargetLanguages)
          Semantics(
            identifier: 'smart-mode-language-${lang.code}',
            child: Builder(
              builder: (rowContext) => ListTile(
                key: ValueKey('smart-mode-language-${lang.code}'),
                contentPadding: EdgeInsets.zero,
                title: Text(smartModeTargetLanguageLabel(l10n, lang)),
                onTap: () => Navigator.of(rowContext).pop(lang),
              ),
            ),
          ),
      ],
    ),
    // The rows are the answer; the footer only leaves without one.
    actions: [
      WpDialogAction(
        label: l10n.actionCancel,
        testId: 'smart-mode-language-cancel',
        role: WpDialogActionRole.cancel,
      ),
    ],
  );
}
