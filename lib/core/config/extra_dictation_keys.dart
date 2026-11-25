/// Extra dictation keys (#2055): up to [kMaxExtraDictationKeys] further
/// dictation hotkeys, each with a language of its own and optionally a Smart
/// Mode choice. Key A for German, key B for English is more reliable than any
/// automatic detection on a short sentence.
///
/// Stored as one JSON list under [HotkeySettings.extraDictationKeys]
/// (`hotkey_extra_dictation_keys`). Nothing stored means no extra key, and
/// then nothing is registered: the main hotkey behaves exactly as before.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import 'whisper_languages.dart';

/// Most extra dictation keys a user can add. More global hotkeys mean more
/// conflicts with other apps, so the list stays short (issue #2055).
const int kMaxExtraDictationKeys = 3;

/// What an extra dictation key does with Smart Mode. [standard] follows the
/// main hotkey (the standard preset); the others force one preset for the
/// recording, or force Smart Mode off.
///
/// Translate is left out on purpose: it needs a target language of its own,
/// and the key already names the language spoken.
enum ExtraDictationKeySmartMode {
  standard('standard'),
  off('off'),
  cleanup('cleanup'),
  concise('concise');

  const ExtraDictationKeySmartMode(this.storageValue);

  /// Value persisted in the JSON entry.
  final String storageValue;

  /// Parses a stored value. Unknown or missing values fall back to
  /// [standard], never to [off].
  static ExtraDictationKeySmartMode fromStorage(Object? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return standard;
  }
}

/// One extra dictation key.
@immutable
class ExtraDictationKey {
  const ExtraDictationKey({
    required this.id,
    required this.key,
    this.keyDisplay = '',
    required this.modifiers,
    required this.language,
    this.smartMode = ExtraDictationKeySmartMode.standard,
  });

  /// Stable id, unique within the list; never shown. Also part of the hotkey
  /// action id, so a reordered list keeps every registration.
  final String id;

  /// Canonical storage token for the non-modifier key, as `resolveKey`
  /// consumes it (see [HotkeySettings.hotkeyKey]).
  final String key;

  /// User-visible label for [key] (see [HotkeySettings.hotkeyKeyDisplay]).
  final String keyDisplay;

  /// Modifier string in storage format, for example `ctrl+shift`.
  final String modifiers;

  /// The language this key forces (a [whisperLanguages] code, never `auto`).
  final String language;

  final ExtraDictationKeySmartMode smartMode;

  /// Whether [language] is one the engine knows. A key with an unknown
  /// language is never registered (it could not force anything).
  bool get hasValidLanguage =>
      language != 'auto' && whisperLanguages.containsKey(language);

  ExtraDictationKey copyWith({
    String? key,
    String? keyDisplay,
    String? modifiers,
    String? language,
    ExtraDictationKeySmartMode? smartMode,
  }) => ExtraDictationKey(
    id: id,
    key: key ?? this.key,
    keyDisplay: keyDisplay ?? this.keyDisplay,
    modifiers: modifiers ?? this.modifiers,
    language: language ?? this.language,
    smartMode: smartMode ?? this.smartMode,
  );

  /// Parses the stored JSON list. A missing or damaged value is an empty list;
  /// entries without id, key or language are dropped, duplicate ids keep the
  /// first, and at most [kMaxExtraDictationKeys] entries are read.
  static List<ExtraDictationKey> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final seen = <String>{};
      final keys = <ExtraDictationKey>[];
      for (final item in decoded) {
        if (keys.length >= kMaxExtraDictationKeys) break;
        if (item is! Map) continue;
        final id = item['id'];
        final key = item['key'];
        final language = item['language'];
        if (id is! String || id.isEmpty || !seen.add(id)) continue;
        if (key is! String || key.isEmpty) continue;
        if (language is! String || language.isEmpty) continue;
        keys.add(
          ExtraDictationKey(
            id: id,
            key: key,
            keyDisplay: item['keyDisplay'] is String
                ? item['keyDisplay'] as String
                : '',
            modifiers: item['modifiers'] is String
                ? item['modifiers'] as String
                : '',
            language: language,
            smartMode: ExtraDictationKeySmartMode.fromStorage(
              item['smartMode'],
            ),
          ),
        );
      }
      return List.unmodifiable(keys);
    } on FormatException {
      return const [];
    }
  }

  /// The stored form; an empty list is stored as an empty string.
  static String listToJson(List<ExtraDictationKey> keys) => keys.isEmpty
      ? ''
      : jsonEncode([
          for (final k in keys)
            {
              'id': k.id,
              'key': k.key,
              'keyDisplay': k.keyDisplay,
              'modifiers': k.modifiers,
              'language': k.language,
              'smartMode': k.smartMode.storageValue,
            },
        ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtraDictationKey &&
          id == other.id &&
          key == other.key &&
          keyDisplay == other.keyDisplay &&
          modifiers == other.modifiers &&
          language == other.language &&
          smartMode == other.smartMode;

  @override
  int get hashCode =>
      Object.hash(id, key, keyDisplay, modifiers, language, smartMode);
}

/// An id for a new key that no key in [existing] uses yet.
String nextExtraDictationKeyId(List<ExtraDictationKey> existing) {
  final used = {for (final k in existing) k.id};
  var n = 1;
  while (used.contains('k$n')) {
    n++;
  }
  return 'k$n';
}
