/// Der eine Weg, auf dem der Schnellnotiz-Hotkey neu belegt wird.
///
/// Ticket 24 gibt der Notizen-Seite eine zweite Stelle, an der dieser Weg
/// beginnt — nicht einen zweiten Weg. Was hier steht, ist deshalb nur noch,
/// *welcher* Einstellungs-Abschnitt gelesen und geschrieben wird; die
/// Reihenfolge „Dialog öffnen → Kollision prüfen → erst dann speichern" gehört
/// allen Hotkeys und steht seit Ticket 27 samt Ergebnistyp und
/// Kollisionsliste in `hotkey_flow.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'hotkey_flow.dart';

/// Öffnet den Aufzeichnungs-Dialog für den Schnellnotiz-Hotkey und speichert
/// das Ergebnis — sofern die Kombination frei ist.
///
/// Der Aufrufer bekommt mit [HotkeyRecordResult] nur zurück, *was* passiert
/// ist, und entscheidet selbst, wie er eine Kollision anzeigt: in den
/// Einstellungen ist dafür Platz für eine eigene Hinweiszeile, im Notiz-Editor
/// ist er knapper. Die Regel selbst entscheidet keiner von beiden.
///
/// Strukturgleich zu [recordSnippetPickerHotkey] und dort belassen: geteilt ist
/// der Ablauf ([recordHotkey] in `hotkey_flow.dart`), verschieden nur der
/// Einstellungs-Abschnitt, den diese Zuordnung benennt. Weiter zusammenzulegen
/// hieße, Abschnitt und Action-ID zur Laufzeit zu wählen — mehr Indirektion als
/// Ersparnis; deshalb die `loam-ignore`-Zeile unten.
Future<HotkeyRecordResult> recordQuickNoteHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  // loam-ignore: code-duplicates – gewollte Symmetrie zu `recordSnippetPickerHotkey`, Begründung im Doc-Kommentar oben
}) {
  final quickNote = settings.quickNoteHotkey;
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: 'quickNote',
    initialKey: quickNote.quickNoteHotkeyKey,
    initialDisplayKey: quickNote.quickNoteHotkeyKeyDisplay,
    initialModifiers: quickNote.quickNoteHotkeyModifiers,
    apply: (s, result) => s.copyWithSections(
      quickNoteHotkey: s.quickNoteHotkey.copyWith(
        quickNoteHotkeyKey: result.key,
        quickNoteHotkeyKeyDisplay: result.displayKey,
        quickNoteHotkeyModifiers: result.modifiers,
      ),
    ),
  );
}

/// Schaltet den Schnellnotiz-Hotkey ein oder aus.
///
/// Zusammen mit [recordQuickNoteHotkey] hier, damit beide Aufrufstellen
/// denselben Schreibweg benutzen: der Umschalter in den Einstellungen und die
/// „einschalten"-Aktion im Notiz-Editor schreiben denselben Abschnitt.
Future<void> setQuickNoteHotkeyEnabled(WidgetRef ref, {required bool enabled}) {
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          quickNoteHotkey: s.quickNoteHotkey.copyWith(
            quickNoteHotkeyEnabled: enabled,
          ),
        ),
      );
}
