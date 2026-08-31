/// Der eine Weg, auf dem der Smart-Mode-Hotkey neu belegt wird.
///
/// Zwillingsdatei zu `quick_note_hotkey_flow.dart`/
/// `snippet_picker_hotkey_flow.dart` und aus demselben Grund eine eigene: die
/// Einstellungen sind die einzige Aufrufstelle heute, aber der Weg selbst —
/// „Dialog öffnen → Kollision prüfen → erst dann speichern" — steht in
/// `hotkey_flow.dart`; hier steht nur, welcher Abschnitt dabei gelesen und
/// geschrieben wird (ticket 04 of `.scratch/smart-mode-v2/`).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'hotkey_flow.dart';

/// Öffnet den Aufzeichnungs-Dialog für den Smart-Mode-Hotkey und speichert
/// das Ergebnis — sofern die Kombination frei ist.
Future<HotkeyRecordResult> recordSmartModeHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  // loam-ignore: code-duplicates – Zwilling zu `recordSnippetPickerHotkey`, Begründung im Doc-Kommentar dort
}) {
  final smartMode = settings.smartModeHotkey;
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: 'smartMode',
    initialKey: smartMode.smartModeHotkeyKey,
    initialDisplayKey: smartMode.smartModeHotkeyKeyDisplay,
    initialModifiers: smartMode.smartModeHotkeyModifiers,
    apply: (s, result) => s.copyWithSections(
      smartModeHotkey: s.smartModeHotkey.copyWith(
        smartModeHotkeyKey: result.key,
        smartModeHotkeyKeyDisplay: result.displayKey,
        smartModeHotkeyModifiers: result.modifiers,
      ),
    ),
  );
}

/// Schaltet den Smart-Mode-Hotkey ein oder aus.
Future<void> setSmartModeHotkeyEnabled(WidgetRef ref, {required bool enabled}) {
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          smartModeHotkey: s.smartModeHotkey.copyWith(
            smartModeHotkeyEnabled: enabled,
          ),
        ),
      );
}

/// Setzt das an den Smart-Mode-Hotkey gebundene Preset.
///
/// Nie `off` — ein deaktivierter Hotkey wird über
/// [setSmartModeHotkeyEnabled] ausgedrückt, nicht über dieses Feld (ADR 0008).
Future<void> setSmartModeHotkeyPreset(WidgetRef ref, {required String preset}) {
  assert(preset != 'off', 'Smart-Mode hotkey preset must never be "off"');
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          smartModeHotkey: s.smartModeHotkey.copyWith(
            smartModeHotkeyPreset: preset,
          ),
        ),
      );
}
