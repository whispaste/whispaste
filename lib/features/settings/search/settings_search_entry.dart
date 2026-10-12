/// Static settings search table — one entry per visible settings section.
///
/// The search table is the single source of truth for section keywords.
/// Each entry carries the section key (matching [SettingsPage._sectionKeys]),
/// the L10n keys of the section's own title and subtitle (the same strings the
/// section header renders, so chips and search hits never drift from the page),
/// and a flat keyword list that includes synonyms in both DE and EN so searches
/// work regardless of app locale.
library;

import 'package:flutter/widgets.dart';

import '../../../core/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Resolves one localised settings label from the generated [L10n] strings.
typedef SettingsSearchLabel = String Function(L10n l10n);

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.sectionKey,
    required this.titleOf,
    required this.subtitleOf,
    required this.keywords,
  });

  /// Stable identifier for this entry (currently equal to [sectionKey]).
  final String id;

  /// Section key matching [SettingsPage._sectionKeys].
  final String sectionKey;

  /// Section title as rendered by the section header (all UI languages).
  final SettingsSearchLabel titleOf;

  /// Section subtitle as rendered by the section header (all UI languages).
  final SettingsSearchLabel subtitleOf;

  /// Synonym keywords in both DE and EN for accent-tolerant substring search.
  ///
  /// The title and subtitle are already searched; [keywords] adds extra
  /// synonyms that are not part of the displayed text.
  final List<String> keywords;

  /// Returns the title for the given locale language tag (e.g. `'ru'`).
  String title(String locale) => titleOf(_l10nFor(locale));

  /// Returns the subtitle for the given locale language tag.
  String subtitle(String locale) => subtitleOf(_l10nFor(locale));
}

/// Resolves the generated [L10n] for a BCP-47 language tag. Tags without an
/// app translation fall back to English, the template locale.
L10n _l10nFor(String locale) {
  final language = locale.split(RegExp('[-_]')).first;
  final supported = L10n.supportedLocales.any(
    (l) => l.languageCode == language,
  );
  return lookupL10n(Locale(supported ? language : 'en'));
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

/// Static search table covering all settings sections.
///
/// Keywords deliberately include both DE and EN synonyms so the matcher works
/// regardless of the app language the user has selected.
final List<SettingsSearchEntry> kSettingsSearchTable = [
  SettingsSearchEntry(
    id: 'interface',
    sectionKey: 'interface',
    titleOf: (l10n) => l10n.settingsInterface,
    subtitleOf: (l10n) => l10n.settingsInterfaceSubtitle,
    keywords: [
      // DE
      'Thema', 'Hell', 'Dunkel', 'Design', 'Erscheinungsbild', 'Sprache',
      'Autostart', 'minimiert', 'Benachrichtigungen', 'Systemsprache',
      'Panel', 'Seitenpanel', 'Zwischenablage-Panel', 'Schnelleinfügen',
      'Panel-Position', 'Bildschirmkante', 'Kante', 'links', 'rechts',
      'Papierkorb', 'Ablage',
      // EN
      'theme', 'dark mode', 'light mode', 'appearance', 'language',
      'startup', 'launch', 'minimized', 'notifications', 'system language',
      'panel', 'side panel', 'quick paste', 'quick-paste', 'clipboard panel',
      'panel position', 'screen edge', 'edge', 'dock', 'tray',
      'CPU', 'indicator', 'status bar', 'utilization',
    ],
  ),
  SettingsSearchEntry(
    id: 'stt',
    sectionKey: 'stt',
    titleOf: (l10n) => l10n.settingsSpeechRecognition,
    subtitleOf: (l10n) => l10n.settingsSpeechRecognitionSubtitle,
    keywords: [
      // DE
      'Modell', 'Whisper', 'Qualität', 'Transkription', 'Dienst', 'lokal',
      'Cloud', 'Sprache', 'Wartezeit', 'Vokabular', 'Wörterbuch',
      'STT', 'Sprachdienst', 'Wörter', 'Deepgram', 'OpenAI', 'API-Schlüssel',
      'Nur Zahlen', 'Interpunktion', 'Zeichensetzung', 'Engine', 'Stille',
      'Trimmen', 'Füllwörter', 'äh', 'Zeilenumbruch', 'Absatz', 'Zeile',
      // EN
      'model', 'whisper', 'quality', 'transcription', 'service', 'local',
      'on-device', 'cloud', 'language', 'timeout', 'vocabulary',
      'dictionary', 'words', 'STT', 'voice', 'deepgram', 'openai', 'api key',
      'numbers only', 'punctuation', 'priming', 'engine', 'silence', 'trim',
      'filler words', 'filler', 'line break', 'paragraph', 'new line',
      // GPU (now embedded in STT section, local mode only)
      'GPU', 'Grafik', 'Beschleunigung', 'Prozessor', 'Hardware',
      'graphics', 'acceleration', 'processor', 'hardware',
    ],
  ),
  SettingsSearchEntry(
    id: 'smartMode',
    sectionKey: 'smartMode',
    titleOf: (l10n) => l10n.settingsSmartMode,
    subtitleOf: (l10n) => l10n.settingsSmartModeSubtitle,
    keywords: [
      // DE
      'Preset', 'Aufräumen', 'Kürzen', 'Übersetzen', 'Gemma', 'Modell',
      'herunterladen', 'Nachbearbeitung', 'Textbereinigung',
      'Auswahl bearbeiten', 'Auswahl', 'markierten Text',
      // EN
      'preset', 'cleanup', 'concise', 'translate', 'gemma', 'model',
      'download', 'post-processing', 'polish', 'edit selection', 'selection',
      'selected text', 'rewrite',
    ],
  ),
  SettingsSearchEntry(
    id: 'audio',
    sectionKey: 'audio',
    titleOf: (l10n) => l10n.settingsAudio,
    subtitleOf: (l10n) => l10n.settingsAudioSubtitle,
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
    titleOf: (l10n) => l10n.settingsAfterTranscription,
    subtitleOf: (l10n) => l10n.settingsAfterTranscriptionSubtitle,
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
    titleOf: (l10n) => l10n.settingsOverlayFloatingButton,
    subtitleOf: (l10n) => l10n.settingsOverlayFloatingButtonSubtitle,
    keywords: [
      // DE
      'Overlay', 'schwebend', 'Anzeige', 'Status', 'Position', 'Fenster',
      'oben mittig', 'unten mittig', 'Startposition', 'Live-Transkript',
      // EN
      'overlay', 'floating window', 'display', 'status', 'position',
      'window', 'top center', 'bottom center', 'start position',
      'live transcript',
    ],
  ),
  SettingsSearchEntry(
    id: 'floatingButton',
    sectionKey: 'floatingButton',
    titleOf: (l10n) => l10n.settingsFloatingButtonSection,
    subtitleOf: (l10n) => l10n.settingsFloatingButtonSectionSubtitle,
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
    titleOf: (l10n) => l10n.settingsKeyboardShortcut,
    subtitleOf: (l10n) => l10n.settingsKeyboardShortcutSubtitle,
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
    titleOf: (l10n) => l10n.settingsSoundFeedback,
    subtitleOf: (l10n) => l10n.settingsSoundFeedbackSubtitle,
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
    titleOf: (l10n) => l10n.settingsRecordingSafety,
    subtitleOf: (l10n) => l10n.settingsRecordingSafetySubtitle,
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
    titleOf: (l10n) => l10n.settingsHistory,
    subtitleOf: (l10n) => l10n.settingsHistorySubtitle,
    keywords: [
      // DE
      'Einträge', 'Papierkorb', 'Bereinigung', 'Aufbewahrung', 'Maximum',
      'automatisch löschen', 'Löschung', 'Speicher', 'verbergen', 'ausblenden',
      'Privatsphäre', 'PIN', 'sperren', 'Sperre', 'Schutz',
      // EN
      'entries', 'trash', 'cleanup', 'retention', 'maximum', 'auto-delete',
      'storage',
      'delete',
      'hide',
      'privacy',
      'lock',
      'protect',
      'PIN protection',
    ],
  ),
  SettingsSearchEntry(
    id: 'settingsPortability',
    sectionKey: 'settingsPortability',
    titleOf: (l10n) => l10n.settingsPortabilitySectionTitle,
    subtitleOf: (l10n) => l10n.settingsPortabilitySectionSubtitle,
    keywords: [
      // DE
      'Export', 'Import', 'exportieren', 'importieren', 'Umzug', 'übertragen',
      'sichern', 'Sicherung', 'wiederherstellen', 'Gerätewechsel', 'mitnehmen',
      'Datensicherung', 'neuer Rechner',
      // DE — Autosicherung (Ticket 26) lives in this section, so it has to
      // be findable under its own name and not only under "Sicherung".
      'Autosicherung', 'automatisch sichern', 'automatische Sicherung',
      // EN
      'export', 'import', 'migrate', 'transfer', 'move', 'backup', 'restore',
      'device change', 'portability', 'new computer',
      // EN — Autosicherung
      'automatic backup', 'auto backup', 'autosave',
    ],
  ),
  SettingsSearchEntry(
    id: 'advanced',
    sectionKey: 'advanced',
    titleOf: (l10n) => l10n.settingsAdvanced,
    subtitleOf: (l10n) => l10n.settingsAdvancedSubtitle,
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
  SettingsSearchEntry(
    id: 'automationApi',
    sectionKey: 'automationApi',
    titleOf: (l10n) => l10n.settingsAutomationApi,
    subtitleOf: (l10n) => l10n.settingsAutomationApiSubtitle,
    keywords: [
      // DE
      'Automatisierung', 'API', 'Skript', 'Token', 'Bearer', 'HTTP',
      'localhost', 'Port',
      // EN
      'automation', 'api', 'script', 'token', 'bearer', 'http', 'localhost',
      'port',
    ],
  ),
  SettingsSearchEntry(
    id: 'updates',
    sectionKey: 'updates',
    titleOf: (l10n) => l10n.settingsUpdates,
    subtitleOf: (l10n) => l10n.settingsUpdatesSubtitle,
    keywords: [
      // DE
      'Update', 'Beta', 'Kanal', 'Release-Kanal', 'Vorabversion', 'prüfen',
      'automatisch', 'neue Version', 'Stable', 'Version',
      // EN
      'update', 'beta', 'channel', 'release channel', 'pre-release', 'check',
      'automatic', 'new version', 'stable', 'version',
    ],
  ),
  SettingsSearchEntry(
    id: 'onboardingReview',
    sectionKey: 'onboardingReview',
    titleOf: (l10n) => l10n.onboardingReviewEntry,
    subtitleOf: (l10n) => l10n.onboardingReviewSubtitle,
    keywords: [
      // DE
      'Einführung', 'Onboarding', 'Ersteinrichtung', 'Einrichtung',
      'Rundgang', 'Tour', 'erneut', 'nochmal', 'erste Schritte',
      // EN
      'introduction', 'onboarding', 'setup', 'first run', 'tour',
      'walkthrough', 'getting started', 'again', 'replay',
    ],
  ),
  SettingsSearchEntry(
    id: 'reviewSupport',
    sectionKey: 'reviewSupport',
    titleOf: (l10n) => l10n.reviewSupportEntry,
    subtitleOf: (l10n) => l10n.reviewSupportSubtitle,
    keywords: [
      // DE
      'Bewertung', 'bewerten', 'Sterne', 'Store', 'unterstützen',
      // EN
      'rate', 'rating', 'review', 'stars', 'store', 'support',
    ],
  ),
  SettingsSearchEntry(
    id: 'privacy',
    sectionKey: 'privacy',
    titleOf: (l10n) => l10n.settingsPrivacy,
    subtitleOf: (l10n) => l10n.settingsPrivacySubtitle,
    keywords: [
      // DE
      'Datenschutz', 'Analyse', 'Statistik', 'Tracking', 'anonym',
      'Fehlerberichte', 'Absturzberichte', 'Nutzungsstatistiken',
      'Daten', 'Teilen', 'Privatsphäre', 'Aufnahmen behalten', 'kürzlich',
      // EN
      'privacy', 'analytics', 'statistics', 'tracking', 'anonymous',
      'error reports', 'crash reports', 'usage stats',
      'data', 'share', 'consent', 'keep recordings', 'recent recordings',
    ],
  ),
];
