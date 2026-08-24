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
  String get navNotes => 'Notizen';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navReplacements => 'Ersetzungen';

  @override
  String get navSnippets => 'Snippets';

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
  String get pageReplacementsTitle => 'Ersetzungen';

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
      'Drücke den Aufnahmeknopf oder nutze den Hotkey, um die Aufnahme zu starten.';

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
  String get historyExportAction => 'Exportieren…';

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
  String get historySearchFieldLabel => 'Transkriptionen suchen';

  @override
  String get historyNewRecording => 'Neue Aufnahme';

  @override
  String get historyStopRecording => 'Aufnahme beenden';

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
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Papierkorb geleert — $count Einträge gelöscht',
      one: 'Papierkorb geleert — 1 Eintrag gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get historyNoArchivedItems => 'Keine archivierten Elemente';

  @override
  String get historyNoArchivedItemsHint =>
      'Archiviere Transkriptionen, die du aufbewahren\naber nicht in der Hauptliste benötigst.';

  @override
  String get historyNoRecordingsHint =>
      'Drücke den Aufnahmeknopf oder nutze den Hotkey, um die Aufnahme zu starten.\nDeine Transkriptionen erscheinen hier.';

  @override
  String get historyNoPinned => 'Noch keine Favoriten';

  @override
  String get historyNoPinnedHint =>
      'Markiere eine Transkription als Favorit, um sie schnell wiederzufinden.';

  @override
  String get historyNoToday => 'Heute noch keine Aufnahmen';

  @override
  String get historyNoTodayHint => 'Die Aufnahmen von heute erscheinen hier.';

  @override
  String get historyNoThisWeek => 'Diese Woche noch keine Aufnahmen';

  @override
  String get historyNoThisWeekHint =>
      'Die Aufnahmen dieser Woche erscheinen hier.';

  @override
  String get historyCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get historyMovedToTrash => 'In den Papierkorb verschoben';

  @override
  String get historyUndo => 'Rückgängig';

  @override
  String get historyEntriesMerged => 'Einträge zusammengeführt';

  @override
  String historyMergeConfirm(int count) {
    return '$count Einträge zusammenführen?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'Die ausgewählten Einträge werden zu einem zusammengeführt. Dies kann nicht rückgängig gemacht werden.';

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
  String get settingsLaunchAtStartup => 'Beim Start ausführen';

  @override
  String get settingsStartMinimized => 'Minimiert starten';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Beim Systemstart im Hintergrund starten';

  @override
  String get settingsAutostartNever => 'Nie';

  @override
  String get settingsAutostartNormal => 'Normal';

  @override
  String get settingsAutostartMinimized => 'Minimiert';

  @override
  String get settingsAutostartSyncFailed =>
      'Autostart konnte nicht beim Betriebssystem registriert werden. Möglicherweise fehlen Berechtigungen oder deine Betriebssystemversion wird nicht unterstützt.';

  @override
  String get settingsShowNotifications => 'Benachrichtigungen anzeigen';

  @override
  String get settingsShowBackendUtilization =>
      'CPU/GPU-Anzeige in der Statusleiste';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Zeigt, ob die Transkription gerade wirklich per CPU oder GPU läuft, inklusive Auslastung';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Mikrofon und Aufnahme';

  @override
  String get settingsMicrophone => 'Mikrofon';

  @override
  String get settingsGain => 'Mikrofon-Lautstärke';

  @override
  String get settingsClippingBanner =>
      'Letzte Aufnahme hatte Übersteuerung. Gain reduzieren?';

  @override
  String get settingsClippingDismiss => 'Verstanden';

  @override
  String get settingsHoldToRecord => 'Gedrückt halten für Aufnahme';

  @override
  String get pushToTalkUnavailableTooltip =>
      'Auf dieser Plattform nicht verfügbar';

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
  String get settingsLanguageHebrew => 'Hebräisch';

  @override
  String get settingsSoundFeedback => 'Ton & Feedback';

  @override
  String get settingsSoundFeedbackSubtitle =>
      'Audio-Signale für Aufnahme-Ereignisse';

  @override
  String get settingsSoundsEnabled => 'Töne';

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
  String get settingsAfterTranscriptionActionLabel => 'Aktion';

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
  String get pasteFailurePermissionMissing =>
      'Auto-Einfügen vom System blockiert. WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt diese Berechtigung „Bedienungshilfen“.';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Einfügen übersprungen, keine Ziel-App erkannt. Fokussiere zuerst die Ziel-App, dann starte die Aufnahme.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Einfügen blockiert: Die Ziel-App läuft mit Administratorrechten. Starte WhisPaste ebenfalls als Administrator, um dort einzufügen.';

  @override
  String get pasteFailureGeneric =>
      'Auto-Einfügen fehlgeschlagen. Der Text ist in der Zwischenablage, füge ihn manuell mit ⌘V / Strg+V ein.';

  @override
  String get pasteFailureOpenSettings => 'Einstellungen öffnen';

  @override
  String get pasteCapabilityCheckTitle => 'Einen Moment…';

  @override
  String get pasteCapabilityReady => 'Alles bereit';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Dein Diktat landet direkt an deinem Cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Noch nicht freigegeben';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Einfügen ist auf dieser Plattform nicht verfügbar';

  @override
  String get pasteCapabilityTestButton => 'Jetzt testen';

  @override
  String get pasteCapabilityGrantButton => 'Weiter';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste braucht die Berechtigung, Text in die App einzufügen, in der du gerade schreibst — macOS nennt diese Berechtigung „Bedienungshilfen“.';

  @override
  String get pasteCapabilityTroubleshoot => 'Probleme?';

  @override
  String get pasteCapabilityRepairHint =>
      'Manchmal merkt sich macOS einen alten Eintrag und vergisst die neue Freigabe. Setz den Eintrag zurück, dann fragt macOS dich nochmal sauber.';

  @override
  String get pasteCapabilityRepairButton => 'Eintrag zurücksetzen';

  @override
  String get pasteCapabilityRestartButton => 'WhisPaste neu starten';

  @override
  String get pasteCapabilityRestartTitle =>
      'Fast fertig — WhisPaste neu starten';

  @override
  String get pasteCapabilityRestartBody =>
      'Wenn du die Berechtigung aktiviert hast, übernimmt macOS sie erst nach einem Neustart. Ein Klick — WhisPaste beendet sich und kommt sofort zurück.';

  @override
  String get pasteRestartAlertTitle => 'WhisPaste jetzt neu starten';

  @override
  String get pasteRestartAlertBody =>
      'Die Auto-Einfügen-Berechtigung ist gesetzt, greift aber erst nach einem Neustart. WhisPaste beendet sich und kommt sofort zurück.';

  @override
  String get pasteRestartAlertConfirm => 'Jetzt neu starten';

  @override
  String get pasteManualGrantAlertTitle => 'Neustart hat nicht geholfen';

  @override
  String get pasteManualGrantAlertBody =>
      'WhisPaste wurde bereits neu gestartet, aber die Auto-Einfügen-Berechtigung greift immer noch nicht. Bitte prüfe in den Systemeinstellungen unter Datenschutz & Sicherheit → Bedienungshilfen, ob WhisPaste dort aktiviert ist, und aktiviere den Schalter bei Bedarf neu.';

  @override
  String get pasteManualGrantAlertConfirm => 'Systemeinstellungen öffnen';

  @override
  String get permissionAlertLaterButton => 'Später';

  @override
  String get micGateAlertTitle => 'Mikrofonzugriff fehlt';

  @override
  String get micGateAlertBody =>
      'Ohne Mikrofonzugriff kann WhisPaste nichts aufnehmen. Bestätige, um Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon zu öffnen — aktiviere dort den Schalter für WhisPaste. Deine Freigabe erkennt WhisPaste automatisch.';

  @override
  String get micGateAlertBodyGeneric =>
      'Ohne Mikrofonzugriff kann WhisPaste nichts aufnehmen. Bitte erlaube WhisPaste den Mikrofonzugriff in den Datenschutz-Einstellungen deines Systems — deine Freigabe erkennt WhisPaste automatisch.';

  @override
  String get micGateAlertConfirm => 'Einstellungen öffnen';

  @override
  String get micGateRestartAlertTitle => 'Zum Abschluss WhisPaste neu starten';

  @override
  String get micGateRestartAlertBody =>
      'Der Mikrofonzugriff ist erteilt, aber diese laufende WhisPaste-Instanz kann ihn noch nicht übernehmen. WhisPaste beendet sich und kommt sofort zurück — alles bleibt, wie es ist.';

  @override
  String get micGateRestartAlertConfirm => 'Jetzt neu starten';

  @override
  String get autoPasteGateAlertTitle =>
      'Fürs automatische Einfügen fehlt ein Schalter';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste fügt dein Diktat direkt an der Schreibmarke ein. macOS verlangt dafür einen Schalter, den nur du umlegen kannst: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen. Bestätige, um genau diese Seite zu öffnen — deine Freigabe erkennt WhisPaste automatisch und startet sich danach bei Bedarf selbst neu.';

  @override
  String get autoPasteGateAlertConfirm => 'Systemeinstellungen öffnen';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'Neustart hat die Berechtigung nicht übernommen';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'Öffne die Berechtigung erneut und prüfe in Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen, ob WhisPaste dort wirklich aktiviert ist. Aktiviere den Schalter neu, dann startet WhisPaste noch einmal.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count veraltete Einträge entfernt. Bitte einmal Paste auslösen, um die neuen Prompts zu sehen.',
      one:
          '1 veralteter Eintrag entfernt. Bitte einmal Paste auslösen, um den neuen Prompt zu sehen.',
      zero: 'Keine veralteten Einträge gefunden. Bitte einmal Paste auslösen.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'Kein alter Eintrag gefunden. Wahrscheinlich hilft jetzt ein Neustart.';

  @override
  String get pasteCapabilityRepairFailed =>
      'macOS-Berechtigungs-Reset konnte nicht ausgeführt werden. Bitte WhisPaste manuell aus Systemeinstellungen → Bedienungshilfen entfernen.';

  @override
  String get onboardingPasteTitle =>
      'Damit dein Text dort landet, wo du tippst';

  @override
  String get onboardingPasteSubtitle =>
      'macOS fragt dich gleich, ob WhisPaste das darf. Sag Ja, fertig.';

  @override
  String get onboardingPasteSubtitleWin =>
      'Unter Windows ist keine Berechtigung nötig — entscheide nur, ob WhisPaste diktierten Text automatisch für dich einfügen soll.';

  @override
  String get onboardingPasteChipReady => 'Auto-Einfügen bereit';

  @override
  String get onboardingPasteChipPending => 'Auto-Einfügen-Zugriff ausstehend';

  @override
  String get onboardingPasteChipAction => 'Auto-Einfügen: Aktion nötig';

  @override
  String get onboardingPasteGrantCta => 'Auto-Einfügen freigeben';

  @override
  String get onboardingPasteSkip => 'Erstmal nur kopieren, ohne Auto-Einfügen';

  @override
  String get onboardingPasteWhyMac =>
      'Ohne Freigabe wird dein Text in die Zwischenablage kopiert. Du musst dann selbst mit ⌘V einfügen.';

  @override
  String get onboardingPasteWhyWin =>
      'Auto-Paste drückt nach jedem Diktat Strg+V für dich — der Text landet direkt dort, wo du gerade schreibst. Auf diesem Gerät geprüft, unten aktivieren.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'In bestimmten Apps mit UIPI/UAC-Schutz wird Auto-Paste nicht funktionieren. Der Text liegt dann in der Zwischenablage und du fügst mit Ctrl+V ein.';

  @override
  String get onboardingPasteWinOnTitle => 'Auto-Paste ist aktiv';

  @override
  String get onboardingPasteWinOnDetail =>
      'Nach jedem Diktat drückt WhisPaste Strg+V für dich — der Text landet direkt an deinem Cursor. Eine Kopie bleibt zusätzlich in der Zwischenablage.';

  @override
  String get onboardingPasteWinEnableCta => 'Auto-Paste aktivieren';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'Apps, die als Administrator laufen, nehmen simulierte Tastendrücke nicht an — dort bleibt dein Text in der Zwischenablage, bereit zum Einfügen mit Strg+V.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Setz das Häkchen bei WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Die Systemeinstellungen sind offen. Such WhisPaste in der Liste und schalt es ein.\n\nNicht in der Liste? Zieh das App-Symbol einfach rein oder klick auf „+\".';

  @override
  String get onboardingPasteTestTitle => 'Probier Auto-Paste aus';

  @override
  String get onboardingPasteTestSubtitle =>
      'Drück den Button. Der Demo-Text sollte gleich im Feld unten erscheinen.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste tippt für dich.';

  @override
  String get onboardingPasteTestSuccess =>
      'Auto-Paste funktioniert! Klick auf Weiter.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'Kein Eingabefeld erkannt. Bitte ins Feld unten klicken und nochmal probieren.';

  @override
  String get onboardingPasteTestFailure =>
      'Test fehlgeschlagen. Vielleicht hilft ein App-Neustart, oder fahre ohne Test fort.';

  @override
  String get onboardingPasteTestSkip => 'Ohne Test fortfahren';

  @override
  String get settingsOverlayFloatingButton => 'Aufnahme-Overlay';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Lege fest, wie der Aufnahmezustand beim Aufnehmen angezeigt wird';

  @override
  String get settingsShowOverlay => 'Anzeige des Aufnahme-Status';

  @override
  String get settingsShowOverlaySubtitle =>
      'Wähle, wo du beim Aufnehmen Live-Feedback zur Aufnahme siehst';

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
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsRecognitionLanguage => 'Erkennungssprache';

  @override
  String get settingsCustomVocabulary => 'Benutzerdefiniertes Vokabular';

  @override
  String get settingsCustomVocabularyHint =>
      'Namen, Fachbegriffe: verbessert die Erkennungsgenauigkeit';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'z.B. WhisPaste, Kubernetes, Dr. Müller';

  @override
  String get settingsPunctuationPriming => 'Satzzeichen anregen';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Bringt Whisper dazu, eher Satzzeichen zu setzen, wenn kein benutzerdefiniertes Vokabular hinterlegt ist. Hat keinen Einfluss auf die Geschwindigkeit.';

  @override
  String get settingsVadEnabled => 'Stille am Ende entfernen';

  @override
  String get settingsVadEnabledSubtitle =>
      'Entfernt lange Stille bzw. Rauschen am Ende einer Aufnahme, bevor Whisper sie decodiert – so kann dort kein erfundener Schlusssatz entstehen (z. B. halluziniertes „Vielen Dank\"). Kaum spürbarer Zeitaufwand, ausschaltbar, falls du lieber Whispers unbearbeitete Ausgabe möchtest.';

  @override
  String get settingsStripPunctuation => 'Satzzeichen entfernen';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Entfernt Punkte, Kommas und andere Satzzeichen aus jedem Transkript, bevor es gespeichert oder eingefügt wird. Funktioniert bei jeder Engine und jedem Anbieter gleich, nicht nur bei Whisper.';

  @override
  String get settingsNumericOnlyMode => 'Nur Zahlen';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Wandelt gesprochene Zahlen (Deutsch und Englisch) in Ziffern um, z. B. wird „fünf Komma zwei“ zu „5,2“. Lässt das Transkript unverändert, wenn es nicht vollständig umwandelbar ist.';

  @override
  String get settingsAppLanguage => 'App-Sprache';

  @override
  String get settingsSttModels => 'Spracherkennungs-Modelle';

  @override
  String get settingsOpenAiApiKey => 'OpenAI API-Schlüssel';

  @override
  String get settingsDeepgramApiKey => 'Deepgram API-Schlüssel';

  @override
  String get settingsToggleApiKeyVisibility =>
      'API-Schlüssel anzeigen/verbergen';

  @override
  String get settingsAdvanced => 'Erweitert';

  @override
  String get settingsAdvancedSubtitle =>
      'Zurücksetzen, Fehlerberichte, Updates und Systemverhalten';

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
      'Damit werden ALLE Daten unwiderruflich gelöscht: Aufnahmeverlauf, Tags, Ersetzungen, heruntergeladene Modelle, Protokolle und Einstellungen. Die App wird in den Ausgangszustand zurückversetzt.\n\nDies kann nicht rückgängig gemacht werden.';

  @override
  String get settingsFactoryResetConfirm => 'Alles löschen';

  @override
  String get settingsFactoryResetSuccess =>
      'App wurde vollständig zurückgesetzt';

  @override
  String get settingsFactoryResetProgressTitle =>
      'WhisPaste wird zurückgesetzt';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Beende Sprachdienst…';

  @override
  String get settingsFactoryResetPhaseDeletingModels => 'Lösche Sprachmodelle…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase => 'Lösche Datenbank…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Setze Anmeldedaten zurück…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Setze Einstellungen zurück…';

  @override
  String get settingsFactoryResetFailedMessage =>
      'Werks-Reset unvollständig. App neu starten?';

  @override
  String get settingsPortabilitySectionTitle => 'Sicherung & Übertragung';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'Lege eine Sicherung deiner WhisPaste-Einrichtung an oder nimm sie mit auf einen anderen Rechner';

  @override
  String get settingsPortabilityExportAction => 'Exportieren';

  @override
  String get settingsPortabilityImportAction => 'Importieren';

  @override
  String get settingsPortabilityExportLocationLabel => 'Exportziel';

  @override
  String get settingsPortabilityImportLocationLabel => 'Importquelle';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'Wird beim ersten Export gefragt';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'Wird beim ersten Import gefragt';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'Anderes Exportziel wählen (es wird noch nichts exportiert)';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'Andere Importquelle wählen (es wird noch nichts importiert)';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'Einstellungen exportiert nach $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'Export fehlgeschlagen: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle =>
      'Einstellungen importieren?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'Dies ersetzt deine aktuellen Einstellungen – Oberfläche, Spracherkennungs-Konfiguration, Verhalten, Textersetzungen und Snippets eingeschlossen – durch den Inhalt von $path. Deine API-Schlüssel bleiben unangetastet.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'Einstellungen importiert aus $path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'Keine Exportdatei unter $path gefunden. Zuerst Einstellungen exportieren oder eine Exportdatei dorthin kopieren.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'Import fehlgeschlagen: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'Autosicherung';

  @override
  String get settingsAutosaveHint =>
      'Sichert deine Einrichtung wenige Sekunden nach jeder Änderung in den gewählten Ordner';

  @override
  String get settingsAutosaveChooseFolder =>
      'Anderen Ordner für die Autosicherung wählen (es wird noch nichts gesichert)';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'Letzte Sicherung: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'Noch keine Sicherung';

  @override
  String get settingsAutosaveLastRunFailed => 'Sicherung fehlgeschlagen';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'Letzter Versuch fehlgeschlagen – letzte Sicherung: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'Autosicherung fehlgeschlagen: Der gewählte Ordner ist nicht erreichbar.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'Autosicherung fehlgeschlagen: $reason';
  }

  @override
  String get groqRemovedToast =>
      'Groq STT wurde entfernt. Provider auf On-Device zurückgesetzt.';

  @override
  String get tccResetAfterUpdateToast =>
      'macOS hat deine Auto-Paste-Berechtigung beim Update zurückgesetzt.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufnahmen von WhisPaste 1.x migriert',
      one: '1 Aufnahme von WhisPaste 1.x migriert',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Aus';

  @override
  String get settingsOn => 'An';

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
      'Kein Audio erkannt. Bitte versuche es erneut. Manchmal braucht das Mikrofon einen Moment.';

  @override
  String get recordingAutoStopped => 'Aufnahme gestoppt: Stille erkannt.';

  @override
  String get actionCopy => 'Kopieren';

  @override
  String get actionDuplicate => 'Duplizieren';

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
  String get actionRetry => 'Erneut versuchen';

  @override
  String get actionClearSearch => 'Suche zurücksetzen';

  @override
  String get tooltipLanguage => 'Sprache';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Einmal sprechen. Überall einfügen.';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackHint =>
      'Sag uns, was du denkst. Wir lesen jede Nachricht.';

  @override
  String get analyticsPreviewBanner =>
      'Vorschau: zeigt Beispieldaten. Echte Statistiken erscheinen, sobald du aufnimmst.';

  @override
  String get analyticsEmptyTitle => 'Noch keine Aufnahmen';

  @override
  String get analyticsEmptySubtitle =>
      'Starte eine Aufnahme, um hier deine Statistiken zu sehen.';

  @override
  String get analyticsOverview => 'Überblick';

  @override
  String get analyticsOverviewSubtitle =>
      'Deine Aufnahmestatistiken auf einen Blick';

  @override
  String get analyticsActivity => 'Aktivität';

  @override
  String get analyticsInsights => 'Einblicke';

  @override
  String get analyticsTotalRecordings => 'Aufnahmen gesamt';

  @override
  String get analyticsTotalDuration => 'Gesamtdauer';

  @override
  String get analyticsWordsDictated => 'Transkribierte Wörter';

  @override
  String get analyticsTimeSaved => 'Zeitersparnis';

  @override
  String get analyticsAvgLatency => 'Ø Geschwindigkeit';

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
  String get analyticsDuration15To30s => '15-30s';

  @override
  String get analyticsDuration30To60s => '30-60s';

  @override
  String get analyticsDuration1To3m => '1-3m';

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
  String get replacementsSearch => 'Ersetzungen suchen…';

  @override
  String get replacementsSearchFieldLabel => 'Ersetzungen suchen';

  @override
  String get replacementsAdd => 'Hinzufügen';

  @override
  String get replacementsEmpty => 'Noch keine Ersetzungen';

  @override
  String get replacementsEmptyHint =>
      'Füge Ersetzungen hinzu, um Wörter beim Aufnehmen automatisch zu ersetzen.\nBeispiel: \"mfg\" → \"mit freundlichen Grüßen\"';

  @override
  String get replacementsNoMatches => 'Keine Treffer';

  @override
  String get replacementsNoMatchesHint => 'Versuche einen anderen Suchbegriff.';

  @override
  String get replacementsToggleLabel => 'Ersetzungen aktivieren';

  @override
  String get replacementsToggleEnabled => 'Ersetzungen sind aktiv';

  @override
  String get replacementsToggleDisabled => 'Ersetzungen sind deaktiviert';

  @override
  String get replacementsEnableBannerTitle => 'Ersetzungen sind ausgeschaltet';

  @override
  String get replacementsEnableBannerHint =>
      'Aktiviere sie, damit Auslöser-Phrasen bei der Aufnahme automatisch ersetzt werden.';

  @override
  String get replacementsEnableAction => 'Aktivieren';

  @override
  String get replacementsDisableAction => 'Deaktivieren';

  @override
  String get replacementsEditShortcut => 'Ersetzung bearbeiten';

  @override
  String get replacementsNewShortcut => 'Neue Ersetzung';

  @override
  String get replacementsDialogHint =>
      'Jeder der Auslöser wird beim Aufnehmen automatisch ersetzt.';

  @override
  String get replacementsTriggerLabel => 'Auslöser';

  @override
  String get replacementsTriggerHint => 'z. B. mfg';

  @override
  String get replacementsAddTrigger => 'Auslöser hinzufügen';

  @override
  String get replacementsRemoveTrigger => 'Auslöser entfernen';

  @override
  String get replacementsReplacementLabel => 'Ersetzungstext';

  @override
  String get replacementsReplacementHint => 'z. B. mit freundlichen Grüßen';

  @override
  String get replacementsDeleteTitle => 'Ersetzung löschen';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Ersetzung \"$trigger\" entfernen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get snippetsSearch => 'Snippets suchen…';

  @override
  String get snippetsSearchFieldLabel => 'Snippets suchen';

  @override
  String get snippetsAdd => 'Hinzufügen';

  @override
  String get snippetsEmpty => 'Noch keine Snippets';

  @override
  String get snippetsEmptyHint =>
      'Füge einen Snippet hinzu, um wiederkehrende Textbausteine schnell wiederzuverwenden — z. B. eine Signatur oder eine Standardantwort.';

  @override
  String get snippetsNoMatches => 'Keine Treffer';

  @override
  String get snippetsNoMatchesHint => 'Versuche einen anderen Suchbegriff.';

  @override
  String get snippetsEditSnippet => 'Snippet bearbeiten';

  @override
  String get snippetsNewSnippet => 'Neuer Snippet';

  @override
  String get snippetsDialogHint =>
      'Öffne beim Diktieren den Snippet-Picker, um diesen Text einzufügen.';

  @override
  String get snippetsTitleLabel => 'Titel';

  @override
  String get snippetsTitleHint => 'z. B. E-Mail-Signatur';

  @override
  String get snippetsBodyLabel => 'Text';

  @override
  String get snippetsBodyHint => 'Der Text, den dieser Snippet einfügt…';

  @override
  String get snippetsDeleteTitle => 'Snippet löschen';

  @override
  String snippetsDeleteMessage(String title) {
    return 'Snippet \"$title\" entfernen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Trigger-Wort für den Picker';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Sprich nur dieses Wort, um den Snippet-Picker zu öffnen. Leer lassen, um den Picker auszuschalten.';

  @override
  String get snippetsPickerTriggerHint => 'z. B. Snippet';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'Das Trigger-Wort ist gesetzt, aber es gibt noch keine Snippets — diktierst du es, wird es als normaler Text eingefügt, bis du dein erstes Snippet anlegst.';

  @override
  String get snippetsPickerHotkeyLabel => 'Hotkey für den Picker';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Öffnet den Picker sofort — der zweite Weg zum selben Panel.';

  @override
  String get snippetsPickerHotkeyOff =>
      'Der Hotkey für den Picker ist ausgeschaltet.';

  @override
  String get snippetsPickerHotkeyEnable => 'Hotkey einschalten';

  @override
  String get snippetsPickerUnavailable =>
      'Der Snippet-Picker ist auf dieser Plattform noch nicht verfügbar.';

  @override
  String get snippetsPickerSemanticsLabel => 'Snippet-Picker';

  @override
  String get snippetsPickerInsertAction => 'Einfügen';

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
      'WhisPaste ist kostenlos und Open Source unter der MIT-Lizenz. Sponsoring deckt echte laufende Fixkosten (Apple Developer Program, Microsoft Partner Center und Hosting/Domain), die die App auf allen Plattformen verfügbar halten.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Stern auf GitHub';

  @override
  String get aboutSponsorsTitle => 'Sponsoren';

  @override
  String get supportPromptRecurringTitle =>
      'Daraus ein monatliches Sponsoring machen?';

  @override
  String get supportPromptRecurringDescription =>
      'Danke, dass du WhisPaste bereits unterstützt hast. Wenn du möchtest, kannst du daraus ein kleines monatliches Sponsoring machen, das unsere laufenden Fixkosten weiter deckt.';

  @override
  String get aboutBuiltWith => 'Gebaut mit';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Plattformübergreifende UI mit Flutter. Lokale Spracherkennung über whisper.cpp und Parakeet.';

  @override
  String get aboutWhisper => 'whisper.cpp & OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Lokale und Cloud-Spracherkennung: schnell, genau, mehrsprachig (99 Sprachen).';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet & sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Lokale Spracherkennung, optimiert für Geschwindigkeit auf reiner CPU-Hardware (~25 Sprachen).';

  @override
  String get aboutPrivacyFirst => 'Privatsphäre zuerst';

  @override
  String get aboutPrivacyFirstDesc =>
      'Standardmäßig lokale Spracherkennung: deine Stimme verlässt dein Gerät nie, es sei denn, du wählst einen Cloud-Anbieter.';

  @override
  String get aboutPrivacy => 'Datenschutz & Daten';

  @override
  String get aboutPrivacyLocal =>
      'Alle Transkriptionen und der Verlauf werden lokal auf deinem Gerät gespeichert, niemals auf externen Servern.';

  @override
  String get aboutPrivacyCloud =>
      'Cloud-Anbieter (OpenAI, Deepgram) erhalten nur Audio, wenn du sie aktiv nutzt. Deren Datenschutzrichtlinien gelten.';

  @override
  String get aboutPrivacyNoTracking =>
      'Die Nutzungsstatistik ist anonym und DSGVO-konform (Server in der EU) und in Einstellungen → Datenschutz abschaltbar. Keine Benutzerkonten. Update-Prüfungen kontaktieren GitHub (nur Version + IP).';

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
  String get aboutFollowOnX => 'Auf X folgen';

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
  String get aboutMadeWith => 'Gemacht mit ♥ von WhisPaste';

  @override
  String get aboutOpenSource => 'Open Source unter der MIT-Lizenz';

  @override
  String get feedbackSubtitle =>
      'Hilf uns, WhisPaste zu verbessern. Jede Stimme zählt.';

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
  String get feedbackPlaceholderAi => 'Wie war die Transkriptionsqualität?';

  @override
  String get feedbackPlaceholderGeneral => 'Teile deine Gedanken…';

  @override
  String get feedbackContactEmailLabel => 'E-Mail (optional)';

  @override
  String get feedbackContactEmailExplanation =>
      'Nur falls du eine Antwort möchtest. Wir nutzen sie ausschließlich, um zu dieser Meldung zurückzumelden, niemals für Werbung, und sie wird nach 90 Tagen gelöscht.';

  @override
  String get feedbackContactEmailPlaceholder => 'du@beispiel.de';

  @override
  String get feedbackContactEmailInvalid =>
      'Bitte eine gültige E-Mail-Adresse eingeben oder leer lassen.';

  @override
  String get feedbackContactLanguageLabel => 'Antwortsprache';

  @override
  String get feedbackContactLanguageHint =>
      'In welcher Sprache dürfen wir dir antworten?';

  @override
  String get feedbackSubmit => 'Feedback senden';

  @override
  String get feedbackPrivacyNote =>
      'Standardmäßig anonym, nur identifizierbar, wenn du oben deine E-Mail angibst.';

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
  String get feedbackErrorNotConfigured =>
      'Feedback ist in diesem Build nicht verfügbar.';

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
  String get statusBarSttTooltip => 'Sprachdienst und aktueller Status';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Transkriptions-Backend: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'Echte GPU-Auslastung ist plattformübergreifend nicht ohne Zusatzrechte messbar; die angezeigte Prozentzahl bezieht sich stattdessen auf die CPU-Aktivität dieses Prozesses.';

  @override
  String get statusBarRecording => 'Aufnahme…';

  @override
  String get statusBarTranscribing => 'Transkribieren…';

  @override
  String get statusBarDone => 'Fertig';

  @override
  String get statusBarHotkeyTooltip =>
      'Globaler Hotkey: klicken zum Konfigurieren';

  @override
  String get statusBarAutoPasteOffHint =>
      'Auto-Paste deaktiviert, in Settings aktivierbar';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste ist aktuell aus. Klicken, um die Einstellungen zu öffnen.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Hinweis ausblenden';

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
  String get modifierAltGr => 'AltGr';

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
  String get modelServerReady => 'Sprachdienst bereit';

  @override
  String get modelServerMissing => 'Sprachdienst nicht installiert';

  @override
  String get modelServerWhisper => 'Lokaler Sprachdienst';

  @override
  String get modelReady => 'Bereit';

  @override
  String get modelDownloadComplete => 'Modell einsatzbereit';

  @override
  String get modelUse => 'Verwenden';

  @override
  String get modelDownload => 'Laden';

  @override
  String get modelDownloading => 'Wird geladen…';

  @override
  String get modelDownloadingEngine => 'Sprachdienst wird vorbereitet…';

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
  String get qualityTierCompactLabel => 'Schnell & Kompakt';

  @override
  String get qualityTierCompactDesc =>
      'Schnelle Ergebnisse, kleiner Download. Ideal für kurze Notizen und schnelle Nachrichten.';

  @override
  String get qualityTierBalancedLabel => 'Ausgewogen';

  @override
  String get qualityTierBalancedDesc =>
      'Zuverlässig und genau für alltägliche Aufnahmen. Funktioniert auf den meisten Geräten.';

  @override
  String get qualityTierPremiumLabel => 'Beste Qualität';

  @override
  String get qualityTierPremiumDesc =>
      'Höchste Genauigkeit für längere Aufnahmen und komplexe Inhalte. Benötigt eine leistungsfähige Grafikkarte.';

  @override
  String get qualityTierRecommended => 'Empfohlen für deinen Rechner';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size Download';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Modell herunterladen';

  @override
  String get qualityTierChooseDifferent => 'Andere Qualitätsstufe wählen';

  @override
  String get qualityTierActive => 'Aktiv';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Beste Qualität, dauert ~${ratio}x länger';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Beste Qualität, dauert ~${ratio}x länger als Small';
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
      'Sprachdienst wird vorbereitet. Bitte warte einen Moment.';

  @override
  String get infoModelMissing =>
      'Bitte lade zuerst ein Sprachmodell in den Einstellungen herunter.';

  @override
  String get infoPipelineBusy =>
      'WhisPaste ist noch mit der vorherigen Aufnahme beschäftigt.';

  @override
  String get infoSnippetPickerEmpty =>
      'Trigger-Wort erkannt, aber du hast noch keine Snippets — der Text wurde ganz normal eingefügt.';

  @override
  String get infoSnippetPickerEmptyAction => 'Snippets öffnen';

  @override
  String get oomRecoveryTitle => 'Aufnahme fehlgeschlagen: GPU-Speicherproblem';

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
      'Qualität reduziert: deiner GPU ist der Speicher ausgegangen. Es wurde auf ein kleineres Modell umgestellt.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Deiner GPU ist der Speicher ausgegangen. Für mehr Zuverlässigkeit wurde auf CPU-Modus umgestellt.';

  @override
  String get errorSttServerConnectionLost =>
      'Sprachdienst wurde unerwartet beendet. Bitte versuche es erneut.';

  @override
  String get errorSttCudaOom =>
      'Deiner GPU ist der Speicher ausgegangen. Die Qualität wurde reduziert, damit der nächste Versuch funktionieren sollte.';

  @override
  String get errorCloudAuth =>
      'API-Schlüssel fehlt oder ist ungültig. Prüfe ihn unter Einstellungen → Spracherkennung.';

  @override
  String get errorCloudQuota =>
      'Rate-Limit des Cloud-Anbieters erreicht. Warte kurz und versuche es erneut.';

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
      'Aufnahme konnte nicht gestartet werden, bitte versuche es erneut';

  @override
  String get errorNoAudioRecorded =>
      'Keine Audiodaten aufgenommen, bitte versuche es erneut';

  @override
  String get errorTranscriptionEmpty =>
      'Transkription hat keinen Text ergeben, bitte erneut versuchen';

  @override
  String get errorSttServerFailed =>
      'Sprachdienst konnte nicht gestartet werden';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'Das Sprachmodell ist mit der installierten Laufzeitumgebung nicht kompatibel. Bitte lade das Sprachmodell in den Einstellungen neu herunter.';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'Das Sprachmodell scheint beschädigt zu sein. Eine neue Kopie wird automatisch heruntergeladen.';

  @override
  String get errorSttDllMissing =>
      'Eine erforderliche Systemkomponente fehlt. Erneuter Versuch im CPU-Modus.';

  @override
  String get errorSttGpuFatal =>
      'GPU-Beschleunigung fehlgeschlagen. Erneuter Versuch im CPU-Modus.';

  @override
  String get errorSttHeapCorruption =>
      'Ein Speicherfehler ist aufgetreten. Erneuter Versuch im CPU-Modus.';

  @override
  String get errorSttCpuFallbackFailed =>
      'Der Sprachdienst ist sowohl auf der GPU als auch auf der CPU fehlgeschlagen. Bitte starte die App neu oder lade das Modell neu herunter.';

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
      'Sprachdienst startet noch. Bitte versuche es gleich nochmal.';

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
  String get historyAddNote => 'Anmerkung hinzufügen';

  @override
  String get historyEditNote => 'Anmerkung bearbeiten';

  @override
  String get historyNotes => 'Anmerkungen';

  @override
  String get historyNotePlaceholder => 'Anmerkung schreiben…';

  @override
  String get historyVoiceNoteHint =>
      'Tipp: Sag „tag: Name“ oder „korrektur: Text“ bei der Aufnahme.';

  @override
  String get historyNoteAdded => 'Anmerkung hinzugefügt';

  @override
  String get historyNoteDeleted => 'Anmerkung gelöscht';

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
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Tags',
      one: '1 weiterer Tag',
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
  String get historyShortcutNotes => 'Anmerkung hinzufügen';

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
  String get historyRecentSearches => 'Letzte Suchen';

  @override
  String get historyRemoveRecentSearch => 'Letzte Suche entfernen';

  @override
  String get historyRemoveFilter => 'Filter entfernen';

  @override
  String get historyQuickActions => 'Schnellfilter';

  @override
  String get historyQuickActionAllLangs => 'Alle Sprachen';

  @override
  String get historyQuickActionFavorites => 'Nur Favoriten';

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
  String get settingsHotkeyRecorderModifierHint =>
      'Jede Modifier-Kombination ist möglich: z. B. Alt+Leertaste, Ctrl+Alt+V oder Ctrl+Alt+Shift+R';

  @override
  String get settingsHotkeyRecorderCancel => 'Abbrechen';

  @override
  String get settingsHotkeyRecorderSave => 'Speichern';

  @override
  String get settingsHotkeyRecorderClear => 'Zurücksetzen';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'Diese Taste lässt sich nicht als Hotkey speichern. Probier einen Buchstaben, eine Ziffer, eine F-Taste (F1-F12) oder eine Pfeiltaste.';

  @override
  String get settingsHotkeyActionRecording => 'Aufnahme starten/stoppen';

  @override
  String get settingsHotkeyActionQuickNote => 'Schnellnotiz';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'Schnellnotiz-Hotkey';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'Diktiertes hängt an der Notiz, die als Schnellnotiz markiert ist. Welche das ist, legst du im Bereich „Notizen“ fest.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Kombination';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähl eine andere.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Schnellnotiz-Hotkey ist derzeit nicht aktiv. Wähl eine andere Kombination.';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Snippet-Picker';

  @override
  String get settingsSnippetPickerHotkeyEnabled => 'Snippet-Picker-Hotkey';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Öffnet den Snippet-Picker sofort — ohne Aufnahme und ohne das gesprochene Trigger-Wort.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Kombination';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähl eine andere.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Snippet-Picker-Hotkey ist derzeit nicht aktiv. Wähl eine andere Kombination.';

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
  String get settingsSidePanelEnabled => 'Zwischenablage-Schnelleinfüge-Panel';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'Ausklappbares Panel bei Hover am linken Bildschirmrand für Transkriptionen, Snippets und Zwischenablage-Verlauf';

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
  String get settingsCheckUpdates => 'Auf Updates prüfen';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Beim Start automatisch nach neuen Versionen suchen';

  @override
  String get settingsCheckForUpdatesNow => 'Jetzt nach Updates suchen';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsUpdatesSubtitle => 'Release-Kanal und Update-Prüfung';

  @override
  String get settingsBetaUpdates => 'Beta-Updates';

  @override
  String get settingsBetaUpdatesSubtitle =>
      'Vorab-Versionen erhalten, die weniger getestet sind.';

  @override
  String get settingsStableRevertHintMessage =>
      'Automatisches Zurückkehren zu Stable ist hier nicht möglich. Du hast bereits eine neuere Beta-Version installiert.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'Stable $stableVersion manuell herunterladen';
  }

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingBack => 'Zurück';

  @override
  String get onboardingPrivacyTitle => 'Hilf mit, WhisPaste zu verbessern';

  @override
  String get onboardingPrivacyHint =>
      'Audio und Text bleiben lokal. Nur anonyme Nutzungsstatistik geht an einen selbst gehosteten Server in der EU — DSGVO-konform.';

  @override
  String get onboardingPrivacyToggle => 'Anonyme Nutzungsstatistik teilen';

  @override
  String get onboardingPrivacyToggleHint =>
      'Standardmäßig aktiv, jederzeit abschaltbar';

  @override
  String get onboardingPrivacyCrashToggle => 'Anonyme Absturzberichte senden';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'Hilft beim Beheben von Fehlern, standardmäßig aktiv, jederzeit abschaltbar';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'Aussehen';

  @override
  String get onboardingAppearancePageSubtitle =>
      'Wie die App startet und wie das Aufnahme-Overlay aussieht.';

  @override
  String get onboardingBeat1Title => 'Hotkey drücken, sprechen, fertig';

  @override
  String get onboardingBeat1Caption =>
      'Die Aufnahme startet sofort – deine Worte landen als Text direkt an der Cursor-Position.';

  @override
  String get onboardingBeat2Title => 'Läuft lokal, auf deiner Hardware';

  @override
  String get onboardingBeat2Caption =>
      'Die Transkription läuft auf deinem Gerät – ganz ohne Internet.';

  @override
  String get onboardingBeat3Title => 'Überall, wo du tippst';

  @override
  String get onboardingBeat3Caption =>
      'Browser, Mail, Editor – WhisPaste funktioniert systemweit.';

  @override
  String get onboardingMicChipReady => 'Mikrofon bereit';

  @override
  String get onboardingMicChipPending => 'Mikrofonzugriff ausstehend';

  @override
  String get onboardingMicChipAction => 'Mikrofon: Aktion nötig';

  @override
  String get onboardingModelTitle => 'Spracherkennung einrichten';

  @override
  String get onboardingModelSubtitle =>
      'Lade das Sprachmodell herunter, um offline aufzunehmen. Deine Stimme verlässt nie dein Gerät.';

  @override
  String get onboardingModelRecommended => 'Empfohlen';

  @override
  String get onboardingModelChangeLater =>
      'Du kannst die Qualität später in den Einstellungen anpassen';

  @override
  String get onboardingModelDownloading => 'Wird heruntergeladen…';

  @override
  String get onboardingModelReady => 'Modell bereit';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Optimierte GPU-Beschleunigung nicht verfügbar, App nutzt CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Schnell & europäisch';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'Der schnellste Weg zu Text in rund 25 europäischen Sprachen, inklusive Deutsch. Läuft gut auf jeder Hardware, auch ohne GPU.';

  @override
  String get onboardingModelEngineWhisperLabel => 'Alle 99 Sprachen';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'Breiteste Sprachabdeckung, plus eigenes Vokabular und Interpunktions-Tuning für Namen, Akronyme und Fachbegriffe.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Unterstützt deine gewählte Sprache noch nicht';

  @override
  String get onboardingTestRecordingTitle => 'Probier es gleich aus';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Drück die Schaltfläche unten und sprich einen Satz. Der Text landet im Testfeld. Dein Hotkey funktioniert genauso.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Dein Hotkey';

  @override
  String get onboardingTestRecordingStartCta => 'Aufnahme starten';

  @override
  String get onboardingTestRecordingStopCta => 'Aufnahme stoppen';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'Probier zuerst eine Aufnahme aus, um fortzufahren.';

  @override
  String get onboardingTestRecordingMicBypassCta => 'Ohne Mikrofon fortfahren';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'Ohne funktionierendes Mikrofon kann WhisPaste noch keine Aufnahme starten. Das lässt sich jederzeit über den Mikrofon-Status auf dieser Seite oder in den Einstellungen nachholen.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'Hier erscheint gleich dein gesprochener Text …';

  @override
  String get onboardingTestRecordingInProgress =>
      'Aufnahme läuft, sprich einfach los. Erneut drücken stoppt.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      'Klappt! Genau so funktioniert es in jeder App.';

  @override
  String get onboardingTestRecordingReassurance =>
      'Nur ein Test, der Text bleibt in diesem Feld.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'Nur ein Test, der Text bleibt in diesem Feld — Aufnahmen stoppen automatisch nach $seconds Sekunden, änderbar unter Einstellungen → $section.';
  }

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
  String get onboardingReadyStep3AutoPaste =>
      'Text fließt direkt in die aktive App';

  @override
  String get onboardingReadyStep3CopyOnly =>
      'Text liegt in der Zwischenablage, drück ⌘V / Strg+V zum Einfügen';

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste reicht Kontext aus dem vorigen Aufnahme-Vorgang bis zu zehn Minuten weiter. Bei einem schnellen Wechsel zu einem ganz anderen Thema lohnt eine kurze Pause, sonst kann das nächste Ergebnis inhaltlich verzogen werden.';

  @override
  String get onboardingReadyAutostartToggle =>
      'WhisPaste beim Anmelden starten';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Standardmäßig aus, jederzeit in den Einstellungen aktivierbar';

  @override
  String get onboardingTriggerTitle => 'Wie möchtest du die Aufnahme starten?';

  @override
  String get onboardingTriggerSubtitle =>
      'Lege deinen Hotkey fest und wähle, wie er eine Aufnahme startet.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Aktuelles Tastenkürzel';

  @override
  String get onboardingTriggerHotkeyConflictTitle =>
      'Tastenkürzel bereits belegt';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Dein Tastenkürzel ist offenbar von einer anderen App belegt. Nimm unten eine neue Kombination auf.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Geh mit „Zurück\" zur Hotkey-Seite und nimm dort eine neue Kombination auf.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Tastenkürzel gedrückt halten und sprechen, Loslassen beendet die Aufnahme';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Einmal drücken startet, erneutes Drücken beendet die Aufnahme';

  @override
  String get onboardingTriggerSystemWideHint =>
      'Funktioniert systemweit — nicht nur innerhalb von WhisPaste.';

  @override
  String get onboardingStartUsing => 'Los geht\'s';

  @override
  String get onboardingReviewExit => 'Einführung schließen';

  @override
  String get onboardingReviewDone => 'Fertig';

  @override
  String get onboardingReviewEntry => 'Einführung';

  @override
  String get onboardingReviewSubtitle =>
      'Gehe die fünf Einrichtungsschritte jederzeit erneut durch — es ändert sich nichts, außer du änderst es.';

  @override
  String get onboardingReviewLabel => 'Einführung erneut ansehen';

  @override
  String get onboardingReviewAction => 'Öffnen';

  @override
  String get onboardingRevisionNoticeTitle =>
      'WhisPaste wurde aktualisiert — deine Einstellungen bleiben unverändert.';

  @override
  String get onboardingRevisionExit => 'Einführung verlassen';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Einführung verlassen?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Diesen Update-Durchgang gibt es nur einmal — was du jetzt überspringst, wird nicht für dich eingerichtet. Du kannst dieselben Schritte jederzeit unter Einstellungen → Einführung erneut öffnen, und jede Einstellung daraus hat außerdem ihren eigenen Platz in den Einstellungen. Was du bereits eingerichtet hast, bleibt unverändert.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Verlassen';

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
  String get overlayRecordingQuickNote => 'Aufnahme für Notiz';

  @override
  String get overlayTargetQuickNote => 'Notiz';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayDoneQuickNote => 'An Notiz angehängt';

  @override
  String get floatingButtonHide => 'Ausblenden';

  @override
  String get floatingButtonQuit => 'Beenden';

  @override
  String get a11yRecordingButton => 'Aufnahmeknopf';

  @override
  String get a11yRecordingOverlay => 'Aufnahme-Overlay';

  @override
  String get a11ySidePanel => 'Schnelleinfüge-Panel';

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
  String get trayMicrophone => 'Mikrofon';

  @override
  String get settingsComingSoon => 'Demnächst';

  @override
  String get undo => 'Rückgängig';

  @override
  String get hintDismiss => 'Hinweis schließen';

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
  String updateAvailable(String version) {
    return 'Update verfügbar: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Update wird heruntergeladen… $percent %';
  }

  @override
  String get updateReadyToInstall => 'Update bereit, zum Installieren klicken';

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
      'Zu viele Anfragen, versuche es später erneut';

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
  String get settingsOverlaySizeMini => 'Mini';

  @override
  String get settingsOverlayStyle => 'Overlay-Stil';

  @override
  String get settingsOverlayStyleSubtitle =>
      'Wähle zwischen Glas-Effekt oder volldeckender Darstellung';

  @override
  String get settingsOverlayStyleGlass => 'Glas';

  @override
  String get settingsOverlayStyleSolid => 'Volldeckend';

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
  String get overlayContextSwitchMini => 'Zu Mini wechseln';

  @override
  String get overlayContextHide => 'Overlay ausblenden';

  @override
  String get buttonContextOpen => 'WhisPaste öffnen';

  @override
  String get buttonContextStartRecording => 'Aufnahme starten';

  @override
  String get buttonContextShowHistory => 'Verlauf anzeigen';

  @override
  String get buttonContextSettings => 'Einstellungen';

  @override
  String get buttonContextQuit => 'WhisPaste beenden';

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
  String get settingsHistoryRetentionPreset => 'Aufbewahrung';

  @override
  String get settingsHistoryPresetMinimal => 'Minimal';

  @override
  String get settingsHistoryPresetStandard => 'Standard';

  @override
  String get settingsHistoryPresetUnlimited => 'Unbegrenzt';

  @override
  String get settingsHistoryPresetCustom => 'Benutzerdefiniert';

  @override
  String get settingsFloatingButtonSection => 'Schwebender Button';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Immer sichtbarer Aufnahme-Button für schnellen Zugriff';

  @override
  String get settingsSttIdleTimeout => 'Sprachdienst-Leerlauf';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Wie lange der Sprachdienst nach Nutzung geladen bleibt';

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

  @override
  String get reviewPromptTitle => 'Gefällt dir WhisPaste?';

  @override
  String get reviewPromptBody =>
      'Deine Bewertung hilft anderen, die App zu finden, und unterstützt die Weiterentwicklung.';

  @override
  String get reviewPromptYes => 'Sehr gern!';

  @override
  String get reviewPromptNotNow => 'Nicht jetzt';

  @override
  String get reviewPromptNever => 'Nicht mehr fragen';

  @override
  String get reviewPromptStarGitHub => '⭐ Auf GitHub einen Stern geben';

  @override
  String get reviewPromptRateStore => '★ Im Store bewerten';

  @override
  String get reviewPromptGateBody =>
      'Nur eine kurze Frage an uns, das ist keine Store-Bewertung.';

  @override
  String get reviewPromptGateYes => 'Ja, gefällt mir';

  @override
  String get reviewPromptGateNo => 'Eher nicht';

  @override
  String get reviewSupportEntry => 'WhisPaste bewerten & unterstützen';

  @override
  String get reviewSupportLabel => 'Deine Bewertung';

  @override
  String get reviewSupportSubtitle =>
      'Deine Bewertung hilft anderen, WhisPaste zu finden, und unterstützt das Projekt.';

  @override
  String get reviewSupportAction => 'Bewerten';

  @override
  String get insufficientRamTitle => 'Zu wenig Arbeitsspeicher';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'WhisPaste benötigt mindestens $requiredGb GB Arbeitsspeicher. Dein System hat $detectedGbString GB.\n\nMit weniger Arbeitsspeicher kann die KI-Transkription möglicherweise nicht geladen werden oder stürzt ab.';
  }

  @override
  String get insufficientRamQuit => 'WhisPaste beenden';

  @override
  String get insufficientRamLearnMore => 'Systemanforderungen';

  @override
  String get insufficientRamSystemCheck => 'Systemprüfung';

  @override
  String get insufficientRamYourSystem => 'Dein System';

  @override
  String get insufficientRamRequired => 'Mindestens';

  @override
  String get hotkeyRegistrationFailed =>
      'Hotkey-Registrierung fehlgeschlagen, bitte Tastenkombination in den Einstellungen neu belegen.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'Hotkey-Registrierung fehlgeschlagen, Strg+Umschalt+Leertaste wird als Fallback verwendet. Bitte in den Einstellungen neu belegen.';

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Diese Tastenkombination ist von $platform reserviert ($note) und funktioniert möglicherweise nicht.';
  }

  @override
  String get exportFormatPickerTitle => 'Exportformat wählen';

  @override
  String get exportFormatText => 'Text';

  @override
  String get exportFormatMarkdown => 'Markdown';

  @override
  String get exportFormatCsv => 'CSV';

  @override
  String get exportFormatJson => 'JSON';

  @override
  String get exportFormatWord => 'Word';

  @override
  String get cpuFallbackToast =>
      'Transkription dauert gerade etwas länger als sonst, läuft aber weiter.';

  @override
  String get recoveryExhaustedToast =>
      'Sprachdienst kann nicht starten. Bitte App neu starten oder Sprachmodell neu laden.';

  @override
  String get recoveryExhaustedAction => 'Einstellungen öffnen';

  @override
  String get recoveryVcRuntimeToast =>
      'Sprachdienst kann nicht starten: eine Windows-Komponente fehlt (Microsoft Visual C++). Bitte installiere das Visual C++ Redistributable (x64) und starte WhisPaste neu.';

  @override
  String get recoveryVcRuntimeAction => 'Installieren';

  @override
  String get modelAbiInfoToast => 'Lade Sprachmodell neu, bitte warten.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste läuft jetzt ohne Grafikkarten-Beschleunigung, weil es beim letzten Start ein Problem gab. Diktieren funktioniert unverändert.';

  @override
  String get serverDownloadFailedToast =>
      'Sprachdienst konnte nicht heruntergeladen werden. Internetverbindung prüfen?';

  @override
  String get serverDownloadFailedAction => 'Erneut versuchen';

  @override
  String get serverDownloadStalledToast =>
      'Download steht: Verbindung wird neu aufgebaut.';

  @override
  String get historyWriteFailedToast =>
      'Eintrag konnte nicht gespeichert werden, bitte Speicherplatz prüfen.';

  @override
  String get historyWriteFailedAction => 'Diagnose kopieren';

  @override
  String get factoryResetFailedToast =>
      'Werks-Reset unvollständig. App neu starten?';

  @override
  String get factoryResetFailedAction => 'App schließen';

  @override
  String get errorSttRejectEmpty =>
      'Keine Audiodaten zum Transkribieren, bitte Aufnahme wiederholen.';

  @override
  String get errorSttRejectInvalidWav =>
      'Audiodatei ist beschädigt, bitte Aufnahme wiederholen.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'Diese Sprache wird vom lokalen Sprachmodell nicht unterstützt, bitte Sprache in den Einstellungen prüfen.';

  @override
  String get errorSttRejectPromptTooLong =>
      'Eigenes Vokabular ist zu lang, bitte in den Einstellungen kürzen.';

  @override
  String get settingsGpuAcceleration => 'Grafikbeschleunigung';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Legt fest, ob der Sprachdienst GPU oder CPU für die lokale Erkennung verwendet';

  @override
  String get settingsGpuAccelerationAuto => 'Automatisch (empfohlen)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (erzwingen)';

  @override
  String get settingsGpuAccelerationDisabled => 'Nur CPU';

  @override
  String get settingsSttEngine => 'Engine';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper deckt 99 Sprachen und jedes GPU-Backend ab; Parakeet ist auf reiner CPU-Hardware deutlich schneller, deckt aber nur ~25 Sprachen ab und hat noch kein GPU-Backend';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet =>
      'Parakeet (am schnellsten, ~25 Sprachen)';

  @override
  String get parakeetModelTitle => 'Parakeet-TDT-Modell';

  @override
  String get parakeetModelSubtitle =>
      'Einmaliger Download (~640 MB), läuft danach vollständig offline';

  @override
  String get parakeetModelDownload => 'Herunterladen';

  @override
  String get parakeetModelDownloading => 'Wird heruntergeladen …';

  @override
  String get parakeetModelInstalled => 'Installiert';

  @override
  String get parakeetModelDelete => 'Löschen';

  @override
  String get parakeetModelCancel => 'Abbrechen';

  @override
  String get settingsSearchHint => 'Einstellungen durchsuchen…';

  @override
  String get settingsSearchNoResults => 'Keine Treffer';

  @override
  String get settingsSearchNoResultsHint =>
      'Versuche einen anderen Suchbegriff.';

  @override
  String get settingsSearchFieldLabel => 'Einstellungen durchsuchen';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
      zero: 'Keine Treffer',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'Datenschutz';

  @override
  String get settingsPrivacySubtitle =>
      'Lege fest, welche Daten WhisPaste teilt';

  @override
  String get settingsShareUsageStats => 'Anonyme Nutzungsstatistiken senden';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Cookiefrei und ohne Identifikatoren, hilf uns zu verstehen, wie WhisPaste genutzt wird';

  @override
  String get settingsRetainRecentAudio => 'Letzte Aufnahmen aufbewahren';

  @override
  String get settingsRetainRecentAudioSubtitle =>
      'Audio der letzten 20 Diktate lokal aufbewahren, zum Debuggen oder um ein früheres Transkript wiederherzustellen; ältere Aufnahmen werden automatisch gelöscht';

  @override
  String get storeThankYouTitle => 'Danke für deine Unterstützung!';

  @override
  String get storeThankYouBody =>
      'Wir freuen uns sehr, dass du dabei bist. Wenn dir WhisPaste im Alltag hilft, würde uns eine kurze Bewertung sehr freuen.';

  @override
  String get storeThankYouCtaStore => '★ Im Store bewerten';

  @override
  String get storeThankYouCtaGitHub => '⭐ Stern auf GitHub';

  @override
  String get storeThankYouDismiss => 'Schließen';

  @override
  String get featureSpotlightHeading => 'Neu in WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Verstanden';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Snippet-Picker';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Speichere wiederverwendbare Textbausteine und füge sie per Hotkey oder gesprochenem Trigger überall ein – ganz ohne erneutes Tippen.';

  @override
  String get featureSpotlightSidePanelTitle => 'Clipboard-Seitenleiste';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Fahre an den Bildschirmrand, um deinen letzten Clipboard-Verlauf zu öffnen, und ziehe jeden Eintrag direkt in dein Dokument.';

  @override
  String get featureSpotlightChangelogLink => 'Vollständiges Changelog ansehen';

  @override
  String get featureSpotlightReviewLabel => 'Neue Funktionen erneut ansehen';

  @override
  String get featureSpotlightReviewAction => 'Anzeigen';

  @override
  String get notesNewNote => 'Neue Notiz';

  @override
  String get notesEmptyTitle => 'Noch keine Notizen';

  @override
  String get notesEmptyHint =>
      'Leg eine Notiz an, um Text von überall zu sammeln.';

  @override
  String get notesUntitled => 'Notiz ohne Titel';

  @override
  String get notesEditorPlaceholder => 'Leg los…';

  @override
  String get notesListSemantics => 'Notizenliste';

  @override
  String get notesCopy => 'Notiz kopieren';

  @override
  String get notesCopied => 'Notiz kopiert';

  @override
  String get notesFavorite => 'Als Favorit markieren';

  @override
  String get notesUnfavorite => 'Favorit aufheben';

  @override
  String get notesQuickNoteSet =>
      'Zur Schnellnotiz machen, an die der Hotkey anhängt';

  @override
  String get notesQuickNoteClear => 'Schnellnotiz — Markierung entfernen';

  @override
  String get notesQuickNoteHotkeyLabel => 'Hotkey';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'Hotkey der Schnellnotiz ändern — derzeit $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff =>
      'Der Schnellnotiz-Hotkey ist ausgeschaltet.';

  @override
  String get notesQuickNoteHotkeyEnable => 'Hotkey einschalten';

  @override
  String get notesMoveToTrash => 'In den Papierkorb verschieben';

  @override
  String get notesMovedToTrash => 'In den Papierkorb verschoben';

  @override
  String get notesRestore => 'Wiederherstellen';

  @override
  String get notesDeleteForever => 'Endgültig löschen';

  @override
  String get notesDeleteForeverConfirm => 'Notiz endgültig löschen?';

  @override
  String get notesTrash => 'Papierkorb';

  @override
  String get notesTrashEmpty => 'Papierkorb ist leer';

  @override
  String get notesTrashEmptyHint =>
      'Gelöschte Notizen landen hier und werden nicht automatisch entfernt.';

  @override
  String get notesUndo => 'Rückgängig';

  @override
  String get notesAddTag => 'Tag hinzufügen';

  @override
  String get notesTagPlaceholder => 'Tag-Name…';

  @override
  String get notesSearchPlaceholder => 'Notizen durchsuchen…';

  @override
  String get notesSearchFieldLabel => 'Notizen durchsuchen';

  @override
  String get notesNoResults => 'Keine Ergebnisse';

  @override
  String notesNoResultsHint(String query) {
    return 'Keine Notizen stimmen mit \"$query\" überein.\nVersuche einen anderen Suchbegriff.';
  }

  @override
  String notesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ergebnisse',
      one: '1 Ergebnis',
    );
    return '$_temp0';
  }

  @override
  String get notesExport => 'Exportieren';

  @override
  String markdownToolbarBold(String shortcut) {
    return 'Fett ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'Kursiv ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'Überschrift';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'Aufzählung ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'Nummerierte Liste';

  @override
  String get markdownToolbarQuote => 'Zitat';

  @override
  String get markdownToolbarCode => 'Code';

  @override
  String get findReplaceToggle => 'In diesem Text suchen und ersetzen';

  @override
  String get findReplaceFindLabel => 'In diesem Text suchen';

  @override
  String get findReplaceFindHint => 'Suchen…';

  @override
  String get findReplaceReplaceLabel => 'Treffer ersetzen durch';

  @override
  String get findReplaceReplaceHint => 'Ersetzen durch…';

  @override
  String get findReplaceNext => 'Nächster Treffer';

  @override
  String get findReplacePrevious => 'Vorheriger Treffer';

  @override
  String get findReplaceReplaceAction => 'Diesen Treffer ersetzen';

  @override
  String get findReplaceReplaceAllAction => 'Alle Treffer ersetzen';

  @override
  String get findReplaceClose => 'Suchen und Ersetzen schließen';

  @override
  String get findReplaceNoMatches => 'Keine Treffer';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current von $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'Transkriptionen';

  @override
  String get sidePanelSnippetsTitle => 'Snippets';

  @override
  String get sidePanelClipboardHistoryTitle => 'Zwischenablage-Verlauf';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Noch nichts kopiert';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Alles, was du kopierst während WhisPaste läuft, erscheint hier — wird beim Neustart der App gelöscht.';

  @override
  String get sidePanelClose => 'Panel schließen';

  @override
  String get sidePanelSearchHint => 'Suchen';

  @override
  String get sidePanelSearchFieldLabel => 'Diese Liste durchsuchen';

  @override
  String get sidePanelNoMatches => 'Keine Treffer';

  @override
  String get sidePanelNoMatchesHint => 'Versuche einen anderen Suchbegriff.';
}
