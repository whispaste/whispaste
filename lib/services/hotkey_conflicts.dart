/// Platform-specific list of known system-reserved hotkeys.
///
/// These are combinations that the OS typically captures before any app can
/// intercept them. Registering them as global hotkeys will silently fail or
/// behave unexpectedly for the user.
///
/// The list is intentionally conservative — it covers only widely-known,
/// broadly-applicable system shortcuts. The goal is to warn users proactively,
/// not to enforce policy.
library;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import '../core/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// What the user can do about a reserved hotkey.
enum ConflictAction {
  /// Pick another combination or trigger. Every reservation allows this.
  chooseOther,

  /// Switch the system function off in the system settings (macOS dictation
  /// on a double tap of Fn). The hint names the path.
  disableInSystem,
}

/// A known system-reserved hotkey combination, or a single-key double tap.
class ConflictEntry {
  const ConflictEntry({
    required this.modifiers,
    required this.key,
    this.note,
    this.action = ConflictAction.chooseOther,
    this.doubleTapKey,
  });

  /// The [ModifierHotkey] name of a single-key double tap this entry reserves
  /// (e.g. `fn`), or null for a key combination. A double tap is a trigger,
  /// not a combination, so [findConflict] never matches such an entry.
  final String? doubleTapKey;

  /// What the user can do about this reservation.
  final ConflictAction action;

  /// Modifier set in storage format, e.g. `'meta'` or `'ctrl+alt'`.
  ///
  /// Empty string means the shortcut requires no modifier (rare — e.g. PrintScreen).
  final String modifiers;

  /// Non-modifier key label matching [WpHotkeyRecorderDialog.keyLabel] output,
  /// e.g. `'Space'`, `'Tab'`, `'F4'`, `'L'`.
  final String key;

  /// Which system function owns this combo. Rendered in the user's language
  /// by the hotkey recorder; `null` shows the key instead.
  final ConflictNote? note;

  @override
  String toString() => 'ConflictEntry($modifiers + $key)';
}

/// The system function that owns a conflicting combination. Each value maps to
/// one `hotkeyConflictNote*` ARB key, so the warning is shown in the app
/// language instead of the English OS menu names.
enum ConflictNote {
  spotlight,
  appSwitcher,
  quitApp,
  closeWindow,
  hideApp,
  minimizeWindow,
  cycleWindows,
  screenshotFullScreen,
  screenshotSelection,
  screenshotRecording,
  emojiPicker,
  forceQuit,
  lockWorkstation,
  showDesktop,
  fileExplorer,
  runDialog,
  settings,
  search,
  taskView,
  inputLanguageSwitch,
  maximizeWindow,
  snapLeft,
  snapRight,
  securityOptionsTaskManager,
  taskManager,
  lockScreenGnomeKde,
  runDialogKde,
  inputSourceGnome,
  logoutShutdownDialog,
  openTerminal,
  lockScreenGnome,
  fnDoubleTap,
  windowsDictation,
  windowsClipboardHistory,
}

// ---------------------------------------------------------------------------
// Platform-gated conflict lists
// ---------------------------------------------------------------------------

/// System hotkeys reserved on macOS.
const _macConflicts = <ConflictEntry>[
  ConflictEntry(modifiers: 'meta', key: 'Space', note: ConflictNote.spotlight),
  ConflictEntry(modifiers: 'meta', key: 'Tab', note: ConflictNote.appSwitcher),
  ConflictEntry(modifiers: 'meta', key: 'Q', note: ConflictNote.quitApp),
  ConflictEntry(modifiers: 'meta', key: 'W', note: ConflictNote.closeWindow),
  ConflictEntry(modifiers: 'meta', key: 'H', note: ConflictNote.hideApp),
  ConflictEntry(modifiers: 'meta', key: 'M', note: ConflictNote.minimizeWindow),
  ConflictEntry(modifiers: 'meta', key: '`', note: ConflictNote.cycleWindows),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '3',
    note: ConflictNote.screenshotFullScreen,
  ),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '4',
    note: ConflictNote.screenshotSelection,
  ),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '5',
    note: ConflictNote.screenshotRecording,
  ),
  ConflictEntry(
    modifiers: 'ctrl+meta',
    key: 'Space',
    note: ConflictNote.emojiPicker,
  ),
  ConflictEntry(
    modifiers: 'meta+option',
    key: 'Esc',
    note: ConflictNote.forceQuit,
  ),
  // macOS dictation: a double tap of Fn (Globe) starts the system dictation,
  // which also takes WhisPaste's Fn double tap. Switched off in Keyboard
  // settings > Dictation.
  ConflictEntry(
    modifiers: '',
    key: 'Fn',
    note: ConflictNote.fnDoubleTap,
    action: ConflictAction.disableInSystem,
    doubleTapKey: 'fn',
  ),
];

/// System hotkeys reserved on Windows.
const _windowsConflicts = <ConflictEntry>[
  ConflictEntry(
    modifiers: 'meta',
    key: 'L',
    note: ConflictNote.lockWorkstation,
  ),
  ConflictEntry(modifiers: 'meta', key: 'D', note: ConflictNote.showDesktop),
  ConflictEntry(modifiers: 'meta', key: 'E', note: ConflictNote.fileExplorer),
  ConflictEntry(modifiers: 'meta', key: 'R', note: ConflictNote.runDialog),
  ConflictEntry(modifiers: 'meta', key: 'I', note: ConflictNote.settings),
  ConflictEntry(modifiers: 'meta', key: 'S', note: ConflictNote.search),
  // Win+H starts Windows voice typing; Win+V opens the clipboard history.
  ConflictEntry(
    modifiers: 'meta',
    key: 'H',
    note: ConflictNote.windowsDictation,
  ),
  ConflictEntry(
    modifiers: 'meta',
    key: 'V',
    note: ConflictNote.windowsClipboardHistory,
  ),
  ConflictEntry(modifiers: 'meta', key: 'Tab', note: ConflictNote.taskView),
  ConflictEntry(
    modifiers: 'meta',
    key: 'Space',
    note: ConflictNote.inputLanguageSwitch,
  ),
  ConflictEntry(modifiers: 'meta', key: '↑', note: ConflictNote.maximizeWindow),
  ConflictEntry(modifiers: 'meta', key: '↓', note: ConflictNote.minimizeWindow),
  ConflictEntry(modifiers: 'meta', key: '←', note: ConflictNote.snapLeft),
  ConflictEntry(modifiers: 'meta', key: '→', note: ConflictNote.snapRight),
  ConflictEntry(modifiers: 'alt', key: 'F4', note: ConflictNote.closeWindow),
  ConflictEntry(modifiers: 'alt', key: 'Tab', note: ConflictNote.appSwitcher),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'Delete',
    note: ConflictNote.securityOptionsTaskManager,
  ),
  ConflictEntry(
    modifiers: 'ctrl+shift',
    key: 'Esc',
    note: ConflictNote.taskManager,
  ),
];

/// System hotkeys reserved on Linux (covers common GNOME & KDE defaults).
const _linuxConflicts = <ConflictEntry>[
  ConflictEntry(
    modifiers: 'meta',
    key: 'L',
    note: ConflictNote.lockScreenGnomeKde,
  ),
  ConflictEntry(modifiers: 'alt', key: 'F4', note: ConflictNote.closeWindow),
  ConflictEntry(modifiers: 'alt', key: 'Tab', note: ConflictNote.appSwitcher),
  ConflictEntry(modifiers: 'alt', key: 'F2', note: ConflictNote.runDialogKde),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'Delete',
    note: ConflictNote.logoutShutdownDialog,
  ),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'T',
    note: ConflictNote.openTerminal,
  ),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'L',
    note: ConflictNote.lockScreenGnome,
  ),
  // GNOME: Super+Space switches the input source (keyboard layout).
  ConflictEntry(
    modifiers: 'meta',
    key: 'Space',
    note: ConflictNote.inputSourceGnome,
  ),
];

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns the conflict list applicable to the current OS.
///
/// Never throws; returns an empty list on unsupported platforms (mobile/web).
///
/// Reads [defaultTargetPlatform] (the platform seam): the list is pure data, so
/// tests pin the OS with `TargetPlatformVariant` instead of depending on the
/// host.
List<ConflictEntry> get platformConflicts => conflictsFor(
  isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
  isWindows: defaultTargetPlatform == TargetPlatform.windows,
  isLinux: defaultTargetPlatform == TargetPlatform.linux,
);

/// The conflict list of one OS. Pure, so every list is testable on any host.
List<ConflictEntry> conflictsFor({
  required bool isMacOS,
  required bool isWindows,
  required bool isLinux,
}) {
  if (isMacOS) return _macConflicts;
  if (isWindows) return _windowsConflicts;
  if (isLinux) return _linuxConflicts;
  return const [];
}

/// Returns the matching [ConflictEntry] or `null` if no conflict is found.
///
/// Accepts an optional [conflicts] list for testing purposes; defaults to
/// [platformConflicts].
ConflictEntry? findConflict(
  String modifiers,
  String key, {
  List<ConflictEntry>? conflicts,
}) {
  final list = conflicts ?? platformConflicts;

  // Normalise: lower-case, sort modifier tokens so order doesn't matter.
  final normMods = _normalise(modifiers);
  final normKey = key.trim();

  for (final entry in list) {
    if (entry.doubleTapKey != null) continue;
    if (_normalise(entry.modifiers) == normMods &&
        entry.key.trim() == normKey) {
      return entry;
    }
  }
  return null;
}

/// The system entry that reserves a single-key double tap of [keyName] (a
/// [ModifierHotkey] name such as `fn`), or null when the OS does not use it.
ConflictEntry? findDoubleTapConflict(
  String keyName, {
  List<ConflictEntry>? conflicts,
}) {
  for (final entry in conflicts ?? platformConflicts) {
    if (entry.doubleTapKey == keyName) return entry;
  }
  return null;
}

/// The sentences that say what to do about [entry], one per line: pick another
/// combination, or switch the system function off where the OS allows it. The
/// system function comes first and is followed by the other way out. Two
/// separate lines, not one run-on paragraph, so each way out reads as its own
/// option (UX-107).
List<String> conflictActionLines(L10n l10n, ConflictEntry entry) =>
    switch (entry.action) {
      ConflictAction.chooseOther => [l10n.hotkeyConflictActionChooseOther],
      ConflictAction.disableInSystem => [
        l10n.hotkeyConflictActionDisableMacDictation,
        l10n.hotkeyConflictActionChooseOther,
      ],
    };

/// Localized name of the OS function behind a conflicting combination.
String conflictNoteLabel(L10n l10n, ConflictNote note) => switch (note) {
  ConflictNote.spotlight => l10n.hotkeyConflictNoteSpotlight,
  ConflictNote.appSwitcher => l10n.hotkeyConflictNoteAppSwitcher,
  ConflictNote.quitApp => l10n.hotkeyConflictNoteQuitApp,
  ConflictNote.closeWindow => l10n.hotkeyConflictNoteCloseWindow,
  ConflictNote.hideApp => l10n.hotkeyConflictNoteHideApp,
  ConflictNote.minimizeWindow => l10n.hotkeyConflictNoteMinimizeWindow,
  ConflictNote.cycleWindows => l10n.hotkeyConflictNoteCycleWindows,
  ConflictNote.screenshotFullScreen =>
    l10n.hotkeyConflictNoteScreenshotFullScreen,
  ConflictNote.screenshotSelection =>
    l10n.hotkeyConflictNoteScreenshotSelection,
  ConflictNote.screenshotRecording =>
    l10n.hotkeyConflictNoteScreenshotRecording,
  ConflictNote.emojiPicker => l10n.hotkeyConflictNoteEmojiPicker,
  ConflictNote.forceQuit => l10n.hotkeyConflictNoteForceQuit,
  ConflictNote.lockWorkstation => l10n.hotkeyConflictNoteLockWorkstation,
  ConflictNote.showDesktop => l10n.hotkeyConflictNoteShowDesktop,
  ConflictNote.fileExplorer => l10n.hotkeyConflictNoteFileExplorer,
  ConflictNote.runDialog => l10n.hotkeyConflictNoteRunDialog,
  ConflictNote.settings => l10n.hotkeyConflictNoteSettings,
  ConflictNote.search => l10n.hotkeyConflictNoteSearch,
  ConflictNote.taskView => l10n.hotkeyConflictNoteTaskView,
  ConflictNote.inputLanguageSwitch =>
    l10n.hotkeyConflictNoteInputLanguageSwitch,
  ConflictNote.maximizeWindow => l10n.hotkeyConflictNoteMaximizeWindow,
  ConflictNote.snapLeft => l10n.hotkeyConflictNoteSnapLeft,
  ConflictNote.snapRight => l10n.hotkeyConflictNoteSnapRight,
  ConflictNote.securityOptionsTaskManager =>
    l10n.hotkeyConflictNoteSecurityOptionsTaskManager,
  ConflictNote.taskManager => l10n.hotkeyConflictNoteTaskManager,
  ConflictNote.lockScreenGnomeKde => l10n.hotkeyConflictNoteLockScreenGnomeKde,
  ConflictNote.runDialogKde => l10n.hotkeyConflictNoteRunDialogKde,
  ConflictNote.logoutShutdownDialog =>
    l10n.hotkeyConflictNoteLogoutShutdownDialog,
  ConflictNote.openTerminal => l10n.hotkeyConflictNoteOpenTerminal,
  ConflictNote.lockScreenGnome => l10n.hotkeyConflictNoteLockScreenGnome,
  ConflictNote.inputSourceGnome => l10n.hotkeyConflictNoteInputSourceGnome,
  ConflictNote.fnDoubleTap => l10n.hotkeyConflictNoteFnDoubleTap,
  ConflictNote.windowsDictation => l10n.hotkeyConflictNoteWindowsDictation,
  ConflictNote.windowsClipboardHistory =>
    l10n.hotkeyConflictNoteWindowsClipboardHistory,
};

// ---------------------------------------------------------------------------
// WhisPaste-interne Doppelbelegung
// ---------------------------------------------------------------------------

/// Eine von WhisPaste selbst belegte Tastenkombination.
///
/// Bewusst getrennt von [ConflictEntry]: dort steht, was das *Betriebssystem*
/// beansprucht, hier, was die *App* beansprucht. Die beiden Prüfungen haben
/// unterschiedliche Konsequenzen — ein System-Konflikt ist eine Warnung, eine
/// interne Doppelbelegung ist ein Bedienfehler, der das Speichern verhindert,
/// weil sonst später still einer der beiden Hotkeys nicht mehr auslöst.
class HotkeyBinding {
  const HotkeyBinding({
    required this.actionId,
    required this.actionLabel,
    required this.key,
    required this.modifiers,
  });

  /// Stabile, nicht übersetzte Kennung der Aktion (z. B. `'global'`,
  /// `'quickNote'`). Dient dem Ausschluss der gerade bearbeiteten Aktion.
  final String actionId;

  /// Übersetzter Name der Aktion — geht direkt in die Meldung an den Nutzer,
  /// deshalb muss der Aufrufer ihn lokalisiert übergeben.
  final String actionLabel;

  /// Kanonischer Speicher-Token der Nicht-Modifier-Taste (z. B. `'D'`,
  /// `'Space'`). **Nicht** die layoutabhängige Anzeige-Taste: registriert wird
  /// beim OS der kanonische Token, also kollidiert auch nur der.
  ///
  /// Leer heißt „nicht konfiguriert" und kollidiert mit nichts.
  final String key;

  /// Modifier im Speicherformat, z. B. `'ctrl+shift'`.
  final String modifiers;

  @override
  String toString() => 'HotkeyBinding($actionId: $modifiers + $key)';
}

/// Sucht in [bindings] den WhisPaste-Hotkey, der ([modifiers], [key]) bereits
/// belegt — oder `null`, wenn die Kombination frei ist.
///
/// Absichtlich generisch über eine Liste statt fest gegen zwei Hotkeys
/// verdrahtet: der Aufrufer entscheidet, welche Hotkeys überhaupt in Frage
/// kommen (etwa nur die eingeschalteten), und ein dritter Hotkey kommt später
/// als weiterer Listeneintrag dazu, ohne dass diese Funktion sich ändert.
///
/// [excludeActionId] nimmt die gerade bearbeitete Aktion aus der Prüfung —
/// sonst meldete jeder Dialog, der seine eigene Kombination unverändert
/// bestätigt, eine Kollision mit sich selbst.
HotkeyBinding? findHotkeyCollision({
  required String modifiers,
  required String key,
  required Iterable<HotkeyBinding> bindings,
  String? excludeActionId,
}) {
  final normKey = _normaliseKey(key);
  // Ohne Taste gibt es keine Kombination, die belegt sein könnte.
  if (normKey.isEmpty) return null;
  final normMods = _normalise(modifiers.trim());

  for (final binding in bindings) {
    if (binding.actionId == excludeActionId) continue;
    if (_normaliseKey(binding.key) == normKey &&
        _normalise(binding.modifiers.trim()) == normMods) {
      return binding;
    }
  }
  return null;
}

/// Normalisiert einen Tasten-Token: getrimmt und klein geschrieben.
///
/// Groß-/Kleinschreibung ist bewusst egal — zwei Token, die sich nur darin
/// unterscheiden, meinen dieselbe physische Taste und müssen deshalb als
/// Doppelbelegung auffallen.
String _normaliseKey(String key) => key.trim().toLowerCase();

/// Normalises a modifier string: lower-case, tokens sorted alphabetically.
String _normalise(String modifiers) {
  if (modifiers.isEmpty) return '';
  final tokens = modifiers.toLowerCase().split('+')..sort();
  return tokens.join('+');
}
