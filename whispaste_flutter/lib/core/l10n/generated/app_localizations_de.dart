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
  String get settingsPostProcessing => 'Nachbearbeitung';

  @override
  String get settingsPostProcessingHint =>
      'Diktierten Text automatisch mit KI verbessern.';

  @override
  String get settingsTextEnhancementSubtitle =>
      'Diktierten Text automatisch bereinigen, kürzen oder übersetzen';

  @override
  String get settingsEnabled => 'Aktiviert';

  @override
  String get settingsStyle => 'Stil';

  @override
  String get settingsMicrophoneDefault => 'Standard';

  @override
  String get settingsMicrophoneHeadset => 'Headset-Mikrofon';

  @override
  String get settingsMicrophoneUsb => 'USB-Mikrofon';

  @override
  String get settingsServiceOnDevicePrivate => 'Auf dem Gerät (privat)';

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
  String get settingsOverlayFloatingButton => 'Overlay & Schwebender Button';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Bildschirm-Aufnahmesteuerung';

  @override
  String get settingsShowOverlay => 'Aufnahme-Overlay';

  @override
  String get settingsOverlayModeInWindow => 'Während der Aufnahme anzeigen';

  @override
  String get settingsOverlayModeOff => 'Aus';

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
  String get settingsResetToDefaults => 'Auf Standardwerte zurücksetzen';

  @override
  String get settingsResetDialogTitle => 'Alle Einstellungen zurücksetzen?';

  @override
  String get settingsResetConfirmMessage =>
      'Alle Einstellungen werden auf die ursprünglichen Werte zurückgesetzt. Dein Verlauf und deine Daten sind davon nicht betroffen.';

  @override
  String get settingsResetConfirm => 'Zurücksetzen';

  @override
  String get settingsResetSuccess =>
      'Einstellungen auf Standardwerte zurückgesetzt.';

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
      'Kein Audio erkannt — Mikrofon funktioniert möglicherweise nicht.';

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

  @override
  String get analyticsPreviewBanner =>
      'Vorschau — zeigt Beispieldaten. Echte Statistiken erscheinen, sobald du aufnimmst.';

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
  String get aboutFlutterGo => 'Flutter & Go';

  @override
  String get aboutFlutterGoDesc =>
      'Plattformübergreifende UI mit Flutter, performancekritisches Backend in Go via FFI.';

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
  String get aboutShortcutPalette => 'Befehlspalette';

  @override
  String get aboutShortcutSettings => 'Einstellungen';

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
  String get statusBarOnDevice => 'Auf dem Gerät';

  @override
  String get statusBarPostProcessing => 'Nachbearbeitung';

  @override
  String get sttStatusStandby => 'Bereitschaft';

  @override
  String get sttStatusStarting => 'Startet…';

  @override
  String get sttStatusReady => 'Bereit';

  @override
  String get sttStatusError => 'Fehler';

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
  String get modelDownload => 'Laden';

  @override
  String get modelDownloading => 'Wird geladen…';

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
  String get settingsQualityFast => 'Schnell';

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
  String get settingsPrivacyHintLocal => 'Deine Stimme verlässt nie dein Gerät';

  @override
  String get errorSttServerNotFound =>
      'Sprachmodul nicht gefunden. Bitte lade ein Sprachmodell in den Einstellungen herunter.';

  @override
  String get errorSttModelNotFound =>
      'Sprachmodell nicht gefunden. Bitte lade es in den Einstellungen herunter.';

  @override
  String get errorSttModelUnknown =>
      'Unbekanntes Sprachmodell. Bitte wähle ein gültiges Modell in den Einstellungen.';

  @override
  String get errorRecordingFailed => 'Aufnahme konnte nicht gestartet werden';

  @override
  String get errorNoAudioRecorded => 'Keine Audiodaten aufgenommen';

  @override
  String get errorTranscriptionEmpty =>
      'Transkription hat keinen Text ergeben — bitte erneut versuchen';

  @override
  String get errorSttServerFailed =>
      'Sprachmodul konnte nicht gestartet werden';

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
  String get settingsKeyboardShortcut => 'Tastenkürzel';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Globaler Hotkey zum Starten und Stoppen der Aufnahme';

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
  String get settingsLlmModel => 'LLM-Modell';

  @override
  String get settingsLlmModelSubtitle => 'Modell für die Cloud-Nachbearbeitung';

  @override
  String get settingsLlmModelPlaceholder => 'z.B. gpt-4o-mini';

  @override
  String get settingsCustomInstructions => 'Eigene Anweisungen';

  @override
  String get settingsCustomInstructionsSubtitle =>
      'Eigener Prompt für die KI-Nachbearbeitung';

  @override
  String get settingsCustomInstructionsPlaceholder =>
      'z.B. Verwende immer formelle Sprache…';

  @override
  String get settingsOutputLanguage => 'Ausgabesprache';

  @override
  String get settingsOutputLanguageSubtitle =>
      'Erzwinge Ausgabe in einer bestimmten Sprache';

  @override
  String get settingsOutputLanguageSameAsInput => 'Wie Eingabe';

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
  String get settingsGpuAcceleration => 'GPU-Beschleunigung';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Grafikkarte für schnellere KI-Verarbeitung nutzen';

  @override
  String get settingsGpuAuto => 'Automatisch';

  @override
  String get settingsGpuEnabled => 'Immer an';

  @override
  String get settingsGpuDisabled => 'Deaktiviert';

  @override
  String get settingsAutoPasteDelay => 'Auto-Einfüge-Verzögerung';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Wartezeit vor dem Einfügen in das aktive Fenster';

  @override
  String get settingsFloatingButtonAdvanced =>
      'Erweiterte Floating-Button-Optionen';

  @override
  String get settingsLockPosition => 'Position sperren';

  @override
  String get settingsLockPositionSubtitle =>
      'Versehentliches Verschieben verhindern';

  @override
  String get settingsAutoHide => 'Automatisch ausblenden';

  @override
  String get settingsAutoHideSubtitle =>
      'Automatisch ausblenden, wenn nicht aufgenommen wird';

  @override
  String get settingsAutoHideNever => 'Nie';

  @override
  String get settingsAutoHide5s => 'Nach 5 Sekunden';

  @override
  String get settingsAutoHideEdge => 'Am Rand anheften';

  @override
  String get onboardingGetStarted => 'Los geht\'s';

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
  String get onboardingLanguageTitle => 'Sprache wählen';

  @override
  String get onboardingLanguageSubtitle =>
      'Du kannst die Sprache jederzeit in den Einstellungen ändern';

  @override
  String get onboardingThemeTitle => 'Design wählen';

  @override
  String get onboardingThemeLight => 'Hell';

  @override
  String get onboardingThemeDark => 'Dunkel';

  @override
  String get onboardingMicTitle => 'Mikrofon einrichten';

  @override
  String get onboardingMicSubtitle =>
      'WhisPaste benötigt Mikrofonzugriff, um deine Stimme zu transkribieren';

  @override
  String get onboardingMicPermissionGranted => 'Mikrofonzugriff gewährt';

  @override
  String get onboardingMicPermissionDenied => 'Mikrofonzugriff verweigert';

  @override
  String get onboardingMicPermissionPending => 'Warte auf Berechtigung…';

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
      'Aufnahme abgeschlossen! Tippe zum Abspielen';

  @override
  String get onboardingMicDeviceLabel => 'Audio-Eingabegerät';

  @override
  String get onboardingMicDeniedInstructions =>
      'Öffne die Systemeinstellungen, um den Mikrofonzugriff zu erlauben';

  @override
  String get onboardingModelTitle => 'Spracherkennungsmodell';

  @override
  String get onboardingModelSubtitle =>
      'Lade ein Modell für lokale, private Spracherkennung herunter';

  @override
  String get onboardingModelRecommended => 'Empfohlen für dein Gerät';

  @override
  String get onboardingModelChangeLater =>
      'Du kannst das Modell jederzeit in den Einstellungen ändern';

  @override
  String get onboardingModelUseCloud => 'Stattdessen Cloud-API verwenden';

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
  String get onboardingPrivacyLocal =>
      'Alle Verarbeitung findet auf deinem Gerät statt';

  @override
  String get onboardingPrivacyBadge => '100% Privat';

  @override
  String get overlayRecording => 'Aufnahme';

  @override
  String get overlayTranscribing => 'Wird transkribiert…';

  @override
  String get overlayRefining => 'Wird verfeinert…';

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
}
