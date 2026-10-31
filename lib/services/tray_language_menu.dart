/// Pure builder for the "Language" submenu of the tray context menu.
///
/// Lists the favorite recognition languages (`settings.stt.favoriteLanguages`)
/// as radio entries and adds the active language when it is not a favorite,
/// so the checkmark is never missing. "More…" is a trailing entry that opens
/// the app window with the full language list in the dock.
library;

import 'package:flutter/widgets.dart' show Locale;
import '../core/config/whisper_languages.dart';
import '../core/l10n/locale_native_name.dart';
import 'app_commands/app_command.dart';
import 'tray_submenu_builder.dart';

/// Key namespace for language entries in the tray context menu.
const langMenuKeyPrefix = 'lang:';

/// Key of the "More…" entry that opens the window with the full language list.
const langMoreMenuKey = 'lang-more';

/// Encodes a language code as a tray menu-item key.
String langMenuKey(String code) => '$langMenuKeyPrefix$code';

/// The language code encoded in [key], or null outside the language namespace.
String? langCodeFromMenuKey(String key) =>
    trayRadioValueFromKey(langMenuKeyPrefix, key);

/// Builds the entries of the Language submenu.
///
/// [activeCode] is the persisted recognition language (`auto` or a code).
/// [favoriteCodes] are listed first, in their stored order. The active code is
/// added before them when it is not a favorite. [autoLabelKey] names `auto`,
/// [moreLabelKey] the trailing entry.
List<AppCommand> buildLanguageCommands({
  required String activeCode,
  required List<String> favoriteCodes,
  required String autoLabelKey,
  required String moreLabelKey,
}) {
  final codes = [
    if (!favoriteCodes.contains(activeCode)) activeCode,
    ...favoriteCodes,
  ];
  return buildRadioCommands(
    keyPrefix: langMenuKeyPrefix,
    selected: activeCode,
    options: [
      for (final code in codes)
        TrayRadioOption(
          value: code,
          labelKey: code == 'auto' ? autoLabelKey : languageMenuName(code),
        ),
    ],
    trailing: [AppCommand(id: langMoreMenuKey, labelKey: moreLabelKey)],
  );
}

/// Endonym of a language code (e.g. `Deutsch`), falling back to the catalog
/// name and then to the code itself.
String languageMenuName(String code) =>
    whisperLanguages[code] == null ? code : localeNativeName(Locale(code));
