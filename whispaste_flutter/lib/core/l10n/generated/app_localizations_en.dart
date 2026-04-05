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
  String get historyPinned => 'Pinned';

  @override
  String get historyToday => 'Today';

  @override
  String get historyYesterday => 'Yesterday';

  @override
  String get historyThisWeek => 'This Week';

  @override
  String get historyOlder => 'Older';

  @override
  String get historyAll => 'All';

  @override
  String get historyTrash => 'Trash';

  @override
  String get historyArchive => 'Archive';

  @override
  String get historyArchived => 'Archived';

  @override
  String get historyList => 'List';

  @override
  String get historyCards => 'Cards';

  @override
  String get historyCompact => 'Compact';

  @override
  String historyItemsSelected(int count) {
    return '$count selected';
  }

  @override
  String get historyMerge => 'Merge';

  @override
  String get historyRestore => 'Restore';

  @override
  String get historyDeleteForever => 'Delete forever';

  @override
  String get historyDeletePermanently => 'Delete Permanently';

  @override
  String get historyUnarchive => 'Unarchive';

  @override
  String get historyExport => 'Export';

  @override
  String get historyCopyAsMarkdown => 'Copy as Markdown';

  @override
  String get historyDetail => 'Detail';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Duration';

  @override
  String get historyModel => 'Model';

  @override
  String get historyWords => 'Words';

  @override
  String get historyCharacters => 'Characters';

  @override
  String get historySearchTranscriptions => 'Search transcriptions…';

  @override
  String get historyNoResults => 'No results';

  @override
  String historyNoResultsHint(String query) {
    return 'No transcriptions match \"$query\".\nTry a different search term.';
  }

  @override
  String get historyTrashEmpty => 'Trash is empty';

  @override
  String get historyTrashEmptyHint =>
      'Deleted transcriptions will appear here.\nItems are permanently removed after 30 days.';

  @override
  String get historyNoArchivedItems => 'No archived items';

  @override
  String get historyNoArchivedItemsHint =>
      'Archive transcriptions you want to keep\nbut don\'t need in your main list.';

  @override
  String get historyNoRecordingsHint =>
      'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.\n\n🔒 All data stays on your device.';

  @override
  String get historyCopiedToClipboard => 'Copied to clipboard';

  @override
  String get historyMovedToTrash => 'Moved to trash';

  @override
  String get historyUndo => 'Undo';

  @override
  String get historyEntriesMerged => 'Entries merged';

  @override
  String get historyExitSelection => 'Exit selection';

  @override
  String get historySelectMultiple => 'Select multiple';

  @override
  String get historyProcessed => 'Processed';

  @override
  String get historyOnDevice => 'On device';

  @override
  String get historyUntitledRecording => 'Untitled recording';

  @override
  String get historyUntitled => 'Untitled';

  @override
  String get historyPinToTop => 'Pin to top';

  @override
  String get historyUnpin => 'Unpin';

  @override
  String get historyCopyText => 'Copy text';

  @override
  String get historyClose => 'Close';

  @override
  String get historyLanguageLabel => 'Language';

  @override
  String historyResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get historySelectAll => 'Select All';

  @override
  String get historyDeselectAll => 'Deselect All';

  @override
  String get settingsInterface => 'Interface';

  @override
  String get settingsInterfaceSubtitle => 'Appearance and behavior';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsLaunchAtStartup => 'Launch at Startup';

  @override
  String get settingsShowNotifications => 'Show Notifications';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Microphone and recording';

  @override
  String get settingsMicrophone => 'Microphone';

  @override
  String get settingsGain => 'Microphone Volume';

  @override
  String get settingsHoldToRecord => 'Hold to Record';

  @override
  String get settingsSpeechRecognition => 'Speech Recognition';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Voice recognition quality and service';

  @override
  String get settingsService => 'Service';

  @override
  String get settingsQuality => 'Quality';

  @override
  String get settingsRecordingSafety => 'Recording Safety';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Automatic checks and safeguards';

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
  String get settingsTextEnhancementSubtitle =>
      'Improve your dictated text automatically';

  @override
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsStyle => 'Style';

  @override
  String get settingsPresetCleanup => 'Clean up';

  @override
  String get settingsPresetConcise => 'Make concise';

  @override
  String get settingsPresetTranslate => 'Translate';

  @override
  String get settingsSoundFeedback => 'Sound & Feedback';

  @override
  String get settingsSoundFeedbackSubtitle => 'Audio cues for recording events';

  @override
  String get settingsRecordStartSound => 'Record Start Sound';

  @override
  String get settingsRecordStopSound => 'Record Stop Sound';

  @override
  String get settingsTranscriptionCompleteSound =>
      'Transcription Complete Sound';

  @override
  String get settingsOverlayFloatingButton => 'Overlay & Floating Button';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'On-screen recording controls';

  @override
  String get settingsShowOverlay => 'Show Overlay';

  @override
  String get settingsShowFloatingButton => 'Show Floating Button';

  @override
  String get settingsFloatingButtonOpacity => 'Floating Button Opacity';

  @override
  String get settingsFloatingButtonSize => 'Floating Button Size';

  @override
  String get settingsSizeSmall => 'Small';

  @override
  String get settingsSizeNormal => 'Normal';

  @override
  String get settingsSizeLarge => 'Large';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSttModels => 'Speech Recognition Models';

  @override
  String get settingsCloudProviders => 'Cloud Providers';

  @override
  String get settingsCloudProvidersSubtitle => 'API keys for online services';

  @override
  String get settingsOpenAiApiKey => 'OpenAI API Key';

  @override
  String get settingsGroqApiKey => 'Groq API Key';

  @override
  String get settingsDeepgramApiKey => 'Deepgram API Key';

  @override
  String get settingsAnthropicApiKey => 'Anthropic API Key';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsPrivacyNote =>
      'Your recordings and text stay on your device by default. Cloud services are only used when you explicitly enable them.';

  @override
  String get settingsOff => 'Off';

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
