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
  String get settingsTrimSilence => 'Trim Silence';

  @override
  String get settingsTrimSilenceSubtitle =>
      'Automatically remove leading and trailing silence from recordings';

  @override
  String get settingsVoiceActivityDetection => 'Voice Activity Detection';

  @override
  String get settingsVoiceActivityDetectionSubtitle =>
      'Only process audio segments with speech detected';

  @override
  String get settingsVadSensitivity => 'VAD Sensitivity';

  @override
  String get settingsVadSensitivitySubtitle =>
      'How sensitive speech detection is (lower = more sensitive)';

  @override
  String get settingsPostProcessing => 'Post-Processing';

  @override
  String get settingsPostProcessingHint =>
      'Improve your dictated text automatically using AI.';

  @override
  String get settingsTextEnhancementSubtitle =>
      'Clean up, shorten, or translate dictated text automatically';

  @override
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsStyle => 'Style';

  @override
  String get settingsMicrophoneDefault => 'Default';

  @override
  String get settingsMicrophoneHeadset => 'Headset Mic';

  @override
  String get settingsMicrophoneUsb => 'USB Mic';

  @override
  String get settingsServiceOnDevicePrivate => 'On Device (Private)';

  @override
  String get settingsQualityFastTiny => 'Fast (Tiny)';

  @override
  String get settingsQualityBalancedSmall => 'Balanced (Small)';

  @override
  String get settingsQualityHighQualityMedium => 'High Quality (Medium)';

  @override
  String get settingsQualityBestLarge => 'Best Quality (Large)';

  @override
  String get settingsLanguageAutoDetect => 'Auto-detect';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageGerman => 'German';

  @override
  String get settingsLanguageFrench => 'French';

  @override
  String get settingsLanguageSpanish => 'Spanish';

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
  String get settingsSoundVolume => 'Sound Volume';

  @override
  String get settingsAfterTranscription => 'After Transcription';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'What happens with the transcribed text';

  @override
  String get settingsAfterTranscriptionClipboard => 'Copy to Clipboard';

  @override
  String get settingsAfterTranscriptionPaste => 'Auto-Paste at Cursor';

  @override
  String get settingsAfterTranscriptionBoth => 'Copy & Auto-Paste';

  @override
  String get settingsAfterTranscriptionNothing => 'Do Nothing';

  @override
  String get settingsOverlayFloatingButton => 'Overlay & Floating Button';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'On-screen recording controls';

  @override
  String get settingsShowOverlay => 'Recording Overlay';

  @override
  String get settingsOverlayModeInWindow => 'Show during recording';

  @override
  String get settingsOverlayModeFloating => 'Floating (always on top)';

  @override
  String get settingsOverlayModeOff => 'Off';

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
  String get settingsResetToDefaults => 'Reset to Defaults';

  @override
  String get settingsResetDialogTitle => 'Reset all settings?';

  @override
  String get settingsResetConfirmMessage =>
      'This will restore all settings to their original values. Your history and data will not be affected.';

  @override
  String get settingsResetConfirm => 'Reset';

  @override
  String get settingsResetSuccess => 'Settings restored to defaults.';

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
  String get statusTranscriptionDone => 'Transcription complete';

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
  String get actionDismiss => 'Dismiss';

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
  String get tooltipProcessing => 'Processing audio…';

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

  @override
  String get analyticsPreviewBanner =>
      'Preview — showing sample data. Real analytics will appear once you start recording.';

  @override
  String get analyticsOverview => 'Overview';

  @override
  String get analyticsOverviewSubtitle => 'Your dictation stats at a glance';

  @override
  String get analyticsActivity => 'Activity';

  @override
  String get analyticsInsights => 'Insights';

  @override
  String get analyticsTotalRecordings => 'Total Recordings';

  @override
  String get analyticsTotalDuration => 'Total Duration';

  @override
  String get analyticsWordsDictated => 'Words Dictated';

  @override
  String get analyticsTimeSaved => 'Time Saved';

  @override
  String get analyticsRecordingActivity => 'Recording Activity';

  @override
  String get analyticsLast7Days => 'Last 7 days';

  @override
  String get analyticsModelUsage => 'Model Usage';

  @override
  String get analyticsDurationDistribution => 'Duration Distribution';

  @override
  String get analyticsCostSavings => 'Cost & Savings';

  @override
  String get analyticsLocalSavings => 'Local savings';

  @override
  String get analyticsCloudCost => 'Cloud cost';

  @override
  String get analyticsPeriod7d => '7 days';

  @override
  String get analyticsPeriod30d => '30 days';

  @override
  String get analyticsPeriod90d => '90 days';

  @override
  String get analyticsPeriodAll => 'All time';

  @override
  String get analyticsReset => 'Reset';

  @override
  String get analyticsResetTitle => 'Reset Statistics';

  @override
  String get analyticsResetMessage =>
      'Are you sure you want to clear all analytics data? This action cannot be undone.';

  @override
  String get analyticsDayMon => 'Mon';

  @override
  String get analyticsDayTue => 'Tue';

  @override
  String get analyticsDayWed => 'Wed';

  @override
  String get analyticsDayThu => 'Thu';

  @override
  String get analyticsDayFri => 'Fri';

  @override
  String get analyticsDaySat => 'Sat';

  @override
  String get analyticsDaySun => 'Sun';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta this week';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta vs last month';
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
    return '$amount saved';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount spent';
  }

  @override
  String get replacementsSearch => 'Search shortcuts…';

  @override
  String get replacementsAdd => 'Add';

  @override
  String get replacementsEmpty => 'No voice shortcuts yet';

  @override
  String get replacementsEmptyHint =>
      'Add shortcuts to auto-replace words during dictation.\nExample: \"btw\" → \"by the way\"';

  @override
  String get replacementsNoMatches => 'No matches';

  @override
  String get replacementsNoMatchesHint => 'Try a different search term.';

  @override
  String get replacementsAddShortcut => 'Add Shortcut';

  @override
  String get replacementsEditShortcut => 'Edit Shortcut';

  @override
  String get replacementsNewShortcut => 'New Shortcut';

  @override
  String get replacementsDialogHint =>
      'The trigger phrase will be replaced automatically during dictation.';

  @override
  String get replacementsTriggerLabel => 'Trigger phrase';

  @override
  String get replacementsTriggerHint => 'e.g. btw';

  @override
  String get replacementsReplacementLabel => 'Replacement text';

  @override
  String get replacementsReplacementHint => 'e.g. by the way';

  @override
  String get replacementsDeleteTitle => 'Delete Shortcut';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Remove the shortcut \"$trigger\"? This cannot be undone.';
  }

  @override
  String get aboutTagline => 'Voice to text, instantly.';

  @override
  String get aboutWhatsNew => 'What\'s New';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutReportIssue => 'Report Issue';

  @override
  String get aboutSupportTitle => 'Support this project';

  @override
  String get aboutSupportDescription =>
      'WhisPaste is free and open source under the MIT license. If you find it useful, please consider supporting its development!';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Star on GitHub';

  @override
  String get aboutBuiltWith => 'Built with';

  @override
  String get aboutFlutterGo => 'Flutter & Go';

  @override
  String get aboutFlutterGoDesc =>
      'Cross-platform UI with Flutter, performance-critical backend in Go via FFI.';

  @override
  String get aboutWhisper => 'whisper.cpp & OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Local and cloud speech recognition — fast, accurate, multilingual.';

  @override
  String get aboutLlamaCpp => 'llama.cpp';

  @override
  String get aboutLlamaCppDesc =>
      'Local LLM inference for AI post-processing without cloud dependency.';

  @override
  String get aboutPrivacyFirst => 'Privacy-first';

  @override
  String get aboutPrivacyFirstDesc =>
      'Local AI inference by default — your voice never leaves your device unless you choose a cloud provider.';

  @override
  String get aboutPrivacy => 'Privacy & Data';

  @override
  String get aboutPrivacyLocal =>
      'All transcriptions and history are stored locally on your device — never on external servers.';

  @override
  String get aboutPrivacyCloud =>
      'Cloud providers (OpenAI, Groq, Deepgram, Anthropic, Gemini) only receive audio or text when you actively use them. Their privacy policies apply.';

  @override
  String get aboutPrivacyNoTracking =>
      'No analytics, no tracking, no user accounts. Update checks contact GitHub (version + IP only).';

  @override
  String get aboutKeyboardShortcuts => 'Keyboard Shortcuts';

  @override
  String get aboutShortcutRecord => 'Start / Stop recording';

  @override
  String get aboutShortcutPalette => 'Command palette';

  @override
  String get aboutShortcutSettings => 'Settings';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutGitHubRepo => 'GitHub Repository';

  @override
  String get aboutMitLicense => 'MIT License';

  @override
  String get aboutViewOnGitHub => 'View on GitHub';

  @override
  String get aboutPrivacyPolicy => 'Privacy Policy';

  @override
  String get aboutSystemInfo => 'System Info';

  @override
  String get aboutSystemInfoDesc =>
      'Copy a compact diagnostics snapshot for bug reports.';

  @override
  String get aboutCopyDebugInfo => 'Copy Debug Info';

  @override
  String get aboutCopied => 'Copied!';

  @override
  String get aboutMadeWith => 'Made with ♥ by Silvio Lindstedt';

  @override
  String get aboutOpenSource => 'Open source under the MIT License';

  @override
  String get feedbackSubtitle =>
      'Help us improve WhisPaste — every voice matters.';

  @override
  String get feedbackCategoryLabel => 'What\'s this about?';

  @override
  String get feedbackCategoryBug => 'Bug Report';

  @override
  String get feedbackCategoryFeature => 'Feature Idea';

  @override
  String get feedbackCategoryGeneral => 'General';

  @override
  String get feedbackCategoryAiQuality => 'AI Quality';

  @override
  String get feedbackRatingLabel => 'How are you feeling about WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Tell us more';

  @override
  String get feedbackPlaceholderBug =>
      'Describe what happened and what you expected…';

  @override
  String get feedbackPlaceholderFeature =>
      'What would you like to see in WhisPaste?';

  @override
  String get feedbackPlaceholderAi =>
      'How was the transcription or post-processing quality?';

  @override
  String get feedbackPlaceholderGeneral => 'Share your thoughts…';

  @override
  String get feedbackSubmit => 'Send Feedback';

  @override
  String get feedbackPrivacyNote => 'Your feedback is anonymous and encrypted.';

  @override
  String get feedbackThankYou => 'Thank you!';

  @override
  String get feedbackThankYouMessage =>
      'Your feedback helps us make WhisPaste better\nfor everyone.';

  @override
  String get feedbackSendAnother => 'Send another';

  @override
  String get feedbackRatingFrustrated => 'Frustrated';

  @override
  String get feedbackRatingMeh => 'Meh';

  @override
  String get feedbackRatingOkay => 'Okay';

  @override
  String get feedbackRatingHappy => 'Happy';

  @override
  String get feedbackRatingLoveIt => 'Love it!';

  @override
  String get statusBarOnDevice => 'On device';

  @override
  String get statusBarPostProcessing => 'Post-Processing';

  @override
  String get sttStatusStandby => 'Standby';

  @override
  String get sttStatusStarting => 'Starting…';

  @override
  String get sttStatusReady => 'Ready';

  @override
  String get sttStatusError => 'Error';

  @override
  String get tooltipSwitchToLight => 'Switch to Light Mode';

  @override
  String get tooltipSwitchToDark => 'Switch to Dark Mode';

  @override
  String get modelServerReady => 'Speech engine ready';

  @override
  String get modelServerMissing => 'Speech engine not installed';

  @override
  String get modelServerWhisper => 'Local engine';

  @override
  String get modelReady => 'Ready';

  @override
  String get modelDownload => 'Download';

  @override
  String get modelDownloading => 'Downloading…';

  @override
  String get modelVerifying => 'Verifying…';

  @override
  String get modelExtracting => 'Extracting…';

  @override
  String get modelDeleteConfirm => 'Delete this model?';

  @override
  String get modelDeleteConfirmMessage =>
      'The model file will be permanently removed. You can re-download it any time.';

  @override
  String get modelSizeTiny => 'Quick transcription for short notes';

  @override
  String get modelSizeBase => 'Faster processing, decent accuracy';

  @override
  String get modelSizeSmall => 'Good balance of speed and accuracy';

  @override
  String get modelSizeMedium => 'Excellent accuracy for most use cases';

  @override
  String get modelSizeLargeTurbo => 'Best accuracy with optimized speed';

  @override
  String get modelSizeLarge => 'Maximum accuracy, needs more resources';

  @override
  String get settingsQualityFast => 'Fast';

  @override
  String get settingsQualityBasic => 'Basic';

  @override
  String get settingsQualityBalanced => 'Balanced';

  @override
  String get settingsQualityHigh => 'High Quality';

  @override
  String get settingsQualityBest => 'Best Quality';

  @override
  String get settingsQualityMaximum => 'Maximum Accuracy';

  @override
  String get settingsQualityRecommended => '★ Recommended';

  @override
  String get settingsModelStatusReady => 'Speech model ready';

  @override
  String get settingsModelStatusNeeded =>
      'Speech model will be downloaded when you start recording';

  @override
  String get settingsModelStatusDownloading => 'Downloading speech model…';

  @override
  String get settingsAdvancedModelManagement => 'Advanced model settings';

  @override
  String get settingsPrivacyHintLocal => 'Your voice never leaves your device';

  @override
  String get errorSttServerNotFound =>
      'Speech engine not found. Please download a speech model in Settings.';

  @override
  String get errorSttModelNotFound =>
      'Speech model not found. Please download it in Settings.';

  @override
  String get errorSttModelUnknown =>
      'Unknown speech model. Please select a valid model in Settings.';

  @override
  String get errorRecordingFailed => 'Failed to start recording';

  @override
  String get errorNoAudioRecorded => 'No audio recorded';

  @override
  String get errorTranscriptionEmpty =>
      'Transcription returned empty text — please try again';

  @override
  String get errorSttServerFailed => 'Speech engine failed to start';

  @override
  String get statusSttLoading => 'Loading model…';

  @override
  String get statusSttReady => 'Model ready';

  @override
  String get historyDuplicate => 'Duplicate';

  @override
  String get historyDuplicated => 'Entry duplicated';

  @override
  String get historyAddNote => 'Add note';

  @override
  String get historyNotes => 'Notes';

  @override
  String get historyNotePlaceholder => 'Write a note…';

  @override
  String get historyNoteAdded => 'Note added';

  @override
  String get historyNoteDeleted => 'Note deleted';

  @override
  String get historyCopiedAsMarkdown => 'Copied as Markdown';

  @override
  String get settingsKeyboardShortcut => 'Keyboard Shortcut';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Global hotkey to start and stop recording';

  @override
  String get settingsCurrentHotkey => 'Current Hotkey';

  @override
  String get settingsChangeHotkey => 'Change';

  @override
  String get settingsHotkeyRecorderTitle => 'Record New Hotkey';

  @override
  String get settingsHotkeyRecorderHint =>
      'Press the key combination you want to use…';

  @override
  String get settingsHotkeyRecorderCancel => 'Cancel';

  @override
  String get settingsHotkeyRecorderSave => 'Save';

  @override
  String get settingsHotkeyRecorderClear => 'Clear';

  @override
  String get settingsGeminiApiKey => 'Gemini API Key';

  @override
  String get settingsDefaultSttProvider => 'Default Cloud STT';

  @override
  String get settingsDefaultSttProviderSubtitle =>
      'Cloud speech recognition service';

  @override
  String get settingsLlmModel => 'LLM Model';

  @override
  String get settingsLlmModelSubtitle => 'Model used for cloud post-processing';

  @override
  String get settingsLlmModelPlaceholder => 'e.g. gpt-4o-mini';

  @override
  String get settingsCustomInstructions => 'Custom Instructions';

  @override
  String get settingsCustomInstructionsSubtitle =>
      'Custom prompt for AI post-processing';

  @override
  String get settingsCustomInstructionsPlaceholder =>
      'e.g. Always use formal language…';

  @override
  String get settingsOutputLanguage => 'Output Language';

  @override
  String get settingsOutputLanguageSubtitle =>
      'Force output to a specific language';

  @override
  String get settingsOutputLanguageSameAsInput => 'Same as input';

  @override
  String get settingsMaxRecordDuration => 'Max Recording Duration';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Automatic safety stop after this time';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Unlimited';

  @override
  String get settingsCloseToTray => 'Close to Tray';

  @override
  String get settingsCloseToTraySubtitle =>
      'Keep running in the system tray when closing the window';

  @override
  String get settingsErrorReporting => 'Error Reporting';

  @override
  String get settingsErrorReportingSubtitle =>
      'Help improve WhisPaste by sending anonymous crash reports';

  @override
  String get settingsGpuAcceleration => 'GPU Acceleration';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Use graphics card for faster AI processing';

  @override
  String get settingsGpuAuto => 'Auto-detect';

  @override
  String get settingsGpuEnabled => 'Always On';

  @override
  String get settingsGpuDisabled => 'Disabled';

  @override
  String get settingsAutoPasteDelay => 'Auto-Paste Delay';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Wait time before pasting into the active window';

  @override
  String get settingsTextReplacements => 'Text Replacements';

  @override
  String get settingsTextReplacementsSubtitle =>
      'Automatically replace specific words or phrases after transcription';

  @override
  String get settingsTextReplacementsEnabled => 'Enable Text Replacements';

  @override
  String get settingsCheckUpdates => 'Check for Updates';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Automatically check for new versions on startup';

  @override
  String get settingsFloatingButtonAdvanced =>
      'Advanced Floating Button Options';

  @override
  String get settingsLockPosition => 'Lock Position';

  @override
  String get settingsLockPositionSubtitle => 'Prevent accidental dragging';

  @override
  String get settingsAutoHide => 'Auto-Hide';

  @override
  String get settingsAutoHideSubtitle =>
      'Automatically hide when not recording';

  @override
  String get settingsAutoHideNever => 'Never';

  @override
  String get settingsAutoHide5s => 'After 5 seconds';

  @override
  String get settingsAutoHideEdge => 'Snap to edge';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingLanguageTitle => 'Choose Your Language';

  @override
  String get onboardingLanguageSubtitle =>
      'You can change this later in Settings';

  @override
  String get onboardingThemeTitle => 'Pick Your Theme';

  @override
  String get onboardingThemeLight => 'Light';

  @override
  String get onboardingThemeDark => 'Dark';

  @override
  String get onboardingMicTitle => 'Microphone Setup';

  @override
  String get onboardingMicSubtitle =>
      'WhisPaste needs microphone access to transcribe your voice';

  @override
  String get onboardingMicPermissionGranted => 'Microphone access granted';

  @override
  String get onboardingMicPermissionDenied => 'Microphone access denied';

  @override
  String get onboardingMicPermissionPending => 'Waiting for permission…';

  @override
  String get onboardingMicRequestAccess => 'Grant Access';

  @override
  String get onboardingMicTestTitle => 'Test Your Microphone';

  @override
  String get onboardingMicTestHint => 'Tap to start a test recording';

  @override
  String get onboardingMicTestRecording => 'Recording… speak now';

  @override
  String get onboardingMicTestDone => 'Recording complete! Tap to play back';

  @override
  String get onboardingMicDeviceLabel => 'Audio Input Device';

  @override
  String get onboardingMicDeniedInstructions =>
      'Open your system settings to grant microphone access';

  @override
  String get onboardingModelTitle => 'Speech Recognition Model';

  @override
  String get onboardingModelSubtitle =>
      'Download a model for local, private speech-to-text';

  @override
  String get onboardingModelRecommended => 'Recommended for your device';

  @override
  String get onboardingModelChangeLater =>
      'You can always change the model later in Settings';

  @override
  String get onboardingModelUseCloud => 'Use Cloud API instead';

  @override
  String get onboardingModelDownloading => 'Downloading…';

  @override
  String get onboardingModelReady => 'Model ready';

  @override
  String get onboardingReadyTitle => 'You\'re All Set!';

  @override
  String get onboardingReadySubtitle => 'Here\'s how to use WhisPaste';

  @override
  String get onboardingReadyStep1 => 'Press the hotkey to start recording';

  @override
  String get onboardingReadyStep2 => 'Press again to stop and transcribe';

  @override
  String get onboardingReadyStep3 =>
      'Text is copied to clipboard automatically';

  @override
  String get onboardingReadyChangeHotkey => 'Change Hotkey';

  @override
  String get onboardingReadyCurrentHotkey => 'Current hotkey';

  @override
  String get onboardingStartDictating => 'Start Dictating';

  @override
  String get onboardingPrivacyLocal => 'All processing happens on your device';

  @override
  String get onboardingPrivacyBadge => '100% Private';

  @override
  String get overlayRecording => 'Recording';

  @override
  String get overlayTranscribing => 'Transcribing…';

  @override
  String get overlayRefining => 'Refining…';

  @override
  String get overlayDone => 'Copied';

  @override
  String get overlayDonePasted => 'Pasted';

  @override
  String get overlayDoneBoth => 'Copied & Pasted';

  @override
  String get overlayDoneReady => 'Done';

  @override
  String get overlayError => 'Error';

  @override
  String get overlayCancel => 'Cancel';

  @override
  String get overlayPause => 'Pause';

  @override
  String get overlayResume => 'Resume';

  @override
  String get overlayStop => 'Stop';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'Press $hotkey to stop';
  }

  @override
  String get overlayProcessingLocal => 'Local';

  @override
  String get overlayProcessingCloud => 'Cloud';

  @override
  String get floatingButtonHide => 'Hide';

  @override
  String get floatingButtonQuit => 'Quit';

  @override
  String get trayStatusRecording => 'Recording…';

  @override
  String get trayStatusReady => 'Ready';

  @override
  String get trayStartRecording => 'Start Recording';

  @override
  String get trayStopRecording => 'Stop Recording';

  @override
  String get trayOpenApp => 'Open WhisPaste';

  @override
  String get traySettings => 'Settings';

  @override
  String get trayQuit => 'Quit';
}
