/// Plans the hotkeys of the app profiles (ticket 13, part 2).
///
/// Pure functions, so the rules are testable without the OS: which profile
/// hotkeys may be registered, and which are refused because another hotkey of
/// the app already holds the combination, an earlier profile does, or the
/// combination has no modifier (a bare key would be grabbed system-wide).
///
/// The hotkeys of the favorite languages (#2137) are planned here as well:
/// they yield to the fixed app hotkeys, and the profiles yield to them.
library;

import '../core/config/favorite_language_hotkeys.dart';
import '../core/config/settings_provider.dart';
import 'app_profiles/app_profile.dart';

/// One profile hotkey that should be registered.
class ProfileHotkeyEntry {
  const ProfileHotkeyEntry({
    required this.profileId,
    required this.key,
    required this.modifiers,
  });

  final String profileId;

  /// Key label in the settings' storage format (for example `F5`).
  final String key;

  /// Modifier string in storage format (for example `ctrl+shift`).
  final String modifiers;

  /// The hotkey service's action id for this profile.
  String get actionId => profileHotkeyActionId(profileId);
}

/// Prefix of every profile hotkey action id.
const kProfileHotkeyActionPrefix = 'profile:';

/// Action id of a profile hotkey in the hotkey service.
String profileHotkeyActionId(String profileId) =>
    '$kProfileHotkeyActionPrefix$profileId';

/// Every hotkey of the app that is switched on, so a profile cannot take it:
/// the fixed app hotkeys, the favorite-language hotkeys that register and
/// the extra dictation keys (#2055).
List<({String key, String modifiers})> reservedHotkeysOf(AppSettings s) => [
  ...hotkeysBeforeDictationKeysOf(s),
  for (final k in s.hotkey.extraDictationKeys)
    (key: k.key, modifiers: k.modifiers),
];

/// What an extra dictation key (#2055) may never take: the fixed app hotkeys
/// and the favorite-language hotkeys that register.
List<({String key, String modifiers})> hotkeysBeforeDictationKeysOf(
  AppSettings s,
) => [
  ...fixedAppHotkeysOf(s),
  for (final entry in planFavoriteLanguageHotkeys(s).entries)
    (key: entry.key, modifiers: entry.modifiers),
];

/// The hotkeys with a fixed place in the settings that are switched on.
List<({String key, String modifiers})> fixedAppHotkeysOf(AppSettings s) => [
  (key: s.hotkeyKey, modifiers: s.hotkeyModifiers),
  if (s.quickNoteHotkey.quickNoteHotkeyEnabled)
    (
      key: s.quickNoteHotkey.quickNoteHotkeyKey,
      modifiers: s.quickNoteHotkey.quickNoteHotkeyModifiers,
    ),
  if (s.snippetPickerHotkey.snippetPickerHotkeyEnabled)
    (
      key: s.snippetPickerHotkey.snippetPickerHotkeyKey,
      modifiers: s.snippetPickerHotkey.snippetPickerHotkeyModifiers,
    ),
  if (s.stt.languageCycleHotkeyEnabled)
    (
      key: s.stt.languageCycleHotkeyKey,
      modifiers: s.stt.languageCycleHotkeyModifiers,
    ),
  if (s.behavior.repasteHotkeyEnabled)
    (
      key: s.behavior.repasteHotkeyKey,
      modifiers: s.behavior.repasteHotkeyModifiers,
    ),
  if (s.behavior.learnCorrectionHotkeyEnabled)
    (
      key: s.behavior.learnCorrectionHotkeyKey,
      modifiers: s.behavior.learnCorrectionHotkeyModifiers,
    ),
  if (s.smartModeHotkey.smartModeHotkeyEnabled)
    (
      key: s.smartModeHotkey.smartModeHotkeyKey,
      modifiers: s.smartModeHotkey.smartModeHotkeyModifiers,
    ),
  if (s.selectionEditHotkey.selectionEditHotkeyEnabled)
    (
      key: s.selectionEditHotkey.selectionEditHotkeyKey,
      modifiers: s.selectionEditHotkey.selectionEditHotkeyModifiers,
    ),
];

/// The result of [planProfileHotkeys].
class ProfileHotkeyPlan {
  const ProfileHotkeyPlan({required this.entries, required this.refusedIds});

  /// Hotkeys to register, in profile order.
  final List<ProfileHotkeyEntry> entries;

  /// Profiles whose hotkey was refused, with the reason in the settings UI.
  final Set<String> refusedIds;
}

/// A combination in one comparable form: upper-case key, lower-case modifier
/// tokens sorted, so `Ctrl+Shift` and `shift+ctrl` are the same.
String canonicalHotkeyCombo(String key, String modifiers) {
  final tokens =
      modifiers
          .toLowerCase()
          .split('+')
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return '${key.trim().toUpperCase()}|${tokens.join('+')}';
}

/// Decides which profile hotkeys are registered. The first profile that asks
/// for a combination gets it; later profiles and any app hotkey in [reserved]
/// with the same combination are refused. A hotkey without a modifier is
/// refused as well.
ProfileHotkeyPlan planProfileHotkeys({
  required List<AppProfile> profiles,
  required List<({String key, String modifiers})> reserved,
}) {
  final taken = {
    for (final r in reserved) canonicalHotkeyCombo(r.key, r.modifiers),
  };
  final entries = <ProfileHotkeyEntry>[];
  final refused = <String>{};

  for (final profile in profiles) {
    if (!profile.hasHotkey) continue;
    final key = profile.hotkeyKey!;
    final modifiers = profile.hotkeyModifiers ?? '';
    if (modifiers.trim().isEmpty) {
      refused.add(profile.id);
      continue;
    }
    final combo = canonicalHotkeyCombo(key, modifiers);
    if (!taken.add(combo)) {
      refused.add(profile.id);
      continue;
    }
    entries.add(
      ProfileHotkeyEntry(profileId: profile.id, key: key, modifiers: modifiers),
    );
  }
  return ProfileHotkeyPlan(entries: entries, refusedIds: refused);
}

/// The result of [planFavoriteLanguageHotkeys].
class FavoriteLanguageHotkeyPlan {
  const FavoriteLanguageHotkeyPlan({
    required this.entries,
    required this.refusedCodes,
  });

  /// Hotkeys to register, in the order of the favorites.
  final List<({String code, String key, String modifiers})> entries;

  /// Favorites whose stored hotkey is refused.
  final Set<String> refusedCodes;
}

/// Decides which favorite-language hotkeys (#2137) are registered: one per
/// current favorite with a stored key. A combination a fixed app hotkey holds
/// or an earlier favorite holds is refused. Unlike a profile key, a language
/// key may be a bare function key: the recording dialog only lets the keys of
/// `singleKeyWhitelist` through without a modifier, as for every app hotkey.
FavoriteLanguageHotkeyPlan planFavoriteLanguageHotkeys(AppSettings s) {
  final taken = {
    for (final r in fixedAppHotkeysOf(s))
      canonicalHotkeyCombo(r.key, r.modifiers),
  };
  final entries = <({String code, String key, String modifiers})>[];
  final refused = <String>{};
  for (final active in activeFavoriteLanguageHotkeys(
    favorites: s.stt.favoriteLanguages,
    hotkeys: s.stt.favoriteLanguageHotkeys,
  )) {
    final key = active.hotkey.key;
    final modifiers = active.hotkey.modifiers;
    if (!taken.add(canonicalHotkeyCombo(key, modifiers))) {
      refused.add(active.code);
      continue;
    }
    entries.add((code: active.code, key: key, modifiers: modifiers));
  }
  return FavoriteLanguageHotkeyPlan(entries: entries, refusedCodes: refused);
}
