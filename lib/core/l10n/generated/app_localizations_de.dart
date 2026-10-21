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
  String get navHistory => 'Aufnahmen';

  @override
  String get navNotes => 'Notizen';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navReplacements => 'Wörterbuch';

  @override
  String get navSnippets => 'Textbausteine';

  @override
  String get navAnalytics => 'Statistik';

  @override
  String get navHelp => 'Hilfe';

  @override
  String get actionOpen => 'Öffnen';

  @override
  String actionOpenNamed(String name) {
    return '$name öffnen';
  }

  @override
  String get helpTabManual => 'Handbuch';

  @override
  String get helpTabIntro => 'Einführung';

  @override
  String get helpTabSupport => 'Unterstützung';

  @override
  String get helpTabDiagnostics => 'Diagnose';

  @override
  String get manualSearchHint => 'Im Handbuch suchen';

  @override
  String get manualSearchEmpty => 'Kein Kapitel passt zu dieser Suche.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kapitel gefunden',
      one: '1 Kapitel gefunden',
      zero: 'Keine Kapitel gefunden',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'Aufnahmen';

  @override
  String get pageSettingsTitle => 'Einstellungen';

  @override
  String get pageReplacementsTitle => 'Wörterbuch';

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
  String get historyPrivacyGateTitle => 'Aufnahmen verborgen';

  @override
  String get historyPrivacyGateHint =>
      'Transkriptionen und Audio werden nur ausgeblendet, nicht gelöscht, bis du die Aufnahmen einblendest.';

  @override
  String get historyPrivacyGateShow => 'Aufnahmen anzeigen';

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
  String historyExportDone(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String get historyExportFailed =>
      'Export fehlgeschlagen. Prüfe, ob der Zielordner beschreibbar ist, und versuche es erneut.';

  @override
  String get historyCopyAsMarkdown => 'Als Markdown kopieren';

  @override
  String get historyDetail => 'Details';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Dauer';

  @override
  String get historyModel => 'Sprachmodell';

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
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ca. $count Wörter',
      one: 'ca. 1 Wort',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'Ansicht und Auswahl';

  @override
  String get historyEditing => 'Bearbeiten';

  @override
  String get historySearchTranscriptions => 'Aufnahmen durchsuchen…';

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
    return 'Keine Einträge stimmen mit „$query“ überein.\nVersuche einen anderen Suchbegriff.';
  }

  @override
  String get historyTrashEmpty => 'Papierkorb ist leer';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Elemente werden nach $days Tagen endgültig entfernt.',
      one: 'Elemente werden nach 1 Tag endgültig entfernt.',
      zero: 'Elemente bleiben, bis du sie endgültig löschst.',
    );
    return 'Gelöschte Transkriptionen erscheinen hier.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'Papierkorb leeren';

  @override
  String get historyEmptyTrashConfirm => 'Papierkorb leeren?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Transkriptionen werden endgültig gelöscht. Vorhandene Audiodateien werden spätestens 30 Tage nach der Aufnahme entfernt. Diese Aktion kann nicht rückgängig gemacht werden.',
      one:
          '1 Transkription wird endgültig gelöscht. Vorhandene Audiodateien werden spätestens 30 Tage nach der Aufnahme entfernt. Diese Aktion kann nicht rückgängig gemacht werden.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => 'Endgültig löschen?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Transkriptionen werden endgültig gelöscht, samt gespeicherten Audios. Diese Aktion kann nicht rückgängig gemacht werden.',
      one:
          '1 Transkription wird endgültig gelöscht, samt gespeichertem Audio. Diese Aktion kann nicht rückgängig gemacht werden.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Papierkorb geleert — $count Transkriptionen gelöscht',
      one: 'Papierkorb geleert — 1 Transkription gelöscht',
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
  String get historyRestored => 'Wiederhergestellt';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Transkriptionen archiviert',
      one: '1 Transkription archiviert',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Transkriptionen in den Papierkorb verschoben',
      one: '1 Transkription in den Papierkorb verschoben',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Transkriptionen wiederhergestellt',
      one: '1 Transkription wiederhergestellt',
    );
    return '$_temp0';
  }

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
  String get historyShowAll => 'Alle anzeigen';

  @override
  String get historyMoreActions => 'Weitere Aktionen';

  @override
  String get historyMdTags => 'Schlagwörter';

  @override
  String get historyMdDate => 'Datum';

  @override
  String get historyMdModel => 'Modell';

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
  String get settingsReviewPromptRestore =>
      'Bewertungs-Hinweis wieder anzeigen';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'Du hast beim Hinweis „Nicht mehr fragen“ gewählt. Einschalten erlaubt ihn wieder; die üblichen Pausen bleiben bestehen.';

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
      'Anzeige: Rechenleistung in der Statusleiste';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Zeigt, ob gerade der Prozessor oder die Grafikkarte arbeitet.';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Mikrofon und Aufnahme';

  @override
  String get settingsMicrophone => 'Mikrofon';

  @override
  String get settingsGain => 'Mikrofon-Empfindlichkeit';

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
  String get pushToTalkUnavailableLinuxTooltip =>
      'Dein Desktop meldet hier kein Loslassen von Tasten. Lege stattdessen „whispaste --toggle“ in den Systemeinstellungen als Tastenkombination an.';

  @override
  String get settingsExperimentalBadge => 'Experimentell';

  @override
  String get settingsHoldOrTap => 'Tippen oder Halten';

  @override
  String get settingsHoldOrTapHint =>
      'Kurz tippen startet und stoppt die Aufnahme, gedrückt halten nimmt bis zum Loslassen auf.';

  @override
  String get settingsSpeechRecognition => 'Spracherkennung';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Spracherkennungsqualität und Dienst';

  @override
  String get settingsService => 'Erkennung läuft auf';

  @override
  String get settingsQuality => 'Geschwindigkeit & Genauigkeit';

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
  String get settingsAfterTranscriptionActionLabel => 'Nach dem Aufnehmen';

  @override
  String get settingsAfterTranscriptionClipboard =>
      'In Zwischenablage kopieren';

  @override
  String get settingsAfterTranscriptionPaste => 'Auto-Paste';

  @override
  String get settingsAfterTranscriptionBoth => 'Kopieren & einfügen';

  @override
  String get settingsAfterTranscriptionNothing => 'Nichts tun';

  @override
  String get pasteFailurePermissionMissing =>
      'Auto-Paste vom System blockiert. WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt diese Berechtigung „Bedienungshilfen“.';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Paste übersprungen, keine Ziel-App erkannt. Fokussiere zuerst die Ziel-App, dann starte die Aufnahme.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Paste blockiert: Die Ziel-App läuft mit Administratorrechten. Starte WhisPaste ebenfalls als Administrator, um dort einzufügen.';

  @override
  String pasteFailureGeneric(String paste) {
    return 'Auto-Paste fehlgeschlagen. Der Text ist in der Zwischenablage, füge ihn manuell mit $paste ein.';
  }

  @override
  String get pasteFailureOpenSettings => 'Einstellungen öffnen';

  @override
  String get pendingAudioSaveLater =>
      'Die Aufnahme konnte nicht in den Aufnahmen gespeichert werden. Die Audiodatei bleibt erhalten und wird beim nächsten Start von WhisPaste erneut gespeichert.';

  @override
  String get pendingAudioRecovered =>
      'Eine Aufnahme, die zuvor nicht gespeichert werden konnte, ist jetzt in den Aufnahmen.';

  @override
  String get pasteNotificationNoTargetTitle =>
      'WhisPaste: Auto-Paste übersprungen';

  @override
  String get pasteNotificationNoTargetBody =>
      'Keine Ziel-App erkannt. Fokussiere zuerst die Ziel-App, dann starte die Aufnahme. Der Text liegt in der Zwischenablage.';

  @override
  String get pasteNotificationNoTargetTray => 'Auto-Paste: Ziel-App fehlte';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: Kein Signal vom Mikrofon';

  @override
  String get silentMicrophoneNotificationBody =>
      'Das Mikrofon liefert keinen Ton. Prüfe das ausgewählte Mikrofon oder ob es stummgeschaltet ist. Die Aufnahme läuft weiter.';

  @override
  String get pasteNotificationRestartNeededTitle => 'WhisPaste: Neustart nötig';

  @override
  String get pasteNotificationRestartNeededBody =>
      'Die Berechtigung wurde erteilt, aber WhisPaste läuft noch mit dem alten Stand. Klicke hier, um WhisPaste neu zu starten.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'Auto-Paste blockiert — Neustart nötig';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: Auto-Paste blockiert';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt sie „Bedienungshilfen“. Klicke hier: WhisPaste räumt einen möglicherweise veralteten Eintrag weg und lässt macOS neu fragen.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt sie „Bedienungshilfen“. Klicke hier oder das Tray-Icon, um die Systemeinstellungen zu öffnen.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'Auto-Paste blockiert — Systemeinstellungen öffnen';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: Auto-Paste blockiert';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'Die Ziel-App läuft mit Administratorrechten. Starte WhisPaste ebenfalls als Administrator, um dort einzufügen.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'Auto-Paste blockiert — Administrator nötig';

  @override
  String get pasteNotificationFailedTitle =>
      'WhisPaste: Auto-Paste fehlgeschlagen';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'Die Einfügen-Taste wurde vom System blockiert. Der Text liegt in der Zwischenablage. Füge ihn mit $paste selbst ein.';
  }

  @override
  String get pasteNotificationFailedTray => 'Auto-Paste fehlgeschlagen';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'WhisPaste darf das virtuelle Tastaturgerät /dev/uinput noch nicht nutzen. Der Text liegt in der Zwischenablage, füge ihn mit $paste ein. Klicke hier, um es einzurichten.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'Auto-Paste blockiert — Einrichtung nötig';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'Auto-Paste ist hier nicht verfügbar: Auf diesem System fehlt das virtuelle Tastaturgerät dafür. Der Text liegt in der Zwischenablage, füge ihn mit $paste ein. Klicke hier für die Auto-Paste-Einstellungen.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray => 'Auto-Paste nicht verfügbar';

  @override
  String get pasteCapabilityCheckTitle => 'Einen Moment…';

  @override
  String get pasteCapabilityReady => 'Alles bereit';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Dein Text landet direkt an deinem Cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Noch nicht freigegeben';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Paste ist auf dieser Plattform nicht verfügbar';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'Auto-Paste ist hier gerade nicht möglich';

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
      'Manchmal merkt sich macOS einen alten Eintrag und vergisst die neue Freigabe. Setze den Eintrag zurück, dann fragt macOS dich nochmal sauber.';

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
      'Die Auto-Paste-Berechtigung ist gesetzt, greift aber erst nach einem Neustart. WhisPaste beendet sich und kommt sofort zurück.';

  @override
  String get pasteRestartAlertConfirm => 'Jetzt neu starten';

  @override
  String get pasteStaleEntryGuideTitle => 'Alten WhisPaste-Eintrag entfernen';

  @override
  String get pasteStaleEntryGuideBody =>
      'macOS hält noch die Auto-Paste-Berechtigung einer früheren WhisPaste-Version fest. Dieser Eintrag lässt sich nicht einschalten – er muss einmal entfernt werden:\n\n1. In der Liste „WhisPaste“ auswählen.\n2. Unter der Liste auf „−“ klicken.\n3. Zu WhisPaste zurückkehren.\n\nNach einem Neustart fragt macOS erneut – einfach erlauben.';

  @override
  String get pasteStaleEntryGuideConfirm => 'Systemeinstellungen öffnen';

  @override
  String get pasteStaleEntryRestartTitle => 'WhisPaste neu starten';

  @override
  String get pasteStaleEntryRestartBody =>
      'Sobald der alte Eintrag entfernt ist, starte WhisPaste neu. macOS fragt dann erneut nach der Berechtigung – bestätige sie und schalte WhisPaste ein.';

  @override
  String get pasteStaleEntryRestartConfirm => 'WhisPaste neu starten';

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
  String get autoPasteGateAlertTitle => 'Für Auto-Paste fehlt ein Schalter';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste fügt deinen Text direkt an der Schreibmarke ein. macOS verlangt dafür einen Schalter, den nur du umlegen kannst: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen. Bestätige, um genau diese Seite zu öffnen — deine Freigabe erkennt WhisPaste automatisch und startet sich danach bei Bedarf selbst neu.';

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
      'Unter Windows ist keine Berechtigung nötig — entscheide nur, ob WhisPaste deinen Text automatisch für dich einfügen soll.';

  @override
  String get onboardingPasteSubtitleLinux =>
      'Unter Linux fragt kein Systemdialog. Unten steht, ob und was du dafür einrichten musst.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste bereit';

  @override
  String get onboardingPasteChipPending => 'Auto-Paste-Zugriff ausstehend';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: Aktion nötig';

  @override
  String get onboardingPasteGrantCta => 'Auto-Paste freigeben';

  @override
  String get onboardingPasteSkip => 'Erstmal nur kopieren, ohne Auto-Paste';

  @override
  String get onboardingPasteWhyMac =>
      'Ohne Freigabe wird dein Text in die Zwischenablage kopiert. Du musst dann selbst mit ⌘V einfügen.';

  @override
  String get onboardingPasteWhyWin =>
      'Auto-Paste drückt nach jeder Aufnahme Strg+V für dich — der Text landet direkt dort, wo du gerade schreibst. Auf diesem Gerät geprüft, unten aktivieren.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'In Programmen, die als Administrator laufen, funktioniert Auto-Paste nicht. Der Text bleibt dann in der Zwischenablage, und du fügst ihn mit Strg+V ein.';

  @override
  String get onboardingPasteWinOnTitle => 'Auto-Paste ist aktiv';

  @override
  String get onboardingPasteWinOnDetail =>
      'Nach jeder Aufnahme drückt WhisPaste Strg+V für dich — der Text landet direkt an deinem Cursor. Eine Kopie bleibt zusätzlich in der Zwischenablage.';

  @override
  String get onboardingPasteLinuxNative =>
      'Auto-Paste braucht deine Freigabe für die virtuelle Tastatur (/dev/uinput). Mit dem .deb-Paket wählst du „Freigeben (Administratorpasswort)“ und gibst dein Administratorpasswort ein, sonst kopierst du den Befehl und führst ihn einmal im Terminal aus. In den Einstellungen kannst du die Freigabe wieder entfernen.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'In der Flatpak-Version macht --device=all /dev/input/* und /dev/uinput in der Sandbox sichtbar. WhisPaste selbst liest keine Eingabegeräte. Hat dein Benutzer auf dem Rechner Leserechte (z. B. als Mitglied der Gruppe input), könnte die App Tastatureingaben anderer Programme lesen. Auto-Paste braucht zusätzlich Schreibzugriff auf /dev/uinput auf dem Rechner: Kopiere den Befehl und führe ihn einmal im Terminal aus. Er installiert die udev-Regel 71-whispaste-uinput.rules, die nur der angemeldeten Sitzung Zugriff gibt. Der Befehl braucht Administratorrechte (sudo) und verändert das System. Wer das nicht möchte: Auto-Paste aus lassen und Text von Hand einfügen.';

  @override
  String get onboardingPasteLinuxSnap =>
      'In der Snap-Version führe das einmal im Terminal aus: sudo snap connect whispaste:uinput. Bis dahin kopiert Auto-Paste den Text nur.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'Das AppImage braucht Zugriff auf /dev/uinput (das virtuelle Tastaturgerät). Kopiere den Befehl und führe ihn einmal im Terminal aus. Er installiert die udev-Regel 71-whispaste-uinput.rules nach /etc/udev/rules.d/ und führt sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput aus. Die Regel gibt nur der angemeldeten Sitzung Schreibzugriff. Der Befehl braucht Administratorrechte (sudo) und verändert das System. Bis dahin kopiert Auto-Paste den Text nur.';

  @override
  String get onboardingPasteWinEnableCta => 'Auto-Paste aktivieren';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'In Programmen, die als Administrator laufen, funktioniert Auto-Paste nicht. Der Text bleibt dann in der Zwischenablage, und du fügst ihn mit Strg+V ein.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'Auto-Paste ist eingeschaltet. Bis der Zugriff eingerichtet ist, legt WhisPaste den Text in die Zwischenablage, und du fügst ihn mit Strg+V ein.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'Der Text landet in der Zwischenablage. Füge ihn mit $shortcut ein.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Setze das Häkchen bei WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Die Systemeinstellungen sind offen. Suche WhisPaste in der Liste und schalte es ein.\n\nNicht in der Liste? Ziehe das App-Symbol einfach rein oder klicke auf „+“.';

  @override
  String get onboardingPasteTestTitle => 'Probier Auto-Paste aus';

  @override
  String get onboardingPasteTestSubtitle =>
      'Drücke den Button. Der Demo-Text sollte gleich im Feld unten erscheinen.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste tippt für dich.';

  @override
  String get onboardingPasteTestSuccess =>
      'Auto-Paste funktioniert! Klicke auf Weiter.';

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
  String get settingsOverlayModeFloating => 'Schwebend (immer sichtbar)';

  @override
  String get settingsOverlayModeOff => 'Aus';

  @override
  String get settingsOverlayStartPosition => 'Overlay-Startposition';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Wo das Aufnahme-Overlay beim Aufnahmestart erscheint';

  @override
  String get settingsOverlayStartTopCenter => 'Oben mittig';

  @override
  String get settingsOverlayStartBottomCenter => 'Unten mittig';

  @override
  String get settingsOverlayStartLastPosition => 'Letzte Position merken';

  @override
  String get settingsShowFloatingButton => 'Schwebender Button';

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
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return 'ca. $count von $budget belegt';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Belegt die Liste mehr als $budget, wird der Rest automatisch weggelassen.';
  }

  @override
  String get settingsPunctuationPriming => 'Satzzeichen anregen';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Lässt die Erkennung eher Satzzeichen setzen, wenn kein eigenes Vokabular hinterlegt ist. Die Geschwindigkeit ändert sich nicht.';

  @override
  String get settingsVadEnabled => 'Stille am Ende entfernen';

  @override
  String get settingsVadEnabledSubtitle =>
      'Schneidet lange Stille und Rauschen am Ende einer Aufnahme ab. So erfindet die Erkennung keinen Schlusssatz (z. B. „Danke fürs Zuschauen“).';

  @override
  String get settingsStripPunctuation => 'Satzzeichen entfernen';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Entfernt Punkte, Kommas und andere Satzzeichen aus jedem Transkript, bevor es gespeichert oder eingefügt wird. Zahlen wie 3,5 bleiben unverändert. Gilt gleich für alle Erkennungsarten.';

  @override
  String get settingsNumericOnlyMode => 'Nur Zahlen';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Wandelt gesprochene Zahlen (Deutsch und Englisch) in Ziffern um, z. B. wird „fünf Komma zwei“ zu „5,2“. Lässt das Transkript unverändert, wenn es nicht vollständig umwandelbar ist.';

  @override
  String get settingsRemoveFillerWords => 'Füllwörter entfernen';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'Entfernt Verlegenheitslaute wie „äh“, „ähm“ und „öhm“, bevor das Transkript gespeichert oder eingefügt wird. Nur eindeutige deutsche und englische Füllwörter; Wörter mit Bedeutung bleiben unangetastet.';

  @override
  String get settingsVoiceLineBreaks => 'Gesprochene Zeilenumbrüche';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'Macht aus gesprochenen Befehlen wie „neuer Absatz“ und „neue Zeile“ echte Zeilenumbrüche. Gilt für die Sprache der Transkription, bei automatischer Erkennung für alle unterstützten Sprachen.';

  @override
  String get settingsSpokenPunctuation => 'Gesprochene Satzzeichen';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'Sagst du „Punkt“ oder „Komma“ als Wort im Satz, prüfe danach den Text.';

  @override
  String get settingsAppLanguage => 'App-Sprache';

  @override
  String get settingsSttModels => 'Sprachmodelle';

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
  String get settingsFactoryReset => 'Alles zurücksetzen';

  @override
  String get settingsFactoryResetTitle => 'Werksreset';

  @override
  String get settingsFactoryResetMessage =>
      'Damit werden sofort gelöscht: Transkriptionen mit Tags und Notizen, gespeicherte Audiodateien, Wörterbuch, Textbausteine, Statistik, API-Schlüssel, heruntergeladene Modelle, Protokolle und Einstellungen. Die App wird in den Ausgangszustand zurückversetzt.\n\nDie App kann nichts davon wiederherstellen. Dateien werden normal gelöscht und nicht überschrieben; mit Spezialwerkzeugen lassen sich Reste unter Umständen wiederherstellen.';

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
      'Beende Sprachmodell…';

  @override
  String get settingsFactoryResetPhaseDeletingModels => 'Lösche Sprachmodelle…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio => 'Lösche Aufnahmen…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase => 'Lösche Datenbank…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Setze Anmeldedaten zurück…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Setze Einstellungen zurück…';

  @override
  String settingsFactoryResetFailedMessage(String areas) {
    return 'Das Zurücksetzen ist nicht vollständig. Betroffen: $areas. Du kannst es erneut versuchen.';
  }

  @override
  String get factoryResetAreaDb =>
      'Transkriptionen, Notizen, Wörterbuch, Textbausteine und Statistik';

  @override
  String get factoryResetAreaAudio => 'Audiodateien';

  @override
  String get factoryResetAreaModels => 'Modelle und Protokolle';

  @override
  String get factoryResetAreaSecure => 'API-Schlüssel';

  @override
  String get factoryResetAreaSettings => 'Einstellungen';

  @override
  String get factoryResetAreaProcess => 'Hintergrundprozess';

  @override
  String get factoryResetRetryAction => 'Erneut versuchen';

  @override
  String get factoryResetKeyringHint =>
      'Die API-Schlüssel ließen sich nicht aus dem Schlüsselbund entfernen. Lösche bei Bedarf die Einträge, die mit „wp_“ beginnen, selbst in der Passwortverwaltung deines Systems.';

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
    return 'Dies ersetzt deine aktuellen Einstellungen – Oberfläche, Sprachmodell-Konfiguration, Verhalten, Textersetzungen und Textbausteine eingeschlossen – durch den Inhalt von $path. Deine API-Schlüssel bleiben unangetastet.';
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
      'Der bisherige Cloud-Anbieter wurde entfernt. Die Spracherkennung läuft jetzt auf diesem Gerät.';

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
  String get statusSelectionEdited => 'Auswahl bearbeitet';

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
  String get unsavedInputTitle => 'Änderungen verwerfen?';

  @override
  String get unsavedInputMessage =>
      'Der eingegebene Text ist noch nicht gespeichert.';

  @override
  String get unsavedInputDiscard => 'Verwerfen';

  @override
  String get trayUnavailableMinimizedHint =>
      'Das Tray-Symbol ist nicht verfügbar. WhisPaste wurde minimiert und läuft weiter.';

  @override
  String get settingsSaveFailedToast =>
      'Die Einstellung konnte nicht gespeichert werden. Es bleibt der bisherige Wert.';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionClose => 'Schließen';

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
  String get analyticsNoRecordingsInPeriod =>
      'In diesem Zeitraum gibt es keine Aufnahmen';

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
  String get analyticsTimeSaved => 'Zeitersparnis (geschätzt)';

  @override
  String get analyticsAvgLatency => 'Ø Zeit bis zum Text';

  @override
  String get analyticsRecordingActivity => 'Aufnahmeaktivität';

  @override
  String get analyticsLast7Days => 'Letzte 7 Tage';

  @override
  String get analyticsWeekEmpty =>
      'In den letzten 7 Tagen gab es keine Aufnahmen';

  @override
  String get analyticsModelUsage => 'Sprachmodellnutzung';

  @override
  String get analyticsNoModelData =>
      'Noch keine Modelldaten in diesem Zeitraum';

  @override
  String get analyticsLoading => 'Statistik wird geladen';

  @override
  String get analyticsDurationDistribution => 'Dauerverteilung';

  @override
  String get analyticsCostSavings => 'Kosten & Ersparnis';

  @override
  String get analyticsLocalSavings => 'Lokale Ersparnis';

  @override
  String get analyticsCloudCost => 'Cloud-Kosten';

  @override
  String get analyticsEstimateNote =>
      'Schätzung aus den Listenpreisen pro Transkription';

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
  String get analyticsResetDone => 'Statistiken wurden zurückgesetzt.';

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
      'Füge Ersetzungen hinzu, um Wörter beim Aufnehmen automatisch zu ersetzen.\nBeispiel: „mfg“ → „mit freundlichen Grüßen“';

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
  String get replacementsMissingTrigger => 'Gib mindestens einen Auslöser ein.';

  @override
  String get replacementsRemoveTrigger => 'Auslöser entfernen';

  @override
  String get replacementsReplacementLabel => 'Ersetzungstext';

  @override
  String get replacementsMissingReplacement => 'Gib den Ersetzungstext ein.';

  @override
  String get replacementsReplacementHint => 'z. B. mit freundlichen Grüßen';

  @override
  String get replacementsReplacementHelper =>
      'Verwende \\n für einen Zeilenumbruch und \\n\\n für eine Leerzeile. Für ein wörtliches Backslash-n schreibe \\\\n.';

  @override
  String get replacementsDeleteTitle => 'Ersetzung löschen';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Ersetzung „$trigger“ entfernen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get replacementsImportFromFolder => 'Aus Ordner importieren';

  @override
  String get replacementsImportHint =>
      'Durchsucht einen Projektordner nach Bezeichnern und legt sie als unscharfe (fuzzy) Ersetzungen an — nichts verlässt dein Gerät.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return '$found gefunden, $added hinzugefügt, $skipped Dublette(n) übersprungen';
  }

  @override
  String get replacementsImportScanning =>
      'Ordner wird durchsucht — bei großen Projekten kann das einen Moment dauern…';

  @override
  String get replacementsImportError =>
      'Import fehlgeschlagen — der Ordner konnte nicht durchsucht werden.';

  @override
  String get replacementsImportedBadge => 'Importiert';

  @override
  String get replacementsLearnedBadge => 'Gelernt';

  @override
  String get correctionLearningToggleLabel => 'Aus Korrekturen lernen';

  @override
  String get correctionLearningToggleEnabled =>
      'Wiederholte Korrekturen werden auf Vorschläge geprüft';

  @override
  String get correctionLearningToggleDisabled =>
      'Korrekturen werden nicht auf Vorschläge geprüft';

  @override
  String get correctionLearningHowTo =>
      'Sag beim Aufnehmen einer Notiz in den Aufnahmen „korrektur: …“ (oder „correct: …“), gefolgt vom richtigen Text, um sie zu überschreiben. Korrigierst du zweimal dasselbe, schlägt WhisPaste hier eine automatische Ersetzung dafür vor.';

  @override
  String get correctionCandidatesCardTitle =>
      'Aus deinen Korrekturen vorgeschlagen';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count Vorschlag/Vorschläge aus wiederholten Korrekturen — vor der Übernahme prüfen.';
  }

  @override
  String get correctionCandidatesReviewButton => 'Prüfen';

  @override
  String get correctionCandidatesReviewTitle => 'Gelernte Korrekturen prüfen';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    return '$count wiederholte Korrektur(en) — übernimm, was WhisPaste künftig automatisch anwenden soll. Nichts ändert sich, bevor du bestätigst.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return '$added gelernte Ersetzung(en) hinzugefügt';
  }

  @override
  String get replacementsImportNothingFound =>
      'In diesem Ordner wurden keine neuen Bezeichner gefunden.';

  @override
  String get replacementsImportReviewTitle => 'Auswählen, was importiert wird';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return '$count Kandidaten gefunden — wähle aus, welche zu Ersetzungen werden. Es wird nichts hinzugefügt, bevor du bestätigst.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'Kandidaten filtern';

  @override
  String get replacementsImportReviewSelectAllFiltered =>
      'Alle angezeigten auswählen';

  @override
  String get replacementsImportReviewDeselectAll => 'Alle abwählen';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return '$selected von $total ausgewählt';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'Kein Kandidat entspricht deinem Filter.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'Auswahl importieren ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'Abgleich';

  @override
  String get replacementsMatchModeExact => 'Exakt';

  @override
  String get replacementsMatchModeFuzzy => 'Ähnlich';

  @override
  String get replacementsFuzzyToleranceLabel => 'Toleranz';

  @override
  String get replacementsFuzzyToleranceStrict => 'Streng';

  @override
  String get replacementsFuzzyToleranceStandard => 'Standard';

  @override
  String get replacementsFuzzyToleranceTolerant => 'Tolerant';

  @override
  String get replacementsFuzzyToleranceHint =>
      'Wie ähnlich eine gesprochene Formulierung dem Auslöser klingen muss, damit sie noch als Treffer zählt. Streng erkennt nur nahezu identische Formulierungen — dadurch wird fast nie versehentlich etwas ersetzt, ein undeutlich gesprochener Auslöser kann aber unerkannt bleiben. Standard ist ein ausgewogener Mittelweg für den Alltag. Tolerant erkennt auch deutlich abweichende Aussprache oder Formulierung, mit höherem Risiko, dass etwas ersetzt wird, das nicht gemeint war.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Auslöser unter $minLength Zeichen können nicht unscharf abgeglichen werden — das erzeugt zu viele Fehltreffer.';
  }

  @override
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'Der Auslöser „$trigger“ ist bereits vorhanden (Ersetzung: „$replacement“).';
  }

  @override
  String get snippetsSearch => 'Textbausteine suchen…';

  @override
  String get snippetsSearchFieldLabel => 'Textbausteine suchen';

  @override
  String get snippetsAdd => 'Hinzufügen';

  @override
  String get snippetCopySuffix => '(Kopie)';

  @override
  String get snippetsEmpty => 'Noch keine Textbausteine';

  @override
  String get snippetsEmptyHint =>
      'Füge einen Textbaustein hinzu, um wiederkehrende Texte schnell wiederzuverwenden — z. B. eine Signatur oder eine Standardantwort.';

  @override
  String get snippetsNoMatches => 'Keine Treffer';

  @override
  String get snippetsNoMatchesHint => 'Versuche einen anderen Suchbegriff.';

  @override
  String get snippetsEditSnippet => 'Textbaustein bearbeiten';

  @override
  String get snippetsNewSnippet => 'Neuer Textbaustein';

  @override
  String get snippetsDialogHint =>
      'Öffne beim Aufnehmen die Textbaustein-Auswahl, um diesen Text einzufügen.';

  @override
  String get snippetsTitleLabel => 'Titel';

  @override
  String get snippetsTitleHint => 'z. B. E-Mail-Signatur';

  @override
  String get snippetsBodyLabel => 'Text';

  @override
  String get snippetsBodyHint => 'Der Text, den dieser Textbaustein einfügt…';

  @override
  String get snippetsKindLabel => 'Art';

  @override
  String get snippetsKindStatic => 'Statisch';

  @override
  String get snippetsKindInteractive => 'Interaktiv';

  @override
  String get snippetsFieldsLabel => 'Felder';

  @override
  String get snippetsFieldsHint =>
      'Du wirst der Reihe nach durch jedes Feld geführt, jeweils mit einer eigenen kurzen Aufnahme.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'Name für Feld $number';
  }

  @override
  String get snippetsFieldMoveUp => 'Feld nach oben verschieben';

  @override
  String get snippetsFieldMoveDown => 'Feld nach unten verschieben';

  @override
  String get snippetsFieldRemove => 'Feld entfernen';

  @override
  String get snippetsFieldAdd => 'Feld hinzufügen';

  @override
  String get snippetsFieldInsertIntoTemplate => 'In Vorlage einfügen';

  @override
  String snippetsFieldsMinWarning(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min benannte Felder',
      one: '1 benanntes Feld',
    );
    return 'Ein interaktiver Textbaustein braucht mindestens $_temp0.';
  }

  @override
  String get snippetsTemplateLabel => 'Vorlage';

  @override
  String get snippetsTemplateHint =>
      'Schreibe den Text deines Textbausteins und platziere jedes Feld über den Einfügen-Button daneben an beliebiger Stelle.';

  @override
  String get snippetsTemplateFieldHint =>
      'Schreibe hier deinen Text und füge Felder über die Buttons oben ein.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'Noch nicht alle Felder werden in der Vorlage verwendet — ihr gesprochener Text bliebe sonst ungenutzt.';

  @override
  String get snippetsSaveMissingTitle => 'Titel fehlt';

  @override
  String get snippetsSaveMissingBody => 'Text fehlt';

  @override
  String get snippetsFieldsDuplicateWarning =>
      'Feldnamen müssen unterschiedlich sein.';

  @override
  String get snippetsInteractiveBadge => 'Interaktiv';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Felder',
      one: '1 Feld',
    );
    return '$_temp0 · Enter startet';
  }

  @override
  String interactiveSnippetBriefingHint(String name) {
    return 'Feld 1: $name · Esc: Abbrechen';
  }

  @override
  String interactiveSnippetAnnounceLabel(int index, int count, String name) {
    return 'Feld $index/$count: $name';
  }

  @override
  String get interactiveSnippetAnnounceHint => 'Gleich sprechen…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'Weiter';

  @override
  String get snippetsDeleteTitle => 'Textbaustein löschen';

  @override
  String snippetsDeleteMessage(String title) {
    return 'Textbaustein „$title“ entfernen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Trigger-Wort für die Auswahl';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Sprich nur dieses Wort, um die Textbaustein-Auswahl zu öffnen. Leer lassen, um die Auswahl auszuschalten.';

  @override
  String get snippetsPickerTriggerHint => 'z. B. Textbaustein';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'Das Trigger-Wort ist gesetzt, aber es gibt noch keine Textbausteine — sagst du es, wird es als normaler Text eingefügt, bis du deinen ersten Textbaustein anlegst.';

  @override
  String get snippetsPickerHotkeyLabel => 'Hotkey für die Auswahl';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Öffnet die Auswahl sofort — der zweite Weg zum selben Panel.';

  @override
  String get snippetsPickerHotkeyOff =>
      'Der Hotkey für die Auswahl ist ausgeschaltet.';

  @override
  String get snippetsPickerHotkeyEnable => 'Hotkey einschalten';

  @override
  String get snippetsPickerUnavailable =>
      'Die Textbaustein-Auswahl ist auf dieser Plattform noch nicht verfügbar.';

  @override
  String get snippetsPickerSemanticsLabel => 'Textbaustein-Auswahl';

  @override
  String get snippetsPickerInsertAction => 'Einfügen';

  @override
  String get aboutTagline => 'Sprache zu Text, sofort.';

  @override
  String get aboutWhatsNew => 'Neuigkeiten';

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
      'Lokale Spracherkennung, auf der GPU beschleunigt, wo verfügbar (Metal, Vulkan, CUDA), sonst auf der CPU (~25 Sprachen).';

  @override
  String get aboutParakeetModelCredit =>
      'Modell: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'GGUF-Konvertierung: ggml-org, MIT';

  @override
  String get aboutLinks => 'Links';

  @override
  String get helpLegalTitle => 'Rechtliches';

  @override
  String get helpDiagnosticsPublicNote =>
      'GitHub-Issues sind öffentlich. Prüfe den Bericht vor dem Einfügen.';

  @override
  String get helpDiagnosticsBuilding => 'Bericht wird erstellt …';

  @override
  String get tabsScrollBack => 'Frühere Tabs anzeigen';

  @override
  String get tabsScrollForward => 'Weitere Tabs anzeigen';

  @override
  String get aboutWebsite => 'Webseite';

  @override
  String get aboutGitHubRepo => 'GitHub-Repository';

  @override
  String get aboutFollowOnX => 'Auf X folgen';

  @override
  String get aboutMitLicense => 'MIT-Lizenz';

  @override
  String get aboutThirdPartyLicenses => 'Lizenzen von Drittanbietern';

  @override
  String get aboutThirdPartyLicensesDetail => 'Schriften und Modelle';

  @override
  String get aboutPrivacyPolicy => 'Datenschutzerklärung';

  @override
  String get aboutImprint => 'Impressum';

  @override
  String get aboutSystemInfo => 'Systeminformationen';

  @override
  String get aboutSystemInfoDesc =>
      'Kopiere eine kompakte Diagnosezusammenfassung für Fehlerberichte.';

  @override
  String get aboutDiagnosticsContentsTitle => 'Was der Bericht enthält';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'App-Version, Betriebssystem, Programmpfad ohne Benutzernamen, Sprachmodell (Variante, Modell, Status, letzter Fehler), GPU, Modelldateien und die letzten 40 Logzeilen. Schlüssel und Tokens sind in den Logzeilen geschwärzt.';

  @override
  String get aboutDiagnosticsPreviewShow => 'Anzeigen';

  @override
  String get aboutDiagnosticsPreviewHide => 'Ausblenden';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'Diagnose unvollständig: $error';
  }

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
  String get feedbackRatingLabel => 'Wie zufrieden bist du mit WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Erzähl uns mehr';

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
  String feedbackSubmitMissing(String what) {
    return 'Zum Senden bitte $what.';
  }

  @override
  String get feedbackMissingCategory => 'wähle aus, worum es geht';

  @override
  String get feedbackMissingRating => 'bewerte, wie du WhisPaste findest';

  @override
  String get feedbackMissingComment => 'schreib uns eine Nachricht';

  @override
  String get feedbackMissingEmail =>
      'korrigiere die E-Mail-Adresse oder lass das Feld leer';

  @override
  String get feedbackRequiredMarker => 'Pflicht';

  @override
  String get feedbackPublishConsentLabel =>
      'Ich erlaube, dass mein Feedback anonym als Zitat auf der Website erscheinen darf.';

  @override
  String get feedbackPublishConsentExplanation =>
      'Standardmäßig aus. Gezeigt werden nur dein Text und deine Bewertung, nie Name oder E-Mail. Du kannst die Zustimmung jederzeit mit einem Klick auf der Seite Feedback in der App zurückziehen.';

  @override
  String get feedbackWithdrawConsentLabel => 'Zustimmung zurückziehen';

  @override
  String get feedbackWithdrawConsentHelp =>
      'Gilt für Feedback, das du von diesem Gerät aus mit Zustimmung gesendet hast. Das Zitat verschwindet innerhalb von etwa 24 Stunden von der Website.';

  @override
  String get feedbackWithdrawConsentPending =>
      'Der Widerruf ist gespeichert und wird gesendet, sobald WhisPaste mit Internetverbindung läuft (bis zu 30 Tage); sonst bitte per E-Mail widerrufen.';

  @override
  String get feedbackWithdrawNoCode =>
      'Auf diesem Gerät ist kein Widerrufscode gespeichert – per E-Mail zurückziehen';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'Widerruf vom $date wird gesendet …';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'Widerruf vom $date nicht zugestellt – per E-Mail widerrufen';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'Der Widerruf konnte nicht zugestellt werden – bitte per E-Mail widerrufen.';

  @override
  String get feedbackWithdrawEmailLabel => 'Per E-Mail zurückziehen';

  @override
  String get feedbackWithdrawEmailSubject =>
      'Widerruf meiner Zustimmung zum Zitat';

  @override
  String get feedbackWithdrawEmailBody =>
      'Bitte zieh meine Zustimmung zum Zitat meines Feedbacks zurück.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'Datum des Feedbacks:';

  @override
  String get feedbackWithdrawEmailReferenceLabel => 'Widerrufs-Referenz:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'Ich habe die E-Mail gesendet';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'Kein E-Mail-Programm gefunden. Schick die vorbereitete Nachricht bitte an diese Adresse:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'Adresse und Nachricht kopieren';

  @override
  String get feedbackWithdrawEmailCopied => 'Adresse und Nachricht kopiert.';

  @override
  String get feedbackWithdrawLocked =>
      'Der Schlüsselspeicher deines Systems ist gerade nicht lesbar. Zustimmungen und Widerrufe, die dort liegen, kann WhisPaste nicht senden. Bitte widerrufe per E-Mail; die vorbereitete E-Mail enthält die nötigen Referenzen.';

  @override
  String get feedbackWithdrawConsentDone =>
      'Widerruf übermittelt. Das Zitat verschwindet innerhalb von etwa 24 Stunden von der Website, beim nächsten täglichen Update.';

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
  String get dockOutputCopy => 'Kopieren';

  @override
  String get dockOutputPaste => 'Einfügen';

  @override
  String get dockOutputBoth => 'Kopieren & Einfügen';

  @override
  String get dockOutputNothing => 'Manuell';

  @override
  String get sttStatusStarting => 'Startet…';

  @override
  String get sttStatusReady => 'Bereit';

  @override
  String get sttStatusError => 'Fehler';

  @override
  String get statusBarSttTooltip => 'Sprachmodell: Status';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Erkennung läuft auf: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'Echte GPU-Auslastung ist plattformübergreifend nicht ohne Zusatzrechte messbar; die angezeigte Prozentzahl bezieht sich stattdessen auf die CPU-Aktivität dieses Prozesses.';

  @override
  String get statusBarRecording => 'Aufnahme läuft…';

  @override
  String get statusBarTranscribing => 'Wird verarbeitet…';

  @override
  String get statusBarRefining => 'Wird verarbeitet…';

  @override
  String get statusBarHotkeyTooltip =>
      'Globaler Hotkey: klicken zum Konfigurieren';

  @override
  String get statusBarAutoPasteOffHint => 'Auto-Paste einschalten…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste ist aktuell aus. Klicken, um die Einstellungen zu öffnen.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Hinweis ausblenden';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'Automatisierung: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'Automatisierung: Fehler';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'Automatisierungs-API aktiv auf Port $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'Automatisierungs-API aktiv auf Port $port (Port $requestedPort war belegt)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'Automatisierungs-API: kein freier Port gefunden';

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
  String get modelServerReady => 'Sprachmodell bereit';

  @override
  String get modelServerMissing => 'Sprachmodell nicht installiert';

  @override
  String get modelServerWhisper => 'Lokales Sprachmodell';

  @override
  String get modelReady => 'Bereit';

  @override
  String get modelDownloadComplete => 'Sprachmodell einsatzbereit';

  @override
  String get modelUse => 'Verwenden';

  @override
  String get modelDownload => 'Laden';

  @override
  String get modelDownloading => 'Wird geladen…';

  @override
  String get modelDownloadingEngine => 'Sprachmodell wird vorbereitet…';

  @override
  String get modelVerifying => 'Wird überprüft…';

  @override
  String get modelExtracting => 'Wird entpackt…';

  @override
  String get modelDeleteConfirm => 'Sprachmodell löschen?';

  @override
  String get modelDeleteConfirmMessage =>
      'Die Datei des Sprachmodells wird von diesem Gerät gelöscht. Du kannst sie jederzeit erneut herunterladen.';

  @override
  String get modelTierDeleteConfirm => 'Diese Modelle löschen?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Modelle ($size) werden von diesem Gerät gelöscht. Du kannst sie jederzeit erneut herunterladen.',
      one:
          '1 Modell ($size) wird von diesem Gerät gelöscht. Du kannst es jederzeit erneut herunterladen.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'Schnell';

  @override
  String get qualityTierCompactDesc =>
      'Schnelle Ergebnisse, kleiner Download. Ideal für kurze Notizen und schnelle Nachrichten.';

  @override
  String get qualityTierBalancedLabel => 'Ausgewogen';

  @override
  String get qualityTierBalancedDesc =>
      'Zuverlässig und genau für alltägliche Aufnahmen. Funktioniert auf den meisten Geräten.';

  @override
  String get qualityTierPremiumLabel => 'Genau';

  @override
  String get qualityTierPremiumDesc =>
      'Höchste Genauigkeit für längere Aufnahmen und komplexe Inhalte. Benötigt eine leistungsfähige Grafikkarte.';

  @override
  String get qualityTierRecommended => 'Empfohlen für deinen Rechner';

  @override
  String get qualityTierRecommendedMeasured => 'Gemessen für deinen Rechner';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size Download';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Sprachmodell herunterladen';

  @override
  String get qualityTierChooseDifferent => 'Andere Stufe wählen';

  @override
  String get qualityTierActive => 'Aktiv';

  @override
  String get qualityTierInfoSlow =>
      'Genau, braucht auf diesem Gerät deutlich länger';

  @override
  String get qualityTierInfoSlowEstimate =>
      'Genau, dauert auf diesem Gerät vermutlich deutlich länger (geschätzt)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Genau, dauert ~${ratio}x länger als Schnell';
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
  String get benchmarkRowSubtitle =>
      'Misst, wie schnell jede installierte Stufe auf diesem Rechner läuft. Die Ergebnisse bestimmen die Geschwindigkeitshinweise und die Empfehlung.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'Läuft… Stufe $step von $total: $tier';
  }

  @override
  String get benchmarkCancel => 'Test abbrechen';

  @override
  String get benchmarkCancelled =>
      'Test abgebrochen. Bereits gemessene Stufen sind gespeichert.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stufen gemessen',
      one: '1 Stufe gemessen',
    );
    return 'Messung abgeschlossen: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'Zuletzt gemessen: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'Rechenweg: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'Prozessor (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'Grafikkarte ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds s Rechenzeit je Sekunde Audio';
  }

  @override
  String get benchmarkNoResult =>
      'Noch keine Messung. Starte den Test, um Geschwindigkeitshinweise für deinen Rechner zu erhalten.';

  @override
  String get benchmarkStaleNotice =>
      'Ergebnisse stammen von einem anderen Rechner oder einer früheren Version. Sie werden im Hintergrund neu gemessen.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'Die Messung gilt für Whisper-Modelle. Parakeet wird nicht gemessen.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'Nach der Messung empfohlen: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'Auf $tier wechseln';
  }

  @override
  String get benchmarkErrorBusy =>
      'Während einer Aufnahme kann der Test nicht laufen. Starte ihn danach erneut.';

  @override
  String get benchmarkErrorNoModel =>
      'Keine Stufe ist installiert. Lade zuerst ein Sprachmodell herunter.';

  @override
  String get benchmarkErrorFailed =>
      'Der Test konnte nicht abgeschlossen werden.';

  @override
  String get benchmarkRetry => 'Erneut versuchen';

  @override
  String get qualityTierActionOverride => 'Trotzdem verwenden';

  @override
  String get qualityTierActionOverrideHint =>
      'Diese Stufe trotz Warnung verwenden';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'Standard';

  @override
  String get settingsQualityBalanced => 'Ausgewogen';

  @override
  String get settingsQualityHigh => 'Hohe Qualität';

  @override
  String get settingsQualityBest => 'Genau';

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
      'Erweiterte Sprachmodell-Einstellungen';

  @override
  String get infoEngineDownloading =>
      'Sprachmodell wird vorbereitet. Bitte warte einen Moment.';

  @override
  String get infoModelMissing =>
      'Bitte lade zuerst ein Sprachmodell in den Einstellungen herunter.';

  @override
  String infoModelMissingSelected(String size) {
    return 'Das ausgewählte Sprachmodell ($size) ist noch nicht heruntergeladen.';
  }

  @override
  String get infoModelMissingDownload => 'Jetzt herunterladen';

  @override
  String get statusBarModelMissing => 'Sprachmodell fehlt';

  @override
  String statusBarModelDownloading(int percent) {
    return 'Sprachmodell wird geladen … $percent %';
  }

  @override
  String get modelDownloadAction => 'Herunterladen';

  @override
  String get modelMissingDownloadAction => 'Fehlt – herunterladen';

  @override
  String get infoPipelineBusy =>
      'WhisPaste ist noch mit der vorherigen Aufnahme beschäftigt.';

  @override
  String get infoSnippetPickerEmpty =>
      'Du hast noch keine Textbausteine. Lege einen an, dann öffnet sich die Auswahl.';

  @override
  String get infoSnippetPickerEmptyAction => 'Textbausteine öffnen';

  @override
  String get oomRecoveryTitle =>
      'Aufnahme abgebrochen: Grafikkarte hat zu wenig Speicher';

  @override
  String get oomRecoveryMessage =>
      'Deiner GPU ist nicht mehr genügend Speicher verfügbar. Wie möchtest du fortfahren?';

  @override
  String get oomRecoveryTrySmaller => 'Kleineres Sprachmodell versuchen';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Zu $model wechseln und Aufnahme wiederholen';
  }

  @override
  String get oomRecoverySwitchCloud => 'Zur Cloud wechseln';

  @override
  String get oomRecoverySwitchCloudHint => 'Cloud-Sprachmodell verwenden';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'Aufnahmen werden dann an $provider übertragen.';
  }

  @override
  String get oomRecoveryCancel => 'Abbrechen';

  @override
  String get oomRecoveryPermanentTitle =>
      'Lokales Sprachmodell nicht verfügbar';

  @override
  String get oomRecoveryPermanentMessage =>
      'Alle lokalen Modelle sind wegen GPU-Speicherlimits fehlgeschlagen. Bitte wechsle in den Einstellungen zu einem Cloud-Sprachmodell.';

  @override
  String get oomRecoveryPermanentCloud => 'Einstellungen öffnen';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Wechsle zu $model…';
  }

  @override
  String get oomRecoverySwitchingCloud => 'Wechsle zu Cloud-Sprachmodell…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Sprachmodell $model ist ebenfalls fehlgeschlagen. Nächste Option wird versucht…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'Kein kleineres Modell verfügbar. Wähle in den Einstellungen ein anderes Modell oder nutze die Cloud-Spracherkennung.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'Qualität reduziert: deiner GPU ist der Speicher ausgegangen. Es wurde auf ein kleineres Sprachmodell umgestellt.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Deiner GPU ist der Speicher ausgegangen. Für mehr Zuverlässigkeit wurde auf CPU-Modus umgestellt.';

  @override
  String get errorSttServerConnectionLost =>
      'Sprachmodell wurde unerwartet beendet. Bitte versuche es erneut.';

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
  String get errorCloudTimeoutLocal =>
      'Der Cloud-Dienst hat zu lange nicht geantwortet. Prüfe deine Verbindung oder diktiere offline mit dem lokalen Sprachmodell.';

  @override
  String get errorCloudTimeout =>
      'Der Cloud-Dienst hat zu lange nicht geantwortet. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get errorCloudNetworkLocal =>
      'Der Cloud-Dienst ist nicht erreichbar. Prüfe deine Internetverbindung oder diktiere offline mit dem lokalen Sprachmodell.';

  @override
  String get errorCloudNetwork =>
      'Der Cloud-Dienst ist nicht erreichbar. Prüfe deine Internetverbindung und versuche es erneut.';

  @override
  String get errorQuickNoteAppendFailed =>
      'Die Schnellnotiz konnte nicht gespeichert werden. Der Text wurde nicht angehängt. Kopiere ihn und füge ihn in die Notiz ein.';

  @override
  String get errorOnboardingNotCompleted =>
      'Bitte schließe zuerst die Einrichtung ab.';

  @override
  String get errorSttModelNotFound =>
      'Sprachmodell nicht gefunden. Bitte lade es in den Einstellungen herunter.';

  @override
  String get errorSttModelLoadFailed =>
      'Das Sprachmodell konnte nicht geladen werden. Starte WhisPaste neu. Wenn der Fehler bleibt, lade das Sprachmodell in den Einstellungen erneut herunter.';

  @override
  String get errorSttModelFileMissing =>
      'Die Datei des Sprachmodells fehlt. Lade das Sprachmodell in den Einstellungen herunter.';

  @override
  String get errorSttModelCorrupted =>
      'Die Datei des Sprachmodells ist beschädigt. Lade das Sprachmodell in den Einstellungen erneut herunter.';

  @override
  String get errorSttEngineRestartNeeded =>
      'Die Spracherkennung läuft noch in einem früheren Diktat. Starte WhisPaste neu, um sie wieder zu nutzen.';

  @override
  String get pendingRetryFailed =>
      'Die erneute Transkription ist fehlgeschlagen. Die Aufnahme bleibt für einen weiteren Versuch erhalten.';

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
      'Sprachmodell konnte nicht gestartet werden';

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
      'Das Sprachmodell ist sowohl auf der GPU als auch auf der CPU fehlgeschlagen. Bitte starte die App neu oder lade das Sprachmodell neu herunter.';

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
      'Sprachmodell startet noch. Bitte versuche es gleich nochmal.';

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
  String get errorNoMicrophone =>
      'Kein Mikrofon gefunden. Schließe ein Mikrofon an und versuche es erneut.';

  @override
  String get errorGeneric =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get modelDownloadFailed =>
      'Download fehlgeschlagen. Bitte überprüfe deine Internetverbindung.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'Nicht genug Speicherplatz für den Download: benötigt $needed / frei $free. Der Download wurde nicht gestartet.';
  }

  @override
  String get modelDeleteInUse =>
      'Die Datei des Sprachmodells wird von einem anderen Programm verwendet und konnte nicht gelöscht werden. Schließe es und versuche es erneut.';

  @override
  String get statusSttLoading => 'Sprachmodell wird geladen…';

  @override
  String get statusSttReady => 'Sprachmodell bereit';

  @override
  String get modelDownloadFailedChecksum =>
      'Die heruntergeladene Datei war beschädigt und wurde gelöscht. Bitte lade sie erneut herunter.';

  @override
  String get modelDownloadFailedStorage =>
      'Die Datei konnte nicht gespeichert werden. Prüfe, ob genug Speicherplatz frei ist.';

  @override
  String get modelDownloadFailedUnknown =>
      'Download fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get onboardingModelDownloadCancel => 'Download abbrechen';

  @override
  String get onboardingModelDiskSpaceTitle => 'Wenig Speicherplatz';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'Das Modell braucht $needed, frei sind nur $free. Der Download wird deshalb wahrscheinlich scheitern.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'Trotzdem laden';

  @override
  String get historyDuplicate => 'Duplizieren';

  @override
  String get historyDuplicated => 'Eintrag dupliziert';

  @override
  String get historyTakeAsNote => 'Als Notiz übernehmen';

  @override
  String get historyTakenAsNote => 'Als Notiz übernommen';

  @override
  String get historyOpenNote => 'Öffnen';

  @override
  String get historyViewRaw => 'Rohtext';

  @override
  String get historyViewEdited => 'Bearbeitet';

  @override
  String get historyApplySmartModePreset => 'Smart-Mode-Preset anwenden';

  @override
  String get historySmartModeApplied => 'Smart Mode angewendet';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode angewendet';

  @override
  String get smartModeUndoAction => 'Rückgängig';

  @override
  String get smartModeBusy => 'Smart Mode läuft noch';

  @override
  String get smartModeBusyRetry =>
      'Smart Mode läuft noch – bitte gleich erneut versuchen';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Namen geändert',
      one: '1 Name geändert',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'Original in die Zwischenablage kopiert – mit $shortcut einfügen. Der vorherige Inhalt wurde ersetzt.';
  }

  @override
  String get selectionUndoUnavailable => 'Rückgängig ist gerade nicht möglich.';

  @override
  String get smartModeCheckTimedOut =>
      'Die Prüfung hat zu lange gedauert – dein Text bleibt unverändert.';

  @override
  String get historySmartModeUndo => 'Smart Mode rückgängig machen';

  @override
  String get historySmartModeRestore => 'Smart Mode wiederherstellen';

  @override
  String get historySmartModeFailedModelMissing =>
      'Textmodell nicht heruntergeladen';

  @override
  String get historySmartModeFailedTimeout =>
      'Smart Mode hat zu lange gebraucht';

  @override
  String get historySmartModeFailedGeneric =>
      'Smart Mode fehlgeschlagen — bitte erneut versuchen';

  @override
  String get historySmartModeSelectTargetLanguage => 'Zielsprache wählen';

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
  String get tagManageEmpty =>
      'Noch keine Tags. Tags legst du an, indem du sie einer Aufnahme zuweist.';

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
  String tagRemoveSemanticsLabel(String tag) {
    return 'Tag „$tag“ entfernen';
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
  String get historyShortcutListGroup => 'LISTE DER AUFNAHMEN';

  @override
  String get historyShortcutMoveFocus => 'Eintrag auswählen';

  @override
  String get historyShortcutOpenEntry => 'Eintrag öffnen';

  @override
  String get historyShortcutCopyEntry => 'Eintrag kopieren';

  @override
  String get historyShortcutDeleteEntry => 'Eintrag löschen';

  @override
  String get historyShortcutSelectAll => 'Alle auswählen';

  @override
  String get historyShortcutClearSelection => 'Auswahl aufheben';

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
  String get historyShortcutDiscardEdit => 'Bearbeitung verwerfen';

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
  String get settingsKeyboardShortcut => 'Hotkey';

  @override
  String get shortcutsGroupDictate => 'Diktieren';

  @override
  String get shortcutsGroupNotes => 'Notizen & Textbausteine';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode & Auswahl bearbeiten';

  @override
  String get shortcutsAreaIntro =>
      'Diese Hotkeys wirken systemweit: in jeder App, auch wenn WhisPaste im Hintergrund läuft. Jede Kombination gehört nur einem Hotkey.';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Hotkey zum Starten und Stoppen der Aufnahme';

  @override
  String get settingsHotkeyEnabled => 'Aufnahme starten/stoppen';

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
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'Jede Modifier-Kombination ist möglich: z. B. $first, $second oder $third';
  }

  @override
  String get settingsHotkeyRecorderCancel => 'Abbrechen';

  @override
  String get settingsHotkeyRecorderSave => 'Speichern';

  @override
  String get settingsHotkeyRecorderClear => 'Leeren';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'Diese Taste lässt sich nicht als Hotkey speichern. Probier einen Buchstaben, eine Ziffer, eine F-Taste (F1-F12) oder eine Pfeiltaste.';

  @override
  String get settingsHotkeyActionRecording => 'Aufnahme starten/stoppen';

  @override
  String get settingsHotkeyActionQuickNote => 'Schnellnotiz';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'Schnellnotiz aufnehmen';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'Der erkannte Text wird an die Notiz angehängt, die als Schnellnotiz markiert ist. Welche das ist, legst du im Bereich „Notizen“ fest.';

  @override
  String get settingsQuickNoteOpenInMainWindow =>
      'Notizen im Hauptfenster öffnen';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'Aus: Die Schnellnotiz wird im Hintergrund gespeichert, eine Meldung bietet „Zur Notiz“ an. An: Das Hauptfenster kommt nach vorn und zeigt die Notiz.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Aktueller Hotkey';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähle eine andere.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähle eine andere.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Schnellnotiz-Hotkey ist derzeit nicht aktiv. Wähle eine andere Kombination.';

  @override
  String get quickNoteToastSaved => 'Schnellnotiz gespeichert';

  @override
  String get quickNoteToastOpenNote => 'Zur Notiz';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Textbaustein-Auswahl';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Textbaustein-Auswahl öffnen';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Öffnet die Textbaustein-Auswahl sofort — ohne Aufnahme und ohne das gesprochene Trigger-Wort.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Aktueller Hotkey';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähle eine andere.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Hotkey für die Textbaustein-Auswahl ist derzeit nicht aktiv. Wähle eine andere Kombination.';

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
      'Ausklappbares Panel bei Hover am gewählten Bildschirmrand für Transkriptionen, Textbausteine und Zwischenablage-Verlauf';

  @override
  String get settingsSidePanelEdge => 'Panel-Position';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'An welchem Bildschirmrand das Panel andockt und herausgleitet';

  @override
  String get settingsSidePanelEdgeLeft => 'Linker Rand';

  @override
  String get settingsSidePanelEdgeRight => 'Rechter Rand';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsAppearanceSubtitle =>
      'Farben der App-Fenster. Aufnahmeleiste und Overlay bleiben dunkel.';

  @override
  String get settingsAppearanceSystem => 'Wie System';

  @override
  String get settingsAppearanceLight => 'Hell';

  @override
  String get settingsAppearanceDark => 'Dunkel';

  @override
  String get settingsAppearanceNavy => 'Marine';

  @override
  String get settingsAppearanceCardNavy => 'Marine';

  @override
  String get settingsLanguageDialogSubtitle =>
      'Wähle die Sprache, die WhisPaste bei der Aufnahme erwartet. Mit „Automatisch erkennen“ erkennt sie die Sprache selbst.';

  @override
  String get settingsLanguageSearchHint => 'Sprachen suchen';

  @override
  String get settingsLanguageSelectedTitle => 'Ausgewählt';

  @override
  String get settingsLanguageSaveAndClose => 'Speichern und schließen';

  @override
  String get settingsLanguageSavePickOne =>
      'Wähle mindestens eine Sprache, um zu speichern.';

  @override
  String get settingsLanguageNoResults => 'Keine Sprache gefunden';

  @override
  String get settingsLanguageChange => 'Ändern';

  @override
  String get settingsLanguageCancel => 'Abbrechen';

  @override
  String get settingsErrorReporting => 'Fehlerberichte';

  @override
  String get settingsErrorReportingSubtitle =>
      'Sendet Absturz- und Fehlerberichte mit einer anonymen Gerätekennung. Nie dein Audio oder Text.';

  @override
  String get settingsErrorReportingRestartHint =>
      'Wird nach einem Neustart von WhisPaste wirksam.';

  @override
  String get settingsAutoPasteBlocklist => 'Auto-Paste-Sperrliste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Apps, in denen nur kopiert wird (kein Auto-Paste). Ist der Schalter darunter an, landet der Text in der Zwischenablage, sonst nur in den Aufnahmen. Solange eine Liste gesetzt ist, gilt eine nicht erkannte App als gesperrt.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'Bei gesperrten Apps in die Zwischenablage kopieren';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'Aus: Der Text landet nur in den Aufnahmen.';

  @override
  String get settingsAutoPasteBlocklistPlaceholderMac =>
      'com.1password.1password, com.apple.Terminal';

  @override
  String get settingsAutoPasteBlocklistPlaceholderWindows =>
      '1password, windowsterminal';

  @override
  String get settingsAutoPasteBlocklistPlaceholderLinux =>
      '1password, gnome-terminal-server';

  @override
  String get settingsAutoPasteBlocklistShortPrefixWarning =>
      'Auf dem Mac sind Bundle-IDs gemeint, z. B. com.apple.Terminal. Ohne Punkt trifft ein Eintrag nur eine exakt gleiche ID.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'Unter GNOME (Wayland) erkennt WhisPaste die Ziel-App nur mit der WhisPaste-Erweiterung für GNOME – ohne sie wird bei aktiver Sperrliste nur kopiert';

  @override
  String get settingsLinuxAlwaysShiftPaste =>
      'Immer mit Strg+Umschalt+V einfügen';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'Wie in Terminals üblich, auch in allen anderen Apps. Manche Apps belegen die Tasten anders, LibreOffice öffnet damit zum Beispiel „Inhalte einfügen“';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'WhisPaste erkennt hier die Ziel-App und fügt in Terminals von selbst mit Strg+Umschalt+V ein';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'Unter GNOME (Wayland) erkennt WhisPaste Terminals erst mit der WhisPaste-Erweiterung für GNOME. Bis dahin: einschalten, wenn du vor allem in Terminals diktierst';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'Auf diesem Desktop erkennt WhisPaste keine Terminals. Einschalten, wenn du vor allem in Terminals diktierst';

  @override
  String get settingsLinuxPortalInputTitle =>
      'Einfügen über die Desktop-Freigabe';

  @override
  String get settingsLinuxPortalInputBody =>
      'Geht ohne Einrichtung: Dein Desktop fragt einmal, ob WhisPaste Tastenkürzel senden darf. WhisPaste sendet darüber nur Strg+V und Strg+C';

  @override
  String get settingsLinuxPortalInputConnect => 'Freigabe anfragen';

  @override
  String get settingsLinuxPortalInputRevoke => 'Freigabe zurücknehmen';

  @override
  String get settingsLinuxPortalInputConnected =>
      'Freigabe erteilt. WhisPaste kann jetzt darüber einfügen';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'Keine Freigabe erteilt. Du kannst sie jederzeit erneut anfragen';

  @override
  String get settingsLinuxPortalInputFailed =>
      'Die Freigabe hat nicht geklappt. Versuche es später erneut';

  @override
  String get settingsLinuxGnomeExtensionTitle =>
      'WhisPaste-Erweiterung für GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'Unter GNOME erfährt WhisPaste nur mit dieser Erweiterung, welche App aktiv ist, etwa für Terminals und die Sperrliste. Sie liest nur den App-Namen, nie Fenstertitel oder Inhalte';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'Erweiterung einschalten';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'Erweiterung ausschalten';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'Die Erweiterung ist hier nicht installiert. Wie du sie installierst, steht im Handbuch';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'Eingeschaltet. Erkennt WhisPaste die App noch nicht, melde dich einmal ab und wieder an';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'Einschalten hat nicht geklappt. Im Terminal: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'Unter Wayland erkennt WhisPaste die aktive App nicht. Solange eine App gesperrt ist, wird der Text deshalb nur kopiert, nicht eingefügt.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'Unter Wayland kann WhisPaste nicht prüfen, ob du während der Verarbeitung das Fenster gewechselt hast – der Text landet im Fenster, das beim Einfügen aktiv ist';

  @override
  String get settingsPasteBlocklistAdd => 'App hinzufügen';

  @override
  String get settingsPasteBlocklistEmpty =>
      'Keine App gesperrt – Auto-Paste funktioniert überall.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'Von der Sperrliste entfernen: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle =>
      'App zur Sperrliste hinzufügen';

  @override
  String get settingsPasteBlocklistRecentHeading => 'Zuletzt eingefügt in';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'Noch keine Aufnahme mit erkennbarer App. Die App-Kennung unten eintragen.';

  @override
  String get settingsPasteBlocklistManualHeading => 'Kennung manuell eingeben';

  @override
  String get settingsPasteBlocklistManualAdd => 'Hinzufügen';

  @override
  String get historyAutoPasteOffForApp => 'Auto-Paste in dieser App aus';

  @override
  String get settingsPasteClipboardAfter => 'Zwischenablage nach dem Einfügen';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'Ob nach dem Einfügen dein vorheriger Zwischenablage-Inhalt zurückkommt. Blieb das Einfügen unbestätigt (Zeitüberschreitung), bleibt das Transkript immer in der Zwischenablage.';

  @override
  String get settingsPasteClipboardAfterKeep => 'Transkript behalten';

  @override
  String get settingsPasteClipboardAfterRestore => 'Vorherigen Inhalt zurück';

  @override
  String get pasteClipboardUnsavedHint =>
      'Deine vorherige Zwischenablage konnte nicht gesichert werden – macOS hat den Zugriff verweigert. Erlauben unter Systemeinstellungen → Datenschutz & Sicherheit.';

  @override
  String get pasteClipboardUnsavedAction => 'Systemeinstellungen öffnen';

  @override
  String get settingsCheckUpdates => 'Auf Updates prüfen';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Beim Start und alle 24 Stunden nach neuen Versionen suchen';

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
      'Audio und Text bleiben lokal. Anonyme Nutzungsstatistik geht an einen selbst gehosteten Server in der EU, Absturzberichte gehen an einen Dienst in der EU (Sentry) — DSGVO-konform.';

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
  String get onboardingModelTitle => 'Sprachmodell einrichten';

  @override
  String get onboardingModelSubtitle =>
      'Lade das Sprachmodell herunter, um offline aufzunehmen. Deine Stimme verlässt nie dein Gerät.';

  @override
  String get onboardingModelRecommended => 'Empfohlen';

  @override
  String get onboardingModelChangeLater =>
      'Du kannst die Qualität später in den Einstellungen anpassen';

  @override
  String get onboardingModelNextBlocked =>
      'Lade ein Sprachmodell herunter oder nutze einen Cloud-Anbieter mit gespeichertem API-Schlüssel, um fortzufahren.';

  @override
  String get onboardingModelDownloading => 'Wird heruntergeladen…';

  @override
  String get onboardingModelReady => 'Sprachmodell bereit';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Optimierte GPU-Beschleunigung nicht verfügbar, App nutzt CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'Der schnellste Weg zu Text in rund 25 europäischen Sprachen, inklusive Deutsch. Läuft gut auf jeder Hardware, auch ohne GPU.';

  @override
  String get onboardingModelDetectingHardware =>
      'Prüfe deine Hardware für die passende Empfehlung…';

  @override
  String onboardingModelUseCloud(String provider) {
    return '$provider nutzen';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'Für $provider ist schon ein API-Schlüssel gespeichert. Du kannst ihn statt eines lokalen Sprachmodells nutzen.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'Du nutzt $provider für die Spracherkennung. Ein lokales Sprachmodell brauchst du dafür nicht.';
  }

  @override
  String get onboardingModelUseLocal => 'Lokales Sprachmodell nutzen';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

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
      'Drücke die Schaltfläche unten und sprich einen Satz. Der Text landet im Testfeld. Dein Hotkey funktioniert genauso.';

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
  String get onboardingTestRecordingMicBypassConsequence =>
      'Dann bleibt der Hotkey ungetestet, bis du ihn zum ersten Mal benutzt.';

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
  String get onboardingReadyNoModelTitle => 'Ein Sprachmodell fehlt noch';

  @override
  String get onboardingReadyNoModelBody =>
      'Ohne Sprachmodell oder API-Schlüssel kann WhisPaste nichts transkribieren. Lade ein Modell herunter oder hinterlege einen Schlüssel, dann ist alles bereit.';

  @override
  String get onboardingReadyBackToModel => 'Zurück zum Modell';

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
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'Text liegt in der Zwischenablage, drücke $paste zum Einfügen';
  }

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste reicht Kontext aus dem vorigen Aufnahme-Vorgang bis zu zehn Minuten weiter. Bei einem schnellen Wechsel zu einem ganz anderen Thema lohnt eine kurze Pause, sonst kann das nächste Ergebnis inhaltlich verzogen werden.';

  @override
  String get onboardingReadyAutostartToggle =>
      'WhisPaste beim Anmelden starten';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Startet minimiert im Hintergrund, bereit für deinen Hotkey';

  @override
  String get onboardingTriggerTitle => 'Wie möchtest du die Aufnahme starten?';

  @override
  String get onboardingTriggerSubtitle =>
      'Lege deinen Hotkey fest und wähle, wie er eine Aufnahme startet.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Aktueller Hotkey';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Hotkey bereits belegt';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Dein Hotkey ist offenbar von einer anderen App belegt. Nimm unten eine neue Kombination auf.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Gehe mit „Zurück“ zur Hotkey-Seite und nimm dort eine neue Kombination auf.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Hotkey gedrückt halten und sprechen. Loslassen beendet die Aufnahme.';

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
  String get onboardingRevisionNoticeExpand => 'Alle Neuerungen anzeigen';

  @override
  String get onboardingRevisionNoticeCollapse => 'Weniger anzeigen';

  @override
  String get onboardingRevisionExit => 'Einführung verlassen';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Einführung verlassen?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Diesen Update-Durchgang gibt es nur einmal — was du jetzt überspringst, wird nicht für dich eingerichtet. Du kannst dieselben Schritte jederzeit auf der Seite Hilfe unter „Einführung erneut ansehen“ öffnen, und jede Einstellung daraus hat außerdem ihren eigenen Platz in den Einstellungen. Was du bereits eingerichtet hast, bleibt unverändert.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Verlassen';

  @override
  String get overlayRecording => 'Aufnahme läuft';

  @override
  String get overlayTranscribing => 'Wird verarbeitet…';

  @override
  String get overlayRefining => 'Wird bereinigt…';

  @override
  String get overlayStarting => 'Startet…';

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
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey zum Stoppen · $cancelKey zum Abbrechen';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return 'Aufnahme verwerfen? Erneut $cancelKey drücken';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Enter oder $hotkey: nächstes Feld · Esc: Abbrechen';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Enter: nächstes Feld · Esc: Abbrechen';

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
  String get overlayMicSignalLost => 'Kein Mikrofonsignal';

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
  String get trayTranscribeFile => 'Datei transkribieren…';

  @override
  String get trayOpenSidePanel => 'Schnelleinfüge-Panel öffnen';

  @override
  String get traySettings => 'Einstellungen';

  @override
  String get trayQuit => 'Beenden';

  @override
  String get trayRecentRecordings => 'Letzte Aufnahmen';

  @override
  String get trayUnlockRecordings => 'Aufnahmen entsperren…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wörter',
      one: '1 Wort',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'Feedback senden…';

  @override
  String get quitDuringDictationTitle => 'Aufnahme läuft noch';

  @override
  String get quitDuringDictationMessage =>
      'Beim Beenden wird die laufende Aufnahme oder Transkription abgebrochen. Der Text geht dabei verloren.';

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
  String get voiceCorrectionUndone => 'Korrektur rückgängig gemacht';

  @override
  String get voiceNoteEmpty => 'Keine Sprache erkannt';

  @override
  String get voiceNoteError => 'Sprachnotiz fehlgeschlagen';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'Sprachnotiz — sag „tag: …“, um ein Tag hinzuzufügen, oder „korrektur: …“, um dieses Transkript zu ersetzen';

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
  String get updateInstallAfterRecording =>
      'Update wird nach der Aufnahme installiert';

  @override
  String get updateInstallerMissing =>
      'Die Installationsdatei fehlt. Prüfe erneut auf Updates.';

  @override
  String get updateInstallFailed =>
      'Die Installation konnte nicht gestartet werden. Installiere das Update erneut.';

  @override
  String get updateInstallRetry => 'Erneut installieren';

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
  String get settingsOverlayColors => 'Overlay-Farben';

  @override
  String get settingsOverlayBackground => 'Hintergrund für Overlay und Button';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'Gilt für das Aufnahme-Overlay und den schwebenden Button.';

  @override
  String get settingsOverlayBackgroundMarine => 'Marine';

  @override
  String get settingsOverlayBackgroundGraphit => 'Graphit';

  @override
  String get settingsOverlayBackgroundGletscher => 'Gletscher';

  @override
  String get settingsOverlayBackgroundAmber => 'Bernstein';

  @override
  String get settingsOverlayWave => 'Farbe der Welle für Overlay und Button';

  @override
  String get settingsOverlayWaveSubtitle =>
      'Gilt für das Aufnahme-Overlay und den schwebenden Button: Welle und Aufnahmering.';

  @override
  String get settingsOverlayWaveCyan => 'Cyan';

  @override
  String get settingsOverlayWaveViolett => 'Violett';

  @override
  String get settingsOverlayWaveNeutral => 'Neutral';

  @override
  String get settingsOverlayWaveAmber => 'Bernstein';

  @override
  String get settingsOverlayWaveInk => 'Tinte';

  @override
  String get settingsOverlayWaveCoral => 'Koralle';

  @override
  String get settingsOverlayWaveMint => 'Mint';

  @override
  String get settingsOverlayWaveUnavailable =>
      'Auf diesem Hintergrund nicht gut sichtbar';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '„$from“ ist auf diesem Hintergrund nicht gut sichtbar. Die Welle wurde auf „$to“ gewechselt.';
  }

  @override
  String get settingsOverlayLiveTranscript => 'Live-Transkript';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'Zeigt den erkannten Text live während des Sprechens statt nur der Wellenform. Benötigt zusätzliche Rechenleistung während der Aufnahme';

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
  String get buttonContextShowHistory => 'Aufnahmen anzeigen';

  @override
  String get buttonContextSettings => 'Einstellungen';

  @override
  String get buttonContextQuit => 'WhisPaste beenden';

  @override
  String get settingsHistory => 'Aufnahmen';

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
  String get settingsHistoryHideOnOpen => 'Aufnahmen beim Öffnen verbergen';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Zeigt statt deiner Transkriptionen einen „Aufnahmen anzeigen“-Button, sobald WhisPaste startet oder das Fenster wieder geöffnet wird. Es wird nichts gelöscht.';

  @override
  String get historyPinGateTitle => 'Aufnahmen sind gesperrt';

  @override
  String get historyPinGateHint =>
      'Gib deine PIN ein, um deine Transkriptionen anzuzeigen.';

  @override
  String get historyImportUnlockHint =>
      'Entsperre die Aufnahmen, um die Datei zu transkribieren.';

  @override
  String get historyPinUnlock => 'Entsperren';

  @override
  String get historyPinDialogTitle => 'PIN eingeben';

  @override
  String get historyPinDialogSubtitle =>
      'Deine Aufnahmen sind mit einer PIN geschützt.';

  @override
  String get historyPinFieldHint => 'PIN';

  @override
  String get historyPinRepeatHint => 'PIN wiederholen';

  @override
  String get historyPinWrong => 'Falsche PIN.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'Zu viele Versuche. Erneut in $seconds s.';
  }

  @override
  String get historyPinForgot => 'PIN vergessen?';

  @override
  String get historyPinForgotHint =>
      'Das Zurücksetzen löscht sofort alle Aufnahmen, gespeicherten Audiodateien, Notizen mit Versionen und Notizbilder. Kann eine Datei nicht gelöscht werden, zeigt WhisPaste einen Hinweis.';

  @override
  String get historyPinForgotConfirmTitle =>
      'Aufnahmen und Notizen löschen und PIN entfernen?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Eine vergessene PIN lässt sich nicht wiederherstellen. Zum Zurücksetzen werden sofort und endgültig gelöscht: alle Aufnahmen und gespeicherten Audiodateien (auch Archiv und Papierkorb), alle Notizen mit ihren Versionen (auch Papierkorb) und alle Notizbilder. Einstellungen, Textbausteine und Ersetzungen bleiben erhalten. Kann eine Datei nicht gelöscht werden, zeigt WhisPaste einen Hinweis.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'Einige Aufnahmen, Importe oder Notizbilder konnten nicht gelöscht werden. WhisPaste entfernt sie beim nächsten Start.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'Einige Aufnahmen oder Importe ließen sich nicht löschen, und WhisPaste kann die Löschung nicht später nachholen. Bitte lösche sie von Hand. Ort: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'Eine Kopie der alten Datenbank ($path) ließ sich nicht löschen. Bitte lösche sie von Hand.';
  }

  @override
  String get historyPinForgotConfirmAction => 'Löschen';

  @override
  String get historyPinSetTitle => 'PIN festlegen';

  @override
  String get historyPinSetSubtitle =>
      '4–8 Ziffern. Hält andere davon ab, deine Transkriptionen an diesem Computer einfach einzusehen – verschlüsselt sie aber nicht.';

  @override
  String get historyPinInvalid => 'Verwende 4 bis 8 Ziffern.';

  @override
  String get historyPinMismatch => 'Die PINs stimmen nicht überein.';

  @override
  String get settingsHistoryPin => 'PIN-Schutz';

  @override
  String get settingsHistoryPinSubtitle =>
      'Verlangt eine PIN, um Aufnahmen und Notizen anzuzeigen – auch in Seitenleiste, Menü des schwebenden Buttons und Automatisierungs-API.';

  @override
  String get settingsHistoryPinChange => 'Ändern';

  @override
  String get settingsHistoryPinRemove => 'Entfernen';

  @override
  String get settingsHistoryAutoLock => 'Automatisch sperren';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Blendet die Aufnahmen nach dieser Zeit ohne Aktivität wieder aus.';

  @override
  String get settingsHistoryAutoLockNever => 'Nie';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Nach $minutes Min.';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'Schalte den schwebenden Button ein, um das anzupassen.';

  @override
  String get settingsFloatingButtonSection => 'Schwebender Button';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Immer sichtbarer Aufnahme-Button für schnellen Zugriff';

  @override
  String get settingsFloatingButtonWaylandTitle => 'Wayland-Grenzen';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'Unter Wayland entscheidet der Desktop, wo der Button liegt und ob er immer oben bleibt. WhisPaste kann beides dort nur eingeschränkt zusichern. Aufnahme per Klick funktioniert trotzdem, und der Button nimmt dir nicht den Tastaturfokus.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'Auf diesem Linux-Desktop nicht verfügbar: Der Button braucht X11 oder XWayland. Ausschalten bleibt möglich.';

  @override
  String get settingsSttIdleTimeout => 'Sprachmodell-Leerlauf';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Wie lange das Sprachmodell nach Nutzung geladen bleibt';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Dauerhaft aktiv';

  @override
  String get settingsSttKeepLoaded => 'Modell geladen halten';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'Ein geladenes Modell startet Aufnahmen ohne Wartezeit. Solange es geladen ist, belegt es Arbeitsspeicher.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'Im geladenen Zustand braucht das Modell etwa $size Arbeitsspeicher.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'Der Grafikspeicher ($vramMb MB) reicht für dieses Modell nicht ($requiredMb MB). Es läuft auf dem Prozessor.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'Immer';

  @override
  String get settingsSttKeepLoadedAutomatic => 'Automatisch';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'Nach Leerlauf';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'Entladen nach';

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
  String get reviewPromptStarGitHub => 'Auf GitHub einen Stern geben';

  @override
  String get reviewPromptRateStore => 'Im Store bewerten';

  @override
  String get reviewSupportEntry => 'WhisPaste bewerten & unterstützen';

  @override
  String get reviewSupportLabel => 'App bewerten';

  @override
  String get reviewSupportAction => 'Bewerten';

  @override
  String get reviewSupportGitHubLabel => 'Auf GitHub mit Stern unterstützen';

  @override
  String get reviewSupportGitHubAction => 'Auf GitHub ansehen';

  @override
  String get githubInviteTitle => 'WhisPaste ist Open Source';

  @override
  String get githubInviteBody =>
      'Ein Stern auf GitHub hilft anderen, es zu finden.';

  @override
  String get githubInviteOpen => 'Auf GitHub ansehen';

  @override
  String get githubInviteLater => 'Später';

  @override
  String get githubInviteNever => 'Nicht mehr fragen';

  @override
  String get ideasBoardLabel => 'Ideen & Featurewünsche';

  @override
  String get ideasBoardAction => 'Board ansehen';

  @override
  String get feedbackIdeasLink => 'Ideen vorschlagen & abstimmen';

  @override
  String get feedbackTypeProblem => 'Problem';

  @override
  String get feedbackTypeIdea => 'Idee';

  @override
  String get feedbackTypePraise => 'Lob';

  @override
  String get feedbackTypeQuestion => 'Frage';

  @override
  String get feedbackPromptProblem =>
      'Was ist schiefgelaufen? Sag uns, was du gemacht hast und was passiert ist.';

  @override
  String get feedbackPromptIdea =>
      'Was würde WhisPaste für dich besser machen?';

  @override
  String get feedbackPromptPraise => 'Was funktioniert bei dir gut?';

  @override
  String get feedbackPromptQuestion => 'Was möchtest du wissen?';

  @override
  String get feedbackDiagnosticsLabel => 'Diagnose anhängen';

  @override
  String get feedbackDiagnosticsExplanation =>
      'Hängt App-Version, Betriebssystem, Spracherkennung und Backend an. Aufnahmen und Texte werden nie angehängt.';

  @override
  String get feedbackDiagnosticsPreview => 'Vorschau anzeigen';

  @override
  String get feedbackDiagnosticsPreviewHide => 'Vorschau ausblenden';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'Dieser genaue Text wird deiner Nachricht angehängt:';

  @override
  String get feedbackIdeaBoardHint =>
      'Du kannst deine Idee auch auf dem öffentlichen Ideenboard einreichen und über andere abstimmen.';

  @override
  String get feedbackTextTooLong =>
      'Der Text ist zu lang für den Diagnose-Anhang. Kürze ihn etwas.';

  @override
  String get hotkeyRegistrationFailed =>
      'Hotkey-Registrierung fehlgeschlagen, bitte Tastenkombination in den Einstellungen neu belegen.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken ist von einer anderen App belegt. Bis du eine andere Kombination wählst, startet $active die Aufnahme.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'Der Hotkey für $action ist von einer anderen App belegt. Er bleibt aus, bis du in den Einstellungen eine freie Kombination wählst.';
  }

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
      'Sprachmodell kann nicht starten. Bitte App neu starten oder Sprachmodell neu laden.';

  @override
  String get recoveryExhaustedAction => 'Einstellungen öffnen';

  @override
  String get recoveryVcRuntimeToast =>
      'Sprachmodell kann nicht starten: eine Windows-Komponente fehlt (Microsoft Visual C++). Bitte installiere das Visual C++ Redistributable (x64) und starte WhisPaste neu.';

  @override
  String get recoveryVcRuntimeAction => 'Installieren';

  @override
  String get modelAbiInfoToast => 'Lade Sprachmodell neu, bitte warten.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste läuft jetzt ohne Grafikkarten-Beschleunigung, weil es beim letzten Start ein Problem gab. Aufnehmen funktioniert unverändert.';

  @override
  String get serverDownloadFailedToast =>
      'Sprachmodell konnte nicht heruntergeladen werden. Internetverbindung prüfen?';

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
      'Automatisch nutzt die Grafikkarte, wenn sie verfügbar ist. „Nur CPU“ ist langsamer, funktioniert aber auf jedem Gerät. „GPU (erzwingen)“ nur wählen, wenn die Automatik nicht funktioniert.';

  @override
  String get settingsGpuAccelerationAuto => 'Automatisch (empfohlen)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (erzwingen)';

  @override
  String get settingsGpuAccelerationDisabled => 'Nur CPU';

  @override
  String get settingsSttEngine => 'Sprachmodell';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 Sprachen. Parakeet: schneller, rund 25 Sprachen.';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet';

  @override
  String get settingsSttEngineRecommended => 'Empfohlen';

  @override
  String get parakeetModelTitle => 'Parakeet-Modell';

  @override
  String parakeetModelSubtitle(String size) {
    return 'Einmaliger Download ($size), läuft danach vollständig offline';
  }

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
      'Anonyme Nutzungszahlen, ohne Cookies und ohne Verknüpfung mit dir. Hilft uns zu verstehen, welche Funktionen genutzt werden. Dein Text und Audio sind nie enthalten.';

  @override
  String get settingsRetainRecentAudio =>
      'Audio der letzten Aufnahmen aufbewahren';

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'Audio der letzten $count Aufnahmen lokal aufbewahren, zum Debuggen oder um ein früheres Transkript wiederherzustellen; Aufnahmen und importierte Dateien werden spätestens nach $days Tagen automatisch gelöscht';
  }

  @override
  String get pendingAudioRetentionNote =>
      'Schlägt eine Transkription fehl, bleibt das Audio bis zu 24 Stunden erhalten, damit du sie erneut versuchen kannst. Das gilt auch, wenn diese Option aus ist.';

  @override
  String get pendingAudioSectionTitle => 'Aufnahmen für einen erneuten Versuch';

  @override
  String get pendingAudioSectionBody =>
      'Diese Aufnahmen konnten nicht transkribiert werden, etwa weil die Verbindung abbrach. Das Audio wird spätestens nach 24 Stunden gelöscht oder wenn du es verwirfst.';

  @override
  String get pendingAudioEmpty => 'Keine Aufnahmen warten auf einen Versuch.';

  @override
  String get featureSpotlightHeading => 'Neu in WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Verstanden';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Textbaustein-Auswahl';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Speichere wiederverwendbare Textbausteine und füge sie per Hotkey oder gesprochenem Trigger überall ein – ganz ohne erneutes Tippen.';

  @override
  String get featureSpotlightSidePanelTitle => 'Zwischenablage-Seitenleiste';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Fahre an den Bildschirmrand, um deinen letzten Zwischenablage-Verlauf zu öffnen, und ziehe jeden Eintrag direkt in dein Dokument.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle =>
      'Interaktive Textbausteine';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'Textbausteine mit Lücken: WhisPaste führt dich durch jedes Feld – sprechen, mit Enter zum nächsten, und der fertige Text wird in einem Stück eingefügt.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Bereinige, kürze oder übersetze deinen Text vor dem Einfügen – komplett lokal auf deinem Gerät, mit eigenem Hotkey, Preset und eigener Zielsprache.';

  @override
  String get featureSpotlightHistoryPinTitle => 'Aufnahmen mit PIN schützen';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'Schütze deine Transkriptionen mit einer PIN – auch in der Seitenleiste und im Menü des schwebenden Buttons –, auf Wunsch mit automatischer Sperre nach Inaktivität. Einstellungen → Aufnahmen.';

  @override
  String get featureSpotlightEditSelectionTitle =>
      'Markierten Text per Stimme bearbeiten';

  @override
  String get featureSpotlightEditSelectionDescription =>
      'Markiere Text in einer beliebigen App, drücke den Hotkey „Auswahl bearbeiten“ und sag, was sich ändern soll – oder einfach „kürzer“, „verbessern“ oder „übersetzen“. Nutzt das Textmodell von Smart Mode. Standardmäßig aus: einschalten unter Einstellungen → Smart Mode.';

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
      'Lege eine Notiz an, um Text von überall zu sammeln.';

  @override
  String get notesUntitled => 'Notiz ohne Titel';

  @override
  String get notesEditorPlaceholder => 'Lege los…';

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
    return 'Keine Notizen stimmen mit „$query“ überein.\nVersuche einen anderen Suchbegriff.';
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
  String get sidePanelSnippetsTitle => 'Textbausteine';

  @override
  String get sidePanelClipboardHistoryTitle => 'Zwischenablage-Verlauf';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Noch nichts kopiert';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Alles, was du kopierst während WhisPaste läuft, erscheint hier — wird beim Neustart der App gelöscht.';

  @override
  String get sidePanelClipboardLockedTitle => 'Mit PIN gesperrt';

  @override
  String get sidePanelClipboardLockedHint =>
      'Kopierter Text bleibt verborgen, solange die Aufnahmen mit PIN gesperrt sind. Mit der PIN entsperren, um ihn wieder zu sehen.';

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

  @override
  String get sidePanelLoadFailedHint =>
      'Schließe das Panel und öffne es erneut, um es noch einmal zu versuchen.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Lokale Textbereinigung, Kürzung und Übersetzung nach dem Aufnehmen';

  @override
  String get smartModeStandardPreset => 'Standard-Preset';

  @override
  String get smartModePresetOff => 'Aus';

  @override
  String get smartModePresetOffDescription =>
      'Keine automatische Nachbearbeitung — der erkannte Text wird genau so übernommen, wie er erkannt wurde.';

  @override
  String get smartModePresetCleanup => 'Bereinigen';

  @override
  String get smartModePresetCleanupDescription =>
      'Entfernt Füllwörter wie „äh“ und korrigiert Zeichensetzung und Groß-/Kleinschreibung, ohne Wortlaut, Bedeutung oder Sprache zu verändern.';

  @override
  String get smartModePresetConcise => 'Kürzen';

  @override
  String get smartModePresetConciseDescription =>
      'Kürzt den Text, indem Wiederholungen und Füllwörter entfernt werden — alle wichtigen Fakten und die Sprache bleiben erhalten.';

  @override
  String get smartModePresetTranslate => 'Übersetzen';

  @override
  String get smartModePresetTranslateDescription =>
      'Übersetzt den erkannten Text in die unten eingestellte Zielsprache.';

  @override
  String get smartModeTargetLanguage => 'Zielsprache';

  @override
  String get smartModeTargetLanguageGerman => 'Deutsch';

  @override
  String get smartModeTargetLanguageEnglish => 'Englisch';

  @override
  String get smartModeTargetLanguageSpanish => 'Spanisch';

  @override
  String get smartModeTargetLanguageFrench => 'Französisch';

  @override
  String get smartModeTargetLanguagePortuguese => 'Portugiesisch';

  @override
  String get smartModeTargetLanguageMandarin => 'Mandarin';

  @override
  String get smartModeTargetLanguageRussian => 'Russisch';

  @override
  String get smartModeDownload => 'Herunterladen';

  @override
  String get smartModeDownloadComplete => 'Textmodell einsatzbereit';

  @override
  String get smartModeRamWarningTitle => 'Wenig Arbeitsspeicher erkannt';

  @override
  String get smartModeRamWarningBody =>
      'Das lokale Textmodell läuft am besten mit mindestens 8 GB RAM. Es kann auch mit weniger funktionieren, aber langsamer sein oder fehlschlagen. Trotzdem herunterladen?';

  @override
  String get smartModeRamWarningContinue => 'Trotzdem herunterladen';

  @override
  String get smartModeRamWarningCancel => 'Abbrechen';

  @override
  String get smartModeModelDeleteConfirm => 'Textmodell löschen?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'Die Datei des Textmodells wird von diesem Gerät gelöscht. Du kannst sie jederzeit erneut herunterladen.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Läuft vollständig auf dem Gerät. Im aktiven Zustand belegt das Textmodell zusätzlich zum Speicherplatz etwa 4–5 GB RAM. Den Arbeitsspeicher teilt es sich mit dem Sprachmodell, der Gesamtverbrauch hängt also auch davon ab, welches Sprachmodell geladen ist.';

  @override
  String get smartModeFactGuardHint =>
      'Der Fakten-Wächter prüft Zahlen, Daten, Links, E-Mail-Adressen und IBAN. Namen aus dem Wörterbuch bleiben erhalten. Freie Anweisungen können Namen ändern, die nicht im Wörterbuch stehen – trag sie ins Wörterbuch ein, wenn sie erhalten bleiben sollen.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Beispiel: Eine typische Aufnahme mit 50 Wörtern braucht je nach Hardware etwa 1–6 Sekunden zur Verarbeitung.';

  @override
  String get smartModeLocalUnavailable =>
      'Der lokale Smart Mode ist in diesem Build nicht enthalten. Wechsle zu OpenAI oder installiere ein offizielles WhisPaste-Release.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Aufnahme mit Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Startet eine Aufnahme mit einem festen Preset, unabhängig vom Standard-Preset in Smart Mode. „Gedrückt halten für Aufnahme“ gilt auch hier.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Preset';

  @override
  String get settingsSmartModeCurrentHotkey => 'Aktueller Hotkey';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Diese Kombination ist schon für „$action“ vergeben. Wähle eine andere.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Smart-Mode-Hotkey ist derzeit nicht aktiv. Wähle eine andere Kombination.';

  @override
  String get smartModeOnboardingHintTitle => 'Smart Mode ausprobieren';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'Smart Mode kann deinen Text automatisch bereinigen, kürzen oder übersetzen — komplett lokal auf deinem Gerät. Das lokale Textmodell braucht $size Speicherplatz. Lade es jetzt herunter oder richte es später in den Einstellungen ein.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Rohtext';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'also äh das kundenmeeting wurde auf donnerstag um drei uhr verschoben und wir brauchen noch die aktualisierten folien vom marketing';

  @override
  String get smartModeOnboardingHintExampleAfterLabel => 'Smart-Mode-Ergebnis';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'Also, das Kundenmeeting wurde auf Donnerstag um drei Uhr verschoben, und wir brauchen noch die aktualisierten Folien vom Marketing.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Herunterladen';

  @override
  String get smartModeOnboardingHintSkipCta => 'Später';

  @override
  String get smartModeUsageHintTitle =>
      'Smart Mode bei deiner nächsten Aufnahme ausprobieren';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode kann Text wie diesen automatisch bereinigen, kürzen oder übersetzen — direkt auf deinem Gerät. Das hast du gerade gesagt:';

  @override
  String get smartModeUsageHintCta => 'Einrichten';

  @override
  String get smartModeUsageHintDismiss => 'Nicht jetzt';

  @override
  String get settingsAutomationApi => 'Lokale Automatisierungs-API';

  @override
  String get settingsAutomationApiSubtitle =>
      'Andere Programme und Skripte auf diesem Computer können WhisPaste steuern, zum Beispiel eine Aufnahme starten. Geräte im Netzwerk können sie nicht erreichen.';

  @override
  String get settingsAutomationApiEnable =>
      'Lokale Automatisierungs-API aktivieren';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'Bindet nur an 127.0.0.1/::1 — aus dem Netzwerk nie erreichbar';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'Aktiv auf Port $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'Aktiv auf Port $port (Port $requestedPort war belegt)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'Nicht aktiv';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'Kein freier Port im Bereich $start–$end gefunden';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'Benutzerdefinierter Port';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'Leer lassen für automatische Portwahl — weicht bei Belegung automatisch aus';

  @override
  String get settingsAutomationApiCustomPortHint => 'Automatisch';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'Bitte einen Port zwischen 1024 und 65535 eingeben';

  @override
  String get settingsAutomationApiToken => 'Bearer-Token';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'Als „Authorization: Bearer <token>“ senden — jede Anfrage ohne gültigen Token wird abgelehnt';

  @override
  String get settingsAutomationApiRegenerate => 'Neu erzeugen';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle =>
      'Token neu erzeugen?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'Der aktuelle Token funktioniert danach sofort nicht mehr. Skripte, die ihn nutzen, brauchen den neuen.';

  @override
  String get settingsAutomationApiCopyToken => 'Token kopieren';

  @override
  String get settingsAutomationApiTokenCopied =>
      'Token in die Zwischenablage kopiert';

  @override
  String get settingsAutomationApiDocumentation => 'Dokumentation';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'Endpunkt-Referenz und curl-Beispiele';

  @override
  String get settingsAutomationApiDocumentationAction => 'Öffnen';

  @override
  String historyCharacterCount(int count) {
    return '$count Zeichen';
  }

  @override
  String historyPastedInto(String app) {
    return 'Eingefügt in $app';
  }

  @override
  String get historyShowOriginalTranscript => 'Original-Transkript anzeigen';

  @override
  String get historyHideOriginalTranscript => 'Original-Transkript ausblenden';

  @override
  String get historyOriginalTranscriptLabel => 'Original-Transkript';

  @override
  String get settingsHotkeyActionSelectionEdit => 'Auswahl bearbeiten';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'Auswahl bearbeiten';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Text in einer beliebigen App markieren, diesen Hotkey drücken und sagen, was sich ändern soll — oder einfach „kürzer“, „verbessern“ oder „übersetzen“. Das Ergebnis ersetzt die Auswahl; Rückgängig in der App holt das Original zurück. Nutzt das Textmodell, das in Smart Mode eingerichtet ist.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'Diese Kombination ließ sich nicht registrieren — der Hotkey „Auswahl bearbeiten“ ist derzeit nicht aktiv. Wähle eine andere Kombination.';

  @override
  String get overlayTargetSelectionEdit => 'Auswahl';

  @override
  String get overlayRecordingSelectionEdit => 'Sag, was sich ändern soll';

  @override
  String get overlaySelectionEditHint =>
      'Sag, was sich ändern soll — oder: kürzer · verbessern · übersetzen';

  @override
  String get overlayEditingSelection => 'Bearbeite Auswahl…';

  @override
  String get overlayDoneSelectionEdit => 'Auswahl ersetzt';

  @override
  String get errorSelectionEditNoSelection =>
      'Kein Text markiert — erst Text markieren, dann den Hotkey drücken';

  @override
  String get errorSelectionEditNoEngine =>
      'Richte zuerst Smart Mode ein (lokales Textmodell laden oder OpenAI-Schlüssel hinterlegen), um Auswahlen zu bearbeiten';

  @override
  String get errorSelectionEditUnsupported =>
      'Auswahl bearbeiten braucht Auto-Paste, das in diesem Build nicht verfügbar ist';

  @override
  String get errorSelectionEditCopyFailed =>
      'Auswahl konnte nicht gelesen werden — prüfe die Berechtigung für Auto-Paste';

  @override
  String get errorSelectionEditFailed =>
      'Bearbeiten fehlgeschlagen — dein Text bleibt unverändert';

  @override
  String get errorSelectionEditFactsChanged =>
      'Die Bearbeitung würde Fakten ändern, die deine Anweisung nicht nennt — dein Text bleibt unverändert';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'Der Wert „$value“ würde sich ändern, ohne dass du ihn nennst. Nenne alten und neuen Wert, z. B. „ändere 3 zu 5“ — dein Text bleibt unverändert';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'Auswahl konnte nicht ersetzt werden — dein Text bleibt unverändert';

  @override
  String get settingsCudaPackTitle => 'NVIDIA-CUDA-Beschleunigung';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Schnellere Transkription auf GeForce-RTX- und GTX-16-Karten. Einmaliger Download, $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Installiert. Ist der Grafiktreiber zu alt, nutzt WhisPaste weiter Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'Zustimmung erforderlich';

  @override
  String get settingsCudaPackConsentReview => 'Lizenz prüfen';

  @override
  String get settingsCudaPackDownload => 'Herunterladen';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'Wird geladen: $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'Wird installiert …';

  @override
  String get settingsCudaPackCancel => 'Download abbrechen';

  @override
  String get settingsCudaPackRemove => 'CUDA-Paket entfernen';

  @override
  String get settingsCudaPackRemoveConfirm => 'CUDA-Paket entfernen?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'Das CUDA-Paket wird von diesem Gerät entfernt. Du kannst es jederzeit erneut herunterladen.';

  @override
  String get settingsCudaPackToggle => 'CUDA verwenden';

  @override
  String get settingsCudaPackErrorNetwork =>
      'Download fehlgeschlagen. Prüfe die Verbindung und versuche es erneut.';

  @override
  String get settingsCudaPackErrorVerification =>
      'Der Download war beschädigt. Bitte erneut versuchen.';

  @override
  String get settingsCudaPackErrorStorage =>
      'Das Paket konnte nicht gespeichert werden. Prüfe den freien Speicherplatz.';

  @override
  String get cudaEulaDialogTitle => 'NVIDIA-CUDA-Lizenz';

  @override
  String cudaEulaDialogBody(String version) {
    return 'Das CUDA-Paket enthält NVIDIA-Komponenten unter der NVIDIA-CUDA-Endbenutzer-Lizenzvereinbarung ($version). Zugestimmt wird dem Volltext dieser Fassung, den du über „Volltext anzeigen“ lesen kannst. Eine weitere Fassung bei NVIDIA kann davon abweichen. Zum Herunterladen musst du zustimmen.';
  }

  @override
  String get cudaEulaDialogLink => 'Weitere Fassung bei NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'Volltext anzeigen';

  @override
  String get cudaEulaFullTextClose => 'Schließen';

  @override
  String get cudaEulaDialogCancel => 'Abbrechen';

  @override
  String get cudaEulaDialogAccept => 'Zustimmen und herunterladen';

  @override
  String get recoveryCudaDisabledToast =>
      'Die CUDA-Beschleunigung wurde ausgeschaltet, weil es beim letzten Start ein Problem gab. WhisPaste nutzt jetzt Vulkan, Aufnehmen funktioniert unverändert.';

  @override
  String get supportPromptSnooze => '90 Tage nicht fragen';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'Danke, dass du WhisPaste im Store gekauft hast. Weitere Unterstützung ist freiwillig.';

  @override
  String get supportShareText =>
      'Mit WhisPaste spreche ich Text direkt in meine Apps. Lokal auf meinem Rechner und Open Source:';

  @override
  String get supportPageTitle => 'WhisPaste unterstützen';

  @override
  String get supportIntroDirect =>
      'WhisPaste ist kostenlos und Open Source. Mit einem Beitrag oder einer Empfehlung hilfst du dem Projekt.';

  @override
  String get supportCostsNote =>
      'Beiträge helfen, Entwicklung und laufende Kosten für Veröffentlichung, Hosting und Domain zu tragen.';

  @override
  String get supportSectionOnce => 'Einmalig unterstützen';

  @override
  String get supportSectionOthers => 'Weitere Wege';

  @override
  String get supportSectionReach => 'Weiterempfehlen';

  @override
  String get supportStoreTitleWindows => 'WhisPaste im Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste im Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'Installation und Updates laufen über den Store.';

  @override
  String get supportStoreFactPurchase =>
      'Dein einmaliger Kauf unterstützt WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'Gleiche Funktionen. Die direkte Version bleibt kostenlos nutzbar.';

  @override
  String get supportStoreCtaWindows => 'Im Microsoft Store ansehen';

  @override
  String get supportStoreCtaMac => 'Im Mac App Store ansehen';

  @override
  String get supportStorePriceNote => 'Preis im Store';

  @override
  String get supportStoreCoffeeNote =>
      'Einmalig ungefähr ein Kaffee. Den aktuellen Preis zeigt der Store.';

  @override
  String get supportStoreDismiss => 'Store-Hinweis ausblenden';

  @override
  String get supportStoreShowAgain => 'Store-Option anzeigen';

  @override
  String get supportSponsorsCta => 'GitHub Sponsors öffnen';

  @override
  String get supportSponsorsNote =>
      'Monatlich oder mit einem Betrag deiner Wahl. Betrag und Rhythmus wählst du dort.';

  @override
  String get supportKofiCta => 'Ko-fi öffnen';

  @override
  String get supportPayPalCta => 'Mit PayPal unterstützen';

  @override
  String get supportNativeTitle => 'Einmalig im Store unterstützen';

  @override
  String get supportNativeDescription =>
      'Ein einmaliger Betrag, den der Store abrechnet. Gleiche Funktionen, kein Abo.';

  @override
  String get supportNativeCta => 'Einmalig unterstützen';

  @override
  String get supportSheetChoose => 'Wähle einen Betrag';

  @override
  String get supportSheetLoading => 'Beträge werden geladen …';

  @override
  String supportSheetBuy(String price) {
    return 'Für $price unterstützen';
  }

  @override
  String get supportSheetPurchasing => 'Der Store bestätigt deinen Kauf …';

  @override
  String get supportSheetThanks => 'Danke für deine Unterstützung!';

  @override
  String get supportSheetThanksDetail =>
      'Dein Unterstützer-Badge ist jetzt aktiv. Alle Funktionen bleiben für alle verfügbar.';

  @override
  String get supportSheetPending => 'Dein Kauf wartet auf Bestätigung.';

  @override
  String get supportSheetPurchaseError =>
      'Der Kauf konnte nicht abgeschlossen werden. Versuche es später erneut.';

  @override
  String get supportSheetPricesError =>
      'Die Beträge konnten nicht geladen werden. Versuche es später erneut.';

  @override
  String get supportSheetUnavailable =>
      'Im Store sind gerade keine Beträge verfügbar.';

  @override
  String get supportSheetRetry => 'Erneut versuchen';

  @override
  String get supportSheetClose => 'Schließen';

  @override
  String get supportSelfDeclareCta => 'Ich unterstütze WhisPaste bereits';

  @override
  String get supportSelfDeclareNote =>
      'Nur ein Hinweis auf diesem Gerät, nichts wird geprüft. Der Sponsor-Button in der Statusleiste wird ausgeblendet.';

  @override
  String get supportSelfDeclareHint =>
      'Nichts wird geprüft. Nutze das, wenn du bereits beigetragen hast.';

  @override
  String get supportSupporterLine => 'Du unterstützt WhisPaste. Danke!';

  @override
  String get supportSupporterBadge => 'Unterstützer';

  @override
  String get supportRateCta => 'Im Store bewerten';

  @override
  String get supportShareCopy => 'Link kopieren';

  @override
  String get supportShareCopied => 'Link kopiert';

  @override
  String get externalLinkOpenFailed => 'Link konnte nicht geöffnet werden';

  @override
  String get externalLinkCopyAddress => 'Adresse kopieren';

  @override
  String get supportShareEmail => 'E-Mail';

  @override
  String get supportChipLabel => 'Sponsor';

  @override
  String get supportChipTooltip => 'WhisPaste unterstützen';

  @override
  String get supportChipThanksLabel => 'Danke';

  @override
  String get supportChipThanksTooltip => 'Danke für deine Unterstützung';

  @override
  String get settingsSponsorChip => 'Sponsor-Button in der Statusleiste';

  @override
  String get settingsSponsorChipSubtitle =>
      'Zeigt den Weg zum Unterstützen-Bereich. Du kannst ihn jederzeit ausblenden und hier wieder einblenden.';

  @override
  String get automationPreviewTitle => 'Mehrzeiligen Text einfügen?';

  @override
  String get automationPreviewBody =>
      'Die Automatisierung möchte Text mit Zeilenumbrüchen einfügen. Prüfe ihn, bevor er in die aktive App gelangt.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen',
      one: '1 Zeile',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'Einfügen';

  @override
  String get automationPreviewCancel => 'Abbrechen';

  @override
  String get automationIntegrationsHeading => 'Integrationen';

  @override
  String get automationIntegrationsHooksTitle =>
      'Ereignisse an andere Apps senden';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'Sendet fertige Transkripte und geänderte Notizen an eine App auf diesem Rechner. Hooks feuern auch dann, wenn der API-Server ausgeschaltet ist.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hooks',
      one: '1 Hook',
      zero: 'Keine Hooks',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'Verwalten';

  @override
  String get automationIntegrationsCliTitle => 'Kommandozeile und MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'Nur aus dem Quellcode. Starte $path mit gesetztem $token; der Befehl $command startet den MCP-Server.';
  }

  @override
  String get automationHooksIntro =>
      'Fertige Texte oder geänderte Notizen gehen an eine App auf diesem Computer. Die Adresse muss auf diesem Gerät liegen.';

  @override
  String get automationHooksEmpty => 'Noch keine Verbindung eingerichtet.';

  @override
  String get automationHooksUrlLabel => 'Zieladresse (nur dieser Computer)';

  @override
  String get automationHooksEventsLabel => 'Ereignisse';

  @override
  String get automationHooksEventTranscript => 'Transkript fertig';

  @override
  String get automationHooksEventNote => 'Notiz geändert';

  @override
  String get automationHooksAdd => 'Hook hinzufügen';

  @override
  String get automationHooksRemove => 'Hook entfernen';

  @override
  String get automationHooksRemoveConfirm => 'Diesen Hook entfernen?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'Der Hook wird aus der Liste entfernt. Du kannst ihn später wieder hinzufügen.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'Verwende $ipv4, $ipv6 oder $localhost mit Port, zum Beispiel $example.';
  }

  @override
  String get automationHooksNoEvents => 'Wähle mindestens ein Ereignis.';

  @override
  String automationHooksTooMany(int max) {
    return 'Du kannst bis zu $max Hooks hinzufügen.';
  }

  @override
  String get automationHooksDone => 'Fertig';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'Diktieren';

  @override
  String get dockOverflow => 'Mehr';

  @override
  String get dockMenuGroupStatus => 'Status';

  @override
  String get dockMenuGroupNotices => 'Hinweise';

  @override
  String get dockMenuHotkeyChange => 'Tastenkürzel ändern…';

  @override
  String get dockMenuSmartModeSettings => 'Smart-Mode-Einstellungen…';

  @override
  String get dockMenuSttModels => 'Sprachmodelle verwalten…';

  @override
  String get dockMenuGroupCloud => 'Cloud';

  @override
  String get dockMenuModelDownload => 'Laden';

  @override
  String get dockMenuModelLoading => 'wird geladen';

  @override
  String get dockMenuSttLockedReason => 'Während einer Aufnahme nicht änderbar';

  @override
  String get dockMenuSearchHint => 'Suchen…';

  @override
  String get dockMenuSearchNoMatches => 'Keine Treffer';

  @override
  String get dockMenuAppliesNextRecording => 'Gilt ab der nächsten Aufnahme';

  @override
  String get dockStopDictation => 'Aufnahme beenden';

  @override
  String get historyImportAddFiles => 'Dateien hinzufügen';

  @override
  String historyImportDescription(String formats) {
    return 'Audiodateien ($formats) auf diesem Gerät transkribieren. Dateien auf diese Seite ziehen oder hinzufügen.';
  }

  @override
  String get historyImportQueueTitle => 'Importwarteschlange';

  @override
  String get historyImportStatusQueued => 'Wartet';

  @override
  String get historyImportStatusCopying => 'Wird kopiert';

  @override
  String get historyImportStatusDecoding => 'Wird dekodiert';

  @override
  String get historyImportStatusTranscribing => 'Wird transkribiert';

  @override
  String get historyImportStatusDone => 'Fertig';

  @override
  String get historyImportStatusFailed => 'Fehlgeschlagen';

  @override
  String get historyImportStatusCancelled => 'Abgebrochen';

  @override
  String get historyImportFailureCopy =>
      'Die Datei konnte nicht kopiert werden. Prüfe, ob sie noch vorhanden und lesbar ist, und versuche es erneut.';

  @override
  String get historyImportFailureUnsupported =>
      'Dieses Format wird auf dieser Plattform nicht unterstützt. Bitte in WAV umwandeln und erneut importieren.';

  @override
  String get historyImportFailureDecode =>
      'Die Datei konnte nicht dekodiert werden. Sie ist vermutlich beschädigt oder unvollständig. Importiere eine andere Kopie oder wandle sie in WAV um.';

  @override
  String get historyImportFailureInputLimit =>
      'Die Datei ist zu groß oder länger als 6 Stunden. Bitte in kürzere Teile aufteilen.';

  @override
  String get historyImportFailureTranscription =>
      'Transkription fehlgeschlagen. Prüfe die Spracherkennung in den Einstellungen und versuche es erneut.';

  @override
  String get historyImportFailureSave =>
      'Das Transkript konnte nicht gespeichert werden. Prüfe den freien Speicherplatz und versuche es erneut.';

  @override
  String get historyImportRejectedFolder =>
      'Ordner können nicht importiert werden. Bitte die Audiodateien darin auswählen.';

  @override
  String get historyImportRejectedNotFound => 'Die Datei wurde nicht gefunden.';

  @override
  String historyImportRejectedType(String formats) {
    return 'Dieser Dateityp kann nicht importiert werden. Unterstützt: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'Der Dateidialog ließ sich nicht öffnen. Versuche es erneut oder zieh die Dateien auf diese Seite.';

  @override
  String get historyImportDropHere =>
      'Audiodateien hier ablegen, um sie zu transkribieren';

  @override
  String get historyImportCancel => 'Import abbrechen';

  @override
  String get historyImportRetry => 'Import erneut versuchen';

  @override
  String get recoveryOffer =>
      'Eine unterbrochene Aufnahme wurde gefunden. Audio wiederherstellen und transkribieren?';

  @override
  String get recoveryNoAudioKept =>
      'Eine unterbrochene Aufnahme wurde gefunden. Es wurde kein Audio gespeichert, weil die Audio-Aufbewahrung aus ist.';

  @override
  String get recoveryNoAudioCaptured =>
      'Eine unterbrochene Aufnahme wurde gefunden, enthält aber kein Audio.';

  @override
  String get recoveryRestore => 'Wiederherstellen';

  @override
  String get recoveryDiscard => 'Verwerfen';

  @override
  String get recoveryDiscardConfirm => 'Diese Aufnahme verwerfen?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'Diese unterbrochene Aufnahme wird von diesem Gerät entfernt, samt eventuell gespeichertem Audio.';

  @override
  String get recoveryFailed =>
      'Wiederherstellung fehlgeschlagen. Das Audio bleibt erhalten, du kannst es erneut versuchen.';

  @override
  String recoverySkippedCorrupt(int count) {
    return '$count beschädigte Wiederherstellungseinträge wurden übersprungen und bleiben auf dem Datenträger.';
  }

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupDictation => 'Spracheingabe';

  @override
  String get settingsGroupSystem => 'System';

  @override
  String get settingsAreaGeneral => 'Allgemein';

  @override
  String get settingsAreaAppearance => 'Darstellung';

  @override
  String get settingsAreaShortcuts => 'Tastenkürzel';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'Tastenkürzel: $combo';
  }

  @override
  String get settingsAreaRecording => 'Aufnahme & Audio';

  @override
  String get settingsAreaSpeech => 'Spracherkennung';

  @override
  String get settingsAreaTextInsert => 'Text & Einfügen';

  @override
  String get settingsAreaPrivacy => 'Datenschutz & Daten';

  @override
  String get settingsAreaAdvanced => 'Erweitert';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'Aktuell';

  @override
  String get settingsNavUpdateAvailable => 'Update verfügbar';

  @override
  String get settingsNavStoreUpdates => 'Updates über den Store';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'Im Store-Build liefert der Store die Updates. Eine Prüfung in der App gibt es hier nicht.';

  @override
  String get settingsStoreBetaUnavailable =>
      'Vorabversionen gibt es im Store-Build nicht.';

  @override
  String get settingsStoreCudaUnavailable =>
      'Im Store-Build nicht verfügbar, Treiber-Downloads außerhalb des Stores sind dort nicht erlaubt.';

  @override
  String get settingsOverlayPreview => 'Vorschau des Overlays';

  @override
  String get settingsPreviewTitle => 'Vorschau';

  @override
  String get settingsPreviewHint =>
      'So erscheinen Overlay und Button beim Aufnehmen. Änderungen wirken sofort.';

  @override
  String get settingsPreviewOverlayCaption => 'Overlay';

  @override
  String get settingsOverlayOptionsGroup => 'Overlay';

  @override
  String get settingsOverlayForm => 'Form';

  @override
  String get settingsOverlayFormSubtitle =>
      'Pille oder Rechteck mit abgerundeten Ecken.';

  @override
  String get settingsOverlayFormPill => 'Pille';

  @override
  String get settingsOverlayFormRoundedRect => 'Abgerundet';

  @override
  String get settingsOverlayWaveStyle => 'Wellenstil';

  @override
  String get settingsOverlayWaveStyleSubtitle =>
      'Wie deine Stimme im Overlay dargestellt wird.';

  @override
  String get settingsOverlayWaveBars => 'Balken';

  @override
  String get settingsOverlayWaveLine => 'Linie';

  @override
  String get settingsOverlayWaveDots => 'Punkte';

  @override
  String get settingsOverlayWaveFluid => 'Fließende Kontur';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'Der Rand reagiert auf deine Stimme. Bei „Bewegung reduzieren“ aus.';

  @override
  String get settingsOverlayShowTimer => 'Zeitanzeige';

  @override
  String get settingsOverlayShowTimerSubtitle =>
      'Verstrichene Aufnahmezeit im Overlay anzeigen.';

  @override
  String get settingsOverlayShowCancel => 'Abbrechen-Symbol';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'Stopp bleibt immer sichtbar. Esc bricht weiterhin ab.';

  @override
  String get settingsOverlayOpacity => 'Deckkraft';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'Wird angehoben, wenn die Welle sonst zu blass wäre.';

  @override
  String get settingsOverlayOpacityFull => '100 %';

  @override
  String get settingsOverlayOpacityReduced => '80 %';

  @override
  String get settingsOverlayOpacitySubtle => '60 %';

  @override
  String get settingsFloatingButtonSize => 'Größe';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Durchmesser des schwebenden Buttons';

  @override
  String get settingsFloatingButtonSizeSmall => 'Klein';

  @override
  String get settingsFloatingButtonSizeMedium => 'Mittel';

  @override
  String get settingsFloatingButtonSizeLarge => 'Groß';

  @override
  String get settingsFloatingButtonShape => 'Form';

  @override
  String get settingsFloatingButtonShapeSubtitle =>
      'Rund oder abgerundetes Quadrat';

  @override
  String get settingsFloatingButtonShapeRound => 'Rund';

  @override
  String get settingsFloatingButtonShapeSquare => 'Quadrat';

  @override
  String get settingsFloatingButtonRing => 'Aufnahmering';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'Farbiger Ring um den Button, solange aufgenommen wird';

  @override
  String get settingsFloatingButtonIdleOpacity => 'Deckkraft im Ruhezustand';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'Wie deutlich der Button ohne Aufnahme erscheint';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'Gemeinsam (Farben)';

  @override
  String get settingsAreaSmartMode => 'Smart Mode';

  @override
  String get settingsAreaDictionary => 'Wörterbuch';

  @override
  String get settingsSearchEmptyHelp => 'In der Hilfe suchen';

  @override
  String get dictionaryTabTerms => 'Begriffe';

  @override
  String get dictionaryTabReplacements => 'Ersetzungen';

  @override
  String get dictionaryTabSuggestions => 'Vorschläge';

  @override
  String get dictionaryTermsEffectPrompt =>
      'Wird als Hinweis an die Spracherkennung übergeben. Sie kann diese Schreibweisen bevorzugen, ersetzt aber selbst keinen Text.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'Die aktive Spracherkennung nimmt keine Hinweise an. Nur Ersetzungen ändern den Text. Deine Begriffe bleiben gespeichert.';

  @override
  String get dictionaryTermsHelp =>
      'Namen, Fachbegriffe und Abkürzungen, die die Erkennung oft falsch schreibt. Trenne sie mit Kommas oder Zeilenumbrüchen.';

  @override
  String get dictionaryReplacementsHelp =>
      'Nur Wörter eintragen, die die Erkennung tatsächlich falsch schreibt. Richtig erkannte Wörter bleiben unverändert.';

  @override
  String get dictionaryTestTitle => 'Ausprobieren';

  @override
  String get dictionaryTestInputLabel => 'Beispielsatz';

  @override
  String get dictionaryTestInputHint =>
      'Schreibe einen Satz, um zu sehen, welche Ersetzungen greifen.';

  @override
  String get dictionaryTestResultLabel => 'Ergebnis';

  @override
  String get dictionaryTestNoChange => 'Keine Ersetzung greift.';

  @override
  String get dictionaryCsvTitle => 'Import und Export (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'Eine Zeile je Eintrag: Auslöser mit $pipe getrennt, Ersetzung, Modus (exact oder fuzzy), Schwelle.';
  }

  @override
  String get dictionaryCsvImport => 'CSV importieren';

  @override
  String get dictionaryCsvExport => 'CSV exportieren';

  @override
  String get dictionaryCsvExportEmpty =>
      'Noch keine Ersetzungen zum Exportieren.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'Die Datei ist größer als 1 MB. Teile sie in kleinere Dateien.';

  @override
  String get dictionaryCsvImportReadError =>
      'Die Datei konnte nicht gelesen werden.';

  @override
  String get dictionaryCsvImportNothing => 'Keine gültigen Einträge gefunden.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    return '$count Zeilen wurden übersprungen, weil sie unvollständig oder ungültig sind.';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    return 'Nur die ersten $count Einträge wurden gelesen.';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return '$added Einträge hinzugefügt.';
  }

  @override
  String get dictionaryCsvExportFailed =>
      'Die CSV-Datei konnte nicht gespeichert werden.';

  @override
  String dictionaryCsvExportDone(int count) {
    return '$count Einträge exportiert.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'Zeile $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'Zu wenige Spalten.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'Kein Auslöser.';

  @override
  String get dictionaryCsvReasonTriggerTooLong => 'Der Auslöser ist zu lang.';

  @override
  String get dictionaryCsvReasonEmptyReplacement => 'Kein Ersetzungstext.';

  @override
  String get dictionaryCsvReasonReplacementTooLong =>
      'Der Ersetzungstext ist zu lang.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'Der Modus muss exact oder fuzzy sein.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'Die Schwelle muss streng, standard, tolerant oder eine Zahl von 0,5 bis 1 sein.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'Die Zeile enthält ein Steuer- oder unsichtbares Formatierungszeichen oder einen Zeilenumbruch.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'Zu viele Trigger in einer Zeile (höchstens $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'Einträge prüfen';

  @override
  String get dictionaryDuplicateBadge => 'Doppelt';

  @override
  String get dictionaryDuplicateHint =>
      'Ein anderer Eintrag nutzt denselben Auslöser. Es gilt der Eintrag, der in der Liste weiter oben steht.';

  @override
  String dictionaryUsageCount(int count) {
    return '$count× verwendet';
  }

  @override
  String get dictionaryFavouriteLabel => 'Favorit';

  @override
  String dictionarySuggestionsHint(int count) {
    return 'Ein Vorschlag erscheint, wenn dieselbe Korrektur $count-mal vorkommt. Ohne deine Zustimmung wird nichts übernommen.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'Noch keine Vorschläge';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'Korrigierst du dasselbe Wort zweimal, bietet WhisPaste hier eine Ersetzung an.';

  @override
  String get dictionarySuggestionAccept => 'Annehmen';

  @override
  String get dictionarySuggestionReject => 'Ablehnen';

  @override
  String get dictionarySuggestionAccepted => 'Ersetzung hinzugefügt.';

  @override
  String get dictionarySuggestionRejected =>
      'Vorschlag abgelehnt. Er kommt nicht wieder.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'Die Einträge mit „wird hinzugefügt“ kommen in deine Liste. Vorhandene Einträge bleiben unverändert.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return '$count Einträge hinzufügen';
  }

  @override
  String get dictionaryCsvImportEncodingError =>
      'Die Datei ist keine UTF-8-Textdatei.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'Diese Datei hat ein Paketformat, das diese App nicht lesen kann.';

  @override
  String get dictionaryCsvRefusedType =>
      'Diese Datei ist kein Wörterbuch-Paket für Ersetzungen.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'Paket: $name (erstellt am $date)';
  }

  @override
  String get dictionaryCsvPackageNone =>
      'Ohne Paketinfo (ältere oder fremde Datei)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'Neu: $added · Duplikate: $duplicates · Konflikte: $conflicts · Zirkelverweise: $circular · Fehlerhaft: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel => 'Wenn ein Auslöser schon existiert';

  @override
  String get dictionaryCsvStrategySkip => 'Überspringen';

  @override
  String get dictionaryCsvStrategyOverwrite => 'Überschreiben';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'Beide behalten';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'Die Zeile wird nicht übernommen. Vorhandene Einträge bleiben unverändert.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'Der gemeinsame Auslöser wird aus dem alten Eintrag entfernt, die Zeile kommt neu dazu. $changed bestehende Einträge ändern sich oder werden gelöscht.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'Die Zeile kommt zusätzlich dazu. Bei gleichem Auslöser greift weiterhin der vorhandene Eintrag, der früher in der Liste steht.';

  @override
  String get dictionaryCsvStatusAdded => 'wird hinzugefügt';

  @override
  String get dictionaryCsvStatusDuplicate => 'bereits vorhanden';

  @override
  String get dictionaryCsvStatusConflictSkipped =>
      'Konflikt, wird übersprungen';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'Konflikt, ersetzt den bestehenden Auslöser';

  @override
  String get dictionaryCsvStatusConflictKept =>
      'Konflikt, wird zusätzlich angelegt';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'in dieser Datei von einer späteren Zeile ersetzt';

  @override
  String get dictionaryCsvStatusCircular =>
      'Zirkelverweis, wird nicht übernommen';

  @override
  String get dictionaryCsvRowWillAdd => 'wird hinzugefügt';

  @override
  String get dictionaryCsvRowSkipped => 'Duplikat, wird übersprungen';

  @override
  String get dictionaryCsvExportSelectTitle =>
      'Einträge für den Export auswählen';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return '$count Einträge stehen zur Auswahl';
  }

  @override
  String get dictionaryCsvAllPresent =>
      'Alle Einträge sind bereits vorhanden. Es wird nichts geschrieben.';

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'Exportieren ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'Zu viele Einträge für eine Datei: $count. Wähle weniger aus (höchstens 5000 Einträge, 1 MiB).';
  }

  @override
  String get settingsBetaGroupHeading => 'Vorabversionen';

  @override
  String get analyticsWordingTitle => 'Formulierung';

  @override
  String get analyticsWordingPanelTitle => 'Wörter: roh vs. überarbeitet';

  @override
  String get analyticsRawWords => 'Rohwörter';

  @override
  String get analyticsRevisedWords => 'Überarbeitete Wörter';

  @override
  String get analyticsTransformActions => 'Aufnahmen mit Überarbeitung';

  @override
  String get analyticsCorrectionsTitle => 'Häufige Korrekturen';

  @override
  String get analyticsNoCorrections => 'Noch keine Korrekturen erfasst.';

  @override
  String get errorNoticeNoModelCause => 'Kein Sprachmodell installiert.';

  @override
  String get errorNoticeNoModelNext =>
      'Lade ein Modell in den Einstellungen herunter und versuche es erneut.';

  @override
  String get errorNoticeMicCause =>
      'WhisPaste hat keinen Zugriff auf das Mikrofon.';

  @override
  String get errorNoticeMicNext =>
      'Erlaube den Zugriff in den Systemeinstellungen und versuche es erneut.';

  @override
  String get errorNoticeTranscribeCause =>
      'Die Transkription ist fehlgeschlagen.';

  @override
  String get errorNoticeTranscribeNext =>
      'Versuche es erneut. Hilft das nicht, starte WhisPaste neu oder wähle in den Einstellungen ein anderes Modell.';

  @override
  String get errorNoticeCpuCause =>
      'Die GPU konnte für diese Transkription nicht genutzt werden.';

  @override
  String get errorNoticeCpuNext =>
      'Sie lief stattdessen auf dem Prozessor, das ist langsamer. Prüfe die GPU-Beschleunigung in den Einstellungen.';

  @override
  String get languageMismatchHint =>
      'Die erkannte Sprache passt nicht zur Einstellung.';

  @override
  String get languageMismatchSwitch => 'Sprache wechseln';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'Parakeet kann $language nicht. Zu Whisper wechseln?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'Zu Whisper wechseln';

  @override
  String get titleBarMinimizeLabel => 'Fenster minimieren';

  @override
  String get titleBarCloseLabel => 'Fenster schließen';

  @override
  String get titleBarMaximizeLabel => 'Fenster maximieren';

  @override
  String get titleBarRestoreLabel => 'Fenster wiederherstellen';

  @override
  String get notificationSmartModeSkippedTitle =>
      'WhisPaste: Smart Mode übersprungen';

  @override
  String get notificationHotkeyFallbackTitle => 'WhisPaste: Hotkey belegt';

  @override
  String get notificationSmartModeSkippedBody =>
      'Die Nachbearbeitung konnte nicht angewendet werden.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'Es ist kein Textmodell geladen, daher wurde die Nachbearbeitung übersprungen.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'Die Nachbearbeitung hat zu lange gedauert.';

  @override
  String get notificationSmartModeOutcomePasted =>
      'Der unbearbeitete Text wurde eingefügt.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'Ob der unbearbeitete Text eingefügt wurde, ließ sich nicht bestätigen.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'Der unbearbeitete Text liegt in der Zwischenablage, eingefügt wurde er nicht.';

  @override
  String get notificationSmartModeOutcomeNone =>
      'Der unbearbeitete Text wurde nicht eingefügt.';

  @override
  String get smartModeNoTextModelHint =>
      'Kein Textmodell eingerichtet – bis dahin ist nur „Aus“ wählbar.';

  @override
  String get smartModeLoadTextModelAction => 'Kein Textmodell – jetzt laden';

  @override
  String get smartModeAddOpenAiKeyAction => 'OpenAI-Schlüssel eintragen';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'Die Datei ist kein gültiger WhisPaste-Export.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'Die Datei oder die Einstellungen konnten nicht verarbeitet werden.';

  @override
  String get historyImportAudioLabel => 'Audio';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'App-Wechsel';

  @override
  String get hotkeyConflictNoteQuitApp => 'App beenden';

  @override
  String get hotkeyConflictNoteCloseWindow => 'Fenster schließen';

  @override
  String get hotkeyConflictNoteHideApp => 'App ausblenden';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'Fenster minimieren';

  @override
  String get hotkeyConflictNoteCycleWindows => 'Fenster wechseln';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen =>
      'Screenshot (ganzer Bildschirm)';

  @override
  String get hotkeyConflictNoteScreenshotSelection => 'Screenshot (Auswahl)';

  @override
  String get hotkeyConflictNoteScreenshotRecording =>
      'Screenshot/Bildschirmaufnahme';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'Emoji- und Symbolauswahl';

  @override
  String get hotkeyConflictNoteForceQuit => 'Dialog „Sofort beenden“';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'Arbeitsstation sperren';

  @override
  String get hotkeyConflictNoteShowDesktop => 'Desktop anzeigen/ausblenden';

  @override
  String get hotkeyConflictNoteFileExplorer => 'Datei-Explorer';

  @override
  String get hotkeyConflictNoteRunDialog => 'Ausführen-Dialog';

  @override
  String get hotkeyConflictNoteSettings => 'Einstellungen';

  @override
  String get hotkeyConflictNoteSearch => 'Suche';

  @override
  String get hotkeyConflictNoteTaskView => 'Aufgabenansicht';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch => 'Eingabesprache wechseln';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'Fenster maximieren';

  @override
  String get hotkeyConflictNoteSnapLeft => 'Fenster links andocken';

  @override
  String get hotkeyConflictNoteSnapRight => 'Fenster rechts andocken';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'Sicherheitsoptionen / Task-Manager';

  @override
  String get hotkeyConflictNoteTaskManager => 'Task-Manager';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde =>
      'Bildschirm sperren (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'Dialog „Ausführen“ (KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'Dialog zum Abmelden/Herunterfahren';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'Terminal öffnen (GNOME/KDE-Standard)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'Bildschirm sperren (GNOME)';

  @override
  String get hotkeyConflictNoteActivityOverviewKde =>
      'Aktivitätenübersicht (KDE)';

  @override
  String get settingsTextProcessingHeading => 'Textaufbereitung';

  @override
  String get settingsShowNotificationsSubtitle =>
      'Meldet Probleme, zum Beispiel blockiertes Auto-Paste oder ein fehlendes Mikrofonsignal.';

  @override
  String get settingsGainSubtitle =>
      'Verstärkt das Mikrofonsignal, bevor es aufgenommen wird. Zu hohe Werte können die Aufnahme verzerren.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'Was mit dem erkannten Text passiert. „Auto-Paste“ setzt ihn direkt an den Cursor.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'Die Sprache, die die Erkennung erwartet. Die automatische Erkennung funktioniert meist gut. Eine feste Sprache ist bei kurzen Aufnahmen oft genauer.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'Dein eigener Schlüssel von OpenAI. Nur nötig, wenn du OpenAI als Erkennung oder für Smart Mode nutzt. Audio und Text gehen dann direkt an OpenAI und werden nach deren Tarif abgerechnet.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'Dein eigener Schlüssel von Deepgram. Nur nötig, wenn du Deepgram zur Erkennung nutzt. Audio geht dann direkt an Deepgram und wird nach deren Tarif abgerechnet.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'Setzt alle Einstellungen, API-Schlüssel und Statistiken zurück. Aufnahmen, Notizen und Modelle bleiben erhalten.';

  @override
  String get settingsFactoryResetSubtitle =>
      'Löscht sofort alle Transkriptionen, Notizen, Audiodateien, Wörterbuch, Textbausteine, Modelle, Protokolle und Einstellungen auf diesem Gerät. Nicht rückgängig zu machen.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'Mit dem Hotkey startest du eine Aufnahme aus jedem Programm. Ausgeschaltet reagiert WhisPaste auf keinen Hotkey.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'Sucht sofort nach einer neuen Version. Installiert wird erst nach deiner Bestätigung.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'Wie viele Transkriptionen bleiben, bevor ältere in den Papierkorb wandern. Im Papierkorb werden Transkriptionen nach der gewählten Zeit endgültig gelöscht. Favoriten bleiben immer erhalten. Gespeicherte Audiodateien werden unabhängig davon spätestens 30 Tage nach der Aufnahme entfernt.';

  @override
  String get smartModeTargetLanguageSubtitle =>
      'Nur für das Preset Übersetzen.';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'Die Datei ist zu groß für einen Import (Grenze: etwa 5 MB). Wähle eine Einstellungsdatei, die WhisPaste exportiert hat.';

  @override
  String get settingsSearchKeywordsInterface =>
      'Thema, Hell, Dunkel, Design, Erscheinungsbild, Sprache, Autostart, minimiert, Benachrichtigungen, Systemsprache, Panel, Seitenpanel, Zwischenablage-Panel, Schnelleinfügen, Panel-Position, Bildschirmkante, Kante, links, rechts, Papierkorb, Ablage';

  @override
  String get settingsSearchKeywordsStt =>
      'Modell, Whisper, Qualität, Transkription, Dienst, Sprachmodell, lokal, Cloud, Sprache, Wartezeit, Vokabular, Wörterbuch, STT, Spracherkennung, Wörter, Deepgram, OpenAI, API-Schlüssel, Nur Zahlen, Interpunktion, Zeichensetzung, Variante, Stille, Trimmen, Füllwörter, äh, Zeilenumbruch, Absatz, Zeile, GPU, Grafik, Beschleunigung, Prozessor, Hardware';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'Preset, Aufräumen, Kürzen, Übersetzen, Gemma, Textmodell, herunterladen, Nachbearbeitung, Textbereinigung, Auswahl bearbeiten, Auswahl, markierten Text';

  @override
  String get settingsSearchKeywordsAudio =>
      'Mikrofon, Aufnahme, Verstärkung, Lautstärke, Push-to-Talk, Taste halten, Eingang, Gain';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'Zwischenablage, Einfügen, Autopaste, Kopieren, Aktion, Output, nichts tun, Blockliste, Zwischenablage wiederherstellen, Transkript behalten, vorheriger Inhalt';

  @override
  String get settingsSearchKeywordsOverlay =>
      'Overlay, schwebend, Anzeige, Status, Position, Fenster, oben mittig, unten mittig, Startposition, Live-Transkript';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'Hintergrund, Farbe, Marine, Graphit, Gletscher, Glas, Volldeckend, Hintergrundfarbe, Bernstein, Amber';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'Welle, Wellen, Wellenfarbe, Farbe, Cyan, Violett, Neutral, Animation, Bernstein, Amber';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'Button, schwebend, immer sichtbar, Aufnahme-Button, Schnellzugriff';

  @override
  String get settingsSearchKeywordsHotkey =>
      'Tastenkürzel, Tastenkombination, Hotkey, Kürzel, Shortcut, globale Taste, Tastenbindung, Tastatur, Tasten';

  @override
  String get settingsSearchKeywordsSound =>
      'Ton, Klang, Audio-Signal, Signal, Piep, Lautstärke, Aufnahmeton, Abschluss, Benachrichtigung';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'Schutz, Stille, automatisch stoppen, Timeout, Mikrofon-Timeout, Stille-Erkennung, Sicherheit, Totmikrofon, Aufnahmedauer';

  @override
  String get settingsSearchKeywordsHistory =>
      'Aufnahmen, Einträge, Papierkorb, Bereinigung, Aufbewahrung, Maximum, automatisch löschen, Löschung, Speicher, verbergen, ausblenden, Privatsphäre, PIN, Verlauf, sperren, Sperre, Schutz';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'Export, Import, exportieren, importieren, Umzug, übertragen, sichern, Sicherung, wiederherstellen, Gerätewechsel, mitnehmen, Datensicherung, neuer Rechner, Autosicherung, automatisch sichern, automatische Sicherung';

  @override
  String get settingsSearchKeywordsAdvanced =>
      'Zurücksetzen, Standardwerte, Factory Reset';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'Automatisierung, API, Skript, Token, Bearer, HTTP, localhost, Port';

  @override
  String get settingsSearchKeywordsUpdates =>
      'Update, Beta, Kanal, Release-Kanal, Vorabversion, prüfen, automatisch, neue Version, Stable, Version';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'Einführung, Onboarding, Ersteinrichtung, Einrichtung, Rundgang, Tour, erneut, nochmal, erste Schritte';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'Bewertung, bewerten, Sterne, Store, unterstützen';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'Datenschutz, Analyse, Statistik, Tracking, anonym, Fehlerberichte, Absturzberichte, Nutzungsstatistiken, Daten, Teilen, Privatsphäre, Aufnahmen behalten, kürzlich';

  @override
  String get manualNoticeLabel => 'Hinweis in der App';

  @override
  String get manualC01Title => 'Erste Schritte';

  @override
  String get manualC01S1Heading => 'Einrichtung beim ersten Start';

  @override
  String get manualC01S1B1 =>
      'Beim ersten Start führt dich WhisPaste durch die Einrichtung. Du kannst jeden Schritt zurückgehen. Alles lässt sich später in den Einstellungen ändern.';

  @override
  String get manualC01S1B2I1 =>
      'Willkommen: ein kurzer Überblick über WhisPaste.';

  @override
  String get manualC01S1B2I2 => 'Datenschutz: was auf deinem Gerät bleibt.';

  @override
  String get manualC01S1B2I3 =>
      'Sprachmodell: du wählst das Sprachmodell und lädst es herunter. Ist für einen Cloud-Anbieter schon ein API-Schlüssel gespeichert, kannst du stattdessen diesen Anbieter wählen.';

  @override
  String get manualC01S1B2I4 =>
      'Hotkey: du legst die Tastenkombination fest, mit der du aufnimmst.';

  @override
  String get manualC01S1B2I5 =>
      'Darstellung: Autostart beim Anmelden ein- oder ausschalten.';

  @override
  String manualC01S1B2I6(String k1) {
    return '$k1: ob der Text automatisch eingefügt wird. Unter Linux entfällt dieser Schritt.';
  }

  @override
  String get manualC01S1B2I7 =>
      'Ausprobieren: eine Testaufnahme, danach geht es los. Ohne Sprachmodell oder gewählten Cloud-Anbieter mit API-Schlüssel bleibt der Abschluss gesperrt.';

  @override
  String get manualC01S2Heading => 'Systemvoraussetzungen';

  @override
  String manualC01S2B1(String ram) {
    return 'WhisPaste braucht ein Gerät mit mindestens $ram Arbeitsspeicher (RAM). Auf Geräten mit weniger zeigt WhisPaste statt der App nur einen Hinweis.';
  }

  @override
  String get manualC01S2B2 =>
      'Zum Aufnehmen brauchst du ein Mikrofon. Im Onboarding kannst du ohne Mikrofon weitermachen, aufnehmen kannst du dann aber erst, wenn ein Mikrofon angeschlossen ist.';

  @override
  String get manualC01S3Heading => 'Sprachmodell herunterladen';

  @override
  String get manualC01S3B1 =>
      'WhisPaste wandelt deine Sprache in Text um, auf deinem Gerät oder über einen Cloud-Anbieter mit eigenem Schlüssel. Für das Gerät brauchst du ein Modell. Den Download startest du selbst, er beginnt nicht automatisch.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: schnell, für europäische Sprachen, ca. $k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: alle 99 Sprachen, Modelle von ca. $k1 bis ca. $k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'Die Modelle liegen im Datenordner der App, im Unterordner $k1.';
  }

  @override
  String get manualC01S3B4 =>
      'Ein Whisper-Modell bleibt nach dem Diktieren geladen, damit der nächste Start schneller geht. Unter „Modell geladen halten“ im Bereich Spracherkennung wählst du: Immer (Standard) spart Wartezeit, braucht aber dauerhaft Arbeitsspeicher. Automatisch hält das Modell nur geladen, wenn dein Rechner genug Arbeitsspeicher hat, sonst entlädt es sich nach 5 Minuten. Nach Leerlauf entlädt es sich nach der Zeit, die du einstellst. Gerät der Speicher knapp, entlädt WhisPaste das Modell automatisch und lädt es wieder, sobald wieder Luft ist.';

  @override
  String get manualC01S3B3 =>
      'Im Bereich Spracherkennung misst der Eintrag „Benchmark erneut ausführen“, wie schnell jede installierte Stufe auf deinem Rechner läuft. Die Ergebnisse zeigen bei den Modellen, wie viel länger eine Stufe braucht, und bestimmen die empfohlene Whisper-Stufe. Für europäische Sprachen empfiehlt WhisPaste stattdessen Parakeet. Während einer Aufnahme startet der Test nicht.';

  @override
  String get manualC02Title => 'Aufnehmen und einfügen';

  @override
  String get manualC02S1Heading => 'Der Hotkey';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'Der Hotkey ist eine Tastenkombination, die in jedem Programm funktioniert. Standard: $k2 unter Windows und Linux, $k3 auf dem Mac. Du änderst ihn im Bereich „Tastenkürzel“ der Einstellungen.';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'Ist die Kombination schon von einem anderen Programm belegt, nutzt WhisPaste für den Hotkey stattdessen $k2 (auf dem Mac $k3). Die übrigen Hotkeys bleiben dann aus, bis du eine freie Kombination einstellst.';
  }

  @override
  String get manualC02S2Heading => 'Gedrückt halten oder umschalten';

  @override
  String get manualC02S2B1 =>
      'Im Bereich „Tastenkürzel“ der Einstellungen wählst du, wie der Hotkey arbeitet:';

  @override
  String get manualC02S2B2I1 =>
      '„Gedrückt halten für Aufnahme“ eingeschaltet: Halte den Hotkey, sprich und lass los. Beim Loslassen endet die Aufnahme.';

  @override
  String get manualC02S2B2I2 =>
      'Ausgeschaltet: Ein Druck startet die Aufnahme, ein zweiter Druck beendet sie.';

  @override
  String get manualC02S3Heading => 'Die Aufnahme sehen';

  @override
  String get manualC02S3B1 =>
      'Das Dock am unteren Rand des Hauptfensters zeigt den aktuellen Zustand. Während einer Aufnahme wechselt die Schaltfläche zu „Aufnahme beenden“, und der Statusbereich zeigt den aktuellen Schritt. Das Dock ist immer da und lässt sich nicht ausschalten.';

  @override
  String get manualC02S3B3 =>
      'Ist das Fenster schmal, verschiebt das Dock weniger wichtige Bedienelemente in das Menü „Mehr“, darunter den Hotkey, den Hinweis zu Auto-Paste und die Update-Meldung. Dort bleibt alles erreichbar.';

  @override
  String get manualC02S3B2I1 =>
      '„Aufnahme-Overlay“ auf „Schwebend (immer sichtbar)“: ein kleines Wellenform-Overlay über allen Programmen. Standard: aus.';

  @override
  String get manualC02S3B2I2 =>
      '„Schwebender Button“: ein Button, mit dem du per Klick aufnimmst. Standard: aus. Unter Linux mit Wayland kann der Desktop Position und Oben-Bleiben begrenzen.';

  @override
  String get manualC02S4Heading => 'Nach der Aufnahme einfügen';

  @override
  String get manualC02S4B1 =>
      'Unter „Nach der Transkription“ wählst du die Aktion nach jeder Aufnahme:';

  @override
  String get manualC02S4B2I1 =>
      '„In Zwischenablage kopieren“ (Standard): Der Text landet in der Zwischenablage. Du fügst ihn selbst ein.';

  @override
  String get manualC02S4B2I2 =>
      '„Auto-Paste“: WhisPaste fügt den Text an der Cursorposition ein.';

  @override
  String get manualC02S4B2I3 => '„Kopieren & einfügen“: beides.';

  @override
  String get manualC02S4B2I4 =>
      '„Nichts tun“: WhisPaste fügt den Text nicht ein und kopiert ihn nicht.';

  @override
  String get manualC02S4B3 =>
      'Apps auf der „Auto-Paste-Sperrliste“ bekommen kein Auto-Paste. Der Text landet dann in der Zwischenablage, oder nur in den Aufnahmen, wenn der Schalter „Bei gesperrten Apps in die Zwischenablage kopieren“ aus ist.';

  @override
  String get manualC02S4B4 =>
      'Unter Windows funktioniert Auto-Paste nicht in Programmen, die mit Administratorrechten laufen.';

  @override
  String get manualC02S4B5 =>
      'Unter Linux markiert WhisPaste den Text mit einem Hinweis, den nur KDE-Klipper beachtet. Andere Zwischenablage-Manager wie GPaste oder CopyQ speichern deine Transkripte trotzdem: Schalte dort das Mitschreiben aus oder lösche den Eintrag.';

  @override
  String get manualC02S4B6 =>
      'Nach dem Einfügen stellt WhisPaste standardmäßig deinen vorherigen Zwischenablage-Inhalt wieder her. Unter „Zwischenablage nach dem Einfügen“ kannst du stattdessen „Transkript behalten“ wählen: Dann bleibt das Transkript in der Zwischenablage. Bleibt ein Einfügen unbestätigt (Zeitüberschreitung), bleibt das Transkript immer dort. Verweigert macOS den Zugriff auf die Zwischenablage, kann WhisPaste den vorherigen Inhalt nicht sichern und stellt ihn nicht wieder her; das Transkript bleibt dann in der Zwischenablage. Dazu erscheint einmal ein Hinweis mit dem Weg zu den Systemeinstellungen.';

  @override
  String get manualC03Title => 'Schnellnotiz';

  @override
  String get manualC03S1Heading => 'Was die Schnellnotiz tut';

  @override
  String get manualC03S1B1 =>
      'Die Schnellnotiz ist eine Notiz, an die WhisPaste neue Aufnahmen anhängt. So sammelst du Gedanken oder eine Liste, ohne jedes Mal eine neue Notiz anzulegen.';

  @override
  String get manualC03S1B2 =>
      'Gibt es noch keine markierte Notiz, legt WhisPaste beim ersten Mal eine neue an und markiert sie.';

  @override
  String get manualC03S2Heading => 'Einrichten';

  @override
  String get manualC03S2B1I1 =>
      'Öffne die Notiz im Bereich „Notizen“ und schalte „Zur Schnellnotiz machen, an die der Hotkey anhängt“ ein. Mit „Schnellnotiz — Markierung entfernen“ hebst du die Markierung auf.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'Den Schnellnotiz-Hotkey schaltest du im Bereich „Tastenkürzel“ der Einstellungen ein. Er ist standardmäßig aus. Die Taste ist $k1 ($k2 bzw. $k3 auf dem Mac).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'Was Smart Mode tut';

  @override
  String manualC04S1B1(String k1) {
    return '$k1 bearbeitet den erkannten Text, bevor er eingefügt wird. Es ist standardmäßig aus, du schaltest es selbst ein.';
  }

  @override
  String get manualC04S1B2 =>
      'Standardmäßig läuft die Verarbeitung auf deinem Gerät („Lokal auf dem Gerät“). Mit der Option „OpenAI“ geht der Text an OpenAI. Details dazu stehen im Kapitel Datenschutz.';

  @override
  String get manualC04S2Heading => 'Presets';

  @override
  String get manualC04S2B1 =>
      'Ein Preset legt fest, was mit dem Text passiert:';

  @override
  String get manualC04S2B2I1 =>
      '„Aus“: keine Nachbearbeitung, der Text bleibt, wie er erkannt wurde.';

  @override
  String get manualC04S2B2I2 =>
      '„Bereinigen“: entfernt Füllwörter wie „äh“ und korrigiert Zeichensetzung und Groß- und Kleinschreibung, ohne Wortlaut, Bedeutung oder Sprache zu verändern.';

  @override
  String get manualC04S2B2I3 =>
      '„Kürzen“: entfernt Wiederholungen und Füllwörter und behält alle wichtigen Fakten und die Sprache bei.';

  @override
  String get manualC04S2B2I4 =>
      '„Übersetzen“: übersetzt den Text in die eingestellte Zielsprache.';

  @override
  String get manualC04S3Heading => 'Zielsprache und Hotkey';

  @override
  String get manualC04S3B1 =>
      'Für „Übersetzen“ wählst du eine Zielsprache: Deutsch, Englisch, Spanisch, Französisch, Portugiesisch, Mandarin oder Russisch. Standard ist Englisch.';

  @override
  String manualC04S3B2(String k1) {
    return 'Ein eigener Hotkey für $k1 ist standardmäßig aus. Er nutzt das Preset und die Zielsprache aus den Einstellungen.';
  }

  @override
  String get manualC04S4Heading => 'Ressourcen';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'Für die lokale Variante lädst du ein Textmodell von etwa $size herunter. Hat dein Gerät weniger als $ram RAM, warnt WhisPaste vor dem Download. Der Download bleibt aber möglich. Im Betrieb braucht das Textmodell zusätzlich etwa 4 bis 5 GB RAM.';
  }

  @override
  String get manualC04S4B2 =>
      'Ist kein Textmodell eingerichtet (lokal noch nicht geladen oder bei OpenAI kein Schlüssel hinterlegt), sind die Presets außer „Aus“ gesperrt. Das Menü im Dock und die Einstellungen nennen den Grund und führen dorthin, wo du das Textmodell lädst oder den Schlüssel einträgst. Schlägt die Nachbearbeitung trotzdem fehl, meldet WhisPaste das und sagt dir, ob der unbearbeitete Text eingefügt wurde oder nur in der Zwischenablage liegt.';

  @override
  String get manualC05Title => 'Wörterbuch';

  @override
  String get manualC05S1Heading => 'Wie Ersetzungen funktionieren';

  @override
  String get manualC05S1B1 =>
      'Eine Ersetzung tauscht bei jeder Aufnahme bestimmte Wörter oder Wortgruppen automatisch gegen einen anderen Text aus.';

  @override
  String get manualC05S1B2 =>
      'Jede Ersetzung hat einen oder mehrere Auslöser, also die Wortgruppen, die erkannt werden sollen, und den neuen Text. Mehrere Auslöser für denselben Text gibst du unter „Auslöser“ ein.';

  @override
  String get manualC05S2Heading => 'Abgleich';

  @override
  String get manualC05S2B1I1 =>
      'Genau: nur die exakt gleiche Schreibweise wird ersetzt.';

  @override
  String get manualC05S2B1I2 =>
      'Ähnlich: auch leicht abweichende Schreibweisen werden ersetzt. Das gilt nur für Auslöser mit mindestens 4 Zeichen.';

  @override
  String get manualC05S2B1I3 =>
      'Toleranz (Strikt, Standard oder Tolerant): stellst du pro Eintrag ein, nicht für alle gemeinsam.';

  @override
  String get manualC05S3Heading => 'Import und Export (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'Du kannst deine Ersetzungen als CSV-Datei sichern oder übertragen. Die Datei hat die Spalten $k1. Mehrere Auslöser trennst du mit $k2. Eine Datei darf höchstens $k3 groß sein und $k4 Zeilen haben.';
  }

  @override
  String get manualC05S3B2 =>
      'Import und Export findest du im Menü „Mehr“ (⋯) über der Liste. Das Testfeld „Ausprobieren“ öffnest du ebenfalls dort.';

  @override
  String get manualC06Title => 'Textbausteine';

  @override
  String get manualC06S1Heading => 'Was Textbausteine sind';

  @override
  String get manualC06S1B1 =>
      'Ein Textbaustein ist ein gespeicherter Text, den du mit einem Trigger-Wort oder einem Hotkey einfügst, zum Beispiel eine Signatur oder eine Standardantwort.';

  @override
  String get manualC06S1B2I1 =>
      '„Statisch“: der Text wird genau so eingefügt, wie du ihn gespeichert hast.';

  @override
  String get manualC06S1B2I2 =>
      '„Interaktiv“: WhisPaste fragt einzelne Felder nacheinander per Aufnahme ab und setzt sie in deine Vorlage ein.';

  @override
  String get manualC06S2Heading => 'Textbaustein-Auswahl öffnen';

  @override
  String get manualC06S2B1 => 'Die Auswahl öffnest du auf zwei Wegen:';

  @override
  String get manualC06S2B2I1 =>
      'Mit dem Trigger-Wort für die Auswahl: Sag nur dieses Wort. Es zählt nur, wenn die ganze Aufnahme genau aus diesem Wort besteht. Das Trigger-Wort stellst du auf der Seite Textbausteine ein. Leer lassen schaltet die Auswahl aus.';

  @override
  String get manualC06S2B2I2 =>
      'Mit dem Hotkey für die Auswahl: standardmäßig aus, einschalten unter „Hotkey für die Auswahl“.';

  @override
  String get manualC06S3Heading => 'Textbaustein anlegen';

  @override
  String get manualC06S3B1I1 =>
      'Lege mit „Hinzufügen“ einen Textbaustein an und wähle „Statisch“ oder „Interaktiv“.';

  @override
  String manualC06S3B1I2(String k1) {
    return 'Bei „Interaktiv“ legst du die Felder fest und schreibst die Vorlage. Platzhalter setzt du in doppelten geschweiften Klammern, etwa $k1.';
  }

  @override
  String get manualC07Title => 'Notizen';

  @override
  String get manualC07S1Heading => 'Notizen führen';

  @override
  String get manualC07S1B1 =>
      'Im Bereich Notizen sammelst du Text, zum Beispiel Ideen oder Recherchen. Aufnahmen landen direkt in einer Notiz, wenn du die Schnellnotiz nutzt.';

  @override
  String get manualC07S1B2I1 =>
      '„Als Favorit markieren“ hebt eine Notiz hervor.';

  @override
  String get manualC07S1B2I2 =>
      '„Tag hinzufügen“ ordnet eine Notiz einer Kategorie zu.';

  @override
  String get manualC07S2Heading => 'Papierkorb';

  @override
  String get manualC07S2B1 =>
      '„In den Papierkorb verschieben“ legt eine Notiz in den Papierkorb. Dort bleibt sie, bis du sie endgültig löschst. Der Papierkorb leert sich nicht automatisch.';

  @override
  String get manualC07S2B2I1 =>
      '„Endgültig löschen“ entfernt die Notiz aus dem Papierkorb.';

  @override
  String get manualC07S3Heading => 'Schnellnotiz';

  @override
  String get manualC07S3B1 =>
      'Welche Notiz die Schnellnotiz ist, siehst du im Bereich Notizen. Details stehen im Kapitel Schnellnotiz.';

  @override
  String get manualC07S4Heading => 'Bilder und Datenschutz';

  @override
  String get manualC07S4B1 =>
      'Beim Hinzufügen eines Bildes entfernt WhisPaste Metadaten wie den Standort (GPS), Kameradaten sowie EXIF-, XMP- und IPTC-Angaben. Gespeichert wird nur die bereinigte Kopie.';

  @override
  String get notesPinGateTitle => 'Notizen sind gesperrt';

  @override
  String get notesPinGateHint =>
      'Gib deine PIN ein, um deine Notizen anzuzeigen.';

  @override
  String get manualC08Title => 'Aufnahmen';

  @override
  String get manualC08S1Heading => 'Was die Aufnahmen enthalten';

  @override
  String get manualC08S1B1 =>
      'In den Aufnahmen steht jeder Eintrag: der erkannte Text, mit Datum. Ist Audio gespeichert, gehört die Audiodatei zum Eintrag.';

  @override
  String get manualC08S2Heading => 'Suchen und filtern';

  @override
  String manualC08S2B1I1(String k1) {
    return 'Tippe $k1, um nach Tags zu filtern.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'Tippe $k1 und eine Sprache, um nach Sprache zu filtern.';
  }

  @override
  String get manualC08S2B1I3 => 'Oder gib einfach ein Stichwort ein.';

  @override
  String get manualC08S2B1I4 =>
      'Oben stehen die Filter „Favoriten“, „Archiviert“, „Papierkorb“ und „Alle“.';

  @override
  String get manualC08S3Heading => 'Einträge verwalten';

  @override
  String get manualC08S3B1I1 =>
      '„Text kopieren“ kopiert den Text erneut in die Zwischenablage.';

  @override
  String get manualC08S3B1I2 =>
      '„Zu Favoriten hinzufügen“ hält einen Eintrag oben fest. „Aus Favoriten entfernen“ hebt das wieder auf.';

  @override
  String get manualC08S3B1I3 =>
      '„Archiv“ nimmt einen Eintrag aus der Hauptliste, ohne ihn zu löschen.';

  @override
  String get manualC08S3B1I4 =>
      '„Duplizieren“, „Zusammenfügen“ (mehrere Einträge zu einem) und „Mehrere auswählen“ helfen beim Aufräumen.';

  @override
  String get manualC08S3B1I5 =>
      '„Anmerkung hinzufügen“ und „Tag hinzufügen…“ ergänzen einen Eintrag.';

  @override
  String get manualC08S4Heading => 'Sprachnotiz';

  @override
  String get manualC08S4B1 =>
      'Am Eintrag startest du eine Sprachnotiz. Sag „tag: Name“, um einen Tag zu setzen, oder „korrektur: Text“, um den Text des Eintrags zu ersetzen.';

  @override
  String get manualC08S4B2 =>
      'Eine Korrektur ersetzt den gesamten Text des Eintrags, nicht nur ein Wort. „correct: Text“ funktioniert genauso. Direkt danach kannst du die Änderung in der Meldung rückgängig machen.';

  @override
  String get manualC08S5Heading => 'PIN-Schutz';

  @override
  String get manualC08S5B1 =>
      'Mit „PIN-Schutz“ verlangst du eine PIN, bevor die Aufnahmen angezeigt werden. Das gilt auch für die Seitenleiste, das Menü des schwebenden Buttons und die Automatisierungs-API. Die PIN hält andere davon ab, die Transkriptionen einfach einzusehen, verschlüsselt sie aber nicht. Notizen sind ebenso gesperrt. Ist eine PIN gesetzt, zeigt das Tray-Menü bei den letzten Aufnahmen nur Uhrzeit und Wortzahl statt des Textanfangs.';

  @override
  String get manualC08S5B2 =>
      'Eine vergessene PIN lässt sich nicht wiederherstellen. Zum Zurücksetzen werden sofort alle Aufnahmen und gespeicherten Audiodateien (einschließlich Archiv und Papierkorb), alle Notizen mit Versionen und alle Notizbilder gelöscht. Einstellungen, Textbausteine und Ersetzungen bleiben erhalten.';

  @override
  String get manualC08S5B3 =>
      'Solange die Aufnahmen mit PIN gesperrt sind, zeigt der Zwischenablage-Reiter im Seitenpanel keinen kopierten Text und fügt auch keinen ein. Nach dem Entsperren ist er wieder sichtbar.';

  @override
  String get manualC08S6Heading => 'Automatisch leeren';

  @override
  String get manualC08S6B1 =>
      'Unter „Papierkorb leeren nach“ stellst du ein, wie lange gelöschte Einträge im Papierkorb bleiben, bevor sie automatisch entfernt werden.';

  @override
  String get manualC09Title => 'Dateien importieren';

  @override
  String get manualC09S1Heading => 'Audio-Dateien transkribieren';

  @override
  String manualC09S1B1(String k1) {
    return 'Du kannst vorhandene Aufnahmen als Datei transkribieren lassen. Wähle dafür „$k1“ und die Datei aus.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'Neben $k1 kannst du je nach System weitere Formate importieren: auf dem Mac $k2, unter Linux $k3, unter Windows $k4.';
  }

  @override
  String get manualC09S2Heading => 'Grenzen';

  @override
  String get manualC09S2B2 =>
      'Was tun: Teile die Aufnahme in kürzere Stücke und importiere sie einzeln.';

  @override
  String get manualC09S3Heading => 'Fehler beim Import';

  @override
  String manualC09S3B2(String k1) {
    return 'Was tun: Versuche es erneut. Hilft das nicht, starte WhisPaste neu oder wähle unter $k1 ein anderes Modell.';
  }

  @override
  String get manualC10Title => 'Statistik';

  @override
  String get manualC10S1Heading => 'Die Bereiche';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'Die Statistik hat drei Bereiche: $k1, $k2 und $k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'Mit $k1 und $k2 wählst du den Zeitraum.';
  }

  @override
  String get manualC10S2Heading => 'Zahlen erklärt';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 und $k2 zählen deine Aufnahmen und die Zeit, die du aufgenommen hast.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 ist eine grobe Schätzung: WhisPaste rechnet zwei Drittel der Aufnahmezeit als gespart, weil Sprechen meist schneller geht als Tippen. Es ist keine Messung.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: Lokale Aufnahmen sparen Cloud-Kosten. WhisPaste schätzt das mit $k2 pro Minute, einem festen Richtwert.';
  }

  @override
  String get manualC10S3Heading => 'Zurücksetzen';

  @override
  String manualC10S3B1(String k1) {
    return '„$k1“ löscht alle Statistikdaten. WhisPaste fragt vorher nach, und das lässt sich nicht rückgängig machen.';
  }

  @override
  String get manualC11Title => 'Einstellungen';

  @override
  String get manualC11S1Heading => 'Die Bereiche';

  @override
  String get manualC11S1B1 =>
      'Die Einstellungen sind in Bereiche gegliedert. Die wichtigsten:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: die Darstellung der App.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: Modell und Erkennungssprache.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: Mikrofon und Lautstärke.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: Preset, Zielsprache und Anbieter.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: was nach einer Aufnahme passiert.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: Hotkeys.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: Papierkorb-Frist.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: Export, Import und Autosicherung.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: lokale API und Ereignis-Hooks für Programme auf diesem Computer.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: weitere Optionen wie Zurücksetzen.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: Version, Update-Prüfung, Links und Lizenzen.';
  }

  @override
  String get manualC11S2Heading => 'Sichern und zurücksetzen';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 sichert deine Einstellungen nach Änderungen automatisch. Die letzten fünf Dateien bleiben erhalten. Standardmäßig ist es aus.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 löscht sofort alle Transkriptionen, Audiodateien und Einstellungen und setzt WhisPaste zurück. Lies die Bestätigung genau, bevor du sie bestätigst.';
  }

  @override
  String get manualC12Title => 'Datenschutz und Offline';

  @override
  String get manualC12S1Heading => 'Was auf deinem Gerät bleibt';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'Die Spracherkennung läuft standardmäßig auf deinem Gerät. Audio geht nur dann an einen Cloud-Dienst, wenn du einen Cloud-Anbieter aktiv einstellst. Transkriptionen liegen in einer lokalen Datenbank auf deinem Gerät, gespeicherte Audiodateien als Dateien daneben. Das Audio der letzten $count Aufnahmen wird nur bei eingeschaltetem „$k1“ aufbewahrt, höchstens $days Tage.';
  }

  @override
  String get manualC12S1B2 =>
      'Die Update-Prüfung fragt GitHub nach neuen Versionen. Feedback wird nur beim Absenden übertragen.';

  @override
  String get manualC12S1B3 =>
      'Schlägt eine Transkription fehl, weil der Server oder die Verbindung nicht erreichbar ist, bleibt das Audio dieser Aufnahme bis zu 24 Stunden erhalten. Du kannst sie über die Fehlermeldung oder unter Datenschutz erneut versuchen. Das gilt auch bei ausgeschalteter Aufbewahrung. Ist sie an, gilt stattdessen die normale Aufbewahrung.';

  @override
  String get manualC12S2Heading => 'Cloud-Anbieter';

  @override
  String manualC12S2B1(String k1) {
    return 'Die Anbieter OpenAI und Deepgram brauchen deinen eigenen API-Schlüssel. Du trägst ihn unter $k1 ein.';
  }

  @override
  String get manualC12S3Heading => 'Statistik und Fehlerberichte';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'Zwei Optionen sind standardmäßig eingeschaltet: $k1 und $k2. Beide kannst du im Bereich $k3 ausschalten.';
  }

  @override
  String get manualC13Title => 'Hardware und Leistung';

  @override
  String get manualC13S1Heading => 'Arbeitsspeicher';

  @override
  String manualC13S1B1(String k1) {
    return 'WhisPaste empfiehlt mindestens $k1 Arbeitsspeicher. Mit weniger startet die App trotzdem und schlägt für die Spracherkennung die Stufe „Schnell“ vor.';
  }

  @override
  String get manualC13S2Heading => 'Grafikkarte';

  @override
  String get manualC13S2B1 =>
      'WhisPaste nutzt die Grafikkarte, wenn sie die Spracherkennung beschleunigen kann:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, die Grafik-Schnittstelle von Apple.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 und $k2 mit AMD- oder Intel-Grafik: $k3, eine verbreitete Grafik-Schnittstelle.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'NVIDIA-Karten nutzen ebenfalls $k1. Mit dem optionalen CUDA-Paket nutzt die Erkennung zusätzlich $k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'Ohne passende Grafikkarte rechnet WhisPaste auf dem Prozessor ($k1). Das ist langsamer.';
  }

  @override
  String get manualC13S3Heading => 'Das CUDA-Paket';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'Das CUDA-Paket ist eine optionale Zusatzdatei für NVIDIA-Karten, laut App für $k1 und $k2. Es gibt es für $k3 und $k4 (x64). Du schaltest es unter $k5 ein.';
  }

  @override
  String get manualC13S3B2 =>
      'Der Download ist einmalig. Die Größe zeigt die App an.';

  @override
  String get manualC13S3B3 =>
      'Das Paket enthält NVIDIA-Komponenten. Vor dem ersten Download stimmst du der NVIDIA-CUDA-Lizenz (Version 2026-01-26) zu; die Zustimmung gilt für diese Installation. Ohne gültige Zustimmung zeigt die Zeile „Zustimmung erforderlich“, und WhisPaste nutzt bis dahin Vulkan oder die CPU. Ändert sich der Lizenztext oder das Paket, wird erneut gefragt.';

  @override
  String get manualC13S4Heading => 'Grafikbeschleunigung';

  @override
  String manualC13S4B1(String k1) {
    return 'Unter $k1 wählst du, ob WhisPaste die Grafikkarte nutzt. Nur auf dem Prozessor ist meist langsamer.';
  }

  @override
  String get manualC13S5Heading => 'Modelle und Größe';

  @override
  String get manualC13S5B1 =>
      'Die Whisper-Modelle gibt es in drei Stufen: Schnell, Ausgewogen und Genau. Genauere Stufen erkennen meist besser, brauchen aber mehr Rechenzeit.';

  @override
  String get manualC14Title => 'Fehlerbehebung';

  @override
  String get manualC14S1Heading => 'So liest du diese Seite';

  @override
  String get manualC14S1B1 =>
      'Jeder Abschnitt beginnt mit einem Hinweis, den WhisPaste anzeigt. Der Wortlaut ist der Originaltext der App. Darunter stehen Ursache und nächster Schritt.';

  @override
  String get manualC14S2Heading => 'Kein Zugriff aufs Mikrofon';

  @override
  String get manualC14S2B2 =>
      'Was tun: Erlaube WhisPaste den Mikrofonzugriff in den Systemeinstellungen. Starte danach die Aufnahme neu.';

  @override
  String get manualC14S3Heading => 'Kein Mikrofon gefunden';

  @override
  String manualC14S3B2(String k1) {
    return 'Was tun: Schließe ein Mikrofon an und wähle es unter $k1.';
  }

  @override
  String get manualC14S4Heading => 'Keine Töne aufgenommen';

  @override
  String manualC14S4B2(String k1) {
    return 'Was tun: Prüfe, ob das richtige Mikrofon gewählt ist und die $k1 nicht auf null steht. Nimm danach erneut auf.';
  }

  @override
  String get manualC14S5Heading => 'Kein Sprachmodell';

  @override
  String manualC14S5B2(String k1) {
    return 'Was tun: Lade unter $k1 ein Modell herunter und versuche es danach erneut.';
  }

  @override
  String get manualC14S6Heading => 'Unbekanntes Modell';

  @override
  String manualC14S6B2(String k1) {
    return 'Was tun: Wähle unter $k1 ein vorhandenes Modell aus.';
  }

  @override
  String get manualC14S7Heading => 'Transkription fehlgeschlagen';

  @override
  String manualC14S7B2(String k1) {
    return 'Was tun: Versuche es erneut. Hilft das nicht, starte WhisPaste neu oder wähle unter $k1 ein anderes Modell.';
  }

  @override
  String get manualC14S8Heading => 'Kein Text erkannt';

  @override
  String get manualC14S8B2 =>
      'Was tun: Sprich deutlicher oder etwas länger und versuche es erneut. Prüfe auch das Mikrofon.';

  @override
  String get manualC14S9Heading => 'Aufnahme oder Transkription zu lang';

  @override
  String get manualC14S9B2 => 'Was tun: Nimm kürzere Abschnitte auf.';

  @override
  String get manualC14S10Heading => 'Cloud-Schlüssel fehlt oder ist ungültig';

  @override
  String manualC14S10B2(String k1) {
    return 'Was tun: Trage den Schlüssel unter $k1 neu ein oder wechsle auf die Erkennung auf dem Gerät.';
  }

  @override
  String get manualC14S11Heading => 'Grafikspeicher voll';

  @override
  String get manualC14S11B2 =>
      'Was tun: Nichts. Du kannst das Modell später in den Einstellungen wieder wählen.';

  @override
  String get manualC14S12Heading => 'Auf dem Prozessor gerechnet';

  @override
  String manualC14S12B2(String k1) {
    return 'Was tun: Meist nichts. Passiert es oft, prüfe unter $k1 die Einstellung und aktualisiere den Grafiktreiber.';
  }

  @override
  String get manualC14S13Heading => 'Auto-Paste blockiert (macOS)';

  @override
  String get manualC14S13B2 =>
      'Was tun: Erlaube WhisPaste die Bedienungshilfen in den Systemeinstellungen. Bleibt die Meldung, starte WhisPaste neu.';

  @override
  String get manualC14S14Heading => 'Auto-Paste blockiert (Windows)';

  @override
  String get manualC14S14B2 =>
      'Was tun: Starte WhisPaste ebenfalls als Administrator.';

  @override
  String get manualC14S15Heading => 'Auto-Paste unter Linux';

  @override
  String get manualC14S15B1 =>
      'Auf Linux nutzt Auto-Paste ein virtuelles Eingabegerät (uinput). Funktioniert es nicht, prüfe, ob WhisPaste auf dieses Gerät zugreifen darf.';

  @override
  String get manualC14S15B2 =>
      'Das .deb-Paket gibt bei der Installation keinen Zugriff frei. Auto-Paste fragt zuerst: Wähle in der Einrichtung oder unter Einstellungen → Nach der Transkription „Freigeben (Administratorpasswort)“ und gib dein Administratorpasswort ein. Solange die Freigabe besteht, können auch andere Programme in deiner Sitzung Tastendrücke erzeugen. Mit „Freigabe entfernen“ nimmst du sie jederzeit zurück, beim Deinstallieren wird sie ebenfalls entfernt.';

  @override
  String get manualC14S15B3 =>
      'Die Flatpak-Version gibt der App Zugriff auf die Eingabegeräte des Systems, damit das automatische Einfügen funktioniert. WhisPaste selbst liest keine Eingabegeräte.';

  @override
  String get manualC14S15B4 =>
      'In der Snap-Version führe das einmal im Terminal aus:';

  @override
  String get manualC14S15B5 =>
      'Das AppImage braucht Zugriff auf /dev/uinput. Kopiere in der Einrichtung oder in den Einstellungen den Befehl und führe ihn einmal im Terminal aus. Er installiert die udev-Regel 71-whispaste-uinput.rules nach /etc/udev/rules.d/, die nur der angemeldeten Sitzung Schreibzugriff gibt. Bis dahin kopiert Auto-Paste den Text nur.';

  @override
  String get manualC14S15TerminalHeading => 'Terminals und Wayland';

  @override
  String get manualC14S15T1 =>
      'In Terminals fügt man unter Linux mit Strg+Umschalt+V ein. WhisPaste erkennt gängige Terminals und nutzt dort diese Tastenkombination von selbst: unter X11 und XWayland, unter KDE Plasma, Sway, Hyprland und niri sowie unter labwc, Wayfire und anderen wlroots-Desktops.';

  @override
  String get manualC14S15T2 =>
      'Unter GNOME mit Wayland erkennt WhisPaste die Ziel-App nur mit der optionalen WhisPaste-Erweiterung für GNOME. Ohne sie erkennt WhisPaste keine Terminals, und eine Sperrliste kopiert den Text nur.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'Zeigt ein Terminal trotzdem ^V statt des Texts, schalte „$k1“ unter $k2 ein. WhisPaste fügt dann überall mit Strg+Umschalt+V ein. Manche Apps belegen diese Tasten anders, LibreOffice öffnet damit zum Beispiel einen Dialog.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'Unter GNOME schaltest du die WhisPaste-Erweiterung in den Einstellungen mit $k1 ein. Mit dem .deb-Paket ist sie schon installiert. Bei Flatpak, AppImage oder dem Tarball installierst du sie einmal mit dem Skript aus dem entpackten Linux-Paket und schaltest sie dann ein:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'Ohne eingerichtetes uinput, etwa im Flatpak, fügt WhisPaste über die Desktop-Freigabe ein: $k1 unter $k2. Dein Desktop fragt dabei einmal nach; die Freigabe lässt sich dort jederzeit zurücknehmen';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'Dieser Desktop lässt Apps noch keine systemweiten Tastenkürzel nutzen. WhisPaste kann $shortcut stattdessen in die GNOME-Tastaturkürzel eintragen.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'Zu GNOME hinzufügen';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut ist in den GNOME-Tastaturkürzeln eingerichtet. Änderst du den Hotkey, passt WhisPaste ihn dort mit an.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'Aus GNOME entfernen';

  @override
  String get settingsDesktopShortcutFailed =>
      'Die GNOME-Tastaturkürzel konnten nicht geändert werden.';

  @override
  String get settingsDesktopShortcutManual =>
      'Dieser Desktop lässt Apps keine systemweiten Tastenkürzel nutzen. Lege diesen Befehl in den Systemeinstellungen auf eine Tastenkombination:';

  @override
  String get manualC14S15HotkeyHeading => 'Hotkey unter Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'Unter Wayland bekommt eine App systemweite Tastenkürzel nur über den Desktop. KDE Plasma und GNOME ab Version 48 bieten das an. Ältere GNOME-Versionen, etwa in Ubuntu 24.04, können das nicht: Dann bietet WhisPaste unter $k2 „$k1“ an und trägt den Hotkey in die GNOME-Tastaturkürzel ein.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'Auf anderen Desktops wie Sway oder Hyprland legst du den Befehl selbst auf eine Tastenkombination. Den genauen Befehl für deine Installation zeigen die Einstellungen unter $k1.';
  }

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'Mit diesem Zugriff könnte die App theoretisch Tastatureingaben anderer Programme mitlesen, wenn dein Benutzer Leserechte auf die Eingabegeräte hat (z. B. als Mitglied der Gruppe input). Mitglieder der Gruppe input können außerdem virtuelle Eingaben erzeugen.';

  @override
  String get manualC14S15B3S =>
      'Auto-Paste braucht zusätzlich Schreibzugriff auf /dev/uinput auf dem Rechner. Installiere dafür die udev-Regel 71-whispaste-uinput.rules nach /etc/udev/rules.d/ und führe danach diese Befehle aus:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'Befehl kopieren';

  @override
  String get manualCodeCopied => 'Befehl kopiert';

  @override
  String get manualCodeCopyFailed =>
      'Kopieren hat nicht geklappt. Markiere den Befehl und kopiere ihn von Hand.';

  @override
  String get manualC14S15B3E =>
      'Die Regel gibt nur der angemeldeten Sitzung Schreibzugriff. Diese Befehle brauchen Administratorrechte (sudo) und verändern das System. Wer das nicht möchte: Lass Auto-Paste ausgeschaltet und füge den Text von Hand ein. Entfernen kannst du die Regel über den Button in den Einstellungen, der den passenden Befehl kopiert.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'Bis dahin kopiert Auto-Paste den Text nur.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'Hotkey ist belegt';

  @override
  String manualC14S16B2(String k1) {
    return 'Was tun: Wähle unter $k1 eine andere Kombination.';
  }

  @override
  String get manualC14S17Heading => 'Autostart nicht eingerichtet';

  @override
  String get manualC14S17B2 =>
      'Was tun: Prüfe die Berechtigungen für den Autostart im Betriebssystem. Ohne Autostart startet WhisPaste nicht von selbst.';

  @override
  String get manualC14S18Heading => 'Autosicherung fehlgeschlagen';

  @override
  String manualC14S18B2(String k1) {
    return 'Was tun: Wähle unter $k1 einen anderen Ordner, der erreichbar ist.';
  }

  @override
  String get manualC14S19Heading => 'Werksreset unvollständig';

  @override
  String get manualC14S19B2 =>
      'Was tun: „Erneut versuchen“ wählen oder WhisPaste neu starten und den Reset danach erneut ausführen.';

  @override
  String get manualC14S20Heading => 'Kein Ton erkannt';

  @override
  String manualC14S20B2(String k1) {
    return 'Was tun: Prüfe das Mikrofon unter $k1 und nimm danach erneut auf.';
  }

  @override
  String get manualC14S21Heading => 'Zu wenig Arbeitsspeicher';

  @override
  String manualC14S21B1(String k1) {
    return 'WhisPaste startet auch mit weniger Arbeitsspeicher als empfohlen ($k1). Dann schlägt die App für die Spracherkennung die Stufe „Schnell“ vor.';
  }

  @override
  String get manualC15Title => 'Tastenkürzel';

  @override
  String get manualC15S1Heading => 'Nur in WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'Diese Tastenkürzel wirken nur, wenn das Fenster von WhisPaste aktiv ist. Den systemweiten Hotkey stellst du dagegen unter $k2 ein.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'Auf dem Mac ersetzt $k1 in der Regel die Taste $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 öffnet die Hilfe.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k öffnet ebenfalls die Hilfe.';
  }

  @override
  String get manualC15S2Heading => 'Aufnahmen';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: Eintrag löschen.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: Favorit umschalten.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: suchen.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: Suche oder Detailansicht schließen.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: Eintrag kopieren.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: Bearbeitung verwerfen. Bei ungespeicherten Änderungen gibt es vorher eine Rückfrage.';
  }

  @override
  String get manualC15S3Heading => 'Notizen';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: Eintrag löschen.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: neue Notiz anlegen.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: suchen.';
  }

  @override
  String get manualC15S4Heading => 'Wörterbuch und Textbausteine';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: Eintrag löschen.';
  }

  @override
  String get manualC15S5Heading => 'Abbrechen während der Aufnahme';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'Während einer Aufnahme oder Transkription fängt WhisPaste die Taste $k1 systemweit ab, damit du abbrechen kannst. In anderen Programmen wirkt $k1 dann nicht. Willst du das nicht, stelle in den Einstellungen $k2 als Abbruchtaste ein.';
  }

  @override
  String get manualC16Title => 'Feedback und Unterstützung';

  @override
  String get manualC16S1Heading => 'Feedback senden';

  @override
  String get manualC16S1B1I1 => 'Bewertung: Pflicht.';

  @override
  String get manualC16S1B1I2 =>
      'Typ: Pflicht. Wähle Problem, Idee, Lob oder Frage.';

  @override
  String get manualC16S1B1I3 => 'Freitext mit höchstens 1000 Zeichen.';

  @override
  String get manualC16S1B1I4 => 'Eine E-Mail-Adresse ist optional.';

  @override
  String get manualC16S1B2 =>
      'Hast du vor Kurzem schon Feedback gesendet, zeigt die App diesen Hinweis:';

  @override
  String get manualC16S2Heading => 'Unterstützung';

  @override
  String manualC16S2B1(String k1) {
    return 'Der Tab $k1 in der Hilfe zeigt, wie du WhisPaste unterstützen kannst.';
  }

  @override
  String get manualC16S3Heading => 'Bewertungs-Hinweis';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'Hast du beim Bewertungs-Hinweis „Nicht mehr fragen“ gewählt, findest du unter $k1 den Schalter „$k2“. Er erscheint nur in diesem Fall.';
  }

  @override
  String get manualC16S4B1 =>
      'Feedback sendest du im Hilfe-Tab, über das Hilfemenü der Menüleiste (macOS) bzw. das Titelleistenmenü (Windows und Linux) und über das Infobereich-Menü. Das Formular ist von dort nur zwei Schritte entfernt.';

  @override
  String get manualC16S5Heading => 'Ideen teilen';

  @override
  String get manualC16S5B1 =>
      'Wähle Idee oder öffne Idee vorschlagen im Hilfemenü: Der Typ ist dann schon gesetzt. Du kannst deine Idee auch auf dem öffentlichen Ideenboard einreichen und über andere abstimmen.';

  @override
  String get manualC16S6Heading => 'Per Stimme schreiben';

  @override
  String get manualC16S6B1 =>
      'Der Mikrofon-Button im Textfeld nimmt deine Stimme auf und setzt den erkannten Text an der Cursorposition ein.';

  @override
  String get manualC16S7Heading => 'Was gesendet wird';

  @override
  String get manualC16S7B1I1 => 'Der gewählte Typ und deine Nachricht.';

  @override
  String get manualC16S7B1I3 =>
      'Deine E-Mail-Adresse nur, wenn du eine angegeben hast. Sie dient allein einer Antwort und wird nach 90 Tagen gelöscht.';

  @override
  String get manualC16S7B1I4 =>
      'Diagnose nur, wenn du Diagnose anhängen einschaltest: App-Version, Betriebssystem, Spracherkennung und Backend. Vorschau anzeigen zeigt dir den genauen Text vor dem Senden.';

  @override
  String get manualC16S7B2 => 'Aufnahmen und Transkripte werden nie angehängt.';

  @override
  String get manualC16S4Heading => 'Wo du das Formular findest';

  @override
  String get manualC16S7B1I2 => 'Die Bewertung, die du gewählt hast.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'Konnte nicht einfügen – der Text liegt in der Zwischenablage ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'Berechtigung prüfen';

  @override
  String get autoPasteResetConfirmTitle =>
      'Eintrag zurücksetzen und neu erlauben?';

  @override
  String get autoPasteResetConfirmBody =>
      'macOS hat einen alten Eintrag für WhisPaste gespeichert, der nicht mehr greift. WhisPaste entfernt nur diesen Eintrag unter „Bedienungshilfen“. Danach fragt macOS dich erneut. Andere Berechtigungen bleiben unverändert.';

  @override
  String get autoPasteResetConfirmButton =>
      'Eintrag zurücksetzen und neu erlauben';

  @override
  String get permissionRowMicTitle => 'Mikrofon';

  @override
  String get permissionRowMicPurpose =>
      'Nimmt deine Stimme auf. Ohne diese Erlaubnis kann nichts aufgenommen werden.';

  @override
  String get permissionRowPasteTitle => 'Auto-Paste';

  @override
  String get permissionRowPastePurpose =>
      'Setzt den Text direkt an den Cursor. Ohne sie landet er in der Zwischenablage.';

  @override
  String get permissionRowAllow => 'Erlauben';

  @override
  String get permissionRowMissingSettings => 'Fehlt – Einstellungen öffnen';

  @override
  String get permissionRowGranted => 'Erlaubt';

  @override
  String get permissionRowOptional => 'Optional';

  @override
  String get autostartApprovalBody =>
      'macOS wartet auf deine Freigabe: WhisPaste startet beim Anmelden erst, wenn du es unter Anmeldeobjekte einschaltest.';

  @override
  String get autostartApprovalAction => 'Anmeldeobjekte öffnen';

  @override
  String get pasteFailureLinuxUinputHint =>
      'Auto-Paste braucht einmalig deine Freigabe für die virtuelle Tastatur (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'Befehl kopieren';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'Auto-Paste ist auf diesem System nicht verfügbar: Es gibt kein virtuelles Tastaturgerät.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'Auto-Paste braucht einmalig Zugriff auf /dev/uinput. Öffne die Auto-Paste-Einstellungen für die einmalige Einrichtung.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'Auto-Paste fragt jetzt, bevor es die virtuelle Tastatur /dev/uinput nutzt, daher hat dieses Update den alten Zugriff entfernt. Der Text liegt in der Zwischenablage, füge ihn mit $paste ein. Klicke hier, um es freizugeben.';
  }

  @override
  String get linuxUinputSetupAction => 'Einrichten';

  @override
  String get linuxUinputConsentDetail =>
      'Damit WhisPaste den Text selbst einfügt, braucht es eine virtuelle Tastatur. Solange sie freigegeben ist, können auch andere Programme in deiner Sitzung Tastendrücke erzeugen. Ohne Freigabe kopiert WhisPaste den Text, und du fügst ihn selbst ein.';

  @override
  String get linuxUinputGrantButton => 'Freigeben (Administratorpasswort)';

  @override
  String get linuxUinputGrantFailed =>
      'Die Freigabe hat nicht geklappt. WhisPaste kopiert den Text weiter nur.';

  @override
  String get linuxUinputRevokeButton => 'Freigabe entfernen';

  @override
  String get linuxUinputRevokeDone =>
      'Freigabe entfernt. WhisPaste kopiert den Text jetzt nur.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'Schlüssel konnten nicht vollständig entfernt werden.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours Std.';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes Min.';
  }

  @override
  String get dockErrorCauseEngine => 'Das Sprachmodell ist ausgefallen.';

  @override
  String get dockErrorCauseRecording =>
      'Die Aufnahme konnte nicht verarbeitet werden.';

  @override
  String get dockErrorAction =>
      'Spracheinstellungen öffnen und Sprachmodell prüfen.';

  @override
  String get overlayDoneCopiedOnly =>
      'Nur kopiert – Ziel-App gesperrt oder nicht erkannt';

  @override
  String get overlayDoneNotPasted =>
      'Nicht eingefügt – in den Aufnahmen gespeichert';

  @override
  String get overlayDonePasteFailed => 'Einfügen nicht möglich – Text kopieren';

  @override
  String get databaseTooNewTitle => 'WhisPaste kann deine Daten nicht öffnen';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'Die Daten stammen von einer neueren Version von WhisPaste (Datenbankversion $storedVersion). Diese Version unterstützt bis Version $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'Installiere die neueste Version von WhisPaste und starte die App danach erneut. Es wurde nichts verändert oder gelöscht.';

  @override
  String get databaseTooNewQuit => 'Beenden';

  @override
  String get pasteFailureTargetChanged =>
      'Auto-Paste abgebrochen: Du hast während der Verarbeitung die App gewechselt. Der Text liegt in der Zwischenablage.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'Auto-Paste nicht bestätigt. Der Text liegt in der Zwischenablage, füge ihn mit $paste ein.';
  }

  @override
  String get onboardingAppearanceSettingsHint =>
      'Jederzeit änderbar unter Einstellungen → Darstellung';

  @override
  String get onboardingAppearanceSettingsLink =>
      'Live-Vorschau in den Einstellungen öffnen (beendet die Einrichtung)';

  @override
  String get onboardingAppearanceSettingsLinkRevision =>
      'Live-Vorschau in den Einstellungen öffnen (später erneut anzeigen)';

  @override
  String get fileDialogOpenTitle => 'Datei öffnen';

  @override
  String get fileDialogOpenFilesTitle => 'Dateien öffnen';

  @override
  String get fileDialogSaveTitle => 'Datei speichern';

  @override
  String get fileDialogFolderTitle => 'Ordner auswählen';

  @override
  String get fileDialogSelectFolder => 'Auswählen';

  @override
  String get dockLanguageAuto => 'Automatisch';

  @override
  String get settingsLanguageFavoriteAdd => 'Zu Favoriten hinzufügen';

  @override
  String get settingsLanguageFavoriteRemove => 'Aus Favoriten entfernen';

  @override
  String get settingsLanguageFavoritesLimit =>
      'Bis zu 3 Favoriten. Entferne einen, um einen anderen hinzuzufügen.';

  @override
  String get dockMenuFavorites => 'Favoriten';

  @override
  String get dockMenuAllLanguages => 'Alle Sprachen';

  @override
  String get traySpeechModel => 'Sprachmodell';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'Das Tray-Symbol braucht einen Tray-Host. Unter GNOME die Erweiterung AppIndicator installieren; bis dahin ist das Schnellwechsel-Menü nicht verfügbar.';

  @override
  String get trayLanguage => 'Sprache';

  @override
  String get trayLanguageMore => 'Weitere…';

  @override
  String get trayProfile => 'Profil';

  @override
  String get trayProfileAutomatic => 'Automatisch nach App';

  @override
  String get trayProfileNone => 'Kein Profil';

  @override
  String profileSwitchedToast(String name) {
    return 'Profil: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'Nächste Favoriten-Sprache';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'Nächste Favoriten-Sprache';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'Wechselt die Diktiersprache zur nächsten Favoriten-Sprache. Bis zu drei Sprachen lassen sich unter Sprache erkennen als Favorit markieren.';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'Bereits belegt durch $action. Wähle eine andere Kombination.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'Die Tastenkombination ist von einer anderen App belegt oder konnte nicht registriert werden. Wähle eine andere Kombination.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'Unter Wayland funktioniert dieses Kürzel in anderen Apps unter Umständen nicht. Lege dafür einen Desktop-Kurzbefehl an, wenn es nicht reagiert.';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'Diktiersprache: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'Diktiersprache: $language. Gilt ab der nächsten Aufnahme.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'Noch keine Favoriten-Sprachen. Markiere unter Sprache erkennen bis zu drei Sprachen als Favorit, damit das Kürzel funktioniert.';

  @override
  String get languageCycleOpenSettings => 'Einstellungen öffnen';

  @override
  String get manualLangFavHeading => 'Lieblingssprachen';

  @override
  String get manualLangFavB1 =>
      'Markiere in den Einstellungen zur Spracherkennung in der Sprachliste bis zu drei Sprachen mit dem Stern als Favoriten. Favoriten stehen im Sprachmenü der Aufnahme-Leiste und im Tray-Menü ganz oben, damit du mit einem Klick wechseln kannst.';

  @override
  String get manualLangTrayHeading => 'Sprache im Tray-Menü';

  @override
  String get manualLangTrayB1 =>
      'Das Tray-Menü hat ein Untermenü Sprache. Es zeigt deine Favoriten, die aktive Sprache trägt einen Haken. Weitere… öffnet das Fenster mit der vollständigen Liste. Bei Parakeet wählt das Modell die Sprache selbst, dort ist das Untermenü ausgeblendet.';

  @override
  String get manualLangCycleHeading => 'Nächste Favoriten-Sprache';

  @override
  String get manualLangCycleB1 =>
      'Auf der Karte Diktieren kannst du eine Tastenkombination festlegen, die bei jedem Druck die Diktiersprache zur nächsten Favoriten-Sprache wechselt. Das Kürzel ist aus, bis du eine Kombination aufnimmst. Ohne Favoriten zeigt WhisPaste einen Hinweis auf die Einstellung. Unter Linux mit Wayland reagieren andere Apps unter Umständen nicht auf das Kürzel.';

  @override
  String onboardingReadyDesktopShortcutHint(String shortcut) {
    return '$shortcut funktioniert auf diesem Desktop noch nicht systemweit. Geh zurück zur Seite, auf der du den Hotkey gewählt hast, um es einzurichten.';
  }

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut funktioniert erst systemweit, wenn es in den GNOME-Tastaturkürzeln eingetragen ist.';
  }

  @override
  String get recommendationReasonLanguage =>
      'Empfohlen, weil Parakeet deine Sprache kann und auf jedem Gerät schnell ist.';

  @override
  String get recommendationReasonMeasured =>
      'Empfohlen nach der Messung auf diesem Gerät.';

  @override
  String recommendationReasonApple(String memory) {
    return 'Empfohlen für deinen Apple-Chip (Metal) mit $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'Empfohlen für deine NVIDIA-Grafikkarte mit $gb GB Grafikspeicher (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'Empfohlen für deine Grafikkarte $name (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'Empfohlen für den Prozessor, weil keine nutzbare Grafikkarte da ist: $cores Kerne, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name ist Software-Grafik, deshalb rechnet der Prozessor: $cores Kerne, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb GB Arbeitsspeicher';
  }

  @override
  String get recommendationMemoryUnknown => 'Arbeitsspeicher unbekannt';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'Kein Sprachmodell – $name jetzt laden ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'Fehlt das gewählte Sprachmodell, zeigt das Dock „Sprachmodell fehlt“. Das Sprachmenü im Dock bietet es dann als ersten Eintrag zum Laden an, für Whisper wie für Parakeet. Drückst du das Tastenkürzel ohne Modell, erscheint ein Hinweis mit „Jetzt herunterladen“. Wechselst du in den Einstellungen zu Whisper, wählt WhisPaste ein schon geladenes Whisper-Modell, falls das bisher gewählte fehlt.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'Prozessor (Software-Vulkan, $name)';
  }

  @override
  String get menuBarMenuEdit => 'Bearbeiten';

  @override
  String get menuBarMenuWindow => 'Fenster';

  @override
  String get menuBarEditUndo => 'Widerrufen';

  @override
  String get menuBarEditRedo => 'Wiederholen';

  @override
  String get menuBarEditCut => 'Ausschneiden';

  @override
  String get menuBarEditCopy => 'Kopieren';

  @override
  String get menuBarEditPaste => 'Einsetzen';

  @override
  String get menuBarEditSelectAll => 'Alles auswählen';

  @override
  String get menuBarWindowMinimize => 'Minimieren';

  @override
  String get menuBarWindowZoom => 'Zoomen';

  @override
  String get menuBarAppQuit => 'WhisPaste beenden';

  @override
  String get menuBarMenuRecording => 'Aufnahme';

  @override
  String get menuBarAppSettings => 'Einstellungen…';

  @override
  String get menuBarHelpManual => 'Handbuch öffnen';

  @override
  String get menuBarHelpFeedback => 'Feedback senden…';

  @override
  String get menuBarHelpIdea => 'Idee vorschlagen…';

  @override
  String get manualC15S6Heading => 'Menü';

  @override
  String get manualC15S6B1 =>
      'Auf dem Mac stehen die wichtigsten Befehle auch in der Menüleiste oben. Das Menü „Aufnahme“ startet und beendet die Aufnahme und stellt Sprache, Sprachmodell, Smart Mode, Nach der Transkription, Mikrofon und Profil ein.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: Einstellungen öffnen mit $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'Bearbeiten: Ausschneiden, Kopieren, Einsetzen und Alles auswählen wirken auf das gerade aktive Textfeld.';

  @override
  String get manualC15S6B2I3 => 'Fenster: Hauptfenster minimieren und zoomen.';

  @override
  String get manualC15S6B2I4 =>
      'Hilfe: Handbuch öffnen, Feedback senden und Idee vorschlagen.';

  @override
  String get manualC15S6B3 =>
      'Unter Windows und Linux stehen dieselben Befehle in einem Menü-Button oben rechts in der Titelleiste. Er öffnet sich mit Alt oder F10, die Pfeiltasten wählen einen Eintrag, Enter führt ihn aus und Escape schließt das Menü.';

  @override
  String get menuBarAppAbout => 'Über WhisPaste';

  @override
  String get menuBarAppHide => 'Ausblenden';

  @override
  String get menuBarAppHideOthers => 'Andere ausblenden';

  @override
  String get menuBarAppShowAll => 'Alle einblenden';

  @override
  String get titleBarMenuLabel => 'Menü';

  @override
  String get notesTitleLabel => 'Titel';

  @override
  String get notesMoreActions => 'Weitere Aktionen';

  @override
  String get notesVersionSaveNow => 'Version jetzt speichern';

  @override
  String get notesMenuMark => 'Markieren';

  @override
  String get notesMenuAddImage => 'Bild einfügen';

  @override
  String get notesMenuVersions => 'Versionen';

  @override
  String get notesMenuSnippet => 'Als Textbaustein';

  @override
  String get notesVersionsEmpty => 'Noch keine Versionen.';

  @override
  String get notesVersionTooLarge => 'Zu groß für eine Vorschau';

  @override
  String get notesVersionDelete => 'Version löschen';

  @override
  String get notesVersionSaved => 'Version gespeichert';

  @override
  String get notesVersionUnchanged =>
      'Seit der letzten Version gibt es keine Änderungen.';

  @override
  String get notesVersionRestored => 'Version wiederhergestellt';

  @override
  String get notesVersionRestoreMessage =>
      'Titel und Text werden auf diese Version zurückgesetzt. Bilder bleiben unverändert.';

  @override
  String get notesVersionDeleteMessage =>
      'Diese Version wird endgültig gelöscht. Das lässt sich nicht rückgängig machen.';

  @override
  String get notesImageFilesLabel => 'Bilder';

  @override
  String get notesImageRejected =>
      'Diese Datei ist kein unterstütztes Bild (PNG, JPEG, GIF oder WebP).';

  @override
  String get notesImageRemove => 'Bild entfernen';

  @override
  String get notesSnippetCreated => 'Textbaustein angelegt';

  @override
  String get notesSnippetNothing =>
      'Diese Notiz hat keinen Text, der als Textbaustein gespeichert werden könnte.';

  @override
  String get notesMarkNeedsSelection => 'Zuerst eine Textstelle markieren.';

  @override
  String get notesImageLimitCount =>
      'Diese Notiz hat bereits die maximale Anzahl Bilder.';

  @override
  String get notesImageLimitBytes =>
      'Die Bilder dieser Notiz würden die Größengrenze überschreiten.';

  @override
  String get notesImageLimitTotal =>
      'Der Speicher für Bilder ist voll. Entferne ein Bild, um weitere hinzuzufügen.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'Die Datei kam zu langsam oder hat sich beim Kopieren verändert. Bitte erneut versuchen.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'Dieses Format ist auf diesem System nicht verfügbar. Bitte in WAV umwandeln und erneut importieren.';

  @override
  String get audioDropHint =>
      'Audiodateien hier ablegen, um sie zu transkribieren';

  @override
  String audioDropRejectedFolder(String names) {
    return 'Ordner können nicht importiert werden: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'Datei nicht gefunden: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'Nicht unterstützt: $names. Erlaubt sind: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'Das ist keine normale Datei (etwa ein Gerät oder eine Verknüpfung darauf) und kann nicht importiert werden: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'Zu groß (höchstens 1 GB): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'Das ist keine normale Datei und kann nicht importiert werden.';

  @override
  String get historyImportRejectedTooLarge => 'Die Datei ist größer als 1 GB.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'Reservierter Gerätename, kann nicht importiert werden: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'Dieser Dateiname ist unter Windows reserviert und kann nicht importiert werden. Bitte die Datei umbenennen.';

  @override
  String get historyImportFailureIo =>
      'Der Speicher ist voll oder nicht beschreibbar.';

  @override
  String get holdToRecordExplained =>
      'An: Hotkey halten und sprechen, Loslassen beendet die Aufnahme. Aus: einmal drücken startet, erneutes Drücken beendet sie.';

  @override
  String get settingsAreaProfiles => 'Profile';

  @override
  String get profilesSectionHeading => 'Deine Profile';

  @override
  String get profilesEmptyBody =>
      'Profile wechseln Sprachmodell, Sprache, Smart Mode und die Aktion nach der Transkription auf einen Hotkey oder automatisch je App.';

  @override
  String get profilesAddFirst => 'Erstes Profil anlegen';

  @override
  String get profilesAdd => 'Profil anlegen';

  @override
  String get profilesCreate => 'Anlegen';

  @override
  String get profilesLimitReached =>
      'Höchstens 9 Profile. Lösche ein Profil, um ein neues anzulegen.';

  @override
  String get profilesActiveBadge => 'Aktiv';

  @override
  String get profilesMoveUp => 'Nach oben';

  @override
  String get profilesMoveDown => 'Nach unten';

  @override
  String get profilesDragHandle => 'Ziehen zum Sortieren';

  @override
  String get profilesNewTitle => 'Neues Profil';

  @override
  String get profilesNameLabel => 'Name';

  @override
  String get profilesNameEmpty => 'Gib einen Namen ein.';

  @override
  String get profileDetailHeading => 'Einstellungen des Profils';

  @override
  String get profileDetailModel => 'Sprachmodell';

  @override
  String get profileDetailLanguage => 'Sprache';

  @override
  String get profileDetailLanguageSubtitle =>
      'Wirkt bei Whisper und Cloud-Diensten. Parakeet erkennt die Sprache selbst.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'Nach der Transkription';

  @override
  String get profileDetailMicrophone => 'Mikrofon';

  @override
  String get profileKeepUnchanged => 'Unverändert lassen';

  @override
  String profileValueUnavailable(String value) {
    return '$value (nicht verfügbar)';
  }

  @override
  String get profileDetailHotkey => 'Hotkey';

  @override
  String get profileDetailHotkeySubtitle =>
      'Schaltet mit diesem Tastendruck auf dieses Profil.';

  @override
  String get profileHotkeyNone => 'Kein Hotkey';

  @override
  String get profileHotkeyChange => 'Hotkey festlegen';

  @override
  String get profileHotkeyRemove => 'Hotkey entfernen';

  @override
  String get profileHotkeyNeedsModifier =>
      'Ein Profil-Hotkey braucht mindestens eine Zusatztaste, etwa Strg, Alt, Umschalt oder Befehl.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'Belegt von „$action“. Der Hotkey ist nicht aktiv.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'Belegt vom Profil „$name“. Der Hotkey ist nicht aktiv.';
  }

  @override
  String get profileDetailApps => 'Ziel-Apps';

  @override
  String get profileDetailAppsSubtitle =>
      'Ist eine dieser Apps beim Diktieren im Vordergrund, wird das Profil automatisch aktiv.';

  @override
  String get profileAppIdentifierLabel => 'Kennung der App';

  @override
  String get profileAppAdd => 'Hinzufügen';

  @override
  String get profileAppHintMac => 'macOS: Bundle-ID, z. B. com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: Programmname ohne .exe, z. B. chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: WM_CLASS des Fensters, z. B. google-chrome. Unter Wayland nicht erkennbar.';

  @override
  String profileAppClash(String name) {
    return 'Diese App gehört schon zum Profil „$name“.';
  }

  @override
  String get profileAppEmpty => 'Noch keine App zugeordnet.';

  @override
  String get profileAppRemove => 'App-Regel entfernen';

  @override
  String get profileDetailContext => 'Kontext lesen';

  @override
  String get profileDetailContextSubtitle =>
      'Liest optional markierten Text oder die Zwischenablage, damit die Verarbeitung passt. Bei Cloud-Diensten nur mit deiner Einwilligung.';

  @override
  String get profileContextNone => 'Nichts lesen';

  @override
  String get profileContextSelection => 'Markierten Text';

  @override
  String get profileContextClipboard => 'Zwischenablage';

  @override
  String get profileConsentGiven => 'Einwilligung erteilt';

  @override
  String get profileConsentMissing =>
      'Einwilligung fehlt, daher wird kein Kontext gelesen';

  @override
  String get profileConsentWithdraw => 'Einwilligung zurückziehen';

  @override
  String get profileConsentTitle => 'Kontext an einen Cloud-Dienst senden?';

  @override
  String get profileConsentBody =>
      'Ist dieses Profil aktiv, werden der markierte Text oder der Inhalt der Zwischenablage des Zielfensters an den Cloud-Dienst gesendet, der in diesem Profil genannt ist. Das geschieht nur, um diese Aufnahme zu verfeinern. Du kannst die Einwilligung jederzeit in den Profileinstellungen zurückziehen.';

  @override
  String get profileConsentAccept => 'Einwilligen';

  @override
  String get profileDeleteAction => 'Profil löschen';

  @override
  String profileDeleteTitle(String name) {
    return 'Profil „$name“ löschen?';
  }

  @override
  String get profileDeleteMessage =>
      'Das Profil und seine Ziel-Apps werden entfernt. Sein Hotkey ist danach frei.';

  @override
  String get manualProfilesTitle => 'Profile und Schnellwechsel';

  @override
  String get manualProfilesS1Heading => 'Profile anlegen';

  @override
  String get manualProfilesS1Body =>
      'Ein Profil ist ein benannter Satz von Diktier-Einstellungen. Du legst es unter Einstellungen → Profile an und entscheidest bei jedem Feld, ob das Profil es setzt oder unverändert lässt.';

  @override
  String get manualProfilesS1B1 =>
      'Sprachmodell, Sprache, Smart Mode, Aktion nach der Transkription und Mikrofon';

  @override
  String get manualProfilesS1B2 =>
      'Bis zu 9 Profile. Jedes Feld kann auf „Unverändert lassen“ stehen.';

  @override
  String get manualProfilesS2Heading => 'Hotkeys';

  @override
  String get manualProfilesS2Body =>
      'Jedes Profil kann einen eigenen Hotkey bekommen. Drückst du ihn, wird das Profil aktiv und bleibt es, bis du ein anderes Profil wählst oder ein Feld des Profils von Hand änderst.';

  @override
  String get manualProfilesS2Tip =>
      'Ein Hotkey braucht eine Zusatztaste. Eine Kombination, die schon eine andere Funktion nutzt, bleibt inaktiv und wird beim Profil als Konflikt angezeigt.';

  @override
  String get manualProfilesS3Heading => 'Automatisch je App';

  @override
  String get manualProfilesS3Body =>
      'Trägst du unter Ziel-Apps eine App ein, wird das Profil aktiv, sobald diese App beim Diktieren im Vordergrund ist. Die Kennung unterscheidet sich je Betriebssystem:';

  @override
  String get manualProfilesS3Mac =>
      'macOS: Bundle-ID, zum Beispiel com.apple.mail';

  @override
  String get manualProfilesS3Win =>
      'Windows: Programmname ohne .exe, zum Beispiel chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: WM_CLASS des Fensters unter X11, zum Beispiel google-chrome. Unter Wayland kann WhisPaste die App nicht erkennen.';

  @override
  String get manualProfilesS4Heading => 'Tray und Overlay';

  @override
  String get manualProfilesS4Body =>
      'Das Tray-Menü hat das Untermenü „Profil“: „Automatisch nach App“ folgt den Regeln, „Kein Profil“ schaltet sie ab, darunter stehen deine Profile. Im Aufnahme-Overlay steht der Name des aktiven Profils hinter Zeit und Sprache, zum Beispiel 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'Unverändert lassen';

  @override
  String get manualProfilesS5Body =>
      '„Unverändert lassen“ heißt: Das Profil ändert dieses Feld nicht. Es gilt dann der Wert, der gerade in den Einstellungen steht.';

  @override
  String get manualProfilesS6Heading => 'Was ein manueller Wechsel bewirkt';

  @override
  String get manualProfilesS6Body =>
      'Wählst du ein Profil im Tray oder drückst seinen Hotkey, gilt es für alle folgenden Aufnahmen. Ändert du danach ein Feld, das das Profil setzt, etwa das Sprachmodell, endet die Markierung aktiv, und die Regeln je App entscheiden wieder. Die Auswahl bleibt nach einem Neustart erhalten.';

  @override
  String get profileAppCapture => 'App erfassen';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'In $seconds s in die Ziel-App wechseln …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '„$identifier“ wurde als Ziel-App übernommen.';
  }

  @override
  String get profileAppCaptureNone =>
      'Keine fremde App im Vordergrund. Wechsle in die Ziel-App, bevor der Countdown endet.';

  @override
  String get profileAppCaptureUnavailable =>
      'Diese Sitzung kann die Ziel-App nicht erkennen (z. B. Wayland). Trage die Kennung von Hand ein.';
}
