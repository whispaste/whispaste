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
  String get historyPinned => 'Favoriten';

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
  String get historyUnarchive => 'Aus Archiv holen';

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
  String historyWordCount(int count) {
    return '$count Wörter';
  }

  @override
  String historyReadingTime(int minutes) {
    return '$minutes Min. Lesezeit';
  }

  @override
  String get historyReadingTimeUnder1 => '< 1 Min. Lesezeit';

  @override
  String get historyEditing => 'Bearbeiten';

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
  String get historyEmptyTrash => 'Papierkorb leeren';

  @override
  String get historyEmptyTrashConfirm => 'Papierkorb leeren?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'Alle Elemente im Papierkorb werden endgültig gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get historyTrashEmptied => 'Papierkorb geleert';

  @override
  String get historyNoArchivedItems => 'Keine archivierten Elemente';

  @override
  String get historyNoArchivedItemsHint =>
      'Archiviere Transkriptionen, die du aufbewahren\naber nicht in der Hauptliste benötigst.';

  @override
  String get historyNoRecordingsHint =>
      'Drücke den Aufnahmeknopf oder nutze den Hotkey, um mit dem Diktieren zu beginnen.\nDeine Transkriptionen erscheinen hier.';

  @override
  String get historyCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get historyMovedToTrash => 'In den Papierkorb verschoben';

  @override
  String get historyUndo => 'Rückgängig';

  @override
  String get historyEntriesMerged => 'Einträge zusammengefügt';

  @override
  String historyMergeConfirm(int count) {
    return '$count Einträge zusammenführen?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'Die ausgewählten Einträge werden zu einem zusammengefügt. Dies kann nicht rückgängig gemacht werden.';

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
  String get historyPinToTop => 'Zu Favoriten hinzufügen';

  @override
  String get historyUnpin => 'Aus Favoriten entfernen';

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
  String get settingsStartMinimized => 'Minimiert starten';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Beim Systemstart im Hintergrund starten';

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
  String get settingsEnabled => 'Aktiviert';

  @override
  String get settingsStyle => 'Stil';

  @override
  String get settingsMicSystemDefault => 'Systemstandard';

  @override
  String get settingsMicSystemHint =>
      'Die Audio-Eingabe wird über die Systemeinstellungen verwaltet';

  @override
  String get settingsServiceOnDevicePrivate => 'Lokal auf dem Gerät';

  @override
  String get settingsQualityFastTiny => 'Schnell (Tiny)';

  @override
  String get settingsQualityBalancedSmall => 'Ausgewogen (Small)';

  @override
  String get settingsQualityHighQualityMedium => 'Hohe Qualität (Medium)';

  @override
  String get settingsQualityBestLarge => 'Beste Qualität (Large)';

  @override
  String get settingsLanguageAutoDetect => 'Automatisch erkennen';

  @override
  String get settingsLanguageEnglish => 'Englisch';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageFrench => 'Französisch';

  @override
  String get settingsLanguageSpanish => 'Spanisch';

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
  String get settingsDurationWarningSound => 'Zeitlimit-Warnung';

  @override
  String get settingsSoundVolume => 'Ton-Lautstärke';

  @override
  String get settingsAfterTranscription => 'Nach der Transkription';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'Was mit dem transkribierten Text geschieht';

  @override
  String get settingsAfterTranscriptionClipboard =>
      'In Zwischenablage kopieren';

  @override
  String get settingsAfterTranscriptionPaste => 'Automatisch einfügen';

  @override
  String get settingsAfterTranscriptionBoth => 'Kopieren & einfügen';

  @override
  String get settingsAfterTranscriptionNothing => 'Nichts tun';

  @override
  String get settingsOverlayFloatingButton => 'Aufnahme-Overlay';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Lege fest, wie der Aufnahmezustand beim Diktieren angezeigt wird';

  @override
  String get settingsShowOverlay => 'Anzeige des Aufnahme-Status';

  @override
  String get settingsShowOverlaySubtitle =>
      'Wähle, wo du während des Diktierens Live-Feedback zur Aufnahme siehst';

  @override
  String get settingsOverlayModeFloating =>
      'Schwebendes Fenster (immer sichtbar)';

  @override
  String get settingsOverlayModeOff => 'Aus';

  @override
  String get settingsOverlayStartPosition => 'Overlay-Startposition';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Wo das schwebende Overlay beim Aufnahmestart erscheint';

  @override
  String get settingsOverlayStartTopCenter => 'Oben mittig';

  @override
  String get settingsOverlayStartBottomCenter => 'Unten mittig';

  @override
  String get settingsOverlayStartLastPosition => 'Letzte Position merken';

  @override
  String get settingsShowFloatingButton => 'Schwebender Aufnahme-Button';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Kleiner immer sichtbarer Button zum Starten oder Stoppen der Aufnahme aus jeder App';

  @override
  String get settingsFloatingButtonOpacity =>
      'Deckkraft des schwebenden Buttons';

  @override
  String get settingsFloatingButtonOpacitySubtitle =>
      'Betrifft nur den schwebenden Button, nicht das Aufnahme-Overlay';

  @override
  String get settingsFloatingOverlayOpacity => 'Overlay-Deckkraft';

  @override
  String get settingsFloatingOverlayOpacitySubtitle =>
      'Transparenz des schwebenden Aufnahme-Overlays';

  @override
  String get settingsFloatingButtonSize => 'Größe des schwebenden Buttons';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Lege fest, wie präsent der immer sichtbare Button wirken soll';

  @override
  String get settingsSizeSmall => 'Klein';

  @override
  String get settingsSizeNormal => 'Normal';

  @override
  String get settingsSizeLarge => 'Groß';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsRecognitionLanguage => 'Erkennungssprache';

  @override
  String get settingsCustomVocabulary => 'Benutzerdefiniertes Vokabular';

  @override
  String get settingsCustomVocabularyHint =>
      'Namen, Fachbegriffe — verbessert die Erkennungsgenauigkeit';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'z.B. WhisPaste, Kubernetes, Dr. Müller';

  @override
  String get settingsAppLanguage => 'App-Sprache';

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
  String get settingsResetToDefaults => 'Auf Standardwerte zurücksetzen';

  @override
  String get settingsResetTitle => 'Einstellungen zurücksetzen';

  @override
  String get settingsResetMessage =>
      'Alle Einstellungen werden auf die Standardwerte zurückgesetzt. API-Schlüssel werden entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get settingsResetConfirm => 'Zurücksetzen';

  @override
  String get settingsResetSuccess => 'Einstellungen zurückgesetzt';

  @override
  String get settingsFactoryReset => 'Werksreset';

  @override
  String get settingsFactoryResetTitle => 'Werksreset';

  @override
  String get settingsFactoryResetMessage =>
      'Damit werden ALLE Daten unwiderruflich gelöscht: Diktatverlauf, Tags, Projekte, Sprachkürzel, heruntergeladene Modelle, Protokolle und Einstellungen. Die App wird in den Ausgangszustand zurückversetzt.\n\nDies kann nicht rückgängig gemacht werden.';

  @override
  String get settingsFactoryResetConfirm => 'Alles löschen';

  @override
  String get settingsFactoryResetSuccess =>
      'App wurde vollständig zurückgesetzt';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Diktate von WhisPaste 1.x migriert',
      one: '1 Diktat von WhisPaste 1.x migriert',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Aus';

  @override
  String get settingsOn => 'An';

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
  String get statusTranscriptionDone => 'Transkription abgeschlossen';

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
      'Kein Audio erkannt — bitte versuche es erneut. Manchmal braucht das Mikrofon einen Moment.';

  @override
  String get recordingAutoStopped => 'Aufnahme gestoppt — Stille erkannt.';

  @override
  String get actionCopy => 'Kopieren';

  @override
  String get actionDelete => 'Löschen';

  @override
  String get actionDismiss => 'Schließen';

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
  String get tooltipProcessing => 'Audio wird verarbeitet…';

  @override
  String get tooltipEngineNotReady => 'Sprach-Engine nicht bereit';

  @override
  String get tooltipEngineDownloading => 'Sprach-Engine wird heruntergeladen…';

  @override
  String get tooltipModelMissing => 'Kein Sprachmodell heruntergeladen';

  @override
  String get tooltipTheme => 'Design wechseln';

  @override
  String get tooltipLanguage => 'Sprache';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Einmal sprechen. Überall einfügen.';

  @override
  String get onboardingWelcomeHint =>
      'WhisPaste verwandelt schnelle Gedanken in klaren Text für Nachrichten, Mails, Notizen und Kommentare.';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackHint =>
      'Sag uns, was du denkst — wir lesen jede Nachricht.';

  @override
  String get analyticsPreviewBanner =>
      'Vorschau — zeigt Beispieldaten. Echte Statistiken erscheinen, sobald du aufnimmst.';

  @override
  String get analyticsEmptyTitle => 'Noch keine Aufnahmen';

  @override
  String get analyticsEmptySubtitle =>
      'Starte eine Aufnahme, um hier deine Statistiken zu sehen.';

  @override
  String get analyticsOverview => 'Überblick';

  @override
  String get analyticsOverviewSubtitle =>
      'Deine Diktierstatistiken auf einen Blick';

  @override
  String get analyticsActivity => 'Aktivität';

  @override
  String get analyticsInsights => 'Einblicke';

  @override
  String get analyticsTotalRecordings => 'Aufnahmen gesamt';

  @override
  String get analyticsTotalDuration => 'Gesamtdauer';

  @override
  String get analyticsWordsDictated => 'Diktierte Wörter';

  @override
  String get analyticsTimeSaved => 'Zeitersparnis';

  @override
  String get analyticsRecordingActivity => 'Aufnahmeaktivität';

  @override
  String get analyticsLast7Days => 'Letzte 7 Tage';

  @override
  String get analyticsModelUsage => 'Modellnutzung';

  @override
  String get analyticsDurationDistribution => 'Dauerverteilung';

  @override
  String get analyticsCostSavings => 'Kosten & Ersparnis';

  @override
  String get analyticsLocalSavings => 'Lokale Ersparnis';

  @override
  String get analyticsCloudCost => 'Cloud-Kosten';

  @override
  String get analyticsPeriod7d => '7 Tage';

  @override
  String get analyticsPeriod30d => '30 Tage';

  @override
  String get analyticsPeriod90d => '90 Tage';

  @override
  String get analyticsPeriodAll => 'Gesamt';

  @override
  String get analyticsReset => 'Zurücksetzen';

  @override
  String get analyticsResetTitle => 'Statistiken zurücksetzen';

  @override
  String get analyticsResetMessage =>
      'Bist du sicher, dass du alle Statistikdaten löschen möchtest? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get analyticsDayMon => 'Mo';

  @override
  String get analyticsDayTue => 'Di';

  @override
  String get analyticsDayWed => 'Mi';

  @override
  String get analyticsDayThu => 'Do';

  @override
  String get analyticsDayFri => 'Fr';

  @override
  String get analyticsDaySat => 'Sa';

  @override
  String get analyticsDaySun => 'So';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta diese Woche';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta ggü. letztem Monat';
  }

  @override
  String analyticsDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get analyticsDurationLt15s => '< 15s';

  @override
  String get analyticsDuration15To30s => '15–30s';

  @override
  String get analyticsDuration30To60s => '30–60s';

  @override
  String get analyticsDuration1To3m => '1–3m';

  @override
  String get analyticsDurationGt3m => '> 3m';

  @override
  String analyticsSavedAmount(String amount) {
    return '$amount gespart';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount ausgegeben';
  }

  @override
  String get replacementsSearch => 'Shortcuts suchen…';

  @override
  String get replacementsAdd => 'Hinzufügen';

  @override
  String get replacementsEmpty => 'Noch keine Sprach-Shortcuts';

  @override
  String get replacementsEmptyHint =>
      'Füge Shortcuts hinzu, um Wörter beim Diktieren automatisch zu ersetzen.\nBeispiel: \"mfg\" → \"mit freundlichen Grüßen\"';

  @override
  String get replacementsNoMatches => 'Keine Treffer';

  @override
  String get replacementsNoMatchesHint => 'Versuche einen anderen Suchbegriff.';

  @override
  String get replacementsToggleLabel => 'Shortcuts aktivieren';

  @override
  String get replacementsToggleEnabled => 'Sprachkürzel sind aktiv';

  @override
  String get replacementsToggleDisabled => 'Sprachkürzel sind deaktiviert';

  @override
  String get replacementsEnableBannerTitle => 'Sprachkürzel sind deaktiviert';

  @override
  String get replacementsEnableBannerHint =>
      'Aktiviere sie, damit Auslöser-Phrasen bei der Diktat-Aufnahme automatisch ersetzt werden.';

  @override
  String get replacementsEnableAction => 'Aktivieren';

  @override
  String get replacementsDisableAction => 'Deaktivieren';

  @override
  String get replacementsAddShortcut => 'Shortcut hinzufügen';

  @override
  String get replacementsEditShortcut => 'Shortcut bearbeiten';

  @override
  String get replacementsNewShortcut => 'Neuer Shortcut';

  @override
  String get replacementsDialogHint =>
      'Der Auslöser wird beim Diktieren automatisch ersetzt.';

  @override
  String get replacementsTriggerLabel => 'Auslöser';

  @override
  String get replacementsTriggerHint => 'z. B. mfg';

  @override
  String get replacementsReplacementLabel => 'Ersetzungstext';

  @override
  String get replacementsReplacementHint => 'z. B. mit freundlichen Grüßen';

  @override
  String get replacementsDeleteTitle => 'Shortcut löschen';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Shortcut \"$trigger\" entfernen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get aboutTagline => 'Sprache zu Text, sofort.';

  @override
  String get aboutWhatsNew => 'Neuigkeiten';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutReportIssue => 'Problem melden';

  @override
  String get aboutSupportTitle => 'Dieses Projekt unterstützen';

  @override
  String get aboutSupportDescription =>
      'WhisPaste ist kostenlos und Open Source unter der MIT-Lizenz. Wenn du es nützlich findest, unterstütze bitte die Entwicklung!';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Stern auf GitHub';

  @override
  String get aboutBuiltWith => 'Gebaut mit';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Plattformübergreifende UI mit Flutter. Lokale KI-Inferenz über whisper.cpp und llama.cpp.';

  @override
  String get aboutWhisper => 'whisper.cpp & OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Lokale und Cloud-Spracherkennung — schnell, genau, mehrsprachig.';

  @override
  String get aboutLlamaCpp => 'llama.cpp';

  @override
  String get aboutLlamaCppDesc =>
      'Lokale LLM-Inferenz für KI-Nachbearbeitung ohne Cloud-Abhängigkeit.';

  @override
  String get aboutPrivacyFirst => 'Privatsphäre zuerst';

  @override
  String get aboutPrivacyFirstDesc =>
      'Lokale KI-Inferenz standardmäßig — deine Stimme verlässt dein Gerät nie, es sei denn, du wählst einen Cloud-Anbieter.';

  @override
  String get aboutPrivacy => 'Datenschutz & Daten';

  @override
  String get aboutPrivacyLocal =>
      'Alle Transkriptionen und der Verlauf werden lokal auf deinem Gerät gespeichert — niemals auf externen Servern.';

  @override
  String get aboutPrivacyCloud =>
      'Cloud-Anbieter (OpenAI, Groq, Deepgram, Anthropic, Gemini) erhalten nur Audio oder Text, wenn du sie aktiv nutzt. Deren Datenschutzrichtlinien gelten.';

  @override
  String get aboutPrivacyNoTracking =>
      'Keine Analysen, kein Tracking, keine Benutzerkonten. Update-Prüfungen kontaktieren GitHub (nur Version + IP).';

  @override
  String get aboutKeyboardShortcuts => 'Tastenkürzel';

  @override
  String get aboutShortcutRecord => 'Aufnahme starten / stoppen';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutWebsite => 'Webseite';

  @override
  String get aboutGitHubRepo => 'GitHub-Repository';

  @override
  String get aboutMitLicense => 'MIT-Lizenz';

  @override
  String get aboutViewOnGitHub => 'Auf GitHub ansehen';

  @override
  String get aboutPrivacyPolicy => 'Datenschutzerklärung';

  @override
  String get aboutSystemInfo => 'Systeminformationen';

  @override
  String get aboutSystemInfoDesc =>
      'Kopiere eine kompakte Diagnosezusammenfassung für Fehlerberichte.';

  @override
  String get aboutCopyDebugInfo => 'Debug-Info kopieren';

  @override
  String get aboutCopied => 'Kopiert!';

  @override
  String get aboutMadeWith => 'Gemacht mit ♥ von Silvio Lindstedt';

  @override
  String get aboutOpenSource => 'Open Source unter der MIT-Lizenz';

  @override
  String get feedbackSubtitle =>
      'Hilf uns, WhisPaste zu verbessern — jede Stimme zählt.';

  @override
  String get feedbackCategoryLabel => 'Worum geht es?';

  @override
  String get feedbackCategoryBug => 'Fehlerbericht';

  @override
  String get feedbackCategoryFeature => 'Feature-Idee';

  @override
  String get feedbackCategoryGeneral => 'Allgemein';

  @override
  String get feedbackCategoryAiQuality => 'KI-Qualität';

  @override
  String get feedbackRatingLabel => 'Wie zufrieden bist du mit WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Erzähl uns mehr';

  @override
  String get feedbackPlaceholderBug =>
      'Beschreibe, was passiert ist und was du erwartet hast…';

  @override
  String get feedbackPlaceholderFeature =>
      'Was würdest du dir in WhisPaste wünschen?';

  @override
  String get feedbackPlaceholderAi =>
      'Wie war die Transkriptions- oder Nachbearbeitungsqualität?';

  @override
  String get feedbackPlaceholderGeneral => 'Teile deine Gedanken…';

  @override
  String get feedbackSubmit => 'Feedback senden';

  @override
  String get feedbackPrivacyNote =>
      'Dein Feedback ist anonym und verschlüsselt.';

  @override
  String get feedbackThankYou => 'Danke!';

  @override
  String get feedbackThankYouMessage =>
      'Dein Feedback hilft uns, WhisPaste für alle besser zu machen.';

  @override
  String get feedbackSendAnother => 'Weitere Nachricht senden';

  @override
  String get feedbackRatingFrustrated => 'Frustriert';

  @override
  String get feedbackRatingMeh => 'Naja';

  @override
  String get feedbackRatingOkay => 'Okay';

  @override
  String get feedbackRatingHappy => 'Zufrieden';

  @override
  String get feedbackRatingLoveIt => 'Liebe es!';

  @override
  String get feedbackSubmitting => 'Wird gesendet…';

  @override
  String get feedbackErrorRateLimited =>
      'Du hast kürzlich bereits Feedback gesendet. Bitte versuche es später erneut.';

  @override
  String get feedbackErrorNetwork =>
      'Verbindung zum Server fehlgeschlagen. Bitte prüfe deine Internetverbindung.';

  @override
  String get feedbackErrorServer =>
      'Etwas ist schiefgelaufen. Bitte versuche es später erneut.';

  @override
  String get statusBarOnDevice => 'Auf dem Gerät';

  @override
  String get statusBarOverlayFloating => 'Overlay: Schwebend';

  @override
  String get statusBarOverlayOff => 'Overlay: Aus';

  @override
  String get statusBarAfterCopy => 'Danach: Kopieren';

  @override
  String get statusBarAfterPaste => 'Danach: Einfügen';

  @override
  String get statusBarAfterBoth => 'Danach: Kopieren & Einfügen';

  @override
  String get statusBarAfterNothing => 'Danach: Manuell';

  @override
  String get sttStatusStandby => 'Bereitschaft';

  @override
  String get sttStatusStarting => 'Startet…';

  @override
  String get sttStatusReady => 'Bereit';

  @override
  String get sttStatusError => 'Fehler';

  @override
  String get statusBarSttTooltip => 'Sprach-Engine und aktueller Status';

  @override
  String get statusBarRecording => 'Aufnahme…';

  @override
  String get statusBarTranscribing => 'Transkribieren…';

  @override
  String get statusBarProcessing => 'Verarbeiten…';

  @override
  String get statusBarDone => 'Fertig';

  @override
  String get statusBarHotkeyTooltip =>
      'Globaler Hotkey — klicken zum Konfigurieren';

  @override
  String get modifierCtrl => 'Strg';

  @override
  String get modifierShift => 'Umschalt';

  @override
  String get modifierAlt => 'Alt';

  @override
  String get modifierWin => 'Win';

  @override
  String get modifierCmd => 'Befehl';

  @override
  String get modifierOption => 'Option';

  @override
  String get shortcutKeySpace => 'Leertaste';

  @override
  String get shortcutKeyEnter => 'Eingabe';

  @override
  String get shortcutKeyEscape => 'Esc';

  @override
  String get shortcutKeyBackspace => 'Backspace';

  @override
  String get shortcutKeyTab => 'Tab';

  @override
  String get shortcutKeyDelete => 'Entf';

  @override
  String get shortcutKeyInsert => 'Einfg';

  @override
  String get shortcutKeyHome => 'Pos1';

  @override
  String get shortcutKeyEnd => 'Ende';

  @override
  String get shortcutKeyPageUp => 'Bild hoch';

  @override
  String get shortcutKeyPageDown => 'Bild runter';

  @override
  String get tooltipSwitchToLight => 'Zu hellem Modus wechseln';

  @override
  String get tooltipSwitchToDark => 'Zu dunklem Modus wechseln';

  @override
  String get modelServerReady => 'Sprach-Engine bereit';

  @override
  String get modelServerMissing => 'Sprach-Engine nicht installiert';

  @override
  String get modelServerWhisper => 'Lokale Engine';

  @override
  String get modelReady => 'Bereit';

  @override
  String get modelUse => 'Verwenden';

  @override
  String get modelDownload => 'Laden';

  @override
  String get modelDownloading => 'Wird geladen…';

  @override
  String get modelDownloadingEngine => 'Sprachmodul wird vorbereitet…';

  @override
  String get modelVerifying => 'Wird überprüft…';

  @override
  String get modelExtracting => 'Wird entpackt…';

  @override
  String get modelDeleteConfirm => 'Modell löschen?';

  @override
  String get modelDeleteConfirmMessage =>
      'Die Modelldatei wird dauerhaft entfernt. Du kannst sie jederzeit erneut herunterladen.';

  @override
  String get modelSizeTiny => 'Schnelle Transkription für kurze Notizen';

  @override
  String get modelSizeBase =>
      'Schnellere Verarbeitung, ordentliche Genauigkeit';

  @override
  String get modelSizeSmall =>
      'Gute Balance aus Geschwindigkeit und Genauigkeit';

  @override
  String get modelSizeMedium =>
      'Hervorragende Genauigkeit für die meisten Anwendungsfälle';

  @override
  String get modelSizeLargeTurbo =>
      'Beste Genauigkeit mit optimierter Geschwindigkeit';

  @override
  String get modelSizeLarge => 'Maximale Genauigkeit, benötigt mehr Ressourcen';

  @override
  String get qualityTierCompactLabel => 'Schnell & Kompakt';

  @override
  String get qualityTierCompactDesc =>
      'Schnelle Ergebnisse, kleiner Download. Ideal für kurze Notizen und schnelle Nachrichten.';

  @override
  String get qualityTierBalancedLabel => 'Ausgewogen';

  @override
  String get qualityTierBalancedDesc =>
      'Zuverlässig und genau für alltägliches Diktieren. Funktioniert auf den meisten Geräten.';

  @override
  String get qualityTierPremiumLabel => 'Beste Qualität';

  @override
  String get qualityTierPremiumDesc =>
      'Höchste Genauigkeit für längere Diktate und komplexe Inhalte. Benötigt eine leistungsfähige Grafikkarte.';

  @override
  String get qualityTierRecommended => 'Empfohlen für dein Gerät';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size Download';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Herunterladen & Weiter';

  @override
  String get qualityTierChooseDifferent => 'Andere Qualitätsstufe wählen';

  @override
  String get qualityTierActive => 'Aktiv';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Beste Qualität — dauert ~${ratio}x länger';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Beste Qualität — dauert ~${ratio}x länger als Small';
  }

  @override
  String get qualityTierInfoModerate =>
      'Gutes Gleichgewicht zwischen Geschwindigkeit und Qualität';

  @override
  String get qualityTierBenchmarkReRun => 'Benchmark erneut ausführen';

  @override
  String get qualityTierBenchmarkRun => 'Benchmark starten';

  @override
  String get qualityTierInfoBenchmarking => 'Teste Leistung…';

  @override
  String get qualityTierActionOverride => 'Trotzdem verwenden';

  @override
  String get qualityTierActionOverrideHint =>
      'Diese Qualitätsstufe trotz Warnung verwenden';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

  @override
  String get settingsQualityBasic => 'Standard';

  @override
  String get settingsQualityBalanced => 'Ausgewogen';

  @override
  String get settingsQualityHigh => 'Hohe Qualität';

  @override
  String get settingsQualityBest => 'Beste Qualität';

  @override
  String get settingsQualityMaximum => 'Maximale Genauigkeit';

  @override
  String get settingsQualityRecommended => '★ Empfohlen';

  @override
  String get settingsModelStatusReady => 'Sprachmodell bereit';

  @override
  String get settingsModelStatusNeeded =>
      'Sprachmodell wird beim Start der Aufnahme heruntergeladen';

  @override
  String get settingsModelStatusDownloading =>
      'Sprachmodell wird heruntergeladen…';

  @override
  String get settingsAdvancedModelManagement =>
      'Erweiterte Modell-Einstellungen';

  @override
  String get infoEngineDownloading =>
      'Sprach-Engine wird vorbereitet. Bitte warte einen Moment.';

  @override
  String get infoEngineAutoDownload =>
      'Sprach-Engine fehlt — wird automatisch heruntergeladen…';

  @override
  String get infoModelMissing =>
      'Bitte lade zuerst ein Sprachmodell in den Einstellungen herunter.';

  @override
  String get oomRecoveryTitle =>
      'Aufnahme fehlgeschlagen — GPU-Speicherproblem';

  @override
  String get oomRecoveryMessage =>
      'Deiner GPU ist nicht mehr genügend Speicher verfügbar. Wie möchtest du fortfahren?';

  @override
  String get oomRecoveryTrySmaller => 'Kleineres Modell versuchen';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Zu $model wechseln und Aufnahme wiederholen';
  }

  @override
  String get oomRecoverySwitchCloud => 'Zur Cloud wechseln';

  @override
  String get oomRecoverySwitchCloudHint => 'Cloud-Spracherkennung verwenden';

  @override
  String get oomRecoveryCancel => 'Abbrechen';

  @override
  String get oomRecoveryPermanentTitle =>
      'Lokale Spracherkennung nicht verfügbar';

  @override
  String get oomRecoveryPermanentMessage =>
      'Alle lokalen Modelle sind wegen GPU-Speicherlimits fehlgeschlagen. Bitte wechsle in den Einstellungen zu Cloud-Spracherkennung.';

  @override
  String get oomRecoveryPermanentCloud => 'Einstellungen öffnen';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Wechsle zu $model…';
  }

  @override
  String get oomRecoverySwitchingCloud => 'Wechsle zu Cloud-Spracherkennung…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Modell $model ist ebenfalls fehlgeschlagen. Nächste Option wird versucht…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'Qualität reduziert — deiner GPU ist der Speicher ausgegangen. Es wurde auf ein kleineres Modell umgestellt.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Deiner GPU ist der Speicher ausgegangen. Für mehr Zuverlässigkeit wurde auf CPU-Modus umgestellt.';

  @override
  String get errorSttServerNotFound =>
      'Sprachmodul nicht gefunden. Bitte lade ein Sprachmodell in den Einstellungen herunter.';

  @override
  String get errorSttServerConnectionLost =>
      'Sprachmodul wurde unerwartet beendet. Bitte versuche es erneut.';

  @override
  String get errorSttCudaOom =>
      'Deiner GPU ist der Speicher ausgegangen. Die Qualität wurde reduziert, damit der nächste Versuch funktionieren sollte.';

  @override
  String get errorOnboardingNotCompleted =>
      'Bitte schließe zuerst die Einrichtung ab.';

  @override
  String get errorSttModelNotFound =>
      'Sprachmodell nicht gefunden. Bitte lade es in den Einstellungen herunter.';

  @override
  String get errorSttModelUnknown =>
      'Unbekanntes Sprachmodell. Bitte wähle ein gültiges Modell in den Einstellungen.';

  @override
  String get errorRecordingFailed =>
      'Aufnahme konnte nicht gestartet werden — bitte versuche es erneut';

  @override
  String get errorNoAudioRecorded =>
      'Keine Audiodaten aufgenommen — bitte versuche es erneut';

  @override
  String get errorTranscriptionEmpty =>
      'Transkription hat keinen Text ergeben — bitte erneut versuchen';

  @override
  String get errorSttServerFailed =>
      'Sprachmodul konnte nicht gestartet werden';

  @override
  String get errorPipelineTimeout =>
      'Aufnahme hat zu lange gedauert. Bitte versuche eine kürzere Aufnahme.';

  @override
  String get errorWavFileNotCreated =>
      'Audiodatei konnte nicht gespeichert werden. Bitte versuche es erneut.';

  @override
  String get errorWavFileEmpty =>
      'Kein Audio aufgenommen. Bitte überprüfe dein Mikrofon.';

  @override
  String get errorSttStartTimeout =>
      'Sprachmodul startet noch. Bitte versuche es gleich nochmal.';

  @override
  String get errorTranscriptionTimeout =>
      'Transkription hat zu lange gedauert. Bitte versuche eine kürzere Aufnahme.';

  @override
  String get errorMicPermissionDenied =>
      'Mikrofonzugriff wird benötigt. Bitte erlaube ihn in den Systemeinstellungen.';

  @override
  String get errorRecordingStartFailed =>
      'Aufnahme konnte nicht gestartet werden. Bitte versuche es erneut.';

  @override
  String get errorGeneric =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get modelDownloadFailed =>
      'Download fehlgeschlagen. Bitte überprüfe deine Internetverbindung.';

  @override
  String get statusSttLoading => 'Modell wird geladen…';

  @override
  String get statusSttReady => 'Modell bereit';

  @override
  String get historyDuplicate => 'Duplizieren';

  @override
  String get historyDuplicated => 'Eintrag dupliziert';

  @override
  String get historyAddNote => 'Notiz hinzufügen';

  @override
  String get historyNotes => 'Notizen';

  @override
  String get historyNotePlaceholder => 'Notiz schreiben…';

  @override
  String get historyNoteAdded => 'Notiz hinzugefügt';

  @override
  String get historyNoteDeleted => 'Notiz gelöscht';

  @override
  String get historyCopiedAsMarkdown => 'Als Markdown kopiert';

  @override
  String get historyAddTag => 'Tag hinzufügen…';

  @override
  String get historySearchTags => 'Suchen oder erstellen…';

  @override
  String get historyNoteEdited => 'bearbeitet';

  @override
  String get historyTagAdded => 'Tag hinzugefügt';

  @override
  String get historyTagRemoved => 'Tag entfernt';

  @override
  String historyCreateTag(Object tag) {
    return '„$tag“ erstellen';
  }

  @override
  String get historyManageTags => 'Tags verwalten';

  @override
  String get tagManageTitle => 'Tags verwalten';

  @override
  String get tagManageEmpty => 'Noch keine Tags erstellt.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
      zero: 'unbenutzt',
    );
    return '$_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => 'Tag löschen?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträgen',
      one: '1 Eintrag',
    );
    return 'Der Tag „$name“ wird in $_temp0 verwendet. Er wird überall entfernt.';
  }

  @override
  String tagDeleted(String name) {
    return 'Tag „$name“ gelöscht';
  }

  @override
  String get tagDeleteUnusedTitle => 'Unbenutzte Tags löschen?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unbenutzte Tags werden',
      one: '1 unbenutzter Tag wird',
    );
    return '$_temp0 dauerhaft gelöscht.';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return '$count unbenutzte löschen';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unbenutzte Tags',
      one: '1 unbenutzter Tag',
    );
    return '$_temp0 gelöscht';
  }

  @override
  String get historyEditTranscript => 'Transkript bearbeiten';

  @override
  String get historyTranscriptSaved => 'Transkript gespeichert';

  @override
  String get historySaveTranscript => 'Speichern';

  @override
  String get historyShortcutHelp => 'Tastenkürzel';

  @override
  String get historyShortcutGeneral => 'ALLGEMEIN';

  @override
  String get historyShortcutTags => 'Tag-Eingabe fokussieren';

  @override
  String get historyShortcutNotes => 'Notiz hinzufügen';

  @override
  String get historyShortcutPin => 'Favorit / entfernen';

  @override
  String get historyShortcutClose => 'Speichern & schließen';

  @override
  String get historyShortcutEditing => 'BEARBEITUNG';

  @override
  String get historyShortcutToggleEdit => 'Bearbeitungsmodus umschalten';

  @override
  String get historyShortcutSave => 'Transkript speichern';

  @override
  String get historyShortcutBold => 'Fett';

  @override
  String get historyShortcutItalic => 'Kursiv';

  @override
  String get historyShortcutCopy => 'In Zwischenablage kopieren';

  @override
  String get historyShortcutEditTitle => 'Titel bearbeiten';

  @override
  String get historyEditTitle => 'Titel bearbeiten';

  @override
  String get historyTitlePlaceholder => 'Titel eingeben…';

  @override
  String get historyTitleSaved => 'Titel gespeichert';

  @override
  String get historySearchHintCommands => 'Transkriptionen suchen…';

  @override
  String get historySearchHelpTitle => 'Suchtipps';

  @override
  String get historySearchHelpTags => 'Tippe # um nach Tags zu filtern';

  @override
  String get historySearchHelpLang => 'Tippe lang: um nach Sprache zu filtern';

  @override
  String get historySearchHelpFreeText => 'Oder gib einfach ein Stichwort ein';

  @override
  String get historySearchQuickTags => 'Beliebte Tags';

  @override
  String get historySortNewest => 'Neueste zuerst';

  @override
  String get historySortOldest => 'Älteste zuerst';

  @override
  String get historySortLongest => 'Längste zuerst';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'Nach Tag filtern';

  @override
  String get historySearchSuggestLang => 'Nach Sprache filtern';

  @override
  String get settingsKeyboardShortcut => 'Tastenkürzel';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Globaler Hotkey zum Starten und Stoppen der Aufnahme';

  @override
  String get settingsHotkeyEnabled => 'Globalen Hotkey aktivieren';

  @override
  String get settingsCurrentHotkey => 'Aktueller Hotkey';

  @override
  String get settingsChangeHotkey => 'Ändern';

  @override
  String get settingsHotkeyRecorderTitle => 'Neuen Hotkey aufnehmen';

  @override
  String get settingsHotkeyRecorderHint =>
      'Drücke die gewünschte Tastenkombination…';

  @override
  String get settingsHotkeyRecorderCancel => 'Abbrechen';

  @override
  String get settingsHotkeyRecorderSave => 'Speichern';

  @override
  String get settingsHotkeyRecorderClear => 'Zurücksetzen';

  @override
  String get settingsGeminiApiKey => 'Gemini API-Schlüssel';

  @override
  String get settingsDefaultSttProvider => 'Standard Cloud-STT';

  @override
  String get settingsDefaultSttProviderSubtitle =>
      'Cloud-Spracherkennungsdienst';

  @override
  String get settingsMaxRecordDuration => 'Maximale Aufnahmedauer';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Automatischer Sicherheitsstopp nach dieser Zeit';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Unbegrenzt';

  @override
  String get settingsCloseToTray => 'In den Infobereich minimieren';

  @override
  String get settingsCloseToTraySubtitle =>
      'Beim Schließen des Fensters im Infobereich weiterlaufen';

  @override
  String get settingsErrorReporting => 'Fehlerberichte';

  @override
  String get settingsErrorReportingSubtitle =>
      'Hilf WhisPaste zu verbessern, indem du anonyme Absturzberichte sendest';

  @override
  String get settingsAutoPasteDelay => 'Auto-Einfüge-Verzögerung';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Wartezeit vor dem Einfügen in das aktive Fenster';

  @override
  String get settingsAutoPasteBlocklist => 'Auto-Einfüge-Sperrliste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Kommagetrennte App-Kennungen, bei denen Auto-Einfügen deaktiviert ist';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'z. B. com.apple.Terminal, com.1password';

  @override
  String get settingsTextReplacements => 'Textersetzungen';

  @override
  String get settingsTextReplacementsSubtitle =>
      'Bestimmte Wörter oder Phrasen nach der Transkription automatisch ersetzen';

  @override
  String get settingsTextReplacementsEnabled => 'Textersetzungen aktivieren';

  @override
  String get settingsCheckUpdates => 'Auf Updates prüfen';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Beim Start automatisch nach neuen Versionen suchen';

  @override
  String get onboardingGetStarted => 'Weiter';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingBack => 'Zurück';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String get onboardingThemeLight => 'Hell';

  @override
  String get onboardingThemeDark => 'Dunkel';

  @override
  String get onboardingThemeSystem => 'System';

  @override
  String get onboardingMicTitle => 'Lass uns dein Mikrofon einrichten';

  @override
  String get onboardingMicSubtitle =>
      'Wir brauchen Mikrofonzugriff zum Diktieren. Dein Audio bleibt auf deinem Gerät.';

  @override
  String get onboardingMicPermissionGranted => 'Perfekt — Mikrofon ist bereit!';

  @override
  String get onboardingMicPermissionDenied => 'Mikrofonzugriff verweigert';

  @override
  String get onboardingMicPermissionPending =>
      'Tippe unten, um dein Mikrofon zu aktivieren';

  @override
  String get onboardingMicRequestAccess => 'Zugriff gewähren';

  @override
  String get onboardingMicTestTitle => 'Mikrofon testen';

  @override
  String get onboardingMicTestHint => 'Tippe zum Starten einer Testaufnahme';

  @override
  String get onboardingMicTestRecording => 'Aufnahme… sprich jetzt';

  @override
  String get onboardingMicTestDone =>
      'Klingt super — dein Mikrofon funktioniert einwandfrei!';

  @override
  String get onboardingMicDeviceLabel => 'Audio-Eingabegerät';

  @override
  String get onboardingMicDeniedInstructions =>
      'Öffne die Systemeinstellungen, um den Mikrofonzugriff zu erlauben';

  @override
  String get onboardingModelTitle => 'Spracherkennung einrichten';

  @override
  String get onboardingModelSubtitle =>
      'Lade die Sprach-Engine herunter, um offline zu diktieren — deine Stimme verlässt nie dein Gerät.';

  @override
  String get onboardingModelRecommended => 'Empfohlen für dein Gerät';

  @override
  String get onboardingModelChangeLater =>
      'Du kannst die Qualität später in den Einstellungen anpassen';

  @override
  String get onboardingModelUseCloud =>
      'Überspringen — ich nutze lieber einen Cloud-Dienst';

  @override
  String get onboardingModelDownloading => 'Wird heruntergeladen…';

  @override
  String get onboardingModelReady => 'Modell bereit';

  @override
  String get onboardingReadyTitle => 'Alles bereit!';

  @override
  String get onboardingReadySubtitle => 'So verwendest du WhisPaste';

  @override
  String get onboardingReadyStep1 =>
      'Drücke die Taste, um die Aufnahme zu starten';

  @override
  String get onboardingReadyStep2 =>
      'Drücke erneut, um zu stoppen und zu transkribieren';

  @override
  String get onboardingReadyStep3 =>
      'Der Text wird automatisch in die Zwischenablage kopiert';

  @override
  String get onboardingReadyChangeHotkey => 'Tastenkürzel ändern';

  @override
  String get onboardingReadyCurrentHotkey => 'Aktuelles Tastenkürzel';

  @override
  String get onboardingStartDictating => 'Jetzt diktieren';

  @override
  String get overlayRecording => 'Aufnahme';

  @override
  String get overlayTranscribing => 'Wird transkribiert…';

  @override
  String get overlayDone => 'Kopiert';

  @override
  String get overlayDonePasted => 'Eingefügt';

  @override
  String get overlayDoneBoth => 'Kopiert & eingefügt';

  @override
  String get overlayDoneReady => 'Fertig';

  @override
  String get overlayError => 'Fehler';

  @override
  String get overlayCancel => 'Abbrechen';

  @override
  String get overlayPause => 'Pause';

  @override
  String get overlayResume => 'Fortsetzen';

  @override
  String get overlayStop => 'Stopp';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'Drücke $hotkey zum Stoppen';
  }

  @override
  String get overlayProcessingLocal => 'Lokal';

  @override
  String get overlayProcessingCloud => 'Cloud';

  @override
  String get floatingButtonHide => 'Ausblenden';

  @override
  String get floatingButtonQuit => 'Beenden';

  @override
  String get trayStatusRecording => 'Aufnahme…';

  @override
  String get trayStatusReady => 'Bereit';

  @override
  String get trayStartRecording => 'Aufnahme starten';

  @override
  String get trayStopRecording => 'Aufnahme beenden';

  @override
  String get trayOpenApp => 'WhisPaste öffnen';

  @override
  String get traySettings => 'Einstellungen';

  @override
  String get trayQuit => 'Beenden';

  @override
  String get settingsComingSoon => 'Demnächst';

  @override
  String get undo => 'Rückgängig';

  @override
  String get voiceNoteButton => 'Sprachnotiz';

  @override
  String get voiceNoteRecording => 'Sprachnotiz wird aufgenommen…';

  @override
  String get voiceNoteTranscribing => 'Wird transkribiert…';

  @override
  String get voiceNoteAdded => 'Sprachnotiz hinzugefügt';

  @override
  String voiceTagAdded(String tag) {
    return 'Tag „$tag“ per Sprache hinzugefügt';
  }

  @override
  String get voiceCorrectionApplied => 'Transkript per Sprache korrigiert';

  @override
  String get voiceNoteEmpty => 'Keine Sprache erkannt';

  @override
  String get voiceNoteError => 'Sprachnotiz fehlgeschlagen';

  @override
  String get commandPaletteHint => 'Befehl eingeben…';

  @override
  String get commandPaletteNoResults => 'Keine passenden Befehle';

  @override
  String get commandPaletteExportText => 'Als Textdatei exportieren';

  @override
  String commandPaletteExported(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String updateAvailable(String version) {
    return 'Update verfügbar: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Update wird heruntergeladen… $percent %';
  }

  @override
  String get updateReadyToInstall => 'Update bereit — zum Installieren klicken';

  @override
  String get updateUpToDate => 'Du verwendest die neueste Version';

  @override
  String get updateCheckNow => 'Jetzt prüfen';

  @override
  String get updateInstall => 'Update installieren';

  @override
  String get updateDownload => 'Herunterladen';

  @override
  String get updateViewRelease => 'Versionshinweise';

  @override
  String get updateError => 'Update-Prüfung fehlgeschlagen';

  @override
  String get updateRateLimited =>
      'Zu viele Anfragen — versuche es später erneut';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version verfügbar';
  }

  @override
  String get settingsOverlaySize => 'Overlay-Größe';

  @override
  String get settingsOverlaySizeSubtitle =>
      'Wähle zwischen detaillierter oder minimaler Anzeige';

  @override
  String get settingsOverlaySizeNormal => 'Normal';

  @override
  String get settingsOverlaySizeCompact => 'Kompakt';

  @override
  String get settingsOverlayAutoHide => 'Automatisches Ausblenden';

  @override
  String get settingsOverlayAutoHideSubtitle =>
      'Wie lange das Overlay nach Abschluss sichtbar bleibt';

  @override
  String get settingsOverlayAutoHide2s => '2 Sekunden';

  @override
  String get settingsOverlayAutoHide5s => '5 Sekunden';

  @override
  String get settingsOverlayAutoHide10s => '10 Sekunden';

  @override
  String get settingsOverlayAutoHideManual => 'Bis manuell geschlossen';

  @override
  String get overlayRetry => 'Erneut versuchen';

  @override
  String get overlayDismiss => 'Schließen';

  @override
  String get overlayContextCancel => 'Aufnahme abbrechen';

  @override
  String get overlayContextSwitchNormal => 'Zu Normal wechseln';

  @override
  String get overlayContextSwitchCompact => 'Zu Kompakt wechseln';

  @override
  String get overlayContextHide => 'Overlay ausblenden';

  @override
  String get settingsHistory => 'Verlauf';

  @override
  String get settingsHistorySubtitle =>
      'Aufbewahrung und automatische Bereinigung';

  @override
  String get settingsHistoryMaxEntries => 'Maximale Einträge';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'Unbegrenzt';

  @override
  String get settingsHistoryAutoTrashDays => 'Papierkorb leeren nach';

  @override
  String get settingsHistoryAutoTrashNever => 'Nie';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get settingsFloatingButtonSection => 'Schwebender Button';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Immer sichtbarer Aufnahme-Button für schnellen Zugriff';

  @override
  String get settingsSttIdleTimeout => 'Sprachmodul-Leerlauf';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Wie lange das Sprachmodul nach Nutzung geladen bleibt';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Dauerhaft aktiv';

  @override
  String settingsSttIdleTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }
}
