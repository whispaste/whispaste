/// Der eine Weg, auf dem der Schnellnotiz-Hotkey neu belegt wird.
///
/// Ticket 24 gibt der Notizen-Seite eine zweite Stelle, an der dieser Weg
/// beginnt — nicht einen zweiten Weg. Die Reihenfolge „Dialog öffnen →
/// Kollision prüfen → erst dann speichern" liegt deshalb hier und nicht in der
/// Einstellungs-Sektion: sie *ist* die Regel „bereits belegte Kombination wird
/// nicht gespeichert", und eine zweite Kopie davon wäre eine zweite Stelle, an
/// der man sie vergessen kann.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/hotkey_conflicts.dart';
import '../../widgets/hotkey_recorder.dart';

/// Wie ein Belegungs-Versuch ausgegangen ist.
enum QuickNoteHotkeyChange {
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

/// Ergebnis von [recordQuickNoteHotkey].
class QuickNoteHotkeyResult {
  const QuickNoteHotkeyResult._(this.change, this.collidingActionLabel);

  const QuickNoteHotkeyResult.cancelled()
    : this._(QuickNoteHotkeyChange.cancelled, null);

  const QuickNoteHotkeyResult.saved()
    : this._(QuickNoteHotkeyChange.saved, null);

  const QuickNoteHotkeyResult.collided(String actionLabel)
    : this._(QuickNoteHotkeyChange.collided, actionLabel);

  final QuickNoteHotkeyChange change;

  /// Übersetzter Name der Aktion, die die Kombination schon belegt — nur bei
  /// [QuickNoteHotkeyChange.collided] gesetzt.
  final String? collidingActionLabel;
}

/// Alle WhisPaste-Hotkeys, gegen die eine neue Kombination geprüft wird.
///
/// Nur eingeschaltete Hotkeys zählen: ein abgeschalteter belegt beim OS nichts,
/// also gibt es auch nichts zu kollidieren. (Kehrseite — er kollidiert dann
/// eben in dem Moment, in dem er wieder eingeschaltet wird.)
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
];

/// Öffnet den Aufzeichnungs-Dialog für den Schnellnotiz-Hotkey und speichert
/// das Ergebnis — sofern die Kombination frei ist.
///
/// Der Aufrufer bekommt mit [QuickNoteHotkeyResult] nur zurück, *was* passiert
/// ist, und entscheidet selbst, wie er eine Kollision anzeigt: in den
/// Einstellungen ist dafür Platz für eine eigene Hinweiszeile, im Notiz-Editor
/// ist er knapper. Die Regel selbst entscheidet keiner von beiden.
Future<QuickNoteHotkeyResult> recordQuickNoteHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
}) async {
  // Vor dem `await` aufgelöst: danach ist [context] möglicherweise entsorgt,
  // und die Bindings brauchen die übersetzten Aktionsnamen für die Meldung.
  final bindings = activeHotkeyBindings(settings, L10n.of(context));
  final quickNote = settings.quickNoteHotkey;

  final result = await WpHotkeyRecorderDialog.show(
    context,
    initialKey: quickNote.quickNoteHotkeyKey,
    initialDisplayKey: quickNote.quickNoteHotkeyKeyDisplay,
    initialModifiers: quickNote.quickNoteHotkeyModifiers,
  );
  if (result == null) return const QuickNoteHotkeyResult.cancelled();
  // Der Dialog kann überlebt haben, was ihn geöffnet hat (Panel geschlossen,
  // Seite gewechselt). Dann gibt es niemanden mehr, dem ein Ergebnis gehört.
  if (!context.mounted) return const QuickNoteHotkeyResult.cancelled();

  // Vor dem Speichern, nicht danach: eine doppelt vergebene Kombination ließe
  // sich zwar speichern, aber einer der beiden Hotkeys löste danach still
  // nicht mehr aus — ohne dass irgendwo etwas sichtbar fehlschlüge. Gegen den
  // kanonischen Token geprüft, nicht gegen die Anzeige-Taste: beim OS
  // registriert wird der kanonische, also kollidiert auch nur der.
  final collision = findHotkeyCollision(
    modifiers: result.modifiers,
    key: result.key,
    bindings: bindings,
    excludeActionId: 'quickNote',
  );
  if (collision != null) {
    return QuickNoteHotkeyResult.collided(collision.actionLabel);
  }

  await ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          quickNoteHotkey: s.quickNoteHotkey.copyWith(
            quickNoteHotkeyKey: result.key,
            quickNoteHotkeyKeyDisplay: result.displayKey,
            quickNoteHotkeyModifiers: result.modifiers,
          ),
        ),
      );
  return const QuickNoteHotkeyResult.saved();
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
