import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import '../core/config/whisper_languages.dart';
import '../core/l10n/generated/app_localizations.dart';
import 'toast.dart';
import 'wp_banner.dart';
import 'wp_text_link.dart';

/// The language's name in the UI language, falling back to its code.
String parakeetLanguageDisplayName(BuildContext context, String code) =>
    LocaleNames.of(context)?.nameOf(code) ?? whisperLanguages[code] ?? code;

/// Recording-start toast for the Parakeet language gap (SW-05). Dismissable
/// and unobtrusive: it names the gap and offers the switch, never switches.
void showWpParakeetLanguageToast({
  required BuildContext context,
  required L10n l10n,
  required String languageCode,
  required VoidCallback onSwitch,
}) {
  WpToast.show(
    context,
    message: l10n.parakeetLanguageUnsupported(
      parakeetLanguageDisplayName(context, languageCode),
    ),
    type: WpToastType.info,
    duration: const Duration(seconds: 6),
    actionLabel: l10n.parakeetLanguageSwitchToWhisper,
    onAction: onSwitch,
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
        parakeetLanguageDisplayName(context, languageCode),
      ),
      action: WpTextLink(
        key: const ValueKey('settings-stt-parakeet-switch-whisper'),
        label: l10n.parakeetLanguageSwitchToWhisper,
        onPressed: onSwitch,
      ),
    );
  }
}
