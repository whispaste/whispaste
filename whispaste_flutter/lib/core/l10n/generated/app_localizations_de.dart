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
  String get settingsAudio => 'Audio';

  @override
  String get settingsMicrophone => 'Mikrofon';

  @override
  String get settingsGain => 'Eingangsverstärkung';

  @override
  String get settingsRecordingSafety => 'Aufnahme-Schutz';

  @override
  String get settingsDeadMicTimeout => 'Mikrofon-Erkennung';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Aufnahme stoppen, wenn kein Audio erkannt wird (Sekunden). 0 = deaktiviert.';

  @override
  String get settingsAutoStopSilence => 'Auto-Stopp bei Stille';

  @override
  String get settingsAutoStopSilenceHint =>
      'Automatisch stoppen nach dieser Anzahl Sekunden Stille (nach Sprache). 0 = deaktiviert.';

  @override
  String get settingsPostProcessing => 'Nachbearbeitung';

  @override
  String get settingsPostProcessingHint =>
      'Transkribierten Text automatisch mit KI verbessern.';

  @override
  String get settingsPresetCleanup => 'Bereinigen';

  @override
  String get settingsPresetConcise => 'Kürzen';

  @override
  String get settingsPresetTranslate => 'Übersetzen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsSttModels => 'Spracherkennungs-Modelle';

  @override
  String get settingsCloudProviders => 'Cloud-Anbieter';

  @override
  String get settingsAdvanced => 'Erweitert';

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
