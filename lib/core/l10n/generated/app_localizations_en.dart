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
  String get navHistory => 'Recordings';

  @override
  String get navNotes => 'Notes';

  @override
  String get navSettings => 'Settings';

  @override
  String get navReplacements => 'Dictionary';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navAnalytics => 'Statistics';

  @override
  String get navHelp => 'Help';

  @override
  String get actionOpen => 'Open';

  @override
  String actionOpenNamed(String name) {
    return 'Open $name';
  }

  @override
  String get helpTabManual => 'Handbook';

  @override
  String get helpTabIntro => 'Introduction';

  @override
  String get helpTabSupport => 'Support';

  @override
  String get helpTabDiagnostics => 'Diagnostics';

  @override
  String get manualSearchHint => 'Search the handbook';

  @override
  String get manualSearchEmpty => 'No chapter matches this search.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters found',
      one: '1 chapter found',
      zero: 'No chapters found',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'Recordings';

  @override
  String get pageSettingsTitle => 'Settings';

  @override
  String get pageReplacementsTitle => 'Dictionary';

  @override
  String get pageAnalyticsTitle => 'Analytics';

  @override
  String get pageAboutTitle => 'About WhisPaste';

  @override
  String get pageFeedbackTitle => 'Feedback';

  @override
  String get historyEmpty => 'No recordings yet';

  @override
  String get historyEmptyHint =>
      'Press the record button or use the hotkey to start recording.';

  @override
  String get historyPrivacyGateTitle => 'Recordings hidden';

  @override
  String get historyPrivacyGateHint =>
      'Transcriptions and audio are only hidden, not deleted, until you choose to show them.';

  @override
  String get historyPrivacyGateShow => 'Show recordings';

  @override
  String get historySearch => 'Search…';

  @override
  String get historyPinned => 'Favorites';

  @override
  String get historyToday => 'Today';

  @override
  String get historyYesterday => 'Yesterday';

  @override
  String get historyThisWeek => 'This week';

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
  String get historyDeletePermanently => 'Delete permanently';

  @override
  String get historyUnarchive => 'Unarchive';

  @override
  String get historyExport => 'Export';

  @override
  String get historyExportAction => 'Export…';

  @override
  String historyExportDone(String path) {
    return 'Exported to $path';
  }

  @override
  String get historyExportFailed =>
      'Export failed. Check that the target folder is writable and try again.';

  @override
  String get historyCopyAsMarkdown => 'Copy as Markdown';

  @override
  String get historyDetail => 'Detail';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Duration';

  @override
  String get historyModel => 'Speech model';

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
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'approx. $count words',
      one: 'approx. 1 word',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'View and selection';

  @override
  String get historyEditing => 'Editing';

  @override
  String get historySearchTranscriptions => 'Search recordings…';

  @override
  String get historySearchFieldLabel => 'Search transcriptions';

  @override
  String get historyNewRecording => 'New recording';

  @override
  String get historyStopRecording => 'Stop recording';

  @override
  String get historyNoResults => 'No results';

  @override
  String historyNoResultsHint(String query) {
    return 'No entries match \"$query\".\nTry a different search term.';
  }

  @override
  String get historyTrashEmpty => 'Trash is empty';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Items are permanently removed after $days days.',
      one: 'Items are permanently removed after 1 day.',
      zero: 'Items stay until you delete them for good.',
    );
    return 'Deleted transcriptions will appear here.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'Empty trash';

  @override
  String get historyEmptyTrashConfirm => 'Empty trash?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count transcriptions will be permanently deleted. Any saved audio files for them are removed no later than 30 days after recording. This action cannot be undone.',
      one:
          '1 transcription will be permanently deleted. Any saved audio file for it is removed no later than 30 days after recording. This action cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => 'Delete permanently?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count transcriptions and their saved audio will be permanently deleted. This action cannot be undone.',
      one:
          '1 transcription and its saved audio will be permanently deleted. This action cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Trash emptied — $count transcriptions deleted',
      one: 'Trash emptied — 1 transcription deleted',
    );
    return '$_temp0';
  }

  @override
  String get historyNoArchivedItems => 'No archived items';

  @override
  String get historyNoArchivedItemsHint =>
      'Archive transcriptions you want to keep\nbut don\'t need in your main list.';

  @override
  String get historyNoRecordingsHint =>
      'Press the record button or use the hotkey to start recording.\nYour transcriptions will appear here.';

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
  String get historyRestored => 'Restored';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcriptions archived',
      one: '1 transcription archived',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcriptions moved to trash',
      one: '1 transcription moved to trash',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcriptions restored',
      one: '1 transcription restored',
    );
    return '$_temp0';
  }

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
  String get historyShowAll => 'Show all';

  @override
  String get historyMoreActions => 'More actions';

  @override
  String get historyMdTags => 'Tags';

  @override
  String get historyMdDate => 'Date';

  @override
  String get historyMdModel => 'Model';

  @override
  String get historyPinToTop => 'Add to favorites';

  @override
  String get historyUnpin => 'Remove from favorites';

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
  String get historySelectAll => 'Select all';

  @override
  String get historyDeselectAll => 'Deselect all';

  @override
  String get settingsInterface => 'Interface';

  @override
  String get settingsInterfaceSubtitle => 'Appearance and behavior';

  @override
  String get settingsReviewPromptRestore => 'Show the rating reminder again';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'You chose “Never ask again”. Turning this on allows the reminder again; the usual pauses still apply.';

  @override
  String get settingsLaunchAtStartup => 'Launch at startup';

  @override
  String get settingsStartMinimized => 'Start minimized';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Start in the background when launched at system boot';

  @override
  String get settingsAutostartNever => 'Never';

  @override
  String get settingsAutostartNormal => 'Normal';

  @override
  String get settingsAutostartMinimized => 'Minimized';

  @override
  String get settingsAutostartSyncFailed =>
      'Autostart couldn\'t be registered with the operating system. This may be a permissions issue or your OS version isn\'t supported.';

  @override
  String get settingsShowNotifications => 'Show notifications';

  @override
  String get settingsShowBackendUtilization =>
      'Processing indicator in status bar';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Shows whether the processor or the graphics card is doing the work.';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Microphone and recording';

  @override
  String get settingsMicrophone => 'Microphone';

  @override
  String get settingsGain => 'Microphone sensitivity';

  @override
  String get settingsClippingBanner =>
      'Last recording had clipping. Reduce gain?';

  @override
  String get settingsClippingDismiss => 'Dismiss';

  @override
  String get settingsHoldToRecord => 'Hold to record';

  @override
  String get pushToTalkUnavailableTooltip => 'Not available on this platform';

  @override
  String get pushToTalkUnavailableLinuxTooltip =>
      'Your desktop doesn\'t report key releases here. Bind “whispaste --toggle” to a key combination in your system settings instead.';

  @override
  String get settingsExperimentalBadge => 'Experimental';

  @override
  String get settingsHoldOrTap => 'Tap or hold';

  @override
  String get settingsHoldOrTapHint =>
      'A short tap starts and stops recording; holding records until you let go.';

  @override
  String get settingsSpeechRecognition => 'Speech recognition';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Voice recognition quality and service';

  @override
  String get settingsService => 'Recognition runs on';

  @override
  String get settingsQuality => 'Speed & accuracy';

  @override
  String get settingsRecordingSafety => 'Recording safety';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Automatic checks and safeguards';

  @override
  String get settingsDeadMicTimeout => 'Silent mic detection';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Stop recording if no audio detected within this time (seconds). 0 = disabled.';

  @override
  String get settingsAutoStopSilence => 'Auto-Stop after silence';

  @override
  String get settingsAutoStopSilenceHint =>
      'Automatically stop after this many seconds of silence (after speech). 0 = disabled.';

  @override
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsStyle => 'Style';

  @override
  String get settingsMicSystemDefault => 'System default';

  @override
  String get settingsMicSystemHint =>
      'Audio input is managed by your system settings';

  @override
  String get settingsServiceOnDevicePrivate => 'Locally on device';

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
  String get settingsSoundFeedback => 'Sound & feedback';

  @override
  String get settingsSoundFeedbackSubtitle => 'Audio cues for recording events';

  @override
  String get settingsSoundsEnabled => 'Sounds';

  @override
  String get settingsRecordStartSound => 'Record start sound';

  @override
  String get settingsRecordStopSound => 'Record stop sound';

  @override
  String get settingsTranscriptionCompleteSound =>
      'Transcription complete sound';

  @override
  String get settingsDurationWarningSound => 'Duration limit warning';

  @override
  String get settingsSoundVolume => 'Sound volume';

  @override
  String get settingsAfterTranscription => 'After transcription';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'What happens with the transcribed text';

  @override
  String get settingsAfterTranscriptionActionLabel => 'After recording';

  @override
  String get settingsAfterTranscriptionClipboard => 'Copy to clipboard';

  @override
  String get settingsAfterTranscriptionPaste => 'Auto-Paste at cursor';

  @override
  String get settingsAfterTranscriptionBoth => 'Copy & Auto-Paste';

  @override
  String get settingsAfterTranscriptionNothing => 'Do nothing';

  @override
  String get pasteFailurePermissionMissing =>
      'Auto-Paste was blocked by the OS. WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'.';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Paste skipped, no target window was captured. Focus the destination app before triggering a recording.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Paste blocked: the target app is running with administrator rights. Restart WhisPaste as an administrator to paste into that app.';

  @override
  String pasteFailureGeneric(String paste) {
    return 'Auto-Paste failed. The transcript is on the clipboard, paste it manually with $paste.';
  }

  @override
  String get pasteFailureOpenSettings => 'Open Settings';

  @override
  String get pendingAudioSaveLater =>
      'The recording could not be saved to Recordings. The audio is kept and saved again the next time WhisPaste starts.';

  @override
  String get pendingAudioRecovered =>
      'A recording that could not be saved before is now in Recordings.';

  @override
  String get pasteNotificationNoTargetTitle => 'WhisPaste: Auto-Paste skipped';

  @override
  String get pasteNotificationNoTargetBody =>
      'No target app detected. Focus the destination app first, then start recording. The text is on the clipboard.';

  @override
  String get pasteNotificationNoTargetTray => 'Auto-Paste: Target app missing';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: No microphone signal';

  @override
  String get silentMicrophoneNotificationBody =>
      'The microphone delivers no sound. Check the selected microphone or whether it is muted. Recording continues.';

  @override
  String get pasteNotificationRestartNeededTitle => 'WhisPaste: Restart needed';

  @override
  String get pasteNotificationRestartNeededBody =>
      'The permission was granted, but WhisPaste is still running the old state. Click here to restart WhisPaste.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'Auto-Paste blocked — restart needed';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: Auto-Paste blocked';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'. Click here: WhisPaste will clear a possibly stale entry and let macOS ask again.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'. Click here or the tray icon to open System Settings.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'Auto-Paste blocked — open System Settings';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: Auto-Paste blocked';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'The target app is running with administrator rights. Restart WhisPaste as an administrator too, to paste into that app.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'Auto-Paste blocked — administrator needed';

  @override
  String get pasteNotificationFailedTitle => 'WhisPaste: Auto-Paste failed';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'The system blocked the paste key. The text is on the clipboard. Paste it yourself with $paste.';
  }

  @override
  String get pasteNotificationFailedTray => 'Auto-Paste failed';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'WhisPaste can\'t use the virtual keyboard device /dev/uinput yet. The text is on the clipboard, paste it with $paste. Click here to set it up.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'Auto-Paste blocked — setup needed';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'Auto-Paste unavailable: this system has no virtual keyboard device for it. The text is on the clipboard, paste it with $paste. Click here for the Auto-Paste settings.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray => 'Auto-Paste unavailable';

  @override
  String get pasteCapabilityCheckTitle => 'One moment…';

  @override
  String get pasteCapabilityReady => 'All set';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Your text lands right at the cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Not yet allowed';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Paste is not available on this platform';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'Auto-paste isn\'t possible here right now';

  @override
  String get pasteCapabilityTestButton => 'Test now';

  @override
  String get pasteCapabilityGrantButton => 'Continue';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste needs permission to type text into the app you\'re working in — macOS calls this permission \'Accessibility\'.';

  @override
  String get pasteCapabilityTroubleshoot => 'Having trouble?';

  @override
  String get pasteCapabilityRepairHint =>
      'Sometimes macOS remembers an old entry and forgets the new approval. Reset the entry. macOS will then ask you cleanly again.';

  @override
  String get pasteCapabilityRepairButton => 'Reset entry';

  @override
  String get pasteCapabilityRestartButton => 'Restart WhisPaste';

  @override
  String get pasteCapabilityRestartTitle => 'Almost there — restart WhisPaste';

  @override
  String get pasteCapabilityRestartBody =>
      'If you enabled the permission, macOS only applies it to a freshly started app. One click — WhisPaste quits and comes right back.';

  @override
  String get pasteRestartAlertTitle => 'Restart WhisPaste now';

  @override
  String get pasteRestartAlertBody =>
      'The Auto-Paste permission is set, but macOS only applies it after a restart. WhisPaste will quit and come right back.';

  @override
  String get pasteRestartAlertConfirm => 'Restart now';

  @override
  String get pasteStaleEntryGuideTitle => 'Remove the old WhisPaste entry';

  @override
  String get pasteStaleEntryGuideBody =>
      'macOS is still holding on to the Auto-Paste permission of an earlier WhisPaste version. That entry can\'t be switched on — it has to be removed once:\n\n1. Select “WhisPaste” in the list.\n2. Click “−” below the list.\n3. Come back to WhisPaste.\n\nAfter a restart, macOS asks you again — just allow it.';

  @override
  String get pasteStaleEntryGuideConfirm => 'Open System Settings';

  @override
  String get pasteStaleEntryRestartTitle => 'Restart WhisPaste';

  @override
  String get pasteStaleEntryRestartBody =>
      'Once the old entry is gone, restart WhisPaste. macOS then asks for the permission again — confirm it and switch WhisPaste on.';

  @override
  String get pasteStaleEntryRestartConfirm => 'Restart WhisPaste';

  @override
  String get permissionAlertLaterButton => 'Not now';

  @override
  String get micGateAlertTitle => 'Microphone access is missing';

  @override
  String get micGateAlertBody =>
      'WhisPaste can\'t record without microphone access. Confirm to open System Settings → Privacy & Security → Microphone — enable the switch for WhisPaste there. WhisPaste detects your approval automatically.';

  @override
  String get micGateAlertBodyGeneric =>
      'WhisPaste can\'t record without microphone access. Please allow microphone access for WhisPaste in your system\'s privacy settings — WhisPaste detects your approval automatically.';

  @override
  String get micGateAlertConfirm => 'Open Settings';

  @override
  String get micGateRestartAlertTitle => 'Restart WhisPaste to finish';

  @override
  String get micGateRestartAlertBody =>
      'Microphone access is granted, but this running WhisPaste instance can\'t pick it up yet. WhisPaste will quit and come right back — everything stays as it is.';

  @override
  String get micGateRestartAlertConfirm => 'Restart now';

  @override
  String get autoPasteGateAlertTitle => 'One switch is missing for auto-insert';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste inserts your text right at the cursor. macOS requires one switch for that which only you can flip: System Settings → Privacy & Security → Accessibility. Confirm to open exactly that page — WhisPaste detects your approval automatically and restarts itself afterwards if needed.';

  @override
  String get autoPasteGateAlertConfirm => 'Open System Settings';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'The restart didn\'t apply the permission';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'Open the permission again and check under System Settings → Privacy & Security → Accessibility that WhisPaste is really switched on. Re-enable the toggle, then WhisPaste restarts once more.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Cleared $count stale entries. Try paste once to see fresh prompts.',
      one: 'Cleared 1 stale entry. Try paste once to see a fresh prompt.',
      zero: 'No stale entries found. Try paste once.',
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
      'macOS will ask you in a moment whether WhisPaste may do this. Say yes, done.';

  @override
  String get onboardingPasteSubtitleWin =>
      'No permission needed on Windows — just choose whether WhisPaste should insert your text for you.';

  @override
  String get onboardingPasteSubtitleLinux =>
      'On Linux no system dialog asks for permission. Below you can see whether you need to set up anything for it.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste ready';

  @override
  String get onboardingPasteChipPending => 'Auto-Paste access pending';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: action needed';

  @override
  String get onboardingPasteGrantCta => 'Allow auto-paste';

  @override
  String get onboardingPasteSkip => 'Just copy for now, no auto-insert';

  @override
  String get onboardingPasteWhyMac =>
      'Without permission, your text is copied to the clipboard. You\'ll then paste manually with ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'Auto-Paste presses Ctrl+V for you after each recording, so the text lands right where you\'re typing. Verified working on this machine — turn it on below.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'In programs running as administrator, Auto-Paste won\'t work. The text then stays on the clipboard, and you paste it yourself with Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'Auto-Paste is on';

  @override
  String get onboardingPasteWinOnDetail =>
      'After each recording, WhisPaste presses Ctrl+V for you — the text lands right at your cursor. A copy stays on the clipboard, too.';

  @override
  String get onboardingPasteLinuxNative =>
      'Auto-paste needs your permission for the virtual keyboard (/dev/uinput). With the .deb package, choose “Allow (administrator password)” and enter your administrator password; otherwise copy the command and run it once in a terminal. You can remove the permission again in the settings.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'In the Flatpak build, --device=all makes /dev/input/* and /dev/uinput visible inside the sandbox. WhisPaste itself reads no input devices. If your user has read rights on the host (e.g. as a member of the input group), the app could read keystrokes of other programs. Auto-paste also needs write access to /dev/uinput on the host: copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules, which gives access only to the signed-in session. The command needs administrator rights (sudo) and changes the system. If you do not want this, leave auto-paste off and paste the text by hand.';

  @override
  String get onboardingPasteLinuxSnap =>
      'In the Snap build, run this once in a terminal: sudo snap connect whispaste:uinput. Until then, auto-paste only copies the text.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'The AppImage needs access to /dev/uinput (the virtual keyboard device). Copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/ and runs sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. The rule gives write access only to the signed-in session. The command needs administrator rights (sudo) and changes the system. Until then, auto-paste only copies the text.';

  @override
  String get onboardingPasteWinEnableCta => 'Turn on Auto-Paste';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'In programs running as administrator, Auto-Paste won\'t work. The text then stays on the clipboard, and you paste it yourself with Ctrl+V.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'Auto-Paste is on. Until access is set up, WhisPaste puts the text on the clipboard, and you paste it yourself with Ctrl+V.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'The text goes to the clipboard. Paste it with $shortcut.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Tick the box next to WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'System Settings is open. Find WhisPaste in the list and switch it on.\n\nNot in the list? Drag the app icon in or click „+\".';

  @override
  String get onboardingPasteTestTitle => 'Try Auto-Paste';

  @override
  String get onboardingPasteTestSubtitle =>
      'Click the button. The demo text should appear in the field below.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste types for you.';

  @override
  String get onboardingPasteTestSuccess =>
      'Auto-Paste works! Click Next to continue.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'No input field detected. Click the field below and try again.';

  @override
  String get onboardingPasteTestFailure =>
      'Test failed. Try restarting the app, or continue without testing.';

  @override
  String get onboardingPasteTestSkip => 'Continue without testing';

  @override
  String get settingsOverlayFloatingButton => 'Recording overlay';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Control how recording status appears while you record';

  @override
  String get settingsShowOverlay => 'Recording status display';

  @override
  String get settingsShowOverlaySubtitle =>
      'Choose where live recording feedback appears while you record';

  @override
  String get settingsOverlayModeFloating => 'Floating (always visible)';

  @override
  String get settingsOverlayModeOff => 'Off';

  @override
  String get settingsOverlayStartPosition => 'Overlay start position';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Where the recording overlay appears when recording starts';

  @override
  String get settingsOverlayStartTopCenter => 'Top center';

  @override
  String get settingsOverlayStartBottomCenter => 'Bottom center';

  @override
  String get settingsOverlayStartLastPosition => 'Remember last position';

  @override
  String get settingsShowFloatingButton => 'Floating button';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Small always-on-top button for starting or stopping recording from any app';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsRecognitionLanguage => 'Recognition language';

  @override
  String get settingsCustomVocabulary => 'Custom vocabulary';

  @override
  String get settingsCustomVocabularyHint =>
      'Names, technical terms: improves recognition accuracy';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'e.g. WhisPaste, Kubernetes, Dr. Mueller';

  @override
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return '~$count of $budget used';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'If the list takes up more than $budget, the rest is left out automatically.';
  }

  @override
  String get settingsPunctuationPriming => 'Punctuation priming';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Makes the recognition more likely to add punctuation when no custom vocabulary is set. Speed is not affected.';

  @override
  String get settingsVadEnabled => 'Trim trailing silence';

  @override
  String get settingsVadEnabledSubtitle =>
      'Cuts long silence and noise at the end of a recording, so the recognition can\'t invent a closing sentence (e.g. “Thanks for watching”).';

  @override
  String get settingsStripPunctuation => 'Strip punctuation';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Removes periods, commas, and other sentence punctuation from every transcript before it\'s saved or pasted. Numbers like 3.5 stay as they are. Works the same for every recognition method.';

  @override
  String get settingsNumericOnlyMode => 'Numbers only';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Converts spoken numbers (German and English) to digits, e.g. \"five point two\" becomes \"5.2\". Leaves the transcript untouched if it isn\'t fully convertible.';

  @override
  String get settingsRemoveFillerWords => 'Remove filler words';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'Removes hesitation sounds such as \"uh\", \"um\" and \"erm\" before the transcript is saved or pasted. Only unambiguous English and German fillers; words that can carry meaning are never touched.';

  @override
  String get settingsVoiceLineBreaks => 'Spoken line breaks';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'Turns spoken commands such as \"new paragraph\" and \"new line\" into real line breaks. Uses the transcription language, or all supported languages with auto-detect.';

  @override
  String get settingsSpokenPunctuation => 'Spoken punctuation';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'If you say \"comma\" or \"full stop\" as a word in a sentence, check the text afterwards.';

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsSttModels => 'Speech models';

  @override
  String get settingsOpenAiApiKey => 'OpenAI API key';

  @override
  String get settingsDeepgramApiKey => 'Deepgram API key';

  @override
  String get settingsToggleApiKeyVisibility => 'Toggle API key visibility';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsAdvancedSubtitle =>
      'Reset, error reporting, updates, and system behavior';

  @override
  String get settingsResetToDefaults => 'Reset to defaults';

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
  String get settingsFactoryReset => 'Reset everything';

  @override
  String get settingsFactoryResetTitle => 'Factory reset';

  @override
  String get settingsFactoryResetMessage =>
      'This immediately deletes: transcriptions with their tags and notes, saved audio files, Dictionary, Snippets, Statistics, API keys, downloaded models, logs and settings. The app will return to its initial state.\n\nThe app cannot restore any of it. Files are removed with a normal delete and not overwritten, so specialist tools may be able to recover parts of them.';

  @override
  String get settingsFactoryResetConfirm => 'Delete everything';

  @override
  String get settingsFactoryResetSuccess => 'App has been completely reset';

  @override
  String get settingsFactoryResetProgressTitle => 'Resetting WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Stopping speech model…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Deleting voice models…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio => 'Deleting recordings…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase => 'Deleting database…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Clearing credentials…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Restoring default settings…';

  @override
  String settingsFactoryResetFailedMessage(String areas) {
    return 'The reset is incomplete. Affected: $areas. You can try again.';
  }

  @override
  String get factoryResetAreaDb =>
      'Transcriptions, Notes, Dictionary, Snippets and Statistics';

  @override
  String get factoryResetAreaAudio => 'Audio files';

  @override
  String get factoryResetAreaModels => 'Models and logs';

  @override
  String get factoryResetAreaSecure => 'API keys';

  @override
  String get factoryResetAreaSettings => 'Settings';

  @override
  String get factoryResetAreaProcess => 'Background process';

  @override
  String get factoryResetRetryAction => 'Try again';

  @override
  String get factoryResetKeyringHint =>
      'The API keys could not be removed from the keyring. If needed, delete the entries starting with “wp_” yourself in your system\'s password manager.';

  @override
  String get settingsPortabilitySectionTitle => 'Backup & transfer';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'Keep a backup of your WhisPaste setup or take it to another computer';

  @override
  String get settingsPortabilityExportAction => 'Export';

  @override
  String get settingsPortabilityImportAction => 'Import';

  @override
  String get settingsPortabilityExportLocationLabel => 'Export destination';

  @override
  String get settingsPortabilityImportLocationLabel => 'Import source';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'You\'ll be asked on first export';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'You\'ll be asked on first import';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'Choose a different export destination (nothing is exported yet)';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'Choose a different import source (nothing is imported yet)';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'Settings exported to $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'Export failed: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle => 'Import Settings?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'This replaces your current settings — including interface, speech-model configuration, behavior, text replacements, and snippets — with the contents of $path. Your API keys are left untouched.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'Settings imported from $path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'No export file found at $path. Export settings first, or copy an export file there.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'Import failed: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'Automatic backup';

  @override
  String get settingsAutosaveHint =>
      'Saves your setup to the chosen folder a few seconds after every change';

  @override
  String get settingsAutosaveChooseFolder =>
      'Choose a different folder for automatic backups (nothing is backed up yet)';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'Last backup: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'No backup yet';

  @override
  String get settingsAutosaveLastRunFailed => 'Backup failed';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'Last attempt failed — last backup: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'Automatic backup failed: the chosen folder is unavailable.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'Automatic backup failed: $reason';
  }

  @override
  String get groqRemovedToast =>
      'The cloud provider you used has been removed. Speech recognition now runs on this device.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings migrated from WhisPaste 1.x',
      one: '1 recording migrated from WhisPaste 1.x',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Off';

  @override
  String get settingsOn => 'On';

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
  String get statusSelectionEdited => 'Selection edited';

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
      'No audio detected. Please try again. Sometimes the microphone needs a moment to warm up.';

  @override
  String get recordingAutoStopped => 'Recording stopped: silence detected.';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionDuplicate => 'Duplicate';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDismiss => 'Dismiss';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionExport => 'Export';

  @override
  String get unsavedInputTitle => 'Discard your changes?';

  @override
  String get unsavedInputMessage => 'The text you entered is not saved yet.';

  @override
  String get unsavedInputDiscard => 'Discard';

  @override
  String get trayUnavailableMinimizedHint =>
      'The tray icon is unavailable. WhisPaste was minimized and keeps running.';

  @override
  String get settingsSaveFailedToast =>
      'The setting could not be saved. The previous value is kept.';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionClearSearch => 'Clear search';

  @override
  String get tooltipLanguage => 'Language';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get onboardingWelcome => 'Speak it once. Paste it anywhere.';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackHint => 'Tell us what you think. We read every message.';

  @override
  String get analyticsPreviewBanner =>
      'Preview: showing sample data. Real analytics will appear once you start recording.';

  @override
  String get analyticsEmptyTitle => 'No recordings yet';

  @override
  String get analyticsEmptySubtitle =>
      'Start recording to see your analytics here.';

  @override
  String get analyticsNoRecordingsInPeriod => 'No recordings in this period';

  @override
  String get analyticsOverview => 'Overview';

  @override
  String get analyticsOverviewSubtitle => 'Your recording stats at a glance';

  @override
  String get analyticsActivity => 'Activity';

  @override
  String get analyticsInsights => 'Insights';

  @override
  String get analyticsTotalRecordings => 'Total recordings';

  @override
  String get analyticsTotalDuration => 'Total duration';

  @override
  String get analyticsWordsDictated => 'Words transcribed';

  @override
  String get analyticsTimeSaved => 'Time saved (estimate)';

  @override
  String get analyticsAvgLatency => 'Avg. time to text';

  @override
  String get analyticsRecordingActivity => 'Recording activity';

  @override
  String get analyticsLast7Days => 'Last 7 days';

  @override
  String get analyticsWeekEmpty => 'No recordings in the last 7 days';

  @override
  String get analyticsModelUsage => 'Speech model usage';

  @override
  String get analyticsNoModelData => 'No model data in this period';

  @override
  String get analyticsLoading => 'Loading statistics';

  @override
  String get analyticsDurationDistribution => 'Duration distribution';

  @override
  String get analyticsCostSavings => 'Cost & savings';

  @override
  String get analyticsLocalSavings => 'Local savings';

  @override
  String get analyticsCloudCost => 'Cloud cost';

  @override
  String get analyticsEstimateNote =>
      'Estimated from list prices per transcription';

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
  String get analyticsResetTitle => 'Reset statistics';

  @override
  String get analyticsResetMessage =>
      'Are you sure you want to clear all analytics data? This action cannot be undone.';

  @override
  String get analyticsResetDone => 'Statistics were reset.';

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
    return '$amount saved';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount spent';
  }

  @override
  String get replacementsSearch => 'Search replacements…';

  @override
  String get replacementsSearchFieldLabel => 'Search replacements';

  @override
  String get replacementsAdd => 'Add';

  @override
  String get replacementsEmpty => 'No replacements yet';

  @override
  String get replacementsEmptyHint =>
      'Add replacements to auto-replace words while recording.\nExample: \"btw\" → \"by the way\"';

  @override
  String get replacementsNoMatches => 'No matches';

  @override
  String get replacementsNoMatchesHint => 'Try a different search term.';

  @override
  String get replacementsToggleLabel => 'Enable replacements';

  @override
  String get replacementsToggleEnabled => 'Replacements are active';

  @override
  String get replacementsToggleDisabled => 'Replacements are disabled';

  @override
  String get replacementsEnableBannerTitle => 'Replacements are turned off';

  @override
  String get replacementsEnableBannerHint =>
      'Enable them so trigger phrases are replaced automatically while recording.';

  @override
  String get replacementsEnableAction => 'Enable';

  @override
  String get replacementsDisableAction => 'Disable';

  @override
  String get replacementsEditShortcut => 'Edit replacement';

  @override
  String get replacementsNewShortcut => 'New replacement';

  @override
  String get replacementsDialogHint =>
      'Any of the trigger phrases will be replaced automatically while recording.';

  @override
  String get replacementsTriggerLabel => 'Trigger phrases';

  @override
  String get replacementsTriggerHint => 'e.g. btw';

  @override
  String get replacementsAddTrigger => 'Add trigger phrase';

  @override
  String get replacementsMissingTrigger => 'Add at least one trigger phrase.';

  @override
  String get replacementsRemoveTrigger => 'Remove trigger phrase';

  @override
  String get replacementsReplacementLabel => 'Replacement text';

  @override
  String get replacementsMissingReplacement => 'Enter the replacement text.';

  @override
  String get replacementsReplacementHint => 'e.g. by the way';

  @override
  String get replacementsReplacementHelper =>
      'Use \\n for a line break and \\n\\n for a blank line. To keep a literal backslash-n, write \\\\n.';

  @override
  String get replacementsDeleteTitle => 'Delete replacement';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Remove the replacement \"$trigger\"? This cannot be undone.';
  }

  @override
  String get replacementsImportFromFolder => 'Import from folder';

  @override
  String get replacementsImportHint =>
      'Scan a project folder for identifiers and add them as fuzzy replacements — nothing leaves your device.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return 'Found $found, added $added, skipped $skipped duplicate(s)';
  }

  @override
  String get replacementsImportScanning =>
      'Scanning the folder — this can take a moment for large projects…';

  @override
  String get replacementsImportError =>
      'Import failed — the folder could not be scanned.';

  @override
  String get replacementsImportedBadge => 'Imported';

  @override
  String get replacementsLearnedBadge => 'Learned';

  @override
  String get correctionLearningToggleLabel => 'Learn from corrections';

  @override
  String get correctionLearningToggleEnabled =>
      'Watching repeated corrections for suggestions';

  @override
  String get correctionLearningToggleDisabled =>
      'Not watching corrections for suggestions';

  @override
  String get correctionLearningHowTo =>
      'While recording a note in Recordings, say “correct: …” (or “korrektur: …”) followed by the fixed text to overwrite it. Fix the same thing twice and WhisPaste offers it here as an automatic replacement.';

  @override
  String get correctionCandidatesCardTitle => 'Suggested from your corrections';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count suggestion(s) from corrections you repeated — review before they become replacements.';
  }

  @override
  String get correctionCandidatesReviewButton => 'Review';

  @override
  String get correctionCandidatesReviewTitle => 'Review learned corrections';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    return '$count correction(s) you repeated — accept the ones WhisPaste should apply automatically from now on. Nothing changes until you confirm.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return 'Added $added learned replacement(s)';
  }

  @override
  String get replacementsImportNothingFound =>
      'No new identifiers found in this folder.';

  @override
  String get replacementsImportReviewTitle => 'Choose what to import';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return '$count candidates found — pick which ones become replacements. Nothing is added until you confirm.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'Filter candidates';

  @override
  String get replacementsImportReviewSelectAllFiltered => 'Select all shown';

  @override
  String get replacementsImportReviewDeselectAll => 'Deselect all';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return '$selected of $total selected';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'No candidates match your filter.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'Import selected ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'Matching';

  @override
  String get replacementsMatchModeExact => 'Exact';

  @override
  String get replacementsMatchModeFuzzy => 'Similar';

  @override
  String get replacementsFuzzyToleranceLabel => 'Tolerance';

  @override
  String get replacementsFuzzyToleranceStrict => 'Strict';

  @override
  String get replacementsFuzzyToleranceStandard => 'Standard';

  @override
  String get replacementsFuzzyToleranceTolerant => 'Tolerant';

  @override
  String get replacementsFuzzyToleranceHint =>
      'How close a spoken phrase must sound like a trigger to still count as a match. Strict only catches near-identical wording, so almost nothing gets replaced by accident, but a mumbled trigger may slip through unmatched. Standard is a balanced default for everyday use. Tolerant also catches noticeably different pronunciation or phrasing, at a higher risk of matching something you did not mean to replace.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Trigger phrases under $minLength characters cannot use similar matching — too many false hits.';
  }

  @override
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'The trigger “$trigger” already exists (replacement: “$replacement”).';
  }

  @override
  String get snippetsSearch => 'Search snippets…';

  @override
  String get snippetsSearchFieldLabel => 'Search snippets';

  @override
  String get snippetsAdd => 'Add';

  @override
  String get snippetCopySuffix => '(copy)';

  @override
  String get snippetsEmpty => 'No snippets yet';

  @override
  String get snippetsEmptyHint =>
      'Add a snippet to quickly reuse a block of text — like a signature or a boilerplate reply.';

  @override
  String get snippetsNoMatches => 'No matches';

  @override
  String get snippetsNoMatchesHint => 'Try a different search term.';

  @override
  String get snippetsEditSnippet => 'Edit snippet';

  @override
  String get snippetsNewSnippet => 'New snippet';

  @override
  String get snippetsDialogHint =>
      'Open the snippet picker while recording to insert this text.';

  @override
  String get snippetsTitleLabel => 'Title';

  @override
  String get snippetsTitleHint => 'e.g. Email signature';

  @override
  String get snippetsBodyLabel => 'Body';

  @override
  String get snippetsBodyHint => 'The text this snippet inserts…';

  @override
  String get snippetsKindLabel => 'Type';

  @override
  String get snippetsKindStatic => 'Static';

  @override
  String get snippetsKindInteractive => 'Interactive';

  @override
  String get snippetsFieldsLabel => 'Fields';

  @override
  String get snippetsFieldsHint =>
      'You\'ll be guided through each field with its own short recording, in this order.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'Field $number name';
  }

  @override
  String get snippetsFieldMoveUp => 'Move field up';

  @override
  String get snippetsFieldMoveDown => 'Move field down';

  @override
  String get snippetsFieldRemove => 'Remove field';

  @override
  String get snippetsFieldAdd => 'Add field';

  @override
  String get snippetsFieldInsertIntoTemplate => 'Insert into template';

  @override
  String snippetsFieldsMinWarning(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min named fields',
      one: '1 named field',
    );
    return 'An interactive snippet needs at least $_temp0.';
  }

  @override
  String get snippetsTemplateLabel => 'Template';

  @override
  String get snippetsTemplateHint =>
      'Write your snippet text, then use each field\'s insert button to place it wherever you want.';

  @override
  String get snippetsTemplateFieldHint =>
      'Write your text here and insert fields using the buttons above.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'Not all fields appear in the template yet — their spoken text would go unused.';

  @override
  String get snippetsSaveMissingTitle => 'Title is missing';

  @override
  String get snippetsSaveMissingBody => 'Text is missing';

  @override
  String get snippetsFieldsDuplicateWarning =>
      'Each field needs a different name.';

  @override
  String get snippetsInteractiveBadge => 'Interactive';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fields',
      one: '1 field',
    );
    return '$_temp0 · Enter to start';
  }

  @override
  String interactiveSnippetBriefingHint(String name) {
    return 'Field 1: $name · Esc: cancel';
  }

  @override
  String interactiveSnippetAnnounceLabel(int index, int count, String name) {
    return 'Field $index/$count: $name';
  }

  @override
  String get interactiveSnippetAnnounceHint => 'Get ready to speak…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'Next';

  @override
  String get snippetsDeleteTitle => 'Delete snippet';

  @override
  String snippetsDeleteMessage(String title) {
    return 'Remove the snippet \"$title\"? This cannot be undone.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Picker trigger word';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Speak only this word to open the snippet picker. Leave empty to turn the picker off.';

  @override
  String get snippetsPickerTriggerHint => 'e.g. snippet';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'The trigger word is set, but there are no snippets yet — saying it inserts the word as normal text until you add your first snippet.';

  @override
  String get snippetsPickerHotkeyLabel => 'Picker hotkey';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Opens the picker straight away — the second way to the same panel.';

  @override
  String get snippetsPickerHotkeyOff => 'The picker hotkey is switched off.';

  @override
  String get snippetsPickerHotkeyEnable => 'Turn hotkey on';

  @override
  String get snippetsPickerUnavailable =>
      'The snippet picker is not available on this platform yet.';

  @override
  String get snippetsPickerSemanticsLabel => 'Snippet picker';

  @override
  String get snippetsPickerInsertAction => 'Insert';

  @override
  String get aboutTagline => 'Voice to text, instantly.';

  @override
  String get aboutWhatsNew => 'What\'s new';

  @override
  String get aboutReportIssue => 'Report issue';

  @override
  String get aboutSupportTitle => 'Support this project';

  @override
  String get aboutSupportDescription =>
      'WhisPaste is free and open source under the MIT license. Sponsoring covers real recurring fixed costs (the Apple Developer Program, Microsoft Partner Center, and hosting/domain) that keep it available on every platform.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Star on GitHub';

  @override
  String get aboutSponsorsTitle => 'Sponsors';

  @override
  String get supportPromptRecurringTitle => 'Make it monthly?';

  @override
  String get supportPromptRecurringDescription =>
      'Thank you for supporting WhisPaste before. If you\'d like, you could turn that into a small monthly sponsoring that keeps covering our recurring fixed costs.';

  @override
  String get aboutBuiltWith => 'Built with';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Cross-platform UI with Flutter. Local speech recognition via whisper.cpp and Parakeet.';

  @override
  String get aboutWhisper => 'whisper.cpp & OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Local and cloud speech recognition: fast, accurate, multilingual (99 languages).';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet & sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Local speech recognition, GPU-accelerated where available (Metal, Vulkan, CUDA) and on the CPU otherwise (~25 languages).';

  @override
  String get aboutParakeetModelCredit =>
      'Model: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'GGUF conversion: ggml-org, MIT';

  @override
  String get aboutLinks => 'Links';

  @override
  String get helpLegalTitle => 'Legal';

  @override
  String get helpDiagnosticsPublicNote =>
      'GitHub issues are public. Check the report before you paste it.';

  @override
  String get helpDiagnosticsBuilding => 'Building report …';

  @override
  String get tabsScrollBack => 'Show earlier tabs';

  @override
  String get tabsScrollForward => 'Show more tabs';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutGitHubRepo => 'GitHub repository';

  @override
  String get aboutFollowOnX => 'Follow on X';

  @override
  String get aboutMitLicense => 'MIT license';

  @override
  String get aboutThirdPartyLicenses => 'Third-party licenses';

  @override
  String get aboutThirdPartyLicensesDetail => 'Fonts and models';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutImprint => 'Legal notice';

  @override
  String get aboutSystemInfo => 'System info';

  @override
  String get aboutSystemInfoDesc =>
      'Copy a compact diagnostics snapshot for bug reports.';

  @override
  String get aboutDiagnosticsContentsTitle => 'What the report contains';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'App version, operating system, program path without your user name, speech model (variant, model, status, last error), GPU, model files and the last 40 log lines. API keys and tokens are blacked out in the log lines.';

  @override
  String get aboutDiagnosticsPreviewShow => 'Show';

  @override
  String get aboutDiagnosticsPreviewHide => 'Hide';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'Diagnostics incomplete: $error';
  }

  @override
  String get aboutCopyDebugInfo => 'Copy debug info';

  @override
  String get aboutCopied => 'Copied!';

  @override
  String get aboutMadeWith => 'Made with ♥ by WhisPaste';

  @override
  String get aboutOpenSource => 'Open source under the MIT license';

  @override
  String get feedbackSubtitle =>
      'Help us improve WhisPaste. Every voice matters.';

  @override
  String get feedbackCategoryLabel => 'What\'s this about?';

  @override
  String get feedbackRatingLabel => 'How are you feeling about WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Tell us more';

  @override
  String get feedbackContactEmailLabel => 'Email (optional)';

  @override
  String get feedbackContactEmailExplanation =>
      'Only if you\'d like a reply. We\'ll use it solely to follow up on this message, never for marketing, and it\'s deleted after 90 days.';

  @override
  String get feedbackContactEmailPlaceholder => 'you@example.com';

  @override
  String get feedbackContactEmailInvalid =>
      'Please enter a valid email address, or leave it empty.';

  @override
  String get feedbackContactLanguageLabel => 'Reply in';

  @override
  String get feedbackContactLanguageHint =>
      'Which language should we use if we get back to you?';

  @override
  String get feedbackSubmit => 'Send feedback';

  @override
  String feedbackSubmitMissing(String what) {
    return 'To send, please $what.';
  }

  @override
  String get feedbackMissingCategory => 'choose what it is about';

  @override
  String get feedbackMissingRating => 'rate how you feel about WhisPaste';

  @override
  String get feedbackMissingComment => 'write a message';

  @override
  String get feedbackMissingEmail =>
      'correct the email address or leave it empty';

  @override
  String get feedbackRequiredMarker => 'Required';

  @override
  String get feedbackPublishConsentLabel =>
      'I allow my feedback to appear anonymously as a quote on the website.';

  @override
  String get feedbackPublishConsentExplanation =>
      'Off by default. Only your text and rating are shown, never your name or email. You can withdraw this at any time with one click on the Feedback page in the app.';

  @override
  String get feedbackPublishReviewHint =>
      'Quotes are written like a rating: what you like and where there is still room to improve. Bug reports and wishes belong to Problem or Idea and are never published.';

  @override
  String get feedbackWithdrawConsentLabel => 'Withdraw consent';

  @override
  String get feedbackWithdrawConsentHelp =>
      'Applies to feedback you sent with consent from this device. The quote disappears from the website within about 24 hours.';

  @override
  String get feedbackWithdrawConsentPending =>
      'The withdrawal is saved and will be sent once WhisPaste runs with an internet connection (for up to 30 days); otherwise please withdraw by e-mail.';

  @override
  String get feedbackWithdrawNoCode =>
      'No withdrawal code is stored on this device – withdraw by e-mail';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'Withdrawal from $date is being sent …';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'Withdrawal from $date not delivered – withdraw by e-mail';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'The withdrawal could not be delivered – please withdraw by e-mail.';

  @override
  String get feedbackWithdrawEmailLabel => 'Withdraw by e-mail';

  @override
  String get feedbackWithdrawEmailSubject =>
      'Withdraw my consent to quote my feedback';

  @override
  String get feedbackWithdrawEmailBody =>
      'Please withdraw my consent to quote my feedback.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'Feedback date:';

  @override
  String get feedbackWithdrawEmailReferenceLabel => 'Withdrawal reference:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'I have sent the e-mail';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'No e-mail app found. Please send the prepared message to this address:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'Copy address and message';

  @override
  String get feedbackWithdrawEmailCopied => 'Address and message copied.';

  @override
  String get feedbackWithdrawLocked =>
      'Your system\'s credential store cannot be read right now. WhisPaste cannot send the consents and withdrawals kept there. Please withdraw by e-mail; the prepared e-mail contains the references needed.';

  @override
  String get feedbackWithdrawConsentDone =>
      'Withdrawal sent. The quote disappears from the website within about 24 hours, at the next daily update.';

  @override
  String get feedbackPrivacyNote =>
      'Anonymous by default, only identifiable if you add your email above.';

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
  String get statusBarAfterBoth => 'After: Copy & paste';

  @override
  String get statusBarAfterNothing => 'After: Manual';

  @override
  String get dockOutputCopy => 'Copy';

  @override
  String get dockOutputPaste => 'Paste';

  @override
  String get dockOutputBoth => 'Copy & paste';

  @override
  String get dockOutputNothing => 'Manual';

  @override
  String get sttStatusStarting => 'Starting…';

  @override
  String get sttStatusReady => 'Ready';

  @override
  String get sttStatusError => 'Error';

  @override
  String get statusBarSttTooltip => 'Speech model status';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Recognition runs on: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'Real GPU utilization can\'t be measured across platforms without elevated privileges; the percentage shown reflects this process\'s CPU activity instead.';

  @override
  String get statusBarRecording => 'Recording…';

  @override
  String get statusBarTranscribing => 'Processing…';

  @override
  String get statusBarRefining => 'Processing…';

  @override
  String get statusBarHotkeyTooltip => 'Global hotkey: click to configure';

  @override
  String get statusBarAutoPasteOffHint => 'Turn on Auto-Paste…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste is currently disabled. Click to open Settings.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Dismiss';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'Automation: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'Automation: error';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'Automation API active on port $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'Automation API active on port $port (port $requestedPort was in use)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'Automation API: no free port found';

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
  String get modifierAltGr => 'AltGr';

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
  String get modelServerReady => 'Speech model ready';

  @override
  String get modelServerMissing => 'Speech model not installed';

  @override
  String get modelServerWhisper => 'Local speech model';

  @override
  String get modelReady => 'Ready';

  @override
  String get modelDownloadComplete => 'Speech model ready to use';

  @override
  String get modelUse => 'Use';

  @override
  String get modelDownload => 'Download';

  @override
  String get modelDownloading => 'Downloading…';

  @override
  String get modelDownloadingEngine => 'Preparing speech model…';

  @override
  String get modelVerifying => 'Verifying…';

  @override
  String get modelExtracting => 'Extracting…';

  @override
  String get modelDeleteConfirm => 'Delete this speech model?';

  @override
  String get modelDeleteConfirmMessage =>
      'The speech model file is deleted from this device. You can re-download it any time.';

  @override
  String get modelTierDeleteConfirm => 'Delete these models?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count models ($size) are deleted from this device. You can re-download them any time.',
      one:
          '1 model ($size) is deleted from this device. You can re-download it any time.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'Fast';

  @override
  String get qualityTierCompactDesc =>
      'Fast results, small download. Great for short notes and quick messages.';

  @override
  String get qualityTierBalancedLabel => 'Balanced';

  @override
  String get qualityTierBalancedDesc =>
      'Accurate and reliable for everyday recording. Works on most devices.';

  @override
  String get qualityTierPremiumLabel => 'Accurate';

  @override
  String get qualityTierPremiumDesc =>
      'Top accuracy for longer recordings and complex content. Needs a capable GPU.';

  @override
  String get qualityTierRecommended => 'Recommended for your device';

  @override
  String get qualityTierRecommendedMeasured => 'Measured for your device';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size download';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Download speech model';

  @override
  String get qualityTierChooseDifferent => 'Choose a different tier';

  @override
  String get qualityTierActive => 'Active';

  @override
  String get qualityTierInfoSlow =>
      'Accurate, takes noticeably longer to process on this computer';

  @override
  String get qualityTierInfoSlowEstimate =>
      'Accurate, probably takes noticeably longer on this computer (estimate)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Accurate, takes ~${ratio}x longer than Fast';
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
  String get benchmarkRowSubtitle =>
      'Measures how fast each installed tier runs on this computer. The results set the speed hints and the recommendation.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'Running… step $step of $total: $tier';
  }

  @override
  String get benchmarkCancel => 'Cancel benchmark';

  @override
  String get benchmarkCancelled =>
      'Benchmark cancelled. Tiers measured so far are saved.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tiers measured',
      one: '1 tier measured',
    );
    return 'Measurement complete: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'Last measured: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'Compute path: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'Processor (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'Graphics card ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds s processing per second of audio';
  }

  @override
  String get benchmarkNoResult =>
      'No measurement yet. Run the benchmark to get speed hints for this computer.';

  @override
  String get benchmarkStaleNotice =>
      'These results are from another computer or an earlier version. They are measured again in the background.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'The benchmark measures Whisper models. Parakeet is not measured.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'Recommended after measuring: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'Switch to $tier';
  }

  @override
  String get benchmarkErrorBusy =>
      'The benchmark cannot run during a recording. Start it again afterwards.';

  @override
  String get benchmarkErrorNoModel =>
      'No tier is installed. Download a speech model first.';

  @override
  String get benchmarkErrorFailed => 'The benchmark could not be completed.';

  @override
  String get benchmarkRetry => 'Try again';

  @override
  String get qualityTierActionOverride => 'Use anyway';

  @override
  String get qualityTierActionOverrideHint =>
      'Use this tier despite the warning';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'Basic';

  @override
  String get settingsQualityBalanced => 'Balanced';

  @override
  String get settingsQualityHigh => 'High quality';

  @override
  String get settingsQualityBest => 'Accurate';

  @override
  String get settingsQualityMaximum => 'Maximum accuracy';

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
  String get settingsAdvancedModelManagement =>
      'Advanced speech model settings';

  @override
  String get infoEngineDownloading =>
      'Speech model is being prepared. Please wait a moment.';

  @override
  String get infoModelMissing =>
      'Please download a speech model in Settings first.';

  @override
  String infoModelMissingSelected(String size) {
    return 'The selected speech model ($size) isn\'t downloaded yet.';
  }

  @override
  String get infoModelMissingDownload => 'Download now';

  @override
  String get statusBarModelMissing => 'Speech model missing';

  @override
  String statusBarModelDownloading(int percent) {
    return 'Downloading speech model… $percent %';
  }

  @override
  String get modelDownloadAction => 'Download';

  @override
  String get modelMissingDownloadAction => 'Missing — download';

  @override
  String get infoPipelineBusy =>
      'WhisPaste is still busy with the previous recording.';

  @override
  String get infoSnippetPickerEmpty =>
      'You don\'t have any snippets yet. Create one, and the picker will open.';

  @override
  String get infoSnippetPickerEmptyAction => 'Open snippets';

  @override
  String get oomRecoveryTitle =>
      'Recording stopped: graphics card is out of memory';

  @override
  String get oomRecoveryMessage =>
      'Your GPU ran out of memory. Choose how to proceed:';

  @override
  String get oomRecoveryTrySmaller => 'Try smaller speech model';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Switch to $model and retry recording';
  }

  @override
  String get oomRecoverySwitchCloud => 'Switch to cloud';

  @override
  String get oomRecoverySwitchCloudHint => 'Use a cloud speech model instead';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'Recordings are then sent to $provider.';
  }

  @override
  String get oomRecoveryCancel => 'Cancel';

  @override
  String get oomRecoveryPermanentTitle => 'Local speech model unavailable';

  @override
  String get oomRecoveryPermanentMessage =>
      'All local models failed due to GPU memory limits. Please switch to a cloud speech model in settings.';

  @override
  String get oomRecoveryPermanentCloud => 'Open Settings';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Switching to $model…';
  }

  @override
  String get oomRecoverySwitchingCloud => 'Switching to a cloud speech model…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Speech model $model also failed. Trying next option…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'No smaller model is available. Choose another model in Settings or use cloud speech recognition.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'Quality reduced: your GPU ran out of memory. Switched to a lighter speech model.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Your GPU ran out of memory. Switched to CPU mode for reliability.';

  @override
  String get errorSttServerConnectionLost =>
      'Speech model stopped unexpectedly. Please try again.';

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
  String get errorCloudTimeoutLocal =>
      'The cloud service took too long to answer. Check your connection, or dictate offline with your local speech model.';

  @override
  String get errorCloudTimeout =>
      'The cloud service took too long to answer. Check your connection and try again.';

  @override
  String get errorCloudNetworkLocal =>
      'The cloud service could not be reached. Check your internet connection, or dictate offline with your local speech model.';

  @override
  String get errorCloudNetwork =>
      'The cloud service could not be reached. Check your internet connection and try again.';

  @override
  String get errorQuickNoteAppendFailed =>
      'The quick note could not be saved, so the text was not added to it. Copy the text and paste it into the note.';

  @override
  String get errorOnboardingNotCompleted =>
      'Please complete the setup wizard first.';

  @override
  String get errorSttModelNotFound =>
      'Speech model not found. Please download it in Settings.';

  @override
  String get errorSttModelLoadFailed =>
      'The speech model could not be loaded. Restart WhisPaste. If it still fails, download the speech model again in Settings.';

  @override
  String get errorSttModelFileMissing =>
      'The speech model file is missing. Download the speech model in Settings.';

  @override
  String get errorSttModelCorrupted =>
      'The speech model file is damaged. Download the speech model again in Settings.';

  @override
  String get errorSttEngineRestartNeeded =>
      'The speech engine is still busy with an earlier dictation. Restart WhisPaste to use it again.';

  @override
  String get pendingRetryFailed =>
      'Transcribing again failed. The recording is kept for another try.';

  @override
  String get errorSttModelUnknown =>
      'Unknown speech model. Please select a valid model in Settings.';

  @override
  String get errorRecordingFailed =>
      'Could not start recording, please try again';

  @override
  String get errorNoAudioRecorded => 'No audio recorded, please try again';

  @override
  String get errorTranscriptionEmpty =>
      'Transcription returned empty text, please try again';

  @override
  String get errorSttServerFailed => 'Speech model failed to start';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'Speech model appears corrupted. Downloading a fresh copy automatically.';

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
      'Speech model failed on both GPU and CPU. Please restart the app or re-download the speech model.';

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
      'Speech model is still starting. Please try again in a moment.';

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
  String get errorNoMicrophone =>
      'No microphone found. Connect a microphone and try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get modelDownloadFailed =>
      'Download failed. Please check your internet connection.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'Not enough disk space for this download: needs $needed, $free free. The download did not start.';
  }

  @override
  String get modelDeleteInUse =>
      'The speech model file is in use by another program and could not be deleted. Close it and try again.';

  @override
  String get statusSttLoading => 'Loading speech model…';

  @override
  String get statusSttReady => 'Speech model ready';

  @override
  String get modelDownloadFailedChecksum =>
      'The downloaded file was damaged and has been removed. Please download it again.';

  @override
  String get modelDownloadFailedStorage =>
      'The file could not be saved. Check that there is enough free disk space.';

  @override
  String get modelDownloadFailedUnknown => 'Download failed. Please try again.';

  @override
  String get onboardingModelDownloadCancel => 'Cancel download';

  @override
  String get onboardingModelDiskSpaceTitle => 'Low disk space';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'The model needs $needed, but only $free is free. The download will probably fail.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'Download anyway';

  @override
  String get historyDuplicate => 'Duplicate';

  @override
  String get historyDuplicated => 'Entry duplicated';

  @override
  String get historyTakeAsNote => 'Take over as note';

  @override
  String get historyTakenAsNote => 'Taken over as note';

  @override
  String get historyOpenNote => 'Open';

  @override
  String get historyViewRaw => 'Raw';

  @override
  String get historyViewEdited => 'Edited';

  @override
  String get historyApplySmartModePreset => 'Apply Smart Mode preset';

  @override
  String get historySmartModeApplied => 'Smart Mode applied';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode applied';

  @override
  String get smartModeUndoAction => 'Undo';

  @override
  String get smartModeBusy => 'Smart Mode is still running';

  @override
  String get smartModeBusyRetry =>
      'Smart Mode is still running – please try again in a moment';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count names changed',
      one: '1 name changed',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'Original copied to the clipboard – paste it with $shortcut. The previous clipboard content was replaced.';
  }

  @override
  String get selectionUndoUnavailable => 'Undo is not possible right now.';

  @override
  String get smartModeCheckTimedOut =>
      'The check took too long – your text stays unchanged.';

  @override
  String get historySmartModeUndo => 'Undo Smart Mode';

  @override
  String get historySmartModeRestore => 'Restore Smart Mode';

  @override
  String get historySmartModeFailedModelMissing => 'Text model not downloaded';

  @override
  String get historySmartModeFailedTimeout => 'Smart Mode timed out';

  @override
  String get historySmartModeFailedGeneric =>
      'Smart Mode failed — please try again';

  @override
  String get historySmartModeSelectTargetLanguage => 'Select target language';

  @override
  String get historyAddNote => 'Add annotation';

  @override
  String get historyEditNote => 'Edit annotation';

  @override
  String get historyNotes => 'Annotations';

  @override
  String get historyNotePlaceholder => 'Write an annotation…';

  @override
  String get historyVoiceNoteHint =>
      'Tip: say “tag: name” or “correct: text” while recording.';

  @override
  String get historyNoteAdded => 'Annotation added';

  @override
  String get historyNoteDeleted => 'Annotation deleted';

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
  String get tagManageTitle => 'Manage tags';

  @override
  String get tagManageEmpty =>
      'No tags yet. Create one by adding it to a recording.';

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
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more tags',
      one: '1 more tag',
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
  String tagRemoveSemanticsLabel(String tag) {
    return 'Remove tag \"$tag\"';
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
  String get historyShortcutHelp => 'Keyboard shortcuts';

  @override
  String get historyShortcutGeneral => 'GENERAL';

  @override
  String get historyShortcutTags => 'Focus tag input';

  @override
  String get historyShortcutNotes => 'Add an annotation';

  @override
  String get historyShortcutPin => 'Favorite / unfavorite';

  @override
  String get historyShortcutClose => 'Save & close';

  @override
  String get historyShortcutListGroup => 'RECORDINGS LIST';

  @override
  String get historyShortcutMoveFocus => 'Select entry';

  @override
  String get historyShortcutOpenEntry => 'Open entry';

  @override
  String get historyShortcutCopyEntry => 'Copy entry';

  @override
  String get historyShortcutDeleteEntry => 'Delete entry';

  @override
  String get historyShortcutSelectAll => 'Select all';

  @override
  String get historyShortcutClearSelection => 'Clear selection';

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
  String get historyShortcutDiscardEdit => 'Discard edit';

  @override
  String get historyEditTitle => 'Edit title';

  @override
  String get historyTitlePlaceholder => 'Enter a title…';

  @override
  String get historyTitleSaved => 'Title saved';

  @override
  String get historySearchHelpTitle => 'Search tips';

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
  String get historyRemoveRecentSearch => 'Remove recent search';

  @override
  String get historyRemoveFilter => 'Remove filter';

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
  String get settingsKeyboardShortcut => 'Hotkey';

  @override
  String get shortcutsGroupDictate => 'Dictate';

  @override
  String get shortcutsGroupNotes => 'Notes & snippets';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode & edit selection';

  @override
  String get shortcutsAreaIntro =>
      'These hotkeys work system-wide: in every app, even while WhisPaste runs in the background. Each combination belongs to just one hotkey.';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Hotkey to start and stop recording';

  @override
  String get settingsHotkeyEnabled => 'Start/stop recording';

  @override
  String get settingsCurrentHotkey => 'Current hotkey';

  @override
  String get settingsChangeHotkey => 'Change';

  @override
  String get settingsHotkeyRecorderTitle => 'Record new hotkey';

  @override
  String get settingsHotkeyRecorderHint =>
      'Press the key combination you want to use…';

  @override
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'Any modifier combination works: e.g. $first, $second, or $third';
  }

  @override
  String get settingsHotkeyRecorderCancel => 'Cancel';

  @override
  String get settingsHotkeyRecorderSave => 'Save';

  @override
  String get settingsHotkeyRecorderClear => 'Clear';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'This key can\'t be used as a hotkey. Try a letter, digit, function key (F1-F12), or an arrow key.';

  @override
  String get settingsHotkeyActionRecording => 'Start/stop recording';

  @override
  String get settingsHotkeyActionQuickNote => 'Quick note';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'Record a quick note';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'Transcribed text is appended to the note marked as your quick note. You pick that note in the Notes area.';

  @override
  String get settingsQuickNoteOpenInMainWindow =>
      'Open notes in the main window';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'Off: the quick note is saved in the background and a message offers “Open note”. On: the main window comes forward and shows the note.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Current hotkey';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'This combination is already used for \"$action\". Pick a different one.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'This combination is already used for \"$action\". Pick a different one.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'This combination could not be registered — the quick-note hotkey is currently not active. Pick a different combination.';

  @override
  String get quickNoteToastSaved => 'Quick note saved';

  @override
  String get quickNoteToastOpenNote => 'Open note';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Snippet picker';

  @override
  String get settingsSnippetPickerHotkeyEnabled => 'Open snippet picker';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Opens the snippet picker straight away — no recording, and without the spoken trigger word.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Current hotkey';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'This combination is already used for \"$action\". Pick a different one.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'This combination could not be registered — the snippet-picker hotkey is currently not active. Pick a different combination.';

  @override
  String get settingsMaxRecordDuration => 'Max recording duration';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Automatic safety stop after this time';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Unlimited';

  @override
  String get settingsCloseToTray => 'Close to tray';

  @override
  String get settingsCloseToTraySubtitle =>
      'Keep running in the system tray when closing the window';

  @override
  String get settingsSidePanelEnabled => 'Clipboard Quick-Paste panel';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'Slide-out panel on hover at the chosen screen edge for transcriptions, snippets and clipboard history';

  @override
  String get settingsSidePanelEdge => 'Panel position';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'Which screen edge the panel docks to and slides out from';

  @override
  String get settingsSidePanelEdgeLeft => 'Left edge';

  @override
  String get settingsSidePanelEdgeRight => 'Right edge';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceSubtitle =>
      'Colours of the app windows. Recording bar and overlay stay dark.';

  @override
  String get settingsAppearanceSystem => 'Follow system';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsAppearanceNavy => 'Navy';

  @override
  String get settingsAppearanceCardNavy => 'Navy';

  @override
  String get settingsLanguageDialogSubtitle =>
      'Choose the language WhisPaste expects when you record. With auto-detect on, it recognises the language itself.';

  @override
  String get settingsLanguageSearchHint => 'Search by name';

  @override
  String get settingsLanguageSelectedTitle => 'Current choice';

  @override
  String get settingsLanguageSaveAndClose => 'Save and close';

  @override
  String get settingsLanguageSavePickOne =>
      'Pick at least one language to save.';

  @override
  String get settingsLanguageNoResults => 'No language found';

  @override
  String get settingsLanguageChange => 'Change';

  @override
  String get settingsLanguageCancel => 'Cancel';

  @override
  String get settingsErrorReporting => 'Error reporting';

  @override
  String get settingsErrorReportingSubtitle =>
      'Sends crash and error reports with an anonymous device ID. Never your audio or text.';

  @override
  String get settingsErrorReportingRestartHint =>
      'Takes effect after restarting WhisPaste.';

  @override
  String get settingsAutoPasteBlocklist => 'Auto-Paste blocklist';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Apps where text is only copied (no auto-paste). With the switch below on, the text goes to the clipboard; when off, only to Recordings. While a list is set, an app that cannot be identified counts as blocked.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'Copy to the clipboard when apps are blocked';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'Off: the text is only saved in Recordings.';

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
      'On the Mac, enter bundle IDs such as com.apple.Terminal. An entry without a dot only matches an identical ID.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'Under GNOME (Wayland), WhisPaste identifies the target app only with the WhisPaste extension for GNOME – without it, while a block list is set, text is only copied';

  @override
  String get settingsLinuxAlwaysShiftPaste => 'Always paste with Ctrl+Shift+V';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'The terminal shortcut, in every other app too. Some apps use these keys for something else; LibreOffice, for example, opens “Paste Special”';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'WhisPaste identifies the target app here and pastes into terminals with Ctrl+Shift+V on its own';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'Under GNOME (Wayland), WhisPaste recognises terminals only with the WhisPaste extension for GNOME. Until then, switch this on if you mostly dictate into terminals';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'On this desktop, WhisPaste does not recognise terminals. Switch this on if you mostly dictate into terminals';

  @override
  String get settingsLinuxPortalInputTitle =>
      'Paste through desktop permission';

  @override
  String get settingsLinuxPortalInputBody =>
      'Works without setup: your desktop asks once whether WhisPaste may send shortcuts. WhisPaste only sends Ctrl+V and Ctrl+C this way';

  @override
  String get settingsLinuxPortalInputConnect => 'Ask for permission';

  @override
  String get settingsLinuxPortalInputRevoke => 'Withdraw permission';

  @override
  String get settingsLinuxPortalInputConnected =>
      'Permission granted. WhisPaste can now paste this way';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'No permission given. You can ask again at any time';

  @override
  String get settingsLinuxPortalInputFailed =>
      'Asking for permission did not work. Please try again later';

  @override
  String get settingsLinuxGnomeExtensionTitle =>
      'WhisPaste extension for GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'Under GNOME, WhisPaste learns which app is active only with this extension, for terminals and the block list. It reads the app name only, never window titles or content';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'Turn on the extension';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'Turn off the extension';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'The extension is not installed here. The manual explains how to install it';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'Turned on. If WhisPaste does not recognise the app yet, log out and back in once';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'Turning it on did not work. In a terminal: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'Under Wayland, WhisPaste cannot see the active app. While an app is blocked, text is only copied, not pasted.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'Under Wayland, WhisPaste cannot check whether you switched windows during processing – the text goes to the window that is active when it is pasted';

  @override
  String get settingsPasteBlocklistAdd => 'Add app';

  @override
  String get settingsPasteBlocklistEmpty =>
      'No app blocked – auto-paste works everywhere.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'Remove from the block list: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle => 'Add app to the block list';

  @override
  String get settingsPasteBlocklistRecentHeading => 'Recently pasted into';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'No recording with a recognised app yet. Enter the app ID below.';

  @override
  String get settingsPasteBlocklistManualHeading => 'Enter the app ID manually';

  @override
  String get settingsPasteBlocklistManualAdd => 'Add';

  @override
  String get historyAutoPasteOffForApp => 'Turn off auto-paste in this app';

  @override
  String get settingsPasteClipboardAfter => 'Clipboard after pasting';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'Whether your previous clipboard content comes back after a paste. If a paste cannot be confirmed in time, the transcript always stays on the clipboard.';

  @override
  String get settingsPasteClipboardAfterKeep => 'Keep the transcript';

  @override
  String get settingsPasteClipboardAfterRestore =>
      'Restore what you had copied';

  @override
  String get pasteClipboardUnsavedHint =>
      'Your previous clipboard could not be kept – macOS denied access to it. Allow it under System Settings → Privacy & Security.';

  @override
  String get pasteClipboardUnsavedAction => 'Open System Settings';

  @override
  String get settingsCheckUpdates => 'Check for updates';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Check for new versions at startup and every 24 hours';

  @override
  String get settingsCheckForUpdatesNow => 'Check for updates now';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsUpdatesSubtitle => 'Release channel and update checks';

  @override
  String get settingsBetaUpdates => 'Beta updates';

  @override
  String get settingsBetaUpdatesSubtitle =>
      'Get pre-release versions that are less tested.';

  @override
  String get settingsStableRevertHintMessage =>
      'Switching back to Stable automatically isn\'t possible here. You already have a newer beta version installed.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'Manually download stable $stableVersion';
  }

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingPrivacyTitle => 'Help make WhisPaste better';

  @override
  String get onboardingPrivacyHint =>
      'Audio and text stay local. Anonymous usage statistics go to a self-hosted server in the EU, crash reports go to a service in the EU (Sentry) — GDPR-compliant.';

  @override
  String get onboardingPrivacyToggle => 'Share anonymous usage statistics';

  @override
  String get onboardingPrivacyToggleHint => 'On by default, switch off anytime';

  @override
  String get onboardingPrivacyCrashToggle => 'Send anonymous crash reports';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'Helps fix bugs, on by default, switch off anytime';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'Appearance';

  @override
  String get onboardingAppearancePageSubtitle =>
      'How the app starts, and how the recording overlay looks.';

  @override
  String get onboardingBeat1Title => 'Press the hotkey, speak, done';

  @override
  String get onboardingBeat1Caption =>
      'Recording starts instantly — your words land as text right at your cursor.';

  @override
  String get onboardingBeat2Title => 'Runs locally, on your hardware';

  @override
  String get onboardingBeat2Caption =>
      'Transcription happens on your device — no internet needed.';

  @override
  String get onboardingBeat3Title => 'Everywhere you type';

  @override
  String get onboardingBeat3Caption =>
      'Browser, mail, editor — WhisPaste works system-wide.';

  @override
  String get onboardingMicChipReady => 'Microphone ready';

  @override
  String get onboardingMicChipPending => 'Microphone access pending';

  @override
  String get onboardingMicChipAction => 'Microphone: action needed';

  @override
  String get onboardingModelTitle => 'Set up speech model';

  @override
  String get onboardingModelSubtitle =>
      'Download the speech model to record offline. Your voice never leaves your device.';

  @override
  String get onboardingModelRecommended => 'Recommended';

  @override
  String get onboardingModelChangeLater =>
      'You can adjust quality later in Settings';

  @override
  String get onboardingModelNextBlocked =>
      'Download a speech model or use a cloud provider with a saved API key to continue.';

  @override
  String get onboardingModelDownloading => 'Downloading…';

  @override
  String get onboardingModelReady => 'Speech model ready';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Optimised GPU acceleration unavailable, app will use the CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'The quickest way to text in about 25 European languages, including German. Runs well on any hardware, GPU or not.';

  @override
  String get onboardingModelDetectingHardware =>
      'Checking your hardware for the right recommendation…';

  @override
  String onboardingModelUseCloud(String provider) {
    return 'Use $provider';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'An API key for $provider is already saved. You can use it instead of a local speech model.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'You use $provider for speech recognition. You do not need a local speech model for it.';
  }

  @override
  String get onboardingModelUseLocal => 'Use a local speech model';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'Broadest language coverage, plus custom vocabulary and punctuation tuning for names, acronyms, and jargon.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Doesn\'t support your selected language yet';

  @override
  String get onboardingTestRecordingTitle => 'Give it a try';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Press the button below and say a sentence. The text lands in the test field. Your hotkey works too.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Your hotkey';

  @override
  String get onboardingTestRecordingStartCta => 'Start recording';

  @override
  String get onboardingTestRecordingStopCta => 'Stop recording';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'Try a recording first to continue.';

  @override
  String get onboardingTestRecordingMicBypassCta =>
      'Continue without a microphone';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'Without a working microphone, WhisPaste can\'t start a recording yet. You can catch up anytime via the microphone status on this page or in Settings.';

  @override
  String get onboardingTestRecordingMicBypassConsequence =>
      'The hotkey then stays untested until you use it for the first time.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'Your spoken text will appear here …';

  @override
  String get onboardingTestRecordingInProgress =>
      'Recording: just start talking. Press again to stop.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      'That\'s it! This is exactly how it works in every app.';

  @override
  String get onboardingTestRecordingReassurance =>
      'Just a test, the text stays in this field.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'Just a test, the text stays in this field — recordings stop automatically after $seconds seconds, adjustable under Settings → $section.';
  }

  @override
  String get onboardingReadyTitle => 'You\'re All Set!';

  @override
  String get onboardingReadyNoModelTitle => 'A speech model is still missing';

  @override
  String get onboardingReadyNoModelBody =>
      'Without a speech model or an API key WhisPaste cannot transcribe anything. Download a model or save a key, and you are all set.';

  @override
  String get onboardingReadyBackToModel => 'Back to the model';

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
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'Text is in your clipboard, press $paste to paste';
  }

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste carries context from your previous recording forward for up to ten minutes. Before a quick switch to an unrelated topic, a short pause keeps the next result on track.';

  @override
  String get onboardingReadyAutostartToggle => 'Launch WhisPaste at login';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Starts minimized in the background, ready for your hotkey';

  @override
  String get onboardingTriggerTitle => 'How do you want to start recording?';

  @override
  String get onboardingTriggerSubtitle =>
      'Set your hotkey and choose how it starts a recording.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Current hotkey';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Hotkey already in use';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Your hotkey seems to be in use by another app. Record a new combination below to continue.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Go back to the hotkey page and record a new combination there.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Hold the hotkey and speak, release to finish';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Press once to start, press again to finish';

  @override
  String get onboardingTriggerSystemWideHint =>
      'Works system-wide — not just inside WhisPaste.';

  @override
  String get onboardingStartUsing => 'Let\'s go';

  @override
  String get onboardingReviewExit => 'Close introduction';

  @override
  String get onboardingReviewDone => 'Done';

  @override
  String get onboardingReviewEntry => 'Introduction';

  @override
  String get onboardingReviewSubtitle =>
      'Go through the five setup steps again whenever you like — nothing changes unless you change it.';

  @override
  String get onboardingReviewLabel => 'Review the introduction';

  @override
  String get onboardingReviewAction => 'Open';

  @override
  String get onboardingRevisionNoticeTitle =>
      'WhisPaste was updated — your settings are unchanged.';

  @override
  String get onboardingRevisionNoticeExpand => 'Show all changes';

  @override
  String get onboardingRevisionNoticeCollapse => 'Show less';

  @override
  String get onboardingRevisionExit => 'Leave introduction';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Leave the introduction?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'This update walkthrough is shown only once, so the steps you skip now won\'t be set up for you. You can reopen the same steps any time on the Help page, under “Review the introduction”, and every setting they cover also has its own place in Settings. What you already configured stays untouched.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Leave';

  @override
  String get overlayRecording => 'Recording';

  @override
  String get overlayTranscribing => 'Processing…';

  @override
  String get overlayRefining => 'Refining…';

  @override
  String get overlayStarting => 'Starting…';

  @override
  String get overlayDone => 'Copied';

  @override
  String get overlayDonePasted => 'Pasted';

  @override
  String get overlayDoneBoth => 'Copied & pasted';

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
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey to stop · $cancelKey to cancel';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return 'Discard recording? Press $cancelKey again';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Enter or $hotkey: next field · Esc: cancel';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Enter: next field · Esc: cancel';

  @override
  String get overlayProcessingLocal => 'Local';

  @override
  String get overlayProcessingCloud => 'Cloud';

  @override
  String get overlayRecordingQuickNote => 'Recording to note';

  @override
  String get overlayTargetQuickNote => 'Note';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayMicSignalLost => 'No microphone signal';

  @override
  String get overlayDoneQuickNote => 'Added to note';

  @override
  String get floatingButtonHide => 'Hide';

  @override
  String get floatingButtonQuit => 'Quit';

  @override
  String get a11yRecordingButton => 'Recording button';

  @override
  String get a11yRecordingOverlay => 'Recording overlay';

  @override
  String get a11ySidePanel => 'Quick paste panel';

  @override
  String get trayStatusRecording => 'Recording…';

  @override
  String get trayStatusReady => 'Ready';

  @override
  String get trayStartRecording => 'Start recording';

  @override
  String get trayStopRecording => 'Stop recording';

  @override
  String get trayOpenApp => 'Open WhisPaste';

  @override
  String get trayTranscribeFile => 'Transcribe file…';

  @override
  String get trayOpenSidePanel => 'Open quick-paste panel';

  @override
  String get traySettings => 'Settings';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayRecentRecordings => 'Recent recordings';

  @override
  String get trayUnlockRecordings => 'Unlock recordings…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'Send feedback…';

  @override
  String get quitDuringDictationTitle => 'A recording is still running';

  @override
  String get quitDuringDictationMessage =>
      'Quitting now stops the running recording or transcription, and its text is lost.';

  @override
  String get trayMicrophone => 'Microphone';

  @override
  String get settingsComingSoon => 'Coming soon';

  @override
  String get undo => 'Undo';

  @override
  String get hintDismiss => 'Dismiss hint';

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
  String get voiceCorrectionUndone => 'Correction undone';

  @override
  String get voiceNoteEmpty => 'No speech detected';

  @override
  String get voiceNoteError => 'Voice note failed';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'Voice note — say “tag: …” to add a tag, or “correct: …” to replace this transcript';

  @override
  String updateAvailable(String version) {
    return 'Update available: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Downloading update… $percent%';
  }

  @override
  String get updateReadyToInstall => 'Update ready, click to install';

  @override
  String get updateUpToDate => 'You\'re on the latest version';

  @override
  String get updateCheckNow => 'Check now';

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateDownload => 'Download';

  @override
  String get updateViewRelease => 'Release notes';

  @override
  String get updateError => 'Update check failed';

  @override
  String get updateInstallAfterRecording =>
      'The update installs after the recording';

  @override
  String get updateInstallerMissing =>
      'The installer file is missing. Check for updates again.';

  @override
  String get updateInstallFailed =>
      'The update could not be started. Try installing it again.';

  @override
  String get updateInstallRetry => 'Install again';

  @override
  String get updateRateLimited => 'Too many requests, try again later';

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
  String get settingsOverlaySizeMini => 'Mini';

  @override
  String get settingsOverlayColors => 'Overlay colours';

  @override
  String get settingsOverlayBackground => 'Overlay and button background';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'Applies to the recording overlay and the floating button.';

  @override
  String get settingsOverlayBackgroundMarine => 'Marine';

  @override
  String get settingsOverlayBackgroundGraphit => 'Graphite';

  @override
  String get settingsOverlayBackgroundGletscher => 'Glacier';

  @override
  String get settingsOverlayBackgroundAmber => 'Amber';

  @override
  String get settingsOverlayWave => 'Wave colour for overlay and button';

  @override
  String get settingsOverlayWaveSubtitle =>
      'Applies to the recording overlay and the floating button: wave and recording ring.';

  @override
  String get settingsOverlayWaveCyan => 'Cyan';

  @override
  String get settingsOverlayWaveViolett => 'Violet';

  @override
  String get settingsOverlayWaveNeutral => 'Neutral';

  @override
  String get settingsOverlayWaveAmber => 'Amber';

  @override
  String get settingsOverlayWaveInk => 'Ink';

  @override
  String get settingsOverlayWaveCoral => 'Coral';

  @override
  String get settingsOverlayWaveMint => 'Mint';

  @override
  String get settingsOverlayWaveUnavailable =>
      'Not clearly visible on this background';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '“$from” is not clearly visible on this background. The wave was changed to “$to”.';
  }

  @override
  String get settingsOverlayLiveTranscript => 'Live transcript';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'Show recognized text live while you\'re still speaking, instead of the waveform only. Uses extra CPU during recording';

  @override
  String get overlayRetry => 'Retry';

  @override
  String get overlayDismiss => 'Dismiss';

  @override
  String get overlayContextCancel => 'Cancel recording';

  @override
  String get overlayContextSwitchNormal => 'Switch to normal';

  @override
  String get overlayContextSwitchCompact => 'Switch to compact';

  @override
  String get overlayContextSwitchMini => 'Switch to mini';

  @override
  String get overlayContextHide => 'Hide overlay';

  @override
  String get buttonContextOpen => 'Open WhisPaste';

  @override
  String get buttonContextStartRecording => 'Start recording';

  @override
  String get buttonContextShowHistory => 'Show recordings';

  @override
  String get buttonContextSettings => 'Settings';

  @override
  String get buttonContextQuit => 'Quit WhisPaste';

  @override
  String get settingsHistory => 'Recordings';

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
  String get settingsHistoryRetentionPreset => 'Retention';

  @override
  String get settingsHistoryPresetMinimal => 'Minimal';

  @override
  String get settingsHistoryPresetStandard => 'Standard';

  @override
  String get settingsHistoryPresetUnlimited => 'Unlimited';

  @override
  String get settingsHistoryPresetCustom => 'Custom';

  @override
  String get settingsHistoryHideOnOpen => 'Hide recordings on open';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Shows a “Show recordings” button instead of your transcriptions whenever WhisPaste starts or its window reopens. Nothing is deleted.';

  @override
  String get historyPinGateTitle => 'Recordings are locked';

  @override
  String get historyPinGateHint =>
      'Enter your PIN to show your transcriptions.';

  @override
  String get historyImportUnlockHint =>
      'Unlock Recordings to transcribe the file.';

  @override
  String get historyPinUnlock => 'Unlock';

  @override
  String get historyPinDialogTitle => 'Enter PIN';

  @override
  String get historyPinDialogSubtitle =>
      'Your recordings are protected with a PIN.';

  @override
  String get historyPinFieldHint => 'PIN';

  @override
  String get historyPinRepeatHint => 'Repeat PIN';

  @override
  String get historyPinWrong => 'Wrong PIN.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get historyPinForgot => 'Forgot PIN?';

  @override
  String get historyPinForgotHint =>
      'Resetting immediately deletes all transcriptions, saved audio files, notes with their versions, and note images. If a file cannot be deleted, WhisPaste shows a notice.';

  @override
  String get historyPinForgotConfirmTitle =>
      'Delete recordings and notes and remove PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'A forgotten PIN cannot be recovered. To reset it, all transcriptions and saved audio files (including archive and trash), all notes with their versions (including trash) and all note images are deleted immediately and permanently. Settings, snippets and replacements are kept. If a file cannot be deleted, WhisPaste shows a notice.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'Some recordings, imports or note images could not be deleted. WhisPaste removes them the next time it starts.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'Some recordings or imports could not be deleted, and WhisPaste cannot retry later. Please delete them by hand. Location: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'A copy of the old database ($path) could not be deleted. Please delete it by hand.';
  }

  @override
  String get historyPinForgotConfirmAction => 'Delete';

  @override
  String get historyPinSetTitle => 'Set PIN';

  @override
  String get historyPinSetSubtitle =>
      '4–8 digits. Keeps others from casually viewing your transcriptions on this computer — it does not encrypt them.';

  @override
  String get historyPinInvalid => 'Use 4 to 8 digits.';

  @override
  String get historyPinMismatch => 'The PINs do not match.';

  @override
  String get settingsHistoryPin => 'PIN protection';

  @override
  String get settingsHistoryPinSubtitle =>
      'Require a PIN to show recordings and notes, including side panel, the floating button\'s menu and automation API.';

  @override
  String get settingsHistoryPinChange => 'Change';

  @override
  String get settingsHistoryPinRemove => 'Remove';

  @override
  String get settingsHistoryAutoLock => 'Lock automatically';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Hide recordings again after this much inactivity.';

  @override
  String get settingsHistoryAutoLockNever => 'Never';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'After $minutes min';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'Turn on the floating button to change this.';

  @override
  String get settingsFloatingButtonSection => 'Floating button';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Always-on-top recording button for quick access';

  @override
  String get settingsFloatingButtonWaylandTitle => 'Wayland limits';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'Under Wayland the desktop decides where the button appears and whether it stays on top. WhisPaste can only promise both to a limited extent there. Recording with a click still works, and the button does not take keyboard focus.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'Not available on this Linux desktop: the button needs X11 or XWayland. Turning it off is still possible.';

  @override
  String get settingsSttIdleTimeout => 'Speech model idle timeout';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'How long the speech model stays loaded after use';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Keep alive';

  @override
  String get settingsSttKeepLoaded => 'Keep model loaded';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'A loaded model starts recording without waiting for it to load. While it is loaded, it takes up memory.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'Loaded, the model needs about $size of memory.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'The GPU memory ($vramMb MB) is not enough for this model ($requiredMb MB). It runs on the processor.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'Always';

  @override
  String get settingsSttKeepLoadedAutomatic => 'Automatic';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'After idle time';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'Unload after';

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
  String get reviewPromptStarGitHub => 'Star on GitHub';

  @override
  String get reviewPromptRateStore => 'Rate on the Store';

  @override
  String get reviewSupportEntry => 'Rate & support WhisPaste';

  @override
  String get reviewSupportLabel => 'Rate the app';

  @override
  String get reviewSupportAction => 'Rate';

  @override
  String get reviewSupportGitHubLabel =>
      'Support WhisPaste with a star on GitHub';

  @override
  String get reviewSupportGitHubAction => 'View on GitHub';

  @override
  String get githubInviteTitle => 'WhisPaste is open source';

  @override
  String get githubInviteBody => 'A star on GitHub helps others find it.';

  @override
  String get githubInviteOpen => 'View on GitHub';

  @override
  String get githubInviteLater => 'Later';

  @override
  String get githubInviteNever => 'Don\'t ask again';

  @override
  String get ideasBoardLabel => 'Ideas & feature requests';

  @override
  String get ideasBoardAction => 'View board';

  @override
  String get feedbackIdeasLink => 'Suggest & vote on ideas';

  @override
  String get feedbackTypeProblem => 'Problem';

  @override
  String get feedbackTypeIdea => 'Idea';

  @override
  String get feedbackTypePraise => 'Praise';

  @override
  String get feedbackTypeQuestion => 'Question';

  @override
  String get feedbackPromptProblem =>
      'What went wrong? Tell us what you did and what happened.';

  @override
  String get feedbackPromptIdea => 'What would make WhisPaste better for you?';

  @override
  String get feedbackPromptPraise => 'What works well for you?';

  @override
  String get feedbackPromptQuestion => 'What would you like to know?';

  @override
  String get feedbackDiagnosticsLabel => 'Attach diagnostics';

  @override
  String get feedbackDiagnosticsExplanation =>
      'Adds the app version, operating system, speech engine and backend. Recordings and transcripts are never attached.';

  @override
  String get feedbackDiagnosticsPreview => 'Show preview';

  @override
  String get feedbackDiagnosticsPreviewHide => 'Hide preview';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'This exact text is added to your message:';

  @override
  String get feedbackIdeaBoardHint =>
      'You can also post your idea on the public ideas board and vote on others.';

  @override
  String get feedbackTextTooLong =>
      'The text is too long to attach the diagnostics. Shorten it a little.';

  @override
  String get hotkeyRegistrationFailed =>
      'Hotkey registration failed. Choose a new key combination in Settings.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken is already used by another app. Until you choose a different combination, $active starts a recording.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'Another app holds the hotkey for $action. It stays off until you pick a free combination in Settings.';
  }

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'This key combination is reserved by $platform ($note) and may not work.';
  }

  @override
  String get exportFormatPickerTitle => 'Choose export format';

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
      'Transcription is taking a little longer than usual right now, it\'s still working.';

  @override
  String get recoveryExhaustedToast =>
      'Speech model cannot start. Please restart the app or reload the speech model.';

  @override
  String get recoveryExhaustedAction => 'Open settings';

  @override
  String get recoveryVcRuntimeToast =>
      'Speech model cannot start: a Windows component is missing (Microsoft Visual C++). Please install the Visual C++ Redistributable (x64) and restart WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Install';

  @override
  String get modelAbiInfoToast => 'Reloading voice model, please wait.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste is now running without GPU acceleration due to a problem on the last launch. Recording still works as usual.';

  @override
  String get serverDownloadFailedToast =>
      'Speech model could not be downloaded. Check your internet connection?';

  @override
  String get serverDownloadFailedAction => 'Try again';

  @override
  String get serverDownloadStalledToast => 'Download stalled: reconnecting.';

  @override
  String get historyWriteFailedToast =>
      'Entry could not be saved, please check available storage.';

  @override
  String get historyWriteFailedAction => 'Copy diagnostics';

  @override
  String get errorSttRejectEmpty =>
      'No audio to transcribe, please record again.';

  @override
  String get errorSttRejectInvalidWav =>
      'Audio file is corrupted, please record again.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'This language is not supported by the local speech model, please review the language in Settings.';

  @override
  String get errorSttRejectPromptTooLong =>
      'Custom vocabulary is too long, please shorten it in Settings.';

  @override
  String get settingsGpuAcceleration => 'Graphics acceleration';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Automatic uses the graphics card when it is available. \"CPU only\" is slower but works on every device. Force GPU only if automatic mode doesn\'t work.';

  @override
  String get settingsGpuAccelerationAuto => 'Automatic (recommended)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (force)';

  @override
  String get settingsGpuAccelerationDisabled => 'CPU only';

  @override
  String get settingsSttEngine => 'Speech model';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 languages. Parakeet: faster, about 25 languages.';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet';

  @override
  String get settingsSttEngineRecommended => 'Recommended';

  @override
  String get parakeetModelTitle => 'Parakeet model';

  @override
  String parakeetModelSubtitle(String size) {
    return 'One-time download ($size), then runs fully offline';
  }

  @override
  String get parakeetModelDownload => 'Download';

  @override
  String get parakeetModelDownloading => 'Downloading…';

  @override
  String get parakeetModelInstalled => 'Installed';

  @override
  String get parakeetModelDelete => 'Delete';

  @override
  String get parakeetModelCancel => 'Cancel';

  @override
  String get settingsSearchHint => 'Search settings…';

  @override
  String get settingsSearchNoResults => 'No results';

  @override
  String get settingsSearchNoResultsHint => 'Try a different search term.';

  @override
  String get settingsSearchFieldLabel => 'Search settings';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsPrivacySubtitle => 'Control what data WhisPaste shares';

  @override
  String get settingsShareUsageStats => 'Share anonymous usage statistics';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Anonymous usage counts, no cookies, not linked to you. Helps us see which features are used. Your text and audio are never included.';

  @override
  String get settingsRetainRecentAudio => 'Keep audio of recent recordings';

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'Keep the audio of your last $count recordings on this device for debugging or restoring a past transcript; recordings and imported files are deleted automatically after $days days at most';
  }

  @override
  String get pendingAudioRetentionNote =>
      'A recording whose transcription failed keeps its audio for up to 24 hours, so you can try again, even when this is off.';

  @override
  String get pendingAudioSectionTitle => 'Recordings waiting for a retry';

  @override
  String get pendingAudioSectionBody =>
      'These recordings could not be transcribed, for example because the connection dropped. The audio is deleted after 24 hours at most, or when you discard it.';

  @override
  String get pendingAudioEmpty => 'No recordings are waiting.';

  @override
  String get featureSpotlightHeading => 'New in WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Got it';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Snippet picker';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Save reusable text blocks and insert them anywhere with a hotkey or a spoken trigger — no retyping needed.';

  @override
  String get featureSpotlightSidePanelTitle => 'Clipboard side panel';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Hover the screen edge to open your recent clipboard history and drag any item straight into your document.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle => 'Interactive snippets';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'Snippets with blanks: WhisPaste walks you through each field — speak, press Enter for the next one, and the finished text is pasted in one piece.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Clean up, shorten, or translate your text before it is pasted — fully on-device, with its own hotkey, preset, and target language.';

  @override
  String get featureSpotlightHistoryPinTitle =>
      'Lock your recordings with a PIN';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'Keep your transcriptions private behind a PIN — including the side panel and the floating button menu — with optional auto-lock after inactivity. Settings → Recordings.';

  @override
  String get featureSpotlightEditSelectionTitle =>
      'Edit selected text by voice';

  @override
  String get featureSpotlightEditSelectionDescription =>
      'Select text in any app, press the edit-selection hotkey and say what should change — or just “shorter”, “improve” or “translate”. Uses the Smart Mode text model. Off by default: turn it on under Settings → Smart Mode.';

  @override
  String get featureSpotlightChangelogLink => 'View full changelog';

  @override
  String get featureSpotlightReviewLabel => 'Review the new features';

  @override
  String get featureSpotlightReviewAction => 'Show';

  @override
  String get notesNewNote => 'New note';

  @override
  String get notesEmptyTitle => 'No notes yet';

  @override
  String get notesEmptyHint =>
      'Create a note to start collecting text from anywhere.';

  @override
  String get notesUntitled => 'Untitled note';

  @override
  String get notesEditorPlaceholder => 'Start typing…';

  @override
  String get notesListSemantics => 'Notes list';

  @override
  String get notesCopy => 'Copy note';

  @override
  String get notesCopied => 'Note copied';

  @override
  String get notesFavorite => 'Mark as favorite';

  @override
  String get notesUnfavorite => 'Remove from favorites';

  @override
  String get notesQuickNoteSet =>
      'Make this the quick note the hotkey appends to';

  @override
  String get notesQuickNoteClear => 'Quick note — remove the mark';

  @override
  String get notesQuickNoteHotkeyLabel => 'Hotkey';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'Change the quick-note hotkey — currently $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff =>
      'The quick-note hotkey is switched off.';

  @override
  String get notesQuickNoteHotkeyEnable => 'Turn hotkey on';

  @override
  String get notesMoveToTrash => 'Move to trash';

  @override
  String get notesMovedToTrash => 'Moved to trash';

  @override
  String get notesRestore => 'Restore';

  @override
  String get notesDeleteForever => 'Delete forever';

  @override
  String get notesDeleteForeverConfirm => 'Delete note forever?';

  @override
  String get notesTrash => 'Trash';

  @override
  String get notesTrashEmpty => 'Trash is empty';

  @override
  String get notesTrashEmptyHint =>
      'Deleted notes land here and aren\'t removed automatically.';

  @override
  String get notesUndo => 'Undo';

  @override
  String get notesAddTag => 'Add tag';

  @override
  String get notesTagPlaceholder => 'Tag name…';

  @override
  String get notesSearchPlaceholder => 'Search notes…';

  @override
  String get notesSearchFieldLabel => 'Search notes';

  @override
  String get notesNoResults => 'No results';

  @override
  String notesNoResultsHint(String query) {
    return 'No notes match \"$query\".\nTry a different search term.';
  }

  @override
  String notesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get notesExport => 'Export';

  @override
  String markdownToolbarBold(String shortcut) {
    return 'Bold ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'Italic ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'Heading';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'Bullet list ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'Numbered list';

  @override
  String get markdownToolbarQuote => 'Quote';

  @override
  String get markdownToolbarCode => 'Code';

  @override
  String get findReplaceToggle => 'Find and replace in this text';

  @override
  String get findReplaceFindLabel => 'Find in this text';

  @override
  String get findReplaceFindHint => 'Find…';

  @override
  String get findReplaceReplaceLabel => 'Replace matches with';

  @override
  String get findReplaceReplaceHint => 'Replace with…';

  @override
  String get findReplaceNext => 'Next match';

  @override
  String get findReplacePrevious => 'Previous match';

  @override
  String get findReplaceReplaceAction => 'Replace this match';

  @override
  String get findReplaceReplaceAllAction => 'Replace all matches';

  @override
  String get findReplaceClose => 'Close find and replace';

  @override
  String get findReplaceNoMatches => 'No matches';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current of $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'Transcriptions';

  @override
  String get sidePanelSnippetsTitle => 'Snippets';

  @override
  String get sidePanelClipboardHistoryTitle => 'Clipboard history';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Nothing copied yet';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Anything you copy while WhisPaste is running shows up here — cleared when the app restarts.';

  @override
  String get sidePanelClipboardLockedTitle => 'Locked by PIN';

  @override
  String get sidePanelClipboardLockedHint =>
      'Copied text stays hidden while the recordings are locked. Unlock them with your PIN to see it again.';

  @override
  String get sidePanelClose => 'Close panel';

  @override
  String get sidePanelSearchHint => 'Search';

  @override
  String get sidePanelSearchFieldLabel => 'Search this list';

  @override
  String get sidePanelNoMatches => 'No matches';

  @override
  String get sidePanelNoMatchesHint => 'Try a different search term.';

  @override
  String get sidePanelLoadFailedHint =>
      'Close and reopen the panel to try again.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Local text cleanup, shortening, and translation after recording';

  @override
  String get smartModeStandardPreset => 'Standard preset';

  @override
  String get smartModePresetOff => 'Off';

  @override
  String get smartModePresetOffDescription =>
      'No automatic post-processing — the text is used exactly as transcribed.';

  @override
  String get smartModePresetCleanup => 'Cleanup';

  @override
  String get smartModePresetCleanupDescription =>
      'Removes filler words like \"um\" and fixes punctuation and capitalization, without changing the wording, meaning, or language.';

  @override
  String get smartModePresetConcise => 'Concise';

  @override
  String get smartModePresetConciseDescription =>
      'Shortens the text by removing redundancy and filler while keeping every important fact, in the same language.';

  @override
  String get smartModePresetTranslate => 'Translate';

  @override
  String get smartModePresetTranslateDescription =>
      'Translates the transcribed text into the target language set below.';

  @override
  String get smartModeTargetLanguage => 'Target language';

  @override
  String get smartModeTargetLanguageGerman => 'German';

  @override
  String get smartModeTargetLanguageEnglish => 'English';

  @override
  String get smartModeTargetLanguageSpanish => 'Spanish';

  @override
  String get smartModeTargetLanguageFrench => 'French';

  @override
  String get smartModeTargetLanguagePortuguese => 'Portuguese';

  @override
  String get smartModeTargetLanguageMandarin => 'Mandarin';

  @override
  String get smartModeTargetLanguageRussian => 'Russian';

  @override
  String get smartModeDownload => 'Download';

  @override
  String get smartModeDownloadComplete => 'Text model ready to use';

  @override
  String get smartModeRamWarningTitle => 'Limited memory detected';

  @override
  String get smartModeRamWarningBody =>
      'Smart Mode\'s local text model runs best with 8 GB of RAM or more. It may still work, but could run slowly or fail on this machine. Download anyway?';

  @override
  String get smartModeRamWarningContinue => 'Download anyway';

  @override
  String get smartModeRamWarningCancel => 'Cancel';

  @override
  String get smartModeModelDeleteConfirm => 'Delete this text model?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'The text model file is deleted from this device. You can re-download it any time.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Runs fully on-device. While active, the text model uses about 4–5 GB of RAM in addition to disk space — shared with the speech model, so total memory use depends on which speech model you also have loaded.';

  @override
  String get smartModeFactGuardHint =>
      'The fact guard checks numbers, dates, links, e-mail addresses and IBANs. Dictionary names stay intact. Free instructions can change names that are not in the dictionary – add them to the dictionary if they must stay.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Example: a typical 50-word recording takes roughly 1–6 seconds to process, depending on your device\'s hardware.';

  @override
  String get smartModeLocalUnavailable =>
      'On-device Smart Mode isn\'t included in this build. Switch to OpenAI, or install an official WhisPaste release.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Record with Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Starts a recording with a fixed preset, independent of your standard preset in Smart Mode. “Hold to record” applies here too.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Preset';

  @override
  String get settingsSmartModeCurrentHotkey => 'Current hotkey';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'This combination is already used for \"$action\". Pick a different one.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'This combination could not be registered — the Smart-Mode hotkey is currently not active. Pick a different combination.';

  @override
  String get smartModeOnboardingHintTitle => 'Try Smart Mode';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'Smart Mode can clean up, shorten, or translate your text automatically — fully on-device. The local text model takes $size on disk. Download it now, or set it up later in Settings.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Raw text';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'so um the client meeting got moved to thursday at three pm and uh we still need the updated slides from marketing';

  @override
  String get smartModeOnboardingHintExampleAfterLabel => 'Smart Mode result';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'So, the client meeting got moved to Thursday at three PM, and we still need the updated slides from Marketing.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Download';

  @override
  String get smartModeOnboardingHintSkipCta => 'Later';

  @override
  String get smartModeUsageHintTitle => 'Try Smart Mode on your next recording';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode can clean up, shorten, or translate text like this automatically, right on your device. Here\'s what you just said:';

  @override
  String get smartModeUsageHintCta => 'Set up';

  @override
  String get smartModeUsageHintDismiss => 'Not now';

  @override
  String get settingsAutomationApi => 'Local automation API';

  @override
  String get settingsAutomationApiSubtitle =>
      'Other programs and scripts on this computer can control WhisPaste, for example start a recording. Devices on your network can\'t reach it.';

  @override
  String get settingsAutomationApiEnable => 'Enable local automation API';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'Binds only to 127.0.0.1/::1 — never reachable from the network';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'Running on port $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'Running on port $port (port $requestedPort was in use)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'Not running';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'No free port found in range $start–$end';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'Custom port';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'Leave empty for automatic port selection — falls back automatically if it\'s taken';

  @override
  String get settingsAutomationApiCustomPortHint => 'Automatic';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'Enter a port between 1024 and 65535';

  @override
  String get settingsAutomationApiToken => 'Bearer token';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'Send it as \"Authorization: Bearer <token>\" — every request without it is rejected';

  @override
  String get settingsAutomationApiRegenerate => 'Regenerate';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle => 'Regenerate token?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'The current token stops working immediately. Any script using it will need the new one.';

  @override
  String get settingsAutomationApiCopyToken => 'Copy token';

  @override
  String get settingsAutomationApiTokenCopied => 'Token copied to clipboard';

  @override
  String get settingsAutomationApiDocumentation => 'Documentation';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'Endpoint reference and curl examples';

  @override
  String get settingsAutomationApiDocumentationAction => 'Open';

  @override
  String historyCharacterCount(int count) {
    return '$count characters';
  }

  @override
  String historyPastedInto(String app) {
    return 'Pasted into $app';
  }

  @override
  String get historyShowOriginalTranscript => 'Show original transcript';

  @override
  String get historyHideOriginalTranscript => 'Hide original transcript';

  @override
  String get historyOriginalTranscriptLabel => 'Original transcript';

  @override
  String get settingsHotkeyActionSelectionEdit => 'Edit selection';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'Edit selection';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Select text in any app, press this hotkey and say what to change — or just \"shorter\", \"improve\" or \"translate\". The result replaces the selection; undo in the app brings the original back. Uses the text model set up in Smart Mode.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'This combination could not be registered — the edit-selection hotkey is currently not active. Pick a different combination.';

  @override
  String get overlayTargetSelectionEdit => 'Edit selection';

  @override
  String get overlayRecordingSelectionEdit => 'Say what to change';

  @override
  String get overlaySelectionEditHint =>
      'Say what to change — or: shorter · improve · translate';

  @override
  String get overlayEditingSelection => 'Editing selection…';

  @override
  String get overlayDoneSelectionEdit => 'Selection replaced';

  @override
  String get errorSelectionEditNoSelection =>
      'No text selected — select text first, then press the hotkey';

  @override
  String get errorSelectionEditNoEngine =>
      'Set up Smart Mode first (download the local text model or add an OpenAI key) to edit selections';

  @override
  String get errorSelectionEditUnsupported =>
      'Editing a selection needs auto-paste, which is not available in this build';

  @override
  String get errorSelectionEditCopyFailed =>
      'Could not read the selection — check the auto-paste permission';

  @override
  String get errorSelectionEditFailed =>
      'Editing failed — your text was left unchanged';

  @override
  String get errorSelectionEditFactsChanged =>
      'The edit would have changed facts your instruction does not mention — your text was left unchanged';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'The edit would change “$value” without your instruction naming it. Name the old and new value, e.g. “change 3 to 5” — your text was left unchanged';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'Could not replace the selection — your text was left unchanged';

  @override
  String get settingsCudaPackTitle => 'NVIDIA CUDA acceleration';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Faster transcription on GeForce RTX and GTX 16 cards. One-time download of $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Installed. If your graphics driver is too old, WhisPaste keeps using Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'Consent required';

  @override
  String get settingsCudaPackConsentReview => 'Review licence';

  @override
  String get settingsCudaPackDownload => 'Download';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'Downloading $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'Installing …';

  @override
  String get settingsCudaPackCancel => 'Cancel download';

  @override
  String get settingsCudaPackRemove => 'Remove CUDA pack';

  @override
  String get settingsCudaPackRemoveConfirm => 'Remove CUDA pack?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'The CUDA pack is removed from this device. You can download it again any time.';

  @override
  String get settingsCudaPackToggle => 'Use CUDA';

  @override
  String get settingsCudaPackErrorNetwork =>
      'Download failed. Check your connection and try again.';

  @override
  String get settingsCudaPackErrorVerification =>
      'The download was damaged. Please try again.';

  @override
  String get settingsCudaPackErrorStorage =>
      'The pack could not be saved. Check your free disk space.';

  @override
  String get cudaEulaDialogTitle => 'NVIDIA CUDA licence';

  @override
  String cudaEulaDialogBody(String version) {
    return 'The CUDA pack contains NVIDIA components under the NVIDIA CUDA End User License Agreement ($version). You agree to the full text of this version, which you can read via “Full text”. A further version at NVIDIA may differ. You need to accept it to download.';
  }

  @override
  String get cudaEulaDialogLink => 'Further version at NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'Full text';

  @override
  String get cudaEulaFullTextClose => 'Close';

  @override
  String get cudaEulaDialogCancel => 'Cancel';

  @override
  String get cudaEulaDialogAccept => 'Accept and download';

  @override
  String get recoveryCudaDisabledToast =>
      'CUDA acceleration was switched off because of a problem on the last launch. WhisPaste now uses Vulkan, recording works as usual.';

  @override
  String get supportPromptSnooze => 'Don\'t ask for 90 days';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'Thank you for buying WhisPaste in the store. Any further support is optional.';

  @override
  String get supportShareText =>
      'I use WhisPaste to speak text straight into my apps. Local on my computer and open source:';

  @override
  String get supportPageTitle => 'Support WhisPaste';

  @override
  String get supportIntroDirect =>
      'WhisPaste is free and open source. A contribution or recommendation helps the project.';

  @override
  String get supportCostsNote =>
      'Contributions help cover development and the ongoing costs of publishing, hosting and the domain.';

  @override
  String get supportSectionOnce => 'One-time support';

  @override
  String get supportSectionOthers => 'Other ways to support';

  @override
  String get supportSectionReach => 'Recommend WhisPaste';

  @override
  String get supportStoreTitleWindows => 'WhisPaste in the Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste in the Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'Installation and updates are handled by the store.';

  @override
  String get supportStoreFactPurchase =>
      'Your one-time purchase supports WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'Same features. The direct version stays free to use.';

  @override
  String get supportStoreCtaWindows => 'View in Microsoft Store';

  @override
  String get supportStoreCtaMac => 'View in Mac App Store';

  @override
  String get supportStorePriceNote => 'Price in the store';

  @override
  String get supportStoreCoffeeNote =>
      'A one-time purchase, roughly the price of a coffee. The store shows the current price.';

  @override
  String get supportStoreDismiss => 'Hide store option';

  @override
  String get supportStoreShowAgain => 'Show store option';

  @override
  String get supportSponsorsCta => 'Open GitHub Sponsors';

  @override
  String get supportSponsorsNote =>
      'Monthly or with an amount you choose. Pick the amount and rhythm there.';

  @override
  String get supportKofiCta => 'Open Ko-fi';

  @override
  String get supportPayPalCta => 'Support with PayPal';

  @override
  String get supportNativeTitle => 'Support once in the store';

  @override
  String get supportNativeDescription =>
      'A one-time amount, billed by the store. Same features, no subscription.';

  @override
  String get supportNativeCta => 'Support once';

  @override
  String get supportSheetChoose => 'Choose an amount';

  @override
  String get supportSheetLoading => 'Loading amounts …';

  @override
  String supportSheetBuy(String price) {
    return 'Support for $price';
  }

  @override
  String get supportSheetPurchasing =>
      'The store is confirming your purchase …';

  @override
  String get supportSheetThanks => 'Thank you for your support!';

  @override
  String get supportSheetThanksDetail =>
      'Your supporter badge is active now. All features stay available to everyone.';

  @override
  String get supportSheetPending => 'Your purchase is awaiting confirmation.';

  @override
  String get supportSheetPurchaseError =>
      'The purchase could not be completed. Please try again later.';

  @override
  String get supportSheetPricesError =>
      'Prices couldn\'t be loaded. Please try again later.';

  @override
  String get supportSheetUnavailable =>
      'No amounts are available in the store right now.';

  @override
  String get supportSheetRetry => 'Try again';

  @override
  String get supportSheetClose => 'Close';

  @override
  String get supportSelfDeclareCta => 'I already support WhisPaste';

  @override
  String get supportSelfDeclareNote =>
      'Just a note on this device, nothing is verified. The sponsor button in the status bar is hidden.';

  @override
  String get supportSelfDeclareHint =>
      'Nothing is verified. Use this if you already contributed.';

  @override
  String get supportSupporterLine => 'You support WhisPaste. Thank you!';

  @override
  String get supportSupporterBadge => 'Supporter';

  @override
  String get supportRateCta => 'Rate in the store';

  @override
  String get supportShareCopy => 'Copy link';

  @override
  String get supportShareCopied => 'Link copied';

  @override
  String get externalLinkOpenFailed => 'The link couldn\'t be opened';

  @override
  String get externalLinkCopyAddress => 'Copy address';

  @override
  String get supportShareEmail => 'Email';

  @override
  String get supportChipLabel => 'Sponsor';

  @override
  String get supportChipTooltip => 'Support WhisPaste';

  @override
  String get supportChipThanksLabel => 'Thanks';

  @override
  String get supportChipThanksTooltip => 'Thank you for your support';

  @override
  String get settingsSponsorChip => 'Sponsor button in the status bar';

  @override
  String get settingsSponsorChipSubtitle =>
      'Shows the way to the support page. You can hide it at any time and show it again here.';

  @override
  String get automationPreviewTitle => 'Insert multiline text?';

  @override
  String get automationPreviewBody =>
      'An automation wants to insert text with line breaks. Check it before it reaches the active app.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'Insert';

  @override
  String get automationPreviewCancel => 'Cancel';

  @override
  String get automationIntegrationsHeading => 'Integrations';

  @override
  String get automationIntegrationsHooksTitle => 'Send events to other apps';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'Send finished transcripts and changed notes to an app on this computer. Hooks keep firing even when the API server is off.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hooks',
      one: '1 hook',
      zero: 'No hooks',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'Manage';

  @override
  String get automationIntegrationsCliTitle => 'Command line and MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'Source checkouts only. Run $path with $token set; the $command command starts the MCP server.';
  }

  @override
  String get automationHooksIntro =>
      'Finished transcripts and changed notes go to an app on this computer. The address has to be on this device.';

  @override
  String get automationHooksEmpty => 'No connection set up yet.';

  @override
  String get automationHooksUrlLabel => 'Target address (this computer only)';

  @override
  String get automationHooksEventsLabel => 'Events';

  @override
  String get automationHooksEventTranscript => 'Transcript finished';

  @override
  String get automationHooksEventNote => 'Note changed';

  @override
  String get automationHooksAdd => 'Add hook';

  @override
  String get automationHooksRemove => 'Remove hook';

  @override
  String get automationHooksRemoveConfirm => 'Remove this hook?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'The hook is removed from the list. You can add it again later.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'Use $ipv4, $ipv6 or $localhost with a port, for example $example.';
  }

  @override
  String get automationHooksNoEvents => 'Choose at least one event.';

  @override
  String automationHooksTooMany(int max) {
    return 'You can add up to $max hooks.';
  }

  @override
  String get automationHooksDone => 'Done';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'Dictate';

  @override
  String get dockOverflow => 'More';

  @override
  String get dockMenuGroupStatus => 'Status';

  @override
  String get dockMenuGroupNotices => 'Notices';

  @override
  String get dockMenuHotkeyChange => 'Change shortcut…';

  @override
  String get dockMenuSmartModeSettings => 'Smart Mode settings…';

  @override
  String get dockMenuSttModels => 'Manage speech models…';

  @override
  String get dockMenuGroupCloud => 'Cloud';

  @override
  String get dockMenuModelDownload => 'Download';

  @override
  String get dockMenuModelLoading => 'loading';

  @override
  String get dockMenuSttLockedReason => 'Locked during a recording';

  @override
  String get dockMenuSearchHint => 'Search…';

  @override
  String get dockMenuSearchNoMatches => 'No matches';

  @override
  String get dockMenuAppliesNextRecording => 'Applies from the next recording';

  @override
  String get dockStopDictation => 'Stop recording';

  @override
  String get historyImportAddFiles => 'Add files';

  @override
  String historyImportDescription(String formats) {
    return 'Transcribe audio files ($formats) on this device. Drag files onto this page or add them.';
  }

  @override
  String get historyImportQueueTitle => 'Import queue';

  @override
  String get historyImportStatusQueued => 'Waiting';

  @override
  String get historyImportStatusCopying => 'Copying';

  @override
  String get historyImportStatusDecoding => 'Decoding';

  @override
  String get historyImportStatusTranscribing => 'Transcribing';

  @override
  String get historyImportStatusDone => 'Done';

  @override
  String get historyImportStatusFailed => 'Failed';

  @override
  String get historyImportStatusCancelled => 'Cancelled';

  @override
  String get historyImportFailureCopy =>
      'The file could not be copied. Check that it still exists and can be read, then try again.';

  @override
  String get historyImportFailureUnsupported =>
      'This format is not supported on this platform. Convert the file to WAV and import it again.';

  @override
  String get historyImportFailureDecode =>
      'The file could not be decoded. It is probably damaged or incomplete. Import another copy or convert it to WAV.';

  @override
  String get historyImportFailureInputLimit =>
      'The file is too large or longer than 6 hours. Please split it into shorter parts.';

  @override
  String get historyImportFailureTranscription =>
      'Transcription failed. Check speech recognition in Settings, then try again.';

  @override
  String get historyImportFailureSave =>
      'The transcript could not be saved. Check the free disk space, then try again.';

  @override
  String get historyImportRejectedFolder =>
      'Folders cannot be imported. Choose the audio files inside them.';

  @override
  String get historyImportRejectedNotFound => 'The file was not found.';

  @override
  String historyImportRejectedType(String formats) {
    return 'This file type cannot be imported. Supported: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'The file dialog could not be opened. Try again, or drag the files onto this page.';

  @override
  String get historyImportDropHere =>
      'Drop audio files here to transcribe them';

  @override
  String get historyImportCancel => 'Cancel import';

  @override
  String get historyImportRetry => 'Retry import';

  @override
  String get recoveryOffer =>
      'An interrupted recording was found. Recover its audio and transcribe it?';

  @override
  String get recoveryNoAudioKept =>
      'An interrupted recording was found, but no audio was kept because audio retention is off.';

  @override
  String get recoveryNoAudioCaptured =>
      'An interrupted recording was found, but it holds no audio.';

  @override
  String get recoveryRestore => 'Recover';

  @override
  String get recoveryDiscard => 'Discard';

  @override
  String get recoveryDiscardConfirm => 'Discard this recording?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'This interrupted recording is removed from this device, together with any audio it kept.';

  @override
  String get recoveryFailed =>
      'Recovery failed. The audio was kept, so you can try again.';

  @override
  String recoverySkippedCorrupt(int count) {
    return '$count damaged recovery entries were skipped and kept on disk.';
  }

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupDictation => 'Voice input';

  @override
  String get settingsGroupSystem => 'System';

  @override
  String get settingsAreaGeneral => 'General';

  @override
  String get settingsAreaAppearance => 'Appearance';

  @override
  String get settingsAreaShortcuts => 'Keyboard shortcuts';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'Keyboard shortcut: $combo';
  }

  @override
  String get settingsAreaRecording => 'Recording & audio';

  @override
  String get settingsAreaSpeech => 'Speech recognition';

  @override
  String get settingsAreaTextInsert => 'Text & insertion';

  @override
  String get settingsAreaPrivacy => 'Privacy & data';

  @override
  String get settingsAreaAdvanced => 'Advanced';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'Up to date';

  @override
  String get settingsNavUpdateAvailable => 'Update available';

  @override
  String get settingsNavStoreUpdates => 'Updates via the Store';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'The store delivers updates for this build. Checking for updates in the app is not available here.';

  @override
  String get settingsStoreBetaUnavailable =>
      'Preview builds are not offered in the store build.';

  @override
  String get settingsStoreCudaUnavailable =>
      'Not available in the store build, driver downloads outside the store are not allowed there.';

  @override
  String get settingsOverlayPreview => 'Overlay preview';

  @override
  String get settingsPreviewTitle => 'Preview';

  @override
  String get settingsPreviewHint =>
      'This is how the overlay and button look while recording. Changes apply right away.';

  @override
  String get settingsPreviewOverlayCaption => 'Overlay';

  @override
  String get settingsOverlayOptionsGroup => 'Overlay';

  @override
  String get settingsOverlayForm => 'Shape';

  @override
  String get settingsOverlayFormSubtitle => 'Pill or rounded rectangle.';

  @override
  String get settingsOverlayFormPill => 'Pill';

  @override
  String get settingsOverlayFormRoundedRect => 'Rounded';

  @override
  String get settingsOverlayWaveStyle => 'Wave style';

  @override
  String get settingsOverlayWaveStyleSubtitle =>
      'How your voice is drawn in the overlay.';

  @override
  String get settingsOverlayWaveBars => 'Bars';

  @override
  String get settingsOverlayWaveLine => 'Line';

  @override
  String get settingsOverlayWaveDots => 'Dots';

  @override
  String get settingsOverlayWaveFluid => 'Fluid outline';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'The edge reacts to your voice. Off when reduce motion is on.';

  @override
  String get settingsOverlayShowTimer => 'Show timer';

  @override
  String get settingsOverlayShowTimerSubtitle =>
      'Show the elapsed recording time in the overlay.';

  @override
  String get settingsOverlayShowCancel => 'Cancel symbol';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'Stop always stays visible. Esc still cancels.';

  @override
  String get settingsOverlayOpacity => 'Opacity';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'Raised automatically when the wave would otherwise be too faint.';

  @override
  String get settingsOverlayOpacityFull => '100 %';

  @override
  String get settingsOverlayOpacityReduced => '80 %';

  @override
  String get settingsOverlayOpacitySubtle => '60 %';

  @override
  String get settingsFloatingButtonSize => 'Size';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Diameter of the floating button';

  @override
  String get settingsFloatingButtonSizeSmall => 'Small';

  @override
  String get settingsFloatingButtonSizeMedium => 'Medium';

  @override
  String get settingsFloatingButtonSizeLarge => 'Large';

  @override
  String get settingsFloatingButtonShape => 'Shape';

  @override
  String get settingsFloatingButtonShapeSubtitle => 'Round or rounded square';

  @override
  String get settingsFloatingButtonShapeRound => 'Round';

  @override
  String get settingsFloatingButtonShapeSquare => 'Rounded square';

  @override
  String get settingsFloatingButtonRing => 'Recording ring';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'Coloured ring around the button while recording';

  @override
  String get settingsFloatingButtonIdleOpacity => 'Opacity when idle';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'How visible the button is when not recording';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'Shared (colours)';

  @override
  String get settingsAreaSmartMode => 'Smart Mode';

  @override
  String get settingsAreaDictionary => 'Dictionary';

  @override
  String get settingsSearchEmptyHelp => 'Search in help';

  @override
  String get dictionaryTabTerms => 'Terms';

  @override
  String get dictionaryTabReplacements => 'Replacements';

  @override
  String get dictionaryTabSuggestions => 'Suggestions';

  @override
  String get dictionaryTermsEffectPrompt =>
      'Passed to the speech recogniser as a hint. It can favour these spellings but never changes text by itself.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'The active speech engine takes no hints. Only replacements change the text. Your terms stay saved.';

  @override
  String get dictionaryTermsHelp =>
      'Names, jargon and acronyms the recogniser often gets wrong. Separate them with commas or line breaks.';

  @override
  String get dictionaryReplacementsHelp =>
      'Only add words the recogniser actually gets wrong. Correctly recognised words stay untouched.';

  @override
  String get dictionaryTestTitle => 'Try it';

  @override
  String get dictionaryTestInputLabel => 'Sample sentence';

  @override
  String get dictionaryTestInputHint =>
      'Type a sentence to see which replacements apply.';

  @override
  String get dictionaryTestResultLabel => 'Result';

  @override
  String get dictionaryTestNoChange => 'No replacement applies.';

  @override
  String get dictionaryCsvTitle => 'Import and export (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'One line per entry: triggers separated by $pipe, replacement text, match mode (exact or fuzzy), threshold.';
  }

  @override
  String get dictionaryCsvImport => 'Import CSV';

  @override
  String get dictionaryCsvExport => 'Export CSV';

  @override
  String get dictionaryCsvExportEmpty =>
      'There are no replacements to export yet.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'This file is larger than 1 MB. Split it into smaller files.';

  @override
  String get dictionaryCsvImportReadError => 'The file could not be read.';

  @override
  String get dictionaryCsvImportNothing => 'No valid entries found.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    return '$count lines were skipped because they are incomplete or invalid.';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    return 'Only the first $count entries were read.';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return '$added entries added.';
  }

  @override
  String get dictionaryCsvExportFailed => 'The CSV file couldn\'t be saved.';

  @override
  String dictionaryCsvExportDone(int count) {
    return '$count entries exported.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'Line $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'Too few columns.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'No trigger phrase.';

  @override
  String get dictionaryCsvReasonTriggerTooLong =>
      'The trigger phrase is too long.';

  @override
  String get dictionaryCsvReasonEmptyReplacement => 'No replacement text.';

  @override
  String get dictionaryCsvReasonReplacementTooLong =>
      'The replacement text is too long.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'Match mode must be exact or fuzzy.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'The threshold must be strict, standard, tolerant or a number from 0.5 to 1.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'The line contains a control or hidden formatting character, or a line break.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'Too many trigger phrases in one line (at most $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'Check the entries';

  @override
  String get dictionaryDuplicateBadge => 'Duplicate';

  @override
  String get dictionaryDuplicateHint =>
      'Another entry uses the same trigger. The entry listed first applies.';

  @override
  String dictionaryUsageCount(int count) {
    return 'Used $count×';
  }

  @override
  String get dictionaryFavouriteLabel => 'Favourite';

  @override
  String dictionarySuggestionsHint(int count) {
    return 'A suggestion appears once the same correction was made $count times. Nothing is added without your confirmation.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'No suggestions yet';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'When you correct the same word twice, WhisPaste offers a replacement here.';

  @override
  String get dictionarySuggestionAccept => 'Accept';

  @override
  String get dictionarySuggestionReject => 'Dismiss';

  @override
  String get dictionarySuggestionAccepted => 'Replacement added.';

  @override
  String get dictionarySuggestionRejected =>
      'Suggestion dismissed. It will not come back.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'Entries marked “will be added” go into your list. Existing entries stay as they are.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return 'Add $count entries';
  }

  @override
  String get dictionaryCsvImportEncodingError => 'The file is not UTF-8 text.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'This file uses a package format this app cannot read.';

  @override
  String get dictionaryCsvRefusedType =>
      'This file is not a replacement dictionary package.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'Package: $name (created $date)';
  }

  @override
  String get dictionaryCsvPackageNone =>
      'No package info (older or foreign file)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'New: $added · Duplicates: $duplicates · Conflicts: $conflicts · Circular references: $circular · Invalid: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel => 'When a trigger already exists';

  @override
  String get dictionaryCsvStrategySkip => 'Skip';

  @override
  String get dictionaryCsvStrategyOverwrite => 'Overwrite';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'Keep both';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'The row is not imported. Existing entries stay unchanged.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'The shared trigger is removed from the old entry and the row is added. $changed existing entries change or are deleted.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'The row is added as well. For the same trigger, the existing entry that comes first in the list still applies.';

  @override
  String get dictionaryCsvStatusAdded => 'will be added';

  @override
  String get dictionaryCsvStatusDuplicate => 'already present';

  @override
  String get dictionaryCsvStatusConflictSkipped => 'conflict, skipped';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'conflict, replaces the existing trigger';

  @override
  String get dictionaryCsvStatusConflictKept => 'conflict, added alongside';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'replaced by a later row in this file';

  @override
  String get dictionaryCsvStatusCircular => 'circular reference, not imported';

  @override
  String get dictionaryCsvRowWillAdd => 'Will be added';

  @override
  String get dictionaryCsvRowSkipped => 'Duplicate, skipped';

  @override
  String get dictionaryCsvExportSelectTitle => 'Choose entries to export';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return '$count entries to choose from';
  }

  @override
  String get dictionaryCsvAllPresent =>
      'All entries are already present. Nothing will be written.';

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'Export ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'Too many entries for one file: $count. Choose fewer (at most 5000 entries, 1 MiB).';
  }

  @override
  String get settingsBetaGroupHeading => 'Pre-releases';

  @override
  String get analyticsWordingTitle => 'Wording';

  @override
  String get analyticsWordingPanelTitle => 'Words: raw vs. revised';

  @override
  String get analyticsRawWords => 'Raw words';

  @override
  String get analyticsRevisedWords => 'Revised words';

  @override
  String get analyticsTransformActions => 'Recordings revised by actions';

  @override
  String get analyticsCorrectionsTitle => 'Frequent corrections';

  @override
  String get analyticsNoCorrections => 'No corrections recorded yet.';

  @override
  String get errorNoticeNoModelCause => 'No speech model is installed.';

  @override
  String get errorNoticeNoModelNext =>
      'Download a model in Settings, then try again.';

  @override
  String get errorNoticeMicCause =>
      'WhisPaste has no access to the microphone.';

  @override
  String get errorNoticeMicNext =>
      'Allow access in your system settings, then try again.';

  @override
  String get errorNoticeTranscribeCause => 'Transcription failed.';

  @override
  String get errorNoticeTranscribeNext =>
      'Try again. If it keeps failing, restart WhisPaste or choose another model in Settings.';

  @override
  String get errorNoticeCpuCause =>
      'The GPU could not be used for this transcription.';

  @override
  String get errorNoticeCpuNext =>
      'It ran on the CPU instead, which is slower. Check GPU acceleration in Settings.';

  @override
  String get languageMismatchHint =>
      'The detected language does not match your setting.';

  @override
  String get languageMismatchSwitch => 'Switch language';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'Parakeet cannot transcribe $language. Switch to Whisper?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'Switch to Whisper';

  @override
  String get titleBarMinimizeLabel => 'Minimize window';

  @override
  String get titleBarCloseLabel => 'Close window';

  @override
  String get titleBarMaximizeLabel => 'Maximize window';

  @override
  String get titleBarRestoreLabel => 'Restore window';

  @override
  String get notificationSmartModeSkippedTitle =>
      'WhisPaste: Smart Mode skipped';

  @override
  String get notificationHotkeyFallbackTitle => 'WhisPaste: hotkey taken';

  @override
  String get notificationSmartModeSkippedBody =>
      'Post-processing could not be applied.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'No text model is loaded, so post-processing was skipped.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'Post-processing took too long.';

  @override
  String get notificationSmartModeOutcomePasted =>
      'The unedited text was pasted.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'It could not be confirmed whether the unedited text was pasted.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'The unedited text is on the clipboard, but it was not pasted.';

  @override
  String get notificationSmartModeOutcomeNone =>
      'The unedited text was not pasted.';

  @override
  String get smartModeNoTextModelHint =>
      'No text model is set up – until one is, only “Off” can be picked.';

  @override
  String get smartModeLoadTextModelAction => 'No text model – load now';

  @override
  String get smartModeAddOpenAiKeyAction => 'Add OpenAI key';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'The file is not a valid WhisPaste export.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'The file or settings could not be processed.';

  @override
  String get historyImportAudioLabel => 'Audio';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'App Switcher';

  @override
  String get hotkeyConflictNoteQuitApp => 'Quit App';

  @override
  String get hotkeyConflictNoteCloseWindow => 'Close window';

  @override
  String get hotkeyConflictNoteHideApp => 'Hide App';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'Minimize window';

  @override
  String get hotkeyConflictNoteCycleWindows => 'Cycle windows';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen =>
      'Screenshot (full screen)';

  @override
  String get hotkeyConflictNoteScreenshotSelection => 'Screenshot (selection)';

  @override
  String get hotkeyConflictNoteScreenshotRecording =>
      'Screenshot/Screen Recording';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'Emoji & Symbols picker';

  @override
  String get hotkeyConflictNoteForceQuit => 'Force Quit dialog';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'Lock workstation';

  @override
  String get hotkeyConflictNoteShowDesktop => 'Show/Hide Desktop';

  @override
  String get hotkeyConflictNoteFileExplorer => 'File Explorer';

  @override
  String get hotkeyConflictNoteRunDialog => 'Run dialog';

  @override
  String get hotkeyConflictNoteSettings => 'Settings';

  @override
  String get hotkeyConflictNoteSearch => 'Search';

  @override
  String get hotkeyConflictNoteTaskView => 'Task View';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch => 'Input language switch';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'Maximize window';

  @override
  String get hotkeyConflictNoteSnapLeft => 'Snap window left';

  @override
  String get hotkeyConflictNoteSnapRight => 'Snap window right';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'Security options / Task Manager';

  @override
  String get hotkeyConflictNoteTaskManager => 'Task Manager';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde => 'Lock screen (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'Run dialog (KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'System logout/shutdown dialog';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'Open terminal (GNOME/KDE default)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'Lock screen (GNOME)';

  @override
  String get hotkeyConflictNoteActivityOverviewKde => 'Activity overview (KDE)';

  @override
  String get settingsTextProcessingHeading => 'Text processing';

  @override
  String get settingsShowNotificationsSubtitle =>
      'Reports problems, for example blocked Auto-Paste or a missing microphone signal.';

  @override
  String get settingsGainSubtitle =>
      'Boosts the microphone signal before it is recorded. Values that are too high can distort the recording.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'What happens to the recognized text. Auto-Paste puts it right at the cursor.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'The language the recognition expects. Automatic detection works well in most cases. A fixed language is often more accurate for short recordings.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'Your own OpenAI key. Only needed if you use OpenAI for recognition or Smart Mode. Audio and text then go straight to OpenAI and are billed by them.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'Your own Deepgram key. Only needed if you use Deepgram for recognition. Audio then goes straight to Deepgram and is billed by them.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'Resets all settings, API keys and statistics. Recordings, notes and models are kept.';

  @override
  String get settingsFactoryResetSubtitle =>
      'Immediately deletes all transcriptions, notes, audio files, Dictionary, Snippets, models, logs and settings on this device. This can\'t be undone.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'The hotkey starts a recording from any app. When it\'s off, WhisPaste ignores the hotkey.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'Looks for a new version right away. It\'s only installed after you confirm.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'How many transcriptions are kept before older ones move to the trash. Trashed transcriptions are permanently deleted after the chosen time. Favorites always stay. Saved audio files are removed no later than 30 days after recording, regardless of this setting.';

  @override
  String get smartModeTargetLanguageSubtitle =>
      'Only for the Translate preset.';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'The file is too large to import (limit: about 5 MB). Choose a settings file that WhisPaste exported.';

  @override
  String get settingsSearchKeywordsInterface =>
      'theme, dark mode, light mode, appearance, language, startup, launch, minimized, notifications, system language, panel, side panel, quick paste, quick-paste, clipboard panel, panel position, screen edge, edge, dock, tray, CPU, indicator, status bar, utilization';

  @override
  String get settingsSearchKeywordsStt =>
      'model, whisper, quality, transcription, speech recognition, local, on-device, cloud, language, timeout, vocabulary, dictionary, words, STT, voice, deepgram, openai, api key, numbers only, punctuation, priming, engine, silence, trim, filler words, filler, line break, paragraph, new line, GPU, graphics, acceleration, processor, hardware';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'preset, cleanup, concise, translate, gemma, model, text model, download, post-processing, polish, edit selection, selection, selected text, rewrite';

  @override
  String get settingsSearchKeywordsAudio =>
      'microphone, recording, gain, volume, push to talk, hold to record, input, mic';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'clipboard, paste, auto-paste, copy, action, output, do nothing, blocklist, restore clipboard, keep transcript, previous content';

  @override
  String get settingsSearchKeywordsOverlay =>
      'overlay, floating overlay, display, status, position, waveform, top center, bottom center, start position, live transcript';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'background, color, colour, marine, graphite, glacier, glass, solid, amber';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'wave, waves, color, colour, cyan, violet, neutral, animation, amber';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'floating button, always on top, recording button, quick access, button';

  @override
  String get settingsSearchKeywordsHotkey =>
      'keyboard shortcut, hotkey, key binding, shortcut, global key, keyboard, hotkeys, keybinding';

  @override
  String get settingsSearchKeywordsSound =>
      'sound, audio cue, beep, volume, recording sound, notification, completion sound, cue';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'safety, silence, auto-stop, timeout, microphone timeout, silence detection, protection, dead mic, max duration';

  @override
  String get settingsSearchKeywordsHistory =>
      'recordings, entries, trash, cleanup, retention, maximum, auto-delete, storage, delete, hide, privacy, lock, protect, PIN protection, history';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'export, import, migrate, transfer, move, backup, restore, device change, portability, new computer, automatic backup, auto backup, autosave';

  @override
  String get settingsSearchKeywordsAdvanced => 'reset, defaults, factory reset';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'automation, api, script, token, bearer, http, localhost, port';

  @override
  String get settingsSearchKeywordsUpdates =>
      'update, beta, channel, release channel, pre-release, check, automatic, new version, stable, version';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'introduction, onboarding, setup, first run, tour, walkthrough, getting started, again, replay';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'rate, rating, review, stars, store, support';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'privacy, analytics, statistics, tracking, anonymous, error reports, crash reports, usage stats, data, share, consent, keep recordings, recent recordings';

  @override
  String get manualNoticeLabel => 'Message shown in the app';

  @override
  String get manualC01Title => 'Getting started';

  @override
  String get manualC01S1Heading => 'Setup on first start';

  @override
  String get manualC01S1B1 =>
      'On first start, WhisPaste guides you through the setup. You can go back to any step, and you can change everything later in Settings.';

  @override
  String get manualC01S1B2I1 => 'Welcome: a short overview of WhisPaste.';

  @override
  String get manualC01S1B2I2 => 'Privacy: what stays on your device.';

  @override
  String get manualC01S1B2I3 =>
      'Speech model: choose the speech model and download it. If an API key for a cloud provider is already saved, you can choose that provider instead.';

  @override
  String get manualC01S1B2I4 =>
      'Hotkey: set the key combination that starts a recording.';

  @override
  String get manualC01S1B2I5 => 'Appearance: turn start at login on or off.';

  @override
  String manualC01S1B2I6(String k1) {
    return '$k1: whether text is pasted automatically. On Linux, this step is skipped.';
  }

  @override
  String get manualC01S1B2I7 =>
      'Try it: a test recording, then you are ready. Without a speech model or a chosen cloud provider with an API key, finishing stays locked.';

  @override
  String get manualC01S2Heading => 'System requirements';

  @override
  String manualC01S2B1(String ram) {
    return 'WhisPaste needs a device with at least $ram of memory (RAM). On devices with less, WhisPaste shows only a notice instead of the app.';
  }

  @override
  String get manualC01S2B2 =>
      'You need a microphone to record. In onboarding you can continue without one, but you can only record once a microphone is connected.';

  @override
  String get manualC01S3Heading => 'Downloading a speech model';

  @override
  String get manualC01S3B1 =>
      'WhisPaste turns your speech into text, either on your device or through a cloud provider with your own key. On your device it needs a model. You start the download yourself; it does not start automatically.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: fast, for European languages, about $k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: all 99 languages, models from about $k1 to about $k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'The models are stored in the app’s data folder, in the $k1 subfolder.';
  }

  @override
  String get manualC01S3B4 =>
      'A Whisper model stays loaded after a recording, so the next start is faster. Under “Keep model loaded” in the speech recognition section you choose: Always (default) saves waiting time but needs the memory all the time. Automatic keeps the model loaded when your computer has enough memory, otherwise it unloads after 5 minutes. After idle time unloads it after the time you set. When memory runs short, WhisPaste unloads the model automatically and loads it again once there is room.';

  @override
  String get manualC01S3B3 =>
      'In the Speech recognition area, the entry “Re-run benchmark” measures how fast each installed tier runs on your computer. The results show on the model cards how much longer a tier takes and determine the recommended Whisper tier. For European languages WhisPaste recommends Parakeet instead. The test does not start during a recording.';

  @override
  String get manualC02Title => 'Recording and pasting';

  @override
  String get manualC02S1Heading => 'The hotkey';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'The hotkey is a key combination that works in every program. Default: $k2 on Windows and Linux, $k3 on Mac. You can change it under Settings → Keyboard shortcuts.';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'If another program already uses the combination, WhisPaste uses $k2 instead for the hotkey (on Mac, $k3). The other hotkeys stay off until you set a free combination.';
  }

  @override
  String get manualC02S2Heading => 'Hold or toggle';

  @override
  String get manualC02S2B1 =>
      'In Settings → Keyboard shortcuts, choose how the hotkey works:';

  @override
  String get manualC02S2B2I1 =>
      '“Hold to record” on: hold the hotkey, speak, and release. Releasing ends the recording.';

  @override
  String get manualC02S2B2I2 =>
      'Off: one press starts the recording, a second press ends it.';

  @override
  String get manualC02S3Heading => 'Seeing the recording';

  @override
  String get manualC02S3B1 =>
      'The dock at the bottom of the main window shows the current state. While recording, the main button changes to “Stop recording”, and the status area shows the current step. The dock is always there and cannot be turned off.';

  @override
  String get manualC02S3B3 =>
      'In a narrow window, the dock moves less important controls into the “More” menu, including the hotkey, the Auto-Paste hint, and the update notice. Everything stays reachable there.';

  @override
  String get manualC02S3B2I1 =>
      '“Recording overlay” set to “Floating (always visible)”: a small waveform overlay above all programs. Default: off.';

  @override
  String get manualC02S3B2I2 =>
      '“Floating button”: a button you click to record. Default: off. On Linux under Wayland, the desktop may limit its position and whether it stays on top.';

  @override
  String get manualC02S4Heading => 'Pasting after recording';

  @override
  String get manualC02S4B1 =>
      'Under “After transcription”, choose what happens after each recording:';

  @override
  String get manualC02S4B2I1 =>
      '“Copy to clipboard” (default): the text goes to the clipboard, and you paste it yourself.';

  @override
  String get manualC02S4B2I2 =>
      '“Auto-Paste at cursor”: WhisPaste pastes the text at the cursor.';

  @override
  String get manualC02S4B2I3 => '“Copy & Auto-Paste”: both.';

  @override
  String get manualC02S4B2I4 =>
      '“Do nothing”: WhisPaste neither copies nor pastes the text.';

  @override
  String get manualC02S4B3 =>
      'Apps on the “Auto-Paste blocklist” get no automatic pasting. The text then goes to the clipboard, or only to Recordings if “Copy to the clipboard when apps are blocked” is off.';

  @override
  String get manualC02S4B4 =>
      'On Windows, auto-paste does not work in programs running with administrator rights.';

  @override
  String get manualC02S4B5 =>
      'On Linux, WhisPaste marks the text with a hint that only KDE\'s Klipper honours. Other clipboard managers such as GPaste or CopyQ also store your transcripts: turn off their clipboard recording or delete the entry there.';

  @override
  String get manualC02S4B6 =>
      'After pasting, WhisPaste normally puts back what was on your clipboard before. Under “Clipboard after pasting” you can choose “Keep the transcript” instead: then the transcript stays on the clipboard. If a paste cannot be confirmed in time, the transcript always stays there. If macOS denies access to the clipboard, WhisPaste cannot keep the previous content and does not restore it; the transcript then stays on the clipboard. Once, a hint shows the way to System Settings.';

  @override
  String get manualC03Title => 'Quick note';

  @override
  String get manualC03S1Heading => 'What the quick note does';

  @override
  String get manualC03S1B1 =>
      'The quick note is a note that WhisPaste appends new recordings to. This lets you collect thoughts or a list without creating a new note each time.';

  @override
  String get manualC03S1B2 =>
      'If no note is marked yet, WhisPaste creates a new one the first time and marks it.';

  @override
  String get manualC03S2Heading => 'Setting it up';

  @override
  String get manualC03S2B1I1 =>
      'Open the note in the Notes area and turn on “Make this the quick note the hotkey appends to”. “Quick note — remove the mark” removes the mark.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'Turn on the quick-note hotkey under Settings → Keyboard shortcuts. It is off by default. The key is $k1 ($k2, or $k3 on Mac).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'What Smart Mode does';

  @override
  String manualC04S1B1(String k1) {
    return '$k1 edits the recognized text before it is pasted. It is off by default; you turn it on yourself.';
  }

  @override
  String get manualC04S1B2 =>
      'By default, processing runs on your device (“Locally on device”). With “OpenAI”, the text is sent to OpenAI. The privacy chapter has the details.';

  @override
  String get manualC04S2Heading => 'Presets';

  @override
  String get manualC04S2B1 => 'A preset decides what happens to the text:';

  @override
  String get manualC04S2B2I1 =>
      '“Off”: no post-processing; the text stays as it was recognized.';

  @override
  String get manualC04S2B2I2 =>
      '“Cleanup”: removes filler words such as “um” and fixes punctuation and capitalization, without changing the wording, meaning, or language.';

  @override
  String get manualC04S2B2I3 =>
      '“Concise”: removes repetition and filler, keeps every important fact and the language.';

  @override
  String get manualC04S2B2I4 =>
      '“Translate”: translates the text into the target language you set.';

  @override
  String get manualC04S3Heading => 'Target language and hotkey';

  @override
  String get manualC04S3B1 =>
      'For “Translate”, choose a target language: German, English, Spanish, French, Portuguese, Mandarin, or Russian. The default is English.';

  @override
  String manualC04S3B2(String k1) {
    return 'A separate hotkey for $k1 is off by default. It uses the preset and target language from the settings.';
  }

  @override
  String get manualC04S4Heading => 'Resources';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'The local variant downloads a text model of about $size. If your device has less than $ram of RAM, WhisPaste warns before the download, but you can still download. While running, the text model needs an extra 4 to 5 GB of RAM.';
  }

  @override
  String get manualC04S4B2 =>
      'While no text model is set up (local model not downloaded, or no OpenAI key for OpenAI), all presets except “Off” are locked. The dock and Settings name the reason and lead you to the download or the key. If post-processing still fails, WhisPaste says so and tells you whether the unedited text was pasted or is only on the clipboard.';

  @override
  String get manualC05Title => 'Dictionary';

  @override
  String get manualC05S1Heading => 'How replacements work';

  @override
  String get manualC05S1B1 =>
      'A replacement automatically swaps certain words or phrases for other text in every recording.';

  @override
  String get manualC05S1B2 =>
      'Each replacement has one or more trigger phrases, the phrases to look for, and the new text. Enter several trigger phrases for the same text under “Trigger phrases”.';

  @override
  String get manualC05S2Heading => 'Matching';

  @override
  String get manualC05S2B1I1 =>
      'Exact: only the identical spelling is replaced.';

  @override
  String get manualC05S2B1I2 =>
      'Similar: slightly different spellings are replaced too. This applies only to trigger phrases of at least 4 characters.';

  @override
  String get manualC05S2B1I3 =>
      'Tolerance (strict, standard, or tolerant): set per entry, not for all entries at once.';

  @override
  String get manualC05S3Heading => 'Import and export (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'You can back up or transfer your replacements as a CSV file. The file has the columns $k1. Separate several trigger phrases with $k2. A file can be at most $k3 and $k4 lines.';
  }

  @override
  String get manualC05S3B2 =>
      'Import and export are in the More menu (⋯) above the list. The try-it field opens from the same menu.';

  @override
  String get manualC06Title => 'Snippets';

  @override
  String get manualC06S1Heading => 'What snippets are';

  @override
  String get manualC06S1B1 =>
      'A snippet is a block of text you insert with a trigger word or a hotkey, such as a signature or a standard reply.';

  @override
  String get manualC06S1B2I1 =>
      '“Static”: the text is inserted exactly as you saved it.';

  @override
  String get manualC06S1B2I2 =>
      '“Interactive”: WhisPaste asks for individual fields one after another by recording, and places them in your template.';

  @override
  String get manualC06S2Heading => 'Opening the snippet picker';

  @override
  String get manualC06S2B1 => 'There are two ways to open the picker:';

  @override
  String get manualC06S2B2I1 =>
      'With the picker trigger word: say only this word. It counts only if the whole recording is exactly this word. You set the trigger word on the Snippets page. Leave it empty to turn the picker off.';

  @override
  String get manualC06S2B2I2 =>
      'With the picker hotkey: off by default; turn it on under “Picker hotkey”.';

  @override
  String get manualC06S3Heading => 'Creating a snippet';

  @override
  String get manualC06S3B1I1 =>
      'Create a snippet with “Add” and choose “Static” or “Interactive”.';

  @override
  String manualC06S3B1I2(String k1) {
    return 'For “Interactive”, define the fields and write the template. Put placeholders in double curly braces, such as $k1.';
  }

  @override
  String get manualC07Title => 'Notes';

  @override
  String get manualC07S1Heading => 'Working with notes';

  @override
  String get manualC07S1B1 =>
      'The Notes area collects text, such as ideas or research. Recordings go straight into a note when you use the quick note.';

  @override
  String get manualC07S1B2I1 => '“Mark as favorite” highlights a note.';

  @override
  String get manualC07S1B2I2 => '“Add tag” assigns a note to a category.';

  @override
  String get manualC07S2Heading => 'Trash';

  @override
  String get manualC07S2B1 =>
      '“Move to trash” puts a note in the trash. It stays there until you delete it for good. The trash is never emptied automatically.';

  @override
  String get manualC07S2B2I1 =>
      '“Delete forever” removes the note from the trash.';

  @override
  String get manualC07S3Heading => 'Quick note';

  @override
  String get manualC07S3B1 =>
      'The Notes area shows which note is the quick note. Details are in the quick note chapter.';

  @override
  String get manualC07S4Heading => 'Images and privacy';

  @override
  String get manualC07S4B1 =>
      'When you add an image, WhisPaste removes metadata such as the location (GPS), camera data, and EXIF, XMP and IPTC information. Only the cleaned copy is stored.';

  @override
  String get notesPinGateTitle => 'Notes are locked';

  @override
  String get notesPinGateHint => 'Enter your PIN to show your notes.';

  @override
  String get manualC08Title => 'Recordings';

  @override
  String get manualC08S1Heading => 'What recordings hold';

  @override
  String get manualC08S1B1 =>
      'Recordings shows every entry: the recognized text, with its date. If audio was saved, the audio file belongs to that entry.';

  @override
  String get manualC08S2Heading => 'Search and filter';

  @override
  String manualC08S2B1I1(String k1) {
    return 'Type $k1 to filter by tags.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'Type $k1 and a language to filter by language.';
  }

  @override
  String get manualC08S2B1I3 => 'Or just type a keyword.';

  @override
  String get manualC08S2B1I4 =>
      'Above the list are the filters “Favorites”, “Archived”, “Trash”, and “All”.';

  @override
  String get manualC08S3Heading => 'Managing entries';

  @override
  String get manualC08S3B1I1 =>
      '“Copy text” copies the text to the clipboard again.';

  @override
  String get manualC08S3B1I2 =>
      '“Add to favorites” keeps an entry at the top. “Remove from favorites” undoes that.';

  @override
  String get manualC08S3B1I3 =>
      '“Archive” moves an entry out of the main list without deleting it.';

  @override
  String get manualC08S3B1I4 =>
      '“Duplicate”, “Merge” (several entries into one), and “Select multiple” help you tidy up.';

  @override
  String get manualC08S3B1I5 =>
      '“Add annotation” and “Add tag…” add details to an entry.';

  @override
  String get manualC08S4Heading => 'Voice note';

  @override
  String get manualC08S4B1 =>
      'Start a voice note on the entry. Say “tag: name” to set a tag, or “correct: text” to replace the entry’s text.';

  @override
  String get manualC08S4B2 =>
      'A correction replaces the entry’s whole text, not just one word. “korrektur: text” works the same way. Right afterwards you can undo the change from the notice.';

  @override
  String get manualC08S5Heading => 'PIN protection';

  @override
  String get manualC08S5B1 =>
      'With “PIN protection”, a PIN is required before recordings are shown. This also applies to the side panel, the menu of the floating button, and the automation API. The PIN keeps others from casually viewing your transcriptions, but it does not encrypt them. Notes are locked the same way. With a PIN set, the tray menu lists recent recordings by time and word count instead of their first words.';

  @override
  String get manualC08S5B2 =>
      'A forgotten PIN cannot be recovered. To reset it, all transcriptions and saved audio files (including archive and trash), all notes with their versions, and all note images are deleted immediately. Settings, snippets, and replacements are kept.';

  @override
  String get manualC08S5B3 =>
      'While the recordings are locked by a PIN, the clipboard tab in the side panel shows no copied text and pastes none. Copied text comes back once you unlock them.';

  @override
  String get manualC08S6Heading => 'Automatic emptying';

  @override
  String get manualC08S6B1 =>
      'Under “Auto-delete trash after”, set how long deleted entries stay in the trash before they are removed automatically.';

  @override
  String get manualC09Title => 'Importing audio files';

  @override
  String get manualC09S1Heading => 'Transcribing audio files';

  @override
  String manualC09S1B1(String k1) {
    return 'You can have existing audio files transcribed. Choose “$k1” and pick the file.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'Besides $k1, you can import more formats depending on your system: on Mac $k2, on Linux $k3, on Windows $k4.';
  }

  @override
  String get manualC09S2Heading => 'Limits';

  @override
  String get manualC09S2B2 =>
      'What to do: split the recording into shorter parts and import them one by one.';

  @override
  String get manualC09S3Heading => 'Import errors';

  @override
  String manualC09S3B2(String k1) {
    return 'What to do: try again. If that does not help, restart WhisPaste or choose another model under $k1.';
  }

  @override
  String get manualC10Title => 'Statistics';

  @override
  String get manualC10S1Heading => 'The areas';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'The statistics have three areas: $k1, $k2, and $k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'Use $k1 and $k2 to choose the time range.';
  }

  @override
  String get manualC10S2Heading => 'What the numbers mean';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 and $k2 count your recordings and how long you recorded.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 is a rough estimate: WhisPaste counts two thirds of the recording time as saved, because speaking is usually faster than typing. It is not a measurement.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: local recordings save cloud costs. WhisPaste estimates this at $k2 per minute, a fixed reference rate.';
  }

  @override
  String get manualC10S3Heading => 'Reset';

  @override
  String manualC10S3B1(String k1) {
    return '“$k1” deletes all statistics data. WhisPaste asks first, and this cannot be undone.';
  }

  @override
  String get manualC11Title => 'Settings';

  @override
  String get manualC11S1Heading => 'The sections';

  @override
  String get manualC11S1B1 =>
      'Settings are grouped into sections. The most important ones:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: how the app looks.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: model and recognition language.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: microphone and volume.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: preset, target language, and provider.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: what happens after a recording.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: hotkeys.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: trash period.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: export, import, and automatic backup.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: local API and event hooks for programs on this computer.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: more options, such as reset.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: version, update check, links, and licences.';
  }

  @override
  String get manualC11S2Heading => 'Back up and reset';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 saves your settings automatically after changes. The last five files are kept. It is off by default.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 immediately deletes all transcriptions, audio files and settings and resets WhisPaste. Read the confirmation carefully before you confirm.';
  }

  @override
  String get manualC12Title => 'Privacy and offline use';

  @override
  String get manualC12S1Heading => 'What stays on your device';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'By default, speech recognition runs on your device. Audio goes to a cloud service only when you actively choose a cloud provider. Transcriptions are stored in a local database on your device, and saved audio files as files next to it. The audio of your last $count recordings is kept only while “$k1” is on, and for $days days at most.';
  }

  @override
  String get manualC12S1B2 =>
      'The update check asks GitHub for new versions. Feedback is sent only when you submit it.';

  @override
  String get manualC12S1B3 =>
      'If a transcription fails because the server or the connection is not available, the audio of that recording is kept for up to 24 hours, so you can try again from the error message or under Privacy. This also applies when audio retention is off. If it is on, the normal retention applies instead.';

  @override
  String get manualC12S2Heading => 'Cloud providers';

  @override
  String manualC12S2B1(String k1) {
    return 'The providers OpenAI and Deepgram need your own API key. Enter it under $k1.';
  }

  @override
  String get manualC12S3Heading => 'Usage statistics and error reports';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'Two options are on by default: $k1 and $k2. You can turn both off in $k3.';
  }

  @override
  String get manualC13Title => 'Hardware and performance';

  @override
  String get manualC13S1Heading => 'Memory';

  @override
  String manualC13S1B1(String k1) {
    return 'WhisPaste recommends at least $k1 of memory. With less, the app still starts and recommends the “Fast” speech model.';
  }

  @override
  String get manualC13S2Heading => 'Graphics card';

  @override
  String get manualC13S2B1 =>
      'WhisPaste uses the graphics card when it can speed up speech recognition:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, Apple’s graphics interface.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 and $k2 with AMD or Intel graphics: $k3, a widely used graphics interface.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'NVIDIA cards also use $k1. With the optional CUDA pack, recognition also uses $k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'Without a suitable graphics card, WhisPaste computes on the processor ($k1). That is slower.';
  }

  @override
  String get manualC13S3Heading => 'The CUDA pack';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'The CUDA pack is an optional add-on for NVIDIA cards, per the app for $k1 and $k2. It is available for $k3 and $k4 (x64). Turn it on under $k5.';
  }

  @override
  String get manualC13S3B2 =>
      'The download is one-time. The app shows its size.';

  @override
  String get manualC13S3B3 =>
      'The pack contains NVIDIA components. Before the first download you accept the NVIDIA CUDA licence (version 2026-01-26); the consent applies to this installation. Without a valid consent the row shows “Consent required”, and WhisPaste uses Vulkan or the CPU until you accept. If the licence text or the pack changes, you are asked again.';

  @override
  String get manualC13S4Heading => 'Graphics acceleration';

  @override
  String manualC13S4B1(String k1) {
    return 'Under $k1, choose whether WhisPaste uses the graphics card. Processor only is usually slower.';
  }

  @override
  String get manualC13S5Heading => 'Models and size';

  @override
  String get manualC13S5B1 =>
      'The Whisper models come in three tiers: Fast, Balanced, and Accurate. More accurate tiers usually recognise better but need more processing time.';

  @override
  String get manualC14Title => 'Troubleshooting';

  @override
  String get manualC14S1Heading => 'How to read this page';

  @override
  String get manualC14S1B1 =>
      'Each section starts with a notice WhisPaste shows. The wording is the app’s own text. Below it are the cause and the next step.';

  @override
  String get manualC14S2Heading => 'No microphone access';

  @override
  String get manualC14S2B2 =>
      'What to do: allow WhisPaste microphone access in your system settings. Then start the recording again.';

  @override
  String get manualC14S3Heading => 'No microphone found';

  @override
  String manualC14S3B2(String k1) {
    return 'What to do: connect a microphone and choose it under $k1.';
  }

  @override
  String get manualC14S4Heading => 'No audio captured';

  @override
  String manualC14S4B2(String k1) {
    return 'What to do: check that the right microphone is selected and the $k1 is not at zero. Then record again.';
  }

  @override
  String get manualC14S5Heading => 'No speech model';

  @override
  String manualC14S5B2(String k1) {
    return 'What to do: download a model under $k1, then try again.';
  }

  @override
  String get manualC14S6Heading => 'Unknown model';

  @override
  String manualC14S6B2(String k1) {
    return 'What to do: choose an installed model under $k1.';
  }

  @override
  String get manualC14S7Heading => 'Transcription failed';

  @override
  String manualC14S7B2(String k1) {
    return 'What to do: try again. If that does not help, restart WhisPaste or choose another model under $k1.';
  }

  @override
  String get manualC14S8Heading => 'No text recognized';

  @override
  String get manualC14S8B2 =>
      'What to do: speak more clearly or a little longer and try again. Also check the microphone.';

  @override
  String get manualC14S9Heading => 'Recording or transcription too long';

  @override
  String get manualC14S9B2 => 'What to do: record shorter sections.';

  @override
  String get manualC14S10Heading => 'Cloud key missing or invalid';

  @override
  String manualC14S10B2(String k1) {
    return 'What to do: enter the key again under $k1, or switch to on-device recognition.';
  }

  @override
  String get manualC14S11Heading => 'Graphics memory full';

  @override
  String get manualC14S11B2 =>
      'What to do: nothing. You can choose the model again later in Settings.';

  @override
  String get manualC14S12Heading => 'Calculated on the processor';

  @override
  String manualC14S12B2(String k1) {
    return 'What to do: usually nothing. If it happens often, check the setting under $k1 and update the graphics driver.';
  }

  @override
  String get manualC14S13Heading => 'Auto-Paste blocked (macOS)';

  @override
  String get manualC14S13B2 =>
      'What to do: allow WhisPaste accessibility access in the system settings. If the message stays, restart WhisPaste.';

  @override
  String get manualC14S14Heading => 'Auto-Paste blocked (Windows)';

  @override
  String get manualC14S14B2 =>
      'What to do: start WhisPaste as an administrator too.';

  @override
  String get manualC14S15Heading => 'Auto-Paste on Linux';

  @override
  String get manualC14S15B1 =>
      'On Linux, auto-paste uses a virtual input device (uinput). If it does not work, check whether WhisPaste may access that device.';

  @override
  String get manualC14S15B2 =>
      'The .deb package grants no access when it is installed. Auto-paste asks first: in the setup or under Settings → After transcription, choose “Allow (administrator password)” and enter your administrator password. While the permission is in place, other programs in your session can create key presses too. “Remove permission” takes it back at any time; uninstalling removes it as well.';

  @override
  String get manualC14S15B3 =>
      'The Flatpak build gives the app access to the system\'s input devices so that auto-paste can work. WhisPaste itself does not read input devices.';

  @override
  String get manualC14S15B4 =>
      'In the Snap build, run this once in a terminal:';

  @override
  String get manualC14S15B5 =>
      'The AppImage needs access to /dev/uinput. In the setup or in the settings, copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/, which gives write access only to the signed-in session. Until then, auto-paste only copies the text.';

  @override
  String get manualC14S15TerminalHeading => 'Terminals and Wayland';

  @override
  String get manualC14S15T1 =>
      'On Linux, terminals paste with Ctrl+Shift+V. WhisPaste recognises common terminals and uses that shortcut there on its own: under X11 and XWayland, and on KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire and other wlroots desktops.';

  @override
  String get manualC14S15T2 =>
      'Under GNOME with Wayland, WhisPaste identifies the target app only with the optional WhisPaste extension for GNOME. Without it, WhisPaste does not recognise terminals, and a block list only copies the text.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'If a terminal still shows ^V instead of the text, turn on “$k1” under $k2. WhisPaste then pastes with Ctrl+Shift+V everywhere. Some apps use these keys for something else; LibreOffice, for example, opens a dialog.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'Under GNOME, turn on the WhisPaste extension in the settings with $k1. The .deb package already installs it. With Flatpak, AppImage or the tarball, install it once with the script from the unpacked Linux package, then turn it on:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'Without uinput set up, for example in Flatpak, WhisPaste pastes through desktop permission: $k1 under $k2. Your desktop asks once; you can withdraw the permission there at any time';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'This desktop does not let apps use system-wide shortcuts yet. WhisPaste can add $shortcut to the GNOME keyboard shortcuts instead.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'Add to GNOME';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut is set up in the GNOME keyboard shortcuts. If you change the hotkey, WhisPaste updates it there.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'Remove from GNOME';

  @override
  String get settingsDesktopShortcutFailed =>
      'The GNOME keyboard shortcuts could not be changed.';

  @override
  String get settingsDesktopShortcutManual =>
      'This desktop does not let apps use system-wide shortcuts. Assign this command to a key combination in your system settings:';

  @override
  String get manualC14S15HotkeyHeading => 'Hotkey under Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'Under Wayland, an app gets system-wide shortcuts only through the desktop. KDE Plasma and GNOME 48 or newer provide them. Older GNOME versions, such as in Ubuntu 24.04, cannot: WhisPaste then offers “$k1” under $k2 and adds the hotkey to the GNOME keyboard shortcuts.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'On other desktops, such as Sway or Hyprland, assign the command to a key combination yourself. Settings shows the exact command for your installation under $k1.';
  }

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'With this access, the app could in theory read keystrokes of other programs if your user can read the input devices (e.g. as a member of the input group). Members of the input group can also generate virtual input.';

  @override
  String get manualC14S15B3S =>
      'Auto-paste also needs write access to /dev/uinput on the host. Install the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/ and then run these commands:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'Copy command';

  @override
  String get manualCodeCopied => 'Command copied';

  @override
  String get manualCodeCopyFailed =>
      'Could not copy. Select the command and copy it by hand.';

  @override
  String get manualC14S15B3E =>
      'The rule gives write access only to the signed-in session. These commands need administrator rights (sudo) and change the system. If you do not want this, leave auto-paste off and paste the text by hand. To remove the rule, use the button in the settings that copies the matching command.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'Until then, auto-paste only copies the text.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'Hotkey already in use';

  @override
  String manualC14S16B2(String k1) {
    return 'What to do: choose a different combination under $k1.';
  }

  @override
  String get manualC14S17Heading => 'Autostart not set up';

  @override
  String get manualC14S17B2 =>
      'What to do: check the autostart permissions in your operating system. Without autostart, WhisPaste does not start on its own.';

  @override
  String get manualC14S18Heading => 'Automatic backup failed';

  @override
  String manualC14S18B2(String k1) {
    return 'What to do: choose a different, reachable folder under $k1.';
  }

  @override
  String get manualC14S19Heading => 'Factory reset incomplete';

  @override
  String get manualC14S19B2 =>
      'What to do: choose “Try again”, or restart WhisPaste and run the reset again afterwards.';

  @override
  String get manualC14S20Heading => 'No sound detected';

  @override
  String manualC14S20B2(String k1) {
    return 'What to do: check the microphone under $k1 and then record again.';
  }

  @override
  String get manualC14S21Heading => 'Not enough memory';

  @override
  String manualC14S21B1(String k1) {
    return 'WhisPaste still starts with less memory than the recommended $k1. The app then recommends the “Fast” speech model.';
  }

  @override
  String get manualC15Title => 'Keyboard shortcuts';

  @override
  String get manualC15S1Heading => 'Only inside WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'These keyboard shortcuts work only while the WhisPaste window is active. The system-wide hotkey, by contrast, is set under $k2.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'On Mac, $k1 usually replaces $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 opens help.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k opens help as well.';
  }

  @override
  String get manualC15S2Heading => 'Recordings';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: delete the entry.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: toggle favorite.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: search.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: close search or the detail view.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: copy the entry.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: discard an edit. Unsaved changes ask first.';
  }

  @override
  String get manualC15S3Heading => 'Notes';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: delete the entry.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: create a new note.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: search.';
  }

  @override
  String get manualC15S4Heading => 'Dictionary and snippets';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: delete the entry.';
  }

  @override
  String get manualC15S5Heading => 'Cancel during a recording';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'While a recording or transcription runs, WhisPaste catches the $k1 key system-wide so you can cancel. $k1 then does nothing in other apps. If that bothers you, choose $k2 as the cancel key in Settings.';
  }

  @override
  String get manualC16Title => 'Feedback and support';

  @override
  String get manualC16S1Heading => 'Sending feedback';

  @override
  String get manualC16S1B1I1 => 'Rating: required.';

  @override
  String get manualC16S1B1I2 =>
      'Type: required. Choose Problem, Idea, Praise, or Question.';

  @override
  String get manualC16S1B1I3 => 'Free text up to 1000 characters.';

  @override
  String get manualC16S1B1I4 => 'An email address is optional.';

  @override
  String get manualC16S1B2 =>
      'If you have sent feedback recently, the app shows this notice:';

  @override
  String get manualC16S2Heading => 'Support';

  @override
  String manualC16S2B1(String k1) {
    return 'The $k1 tab on the Help page shows how you can support WhisPaste.';
  }

  @override
  String get manualC16S3Heading => 'Rating reminder';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'If you chose “Never ask again” for the rating reminder, you find the switch “$k2” under $k1. It appears only in that case.';
  }

  @override
  String get manualC16S4B1 =>
      'You can send feedback from the Help tab, from the Help menu in the menu bar (macOS) or the title-bar menu (Windows and Linux), and from the tray. The form is two steps away.';

  @override
  String get manualC16S5Heading => 'Share an idea';

  @override
  String get manualC16S5B1 =>
      'Choose Idea, or open Suggest an idea from the Help menu: the type is already set. You can also post your idea on the public ideas board and vote on others.';

  @override
  String get manualC16S6Heading => 'Write by voice';

  @override
  String get manualC16S6B1 =>
      'The microphone button in the message field records your voice and inserts the recognized text at the cursor.';

  @override
  String get manualC16S7Heading => 'What is sent';

  @override
  String get manualC16S7B1I1 => 'The type you chose and your message.';

  @override
  String get manualC16S7B1I3 =>
      'Your e-mail address only if you entered one. It is used only for a reply and deleted after 90 days.';

  @override
  String get manualC16S7B1I4 =>
      'Diagnostics only if you turn on Attach diagnostics: app version, operating system, speech engine and backend. Show preview displays the exact text before you send.';

  @override
  String get manualC16S7B1I5 =>
      'Only for Praise: the consent to show your praise as a quote on the website. It is off by default and you can withdraw it with one click on this page.';

  @override
  String get manualC16S7B2 => 'Recordings and transcripts are never attached.';

  @override
  String get manualC16S4Heading => 'Where to find the form';

  @override
  String get manualC16S7B1I2 => 'The rating you chose.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'Could not paste – the text is on the clipboard ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'Check permission';

  @override
  String get autoPasteResetConfirmTitle => 'Reset entry and allow again?';

  @override
  String get autoPasteResetConfirmBody =>
      'macOS stored an old entry for WhisPaste that no longer applies. WhisPaste removes only this Accessibility entry. macOS will then ask you again. Other permissions stay unchanged.';

  @override
  String get autoPasteResetConfirmButton => 'Reset entry and allow again';

  @override
  String get permissionRowMicTitle => 'Microphone';

  @override
  String get permissionRowMicPurpose =>
      'Records your voice. Without it nothing can be recorded.';

  @override
  String get permissionRowPasteTitle => 'Auto-paste';

  @override
  String get permissionRowPastePurpose =>
      'Places the text at the cursor. Without it, the text lands on the clipboard.';

  @override
  String get permissionRowAllow => 'Allow';

  @override
  String get permissionRowMissingSettings => 'Missing – open Settings';

  @override
  String get permissionRowGranted => 'Allowed';

  @override
  String get permissionRowOptional => 'Optional';

  @override
  String get autostartApprovalBody =>
      'macOS is waiting for your approval: WhisPaste only starts at login once you switch it on under Login Items.';

  @override
  String get autostartApprovalAction => 'Open Login Items';

  @override
  String get pasteFailureLinuxUinputHint =>
      'Auto-paste needs your one-time permission for the virtual keyboard (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'Copy command';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'Auto-paste is not available on this system: there is no virtual keyboard device.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'Auto-paste needs one-time access to /dev/uinput. Open the Auto-Paste settings for the one-time setup.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'Auto-paste now asks before it uses the virtual keyboard /dev/uinput, so this update removed the old access. The text is on the clipboard, paste it with $paste. Click here to allow it.';
  }

  @override
  String get linuxUinputSetupAction => 'Set up';

  @override
  String get linuxUinputConsentDetail =>
      'To paste the text itself, WhisPaste needs a virtual keyboard. While it is allowed, other programs in your session can create key presses too. Without it, WhisPaste copies the text and you paste it yourself.';

  @override
  String get linuxUinputGrantButton => 'Allow (administrator password)';

  @override
  String get linuxUinputGrantFailed =>
      'Allowing did not work. WhisPaste keeps copying the text only.';

  @override
  String get linuxUinputRevokeButton => 'Remove permission';

  @override
  String get linuxUinputRevokeDone =>
      'Permission removed. WhisPaste now only copies the text.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'API keys could not be fully removed.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours h';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get dockErrorCauseEngine => 'The speech model stopped with an error.';

  @override
  String get dockErrorCauseRecording =>
      'The recording could not be transcribed.';

  @override
  String get dockErrorAction =>
      'Open speech settings to check the speech model.';

  @override
  String get overlayDoneCopiedOnly =>
      'Only copied – target app blocked or not recognised';

  @override
  String get overlayDoneNotPasted => 'Not pasted – saved in Recordings';

  @override
  String get overlayDonePasteFailed => 'Paste not possible – copy the text';

  @override
  String get databaseTooNewTitle => 'WhisPaste cannot open your data';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'Your data was written by a newer version of WhisPaste (database version $storedVersion). This version supports up to version $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'Install the latest version of WhisPaste and start it again. Nothing has been changed or deleted.';

  @override
  String get databaseTooNewQuit => 'Quit';

  @override
  String get pasteFailureTargetChanged =>
      'Auto-paste cancelled: you switched apps during processing. The text is in the clipboard.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'Auto-paste not confirmed. The text is in the clipboard, paste it with $paste.';
  }

  @override
  String get onboardingAppearanceSettingsHint =>
      'Changeable anytime under Settings → Appearance';

  @override
  String get onboardingAppearanceSettingsLink =>
      'Open the live preview in Settings (ends setup)';

  @override
  String get onboardingAppearanceSettingsLinkRevision =>
      'Open the live preview in Settings (show again later)';

  @override
  String get fileDialogOpenTitle => 'Open file';

  @override
  String get fileDialogOpenFilesTitle => 'Open files';

  @override
  String get fileDialogSaveTitle => 'Save file';

  @override
  String get fileDialogFolderTitle => 'Choose folder';

  @override
  String get fileDialogSelectFolder => 'Select';

  @override
  String get dockLanguageAuto => 'Auto';

  @override
  String get settingsLanguageFavoriteAdd => 'Add to favorites';

  @override
  String get settingsLanguageFavoriteRemove => 'Remove from favorites';

  @override
  String get settingsLanguageFavoritesLimit =>
      'Up to 3 favorites. Remove one to add another.';

  @override
  String get dockMenuFavorites => 'Favorites';

  @override
  String get dockMenuAllLanguages => 'All languages';

  @override
  String get traySpeechModel => 'Speech model';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'The tray icon needs a tray host. On GNOME, install the AppIndicator extension; until then the quick-switch menu is not available.';

  @override
  String get trayLanguage => 'Language';

  @override
  String get trayLanguageMore => 'More…';

  @override
  String get trayProfile => 'Profile';

  @override
  String get trayProfileAutomatic => 'Automatic, by app';

  @override
  String get trayProfileNone => 'No profile';

  @override
  String profileSwitchedToast(String name) {
    return 'Profile: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'Next favorite language';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'Next favorite language';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'Switches the recording language to the next favorite. Star up to three languages under Speech-to-text.';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'Already used by $action. Choose another combination.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'The shortcut is taken by another app or could not be registered. Choose another combination.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'Under Wayland, this shortcut may not work in other apps. Set a desktop shortcut for it if it does not respond.';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'Recording language: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'Recording language: $language. Applies from the next recording.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'No favorite languages yet. Star up to three languages under Speech-to-text to use this shortcut.';

  @override
  String get languageCycleOpenSettings => 'Open settings';

  @override
  String get manualLangFavHeading => 'Favorite languages';

  @override
  String get manualLangFavB1 =>
      'In the speech recognition settings, mark up to three languages as favorites with the star in the language list. Favorites appear first in the language menu of the recording dock and in the tray menu, so you can switch in one click.';

  @override
  String get manualLangTrayHeading => 'Language in the tray menu';

  @override
  String get manualLangTrayB1 =>
      'The tray menu has a Language submenu. It lists your favorites and puts a check mark on the active language. More… opens the window with the full list. Parakeet picks its own language, so the submenu is hidden there.';

  @override
  String get manualLangCycleHeading => 'Next favorite language';

  @override
  String get manualLangCycleB1 =>
      'In the Dictate card you can assign a key combination that switches the recording language to the next favorite on each press. The shortcut stays off until you record a combination. Without favorites, WhisPaste points you to the setting. Under Linux with Wayland, other apps may not respond to the shortcut.';

  @override
  String onboardingReadyDesktopShortcutHint(String shortcut) {
    return '$shortcut does not work system-wide on this desktop yet. Go back to the page where you chose your hotkey to set it up.';
  }

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut works system-wide only after it is added to the GNOME keyboard shortcuts.';
  }

  @override
  String get recommendationReasonLanguage =>
      'Recommended because Parakeet covers your language and is fast on any device.';

  @override
  String get recommendationReasonMeasured =>
      'Recommended from the measurement on this device.';

  @override
  String recommendationReasonApple(String memory) {
    return 'Recommended for your Apple chip (Metal) with $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'Recommended for your NVIDIA graphics card with $gb GB of video memory (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'Recommended for your graphics card $name (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'Recommended for the processor, as there is no usable graphics card: $cores cores, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name is software graphics, so the processor does the work: $cores cores, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb GB of RAM';
  }

  @override
  String get recommendationMemoryUnknown => 'RAM unknown';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'No speech model – download $name now ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'If the selected speech model is missing, the dock shows “Speech model missing”. The dock’s speech menu then offers it as its first entry to download, for Whisper and Parakeet alike. Pressing the shortcut without a model shows a notice with “Download now”. When you switch to Whisper in Settings and the selected Whisper model is missing, WhisPaste picks one that is already downloaded.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'Processor (software Vulkan, $name)';
  }

  @override
  String get menuBarMenuEdit => 'Edit';

  @override
  String get menuBarMenuWindow => 'Window';

  @override
  String get menuBarEditUndo => 'Undo';

  @override
  String get menuBarEditRedo => 'Redo';

  @override
  String get menuBarEditCut => 'Cut';

  @override
  String get menuBarEditCopy => 'Copy';

  @override
  String get menuBarEditPaste => 'Paste';

  @override
  String get menuBarEditSelectAll => 'Select All';

  @override
  String get menuBarWindowMinimize => 'Minimize';

  @override
  String get menuBarWindowZoom => 'Zoom';

  @override
  String get menuBarAppQuit => 'Quit WhisPaste';

  @override
  String get menuBarMenuRecording => 'Recording';

  @override
  String get menuBarAppSettings => 'Settings…';

  @override
  String get menuBarHelpManual => 'Open manual';

  @override
  String get menuBarHelpFeedback => 'Send feedback…';

  @override
  String get menuBarHelpIdea => 'Suggest an idea…';

  @override
  String get manualC15S6Heading => 'Menu';

  @override
  String get manualC15S6B1 =>
      'On the Mac, the most important commands are also in the menu bar at the top. The Recording menu starts and stops a recording and sets the language, speech model, Smart Mode, what happens after transcription, the microphone and the profile.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: open Settings with $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'Edit: Cut, Copy, Paste and Select All act on the text field that has focus.';

  @override
  String get manualC15S6B2I3 => 'Window: minimize and zoom the main window.';

  @override
  String get manualC15S6B2I4 =>
      'Help: open the manual, send feedback and suggest an idea.';

  @override
  String get manualC15S6B3 =>
      'On Windows and Linux, the same commands are in a menu button at the top right of the title bar. Press Alt or F10 to open it, use the arrow keys to choose an entry, Enter to run it and Escape to close the menu.';

  @override
  String get menuBarAppAbout => 'About WhisPaste';

  @override
  String get menuBarAppHide => 'Hide';

  @override
  String get menuBarAppHideOthers => 'Hide Others';

  @override
  String get menuBarAppShowAll => 'Show All';

  @override
  String get titleBarMenuLabel => 'Menu';

  @override
  String get notesTitleLabel => 'Title';

  @override
  String get notesMoreActions => 'More actions';

  @override
  String get notesVersionSaveNow => 'Save version now';

  @override
  String get notesMenuMark => 'Highlight';

  @override
  String get notesMenuAddImage => 'Insert image';

  @override
  String get notesMenuVersions => 'Versions';

  @override
  String get notesMenuSnippet => 'Save as snippet';

  @override
  String get notesVersionsEmpty => 'No versions yet.';

  @override
  String get notesVersionTooLarge => 'Too large to preview';

  @override
  String get notesVersionDelete => 'Delete version';

  @override
  String get notesVersionSaved => 'Version saved';

  @override
  String get notesVersionUnchanged => 'No changes since the last version.';

  @override
  String get notesVersionRestored => 'Version restored';

  @override
  String get notesVersionRestoreMessage =>
      'Only the title and text are restored to this version. Images stay as they are.';

  @override
  String get notesVersionDeleteMessage =>
      'This version is deleted permanently and cannot be recovered.';

  @override
  String get notesImageFilesLabel => 'Images';

  @override
  String get notesImageRejected =>
      'This file is not a supported image (PNG, JPEG, GIF or WebP).';

  @override
  String get notesImageRemove => 'Remove image';

  @override
  String get notesSnippetCreated => 'Snippet created';

  @override
  String get notesSnippetNothing =>
      'This note has no text to save as a snippet.';

  @override
  String get notesMarkNeedsSelection => 'Select some text first.';

  @override
  String get notesImageLimitCount =>
      'This note already has the maximum number of images.';

  @override
  String get notesImageLimitBytes =>
      'The images of this note would exceed the size limit.';

  @override
  String get notesImageLimitTotal =>
      'Image storage is full. Remove an image to add another.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'The file was too slow to copy or changed while it was being copied. Please try again.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'This format is not available on this system. Convert the file to WAV and import it again.';

  @override
  String get audioDropHint => 'Drop audio files here to transcribe them';

  @override
  String audioDropRejectedFolder(String names) {
    return 'Folders cannot be imported: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'File not found: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'Not supported: $names. Allowed formats: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'Not an ordinary file (such as a device or pipe), cannot be imported: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'Too large (1 GB at most): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'This is not an ordinary file and cannot be imported.';

  @override
  String get historyImportRejectedTooLarge => 'The file is larger than 1 GB.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'Reserved device name, cannot be imported: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'Windows reserves this file name, so it cannot be imported. Rename the file.';

  @override
  String get historyImportFailureIo => 'The storage is full or not writable.';

  @override
  String get holdToRecordExplained =>
      'On: hold the hotkey and speak, release to finish. Off: press once to start, press again to finish.';

  @override
  String get settingsAreaProfiles => 'Profiles';

  @override
  String get profilesSectionHeading => 'Your profiles';

  @override
  String get profilesEmptyBody =>
      'Profiles switch the speech model, language, Smart Mode and the after-transcription action with a hotkey, or automatically per app.';

  @override
  String get profilesAddFirst => 'Create first profile';

  @override
  String get profilesAdd => 'Create profile';

  @override
  String get profilesCreate => 'Create';

  @override
  String get profilesLimitReached =>
      'At most 9 profiles. Delete one to create another.';

  @override
  String get profilesActiveBadge => 'Active';

  @override
  String get profilesMoveUp => 'Move up';

  @override
  String get profilesMoveDown => 'Move down';

  @override
  String get profilesDragHandle => 'Drag to reorder';

  @override
  String get profilesNewTitle => 'New profile';

  @override
  String get profilesNameLabel => 'Name';

  @override
  String get profilesNameEmpty => 'Enter a name.';

  @override
  String get profileDetailHeading => 'Profile settings';

  @override
  String get profileDetailModel => 'Speech model';

  @override
  String get profileDetailLanguage => 'Language';

  @override
  String get profileDetailLanguageSubtitle =>
      'Applies to Whisper and cloud services. Parakeet detects the language itself.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'After transcription';

  @override
  String get profileDetailMicrophone => 'Microphone';

  @override
  String get profileKeepUnchanged => 'Leave unchanged';

  @override
  String profileValueUnavailable(String value) {
    return '$value (unavailable)';
  }

  @override
  String get profileDetailHotkey => 'Hotkey';

  @override
  String get profileDetailHotkeySubtitle =>
      'Switches to this profile with this key press.';

  @override
  String get profileHotkeyNone => 'No hotkey';

  @override
  String get profileHotkeyChange => 'Set hotkey';

  @override
  String get profileHotkeyRemove => 'Remove hotkey';

  @override
  String get profileHotkeyNeedsModifier =>
      'A profile hotkey needs at least one modifier key, such as Ctrl, Alt, Shift or Command.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'Already used by “$action”. The hotkey is not active.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'Already used by the profile “$name”. The hotkey is not active.';
  }

  @override
  String get profileDetailApps => 'Target apps';

  @override
  String get profileDetailAppsSubtitle =>
      'When one of these apps is in front while you dictate, the profile becomes active automatically.';

  @override
  String get profileAppIdentifierLabel => 'App identifier';

  @override
  String get profileAppAdd => 'Add';

  @override
  String get profileAppHintMac => 'macOS: bundle ID, e.g. com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: program name without .exe, e.g. chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: window WM_CLASS, e.g. google-chrome. Not detectable under Wayland.';

  @override
  String profileAppClash(String name) {
    return 'This app already belongs to the profile “$name”.';
  }

  @override
  String get profileAppEmpty => 'No app assigned yet.';

  @override
  String get profileAppRemove => 'Remove app rule';

  @override
  String get profileDetailContext => 'Read context';

  @override
  String get profileDetailContextSubtitle =>
      'Optionally reads the selected text or the clipboard so processing fits. With cloud services only with your consent.';

  @override
  String get profileContextNone => 'Read nothing';

  @override
  String get profileContextSelection => 'Selected text';

  @override
  String get profileContextClipboard => 'Clipboard';

  @override
  String get profileConsentGiven => 'Consent given';

  @override
  String get profileConsentMissing => 'Consent missing, so no context is read';

  @override
  String get profileConsentWithdraw => 'Withdraw consent';

  @override
  String get profileConsentTitle => 'Send context to a cloud service?';

  @override
  String get profileConsentBody =>
      'When this profile is active, the selected text or the clipboard contents of the target window are sent to the cloud provider named in this profile, only to refine this recording. You can withdraw this consent at any time in the profile settings.';

  @override
  String get profileConsentAccept => 'Consent';

  @override
  String get profileDeleteAction => 'Delete profile';

  @override
  String profileDeleteTitle(String name) {
    return 'Delete profile “$name”?';
  }

  @override
  String get profileDeleteMessage =>
      'The profile and its target apps are removed. Its hotkey becomes free.';

  @override
  String get manualProfilesTitle => 'Profiles and quick switching';

  @override
  String get manualProfilesS1Heading => 'Creating profiles';

  @override
  String get manualProfilesS1Body =>
      'A profile is a named set of recording settings. Create it under Settings → Profiles and decide for each field whether the profile sets it or leaves it unchanged.';

  @override
  String get manualProfilesS1B1 =>
      'Speech model, language, Smart Mode, after-transcription action and microphone';

  @override
  String get manualProfilesS1B2 =>
      'Up to 9 profiles. Every field can be set to “Leave unchanged”.';

  @override
  String get manualProfilesS2Heading => 'Hotkeys';

  @override
  String get manualProfilesS2Body =>
      'Each profile can have its own hotkey. Pressing it activates the profile, and it stays active until you choose another one or change one of its fields by hand.';

  @override
  String get manualProfilesS2Tip =>
      'A hotkey needs a modifier key. A combination that another feature already uses stays inactive, and the profile shows it as a conflict.';

  @override
  String get manualProfilesS3Heading => 'Automatic per app';

  @override
  String get manualProfilesS3Body =>
      'If you add an app under target apps, the profile becomes active whenever that app is in front while you dictate. The identifier depends on the operating system:';

  @override
  String get manualProfilesS3Mac =>
      'macOS: bundle ID, for example com.apple.mail';

  @override
  String get manualProfilesS3Win =>
      'Windows: program name without .exe, for example chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: window WM_CLASS under X11, for example google-chrome. Under Wayland WhisPaste cannot detect the app.';

  @override
  String get manualProfilesS4Heading => 'Tray and overlay';

  @override
  String get manualProfilesS4Body =>
      'The tray menu has a Profile submenu: “Automatic, by app” follows the rules, “No profile” switches them off, and your profiles are listed below. In the recording overlay, the name of the active profile follows the time and language, for example 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'Leave unchanged';

  @override
  String get manualProfilesS5Body =>
      '“Leave unchanged” means the profile does not touch this field. The value currently set in Settings applies.';

  @override
  String get manualProfilesS6Heading => 'What a manual change does';

  @override
  String get manualProfilesS6Body =>
      'If you choose a profile in the tray or press its hotkey, it applies to all following recordings. If you then change a field the profile sets, such as the speech model, the active marker ends and the per-app rules decide again. The choice survives a restart.';

  @override
  String get profileAppCapture => 'Capture app';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'Switch to the target app in $seconds s …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '“$identifier” was added as target app.';
  }

  @override
  String get profileAppCaptureNone =>
      'No other app is in front. Switch to the target app before the countdown ends.';

  @override
  String get profileAppCaptureUnavailable =>
      'This session cannot read the app in front (for example Wayland). Enter the identifier by hand.';
}
