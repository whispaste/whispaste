/// Was alle WhisPaste-Hotkeys teilen: das Ergebnis eines Belegungs-Versuchs
/// und die Liste, gegen die eine neue Kombination geprüft wird.
///
/// Lag bis Ticket 27 in `quick_note_hotkey_flow.dart`, weil es dort nur zwei
/// Hotkeys gab und einer davon der Schnellnotiz-Hotkey war. Mit dem dritten
/// (Snippet-Picker, Ticket 26/27) kennt [activeHotkeyBindings] alle drei — und
/// ein Dateiname, der einen davon nennt, wäre die Einladung, den vierten
/// woanders nachzubauen.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/hotkey_conflicts.dart';
import '../../widgets/hotkey_recorder.dart';

/// Wie ein Belegungs-Versuch ausgegangen ist.
enum HotkeyChange {
  /// Der Dialog wurde abgebrochen — nichts geschrieben, nichts gemeldet.
  ///
  /// Bewusst von [saved] unterschieden: eine stehende Kollisions-Meldung gehört
  /// zur Kombination, die sie ausgelöst hat, und darf durch einen abgebrochenen
  /// Dialog weder verschwinden noch bestätigt werden.
  cancelled,

  /// Die Kombination war frei und steht jetzt in den Einstellungen.
  saved,

  /// Die Kombination ist schon von einem anderen WhisPaste-Hotkey belegt und
  /// wurde deshalb **nicht** gespeichert.
  collided,
}

/// Ergebnis eines Belegungs-Versuchs (`recordQuickNoteHotkey`,
/// `recordSnippetPickerHotkey`).
class HotkeyRecordResult {
  const HotkeyRecordResult._(this.change, this.collidingActionLabel);

  const HotkeyRecordResult.cancelled() : this._(HotkeyChange.cancelled, null);

  const HotkeyRecordResult.saved() : this._(HotkeyChange.saved, null);

  const HotkeyRecordResult.collided(String actionLabel)
    : this._(HotkeyChange.collided, actionLabel);

  final HotkeyChange change;

  /// Übersetzter Name der Aktion, die die Kombination schon belegt — nur bei
  /// [HotkeyChange.collided] gesetzt.
  final String? collidingActionLabel;
}

/// Alle WhisPaste-Hotkeys, gegen die eine neue Kombination geprüft wird.
///
/// Nur eingeschaltete Hotkeys zählen: ein abgeschalteter belegt beim OS nichts,
/// also gibt es auch nichts zu kollidieren. (Kehrseite — er kollidiert dann
/// eben in dem Moment, in dem er wieder eingeschaltet wird.)
///
/// Der Snippet-Picker-Hotkey hängt hier bewusst **nur** am Umschalter und
/// nicht zusätzlich an der Plattform-Verfügbarkeit: registriert wird er (siehe
/// `HotkeyService`) auf jeder Plattform, sobald er eingeschaltet ist — diese
/// Liste bildet ab, was tatsächlich belegt ist, nicht was bedienbar angeboten
/// wird.
List<HotkeyBinding> activeHotkeyBindings(AppSettings settings, L10n l10n) => [
  if (settings.hotkeyEnabled)
    HotkeyBinding(
      actionId: 'global',
      actionLabel: l10n.settingsHotkeyActionRecording,
      key: settings.hotkeyKey,
      modifiers: settings.hotkeyModifiers,
    ),
  if (settings.quickNoteHotkey.quickNoteHotkeyEnabled)
    HotkeyBinding(
      actionId: 'quickNote',
      actionLabel: l10n.settingsHotkeyActionQuickNote,
      key: settings.quickNoteHotkey.quickNoteHotkeyKey,
      modifiers: settings.quickNoteHotkey.quickNoteHotkeyModifiers,
    ),
  if (settings.snippetPickerHotkey.snippetPickerHotkeyEnabled)
    HotkeyBinding(
      // Muss zeichengleich zur Action-ID in `HotkeyService` sein — sonst
      // schlösse `excludeActionId` den falschen Hotkey aus.
      actionId: 'snippetPicker',
      actionLabel: l10n.settingsHotkeyActionSnippetPicker,
      key: settings.snippetPickerHotkey.snippetPickerHotkeyKey,
      modifiers: settings.snippetPickerHotkey.snippetPickerHotkeyModifiers,
    ),
];

/// Der eine Ablauf hinter jedem Neu-Belegen: Dialog öffnen → Kollision prüfen
/// → erst dann speichern.
///
/// Die Reihenfolge ist die Regel „bereits belegte Kombination wird nicht
/// gespeichert", und sie steht genau einmal hier. Die Hotkey-spezifischen
/// Dateien (`quick_note_hotkey_flow.dart`, `snippet_picker_hotkey_flow.dart`)
/// sagen nur noch, *welcher* Abschnitt gelesen und geschrieben wird — je
/// weniger davon dort steht, desto weniger kann der vierte Hotkey davon
/// vergessen.
///
/// [actionId] muss zeichengleich zur Action-ID in `HotkeyService` und in
/// [activeHotkeyBindings] sein; [apply] schreibt das Ergebnis in den eigenen
/// Einstellungs-Abschnitt.
Future<HotkeyRecordResult> recordHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  required String actionId,
  required String initialKey,
  required String initialDisplayKey,
  required String initialModifiers,
  required AppSettings Function(AppSettings settings, WpHotkeyResult result)
  apply,
}) async {
  // Vor dem `await` aufgelöst: danach ist [context] möglicherweise entsorgt,
  // und die Bindings brauchen die übersetzten Aktionsnamen für die Meldung.
  final bindings = activeHotkeyBindings(settings, L10n.of(context));

  final result = await WpHotkeyRecorderDialog.show(
    context,
    initialKey: initialKey,
    initialDisplayKey: initialDisplayKey,
    initialModifiers: initialModifiers,
  );
  if (result == null) return const HotkeyRecordResult.cancelled();
  // Der Dialog kann überlebt haben, was ihn geöffnet hat (Panel geschlossen,
  // Seite gewechselt). Dann gibt es niemanden mehr, dem ein Ergebnis gehört.
  if (!context.mounted) return const HotkeyRecordResult.cancelled();

  // Vor dem Speichern, nicht danach: eine doppelt vergebene Kombination ließe
  // sich zwar speichern, aber einer der beiden Hotkeys löste danach still
  // nicht mehr aus — ohne dass irgendwo etwas sichtbar fehlschlüge. Gegen den
  // kanonischen Token geprüft, nicht gegen die Anzeige-Taste: beim OS
  // registriert wird der kanonische, also kollidiert auch nur der.
  final collision = findHotkeyCollision(
    modifiers: result.modifiers,
    key: result.key,
    bindings: bindings,
    excludeActionId: actionId,
  );
  if (collision != null) {
    return HotkeyRecordResult.collided(collision.actionLabel);
  }

  await ref
      .read(settingsProvider.notifier)
      .updateSettings((s) => apply(s, result));
  return const HotkeyRecordResult.saved();
}

/// Die Kollisions-Meldung, die jede Aufrufstelle eines Hotkey-Dialogs führt.
///
/// Zustand und keine Momentan-Meldung (Toast): der Nutzer muss den Dialog
/// erneut öffnen, um die Kollision zu beheben, und eine Meldung, die
/// währenddessen verschwindet, hilft ihm dabei nicht. Weil alle Aufrufstellen
/// (Einstellungen, Notiz-Editor, Snippets-Seite) dieselbe Entscheidung
/// treffen, steht sie hier statt drei Mal nebeneinander — samt der
/// Feinheit, dass ein *abgebrochener* Dialog eine stehende Meldung stehen
/// lässt.
mixin HotkeyCollisionNotice<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  String? _collidingAction;

  /// Übersetzter Name der Aktion, die die zuletzt gewählte Kombination schon
  /// belegt — `null`, solange nichts kollidiert.
  String? get collidingAction => _collidingAction;

  /// Verwirft eine stehende Meldung — beim Ein-/Ausschalten des Hotkeys, wo
  /// sie zur alten Kombination gehört und damit erledigt ist.
  void clearHotkeyCollision() => setState(() => _collidingAction = null);

  /// Führt [record] aus und übernimmt dessen Ausgang in die Anzeige.
  Future<void> recordAndReport(
    Future<HotkeyRecordResult> Function() record,
  ) async {
    final result = await record();
    if (!mounted) return;
    // Abbruch lässt eine stehende Meldung stehen: sie gehört zur Kombination,
    // die sie ausgelöst hat, und die ist unverändert.
    if (result.change == HotkeyChange.cancelled) return;
    setState(() => _collidingAction = result.collidingActionLabel);
  }
}
