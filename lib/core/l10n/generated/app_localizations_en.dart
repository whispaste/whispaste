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
  String get historyPinned => 'Favorites';

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
  String get historyExportAction => 'Export…';

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
  String historyWordCount(int count) {
    return '$count words';
  }

  @override
  String historyReadingTime(int minutes) {
    return '$minutes min read';
  }

  @override
  String get historyReadingTimeUnder1 => '< 1 min read';

  @override
  String get historyEditing => 'Editing';

  @override
  String get historySearchTranscriptions => 'Search transcriptions…';

  @override
  String get historyNoResults => 'No results';

  @override
  String historyNoResultsHint(String query) {
    return 'No transcriptions match \"$query\".\nTry a different search term.';
  }

  @override
  String get historyClearSearch => 'Clear search';

  @override
  String get historyTrashEmpty => 'Trash is empty';

  @override
  String get historyTrashEmptyHint =>
      'Deleted transcriptions will appear here.\nItems are permanently removed after 30 days.';

  @override
  String get historyEmptyTrash => 'Empty Trash';

  @override
  String get historyEmptyTrashConfirm => 'Empty trash?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'This will permanently delete all items in the trash. This action cannot be undone.';

  @override
  String get historyTrashEmptied => 'Trash emptied';

  @override
  String get historyNoArchivedItems => 'No archived items';

  @override
  String get historyNoArchivedItemsHint =>
      'Archive transcriptions you want to keep\nbut don\'t need in your main list.';

  @override
  String get historyNoRecordingsHint =>
      'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.';

  @override
  String get historyNoPinned => 'No favorites yet';

  @override
  String get historyNoPinnedHint =>
      'Mark a transcription as a favorite to find it here quickly.';

  @override
  String get historyNoToday => 'Nothing recorded today';

  @override
  String get historyNoTodayHint => 'Today\'s transcriptions will appear here.';

  @override
  String get historyNoThisWeek => 'Nothing recorded this week';

  @override
  String get historyNoThisWeekHint =>
      'This week\'s transcriptions will appear here.';

  @override
  String get historyCopiedToClipboard => 'Copied to clipboard';

  @override
  String get historyMovedToTrash => 'Moved to trash';

  @override
  String get historyUndo => 'Undo';

  @override
  String get historyEntriesMerged => 'Entries merged';

  @override
  String historyMergeConfirm(int count) {
    return 'Merge $count entries?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'The selected entries will be combined into one. This cannot be undone.';

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
  String get historyPinToTop => 'Add to Favorites';

  @override
  String get historyUnpin => 'Remove from Favorites';

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
  String get settingsStartMinimized => 'Start Minimized';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Start in the background when launched at system boot';

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
  String get settingsClippingBanner =>
      'Last recording had clipping — reduce gain?';

  @override
  String get settingsClippingDismiss => 'Dismiss';

  @override
  String get settingsHoldToRecord => 'Hold to Record';

  @override
  String get pushToTalkUnavailableTooltip => 'Not available on this platform';

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
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsStyle => 'Style';

  @override
  String get settingsMicSystemDefault => 'System Default';

  @override
  String get settingsMicSystemHint =>
      'Audio input is managed by your system settings';

  @override
  String get settingsServiceOnDevicePrivate => 'Locally on Device';

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
  String get settingsLanguageHebrew => 'Hebrew';

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
  String get settingsDurationWarningSound => 'Duration Limit Warning';

  @override
  String get settingsSoundVolume => 'Sound Volume';

  @override
  String get settingsAfterTranscription => 'After Transcription';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'What happens with the transcribed text';

  @override
  String get settingsAfterTranscriptionActionLabel => 'Action';

  @override
  String get settingsAfterTranscriptionClipboard => 'Copy to Clipboard';

  @override
  String get settingsAfterTranscriptionPaste => 'Auto-Paste at Cursor';

  @override
  String get settingsAfterTranscriptionBoth => 'Copy & Auto-Paste';

  @override
  String get settingsAfterTranscriptionNothing => 'Do Nothing';

  @override
  String get pasteFailurePermissionMissing =>
      'Auto-Paste was blocked by the OS. WhisPaste needs the Accessibility permission to paste into other apps.';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Paste skipped — no target window was captured. Focus the destination app before triggering a recording.';

  @override
  String get pasteFailureGeneric =>
      'Auto-Paste failed. The transcript is on the clipboard — paste it manually with ⌘V / Ctrl+V.';

  @override
  String get pasteFailureOpenSettings => 'Open Settings';

  @override
  String get pasteCapabilityCheckTitle => 'One moment…';

  @override
  String get pasteCapabilityReady => 'All set';

  @override
  String get pasteCapabilityPermissionMissing => 'Not yet allowed';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Paste is not available on this platform';

  @override
  String get pasteCapabilityTestButton => 'Test now';

  @override
  String get pasteCapabilityGrantButton => 'Grant permission';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste needs Accessibility permission to type text into the app you\'re working in.';

  @override
  String get pasteCapabilityTroubleshoot => 'Having trouble?';

  @override
  String get pasteCapabilityRepairHint =>
      'Sometimes macOS remembers an old entry and forgets the new approval. Reset the entry — macOS will then ask you cleanly again.';

  @override
  String get pasteCapabilityRepairButton => 'Reset entry';

  @override
  String get pasteCapabilityRestartButton => 'Restart WhisPaste';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Cleared $count stale entries. Try paste once to see fresh prompts.',
      one: 'Cleared 1 stale entry. Try paste once to see a fresh prompt.',
      zero: 'No stale entries found — try paste once.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'No old entry found. A restart is likely to help now.';

  @override
  String get pasteCapabilityRepairFailed =>
      'Could not run the macOS permission reset. Try removing WhisPaste from System Settings → Accessibility manually.';

  @override
  String get onboardingPasteTitle => 'So your text lands where you\'re typing';

  @override
  String get onboardingPasteSubtitle =>
      'macOS will ask you in a moment whether WhisPaste may do this. Say yes — done.';

  @override
  String get onboardingPasteGrantCta => 'Allow now';

  @override
  String get onboardingPasteVerifyCta => 'Verify';

  @override
  String get onboardingPasteSkip => 'Just copy for now — no auto-insert';

  @override
  String get onboardingPasteWhyMac =>
      'Without permission, your text is copied to the clipboard — you\'ll then paste manually with ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'Windows allows keystroke injection without an extra permission. This step just verifies the bridge works on your machine.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'In certain apps with UIPI/UAC protection, Auto-Paste won\'t work — the text will sit in the clipboard and you\'ll need to paste it with Ctrl+V yourself.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Tick the box next to WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'System Settings is open. Find WhisPaste in the list and switch it on.\n\nNot in the list? Drag the app icon in or click „+\".';

  @override
  String get onboardingPasteTccMismatchTitle =>
      'macOS didn\'t pick up the tick';

  @override
  String get onboardingPasteTccMismatchBody =>
      'Happens sometimes after app updates. A restart fixes it — macOS will then see WhisPaste cleanly.';

  @override
  String get onboardingPasteTestTitle => 'Try Auto-Paste';

  @override
  String get onboardingPasteTestSubtitle =>
      'Click the button — the demo text should appear in the field below.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste types for you.';

  @override
  String get onboardingPasteTestRunCta => 'Run test paste';

  @override
  String get onboardingPasteTestSuccess =>
      'Auto-Paste works! Click Next to continue.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'No input field detected. Click the field below and try again.';

  @override
  String get onboardingPasteTestFailure =>
      'Test failed. Try restarting the app — or continue without testing.';

  @override
  String get onboardingPasteTestSkip => 'Continue without testing';

  @override
  String get settingsOverlayFloatingButton => 'Recording Overlay';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Control how recording status appears while you dictate';

  @override
  String get settingsShowOverlay => 'Recording status display';

  @override
  String get settingsShowOverlaySubtitle =>
      'Choose where live recording feedback appears while you dictate';

  @override
  String get settingsOverlayModeFloating => 'Floating window (always visible)';

  @override
  String get settingsOverlayModeOff => 'Off';

  @override
  String get settingsOverlayStartPosition => 'Overlay start position';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Where the floating overlay appears when recording starts';

  @override
  String get settingsOverlayStartTopCenter => 'Top center';

  @override
  String get settingsOverlayStartBottomCenter => 'Bottom center';

  @override
  String get settingsOverlayStartLastPosition => 'Remember last position';

  @override
  String get settingsShowFloatingButton => 'Floating recording button';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Small always-on-top button for starting or stopping recording from any app';

  @override
  String get settingsFloatingButtonOpacity => 'Floating button opacity';

  @override
  String get settingsFloatingButtonOpacitySubtitle =>
      'Only affects the floating button, not the recording overlay';

  @override
  String get settingsFloatingOverlayOpacity => 'Overlay opacity';

  @override
  String get settingsFloatingOverlayOpacitySubtitle =>
      'Transparency of the floating recording overlay';

  @override
  String get settingsFloatingButtonSize => 'Floating button size';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Choose how prominent the always-on-top button should feel';

  @override
  String get settingsSizeSmall => 'Small';

  @override
  String get settingsSizeNormal => 'Normal';

  @override
  String get settingsSizeLarge => 'Large';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsRecognitionLanguage => 'Recognition Language';

  @override
  String get settingsCustomVocabulary => 'Custom Vocabulary';

  @override
  String get settingsCustomVocabularyHint =>
      'Names, technical terms — improves recognition accuracy';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'e.g. WhisPaste, Kubernetes, Dr. Mueller';

  @override
  String get settingsAppLanguage => 'App Language';

  @override
  String get settingsSttModels => 'Speech Recognition Models';

  @override
  String get settingsOpenAiApiKey => 'OpenAI API Key';

  @override
  String get settingsDeepgramApiKey => 'Deepgram API Key';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsResetToDefaults => 'Reset to Defaults';

  @override
  String get settingsResetTitle => 'Reset Settings';

  @override
  String get settingsResetMessage =>
      'All settings will be restored to defaults. API keys will be removed. This cannot be undone.';

  @override
  String get settingsResetConfirm => 'Reset';

  @override
  String get settingsResetSuccess => 'Settings reset to defaults';

  @override
  String get settingsFactoryReset => 'Factory Reset';

  @override
  String get settingsFactoryResetTitle => 'Factory Reset';

  @override
  String get settingsFactoryResetMessage =>
      'This will permanently delete ALL data: dictation history, tags, voice shortcuts, downloaded models, logs, and settings. The app will return to its initial state.\n\nThis cannot be undone.';

  @override
  String get settingsFactoryResetConfirm => 'Delete Everything';

  @override
  String get settingsFactoryResetSuccess => 'App has been completely reset';

  @override
  String get settingsFactoryResetProgressTitle => 'Resetting WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Stopping voice service…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Deleting voice models…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase => 'Deleting database…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Clearing credentials…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Restoring default settings…';

  @override
  String get settingsFactoryResetFailedMessage =>
      'Factory reset incomplete. Please restart the app.';

  @override
  String get groqRemovedToast =>
      'Groq STT was removed — provider reset to On-Device.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dictations migrated from WhisPaste 1.x',
      one: '1 dictation migrated from WhisPaste 1.x',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Off';

  @override
  String get settingsOn => 'On';

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
      'No audio detected — please try again. Sometimes the microphone needs a moment to warm up.';

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
  String get tooltipEngineNotReady => 'Speech service not ready';

  @override
  String get tooltipEngineDownloading => 'Downloading speech service…';

  @override
  String get tooltipModelMissing => 'No speech model downloaded';

  @override
  String get tooltipTheme => 'Toggle theme';

  @override
  String get tooltipLanguage => 'Language';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Speak it once. Paste it anywhere.';

  @override
  String get onboardingWelcomeHint =>
      'WhisPaste turns quick thoughts into clean text for messages, emails, notes, and comments.';

  @override
  String get feedbackTitle => 'Send Feedback';

  @override
  String get feedbackHint => 'Tell us what you think — we read every message.';

  @override
  String get analyticsPreviewBanner =>
      'Preview — showing sample data. Real analytics will appear once you start recording.';

  @override
  String get analyticsEmptyTitle => 'No recordings yet';

  @override
  String get analyticsEmptySubtitle =>
      'Start dictating to see your analytics here.';

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
  String get replacementsToggleLabel => 'Enable shortcuts';

  @override
  String get replacementsToggleEnabled => 'Voice shortcuts are active';

  @override
  String get replacementsToggleDisabled => 'Voice shortcuts are disabled';

  @override
  String get replacementsEnableBannerTitle => 'Voice shortcuts are turned off';

  @override
  String get replacementsEnableBannerHint =>
      'Enable them so trigger phrases are replaced automatically during dictation.';

  @override
  String get replacementsEnableAction => 'Enable';

  @override
  String get replacementsDisableAction => 'Disable';

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
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Cross-platform UI with Flutter. Local speech recognition via whisper.cpp.';

  @override
  String get aboutWhisper => 'whisper.cpp & OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Local and cloud speech recognition — fast, accurate, multilingual.';

  @override
  String get aboutPrivacyFirst => 'Privacy-first';

  @override
  String get aboutPrivacyFirstDesc =>
      'Local speech recognition by default — your voice never leaves your device unless you choose a cloud provider.';

  @override
  String get aboutPrivacy => 'Privacy & Data';

  @override
  String get aboutPrivacyLocal =>
      'All transcriptions and history are stored locally on your device — never on external servers.';

  @override
  String get aboutPrivacyCloud =>
      'Cloud providers (OpenAI, Deepgram) only receive audio when you actively use them. Their privacy policies apply.';

  @override
  String get aboutPrivacyNoTracking =>
      'No analytics, no tracking, no user accounts. Update checks contact GitHub (version + IP only).';

  @override
  String get aboutKeyboardShortcuts => 'Keyboard Shortcuts';

  @override
  String get aboutShortcutRecord => 'Start / Stop recording';

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
  String get feedbackPlaceholderAi => 'How was the transcription quality?';

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
  String get feedbackSubmitting => 'Sending…';

  @override
  String get feedbackErrorRateLimited =>
      'You already sent feedback recently. Please try again later.';

  @override
  String get feedbackErrorNetwork =>
      'Could not connect to the server. Please check your internet connection.';

  @override
  String get feedbackErrorServer =>
      'Something went wrong. Please try again later.';

  @override
  String get feedbackErrorNotConfigured =>
      'Feedback is not available in this build.';

  @override
  String get statusBarOnDevice => 'On device';

  @override
  String get statusBarOverlayFloating => 'Overlay: Floating';

  @override
  String get statusBarOverlayOff => 'Overlay: Off';

  @override
  String get statusBarAfterCopy => 'After: Copy';

  @override
  String get statusBarAfterPaste => 'After: Paste';

  @override
  String get statusBarAfterBoth => 'After: Copy & Paste';

  @override
  String get statusBarAfterNothing => 'After: Manual';

  @override
  String get sttStatusStandby => 'Standby';

  @override
  String get sttStatusStarting => 'Starting…';

  @override
  String get sttStatusReady => 'Ready';

  @override
  String get sttStatusError => 'Error';

  @override
  String get statusBarSttTooltip => 'Speech service and current status';

  @override
  String get statusBarRecording => 'Recording…';

  @override
  String get statusBarTranscribing => 'Transcribing…';

  @override
  String get statusBarDone => 'Done';

  @override
  String get statusBarHotkeyTooltip => 'Global hotkey — click to configure';

  @override
  String get statusBarAutoPasteOffHint => 'Auto-Paste off — enable in Settings';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste is currently disabled. Click to open Settings.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Dismiss';

  @override
  String get modifierCtrl => 'Ctrl';

  @override
  String get modifierShift => 'Shift';

  @override
  String get modifierAlt => 'Alt';

  @override
  String get modifierWin => 'Win';

  @override
  String get modifierCmd => 'Cmd';

  @override
  String get modifierOption => 'Option';

  @override
  String get shortcutKeySpace => 'Space';

  @override
  String get shortcutKeyEnter => 'Enter';

  @override
  String get shortcutKeyEscape => 'Esc';

  @override
  String get shortcutKeyBackspace => 'Backspace';

  @override
  String get shortcutKeyTab => 'Tab';

  @override
  String get shortcutKeyDelete => 'Del';

  @override
  String get shortcutKeyInsert => 'Insert';

  @override
  String get shortcutKeyHome => 'Home';

  @override
  String get shortcutKeyEnd => 'End';

  @override
  String get shortcutKeyPageUp => 'Page Up';

  @override
  String get shortcutKeyPageDown => 'Page Down';

  @override
  String get tooltipSwitchToLight => 'Switch to Light Mode';

  @override
  String get tooltipSwitchToDark => 'Switch to Dark Mode';

  @override
  String get modelServerReady => 'Speech service ready';

  @override
  String get modelServerMissing => 'Speech service not installed';

  @override
  String get modelServerWhisper => 'Local speech service';

  @override
  String get modelReady => 'Ready';

  @override
  String get modelUse => 'Use';

  @override
  String get modelDownload => 'Download';

  @override
  String get modelDownloading => 'Downloading…';

  @override
  String get modelDownloadingEngine => 'Preparing speech service…';

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
  String get qualityTierCompactLabel => 'Quick & Compact';

  @override
  String get qualityTierCompactDesc =>
      'Fast results, small download. Great for short notes and quick messages.';

  @override
  String get qualityTierBalancedLabel => 'Balanced';

  @override
  String get qualityTierBalancedDesc =>
      'Accurate and reliable for everyday dictation. Works on most devices.';

  @override
  String get qualityTierPremiumLabel => 'Best Quality';

  @override
  String get qualityTierPremiumDesc =>
      'Top accuracy for longer dictation and complex content. Needs a capable GPU.';

  @override
  String get qualityTierRecommended => 'Recommended for your device';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size download';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Download & Continue';

  @override
  String get qualityTierChooseDifferent => 'Choose a different quality level';

  @override
  String get qualityTierActive => 'Active';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Best quality — takes ~${ratio}x longer to process';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Best quality — ~${ratio}x slower than Small';
  }

  @override
  String get qualityTierInfoModerate => 'Good balance of speed and quality';

  @override
  String get qualityTierBenchmarkReRun => 'Re-run benchmark';

  @override
  String get qualityTierBenchmarkRun => 'Run benchmark';

  @override
  String get qualityTierInfoBenchmarking => 'Testing performance…';

  @override
  String get qualityTierActionOverride => 'Use anyway';

  @override
  String get qualityTierActionOverrideHint =>
      'Use this quality level despite the warning';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

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
  String get infoEngineDownloading =>
      'Speech service is being prepared. Please wait a moment.';

  @override
  String get infoEngineAutoDownload =>
      'Speech service missing — downloading automatically…';

  @override
  String get infoModelMissing =>
      'Please download a speech model in Settings first.';

  @override
  String get oomRecoveryTitle => 'Recording failed — GPU memory issue';

  @override
  String get oomRecoveryMessage =>
      'Your GPU ran out of memory. Choose how to proceed:';

  @override
  String get oomRecoveryTrySmaller => 'Try smaller model';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Switch to $model and retry recording';
  }

  @override
  String get oomRecoverySwitchCloud => 'Switch to Cloud';

  @override
  String get oomRecoverySwitchCloudHint =>
      'Use cloud speech recognition instead';

  @override
  String get oomRecoveryCancel => 'Cancel';

  @override
  String get oomRecoveryPermanentTitle =>
      'Local speech recognition unavailable';

  @override
  String get oomRecoveryPermanentMessage =>
      'All local models failed due to GPU memory limits. Please switch to cloud speech recognition in settings.';

  @override
  String get oomRecoveryPermanentCloud => 'Open Settings';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Switching to $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Switching to cloud speech recognition…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Model $model also failed. Trying next option…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'Quality reduced — your GPU ran out of memory. Switched to a lighter model.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Your GPU ran out of memory. Switched to CPU mode for reliability.';

  @override
  String get errorSttServerNotFound =>
      'Speech service not found. Please download a speech model in Settings.';

  @override
  String get errorSttServerConnectionLost =>
      'Speech service stopped unexpectedly. Please try again.';

  @override
  String get errorSttCudaOom =>
      'Your GPU ran out of memory. Quality was reduced so the next try should work.';

  @override
  String get errorCloudAuth =>
      'Cloud API key is missing or invalid. Check it in Settings → Speech Recognition.';

  @override
  String get errorCloudQuota =>
      'Cloud provider rate limit reached. Please wait a moment and try again.';

  @override
  String get errorOnboardingNotCompleted =>
      'Please complete the setup wizard first.';

  @override
  String get errorSttModelNotFound =>
      'Speech model not found. Please download it in Settings.';

  @override
  String get errorSttModelUnknown =>
      'Unknown speech model. Please select a valid model in Settings.';

  @override
  String get errorRecordingFailed =>
      'Could not start recording — please try again';

  @override
  String get errorNoAudioRecorded => 'No audio recorded — please try again';

  @override
  String get errorTranscriptionEmpty =>
      'Transcription returned empty text — please try again';

  @override
  String get errorSttServerFailed => 'Speech service failed to start';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'Speech model is incompatible with the installed runtime. Please re-download the speech model in Settings.';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'Speech model appears corrupted — downloading a fresh copy automatically.';

  @override
  String get errorSttDllMissing =>
      'A required system component is missing. Retrying with CPU mode.';

  @override
  String get errorSttGpuFatal =>
      'GPU acceleration failed. Retrying with CPU mode.';

  @override
  String get errorSttHeapCorruption =>
      'A memory error occurred. Retrying with CPU mode.';

  @override
  String get errorSttCpuFallbackFailed =>
      'Speech service failed on both GPU and CPU. Please restart the app or re-download the model.';

  @override
  String get errorPipelineTimeout =>
      'Recording took too long. Please try a shorter recording.';

  @override
  String get errorWavFileNotCreated =>
      'Could not save the audio file. Please try again.';

  @override
  String get errorWavFileEmpty =>
      'No audio was captured. Please check your microphone.';

  @override
  String get errorSttStartTimeout =>
      'Speech service is still starting. Please try again in a moment.';

  @override
  String get errorTranscriptionTimeout =>
      'Transcription took too long. Please try a shorter recording.';

  @override
  String get errorMicPermissionDenied =>
      'Microphone access is needed. Please allow it in your system settings.';

  @override
  String get errorRecordingStartFailed =>
      'Could not start recording. Please try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get modelDownloadFailed =>
      'Download failed. Please check your internet connection.';

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
  String get historyAddTag => 'Add tag…';

  @override
  String get historySearchTags => 'Search or create…';

  @override
  String get historyNoteEdited => 'edited';

  @override
  String get historyTagAdded => 'Tag added';

  @override
  String get historyTagRemoved => 'Tag removed';

  @override
  String historyCreateTag(Object tag) {
    return 'Create \"$tag\"';
  }

  @override
  String get historyManageTags => 'Manage tags';

  @override
  String get tagManageTitle => 'Manage Tags';

  @override
  String get tagManageEmpty => 'No tags created yet.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'unused',
    );
    return '$_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => 'Delete tag?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'The tag \"$name\" is used in $_temp0. It will be removed from all of them.';
  }

  @override
  String tagDeleted(String name) {
    return 'Tag \"$name\" deleted';
  }

  @override
  String get tagDeleteUnusedTitle => 'Delete unused tags?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unused tags',
      one: '1 unused tag',
    );
    return '$_temp0 will be permanently deleted.';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return 'Delete $count unused';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unused tags',
      one: '1 unused tag',
    );
    return '$_temp0 deleted';
  }

  @override
  String get historyEditTranscript => 'Edit transcript';

  @override
  String get historyTranscriptSaved => 'Transcript saved';

  @override
  String get historySaveTranscript => 'Save';

  @override
  String get historyShortcutHelp => 'Keyboard Shortcuts';

  @override
  String get historyShortcutGeneral => 'GENERAL';

  @override
  String get historyShortcutTags => 'Focus tag input';

  @override
  String get historyShortcutNotes => 'Add a note';

  @override
  String get historyShortcutPin => 'Favorite / unfavorite';

  @override
  String get historyShortcutClose => 'Save & close';

  @override
  String get historyShortcutEditing => 'EDITING';

  @override
  String get historyShortcutToggleEdit => 'Toggle edit mode';

  @override
  String get historyShortcutSave => 'Save transcript';

  @override
  String get historyShortcutBold => 'Bold';

  @override
  String get historyShortcutItalic => 'Italic';

  @override
  String get historyShortcutCopy => 'Copy to clipboard';

  @override
  String get historyShortcutEditTitle => 'Edit title';

  @override
  String get historyEditTitle => 'Edit title';

  @override
  String get historyTitlePlaceholder => 'Enter a title…';

  @override
  String get historyTitleSaved => 'Title saved';

  @override
  String get historySearchHelpTitle => 'Search Tips';

  @override
  String get historySearchHelpTags => 'Type # to filter by tags';

  @override
  String get historySearchHelpLang => 'Type lang: to filter by language';

  @override
  String get historySearchHelpFreeText => 'Or just type any keyword';

  @override
  String get historySearchQuickTags => 'Popular tags';

  @override
  String get historyRecentSearches => 'Recent searches';

  @override
  String get historyQuickActions => 'Quick filters';

  @override
  String get historyQuickActionAllLangs => 'All languages';

  @override
  String get historyQuickActionFavorites => 'Favorites only';

  @override
  String get historySortNewest => 'Newest first';

  @override
  String get historySortOldest => 'Oldest first';

  @override
  String get historySortLongest => 'Longest first';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'Filter by tag';

  @override
  String get historySearchSuggestLang => 'Filter by language';

  @override
  String get settingsKeyboardShortcut => 'Keyboard Shortcut';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Global hotkey to start and stop recording';

  @override
  String get settingsHotkeyEnabled => 'Enable Global Hotkey';

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
  String get settingsHotkeyRecorderModifierHint =>
      'Any modifier combination works — e.g. Alt+Space, Ctrl+Alt+V, or Ctrl+Alt+Shift+R';

  @override
  String get settingsHotkeyRecorderCancel => 'Cancel';

  @override
  String get settingsHotkeyRecorderSave => 'Save';

  @override
  String get settingsHotkeyRecorderClear => 'Clear';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'This key can\'t be used as a hotkey. Try a letter, digit, function key (F1–F12), or an arrow key.';

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
  String get settingsAutoPasteDelay => 'Auto-Paste Delay';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Wait time before pasting into the active window';

  @override
  String get settingsAutoPasteBlocklist => 'Auto-Paste Blocklist';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Comma-separated app identifiers where auto-paste is disabled';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'e.g. com.apple.Terminal, com.1password';

  @override
  String get settingsCheckUpdates => 'Check for Updates';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Automatically check for new versions on startup';

  @override
  String get onboardingGetStarted => 'Continue';

  @override
  String get onboardingSkip => 'Skip this step';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingThemeLight => 'Light';

  @override
  String get onboardingThemeDark => 'Dark';

  @override
  String get onboardingThemeSystem => 'System';

  @override
  String get onboardingMicTitle => 'Let\'s set up your microphone';

  @override
  String get onboardingMicSubtitle =>
      'We need mic access so you can dictate. Your audio stays on your device.';

  @override
  String get onboardingMicPermissionGranted =>
      'You\'re all set — microphone ready!';

  @override
  String get onboardingMicPermissionDenied => 'Microphone access denied';

  @override
  String get onboardingMicPermissionPending =>
      'Tap below to enable your microphone';

  @override
  String get onboardingMicRequestAccess => 'Grant Access';

  @override
  String get onboardingMicTestRecording =>
      'Say something — we\'re checking the level';

  @override
  String get onboardingMicTestDone =>
      'Sounds great — your mic is working perfectly!';

  @override
  String get onboardingMicSilent =>
      'We can\'t hear anything. Pick the right microphone below or speak louder and try again.';

  @override
  String get onboardingMicRetry => 'Try again';

  @override
  String get onboardingMicDeviceLabel => 'Microphone';

  @override
  String get onboardingMicDeviceSystemDefault => 'System default';

  @override
  String get onboardingMicDeniedInstructions =>
      'Open your system settings to grant microphone access';

  @override
  String get onboardingModelTitle => 'Set up speech recognition';

  @override
  String get onboardingModelSubtitle =>
      'Download the speech model to dictate offline — your voice never leaves your device.';

  @override
  String get onboardingModelRecommended => 'Recommended for your device';

  @override
  String get onboardingModelChangeLater =>
      'You can adjust quality later in Settings';

  @override
  String get onboardingModelUseCloud =>
      'Skip — I\'ll use a cloud service instead';

  @override
  String get onboardingModelDownloading => 'Downloading…';

  @override
  String get onboardingModelReady => 'Model ready';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Optimised GPU acceleration unavailable — app will use the CPU';

  @override
  String get onboardingReadyTitle => 'You\'re All Set!';

  @override
  String get onboardingReadySubtitle => 'Here\'s how to use WhisPaste';

  @override
  String get onboardingReadyStep1 => 'Press the hotkey to start recording';

  @override
  String get onboardingReadyStep2 => 'Press again to stop and transcribe';

  @override
  String get onboardingReadyStep3AutoPaste =>
      'Text flows straight into the active app';

  @override
  String get onboardingReadyStep3CopyOnly =>
      'Text is in your clipboard — press ⌘V / Ctrl+V to paste';

  @override
  String get onboardingReadyChangeHotkey => 'Change Hotkey';

  @override
  String get onboardingReadyCurrentHotkey => 'Current hotkey';

  @override
  String get onboardingReadyHotkeyConflictTitle => 'Hotkey already in use';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Your hotkey seems to be in use by another app. Record a new combination below to continue.';

  @override
  String get onboardingStartUsing => 'Let\'s go';

  @override
  String get overlayRecording => 'Recording';

  @override
  String get overlayTranscribing => 'Transcribing…';

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

  @override
  String get settingsComingSoon => 'Coming Soon';

  @override
  String get undo => 'Undo';

  @override
  String get voiceNoteButton => 'Voice note';

  @override
  String get voiceNoteRecording => 'Recording voice note…';

  @override
  String get voiceNoteTranscribing => 'Transcribing…';

  @override
  String get voiceNoteAdded => 'Voice note added';

  @override
  String voiceTagAdded(String tag) {
    return 'Tag \"$tag\" added by voice';
  }

  @override
  String get voiceCorrectionApplied => 'Transcript corrected by voice';

  @override
  String get voiceNoteEmpty => 'No speech detected';

  @override
  String get voiceNoteError => 'Voice note failed';

  @override
  String updateAvailable(String version) {
    return 'Update available: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Downloading update… $percent%';
  }

  @override
  String get updateReadyToInstall => 'Update ready — click to install';

  @override
  String get updateUpToDate => 'You\'re on the latest version';

  @override
  String get updateCheckNow => 'Check Now';

  @override
  String get updateInstall => 'Install Update';

  @override
  String get updateDownload => 'Download';

  @override
  String get updateViewRelease => 'Release Notes';

  @override
  String get updateError => 'Update check failed';

  @override
  String get updateRateLimited => 'Too many requests — try again later';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version available';
  }

  @override
  String get settingsOverlaySize => 'Overlay size';

  @override
  String get settingsOverlaySizeSubtitle =>
      'Choose between detailed or minimal display';

  @override
  String get settingsOverlaySizeNormal => 'Normal';

  @override
  String get settingsOverlaySizeCompact => 'Compact';

  @override
  String get settingsOverlayAutoHide => 'Auto-hide delay';

  @override
  String get settingsOverlayAutoHideSubtitle =>
      'How long the overlay stays visible after completion';

  @override
  String get settingsOverlayAutoHide2s => '2 seconds';

  @override
  String get settingsOverlayAutoHide5s => '5 seconds';

  @override
  String get settingsOverlayAutoHide10s => '10 seconds';

  @override
  String get settingsOverlayAutoHideManual => 'Until dismissed';

  @override
  String get overlayRetry => 'Retry';

  @override
  String get overlayDismiss => 'Dismiss';

  @override
  String get overlayContextCancel => 'Cancel recording';

  @override
  String get overlayContextSwitchNormal => 'Switch to Normal';

  @override
  String get overlayContextSwitchCompact => 'Switch to Compact';

  @override
  String get overlayContextHide => 'Hide overlay';

  @override
  String get buttonContextOpen => 'Open WhisPaste';

  @override
  String get buttonContextStartRecording => 'Start Recording';

  @override
  String get buttonContextShowHistory => 'Show History';

  @override
  String get buttonContextSettings => 'Settings';

  @override
  String get buttonContextQuit => 'Quit WhisPaste';

  @override
  String get settingsHistory => 'History';

  @override
  String get settingsHistorySubtitle => 'Retention and automatic cleanup';

  @override
  String get settingsHistoryMaxEntries => 'Maximum entries';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'Unlimited';

  @override
  String get settingsHistoryAutoTrashDays => 'Auto-delete trash after';

  @override
  String get settingsHistoryAutoTrashNever => 'Never';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get settingsFloatingButtonSection => 'Floating Button';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Always-on-top recording button for quick access';

  @override
  String get settingsSttIdleTimeout => 'Engine idle timeout';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'How long the speech service stays loaded after use';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Keep alive';

  @override
  String settingsSttIdleTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get reviewPromptTitle => 'Are you enjoying WhisPaste?';

  @override
  String get reviewPromptBody =>
      'Your rating helps others discover it and keeps development going.';

  @override
  String get reviewPromptYes => 'Loving it!';

  @override
  String get reviewPromptNotNow => 'Not now';

  @override
  String get reviewPromptNever => 'Never ask again';

  @override
  String get reviewPromptStarGitHub => '⭐ Star on GitHub';

  @override
  String get reviewPromptRateStore => '★ Rate on the Store';

  @override
  String get insufficientRamTitle => 'Not Enough Memory';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'WhisPaste requires at least $requiredGb GB of RAM to run. Your system has $detectedGbString GB.\n\nWith less memory, the AI transcription engine may fail to load or crash mid-session.';
  }

  @override
  String get insufficientRamQuit => 'Quit WhisPaste';

  @override
  String get insufficientRamLearnMore => 'System requirements';

  @override
  String get insufficientRamSystemCheck => 'System Check';

  @override
  String get insufficientRamYourSystem => 'Your system';

  @override
  String get insufficientRamRequired => 'Required';

  @override
  String get hotkeyRegistrationFailed =>
      'Hotkey registration failed — please re-bind your shortcut in Settings.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'Hotkey registration failed — using Ctrl+Shift+Space as fallback. Please re-bind in Settings.';

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'This shortcut is reserved by $platform ($note) and may not work.';
  }

  @override
  String get exportFormatPickerTitle => 'Choose Export Format';

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
  String get recoveryExhaustedToast =>
      'Voice service cannot start. Please restart the app or reload the voice model.';

  @override
  String get recoveryExhaustedAction => 'Open settings';

  @override
  String get recoveryVcRuntimeToast =>
      'Voice service cannot start: a Windows component is missing (Microsoft Visual C++). Please install the Visual C++ Redistributable (x64) and restart WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Install';

  @override
  String get modelAbiInfoToast => 'Reloading voice model — please wait.';

  @override
  String get serverDownloadFailedToast =>
      'Voice service could not be downloaded. Check your internet connection?';

  @override
  String get serverDownloadFailedAction => 'Try again';

  @override
  String get serverDownloadStalledToast => 'Download stalled — reconnecting.';

  @override
  String get historyWriteFailedToast =>
      'Entry could not be saved — please check available storage.';

  @override
  String get historyWriteFailedAction => 'Copy diagnostics';

  @override
  String get factoryResetFailedToast =>
      'Factory reset incomplete. Restart the app?';

  @override
  String get factoryResetFailedAction => 'Quit app';

  @override
  String get errorSttRejectEmpty =>
      'No audio to transcribe — please record again.';

  @override
  String get errorSttRejectInvalidWav =>
      'Audio file is corrupted — please record again.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'This language is not supported by the local speech model — please review the language in Settings.';

  @override
  String get errorSttRejectPromptTooLong =>
      'Custom vocabulary is too long — please shorten it in Settings.';

  @override
  String get settingsGpuAcceleration => 'Graphics Acceleration';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Controls whether the speech service uses GPU or CPU for local recognition';

  @override
  String get settingsGpuAccelerationAuto => 'Automatic (recommended)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (force)';

  @override
  String get settingsGpuAccelerationDisabled => 'CPU only';
}
