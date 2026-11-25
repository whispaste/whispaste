/// Plans the extra dictation keys (#2055) and resolves a pressed key to the
/// language and Smart Mode choice its recording runs with.
///
/// Pure functions, so the rules are testable without the OS: which extra keys
/// may be registered, which are refused (no modifier, an unknown language,
/// a combination another hotkey of the app or an earlier extra key already
/// holds), and what one press forces.
library;

import '../core/config/extra_dictation_keys.dart';
import '../core/config/settings_provider.dart';
import 'profile_hotkey_plan.dart' show canonicalHotkeyCombo;
import 'smart_mode/smart_mode_presets.dart';

/// Prefix of every extra dictation key's action id in the hotkey service.
const kDictationKeyActionPrefix = 'dictationKey:';

/// Action id of the extra dictation key [keyId] in the hotkey service.
String dictationKeyActionId(String keyId) => '$kDictationKeyActionPrefix$keyId';

/// One extra dictation key that should be registered.
class DictationKeyEntry {
  const DictationKeyEntry({
    required this.keyId,
    required this.key,
    required this.modifiers,
  });

  final String keyId;

  /// Key label in the settings' storage format (for example `E`).
  final String key;

  /// Modifier string in storage format (for example `ctrl+shift`).
  final String modifiers;

  /// The hotkey service's action id for this key.
  String get actionId => dictationKeyActionId(keyId);

  /// Identifies the registered combination, so a change re-registers it.
  String get signature => canonicalHotkeyCombo(key, modifiers);
}

/// The result of [planDictationKeys].
class DictationKeyPlan {
  const DictationKeyPlan({required this.entries, required this.refusedIds});

  /// Keys to register, in list order.
  final List<DictationKeyEntry> entries;

  /// Keys that are not registered, with the reason shown in Settings.
  final Set<String> refusedIds;
}

/// Decides which extra dictation keys are registered. The first key that
/// asks for a combination gets it; later keys and any app hotkey in
/// [reserved] with the same combination are refused. A key without a
/// modifier (a bare key would be grabbed system-wide) or without a known
/// language is refused as well.
DictationKeyPlan planDictationKeys({
  required List<ExtraDictationKey> keys,
  required List<({String key, String modifiers})> reserved,
}) {
  final taken = {
    for (final r in reserved) canonicalHotkeyCombo(r.key, r.modifiers),
  };
  final entries = <DictationKeyEntry>[];
  final refused = <String>{};
  for (final k in keys.take(kMaxExtraDictationKeys)) {
    if (k.key.trim().isEmpty ||
        k.modifiers.trim().isEmpty ||
        !k.hasValidLanguage) {
      refused.add(k.id);
      continue;
    }
    if (!taken.add(canonicalHotkeyCombo(k.key, k.modifiers))) {
      refused.add(k.id);
      continue;
    }
    entries.add(
      DictationKeyEntry(keyId: k.id, key: k.key, modifiers: k.modifiers),
    );
  }
  return DictationKeyPlan(entries: entries, refusedIds: refused);
}

/// What one press of an extra dictation key forces for its recording.
class DictationKeyRun {
  const DictationKeyRun({required this.language, required this.preset});

  /// The recognition language, never `auto`: the key replaces detection.
  final String language;

  /// The Smart Mode preset forced for this recording, or null to follow the
  /// standard preset like the main hotkey.
  final SmartModePreset? preset;
}

/// The language and Smart Mode choice of the extra key [keyId] in
/// [settings]. Null when the key no longer exists or has no valid language:
/// the press then starts nothing.
DictationKeyRun? resolveDictationKey(AppSettings settings, String keyId) {
  for (final k in settings.hotkey.extraDictationKeys) {
    if (k.id != keyId) continue;
    if (!k.hasValidLanguage) return null;
    return DictationKeyRun(
      language: k.language,
      preset: switch (k.smartMode) {
        ExtraDictationKeySmartMode.standard => null,
        ExtraDictationKeySmartMode.off => SmartModePreset.off,
        ExtraDictationKeySmartMode.cleanup => SmartModePreset.cleanup,
        ExtraDictationKeySmartMode.concise => SmartModePreset.concise,
      },
    );
  }
  return null;
}
