// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get navReplacements => 'Voice Shortcuts';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navAbout => 'About';

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'History';

  @override
  String get pageSettingsTitle => 'Settings';

  @override
  String get pageReplacementsTitle => 'Voice Shortcuts';

  @override
  String get pageAnalyticsTitle => 'Analytics';

  @override
  String get pageAboutTitle => 'About';

  @override
  String get pageFeedbackTitle => 'Feedback';

  @override
  String get historyEmpty => 'No recordings yet';

  @override
  String get historyEmptyHint =>
      'Press the record button or use the hotkey to start dictating.';

  @override
  String get historySearch => 'Search…';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsMicrophone => 'Microphone';

  @override
  String get settingsGain => 'Microphone Volume';

  @override
  String get settingsRecordingSafety => 'Recording Safety';

  @override
  String get settingsDeadMicTimeout => 'Silent Mic Detection';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Stop recording if no audio detected within this time (seconds). 0 = disabled.';

  @override
  String get settingsAutoStopSilence => 'Auto-Stop After Silence';

  @override
  String get settingsAutoStopSilenceHint =>
      'Automatically stop after this many seconds of silence (after speech). 0 = disabled.';

  @override
  String get settingsPostProcessing => 'Text Enhancement';

  @override
  String get settingsPostProcessingHint =>
      'Improve your dictated text automatically using AI.';

  @override
  String get settingsPresetCleanup => 'Clean up';

  @override
  String get settingsPresetConcise => 'Make concise';

  @override
  String get settingsPresetTranslate => 'Translate';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSttModels => 'Speech Recognition Models';

  @override
  String get settingsCloudProviders => 'Cloud Providers';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusRecording => 'Recording…';

  @override
  String get statusTranscribing => 'Transcribing…';

  @override
  String get statusProcessing => 'Processing…';

  @override
  String get statusCopied => 'Copied!';

  @override
  String get statusLocal => 'Local';

  @override
  String get statusCloud => 'Cloud';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get recordingGuardFailed =>
      'No audio detected — microphone may not be working.';

  @override
  String get recordingAutoStopped => 'Recording stopped — silence detected.';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionExport => 'Export';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionSave => 'Save';

  @override
  String get tooltipRecord => 'Start recording';

  @override
  String get tooltipStopRecord => 'Stop recording';

  @override
  String get tooltipTheme => 'Toggle theme';

  @override
  String get tooltipLanguage => 'Language';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Welcome to WhisPaste';

  @override
  String get onboardingWelcomeHint =>
      'Premium dictation with AI post-processing. Dictate anywhere, paste everywhere.';

  @override
  String get feedbackTitle => 'Send Feedback';

  @override
  String get feedbackHint => 'Tell us what you think — we read every message.';
}
