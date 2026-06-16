/// Static settings search table — one entry per visible settings section.
///
/// The search table is the single source of truth for section keywords.
/// Each entry carries the section key (matching [SettingsPage._sectionKeys]),
/// localised title/subtitle for DE and EN, and a flat keyword list that
/// includes synonyms in both languages so searches work regardless of app
/// locale.
library;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.sectionKey,
    required this.titleDe,
    required this.titleEn,
    required this.subtitleDe,
    required this.subtitleEn,
    required this.keywords,
  });

  /// Stable identifier for this entry (currently equal to [sectionKey]).
  final String id;

  /// Section key matching [SettingsPage._sectionKeys].
  final String sectionKey;

  final String titleDe;
  final String titleEn;
  final String subtitleDe;
  final String subtitleEn;

  /// Synonym keywords in both DE and EN for accent-tolerant substring search.
  ///
  /// The title and subtitle are already searched; [keywords] adds extra
  /// synonyms that are not part of the displayed text.
  final List<String> keywords;

  /// Returns the title for the given locale language tag.
  /// Falls back to EN for any locale other than `'de'`.
  String title(String locale) => locale.startsWith('de') ? titleDe : titleEn;

  /// Returns the subtitle for the given locale language tag.
  String subtitle(String locale) =>
      locale.startsWith('de') ? subtitleDe : subtitleEn;
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

/// Static search table covering all 11 settings sections.
///
/// Keywords deliberately include both DE and EN synonyms so the matcher works
/// regardless of the app language the user has selected.
const List<SettingsSearchEntry> kSettingsSearchTable = [
  SettingsSearchEntry(
    id: 'interface',
    sectionKey: 'interface',
    titleDe: 'Oberfläche',
    titleEn: 'Interface',
    subtitleDe: 'Aussehen und Verhalten',
    subtitleEn: 'Appearance and behavior',
    keywords: [
      // DE
      'Thema', 'Hell', 'Dunkel', 'Design', 'Erscheinungsbild', 'Sprache',
      'Autostart', 'minimiert', 'Benachrichtigungen', 'Systemsprache',
      // EN
      'theme', 'dark mode', 'light mode', 'appearance', 'language',
      'startup', 'launch', 'minimized', 'notifications', 'system language',
    ],
  ),
  SettingsSearchEntry(
    id: 'stt',
    sectionKey: 'stt',
    titleDe: 'Spracherkennung',
    titleEn: 'Speech Recognition',
    subtitleDe: 'Spracherkennungsqualität und Dienst',
    subtitleEn: 'Voice recognition quality and service',
    keywords: [
      // DE
      'Modell', 'Whisper', 'Qualität', 'Transkription', 'Dienst', 'lokal',
      'Cloud', 'Sprache', 'Wartezeit', 'Vokabular', 'Wörterbuch',
      'STT', 'Sprachdienst', 'Wörter',
      // EN
      'model', 'whisper', 'quality', 'transcription', 'service', 'local',
      'on-device', 'cloud', 'language', 'timeout', 'vocabulary',
      'dictionary', 'words', 'STT', 'voice',
      // GPU (now embedded in STT section, local mode only)
      'GPU', 'Grafik', 'Beschleunigung', 'Prozessor', 'Hardware',
      'graphics', 'acceleration', 'processor', 'hardware',
    ],
  ),
  SettingsSearchEntry(
    id: 'audio',
    sectionKey: 'audio',
    titleDe: 'Audio',
    titleEn: 'Audio',
    subtitleDe: 'Mikrofon und Aufnahme',
    subtitleEn: 'Microphone and recording',
    keywords: [
      // DE
      'Mikrofon', 'Aufnahme', 'Verstärkung', 'Lautstärke', 'Push-to-Talk',
      'Taste halten', 'Eingang', 'Gain',
      // EN
      'microphone', 'recording', 'gain', 'volume', 'push to talk',
      'hold to record', 'input', 'mic',
    ],
  ),
  SettingsSearchEntry(
    id: 'afterTranscription',
    sectionKey: 'afterTranscription',
    titleDe: 'Nach der Transkription',
    titleEn: 'After Transcription',
    subtitleDe: 'Was mit dem transkribierten Text geschieht',
    subtitleEn: 'What happens with the transcribed text',
    keywords: [
      // DE
      'Zwischenablage', 'Einfügen', 'Autopaste', 'Kopieren', 'Aktion',
      'Output', 'nichts tun',
      // EN
      'clipboard', 'paste', 'auto-paste', 'copy', 'action', 'output',
      'do nothing',
    ],
  ),
  SettingsSearchEntry(
    id: 'overlay',
    sectionKey: 'overlay',
    titleDe: 'Aufnahme-Overlay',
    titleEn: 'Recording Overlay',
    subtitleDe: 'Aufnahmezustand beim Diktieren anzeigen',
    subtitleEn: 'Recording status display while dictating',
    keywords: [
      // DE
      'Overlay', 'schwebend', 'Anzeige', 'Status', 'Position', 'Fenster',
      'oben mittig', 'unten mittig', 'Startposition',
      // EN
      'overlay', 'floating window', 'display', 'status', 'position',
      'window', 'top center', 'bottom center', 'start position',
    ],
  ),
  SettingsSearchEntry(
    id: 'floatingButton',
    sectionKey: 'floatingButton',
    titleDe: 'Schwebender Button',
    titleEn: 'Floating Button',
    subtitleDe: 'Immer sichtbarer Aufnahme-Button für schnellen Zugriff',
    subtitleEn: 'Always-on-top recording button for quick access',
    keywords: [
      // DE
      'Button', 'schwebend', 'immer sichtbar', 'Aufnahme-Button',
      'Schnellzugriff',
      // EN
      'floating button', 'always on top', 'recording button', 'quick access',
      'button',
    ],
  ),
  SettingsSearchEntry(
    id: 'hotkey',
    sectionKey: 'hotkey',
    titleDe: 'Tastenkürzel',
    titleEn: 'Keyboard Shortcut',
    subtitleDe: 'Globaler Hotkey zum Starten und Stoppen der Aufnahme',
    subtitleEn: 'Global hotkey to start and stop recording',
    keywords: [
      // DE
      'Tastenkürzel', 'Tastenkombination', 'Hotkey', 'Kürzel', 'Shortcut',
      'globale Taste', 'Tastenbindung', 'Tastatur', 'Tasten',
      // EN
      'keyboard shortcut', 'hotkey', 'key binding', 'shortcut', 'global key',
      'keyboard', 'hotkeys', 'keybinding',
    ],
  ),
  SettingsSearchEntry(
    id: 'sound',
    sectionKey: 'sound',
    titleDe: 'Ton & Feedback',
    titleEn: 'Sound & Feedback',
    subtitleDe: 'Audio-Signale für Aufnahme-Ereignisse',
    subtitleEn: 'Audio cues for recording events',
    keywords: [
      // DE
      'Ton', 'Klang', 'Audio-Signal', 'Signal', 'Piep', 'Lautstärke',
      'Aufnahmeton', 'Abschluss', 'Benachrichtigung',
      // EN
      'sound', 'audio cue', 'beep', 'volume', 'recording sound',
      'notification', 'completion sound', 'cue',
    ],
  ),
  SettingsSearchEntry(
    id: 'recordingSafety',
    sectionKey: 'recordingSafety',
    titleDe: 'Aufnahme-Schutz',
    titleEn: 'Recording Safety',
    subtitleDe: 'Automatische Prüfungen und Schutzmaßnahmen',
    subtitleEn: 'Automatic checks and safeguards',
    keywords: [
      // DE
      'Schutz', 'Stille', 'automatisch stoppen', 'Timeout', 'Mikrofon-Timeout',
      'Stille-Erkennung', 'Sicherheit', 'Totmikrofon',
      // EN
      'safety', 'silence', 'auto-stop', 'timeout', 'microphone timeout',
      'silence detection', 'protection', 'dead mic',
    ],
  ),
  SettingsSearchEntry(
    id: 'history',
    sectionKey: 'history',
    titleDe: 'Verlauf',
    titleEn: 'History',
    subtitleDe: 'Aufbewahrung und automatische Bereinigung',
    subtitleEn: 'Retention and automatic cleanup',
    keywords: [
      // DE
      'Einträge', 'Papierkorb', 'Bereinigung', 'Aufbewahrung', 'Maximum',
      'automatisch löschen', 'Löschung', 'Speicher',
      // EN
      'entries', 'trash', 'cleanup', 'retention', 'maximum', 'auto-delete',
      'storage', 'delete',
    ],
  ),
  SettingsSearchEntry(
    id: 'advanced',
    sectionKey: 'advanced',
    titleDe: 'Erweitert',
    titleEn: 'Advanced',
    subtitleDe: 'Zurücksetzen, Fehlerberichte, Updates und Systemverhalten',
    subtitleEn: 'Reset, error reporting, updates, and system behavior',
    keywords: [
      // DE
      'Zurücksetzen', 'Standardwerte', 'Fehlerberichte', 'Updates',
      'Tray', 'Systemablage', 'Autopaste-Verzögerung', 'Blockliste',
      'Textersetzungen', 'Aufnahmedauer', 'Factory Reset', 'Zurücksetzen',
      // EN
      'reset', 'defaults', 'error reporting', 'updates', 'tray',
      'system tray', 'auto-paste delay', 'blocklist', 'text replacements',
      'max duration', 'factory reset', 'close to tray',
    ],
  ),
];
