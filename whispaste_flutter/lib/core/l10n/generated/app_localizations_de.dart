// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class L10nDe extends L10n {
  L10nDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'Verlauf';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navReplacements => 'Sprach-Shortcuts';

  @override
  String get navAnalytics => 'Statistiken';

  @override
  String get navAbout => 'Über';

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'Verlauf';

  @override
  String get pageSettingsTitle => 'Einstellungen';

  @override
  String get pageReplacementsTitle => 'Sprach-Shortcuts';

  @override
  String get pageAnalyticsTitle => 'Statistiken';

  @override
  String get pageAboutTitle => 'Über WhisPaste';

  @override
  String get pageFeedbackTitle => 'Feedback';

  @override
  String get historyEmpty => 'Noch keine Aufnahmen';

  @override
  String get historyEmptyHint =>
      'Drücke den Aufnahmeknopf oder nutze den Hotkey, um mit dem Diktieren zu beginnen.';

  @override
  String get historySearch => 'Suchen…';

  @override
  String get historyPinned => 'Angepinnt';

  @override
  String get historyToday => 'Heute';

  @override
  String get historyYesterday => 'Gestern';

  @override
  String get historyThisWeek => 'Diese Woche';

  @override
  String get historyOlder => 'Älter';

  @override
  String get historyAll => 'Alle';

  @override
  String get historyTrash => 'Papierkorb';

  @override
  String get historyArchive => 'Archiv';

  @override
  String get historyArchived => 'Archiviert';

  @override
  String get historyList => 'Liste';

  @override
  String get historyCards => 'Kacheln';

  @override
  String get historyCompact => 'Kompakt';

  @override
  String historyItemsSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get historyMerge => 'Zusammenfügen';

  @override
  String get historyRestore => 'Wiederherstellen';

  @override
  String get historyDeleteForever => 'Endgültig löschen';

  @override
  String get historyDeletePermanently => 'Endgültig löschen';

  @override
  String get historyUnarchive => 'Dearchivieren';

  @override
  String get historyExport => 'Exportieren';

  @override
  String get historyCopyAsMarkdown => 'Als Markdown kopieren';

  @override
  String get historyDetail => 'Details';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Dauer';

  @override
  String get historyModel => 'Modell';

  @override
  String get historyWords => 'Wörter';

  @override
  String get historyCharacters => 'Zeichen';

  @override
  String get historySearchTranscriptions => 'Transkriptionen suchen…';

  @override
  String get historyNoResults => 'Keine Ergebnisse';

  @override
  String historyNoResultsHint(String query) {
    return 'Keine Transkriptionen stimmen mit \"$query\" überein.\nVersuche einen anderen Suchbegriff.';
  }

  @override
  String get historyTrashEmpty => 'Papierkorb ist leer';

  @override
  String get historyTrashEmptyHint =>
      'Gelöschte Transkriptionen erscheinen hier.\nElemente werden nach 30 Tagen endgültig entfernt.';

  @override
  String get historyNoArchivedItems => 'Keine archivierten Elemente';

  @override
  String get historyNoArchivedItemsHint =>
      'Archiviere Transkriptionen, die du aufbewahren\naber nicht in der Hauptliste benötigst.';

  @override
  String get historyNoRecordingsHint =>
      'Drücke den Aufnahmeknopf oder nutze den Hotkey, um mit dem Diktieren zu beginnen.\nDeine Transkriptionen erscheinen hier.\n\n🔒 Alle Daten bleiben auf deinem Gerät.';

  @override
  String get historyCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get historyMovedToTrash => 'In den Papierkorb verschoben';

  @override
  String get historyUndo => 'Rückgängig';

  @override
  String get historyEntriesMerged => 'Einträge zusammengefügt';

  @override
  String get historyExitSelection => 'Auswahl beenden';

  @override
  String get historySelectMultiple => 'Mehrere auswählen';

  @override
  String get historyProcessed => 'Verarbeitet';

  @override
  String get historyOnDevice => 'Auf dem Gerät';

  @override
  String get historyUntitledRecording => 'Unbenannte Aufnahme';

  @override
  String get historyUntitled => 'Unbenannt';

  @override
  String get historyPinToTop => 'Oben anheften';

  @override
  String get historyUnpin => 'Lösen';

  @override
  String get historyCopyText => 'Text kopieren';

  @override
  String get historyClose => 'Schließen';

  @override
  String get historyLanguageLabel => 'Sprache';

  @override
  String historyResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ergebnisse',
      one: '1 Ergebnis',
    );
    return '$_temp0';
  }

  @override
  String get historySelectAll => 'Alle auswählen';

  @override
  String get historyDeselectAll => 'Auswahl aufheben';

  @override
  String get settingsInterface => 'Oberfläche';

  @override
  String get settingsInterfaceSubtitle => 'Aussehen und Verhalten';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsLaunchAtStartup => 'Beim Start ausführen';

  @override
  String get settingsShowNotifications => 'Benachrichtigungen anzeigen';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Mikrofon und Aufnahme';

  @override
  String get settingsMicrophone => 'Mikrofon';

  @override
  String get settingsGain => 'Mikrofon-Lautstärke';

  @override
  String get settingsHoldToRecord => 'Gedrückt halten für Aufnahme';

  @override
  String get settingsSpeechRecognition => 'Spracherkennung';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Spracherkennungsqualität und Dienst';

  @override
  String get settingsService => 'Dienst';

  @override
  String get settingsQuality => 'Qualität';

  @override
  String get settingsRecordingSafety => 'Aufnahme-Schutz';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Automatische Prüfungen und Schutzmaßnahmen';

  @override
  String get settingsDeadMicTimeout => 'Stilles-Mikrofon-Erkennung';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Aufnahme stoppen, wenn kein Audio erkannt wird (Sekunden). 0 = deaktiviert.';

  @override
  String get settingsAutoStopSilence => 'Auto-Stopp nach Stille';

  @override
  String get settingsAutoStopSilenceHint =>
      'Automatisch stoppen nach dieser Anzahl Sekunden Stille (nach Sprache). 0 = deaktiviert.';

  @override
  String get settingsPostProcessing => 'Textverbesserung';

  @override
  String get settingsPostProcessingHint =>
      'Diktierten Text automatisch mit KI verbessern.';

  @override
  String get settingsTextEnhancementSubtitle =>
      'Diktierten Text automatisch verbessern';

  @override
  String get settingsEnabled => 'Aktiviert';

  @override
  String get settingsStyle => 'Stil';

  @override
  String get settingsPresetCleanup => 'Bereinigen';

  @override
  String get settingsPresetConcise => 'Kürzen';

  @override
  String get settingsPresetTranslate => 'Übersetzen';

  @override
  String get settingsSoundFeedback => 'Ton & Feedback';

  @override
  String get settingsSoundFeedbackSubtitle =>
      'Audio-Signale für Aufnahme-Ereignisse';

  @override
  String get settingsRecordStartSound => 'Aufnahme-Startton';

  @override
  String get settingsRecordStopSound => 'Aufnahme-Stoppton';

  @override
  String get settingsTranscriptionCompleteSound => 'Transkription-fertig-Ton';

  @override
  String get settingsOverlayFloatingButton => 'Overlay & Schwebender Button';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Bildschirm-Aufnahmesteuerung';

  @override
  String get settingsShowOverlay => 'Overlay anzeigen';

  @override
  String get settingsShowFloatingButton => 'Schwebenden Button anzeigen';

  @override
  String get settingsFloatingButtonOpacity => 'Schwebender Button Deckkraft';

  @override
  String get settingsFloatingButtonSize => 'Schwebender Button Größe';

  @override
  String get settingsSizeSmall => 'Klein';

  @override
  String get settingsSizeNormal => 'Normal';

  @override
  String get settingsSizeLarge => 'Groß';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsSttModels => 'Spracherkennungs-Modelle';

  @override
  String get settingsCloudProviders => 'Cloud-Anbieter';

  @override
  String get settingsCloudProvidersSubtitle =>
      'API-Schlüssel für Online-Dienste';

  @override
  String get settingsOpenAiApiKey => 'OpenAI API-Schlüssel';

  @override
  String get settingsGroqApiKey => 'Groq API-Schlüssel';

  @override
  String get settingsDeepgramApiKey => 'Deepgram API-Schlüssel';

  @override
  String get settingsAnthropicApiKey => 'Anthropic API-Schlüssel';

  @override
  String get settingsAdvanced => 'Erweitert';

  @override
  String get settingsPrivacyNote =>
      'Deine Aufnahmen und Texte bleiben standardmäßig auf deinem Gerät. Cloud-Dienste werden nur verwendet, wenn du sie ausdrücklich aktivierst.';

  @override
  String get settingsOff => 'Aus';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get statusReady => 'Bereit';

  @override
  String get statusRecording => 'Aufnahme…';

  @override
  String get statusTranscribing => 'Transkribiere…';

  @override
  String get statusProcessing => 'Verarbeite…';

  @override
  String get statusCopied => 'Kopiert!';

  @override
  String get statusLocal => 'Lokal';

  @override
  String get statusCloud => 'Cloud';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get recordingGuardFailed =>
      'Kein Audio erkannt — Mikrofon funktioniert möglicherweise nicht.';

  @override
  String get recordingAutoStopped => 'Aufnahme gestoppt — Stille erkannt.';

  @override
  String get actionCopy => 'Kopieren';

  @override
  String get actionDelete => 'Löschen';

  @override
  String get actionEdit => 'Bearbeiten';

  @override
  String get actionExport => 'Exportieren';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionConfirm => 'Bestätigen';

  @override
  String get actionSave => 'Speichern';

  @override
  String get tooltipRecord => 'Aufnahme starten';

  @override
  String get tooltipStopRecord => 'Aufnahme stoppen';

  @override
  String get tooltipTheme => 'Design wechseln';

  @override
  String get tooltipLanguage => 'Sprache';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Willkommen bei WhisPaste';

  @override
  String get onboardingWelcomeHint =>
      'Premium-Diktat mit KI-Nachbearbeitung. Diktiere überall, füge überall ein.';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackHint =>
      'Sag uns, was du denkst — wir lesen jede Nachricht.';
}
