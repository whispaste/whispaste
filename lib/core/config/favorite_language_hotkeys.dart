/// One hotkey per favorite language (#2137, GitHub #161): a press switches the
/// recognition language straight to that favorite, without cycling.
///
/// The combinations are stored per language code in one JSON setting
/// (`stt_favorite_language_hotkeys`), so unpinning and pinning a language
/// again keeps its key, and the order of the favorites never moves a key to
/// another language. Only languages that are favorites right now register
/// their key (see [activeFavoriteLanguageHotkeys]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, mapEquals;

/// The stored combination of one favorite language.
@immutable
class FavoriteLanguageHotkey {
  const FavoriteLanguageHotkey({
    required this.key,
    required this.modifiers,
    this.keyDisplay = '',
  });

  /// Key token in the settings' storage format (for example `1`).
  final String key;

  /// Key label as the keyboard shows it; empty falls back to [key].
  final String keyDisplay;

  /// Modifier string in storage format (for example `ctrl+alt`).
  final String modifiers;

  Map<String, String> toJson() => {
    'key': key,
    'display': keyDisplay,
    'modifiers': modifiers,
  };

  @override
  bool operator ==(Object other) =>
      other is FavoriteLanguageHotkey &&
      key == other.key &&
      keyDisplay == other.keyDisplay &&
      modifiers == other.modifiers;

  @override
  int get hashCode => Object.hash(key, keyDisplay, modifiers);
}

/// Prefix of every favorite-language action id in the hotkey service.
const kFavoriteLanguageHotkeyActionPrefix = 'favoriteLanguage:';

/// Action id of the hotkey of the favorite [code].
String favoriteLanguageHotkeyActionId(String code) =>
    '$kFavoriteLanguageHotkeyActionPrefix$code';

/// Parses the stored JSON. Anything unreadable (broken JSON, wrong types,
/// empty key, `auto`) is dropped, never thrown: a damaged value only costs
/// the key, not the start of the app.
Map<String, FavoriteLanguageHotkey> parseFavoriteLanguageHotkeys(String raw) {
  if (raw.trim().isEmpty) return const {};
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final result = <String, FavoriteLanguageHotkey>{};
  decoded.forEach((code, value) {
    if (code is! String || value is! Map) return;
    final c = code.trim();
    if (c.isEmpty || c == 'auto') return;
    final key = value['key'];
    final modifiers = value['modifiers'];
    final display = value['display'];
    if (key is! String || key.trim().isEmpty || modifiers is! String) return;
    result[c] = FavoriteLanguageHotkey(
      key: key,
      modifiers: modifiers,
      keyDisplay: display is String ? display : '',
    );
  });
  return Map.unmodifiable(result);
}

/// Encodes [hotkeys] for storage; codes sorted so equal maps store equally.
String encodeFavoriteLanguageHotkeys(
  Map<String, FavoriteLanguageHotkey> hotkeys,
) {
  if (hotkeys.isEmpty) return '';
  final codes = hotkeys.keys.toList()..sort();
  return jsonEncode({for (final c in codes) c: hotkeys[c]!.toJson()});
}

/// The hotkeys that are in effect: one per current favorite that has a key,
/// in the order of [favorites].
List<({String code, FavoriteLanguageHotkey hotkey})>
activeFavoriteLanguageHotkeys({
  required List<String> favorites,
  required Map<String, FavoriteLanguageHotkey> hotkeys,
}) => [
  for (final code in favorites)
    if (hotkeys[code] case final hotkey?) (code: code, hotkey: hotkey),
];

/// [hotkeys] with [code] set to [hotkey], or removed when [hotkey] is null.
Map<String, FavoriteLanguageHotkey> withFavoriteLanguageHotkey(
  Map<String, FavoriteLanguageHotkey> hotkeys,
  String code,
  FavoriteLanguageHotkey? hotkey,
) {
  final next = Map<String, FavoriteLanguageHotkey>.of(hotkeys);
  if (hotkey == null) {
    next.remove(code);
  } else {
    next[code] = hotkey;
  }
  return Map.unmodifiable(next);
}

/// Equality for stored hotkey maps.
bool favoriteLanguageHotkeysEqual(
  Map<String, FavoriteLanguageHotkey> a,
  Map<String, FavoriteLanguageHotkey> b,
) => mapEquals(a, b);
