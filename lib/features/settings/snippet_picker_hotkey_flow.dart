/// Der eine Weg, auf dem der Snippet-Picker-Hotkey neu belegt wird.
///
/// Zwillingsdatei zu `quick_note_hotkey_flow.dart` und aus demselben Grund
/// eine eigene: die Einstellungen und die Snippets-Seite (Ticket 27) sind zwei
/// Aufrufstellen desselben Wegs, nicht zwei Wege. Der Weg selbst — „Dialog
/// öffnen → Kollision prüfen → erst dann speichern" — steht in
/// `hotkey_flow.dart`; hier steht nur, welcher Abschnitt dabei gelesen und
/// geschrieben wird.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'hotkey_flow.dart';

/// Öffnet den Aufzeichnungs-Dialog für den Snippet-Picker-Hotkey und speichert
/// das Ergebnis — sofern die Kombination frei ist.
///
/// Wie beim Schnellnotiz-Hotkey meldet [HotkeyRecordResult] nur, *was*
/// passiert ist; wie eine Kollision aussieht, entscheidet die Aufrufstelle.
Future<HotkeyRecordResult> recordSnippetPickerHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  // loam-ignore: code-duplicates – Zwilling zu `recordQuickNoteHotkey`, Begründung im Doc-Kommentar dort
}) {
  final snippetPicker = settings.snippetPickerHotkey;
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: 'snippetPicker',
    initialKey: snippetPicker.snippetPickerHotkeyKey,
    initialDisplayKey: snippetPicker.snippetPickerHotkeyKeyDisplay,
    initialModifiers: snippetPicker.snippetPickerHotkeyModifiers,
    apply: (s, result) => s.copyWithSections(
      snippetPickerHotkey: s.snippetPickerHotkey.copyWith(
        snippetPickerHotkeyKey: result.key,
        snippetPickerHotkeyKeyDisplay: result.displayKey,
        snippetPickerHotkeyModifiers: result.modifiers,
      ),
    ),
  );
}

/// Schaltet den Snippet-Picker-Hotkey ein oder aus.
///
/// Damit der Umschalter in den Einstellungen und die „einschalten"-Aktion auf
/// der Snippets-Seite denselben Schreibweg benutzen — es gibt genau einen
/// gespeicherten Zustand.
Future<void> setSnippetPickerHotkeyEnabled(
  WidgetRef ref, {
  required bool enabled,
}) {
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          snippetPickerHotkey: s.snippetPickerHotkey.copyWith(
            snippetPickerHotkeyEnabled: enabled,
          ),
        ),
      );
}
