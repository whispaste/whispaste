/// One display name for a Smart Mode preset everywhere it is shown: the
/// Smart Mode page, the dock, the profile editor and the overlay (#891).
///
/// Lives in `core/` so feature files and services can share it without
/// importing `app.dart`.
library;

import '../l10n/generated/app_localizations.dart';
import 'settings_sections.dart' show SmartModeCustomPreset, SmartModeSettings;

/// The built-in presets in their display order.
const List<String> kSmartModeBuiltInPresets = [
  'off',
  'cleanup',
  'concise',
  'translate',
];

/// The localized name of [value]: a built-in preset, or the name of a saved
/// own preset (`custom:<id>`) when [settings] knows it. An own preset without
/// a name shows a neutral fallback; an unknown value reads as "Off", which is
/// also how dictation treats it.
String smartModePresetDisplayName(
  String value,
  L10n l10n, {
  SmartModeSettings? settings,
}) {
  if (value.startsWith(SmartModeCustomPreset.valuePrefix)) {
    final custom = settings?.customPresetFor(value);
    if (custom == null) return l10n.smartModePresetOff;
    final name = custom.name.trim();
    return name.isEmpty ? l10n.smartModeCustomPresetUntitled : name;
  }
  return switch (value) {
    'cleanup' => l10n.smartModePresetCleanup,
    'concise' => l10n.smartModePresetConcise,
    'translate' => l10n.smartModePresetTranslate,
    _ => l10n.smartModePresetOff,
  };
}

/// Every value the standard preset may take: the built-in presets followed by
/// the user's own presets.
List<String> smartModePresetValues(SmartModeSettings settings) => [
  ...kSmartModeBuiltInPresets,
  for (final preset in settings.customPresets) preset.value,
];
