/// Der eine Weg, auf dem die weiteren Diktiertasten (#2055) angelegt, neu
/// belegt, eingestellt und entfernt werden.
///
/// Zwillingsdatei zu `smart_mode_hotkey_flow.dart`: der Ablauf „Dialog öffnen
/// → Kollision prüfen → erst dann speichern" steht in `hotkey_flow.dart`;
/// hier steht nur, welcher Eintrag der Liste gelesen und geschrieben wird.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/extra_dictation_keys.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/spoken_languages.dart';
import '../../services/dictation_key_plan.dart';
import 'hotkey_flow.dart';

/// Die Sprache, die eine neue Zusatztaste vorschlägt: die erste gesprochene
/// oder favorisierte Sprache, die keine andere Taste schon hat und nicht die
/// feste Sprache der Haupttaste ist; sonst Englisch bzw. Deutsch.
String suggestedDictationKeyLanguage(AppSettings settings) {
  final taken = {
    for (final k in settings.hotkey.extraDictationKeys) k.language,
    if (settings.sttLanguageCode != 'auto') settings.sttLanguageCode,
  };
  for (final code in [
    ...spokenLanguagesOf(settings),
    ...settings.stt.favoriteLanguages,
  ]) {
    if (code != 'auto' && !taken.contains(code)) return code;
  }
  return taken.contains('en') ? 'de' : 'en';
}

/// Öffnet den Aufzeichnungs-Dialog für eine neue Zusatztaste und legt sie
/// an — sofern die Kombination frei ist und noch Platz ist
/// ([kMaxExtraDictationKeys]).
Future<HotkeyRecordResult> addDictationKey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
}) {
  final keys = settings.hotkey.extraDictationKeys;
  if (keys.length >= kMaxExtraDictationKeys) {
    return Future.value(const HotkeyRecordResult.cancelled());
  }
  final id = nextExtraDictationKeyId(keys);
  final language = suggestedDictationKeyLanguage(settings);
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: dictationKeyActionId(id),
    // Ein Vorschlag, den der Nutzer im Dialog überschreibt: der
    // Anfangsbuchstabe der Sprache mit den Modifikatoren der Haupttaste.
    initialKey: language.substring(0, 1).toUpperCase(),
    initialDisplayKey: '',
    initialModifiers: settings.hotkeyModifiers,
    apply: (s, result) {
      final current = s.hotkey.extraDictationKeys;
      if (current.length >= kMaxExtraDictationKeys) return s;
      return s.copyWithSections(
        hotkey: s.hotkey.copyWith(
          extraDictationKeys: [
            ...current,
            ExtraDictationKey(
              id: id,
              key: result.key,
              keyDisplay: result.displayKey,
              modifiers: result.modifiers,
              language: language,
            ),
          ],
        ),
      );
    },
  );
}

/// Öffnet den Aufzeichnungs-Dialog für die Zusatztaste [key] und speichert
/// die neue Kombination — sofern sie frei ist.
Future<HotkeyRecordResult> recordDictationKey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  required ExtraDictationKey key,
}) {
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: dictationKeyActionId(key.id),
    initialKey: key.key,
    initialDisplayKey: key.keyDisplay,
    initialModifiers: key.modifiers,
    apply: (s, result) => _updateKey(
      s,
      key.id,
      (k) => k.copyWith(
        key: result.key,
        keyDisplay: result.displayKey,
        modifiers: result.modifiers,
      ),
    ),
  );
}

/// Setzt die Sprache der Zusatztaste [keyId].
Future<void> setDictationKeyLanguage(
  WidgetRef ref, {
  required String keyId,
  required String language,
}) => ref
    .read(settingsProvider.notifier)
    .updateSettings(
      (s) => _updateKey(s, keyId, (k) => k.copyWith(language: language)),
    );

/// Setzt den Smart-Modus der Zusatztaste [keyId].
Future<void> setDictationKeySmartMode(
  WidgetRef ref, {
  required String keyId,
  required ExtraDictationKeySmartMode smartMode,
}) => ref
    .read(settingsProvider.notifier)
    .updateSettings(
      (s) => _updateKey(s, keyId, (k) => k.copyWith(smartMode: smartMode)),
    );

/// Entfernt die Zusatztaste [keyId]; die Sync gibt ihre Kombination frei.
Future<void> removeDictationKey(WidgetRef ref, {required String keyId}) => ref
    .read(settingsProvider.notifier)
    .updateSettings(
      (s) => s.copyWithSections(
        hotkey: s.hotkey.copyWith(
          extraDictationKeys: [
            for (final k in s.hotkey.extraDictationKeys)
              if (k.id != keyId) k,
          ],
        ),
      ),
    );

AppSettings _updateKey(
  AppSettings s,
  String keyId,
  ExtraDictationKey Function(ExtraDictationKey key) change,
) => s.copyWithSections(
  hotkey: s.hotkey.copyWith(
    extraDictationKeys: [
      for (final k in s.hotkey.extraDictationKeys)
        k.id == keyId ? change(k) : k,
    ],
  ),
);
