import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import '../core/config/whisper_languages.dart';
import '../core/l10n/generated/app_localizations.dart';
import 'dictation_message.dart';
import 'onboarding_hold.dart';
import 'wp_banner.dart';
import 'wp_text_link.dart';

/// The language's name in the UI language, falling back to the catalog's
/// English name, then to its code.
String languageDisplayName(BuildContext context, String code) =>
    LocaleNames.of(context)?.nameOf(code) ?? whisperLanguages[code] ?? code;

/// Recording-start toast for the Parakeet language gap (SW-05). Dismissable
/// and unobtrusive: it names the gap and offers the switch, never switches.
void showWpParakeetLanguageToast({
  required BuildContext context,
  required L10n l10n,
  required String languageCode,
  required VoidCallback onSwitch,
}) {
  showWpDictationMessage(
    context,
    message: l10n.parakeetLanguageUnsupported(
      languageDisplayName(context, languageCode),
    ),
    type: WpMessageType.info,
    duration: const Duration(seconds: 6),
    actionLabel: l10n.parakeetLanguageSwitchToWhisper,
    onAction: onSwitch,
  );
}

/// Toast after Parakeet wrote a recording in a script none of the user's
/// [languages] uses (#2168). When Whisper took the recording over it only
/// says so; otherwise it offers the switch to Whisper, never switches.
void showWpParakeetScriptToast({
  required BuildContext context,
  required L10n l10n,
  required List<String> languages,
  required bool handledByWhisper,
  required VoidCallback onSwitch,
}) {
  final names = languages
      .map((code) => languageDisplayName(context, code))
      .join(', ');
  showWpDictationMessage(
    context,
    message: handledByWhisper
        ? l10n.parakeetScriptWhisperTookOver(names)
        : l10n.parakeetScriptMismatch(names),
    type: WpMessageType.info,
    duration: const Duration(seconds: 6),
    actionLabel: handledByWhisper ? null : l10n.parakeetLanguageSwitchToWhisper,
    onAction: handledByWhisper ? null : onSwitch,
    testId: 'parakeet-script-toast',
  );
}

/// Settings notice shown where the recognition language is chosen while
/// Parakeet is the engine (the language row itself is hidden then).
class WpParakeetLanguageBanner extends StatelessWidget {
  const WpParakeetLanguageBanner({
    super.key,
    required this.languageCode,
    required this.onSwitch,
  });

  final String languageCode;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpBanner(
      key: const ValueKey('settings-stt-parakeet-language-notice'),
      tone: WpBannerTone.info,
      message: l10n.parakeetLanguageUnsupported(
        languageDisplayName(context, languageCode),
      ),
      action: WpTextLink(
        key: const ValueKey('settings-stt-parakeet-switch-whisper'),
        label: l10n.parakeetLanguageSwitchToWhisper,
        onPressed: onSwitch,
      ),
    );
  }
}
