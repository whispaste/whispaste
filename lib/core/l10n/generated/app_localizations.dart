import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste'**
  String get appName;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get navNotes;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navReplacements.
  ///
  /// In en, this message translates to:
  /// **'Replacements'**
  String get navReplacements;

  /// No description provided for @navSnippets.
  ///
  /// In en, this message translates to:
  /// **'Snippets'**
  String get navSnippets;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// No description provided for @navFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get navFeedback;

  /// No description provided for @pageHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get pageHistoryTitle;

  /// No description provided for @pageSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get pageSettingsTitle;

  /// No description provided for @pageReplacementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Replacements'**
  String get pageReplacementsTitle;

  /// No description provided for @pageAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get pageAnalyticsTitle;

  /// No description provided for @pageAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get pageAboutTitle;

  /// No description provided for @pageFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get pageFeedbackTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get historyEmpty;

  /// No description provided for @historyEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Press the record button or use the hotkey to start recording.'**
  String get historyEmptyHint;

  /// No description provided for @historySearch.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get historySearch;

  /// No description provided for @historyPinned.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get historyPinned;

  /// No description provided for @historyToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyToday;

  /// No description provided for @historyYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get historyYesterday;

  /// No description provided for @historyThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get historyThisWeek;

  /// No description provided for @historyOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get historyOlder;

  /// No description provided for @historyAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyAll;

  /// No description provided for @historyTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get historyTrash;

  /// No description provided for @historyArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get historyArchive;

  /// No description provided for @historyArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get historyArchived;

  /// No description provided for @historyList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get historyList;

  /// No description provided for @historyCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get historyCards;

  /// No description provided for @historyCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get historyCompact;

  /// No description provided for @historyItemsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String historyItemsSelected(int count);

  /// No description provided for @historyMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get historyMerge;

  /// No description provided for @historyRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get historyRestore;

  /// No description provided for @historyDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get historyDeleteForever;

  /// No description provided for @historyDeletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get historyDeletePermanently;

  /// No description provided for @historyUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get historyUnarchive;

  /// No description provided for @historyExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get historyExport;

  /// No description provided for @historyExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get historyExportAction;

  /// No description provided for @historyCopyAsMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get historyCopyAsMarkdown;

  /// No description provided for @historyDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get historyDetail;

  /// No description provided for @historyTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get historyTags;

  /// No description provided for @historyDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get historyDuration;

  /// No description provided for @historyModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get historyModel;

  /// No description provided for @historyWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get historyWords;

  /// No description provided for @historyCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get historyCharacters;

  /// No description provided for @historyWordCount.
  ///
  /// In en, this message translates to:
  /// **'{count} words'**
  String historyWordCount(int count);

  /// No description provided for @historyReadingTime.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min read'**
  String historyReadingTime(int minutes);

  /// No description provided for @historyReadingTimeUnder1.
  ///
  /// In en, this message translates to:
  /// **'< 1 min read'**
  String get historyReadingTimeUnder1;

  /// No description provided for @historyEditing.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get historyEditing;

  /// No description provided for @historySearchTranscriptions.
  ///
  /// In en, this message translates to:
  /// **'Search transcriptions…'**
  String get historySearchTranscriptions;

  /// No description provided for @historySearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search transcriptions'**
  String get historySearchFieldLabel;

  /// Label of the primary button beside the History search field. Starts the same recording the systemwide hotkey starts; worded like the items the page calls recordings, not like the transcription the search field mentions.
  ///
  /// In en, this message translates to:
  /// **'New recording'**
  String get historyNewRecording;

  /// Label the same button takes on while a recording runs — it stops that recording. Wording follows the tray item trayStopRecording, which ends the same recording from the other end of the app.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get historyStopRecording;

  /// No description provided for @historyNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get historyNoResults;

  /// No description provided for @historyNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'No transcriptions match \"{query}\".\nTry a different search term.'**
  String historyNoResultsHint(String query);

  /// No description provided for @historyTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get historyTrashEmpty;

  /// No description provided for @historyTrashEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Deleted transcriptions will appear here.\nItems are permanently removed after 30 days.'**
  String get historyTrashEmptyHint;

  /// No description provided for @historyEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get historyEmptyTrash;

  /// No description provided for @historyEmptyTrashConfirm.
  ///
  /// In en, this message translates to:
  /// **'Empty trash?'**
  String get historyEmptyTrashConfirm;

  /// No description provided for @historyEmptyTrashConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all items in the trash. This action cannot be undone.'**
  String get historyEmptyTrashConfirmMessage;

  /// Success toast after emptying the trash. The count is a placeholder inside the message rather than a parenthesis appended in Dart: a translator has to be able to move it (Hebrew reads right-to-left, so a trailing '(3)' lands on the wrong side of the sentence) and to choose the plural form for it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Trash emptied — 1 entry deleted} other{Trash emptied — {count} entries deleted}}'**
  String historyTrashEmptied(int count);

  /// No description provided for @historyNoArchivedItems.
  ///
  /// In en, this message translates to:
  /// **'No archived items'**
  String get historyNoArchivedItems;

  /// No description provided for @historyNoArchivedItemsHint.
  ///
  /// In en, this message translates to:
  /// **'Archive transcriptions you want to keep\nbut don\'t need in your main list.'**
  String get historyNoArchivedItemsHint;

  /// No description provided for @historyNoRecordingsHint.
  ///
  /// In en, this message translates to:
  /// **'Press the record button or use the hotkey to start recording.\nYour transcriptions will appear here.'**
  String get historyNoRecordingsHint;

  /// No description provided for @historyNoPinned.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get historyNoPinned;

  /// No description provided for @historyNoPinnedHint.
  ///
  /// In en, this message translates to:
  /// **'Mark a transcription as a favorite to find it here quickly.'**
  String get historyNoPinnedHint;

  /// No description provided for @historyNoToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded today'**
  String get historyNoToday;

  /// No description provided for @historyNoTodayHint.
  ///
  /// In en, this message translates to:
  /// **'Today\'s transcriptions will appear here.'**
  String get historyNoTodayHint;

  /// No description provided for @historyNoThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded this week'**
  String get historyNoThisWeek;

  /// No description provided for @historyNoThisWeekHint.
  ///
  /// In en, this message translates to:
  /// **'This week\'s transcriptions will appear here.'**
  String get historyNoThisWeekHint;

  /// No description provided for @historyCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get historyCopiedToClipboard;

  /// No description provided for @historyMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to trash'**
  String get historyMovedToTrash;

  /// No description provided for @historyUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get historyUndo;

  /// No description provided for @historyEntriesMerged.
  ///
  /// In en, this message translates to:
  /// **'Entries merged'**
  String get historyEntriesMerged;

  /// No description provided for @historyMergeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Merge {count} entries?'**
  String historyMergeConfirm(int count);

  /// No description provided for @historyMergeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The selected entries will be combined into one. This cannot be undone.'**
  String get historyMergeConfirmMessage;

  /// No description provided for @historyExitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get historyExitSelection;

  /// No description provided for @historySelectMultiple.
  ///
  /// In en, this message translates to:
  /// **'Select multiple'**
  String get historySelectMultiple;

  /// No description provided for @historyProcessed.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get historyProcessed;

  /// No description provided for @historyOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On device'**
  String get historyOnDevice;

  /// No description provided for @historyUntitledRecording.
  ///
  /// In en, this message translates to:
  /// **'Untitled recording'**
  String get historyUntitledRecording;

  /// No description provided for @historyUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get historyUntitled;

  /// No description provided for @historyPinToTop.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get historyPinToTop;

  /// No description provided for @historyUnpin.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get historyUnpin;

  /// No description provided for @historyCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get historyCopyText;

  /// No description provided for @historyClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get historyClose;

  /// No description provided for @historyLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get historyLanguageLabel;

  /// No description provided for @historyResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String historyResultCount(int count);

  /// No description provided for @historySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get historySelectAll;

  /// No description provided for @historyDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get historyDeselectAll;

  /// No description provided for @settingsInterface.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get settingsInterface;

  /// No description provided for @settingsInterfaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance and behavior'**
  String get settingsInterfaceSubtitle;

  /// No description provided for @settingsLaunchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Launch at Startup'**
  String get settingsLaunchAtStartup;

  /// No description provided for @settingsStartMinimized.
  ///
  /// In en, this message translates to:
  /// **'Start Minimized'**
  String get settingsStartMinimized;

  /// No description provided for @settingsStartMinimizedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start in the background when launched at system boot'**
  String get settingsStartMinimizedSubtitle;

  /// No description provided for @settingsAutostartNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsAutostartNever;

  /// No description provided for @settingsAutostartNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settingsAutostartNormal;

  /// No description provided for @settingsAutostartMinimized.
  ///
  /// In en, this message translates to:
  /// **'Minimized'**
  String get settingsAutostartMinimized;

  /// No description provided for @settingsAutostartSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Autostart couldn\'t be registered with the operating system. This may be a permissions issue or your OS version isn\'t supported.'**
  String get settingsAutostartSyncFailed;

  /// No description provided for @settingsShowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Show Notifications'**
  String get settingsShowNotifications;

  /// No description provided for @settingsShowBackendUtilization.
  ///
  /// In en, this message translates to:
  /// **'CPU/GPU indicator in status bar'**
  String get settingsShowBackendUtilization;

  /// No description provided for @settingsShowBackendUtilizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows whether transcription is really running on CPU or GPU, plus utilization'**
  String get settingsShowBackendUtilizationSubtitle;

  /// No description provided for @settingsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsAudio;

  /// No description provided for @settingsAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone and recording'**
  String get settingsAudioSubtitle;

  /// No description provided for @settingsMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsMicrophone;

  /// No description provided for @settingsGain.
  ///
  /// In en, this message translates to:
  /// **'Microphone Volume'**
  String get settingsGain;

  /// No description provided for @settingsClippingBanner.
  ///
  /// In en, this message translates to:
  /// **'Last recording had clipping. Reduce gain?'**
  String get settingsClippingBanner;

  /// No description provided for @settingsClippingDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get settingsClippingDismiss;

  /// No description provided for @settingsHoldToRecord.
  ///
  /// In en, this message translates to:
  /// **'Hold to Record'**
  String get settingsHoldToRecord;

  /// No description provided for @pushToTalkUnavailableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get pushToTalkUnavailableTooltip;

  /// No description provided for @settingsSpeechRecognition.
  ///
  /// In en, this message translates to:
  /// **'Speech Recognition'**
  String get settingsSpeechRecognition;

  /// No description provided for @settingsSpeechRecognitionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition quality and service'**
  String get settingsSpeechRecognitionSubtitle;

  /// No description provided for @settingsService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get settingsService;

  /// No description provided for @settingsQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get settingsQuality;

  /// No description provided for @settingsRecordingSafety.
  ///
  /// In en, this message translates to:
  /// **'Recording Safety'**
  String get settingsRecordingSafety;

  /// No description provided for @settingsRecordingSafetySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic checks and safeguards'**
  String get settingsRecordingSafetySubtitle;

  /// No description provided for @settingsDeadMicTimeout.
  ///
  /// In en, this message translates to:
  /// **'Silent Mic Detection'**
  String get settingsDeadMicTimeout;

  /// No description provided for @settingsDeadMicTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'Stop recording if no audio detected within this time (seconds). 0 = disabled.'**
  String get settingsDeadMicTimeoutHint;

  /// No description provided for @settingsAutoStopSilence.
  ///
  /// In en, this message translates to:
  /// **'Auto-Stop After Silence'**
  String get settingsAutoStopSilence;

  /// No description provided for @settingsAutoStopSilenceHint.
  ///
  /// In en, this message translates to:
  /// **'Automatically stop after this many seconds of silence (after speech). 0 = disabled.'**
  String get settingsAutoStopSilenceHint;

  /// No description provided for @settingsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsEnabled;

  /// No description provided for @settingsStyle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get settingsStyle;

  /// No description provided for @settingsMicSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get settingsMicSystemDefault;

  /// No description provided for @settingsMicSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Audio input is managed by your system settings'**
  String get settingsMicSystemHint;

  /// No description provided for @settingsServiceOnDevicePrivate.
  ///
  /// In en, this message translates to:
  /// **'Locally on Device'**
  String get settingsServiceOnDevicePrivate;

  /// No description provided for @settingsLanguageAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get settingsLanguageAutoDetect;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settingsLanguageGerman;

  /// No description provided for @settingsLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get settingsLanguageFrench;

  /// No description provided for @settingsLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLanguageSpanish;

  /// No description provided for @settingsLanguageHebrew.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get settingsLanguageHebrew;

  /// No description provided for @settingsSoundFeedback.
  ///
  /// In en, this message translates to:
  /// **'Sound & Feedback'**
  String get settingsSoundFeedback;

  /// No description provided for @settingsSoundFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Audio cues for recording events'**
  String get settingsSoundFeedbackSubtitle;

  /// No description provided for @settingsSoundsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Sounds'**
  String get settingsSoundsEnabled;

  /// No description provided for @settingsRecordStartSound.
  ///
  /// In en, this message translates to:
  /// **'Record Start Sound'**
  String get settingsRecordStartSound;

  /// No description provided for @settingsRecordStopSound.
  ///
  /// In en, this message translates to:
  /// **'Record Stop Sound'**
  String get settingsRecordStopSound;

  /// No description provided for @settingsTranscriptionCompleteSound.
  ///
  /// In en, this message translates to:
  /// **'Transcription Complete Sound'**
  String get settingsTranscriptionCompleteSound;

  /// No description provided for @settingsDurationWarningSound.
  ///
  /// In en, this message translates to:
  /// **'Duration Limit Warning'**
  String get settingsDurationWarningSound;

  /// No description provided for @settingsSoundVolume.
  ///
  /// In en, this message translates to:
  /// **'Sound Volume'**
  String get settingsSoundVolume;

  /// No description provided for @settingsAfterTranscription.
  ///
  /// In en, this message translates to:
  /// **'After Transcription'**
  String get settingsAfterTranscription;

  /// No description provided for @settingsAfterTranscriptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What happens with the transcribed text'**
  String get settingsAfterTranscriptionSubtitle;

  /// No description provided for @settingsAfterTranscriptionActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get settingsAfterTranscriptionActionLabel;

  /// No description provided for @settingsAfterTranscriptionClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get settingsAfterTranscriptionClipboard;

  /// No description provided for @settingsAfterTranscriptionPaste.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste at Cursor'**
  String get settingsAfterTranscriptionPaste;

  /// No description provided for @settingsAfterTranscriptionBoth.
  ///
  /// In en, this message translates to:
  /// **'Copy & Auto-Paste'**
  String get settingsAfterTranscriptionBoth;

  /// No description provided for @settingsAfterTranscriptionNothing.
  ///
  /// In en, this message translates to:
  /// **'Do Nothing'**
  String get settingsAfterTranscriptionNothing;

  /// No description provided for @pasteFailurePermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste was blocked by the OS. WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'.'**
  String get pasteFailurePermissionMissing;

  /// No description provided for @pasteFailureNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste skipped, no target window was captured. Focus the destination app before triggering a recording.'**
  String get pasteFailureNoTarget;

  /// No description provided for @pasteFailureElevationBlocked.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked: the target app is running with administrator rights. Restart WhisPaste as an administrator to paste into that app.'**
  String get pasteFailureElevationBlocked;

  /// No description provided for @pasteFailureGeneric.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste failed. The transcript is on the clipboard, paste it manually with ⌘V / Ctrl+V.'**
  String get pasteFailureGeneric;

  /// No description provided for @pasteFailureOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get pasteFailureOpenSettings;

  /// No description provided for @pasteCapabilityCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'One moment…'**
  String get pasteCapabilityCheckTitle;

  /// No description provided for @pasteCapabilityReady.
  ///
  /// In en, this message translates to:
  /// **'All set'**
  String get pasteCapabilityReady;

  /// No description provided for @pasteCapabilityReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your dictation lands right at the cursor.'**
  String get pasteCapabilityReadySubtitle;

  /// No description provided for @pasteCapabilityPermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'Not yet allowed'**
  String get pasteCapabilityPermissionMissing;

  /// No description provided for @pasteCapabilityUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste is not available on this platform'**
  String get pasteCapabilityUnsupported;

  /// No description provided for @pasteCapabilityTestButton.
  ///
  /// In en, this message translates to:
  /// **'Test now'**
  String get pasteCapabilityTestButton;

  /// No description provided for @pasteCapabilityGrantButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get pasteCapabilityGrantButton;

  /// No description provided for @pasteCapabilityWhyMac.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste needs permission to type text into the app you\'re working in — macOS calls this permission \'Accessibility\'.'**
  String get pasteCapabilityWhyMac;

  /// No description provided for @pasteCapabilityTroubleshoot.
  ///
  /// In en, this message translates to:
  /// **'Having trouble?'**
  String get pasteCapabilityTroubleshoot;

  /// No description provided for @pasteCapabilityRepairHint.
  ///
  /// In en, this message translates to:
  /// **'Sometimes macOS remembers an old entry and forgets the new approval. Reset the entry. macOS will then ask you cleanly again.'**
  String get pasteCapabilityRepairHint;

  /// No description provided for @pasteCapabilityRepairButton.
  ///
  /// In en, this message translates to:
  /// **'Reset entry'**
  String get pasteCapabilityRepairButton;

  /// No description provided for @pasteCapabilityRestartButton.
  ///
  /// In en, this message translates to:
  /// **'Restart WhisPaste'**
  String get pasteCapabilityRestartButton;

  /// No description provided for @pasteCapabilityRestartTitle.
  ///
  /// In en, this message translates to:
  /// **'Almost there — restart WhisPaste'**
  String get pasteCapabilityRestartTitle;

  /// No description provided for @pasteCapabilityRestartBody.
  ///
  /// In en, this message translates to:
  /// **'If you enabled the permission, macOS only applies it to a freshly started app. One click — WhisPaste quits and comes right back.'**
  String get pasteCapabilityRestartBody;

  /// No description provided for @pasteRestartAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart WhisPaste now'**
  String get pasteRestartAlertTitle;

  /// No description provided for @pasteRestartAlertBody.
  ///
  /// In en, this message translates to:
  /// **'The Auto-Paste permission is set, but macOS only applies it after a restart. WhisPaste will quit and come right back.'**
  String get pasteRestartAlertBody;

  /// No description provided for @pasteRestartAlertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restart now'**
  String get pasteRestartAlertConfirm;

  /// No description provided for @pasteManualGrantAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'The restart didn\'t help'**
  String get pasteManualGrantAlertTitle;

  /// No description provided for @pasteManualGrantAlertBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste already restarted, but the Auto-Paste permission still isn\'t taking effect. Please check under System Settings → Privacy & Security → Accessibility whether WhisPaste is switched on there, and re-enable the toggle if needed.'**
  String get pasteManualGrantAlertBody;

  /// No description provided for @pasteManualGrantAlertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get pasteManualGrantAlertConfirm;

  /// No description provided for @permissionAlertLaterButton.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get permissionAlertLaterButton;

  /// No description provided for @micGateAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is missing'**
  String get micGateAlertTitle;

  /// No description provided for @micGateAlertBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste can\'t record without microphone access. Confirm to open System Settings → Privacy & Security → Microphone — enable the switch for WhisPaste there. WhisPaste detects your approval automatically.'**
  String get micGateAlertBody;

  /// No description provided for @micGateAlertBodyGeneric.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste can\'t record without microphone access. Please allow microphone access for WhisPaste in your system\'s privacy settings — WhisPaste detects your approval automatically.'**
  String get micGateAlertBodyGeneric;

  /// No description provided for @micGateAlertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get micGateAlertConfirm;

  /// No description provided for @micGateRestartAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart WhisPaste to finish'**
  String get micGateRestartAlertTitle;

  /// No description provided for @micGateRestartAlertBody.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is granted, but this running WhisPaste instance can\'t pick it up yet. WhisPaste will quit and come right back — everything stays as it is.'**
  String get micGateRestartAlertBody;

  /// No description provided for @micGateRestartAlertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restart now'**
  String get micGateRestartAlertConfirm;

  /// No description provided for @autoPasteGateAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'One switch is missing for auto-insert'**
  String get autoPasteGateAlertTitle;

  /// No description provided for @autoPasteGateAlertBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste inserts your dictation right at the cursor. macOS requires one switch for that which only you can flip: System Settings → Privacy & Security → Accessibility. Confirm to open exactly that page — WhisPaste detects your approval automatically and restarts itself afterwards if needed.'**
  String get autoPasteGateAlertBody;

  /// No description provided for @autoPasteGateAlertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get autoPasteGateAlertConfirm;

  /// No description provided for @pasteCapabilityRestartIneffectiveTitle.
  ///
  /// In en, this message translates to:
  /// **'The restart didn\'t apply the permission'**
  String get pasteCapabilityRestartIneffectiveTitle;

  /// No description provided for @pasteCapabilityRestartIneffectiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the permission again and check under System Settings → Privacy & Security → Accessibility that WhisPaste is really switched on. Re-enable the toggle, then WhisPaste restarts once more.'**
  String get pasteCapabilityRestartIneffectiveSubtitle;

  /// No description provided for @pasteCapabilityRepairDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No stale entries found. Try paste once.}=1{Cleared 1 stale entry. Try paste once to see a fresh prompt.}other{Cleared {count} stale entries. Try paste once to see fresh prompts.}}'**
  String pasteCapabilityRepairDone(int count);

  /// No description provided for @pasteCapabilityRepairNothingToClear.
  ///
  /// In en, this message translates to:
  /// **'No old entry found. A restart is likely to help now.'**
  String get pasteCapabilityRepairNothingToClear;

  /// No description provided for @pasteCapabilityRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not run the macOS permission reset. Try removing WhisPaste from System Settings → Accessibility manually.'**
  String get pasteCapabilityRepairFailed;

  /// No description provided for @onboardingPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'So your text lands where you\'re typing'**
  String get onboardingPasteTitle;

  /// No description provided for @onboardingPasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'macOS will ask you in a moment whether WhisPaste may do this. Say yes, done.'**
  String get onboardingPasteSubtitle;

  /// No description provided for @onboardingPasteSubtitleWin.
  ///
  /// In en, this message translates to:
  /// **'No permission needed on Windows — just choose whether WhisPaste should insert dictated text for you.'**
  String get onboardingPasteSubtitleWin;

  /// No description provided for @onboardingPasteChipReady.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste ready'**
  String get onboardingPasteChipReady;

  /// No description provided for @onboardingPasteChipPending.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste access pending'**
  String get onboardingPasteChipPending;

  /// No description provided for @onboardingPasteChipAction.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste: action needed'**
  String get onboardingPasteChipAction;

  /// No description provided for @onboardingPasteGrantCta.
  ///
  /// In en, this message translates to:
  /// **'Allow auto-paste'**
  String get onboardingPasteGrantCta;

  /// No description provided for @onboardingPasteSkip.
  ///
  /// In en, this message translates to:
  /// **'Just copy for now, no auto-insert'**
  String get onboardingPasteSkip;

  /// No description provided for @onboardingPasteWhyMac.
  ///
  /// In en, this message translates to:
  /// **'Without permission, your text is copied to the clipboard. You\'ll then paste manually with ⌘V.'**
  String get onboardingPasteWhyMac;

  /// No description provided for @onboardingPasteWhyWin.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste presses Ctrl+V for you after each dictation, so the text lands right where you\'re typing. Verified working on this machine — turn it on below.'**
  String get onboardingPasteWhyWin;

  /// No description provided for @onboardingPasteWhyWinUipi.
  ///
  /// In en, this message translates to:
  /// **'In certain apps with UIPI/UAC protection, Auto-Paste won\'t work. The text will sit in the clipboard and you\'ll need to paste it with Ctrl+V yourself.'**
  String get onboardingPasteWhyWinUipi;

  /// No description provided for @onboardingPasteWinOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste is on'**
  String get onboardingPasteWinOnTitle;

  /// No description provided for @onboardingPasteWinOnDetail.
  ///
  /// In en, this message translates to:
  /// **'After each dictation, WhisPaste presses Ctrl+V for you — the text lands right at your cursor. A copy stays on the clipboard, too.'**
  String get onboardingPasteWinOnDetail;

  /// No description provided for @onboardingPasteWinEnableCta.
  ///
  /// In en, this message translates to:
  /// **'Turn on Auto-Paste'**
  String get onboardingPasteWinEnableCta;

  /// No description provided for @onboardingPasteWinAdminCaveat.
  ///
  /// In en, this message translates to:
  /// **'Apps running as administrator don\'t accept simulated keystrokes — there your text stays on the clipboard, ready to paste with Ctrl+V.'**
  String get onboardingPasteWinAdminCaveat;

  /// No description provided for @onboardingPasteWaitingForGrantTitle.
  ///
  /// In en, this message translates to:
  /// **'Tick the box next to WhisPaste'**
  String get onboardingPasteWaitingForGrantTitle;

  /// No description provided for @onboardingPasteWaitingForGrantHint.
  ///
  /// In en, this message translates to:
  /// **'System Settings is open. Find WhisPaste in the list and switch it on.\n\nNot in the list? Drag the app icon in or click „+\".'**
  String get onboardingPasteWaitingForGrantHint;

  /// No description provided for @onboardingPasteTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Try Auto-Paste'**
  String get onboardingPasteTestTitle;

  /// No description provided for @onboardingPasteTestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Click the button. The demo text should appear in the field below.'**
  String get onboardingPasteTestSubtitle;

  /// No description provided for @onboardingPasteDemoText.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste types for you.'**
  String get onboardingPasteDemoText;

  /// No description provided for @onboardingPasteTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste works! Click Next to continue.'**
  String get onboardingPasteTestSuccess;

  /// No description provided for @onboardingPasteTestNoFrontmost.
  ///
  /// In en, this message translates to:
  /// **'No input field detected. Click the field below and try again.'**
  String get onboardingPasteTestNoFrontmost;

  /// No description provided for @onboardingPasteTestFailure.
  ///
  /// In en, this message translates to:
  /// **'Test failed. Try restarting the app, or continue without testing.'**
  String get onboardingPasteTestFailure;

  /// No description provided for @onboardingPasteTestSkip.
  ///
  /// In en, this message translates to:
  /// **'Continue without testing'**
  String get onboardingPasteTestSkip;

  /// No description provided for @settingsOverlayFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'Recording Overlay'**
  String get settingsOverlayFloatingButton;

  /// No description provided for @settingsOverlayFloatingButtonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control how recording status appears while you record'**
  String get settingsOverlayFloatingButtonSubtitle;

  /// No description provided for @settingsShowOverlay.
  ///
  /// In en, this message translates to:
  /// **'Recording status display'**
  String get settingsShowOverlay;

  /// No description provided for @settingsShowOverlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose where live recording feedback appears while you record'**
  String get settingsShowOverlaySubtitle;

  /// No description provided for @settingsOverlayModeFloating.
  ///
  /// In en, this message translates to:
  /// **'Floating window (always visible)'**
  String get settingsOverlayModeFloating;

  /// No description provided for @settingsOverlayModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOverlayModeOff;

  /// No description provided for @settingsOverlayStartPosition.
  ///
  /// In en, this message translates to:
  /// **'Overlay start position'**
  String get settingsOverlayStartPosition;

  /// No description provided for @settingsOverlayStartPositionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where the floating overlay appears when recording starts'**
  String get settingsOverlayStartPositionSubtitle;

  /// No description provided for @settingsOverlayStartTopCenter.
  ///
  /// In en, this message translates to:
  /// **'Top center'**
  String get settingsOverlayStartTopCenter;

  /// No description provided for @settingsOverlayStartBottomCenter.
  ///
  /// In en, this message translates to:
  /// **'Bottom center'**
  String get settingsOverlayStartBottomCenter;

  /// No description provided for @settingsOverlayStartLastPosition.
  ///
  /// In en, this message translates to:
  /// **'Remember last position'**
  String get settingsOverlayStartLastPosition;

  /// No description provided for @settingsShowFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'Floating recording button'**
  String get settingsShowFloatingButton;

  /// No description provided for @settingsShowFloatingButtonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Small always-on-top button for starting or stopping recording from any app'**
  String get settingsShowFloatingButtonSubtitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsRecognitionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Recognition Language'**
  String get settingsRecognitionLanguage;

  /// No description provided for @settingsCustomVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Custom Vocabulary'**
  String get settingsCustomVocabulary;

  /// No description provided for @settingsCustomVocabularyHint.
  ///
  /// In en, this message translates to:
  /// **'Names, technical terms: improves recognition accuracy'**
  String get settingsCustomVocabularyHint;

  /// No description provided for @settingsCustomVocabularyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. WhisPaste, Kubernetes, Dr. Mueller'**
  String get settingsCustomVocabularyPlaceholder;

  /// No description provided for @settingsPunctuationPriming.
  ///
  /// In en, this message translates to:
  /// **'Punctuation priming'**
  String get settingsPunctuationPriming;

  /// No description provided for @settingsPunctuationPrimingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nudges Whisper towards punctuated output when no custom vocabulary is set. No effect on speed.'**
  String get settingsPunctuationPrimingSubtitle;

  /// No description provided for @settingsVadEnabled.
  ///
  /// In en, this message translates to:
  /// **'Trim trailing silence'**
  String get settingsVadEnabled;

  /// No description provided for @settingsVadEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes long silence/noise at the end of a recording before Whisper decodes it, so it can\'t fabricate a closing sentence there (e.g. \"Thanks for watching\"-style hallucinations). Negligible cost, off if you\'d rather keep Whisper\'s raw output.'**
  String get settingsVadEnabledSubtitle;

  /// No description provided for @settingsStripPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Strip punctuation'**
  String get settingsStripPunctuation;

  /// No description provided for @settingsStripPunctuationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes periods, commas, and other sentence punctuation from every transcript before it\'s saved or pasted. Works the same way for every engine and provider, not just Whisper.'**
  String get settingsStripPunctuationSubtitle;

  /// No description provided for @settingsNumericOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Numbers only'**
  String get settingsNumericOnlyMode;

  /// No description provided for @settingsNumericOnlyModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Converts spoken numbers (German and English) to digits, e.g. \"five point two\" becomes \"5.2\". Leaves the transcript untouched if it isn\'t fully convertible.'**
  String get settingsNumericOnlyModeSubtitle;

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsSttModels.
  ///
  /// In en, this message translates to:
  /// **'Speech Recognition Models'**
  String get settingsSttModels;

  /// No description provided for @settingsOpenAiApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API Key'**
  String get settingsOpenAiApiKey;

  /// No description provided for @settingsDeepgramApiKey.
  ///
  /// In en, this message translates to:
  /// **'Deepgram API Key'**
  String get settingsDeepgramApiKey;

  /// Tooltip for the show/hide button on API key input fields.
  ///
  /// In en, this message translates to:
  /// **'Toggle API key visibility'**
  String get settingsToggleApiKeyVisibility;

  /// No description provided for @settingsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvanced;

  /// No description provided for @settingsAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reset, error reporting, updates, and system behavior'**
  String get settingsAdvancedSubtitle;

  /// No description provided for @settingsResetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get settingsResetToDefaults;

  /// No description provided for @settingsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Settings'**
  String get settingsResetTitle;

  /// No description provided for @settingsResetMessage.
  ///
  /// In en, this message translates to:
  /// **'All settings will be restored to defaults. API keys will be removed. This cannot be undone.'**
  String get settingsResetMessage;

  /// No description provided for @settingsResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetConfirm;

  /// No description provided for @settingsResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings reset to defaults'**
  String get settingsResetSuccess;

  /// No description provided for @settingsFactoryReset.
  ///
  /// In en, this message translates to:
  /// **'Factory Reset'**
  String get settingsFactoryReset;

  /// No description provided for @settingsFactoryResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Factory Reset'**
  String get settingsFactoryResetTitle;

  /// No description provided for @settingsFactoryResetMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete ALL data: recording history, tags, replacements, downloaded models, logs, and settings. The app will return to its initial state.\n\nThis cannot be undone.'**
  String get settingsFactoryResetMessage;

  /// No description provided for @settingsFactoryResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Everything'**
  String get settingsFactoryResetConfirm;

  /// No description provided for @settingsFactoryResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'App has been completely reset'**
  String get settingsFactoryResetSuccess;

  /// No description provided for @settingsFactoryResetProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Resetting WhisPaste'**
  String get settingsFactoryResetProgressTitle;

  /// No description provided for @settingsFactoryResetPhaseStoppingSubprocess.
  ///
  /// In en, this message translates to:
  /// **'Stopping voice service…'**
  String get settingsFactoryResetPhaseStoppingSubprocess;

  /// No description provided for @settingsFactoryResetPhaseDeletingModels.
  ///
  /// In en, this message translates to:
  /// **'Deleting voice models…'**
  String get settingsFactoryResetPhaseDeletingModels;

  /// No description provided for @settingsFactoryResetPhaseDeletingDatabase.
  ///
  /// In en, this message translates to:
  /// **'Deleting database…'**
  String get settingsFactoryResetPhaseDeletingDatabase;

  /// No description provided for @settingsFactoryResetPhaseResettingSecureStore.
  ///
  /// In en, this message translates to:
  /// **'Clearing credentials…'**
  String get settingsFactoryResetPhaseResettingSecureStore;

  /// No description provided for @settingsFactoryResetPhaseResettingSettings.
  ///
  /// In en, this message translates to:
  /// **'Restoring default settings…'**
  String get settingsFactoryResetPhaseResettingSettings;

  /// No description provided for @settingsFactoryResetFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Factory reset incomplete. Please restart the app.'**
  String get settingsFactoryResetFailedMessage;

  /// No description provided for @settingsPortabilitySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & Transfer'**
  String get settingsPortabilitySectionTitle;

  /// No description provided for @settingsPortabilitySectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep a backup of your WhisPaste setup or take it to another computer'**
  String get settingsPortabilitySectionSubtitle;

  /// No description provided for @settingsPortabilityExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsPortabilityExportAction;

  /// No description provided for @settingsPortabilityImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsPortabilityImportAction;

  /// No description provided for @settingsPortabilityExportLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Export destination'**
  String get settingsPortabilityExportLocationLabel;

  /// No description provided for @settingsPortabilityImportLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Import source'**
  String get settingsPortabilityImportLocationLabel;

  /// No description provided for @settingsPortabilityExportLocationUnset.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be asked on first export'**
  String get settingsPortabilityExportLocationUnset;

  /// No description provided for @settingsPortabilityImportLocationUnset.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be asked on first import'**
  String get settingsPortabilityImportLocationUnset;

  /// No description provided for @settingsPortabilityChooseExportLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose a different export destination (nothing is exported yet)'**
  String get settingsPortabilityChooseExportLocation;

  /// No description provided for @settingsPortabilityChooseImportLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose a different import source (nothing is imported yet)'**
  String get settingsPortabilityChooseImportLocation;

  /// No description provided for @settingsPortabilityExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings exported to {path}'**
  String settingsPortabilityExportSuccess(String path);

  /// No description provided for @settingsPortabilityExportError.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {reason}'**
  String settingsPortabilityExportError(String reason);

  /// No description provided for @settingsPortabilityImportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Settings?'**
  String get settingsPortabilityImportConfirmTitle;

  /// No description provided for @settingsPortabilityImportConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This replaces your current settings — including interface, speech-recognition configuration, behavior, text replacements, and snippets — with the contents of {path}. Your API keys are left untouched.'**
  String settingsPortabilityImportConfirmMessage(String path);

  /// No description provided for @settingsPortabilityImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings imported from {path}'**
  String settingsPortabilityImportSuccess(String path);

  /// Deliberate residual case (Ticket 03, settings-portability-vollumfang): since the import target now comes from a remembered path or a native open-file dialog, a missing file is caught internally and silently re-prompts the dialog instead of showing this message. It only surfaces if the freshly re-picked file also vanishes before it can be read (a narrow race), so it stays worded as generic guidance rather than describing that race.
  ///
  /// In en, this message translates to:
  /// **'No export file found at {path}. Export settings first, or copy an export file there.'**
  String settingsPortabilityImportNotFound(String path);

  /// No description provided for @settingsPortabilityImportError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {reason}'**
  String settingsPortabilityImportError(String reason);

  /// No description provided for @settingsAutosaveLabel.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup'**
  String get settingsAutosaveLabel;

  /// No description provided for @settingsAutosaveHint.
  ///
  /// In en, this message translates to:
  /// **'Saves your setup to the chosen folder a few seconds after every change'**
  String get settingsAutosaveHint;

  /// No description provided for @settingsAutosaveChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose a different folder for automatic backups (nothing is backed up yet)'**
  String get settingsAutosaveChooseFolder;

  /// No description provided for @settingsAutosaveLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {time}'**
  String settingsAutosaveLastRun(String time);

  /// No description provided for @settingsAutosaveNeverRun.
  ///
  /// In en, this message translates to:
  /// **'No backup yet'**
  String get settingsAutosaveNeverRun;

  /// No description provided for @settingsAutosaveLastRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get settingsAutosaveLastRunFailed;

  /// No description provided for @settingsAutosaveLastRunFailedSince.
  ///
  /// In en, this message translates to:
  /// **'Last attempt failed — last backup: {time}'**
  String settingsAutosaveLastRunFailedSince(String time);

  /// No description provided for @settingsAutosaveErrorLocation.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup failed: the chosen folder is unavailable.'**
  String get settingsAutosaveErrorLocation;

  /// No description provided for @settingsAutosaveErrorWrite.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup failed: {reason}'**
  String settingsAutosaveErrorWrite(String reason);

  /// No description provided for @groqRemovedToast.
  ///
  /// In en, this message translates to:
  /// **'Groq STT was removed. Provider reset to On-Device.'**
  String get groqRemovedToast;

  /// No description provided for @tccResetAfterUpdateToast.
  ///
  /// In en, this message translates to:
  /// **'macOS reset your Auto-Paste permission during the update.'**
  String get tccResetAfterUpdateToast;

  /// No description provided for @migrationComplete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 recording migrated from WhisPaste 1.x} other{{count} recordings migrated from WhisPaste 1.x}}'**
  String migrationComplete(int count);

  /// No description provided for @settingsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOff;

  /// No description provided for @settingsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsOn;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;

  /// No description provided for @statusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get statusRecording;

  /// No description provided for @statusTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get statusTranscribing;

  /// No description provided for @statusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get statusProcessing;

  /// No description provided for @statusTranscriptionDone.
  ///
  /// In en, this message translates to:
  /// **'Transcription complete'**
  String get statusTranscriptionDone;

  /// No description provided for @statusCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get statusCopied;

  /// No description provided for @statusLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get statusLocal;

  /// No description provided for @statusCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get statusCloud;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @recordingGuardFailed.
  ///
  /// In en, this message translates to:
  /// **'No audio detected. Please try again. Sometimes the microphone needs a moment to warm up.'**
  String get recordingGuardFailed;

  /// No description provided for @recordingAutoStopped.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped: silence detected.'**
  String get recordingAutoStopped;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get actionDuplicate;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get actionDismiss;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionExport;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// Tooltip and screen-reader label of WpSearchField's clear button. Used by every search field that has no feature-specific wording of its own.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get actionClearSearch;

  /// No description provided for @tooltipLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get tooltipLanguage;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @onboardingWelcome.
  ///
  /// In en, this message translates to:
  /// **'Speak it once. Paste it anywhere.'**
  String get onboardingWelcome;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you think. We read every message.'**
  String get feedbackHint;

  /// No description provided for @analyticsPreviewBanner.
  ///
  /// In en, this message translates to:
  /// **'Preview: showing sample data. Real analytics will appear once you start recording.'**
  String get analyticsPreviewBanner;

  /// No description provided for @analyticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get analyticsEmptyTitle;

  /// No description provided for @analyticsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start recording to see your analytics here.'**
  String get analyticsEmptySubtitle;

  /// No description provided for @analyticsOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get analyticsOverview;

  /// No description provided for @analyticsOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your recording stats at a glance'**
  String get analyticsOverviewSubtitle;

  /// No description provided for @analyticsActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get analyticsActivity;

  /// No description provided for @analyticsInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get analyticsInsights;

  /// No description provided for @analyticsTotalRecordings.
  ///
  /// In en, this message translates to:
  /// **'Total Recordings'**
  String get analyticsTotalRecordings;

  /// No description provided for @analyticsTotalDuration.
  ///
  /// In en, this message translates to:
  /// **'Total Duration'**
  String get analyticsTotalDuration;

  /// No description provided for @analyticsWordsDictated.
  ///
  /// In en, this message translates to:
  /// **'Words Transcribed'**
  String get analyticsWordsDictated;

  /// No description provided for @analyticsTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Time Saved'**
  String get analyticsTimeSaved;

  /// No description provided for @analyticsAvgLatency.
  ///
  /// In en, this message translates to:
  /// **'Avg. Speed'**
  String get analyticsAvgLatency;

  /// No description provided for @analyticsRecordingActivity.
  ///
  /// In en, this message translates to:
  /// **'Recording Activity'**
  String get analyticsRecordingActivity;

  /// No description provided for @analyticsLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get analyticsLast7Days;

  /// No description provided for @analyticsModelUsage.
  ///
  /// In en, this message translates to:
  /// **'Model Usage'**
  String get analyticsModelUsage;

  /// No description provided for @analyticsDurationDistribution.
  ///
  /// In en, this message translates to:
  /// **'Duration Distribution'**
  String get analyticsDurationDistribution;

  /// No description provided for @analyticsCostSavings.
  ///
  /// In en, this message translates to:
  /// **'Cost & Savings'**
  String get analyticsCostSavings;

  /// No description provided for @analyticsLocalSavings.
  ///
  /// In en, this message translates to:
  /// **'Local savings'**
  String get analyticsLocalSavings;

  /// No description provided for @analyticsCloudCost.
  ///
  /// In en, this message translates to:
  /// **'Cloud cost'**
  String get analyticsCloudCost;

  /// No description provided for @analyticsPeriod7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get analyticsPeriod7d;

  /// No description provided for @analyticsPeriod30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get analyticsPeriod30d;

  /// No description provided for @analyticsPeriod90d.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get analyticsPeriod90d;

  /// No description provided for @analyticsPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get analyticsPeriodAll;

  /// No description provided for @analyticsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get analyticsReset;

  /// No description provided for @analyticsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Statistics'**
  String get analyticsResetTitle;

  /// No description provided for @analyticsResetMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all analytics data? This action cannot be undone.'**
  String get analyticsResetMessage;

  /// No description provided for @analyticsDayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get analyticsDayMon;

  /// No description provided for @analyticsDayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get analyticsDayTue;

  /// No description provided for @analyticsDayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get analyticsDayWed;

  /// No description provided for @analyticsDayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get analyticsDayThu;

  /// No description provided for @analyticsDayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get analyticsDayFri;

  /// No description provided for @analyticsDaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get analyticsDaySat;

  /// No description provided for @analyticsDaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get analyticsDaySun;

  /// No description provided for @analyticsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'{delta} this week'**
  String analyticsThisWeek(String delta);

  /// No description provided for @analyticsVsLastMonth.
  ///
  /// In en, this message translates to:
  /// **'{delta} vs last month'**
  String analyticsVsLastMonth(String delta);

  /// No description provided for @analyticsDurationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String analyticsDurationHoursMinutes(int hours, int minutes);

  /// No description provided for @analyticsDurationLt15s.
  ///
  /// In en, this message translates to:
  /// **'< 15s'**
  String get analyticsDurationLt15s;

  /// No description provided for @analyticsDuration15To30s.
  ///
  /// In en, this message translates to:
  /// **'15-30s'**
  String get analyticsDuration15To30s;

  /// No description provided for @analyticsDuration30To60s.
  ///
  /// In en, this message translates to:
  /// **'30-60s'**
  String get analyticsDuration30To60s;

  /// No description provided for @analyticsDuration1To3m.
  ///
  /// In en, this message translates to:
  /// **'1-3m'**
  String get analyticsDuration1To3m;

  /// No description provided for @analyticsDurationGt3m.
  ///
  /// In en, this message translates to:
  /// **'> 3m'**
  String get analyticsDurationGt3m;

  /// No description provided for @analyticsSavedAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} saved'**
  String analyticsSavedAmount(String amount);

  /// No description provided for @analyticsSpentAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} spent'**
  String analyticsSpentAmount(String amount);

  /// No description provided for @replacementsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search replacements…'**
  String get replacementsSearch;

  /// No description provided for @replacementsSearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search replacements'**
  String get replacementsSearchFieldLabel;

  /// No description provided for @replacementsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get replacementsAdd;

  /// No description provided for @replacementsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No replacements yet'**
  String get replacementsEmpty;

  /// No description provided for @replacementsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add replacements to auto-replace words while recording.\nExample: \"btw\" → \"by the way\"'**
  String get replacementsEmptyHint;

  /// No description provided for @replacementsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get replacementsNoMatches;

  /// No description provided for @replacementsNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get replacementsNoMatchesHint;

  /// No description provided for @replacementsToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable replacements'**
  String get replacementsToggleLabel;

  /// No description provided for @replacementsToggleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Replacements are active'**
  String get replacementsToggleEnabled;

  /// No description provided for @replacementsToggleDisabled.
  ///
  /// In en, this message translates to:
  /// **'Replacements are disabled'**
  String get replacementsToggleDisabled;

  /// No description provided for @replacementsEnableBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Replacements are turned off'**
  String get replacementsEnableBannerTitle;

  /// No description provided for @replacementsEnableBannerHint.
  ///
  /// In en, this message translates to:
  /// **'Enable them so trigger phrases are replaced automatically while recording.'**
  String get replacementsEnableBannerHint;

  /// No description provided for @replacementsEnableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get replacementsEnableAction;

  /// No description provided for @replacementsDisableAction.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get replacementsDisableAction;

  /// No description provided for @replacementsEditShortcut.
  ///
  /// In en, this message translates to:
  /// **'Edit Replacement'**
  String get replacementsEditShortcut;

  /// No description provided for @replacementsNewShortcut.
  ///
  /// In en, this message translates to:
  /// **'New Replacement'**
  String get replacementsNewShortcut;

  /// No description provided for @replacementsDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Any of the trigger phrases will be replaced automatically while recording.'**
  String get replacementsDialogHint;

  /// No description provided for @replacementsTriggerLabel.
  ///
  /// In en, this message translates to:
  /// **'Trigger phrases'**
  String get replacementsTriggerLabel;

  /// No description provided for @replacementsTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. btw'**
  String get replacementsTriggerHint;

  /// No description provided for @replacementsAddTrigger.
  ///
  /// In en, this message translates to:
  /// **'Add trigger phrase'**
  String get replacementsAddTrigger;

  /// No description provided for @replacementsRemoveTrigger.
  ///
  /// In en, this message translates to:
  /// **'Remove trigger phrase'**
  String get replacementsRemoveTrigger;

  /// No description provided for @replacementsReplacementLabel.
  ///
  /// In en, this message translates to:
  /// **'Replacement text'**
  String get replacementsReplacementLabel;

  /// No description provided for @replacementsReplacementHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. by the way'**
  String get replacementsReplacementHint;

  /// No description provided for @replacementsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Replacement'**
  String get replacementsDeleteTitle;

  /// No description provided for @replacementsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove the replacement \"{trigger}\"? This cannot be undone.'**
  String replacementsDeleteMessage(String trigger);

  /// No description provided for @replacementsImportFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Import from folder'**
  String get replacementsImportFromFolder;

  /// No description provided for @replacementsImportHint.
  ///
  /// In en, this message translates to:
  /// **'Scan a project folder for identifiers and add them as fuzzy replacements — nothing leaves your device.'**
  String get replacementsImportHint;

  /// No description provided for @replacementsImportSummary.
  ///
  /// In en, this message translates to:
  /// **'Found {found}, added {added}, skipped {skipped} duplicate(s)'**
  String replacementsImportSummary(int found, int added, int skipped);

  /// No description provided for @replacementsImportScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning the folder — this can take a moment for large projects…'**
  String get replacementsImportScanning;

  /// No description provided for @replacementsImportError.
  ///
  /// In en, this message translates to:
  /// **'Import failed — the folder could not be scanned.'**
  String get replacementsImportError;

  /// No description provided for @replacementsImportedBadge.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get replacementsImportedBadge;

  /// No description provided for @replacementsImportNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No new identifiers found in this folder.'**
  String get replacementsImportNothingFound;

  /// No description provided for @replacementsImportReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what to import'**
  String get replacementsImportReviewTitle;

  /// No description provided for @replacementsImportReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} candidates found — pick which ones become replacements. Nothing is added until you confirm.'**
  String replacementsImportReviewSubtitle(int count);

  /// No description provided for @replacementsImportReviewSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter candidates'**
  String get replacementsImportReviewSearchHint;

  /// No description provided for @replacementsImportReviewSelectAllFiltered.
  ///
  /// In en, this message translates to:
  /// **'Select all shown'**
  String get replacementsImportReviewSelectAllFiltered;

  /// No description provided for @replacementsImportReviewDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get replacementsImportReviewDeselectAll;

  /// No description provided for @replacementsImportReviewSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} selected'**
  String replacementsImportReviewSelectedCount(int selected, int total);

  /// No description provided for @replacementsImportReviewNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No candidates match your filter.'**
  String get replacementsImportReviewNoMatches;

  /// No description provided for @replacementsImportReviewImportButton.
  ///
  /// In en, this message translates to:
  /// **'Import selected ({count})'**
  String replacementsImportReviewImportButton(int count);

  /// No description provided for @replacementsMatchModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Matching'**
  String get replacementsMatchModeLabel;

  /// No description provided for @replacementsMatchModeExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get replacementsMatchModeExact;

  /// No description provided for @replacementsMatchModeFuzzy.
  ///
  /// In en, this message translates to:
  /// **'Similar'**
  String get replacementsMatchModeFuzzy;

  /// No description provided for @replacementsFuzzyToleranceLabel.
  ///
  /// In en, this message translates to:
  /// **'Tolerance'**
  String get replacementsFuzzyToleranceLabel;

  /// No description provided for @replacementsFuzzyToleranceStrict.
  ///
  /// In en, this message translates to:
  /// **'Strict'**
  String get replacementsFuzzyToleranceStrict;

  /// No description provided for @replacementsFuzzyToleranceStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get replacementsFuzzyToleranceStandard;

  /// No description provided for @replacementsFuzzyToleranceTolerant.
  ///
  /// In en, this message translates to:
  /// **'Tolerant'**
  String get replacementsFuzzyToleranceTolerant;

  /// No description provided for @replacementsFuzzyToleranceHint.
  ///
  /// In en, this message translates to:
  /// **'How close a dictated phrase must sound to a trigger to still count as a match. Strict only catches near-identical wording, so almost nothing gets replaced by accident, but a mumbled trigger may slip through unmatched. Standard is a balanced default for everyday dictation. Tolerant also catches noticeably different pronunciation or phrasing, at a higher risk of matching something you did not mean to replace.'**
  String get replacementsFuzzyToleranceHint;

  /// No description provided for @replacementsFuzzyTooShortWarning.
  ///
  /// In en, this message translates to:
  /// **'Trigger phrases under {minLength} characters cannot use similar matching — too many false hits.'**
  String replacementsFuzzyTooShortWarning(int minLength);

  /// No description provided for @snippetsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search snippets…'**
  String get snippetsSearch;

  /// No description provided for @snippetsSearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search snippets'**
  String get snippetsSearchFieldLabel;

  /// No description provided for @snippetsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get snippetsAdd;

  /// No description provided for @snippetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No snippets yet'**
  String get snippetsEmpty;

  /// No description provided for @snippetsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add a snippet to quickly reuse a block of text — like a signature or a boilerplate reply.'**
  String get snippetsEmptyHint;

  /// No description provided for @snippetsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get snippetsNoMatches;

  /// No description provided for @snippetsNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get snippetsNoMatchesHint;

  /// No description provided for @snippetsEditSnippet.
  ///
  /// In en, this message translates to:
  /// **'Edit Snippet'**
  String get snippetsEditSnippet;

  /// No description provided for @snippetsNewSnippet.
  ///
  /// In en, this message translates to:
  /// **'New Snippet'**
  String get snippetsNewSnippet;

  /// No description provided for @snippetsDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Open the snippet picker while dictating to insert this text.'**
  String get snippetsDialogHint;

  /// No description provided for @snippetsTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get snippetsTitleLabel;

  /// No description provided for @snippetsTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Email signature'**
  String get snippetsTitleHint;

  /// No description provided for @snippetsBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get snippetsBodyLabel;

  /// No description provided for @snippetsBodyHint.
  ///
  /// In en, this message translates to:
  /// **'The text this snippet inserts…'**
  String get snippetsBodyHint;

  /// No description provided for @snippetsKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get snippetsKindLabel;

  /// No description provided for @snippetsKindStatic.
  ///
  /// In en, this message translates to:
  /// **'Static'**
  String get snippetsKindStatic;

  /// No description provided for @snippetsKindInteractive.
  ///
  /// In en, this message translates to:
  /// **'Interactive'**
  String get snippetsKindInteractive;

  /// No description provided for @snippetsFieldsLabel.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get snippetsFieldsLabel;

  /// No description provided for @snippetsFieldsHint.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be guided through each field with its own short recording, in this order.'**
  String get snippetsFieldsHint;

  /// No description provided for @snippetsFieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'Field {number} name'**
  String snippetsFieldNameHint(int number);

  /// No description provided for @snippetsFieldMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move field up'**
  String get snippetsFieldMoveUp;

  /// No description provided for @snippetsFieldMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move field down'**
  String get snippetsFieldMoveDown;

  /// No description provided for @snippetsFieldRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove field'**
  String get snippetsFieldRemove;

  /// No description provided for @snippetsFieldAdd.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get snippetsFieldAdd;

  /// No description provided for @snippetsFieldInsertIntoTemplate.
  ///
  /// In en, this message translates to:
  /// **'Insert into template'**
  String get snippetsFieldInsertIntoTemplate;

  /// No description provided for @snippetsFieldsMinWarning.
  ///
  /// In en, this message translates to:
  /// **'An interactive snippet needs at least {min, plural, one{1 named field} other{{min} named fields}}.'**
  String snippetsFieldsMinWarning(int min);

  /// No description provided for @snippetsTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get snippetsTemplateLabel;

  /// No description provided for @snippetsTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Write your snippet text, then use each field\'s insert button to place it wherever you want.'**
  String get snippetsTemplateHint;

  /// No description provided for @snippetsTemplateFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Write your text here and insert fields using the buttons above.'**
  String get snippetsTemplateFieldHint;

  /// No description provided for @snippetsTemplateMissingFieldsWarning.
  ///
  /// In en, this message translates to:
  /// **'Not all fields appear in the template yet — their dictated text would go unused.'**
  String get snippetsTemplateMissingFieldsWarning;

  /// No description provided for @snippetsInteractiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Interactive'**
  String get snippetsInteractiveBadge;

  /// No description provided for @interactiveSnippetAnnounceLabel.
  ///
  /// In en, this message translates to:
  /// **'Field {index}/{count}: {name} – get ready…'**
  String interactiveSnippetAnnounceLabel(int index, int count, String name);

  /// No description provided for @interactiveSnippetSpeakNowLabel.
  ///
  /// In en, this message translates to:
  /// **'Speak now: {name} ({index}/{count})'**
  String interactiveSnippetSpeakNowLabel(String name, int index, int count);

  /// No description provided for @interactiveSnippetAdvance.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get interactiveSnippetAdvance;

  /// No description provided for @snippetsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Snippet'**
  String get snippetsDeleteTitle;

  /// No description provided for @snippetsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove the snippet \"{title}\"? This cannot be undone.'**
  String snippetsDeleteMessage(String title);

  /// No description provided for @snippetsPickerTriggerLabel.
  ///
  /// In en, this message translates to:
  /// **'Picker trigger word'**
  String get snippetsPickerTriggerLabel;

  /// No description provided for @snippetsPickerTriggerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Speak only this word to open the snippet picker. Leave empty to turn the picker off.'**
  String get snippetsPickerTriggerSubtitle;

  /// No description provided for @snippetsPickerTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. snippet'**
  String get snippetsPickerTriggerHint;

  /// No description provided for @snippetsPickerTriggerEmptyListHint.
  ///
  /// In en, this message translates to:
  /// **'The trigger word is set, but there are no snippets yet — dictating it inserts the word as normal text until you add your first snippet.'**
  String get snippetsPickerTriggerEmptyListHint;

  /// No description provided for @snippetsPickerHotkeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Picker hotkey'**
  String get snippetsPickerHotkeyLabel;

  /// No description provided for @snippetsPickerHotkeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Opens the picker straight away — the second way to the same panel.'**
  String get snippetsPickerHotkeySubtitle;

  /// No description provided for @snippetsPickerHotkeyOff.
  ///
  /// In en, this message translates to:
  /// **'The picker hotkey is switched off.'**
  String get snippetsPickerHotkeyOff;

  /// No description provided for @snippetsPickerHotkeyEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn hotkey on'**
  String get snippetsPickerHotkeyEnable;

  /// No description provided for @snippetsPickerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The snippet picker is not available on this platform yet.'**
  String get snippetsPickerUnavailable;

  /// No description provided for @snippetsPickerSemanticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Snippet picker'**
  String get snippetsPickerSemanticsLabel;

  /// No description provided for @snippetsPickerInsertAction.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get snippetsPickerInsertAction;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Voice to text, instantly.'**
  String get aboutTagline;

  /// No description provided for @aboutWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get aboutWhatsNew;

  /// No description provided for @aboutGitHub.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get aboutGitHub;

  /// No description provided for @aboutReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get aboutReportIssue;

  /// No description provided for @aboutSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support this project'**
  String get aboutSupportTitle;

  /// No description provided for @aboutSupportDescription.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is free and open source under the MIT license. Sponsoring covers real recurring fixed costs (the Apple Developer Program, Microsoft Partner Center, and hosting/domain) that keep it available on every platform.'**
  String get aboutSupportDescription;

  /// No description provided for @aboutGitHubSponsors.
  ///
  /// In en, this message translates to:
  /// **'GitHub Sponsors'**
  String get aboutGitHubSponsors;

  /// No description provided for @aboutKofi.
  ///
  /// In en, this message translates to:
  /// **'Ko-fi'**
  String get aboutKofi;

  /// No description provided for @aboutStarOnGitHub.
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get aboutStarOnGitHub;

  /// No description provided for @aboutSponsorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sponsors'**
  String get aboutSponsorsTitle;

  /// No description provided for @supportPromptRecurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Make it monthly?'**
  String get supportPromptRecurringTitle;

  /// No description provided for @supportPromptRecurringDescription.
  ///
  /// In en, this message translates to:
  /// **'Thank you for supporting WhisPaste before. If you\'d like, you could turn that into a small monthly sponsoring that keeps covering our recurring fixed costs.'**
  String get supportPromptRecurringDescription;

  /// No description provided for @aboutBuiltWith.
  ///
  /// In en, this message translates to:
  /// **'Built with'**
  String get aboutBuiltWith;

  /// No description provided for @aboutFlutterGo.
  ///
  /// In en, this message translates to:
  /// **'Flutter'**
  String get aboutFlutterGo;

  /// No description provided for @aboutFlutterGoDesc.
  ///
  /// In en, this message translates to:
  /// **'Cross-platform UI with Flutter. Local speech recognition via whisper.cpp and Parakeet.'**
  String get aboutFlutterGoDesc;

  /// No description provided for @aboutWhisper.
  ///
  /// In en, this message translates to:
  /// **'whisper.cpp & OpenAI Whisper'**
  String get aboutWhisper;

  /// No description provided for @aboutWhisperDesc.
  ///
  /// In en, this message translates to:
  /// **'Local and cloud speech recognition: fast, accurate, multilingual (99 languages).'**
  String get aboutWhisperDesc;

  /// No description provided for @aboutParakeet.
  ///
  /// In en, this message translates to:
  /// **'NVIDIA Parakeet & sherpa-onnx'**
  String get aboutParakeet;

  /// No description provided for @aboutParakeetDesc.
  ///
  /// In en, this message translates to:
  /// **'Local speech recognition tuned for speed on plain CPU hardware (~25 languages).'**
  String get aboutParakeetDesc;

  /// No description provided for @aboutPrivacyFirst.
  ///
  /// In en, this message translates to:
  /// **'Privacy-first'**
  String get aboutPrivacyFirst;

  /// No description provided for @aboutPrivacyFirstDesc.
  ///
  /// In en, this message translates to:
  /// **'Local speech recognition by default: your voice never leaves your device unless you choose a cloud provider.'**
  String get aboutPrivacyFirstDesc;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Data'**
  String get aboutPrivacy;

  /// No description provided for @aboutPrivacyLocal.
  ///
  /// In en, this message translates to:
  /// **'All transcriptions and history are stored locally on your device, never on external servers.'**
  String get aboutPrivacyLocal;

  /// No description provided for @aboutPrivacyCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud providers (OpenAI, Deepgram) only receive audio when you actively use them. Their privacy policies apply.'**
  String get aboutPrivacyCloud;

  /// No description provided for @aboutPrivacyNoTracking.
  ///
  /// In en, this message translates to:
  /// **'Usage statistics are anonymous and GDPR-compliant (EU server), and can be switched off in Settings → Privacy. No user accounts. Update checks contact GitHub (version + IP only).'**
  String get aboutPrivacyNoTracking;

  /// No description provided for @aboutKeyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get aboutKeyboardShortcuts;

  /// No description provided for @aboutShortcutRecord.
  ///
  /// In en, this message translates to:
  /// **'Start / Stop recording'**
  String get aboutShortcutRecord;

  /// No description provided for @aboutLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get aboutLinks;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutGitHubRepo.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get aboutGitHubRepo;

  /// No description provided for @aboutFollowOnX.
  ///
  /// In en, this message translates to:
  /// **'Follow on X'**
  String get aboutFollowOnX;

  /// No description provided for @aboutMitLicense.
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get aboutMitLicense;

  /// No description provided for @aboutViewOnGitHub.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get aboutViewOnGitHub;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutSystemInfo.
  ///
  /// In en, this message translates to:
  /// **'System Info'**
  String get aboutSystemInfo;

  /// No description provided for @aboutSystemInfoDesc.
  ///
  /// In en, this message translates to:
  /// **'Copy a compact diagnostics snapshot for bug reports.'**
  String get aboutSystemInfoDesc;

  /// No description provided for @aboutCopyDebugInfo.
  ///
  /// In en, this message translates to:
  /// **'Copy Debug Info'**
  String get aboutCopyDebugInfo;

  /// No description provided for @aboutCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get aboutCopied;

  /// No description provided for @aboutMadeWith.
  ///
  /// In en, this message translates to:
  /// **'Made with ♥ by WhisPaste'**
  String get aboutMadeWith;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source under the MIT License'**
  String get aboutOpenSource;

  /// No description provided for @feedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help us improve WhisPaste. Every voice matters.'**
  String get feedbackSubtitle;

  /// No description provided for @feedbackCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'What\'s this about?'**
  String get feedbackCategoryLabel;

  /// No description provided for @feedbackCategoryBug.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get feedbackCategoryBug;

  /// No description provided for @feedbackCategoryFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature Idea'**
  String get feedbackCategoryFeature;

  /// No description provided for @feedbackCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get feedbackCategoryGeneral;

  /// No description provided for @feedbackCategoryAiQuality.
  ///
  /// In en, this message translates to:
  /// **'AI Quality'**
  String get feedbackCategoryAiQuality;

  /// No description provided for @feedbackRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'How are you feeling about WhisPaste?'**
  String get feedbackRatingLabel;

  /// No description provided for @feedbackCommentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tell us more'**
  String get feedbackCommentsLabel;

  /// No description provided for @feedbackPlaceholderBug.
  ///
  /// In en, this message translates to:
  /// **'Describe what happened and what you expected…'**
  String get feedbackPlaceholderBug;

  /// No description provided for @feedbackPlaceholderFeature.
  ///
  /// In en, this message translates to:
  /// **'What would you like to see in WhisPaste?'**
  String get feedbackPlaceholderFeature;

  /// No description provided for @feedbackPlaceholderAi.
  ///
  /// In en, this message translates to:
  /// **'How was the transcription quality?'**
  String get feedbackPlaceholderAi;

  /// No description provided for @feedbackPlaceholderGeneral.
  ///
  /// In en, this message translates to:
  /// **'Share your thoughts…'**
  String get feedbackPlaceholderGeneral;

  /// No description provided for @feedbackContactEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get feedbackContactEmailLabel;

  /// No description provided for @feedbackContactEmailExplanation.
  ///
  /// In en, this message translates to:
  /// **'Only if you\'d like a reply. We\'ll use it solely to follow up on this message, never for marketing, and it\'s deleted after 90 days.'**
  String get feedbackContactEmailExplanation;

  /// No description provided for @feedbackContactEmailPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get feedbackContactEmailPlaceholder;

  /// No description provided for @feedbackContactEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address, or leave it empty.'**
  String get feedbackContactEmailInvalid;

  /// No description provided for @feedbackContactLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Reply in'**
  String get feedbackContactLanguageLabel;

  /// No description provided for @feedbackContactLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Which language should we use if we get back to you?'**
  String get feedbackContactLanguageHint;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackSubmit;

  /// No description provided for @feedbackPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Anonymous by default, only identifiable if you add your email above.'**
  String get feedbackPrivacyNote;

  /// No description provided for @feedbackThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get feedbackThankYou;

  /// No description provided for @feedbackThankYouMessage.
  ///
  /// In en, this message translates to:
  /// **'Your feedback helps us make WhisPaste better\nfor everyone.'**
  String get feedbackThankYouMessage;

  /// No description provided for @feedbackSendAnother.
  ///
  /// In en, this message translates to:
  /// **'Send another'**
  String get feedbackSendAnother;

  /// No description provided for @feedbackRatingFrustrated.
  ///
  /// In en, this message translates to:
  /// **'Frustrated'**
  String get feedbackRatingFrustrated;

  /// No description provided for @feedbackRatingMeh.
  ///
  /// In en, this message translates to:
  /// **'Meh'**
  String get feedbackRatingMeh;

  /// No description provided for @feedbackRatingOkay.
  ///
  /// In en, this message translates to:
  /// **'Okay'**
  String get feedbackRatingOkay;

  /// No description provided for @feedbackRatingHappy.
  ///
  /// In en, this message translates to:
  /// **'Happy'**
  String get feedbackRatingHappy;

  /// No description provided for @feedbackRatingLoveIt.
  ///
  /// In en, this message translates to:
  /// **'Love it!'**
  String get feedbackRatingLoveIt;

  /// No description provided for @feedbackSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get feedbackSubmitting;

  /// No description provided for @feedbackErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You already sent feedback recently. Please try again later.'**
  String get feedbackErrorRateLimited;

  /// No description provided for @feedbackErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server. Please check your internet connection.'**
  String get feedbackErrorNetwork;

  /// No description provided for @feedbackErrorServer.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again later.'**
  String get feedbackErrorServer;

  /// No description provided for @feedbackErrorNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Feedback is not available in this build.'**
  String get feedbackErrorNotConfigured;

  /// No description provided for @statusBarOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On device'**
  String get statusBarOnDevice;

  /// No description provided for @statusBarOverlayFloating.
  ///
  /// In en, this message translates to:
  /// **'Overlay: Floating'**
  String get statusBarOverlayFloating;

  /// No description provided for @statusBarOverlayOff.
  ///
  /// In en, this message translates to:
  /// **'Overlay: Off'**
  String get statusBarOverlayOff;

  /// No description provided for @statusBarAfterCopy.
  ///
  /// In en, this message translates to:
  /// **'After: Copy'**
  String get statusBarAfterCopy;

  /// No description provided for @statusBarAfterPaste.
  ///
  /// In en, this message translates to:
  /// **'After: Paste'**
  String get statusBarAfterPaste;

  /// No description provided for @statusBarAfterBoth.
  ///
  /// In en, this message translates to:
  /// **'After: Copy & Paste'**
  String get statusBarAfterBoth;

  /// No description provided for @statusBarAfterNothing.
  ///
  /// In en, this message translates to:
  /// **'After: Manual'**
  String get statusBarAfterNothing;

  /// No description provided for @sttStatusStandby.
  ///
  /// In en, this message translates to:
  /// **'Standby'**
  String get sttStatusStandby;

  /// No description provided for @sttStatusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get sttStatusStarting;

  /// No description provided for @sttStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get sttStatusReady;

  /// No description provided for @sttStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get sttStatusError;

  /// No description provided for @statusBarSttTooltip.
  ///
  /// In en, this message translates to:
  /// **'Speech service and current status'**
  String get statusBarSttTooltip;

  /// No description provided for @statusBarSttBackendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Transcription backend: {backend}'**
  String statusBarSttBackendTooltip(String backend);

  /// No description provided for @statusBarBackendGpuUtilizationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Real GPU utilization can\'t be measured across platforms without elevated privileges; the percentage shown reflects this process\'s CPU activity instead.'**
  String get statusBarBackendGpuUtilizationUnavailable;

  /// No description provided for @statusBarRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get statusBarRecording;

  /// No description provided for @statusBarTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get statusBarTranscribing;

  /// No description provided for @statusBarRefining.
  ///
  /// In en, this message translates to:
  /// **'Refining…'**
  String get statusBarRefining;

  /// No description provided for @statusBarDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusBarDone;

  /// No description provided for @statusBarHotkeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey: click to configure'**
  String get statusBarHotkeyTooltip;

  /// No description provided for @statusBarAutoPasteOffHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste off, enable in Settings'**
  String get statusBarAutoPasteOffHint;

  /// No description provided for @statusBarAutoPasteOffHintTooltip.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste is currently disabled. Click to open Settings.'**
  String get statusBarAutoPasteOffHintTooltip;

  /// No description provided for @statusBarAutoPasteOffHintDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get statusBarAutoPasteOffHintDismiss;

  /// No description provided for @modifierCtrl.
  ///
  /// In en, this message translates to:
  /// **'Ctrl'**
  String get modifierCtrl;

  /// No description provided for @modifierShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get modifierShift;

  /// No description provided for @modifierAlt.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get modifierAlt;

  /// No description provided for @modifierWin.
  ///
  /// In en, this message translates to:
  /// **'Win'**
  String get modifierWin;

  /// No description provided for @modifierCmd.
  ///
  /// In en, this message translates to:
  /// **'Cmd'**
  String get modifierCmd;

  /// No description provided for @modifierOption.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get modifierOption;

  /// No description provided for @modifierAltGr.
  ///
  /// In en, this message translates to:
  /// **'AltGr'**
  String get modifierAltGr;

  /// No description provided for @shortcutKeySpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get shortcutKeySpace;

  /// No description provided for @shortcutKeyEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get shortcutKeyEnter;

  /// No description provided for @shortcutKeyEscape.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get shortcutKeyEscape;

  /// No description provided for @shortcutKeyBackspace.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get shortcutKeyBackspace;

  /// No description provided for @shortcutKeyTab.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get shortcutKeyTab;

  /// No description provided for @shortcutKeyDelete.
  ///
  /// In en, this message translates to:
  /// **'Del'**
  String get shortcutKeyDelete;

  /// No description provided for @shortcutKeyInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get shortcutKeyInsert;

  /// No description provided for @shortcutKeyHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get shortcutKeyHome;

  /// No description provided for @shortcutKeyEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get shortcutKeyEnd;

  /// No description provided for @shortcutKeyPageUp.
  ///
  /// In en, this message translates to:
  /// **'Page Up'**
  String get shortcutKeyPageUp;

  /// No description provided for @shortcutKeyPageDown.
  ///
  /// In en, this message translates to:
  /// **'Page Down'**
  String get shortcutKeyPageDown;

  /// No description provided for @modelServerReady.
  ///
  /// In en, this message translates to:
  /// **'Speech service ready'**
  String get modelServerReady;

  /// No description provided for @modelServerMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech service not installed'**
  String get modelServerMissing;

  /// No description provided for @modelServerWhisper.
  ///
  /// In en, this message translates to:
  /// **'Local speech service'**
  String get modelServerWhisper;

  /// No description provided for @modelReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get modelReady;

  /// No description provided for @modelDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Model ready to use'**
  String get modelDownloadComplete;

  /// No description provided for @modelUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get modelUse;

  /// No description provided for @modelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get modelDownload;

  /// No description provided for @modelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get modelDownloading;

  /// No description provided for @modelDownloadingEngine.
  ///
  /// In en, this message translates to:
  /// **'Preparing speech service…'**
  String get modelDownloadingEngine;

  /// No description provided for @modelVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get modelVerifying;

  /// No description provided for @modelExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get modelExtracting;

  /// No description provided for @modelDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this model?'**
  String get modelDeleteConfirm;

  /// No description provided for @modelDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The model file will be permanently removed. You can re-download it any time.'**
  String get modelDeleteConfirmMessage;

  /// No description provided for @qualityTierCompactLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick & Compact'**
  String get qualityTierCompactLabel;

  /// No description provided for @qualityTierCompactDesc.
  ///
  /// In en, this message translates to:
  /// **'Fast results, small download. Great for short notes and quick messages.'**
  String get qualityTierCompactDesc;

  /// No description provided for @qualityTierBalancedLabel.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get qualityTierBalancedLabel;

  /// No description provided for @qualityTierBalancedDesc.
  ///
  /// In en, this message translates to:
  /// **'Accurate and reliable for everyday recording. Works on most devices.'**
  String get qualityTierBalancedDesc;

  /// No description provided for @qualityTierPremiumLabel.
  ///
  /// In en, this message translates to:
  /// **'Best Quality'**
  String get qualityTierPremiumLabel;

  /// No description provided for @qualityTierPremiumDesc.
  ///
  /// In en, this message translates to:
  /// **'Top accuracy for longer recordings and complex content. Needs a capable GPU.'**
  String get qualityTierPremiumDesc;

  /// No description provided for @qualityTierRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended for your device'**
  String get qualityTierRecommended;

  /// No description provided for @qualityTierDownloadSize.
  ///
  /// In en, this message translates to:
  /// **'{size} download'**
  String qualityTierDownloadSize(String size);

  /// No description provided for @qualityTierDownloadAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Download model'**
  String get qualityTierDownloadAndContinue;

  /// No description provided for @qualityTierChooseDifferent.
  ///
  /// In en, this message translates to:
  /// **'Choose a different quality level'**
  String get qualityTierChooseDifferent;

  /// No description provided for @qualityTierActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get qualityTierActive;

  /// No description provided for @qualityTierInfoSlow.
  ///
  /// In en, this message translates to:
  /// **'Best quality, takes ~{ratio}x longer to process'**
  String qualityTierInfoSlow(String ratio);

  /// No description provided for @qualityTierInfoSlowerThanCompact.
  ///
  /// In en, this message translates to:
  /// **'Best quality, ~{ratio}x slower than Small'**
  String qualityTierInfoSlowerThanCompact(String ratio);

  /// No description provided for @qualityTierInfoModerate.
  ///
  /// In en, this message translates to:
  /// **'Good balance of speed and quality'**
  String get qualityTierInfoModerate;

  /// No description provided for @qualityTierBenchmarkReRun.
  ///
  /// In en, this message translates to:
  /// **'Re-run benchmark'**
  String get qualityTierBenchmarkReRun;

  /// No description provided for @qualityTierBenchmarkRun.
  ///
  /// In en, this message translates to:
  /// **'Run benchmark'**
  String get qualityTierBenchmarkRun;

  /// No description provided for @qualityTierInfoBenchmarking.
  ///
  /// In en, this message translates to:
  /// **'Testing performance…'**
  String get qualityTierInfoBenchmarking;

  /// No description provided for @qualityTierActionOverride.
  ///
  /// In en, this message translates to:
  /// **'Use anyway'**
  String get qualityTierActionOverride;

  /// No description provided for @qualityTierActionOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Use this quality level despite the warning'**
  String get qualityTierActionOverrideHint;

  /// No description provided for @qualityTierModelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Whisper {modelName} · {size}'**
  String qualityTierModelTooltip(String modelName, String size);

  /// No description provided for @analyticsModelDisplayName.
  ///
  /// In en, this message translates to:
  /// **'{tierLabel} (Whisper {modelLabel})'**
  String analyticsModelDisplayName(String tierLabel, String modelLabel);

  /// No description provided for @settingsQualityBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get settingsQualityBasic;

  /// No description provided for @settingsQualityBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get settingsQualityBalanced;

  /// No description provided for @settingsQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High Quality'**
  String get settingsQualityHigh;

  /// No description provided for @settingsQualityBest.
  ///
  /// In en, this message translates to:
  /// **'Best Quality'**
  String get settingsQualityBest;

  /// No description provided for @settingsQualityMaximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum Accuracy'**
  String get settingsQualityMaximum;

  /// No description provided for @settingsQualityRecommended.
  ///
  /// In en, this message translates to:
  /// **'★ Recommended'**
  String get settingsQualityRecommended;

  /// No description provided for @settingsModelStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Speech model ready'**
  String get settingsModelStatusReady;

  /// No description provided for @settingsModelStatusNeeded.
  ///
  /// In en, this message translates to:
  /// **'Speech model will be downloaded when you start recording'**
  String get settingsModelStatusNeeded;

  /// No description provided for @settingsModelStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading speech model…'**
  String get settingsModelStatusDownloading;

  /// No description provided for @settingsAdvancedModelManagement.
  ///
  /// In en, this message translates to:
  /// **'Advanced model settings'**
  String get settingsAdvancedModelManagement;

  /// No description provided for @infoEngineDownloading.
  ///
  /// In en, this message translates to:
  /// **'Speech service is being prepared. Please wait a moment.'**
  String get infoEngineDownloading;

  /// No description provided for @infoModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Please download a speech model in Settings first.'**
  String get infoModelMissing;

  /// No description provided for @infoPipelineBusy.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is still busy with the previous recording.'**
  String get infoPipelineBusy;

  /// No description provided for @infoSnippetPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trigger word recognized, but you have no snippets yet — the text was inserted as usual.'**
  String get infoSnippetPickerEmpty;

  /// No description provided for @infoSnippetPickerEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Open Snippets'**
  String get infoSnippetPickerEmptyAction;

  /// No description provided for @oomRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording failed: GPU memory issue'**
  String get oomRecoveryTitle;

  /// No description provided for @oomRecoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Choose how to proceed:'**
  String get oomRecoveryMessage;

  /// No description provided for @oomRecoveryTrySmaller.
  ///
  /// In en, this message translates to:
  /// **'Try smaller model'**
  String get oomRecoveryTrySmaller;

  /// No description provided for @oomRecoveryTrySmallerHint.
  ///
  /// In en, this message translates to:
  /// **'Switch to {model} and retry recording'**
  String oomRecoveryTrySmallerHint(String model);

  /// No description provided for @oomRecoverySwitchCloud.
  ///
  /// In en, this message translates to:
  /// **'Switch to Cloud'**
  String get oomRecoverySwitchCloud;

  /// No description provided for @oomRecoverySwitchCloudHint.
  ///
  /// In en, this message translates to:
  /// **'Use cloud speech recognition instead'**
  String get oomRecoverySwitchCloudHint;

  /// No description provided for @oomRecoveryCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get oomRecoveryCancel;

  /// No description provided for @oomRecoveryPermanentTitle.
  ///
  /// In en, this message translates to:
  /// **'Local speech recognition unavailable'**
  String get oomRecoveryPermanentTitle;

  /// No description provided for @oomRecoveryPermanentMessage.
  ///
  /// In en, this message translates to:
  /// **'All local models failed due to GPU memory limits. Please switch to cloud speech recognition in settings.'**
  String get oomRecoveryPermanentMessage;

  /// No description provided for @oomRecoveryPermanentCloud.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get oomRecoveryPermanentCloud;

  /// No description provided for @oomRecoveryDowngrading.
  ///
  /// In en, this message translates to:
  /// **'Switching to {model}…'**
  String oomRecoveryDowngrading(String model);

  /// No description provided for @oomRecoverySwitchingCloud.
  ///
  /// In en, this message translates to:
  /// **'Switching to cloud speech recognition…'**
  String get oomRecoverySwitchingCloud;

  /// No description provided for @oomRecoveryAttemptFailed.
  ///
  /// In en, this message translates to:
  /// **'Model {model} also failed. Trying next option…'**
  String oomRecoveryAttemptFailed(String model);

  /// No description provided for @infoSttCudaOomFallbackModel.
  ///
  /// In en, this message translates to:
  /// **'Quality reduced: your GPU ran out of memory. Switched to a lighter model.'**
  String get infoSttCudaOomFallbackModel;

  /// No description provided for @infoSttCudaOomFallbackCpu.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Switched to CPU mode for reliability.'**
  String get infoSttCudaOomFallbackCpu;

  /// No description provided for @errorSttServerConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Speech service stopped unexpectedly. Please try again.'**
  String get errorSttServerConnectionLost;

  /// No description provided for @errorSttCudaOom.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Quality was reduced so the next try should work.'**
  String get errorSttCudaOom;

  /// No description provided for @errorCloudAuth.
  ///
  /// In en, this message translates to:
  /// **'Cloud API key is missing or invalid. Check it in Settings → Speech Recognition.'**
  String get errorCloudAuth;

  /// No description provided for @errorCloudQuota.
  ///
  /// In en, this message translates to:
  /// **'Cloud provider rate limit reached. Please wait a moment and try again.'**
  String get errorCloudQuota;

  /// No description provided for @errorOnboardingNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Please complete the setup wizard first.'**
  String get errorOnboardingNotCompleted;

  /// No description provided for @errorSttModelNotFound.
  ///
  /// In en, this message translates to:
  /// **'Speech model not found. Please download it in Settings.'**
  String get errorSttModelNotFound;

  /// No description provided for @errorSttModelUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown speech model. Please select a valid model in Settings.'**
  String get errorSttModelUnknown;

  /// No description provided for @errorRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start recording, please try again'**
  String get errorRecordingFailed;

  /// No description provided for @errorNoAudioRecorded.
  ///
  /// In en, this message translates to:
  /// **'No audio recorded, please try again'**
  String get errorNoAudioRecorded;

  /// No description provided for @errorTranscriptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Transcription returned empty text, please try again'**
  String get errorTranscriptionEmpty;

  /// No description provided for @errorSttServerFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech service failed to start'**
  String get errorSttServerFailed;

  /// No description provided for @errorSttModelIncompatibleRuntime.
  ///
  /// In en, this message translates to:
  /// **'Speech model is incompatible with the installed runtime. Please re-download the speech model in Settings.'**
  String get errorSttModelIncompatibleRuntime;

  /// No description provided for @errorSttModelCorruptedRedownloading.
  ///
  /// In en, this message translates to:
  /// **'Speech model appears corrupted. Downloading a fresh copy automatically.'**
  String get errorSttModelCorruptedRedownloading;

  /// No description provided for @errorSttDllMissing.
  ///
  /// In en, this message translates to:
  /// **'A required system component is missing. Retrying with CPU mode.'**
  String get errorSttDllMissing;

  /// No description provided for @errorSttGpuFatal.
  ///
  /// In en, this message translates to:
  /// **'GPU acceleration failed. Retrying with CPU mode.'**
  String get errorSttGpuFatal;

  /// No description provided for @errorSttHeapCorruption.
  ///
  /// In en, this message translates to:
  /// **'A memory error occurred. Retrying with CPU mode.'**
  String get errorSttHeapCorruption;

  /// No description provided for @errorSttCpuFallbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech service failed on both GPU and CPU. Please restart the app or re-download the model.'**
  String get errorSttCpuFallbackFailed;

  /// No description provided for @errorPipelineTimeout.
  ///
  /// In en, this message translates to:
  /// **'Recording took too long. Please try a shorter recording.'**
  String get errorPipelineTimeout;

  /// No description provided for @errorWavFileNotCreated.
  ///
  /// In en, this message translates to:
  /// **'Could not save the audio file. Please try again.'**
  String get errorWavFileNotCreated;

  /// No description provided for @errorWavFileEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audio was captured. Please check your microphone.'**
  String get errorWavFileEmpty;

  /// No description provided for @errorSttStartTimeout.
  ///
  /// In en, this message translates to:
  /// **'Speech service is still starting. Please try again in a moment.'**
  String get errorSttStartTimeout;

  /// No description provided for @errorTranscriptionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Transcription took too long. Please try a shorter recording.'**
  String get errorTranscriptionTimeout;

  /// No description provided for @errorMicPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is needed. Please allow it in your system settings.'**
  String get errorMicPermissionDenied;

  /// No description provided for @errorRecordingStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start recording. Please try again.'**
  String get errorRecordingStartFailed;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Please check your internet connection.'**
  String get modelDownloadFailed;

  /// No description provided for @statusSttLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading model…'**
  String get statusSttLoading;

  /// No description provided for @statusSttReady.
  ///
  /// In en, this message translates to:
  /// **'Model ready'**
  String get statusSttReady;

  /// No description provided for @historyDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get historyDuplicate;

  /// No description provided for @historyDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Entry duplicated'**
  String get historyDuplicated;

  /// No description provided for @historyViewRaw.
  ///
  /// In en, this message translates to:
  /// **'Raw'**
  String get historyViewRaw;

  /// Toggle label for the Smart Mode edited version of a history entry's transcript (ticket 05).
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get historyViewEdited;

  /// No description provided for @historyApplySmartModePreset.
  ///
  /// In en, this message translates to:
  /// **'Apply Smart Mode preset'**
  String get historyApplySmartModePreset;

  /// No description provided for @historySmartModeApplied.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode applied'**
  String get historySmartModeApplied;

  /// No description provided for @historySmartModeFailedModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode model not downloaded'**
  String get historySmartModeFailedModelMissing;

  /// No description provided for @historySmartModeFailedTimeout.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode timed out'**
  String get historySmartModeFailedTimeout;

  /// No description provided for @historySmartModeFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode failed — please try again'**
  String get historySmartModeFailedGeneric;

  /// No description provided for @historySmartModeSelectTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select target language'**
  String get historySmartModeSelectTargetLanguage;

  /// No description provided for @historyAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add annotation'**
  String get historyAddNote;

  /// Accessibility label for the annotation edit text field in the history detail panel.
  ///
  /// In en, this message translates to:
  /// **'Edit annotation'**
  String get historyEditNote;

  /// No description provided for @historyNotes.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get historyNotes;

  /// No description provided for @historyNotePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write an annotation…'**
  String get historyNotePlaceholder;

  /// One-time discoverability hint next to the annotation input, teaching the voice-note prefixes parsed by parseVoiceAction.
  ///
  /// In en, this message translates to:
  /// **'Tip: say “tag: name” or “correct: text” while recording.'**
  String get historyVoiceNoteHint;

  /// No description provided for @historyNoteAdded.
  ///
  /// In en, this message translates to:
  /// **'Annotation added'**
  String get historyNoteAdded;

  /// No description provided for @historyNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Annotation deleted'**
  String get historyNoteDeleted;

  /// No description provided for @historyCopiedAsMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copied as Markdown'**
  String get historyCopiedAsMarkdown;

  /// No description provided for @historyAddTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag…'**
  String get historyAddTag;

  /// No description provided for @historySearchTags.
  ///
  /// In en, this message translates to:
  /// **'Search or create…'**
  String get historySearchTags;

  /// No description provided for @historyNoteEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get historyNoteEdited;

  /// No description provided for @historyTagAdded.
  ///
  /// In en, this message translates to:
  /// **'Tag added'**
  String get historyTagAdded;

  /// No description provided for @historyTagRemoved.
  ///
  /// In en, this message translates to:
  /// **'Tag removed'**
  String get historyTagRemoved;

  /// No description provided for @historyCreateTag.
  ///
  /// In en, this message translates to:
  /// **'Create \"{tag}\"'**
  String historyCreateTag(Object tag);

  /// No description provided for @historyManageTags.
  ///
  /// In en, this message translates to:
  /// **'Manage tags'**
  String get historyManageTags;

  /// No description provided for @tagManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Tags'**
  String get tagManageTitle;

  /// No description provided for @tagManageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags created yet.'**
  String get tagManageEmpty;

  /// No description provided for @tagUsageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{unused} =1{1 entry} other{{count} entries}}'**
  String tagUsageCount(int count);

  /// No description provided for @tagOverflowMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more tag} other{{count} more tags}}'**
  String tagOverflowMore(int count);

  /// No description provided for @tagDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete tag?'**
  String get tagDeleteConfirmTitle;

  /// No description provided for @tagDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The tag \"{name}\" is used in {count, plural, =1{1 entry} other{{count} entries}}. It will be removed from all of them.'**
  String tagDeleteConfirmMessage(String name, int count);

  /// No description provided for @tagDeleted.
  ///
  /// In en, this message translates to:
  /// **'Tag \"{name}\" deleted'**
  String tagDeleted(String name);

  /// No description provided for @tagDeleteUnusedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete unused tags?'**
  String get tagDeleteUnusedTitle;

  /// No description provided for @tagDeleteUnusedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unused tag} other{{count} unused tags}} will be permanently deleted.'**
  String tagDeleteUnusedMessage(int count);

  /// No description provided for @tagDeleteUnusedAction.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} unused'**
  String tagDeleteUnusedAction(int count);

  /// No description provided for @tagDeletedUnused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unused tag} other{{count} unused tags}} deleted'**
  String tagDeletedUnused(int count);

  /// No description provided for @historyEditTranscript.
  ///
  /// In en, this message translates to:
  /// **'Edit transcript'**
  String get historyEditTranscript;

  /// No description provided for @historyTranscriptSaved.
  ///
  /// In en, this message translates to:
  /// **'Transcript saved'**
  String get historyTranscriptSaved;

  /// No description provided for @historySaveTranscript.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get historySaveTranscript;

  /// No description provided for @historyShortcutHelp.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get historyShortcutHelp;

  /// No description provided for @historyShortcutGeneral.
  ///
  /// In en, this message translates to:
  /// **'GENERAL'**
  String get historyShortcutGeneral;

  /// No description provided for @historyShortcutTags.
  ///
  /// In en, this message translates to:
  /// **'Focus tag input'**
  String get historyShortcutTags;

  /// No description provided for @historyShortcutNotes.
  ///
  /// In en, this message translates to:
  /// **'Add an annotation'**
  String get historyShortcutNotes;

  /// No description provided for @historyShortcutPin.
  ///
  /// In en, this message translates to:
  /// **'Favorite / unfavorite'**
  String get historyShortcutPin;

  /// No description provided for @historyShortcutClose.
  ///
  /// In en, this message translates to:
  /// **'Save & close'**
  String get historyShortcutClose;

  /// No description provided for @historyShortcutEditing.
  ///
  /// In en, this message translates to:
  /// **'EDITING'**
  String get historyShortcutEditing;

  /// No description provided for @historyShortcutToggleEdit.
  ///
  /// In en, this message translates to:
  /// **'Toggle edit mode'**
  String get historyShortcutToggleEdit;

  /// No description provided for @historyShortcutSave.
  ///
  /// In en, this message translates to:
  /// **'Save transcript'**
  String get historyShortcutSave;

  /// No description provided for @historyShortcutBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get historyShortcutBold;

  /// No description provided for @historyShortcutItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get historyShortcutItalic;

  /// No description provided for @historyShortcutCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get historyShortcutCopy;

  /// No description provided for @historyShortcutEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit title'**
  String get historyShortcutEditTitle;

  /// No description provided for @historyEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit title'**
  String get historyEditTitle;

  /// No description provided for @historyTitlePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a title…'**
  String get historyTitlePlaceholder;

  /// No description provided for @historyTitleSaved.
  ///
  /// In en, this message translates to:
  /// **'Title saved'**
  String get historyTitleSaved;

  /// No description provided for @historySearchHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Tips'**
  String get historySearchHelpTitle;

  /// No description provided for @historySearchHelpTags.
  ///
  /// In en, this message translates to:
  /// **'Type # to filter by tags'**
  String get historySearchHelpTags;

  /// No description provided for @historySearchHelpLang.
  ///
  /// In en, this message translates to:
  /// **'Type lang: to filter by language'**
  String get historySearchHelpLang;

  /// No description provided for @historySearchHelpFreeText.
  ///
  /// In en, this message translates to:
  /// **'Or just type any keyword'**
  String get historySearchHelpFreeText;

  /// No description provided for @historySearchQuickTags.
  ///
  /// In en, this message translates to:
  /// **'Popular tags'**
  String get historySearchQuickTags;

  /// No description provided for @historyRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get historyRecentSearches;

  /// Accessibility label for the button that removes a single entry from the recent searches list.
  ///
  /// In en, this message translates to:
  /// **'Remove recent search'**
  String get historyRemoveRecentSearch;

  /// Accessibility label for the button that removes an active filter chip from the history search bar.
  ///
  /// In en, this message translates to:
  /// **'Remove filter'**
  String get historyRemoveFilter;

  /// No description provided for @historyQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick filters'**
  String get historyQuickActions;

  /// No description provided for @historyQuickActionAllLangs.
  ///
  /// In en, this message translates to:
  /// **'All languages'**
  String get historyQuickActionAllLangs;

  /// No description provided for @historyQuickActionFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites only'**
  String get historyQuickActionFavorites;

  /// No description provided for @historySortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get historySortNewest;

  /// No description provided for @historySortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get historySortOldest;

  /// No description provided for @historySortLongest.
  ///
  /// In en, this message translates to:
  /// **'Longest first'**
  String get historySortLongest;

  /// No description provided for @historySearchActiveTag.
  ///
  /// In en, this message translates to:
  /// **'#{tag}'**
  String historySearchActiveTag(String tag);

  /// No description provided for @historySearchActiveLang.
  ///
  /// In en, this message translates to:
  /// **'lang:{code}'**
  String historySearchActiveLang(String code);

  /// No description provided for @historySearchSuggestTag.
  ///
  /// In en, this message translates to:
  /// **'Filter by tag'**
  String get historySearchSuggestTag;

  /// No description provided for @historySearchSuggestLang.
  ///
  /// In en, this message translates to:
  /// **'Filter by language'**
  String get historySearchSuggestLang;

  /// No description provided for @settingsKeyboardShortcut.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcut'**
  String get settingsKeyboardShortcut;

  /// No description provided for @settingsKeyboardShortcutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey to start and stop recording'**
  String get settingsKeyboardShortcutSubtitle;

  /// No description provided for @settingsHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Global Hotkey'**
  String get settingsHotkeyEnabled;

  /// No description provided for @settingsCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current Hotkey'**
  String get settingsCurrentHotkey;

  /// No description provided for @settingsChangeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsChangeHotkey;

  /// No description provided for @settingsHotkeyRecorderTitle.
  ///
  /// In en, this message translates to:
  /// **'Record New Hotkey'**
  String get settingsHotkeyRecorderTitle;

  /// No description provided for @settingsHotkeyRecorderHint.
  ///
  /// In en, this message translates to:
  /// **'Press the key combination you want to use…'**
  String get settingsHotkeyRecorderHint;

  /// No description provided for @settingsHotkeyRecorderModifierHint.
  ///
  /// In en, this message translates to:
  /// **'Any modifier combination works: e.g. Alt+Space, Ctrl+Alt+V, or Ctrl+Alt+Shift+R'**
  String get settingsHotkeyRecorderModifierHint;

  /// No description provided for @settingsHotkeyRecorderCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsHotkeyRecorderCancel;

  /// No description provided for @settingsHotkeyRecorderSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsHotkeyRecorderSave;

  /// No description provided for @settingsHotkeyRecorderClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsHotkeyRecorderClear;

  /// No description provided for @settingsHotkeyRecorderInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'This key can\'t be used as a hotkey. Try a letter, digit, function key (F1-F12), or an arrow key.'**
  String get settingsHotkeyRecorderInvalidKey;

  /// No description provided for @settingsHotkeyActionRecording.
  ///
  /// In en, this message translates to:
  /// **'Start/stop recording'**
  String get settingsHotkeyActionRecording;

  /// No description provided for @settingsHotkeyActionQuickNote.
  ///
  /// In en, this message translates to:
  /// **'Quick note'**
  String get settingsHotkeyActionQuickNote;

  /// No description provided for @settingsQuickNoteHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Quick-note hotkey'**
  String get settingsQuickNoteHotkeyEnabled;

  /// No description provided for @settingsQuickNoteHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Dictated text is appended to the note marked as your quick note. You pick that note in the Notes area.'**
  String get settingsQuickNoteHotkeyHint;

  /// No description provided for @settingsQuickNoteCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Combination'**
  String get settingsQuickNoteCurrentHotkey;

  /// No description provided for @settingsQuickNoteHotkeyCollision.
  ///
  /// In en, this message translates to:
  /// **'This combination is already used for \"{action}\". Pick a different one.'**
  String settingsQuickNoteHotkeyCollision(String action);

  /// No description provided for @settingsQuickNoteHotkeyInactive.
  ///
  /// In en, this message translates to:
  /// **'This combination could not be registered — the quick-note hotkey is currently not active. Pick a different combination.'**
  String get settingsQuickNoteHotkeyInactive;

  /// No description provided for @settingsHotkeyActionSnippetPicker.
  ///
  /// In en, this message translates to:
  /// **'Snippet picker'**
  String get settingsHotkeyActionSnippetPicker;

  /// No description provided for @settingsSnippetPickerHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Snippet-picker hotkey'**
  String get settingsSnippetPickerHotkeyEnabled;

  /// No description provided for @settingsSnippetPickerHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Opens the snippet picker straight away — no recording, and without the spoken trigger word.'**
  String get settingsSnippetPickerHotkeyHint;

  /// No description provided for @settingsSnippetPickerCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Combination'**
  String get settingsSnippetPickerCurrentHotkey;

  /// No description provided for @settingsSnippetPickerHotkeyCollision.
  ///
  /// In en, this message translates to:
  /// **'This combination is already used for \"{action}\". Pick a different one.'**
  String settingsSnippetPickerHotkeyCollision(String action);

  /// No description provided for @settingsSnippetPickerHotkeyInactive.
  ///
  /// In en, this message translates to:
  /// **'This combination could not be registered — the snippet-picker hotkey is currently not active. Pick a different combination.'**
  String get settingsSnippetPickerHotkeyInactive;

  /// No description provided for @settingsMaxRecordDuration.
  ///
  /// In en, this message translates to:
  /// **'Max Recording Duration'**
  String get settingsMaxRecordDuration;

  /// No description provided for @settingsMaxRecordDurationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic safety stop after this time'**
  String get settingsMaxRecordDurationSubtitle;

  /// No description provided for @settingsMaxRecordDurationUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settingsMaxRecordDurationUnlimited;

  /// No description provided for @settingsCloseToTray.
  ///
  /// In en, this message translates to:
  /// **'Close to Tray'**
  String get settingsCloseToTray;

  /// No description provided for @settingsCloseToTraySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep running in the system tray when closing the window'**
  String get settingsCloseToTraySubtitle;

  /// No description provided for @settingsSidePanelEnabled.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Quick-Paste Panel'**
  String get settingsSidePanelEnabled;

  /// No description provided for @settingsSidePanelEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slide-out panel on hover at the left screen edge for transcriptions, snippets and clipboard history'**
  String get settingsSidePanelEnabledSubtitle;

  /// No description provided for @settingsErrorReporting.
  ///
  /// In en, this message translates to:
  /// **'Error Reporting'**
  String get settingsErrorReporting;

  /// No description provided for @settingsErrorReportingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help improve WhisPaste by sending anonymous crash reports'**
  String get settingsErrorReportingSubtitle;

  /// No description provided for @settingsAutoPasteDelay.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste Delay'**
  String get settingsAutoPasteDelay;

  /// No description provided for @settingsAutoPasteDelaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wait time before pasting into the active window'**
  String get settingsAutoPasteDelaySubtitle;

  /// No description provided for @settingsAutoPasteBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste Blocklist'**
  String get settingsAutoPasteBlocklist;

  /// No description provided for @settingsAutoPasteBlocklistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated app identifiers where auto-paste is disabled'**
  String get settingsAutoPasteBlocklistSubtitle;

  /// No description provided for @settingsAutoPasteBlocklistPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. com.apple.Terminal, com.1password'**
  String get settingsAutoPasteBlocklistPlaceholder;

  /// No description provided for @settingsCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get settingsCheckUpdates;

  /// No description provided for @settingsCheckUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically check for new versions on startup'**
  String get settingsCheckUpdatesSubtitle;

  /// No description provided for @settingsCheckForUpdatesNow.
  ///
  /// In en, this message translates to:
  /// **'Check for updates now'**
  String get settingsCheckForUpdatesNow;

  /// No description provided for @settingsUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdates;

  /// No description provided for @settingsUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Release channel and update checks'**
  String get settingsUpdatesSubtitle;

  /// No description provided for @settingsBetaUpdates.
  ///
  /// In en, this message translates to:
  /// **'Beta Updates'**
  String get settingsBetaUpdates;

  /// No description provided for @settingsBetaUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get pre-release versions that are less tested.'**
  String get settingsBetaUpdatesSubtitle;

  /// No description provided for @settingsStableRevertHintMessage.
  ///
  /// In en, this message translates to:
  /// **'Switching back to Stable automatically isn\'t possible here. You already have a newer beta version installed.'**
  String get settingsStableRevertHintMessage;

  /// No description provided for @settingsStableRevertHintLink.
  ///
  /// In en, this message translates to:
  /// **'Manually download stable {stableVersion}'**
  String settingsStableRevertHintLink(String stableVersion);

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Help make WhisPaste better'**
  String get onboardingPrivacyTitle;

  /// No description provided for @onboardingPrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Audio and text stay local. Only anonymous usage statistics go to a self-hosted server in the EU — GDPR-compliant.'**
  String get onboardingPrivacyHint;

  /// No description provided for @onboardingPrivacyToggle.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous usage statistics'**
  String get onboardingPrivacyToggle;

  /// No description provided for @onboardingPrivacyToggleHint.
  ///
  /// In en, this message translates to:
  /// **'On by default, switch off anytime'**
  String get onboardingPrivacyToggleHint;

  /// No description provided for @onboardingPrivacyCrashToggle.
  ///
  /// In en, this message translates to:
  /// **'Send anonymous crash reports'**
  String get onboardingPrivacyCrashToggle;

  /// No description provided for @onboardingPrivacyCrashToggleHint.
  ///
  /// In en, this message translates to:
  /// **'Helps fix bugs, on by default, switch off anytime'**
  String get onboardingPrivacyCrashToggleHint;

  /// No description provided for @onboardingStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepOf(int current, int total);

  /// No description provided for @onboardingAppearancePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get onboardingAppearancePageTitle;

  /// No description provided for @onboardingAppearancePageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How the app starts, and how the recording overlay looks.'**
  String get onboardingAppearancePageSubtitle;

  /// No description provided for @onboardingBeat1Title.
  ///
  /// In en, this message translates to:
  /// **'Press the hotkey, speak, done'**
  String get onboardingBeat1Title;

  /// No description provided for @onboardingBeat1Caption.
  ///
  /// In en, this message translates to:
  /// **'Recording starts instantly — your words land as text right at your cursor.'**
  String get onboardingBeat1Caption;

  /// No description provided for @onboardingBeat2Title.
  ///
  /// In en, this message translates to:
  /// **'Runs locally, on your hardware'**
  String get onboardingBeat2Title;

  /// No description provided for @onboardingBeat2Caption.
  ///
  /// In en, this message translates to:
  /// **'Transcription happens on your device — no internet needed.'**
  String get onboardingBeat2Caption;

  /// No description provided for @onboardingBeat3Title.
  ///
  /// In en, this message translates to:
  /// **'Everywhere you type'**
  String get onboardingBeat3Title;

  /// No description provided for @onboardingBeat3Caption.
  ///
  /// In en, this message translates to:
  /// **'Browser, mail, editor — WhisPaste works system-wide.'**
  String get onboardingBeat3Caption;

  /// No description provided for @onboardingMicChipReady.
  ///
  /// In en, this message translates to:
  /// **'Microphone ready'**
  String get onboardingMicChipReady;

  /// No description provided for @onboardingMicChipPending.
  ///
  /// In en, this message translates to:
  /// **'Microphone access pending'**
  String get onboardingMicChipPending;

  /// No description provided for @onboardingMicChipAction.
  ///
  /// In en, this message translates to:
  /// **'Microphone: action needed'**
  String get onboardingMicChipAction;

  /// No description provided for @onboardingModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up speech recognition'**
  String get onboardingModelTitle;

  /// No description provided for @onboardingModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download the speech model to record offline. Your voice never leaves your device.'**
  String get onboardingModelSubtitle;

  /// No description provided for @onboardingModelRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get onboardingModelRecommended;

  /// No description provided for @onboardingModelChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can adjust quality later in Settings'**
  String get onboardingModelChangeLater;

  /// No description provided for @onboardingModelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get onboardingModelDownloading;

  /// No description provided for @onboardingModelReady.
  ///
  /// In en, this message translates to:
  /// **'Model ready'**
  String get onboardingModelReady;

  /// No description provided for @onboardingModelGpuCpuFallback.
  ///
  /// In en, this message translates to:
  /// **'Optimised GPU acceleration unavailable, app will use the CPU'**
  String get onboardingModelGpuCpuFallback;

  /// No description provided for @onboardingModelEngineParakeetLabel.
  ///
  /// In en, this message translates to:
  /// **'Fast & European'**
  String get onboardingModelEngineParakeetLabel;

  /// No description provided for @onboardingModelEngineParakeetDesc.
  ///
  /// In en, this message translates to:
  /// **'The quickest way to text in about 25 European languages, including German. Runs well on any hardware, GPU or not.'**
  String get onboardingModelEngineParakeetDesc;

  /// No description provided for @onboardingModelEngineWhisperLabel.
  ///
  /// In en, this message translates to:
  /// **'All 99 Languages'**
  String get onboardingModelEngineWhisperLabel;

  /// No description provided for @onboardingModelEngineWhisperDesc.
  ///
  /// In en, this message translates to:
  /// **'Broadest language coverage, plus custom vocabulary and punctuation tuning for names, acronyms, and jargon.'**
  String get onboardingModelEngineWhisperDesc;

  /// No description provided for @onboardingModelEngineUnsupportedLanguage.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t support your selected language yet'**
  String get onboardingModelEngineUnsupportedLanguage;

  /// No description provided for @onboardingTestRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Give it a try'**
  String get onboardingTestRecordingTitle;

  /// No description provided for @onboardingTestRecordingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Press the button below and say a sentence. The text lands in the test field. Your hotkey works too.'**
  String get onboardingTestRecordingSubtitle;

  /// No description provided for @onboardingTestRecordingHotkeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Your hotkey'**
  String get onboardingTestRecordingHotkeyLabel;

  /// No description provided for @onboardingTestRecordingStartCta.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get onboardingTestRecordingStartCta;

  /// No description provided for @onboardingTestRecordingStopCta.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get onboardingTestRecordingStopCta;

  /// No description provided for @onboardingTestRecordingCompletionHint.
  ///
  /// In en, this message translates to:
  /// **'Try a recording first to continue.'**
  String get onboardingTestRecordingCompletionHint;

  /// No description provided for @onboardingTestRecordingMicBypassCta.
  ///
  /// In en, this message translates to:
  /// **'Continue without a microphone'**
  String get onboardingTestRecordingMicBypassCta;

  /// No description provided for @onboardingTestRecordingMicBypassHint.
  ///
  /// In en, this message translates to:
  /// **'Without a working microphone, WhisPaste can\'t start a recording yet. You can catch up anytime via the microphone status on this page or in Settings.'**
  String get onboardingTestRecordingMicBypassHint;

  /// No description provided for @onboardingTestRecordingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your spoken text will appear here …'**
  String get onboardingTestRecordingPlaceholder;

  /// No description provided for @onboardingTestRecordingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Recording: just start talking. Press again to stop.'**
  String get onboardingTestRecordingInProgress;

  /// No description provided for @onboardingTestRecordingDoneMessage.
  ///
  /// In en, this message translates to:
  /// **'That\'s it! This is exactly how it works in every app.'**
  String get onboardingTestRecordingDoneMessage;

  /// No description provided for @onboardingTestRecordingReassurance.
  ///
  /// In en, this message translates to:
  /// **'Just a test, the text stays in this field.'**
  String get onboardingTestRecordingReassurance;

  /// No description provided for @onboardingTestRecordingReassuranceWithDuration.
  ///
  /// In en, this message translates to:
  /// **'Just a test, the text stays in this field — recordings stop automatically after {seconds} seconds, adjustable under Settings → {section}.'**
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  );

  /// No description provided for @onboardingReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re All Set!'**
  String get onboardingReadyTitle;

  /// No description provided for @onboardingReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Here\'s how to use WhisPaste'**
  String get onboardingReadySubtitle;

  /// No description provided for @onboardingReadyStep1.
  ///
  /// In en, this message translates to:
  /// **'Press the hotkey to start recording'**
  String get onboardingReadyStep1;

  /// No description provided for @onboardingReadyStep2.
  ///
  /// In en, this message translates to:
  /// **'Press again to stop and transcribe'**
  String get onboardingReadyStep2;

  /// No description provided for @onboardingReadyStep3AutoPaste.
  ///
  /// In en, this message translates to:
  /// **'Text flows straight into the active app'**
  String get onboardingReadyStep3AutoPaste;

  /// No description provided for @onboardingReadyStep3CopyOnly.
  ///
  /// In en, this message translates to:
  /// **'Text is in your clipboard, press ⌘V / Ctrl+V to paste'**
  String get onboardingReadyStep3CopyOnly;

  /// No description provided for @onboardingReadyContextCarryoverHint.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste carries context from your previous recording forward for up to ten minutes. Before a quick switch to an unrelated topic, a short pause keeps the next result on track.'**
  String get onboardingReadyContextCarryoverHint;

  /// No description provided for @onboardingReadyAutostartToggle.
  ///
  /// In en, this message translates to:
  /// **'Launch WhisPaste at login'**
  String get onboardingReadyAutostartToggle;

  /// No description provided for @onboardingReadyAutostartToggleHint.
  ///
  /// In en, this message translates to:
  /// **'Off by default, turn on anytime in Settings'**
  String get onboardingReadyAutostartToggleHint;

  /// No description provided for @onboardingTriggerTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to start recording?'**
  String get onboardingTriggerTitle;

  /// No description provided for @onboardingTriggerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set your hotkey and choose how it starts a recording.'**
  String get onboardingTriggerSubtitle;

  /// No description provided for @onboardingTriggerCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
  String get onboardingTriggerCurrentHotkey;

  /// No description provided for @onboardingTriggerHotkeyConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Hotkey already in use'**
  String get onboardingTriggerHotkeyConflictTitle;

  /// No description provided for @onboardingTriggerHotkeyConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Your hotkey seems to be in use by another app. Record a new combination below to continue.'**
  String get onboardingTriggerHotkeyConflictBody;

  /// No description provided for @onboardingReadyHotkeyConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Go back to the hotkey page and record a new combination there.'**
  String get onboardingReadyHotkeyConflictBody;

  /// No description provided for @onboardingTriggerModeHoldHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the hotkey and speak, release to finish'**
  String get onboardingTriggerModeHoldHint;

  /// No description provided for @onboardingTriggerModeToggleHint.
  ///
  /// In en, this message translates to:
  /// **'Press once to start, press again to finish'**
  String get onboardingTriggerModeToggleHint;

  /// No description provided for @onboardingTriggerSystemWideHint.
  ///
  /// In en, this message translates to:
  /// **'Works system-wide — not just inside WhisPaste.'**
  String get onboardingTriggerSystemWideHint;

  /// No description provided for @onboardingStartUsing.
  ///
  /// In en, this message translates to:
  /// **'Let\'s go'**
  String get onboardingStartUsing;

  /// No description provided for @onboardingReviewExit.
  ///
  /// In en, this message translates to:
  /// **'Close introduction'**
  String get onboardingReviewExit;

  /// No description provided for @onboardingReviewDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get onboardingReviewDone;

  /// No description provided for @onboardingReviewEntry.
  ///
  /// In en, this message translates to:
  /// **'Introduction'**
  String get onboardingReviewEntry;

  /// No description provided for @onboardingReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Go through the five setup steps again whenever you like — nothing changes unless you change it.'**
  String get onboardingReviewSubtitle;

  /// No description provided for @onboardingReviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Review the introduction'**
  String get onboardingReviewLabel;

  /// No description provided for @onboardingReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get onboardingReviewAction;

  /// No description provided for @onboardingRevisionNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste was updated — your settings are unchanged.'**
  String get onboardingRevisionNoticeTitle;

  /// No description provided for @onboardingRevisionExit.
  ///
  /// In en, this message translates to:
  /// **'Leave introduction'**
  String get onboardingRevisionExit;

  /// No description provided for @onboardingRevisionExitConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave the introduction?'**
  String get onboardingRevisionExitConfirmTitle;

  /// No description provided for @onboardingRevisionExitConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This update walkthrough is shown only once, so the steps you skip now won\'t be set up for you. You can reopen the same steps any time under Settings → Introduction, and every setting they cover also has its own place in Settings. What you already configured stays untouched.'**
  String get onboardingRevisionExitConfirmBody;

  /// No description provided for @onboardingRevisionExitConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get onboardingRevisionExitConfirmAction;

  /// No description provided for @overlayRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get overlayRecording;

  /// No description provided for @overlayTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get overlayTranscribing;

  /// No description provided for @overlayRefining.
  ///
  /// In en, this message translates to:
  /// **'Refining…'**
  String get overlayRefining;

  /// No description provided for @overlayDone.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get overlayDone;

  /// No description provided for @overlayDonePasted.
  ///
  /// In en, this message translates to:
  /// **'Pasted'**
  String get overlayDonePasted;

  /// No description provided for @overlayDoneBoth.
  ///
  /// In en, this message translates to:
  /// **'Copied & Pasted'**
  String get overlayDoneBoth;

  /// No description provided for @overlayDoneReady.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get overlayDoneReady;

  /// No description provided for @overlayError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get overlayError;

  /// No description provided for @overlayCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get overlayCancel;

  /// No description provided for @overlayPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get overlayPause;

  /// No description provided for @overlayResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get overlayResume;

  /// No description provided for @overlayStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get overlayStop;

  /// No description provided for @overlayKeyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Press {hotkey} to stop'**
  String overlayKeyboardHint(String hotkey);

  /// No description provided for @overlayKeyboardHintNextFieldEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter or {hotkey}: next field · Esc: cancel'**
  String overlayKeyboardHintNextFieldEnter(String hotkey);

  /// No description provided for @overlayKeyboardHintNextFieldEnterOnly.
  ///
  /// In en, this message translates to:
  /// **'Enter: next field · Esc: cancel'**
  String get overlayKeyboardHintNextFieldEnterOnly;

  /// No description provided for @overlayProcessingLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get overlayProcessingLocal;

  /// No description provided for @overlayProcessingCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get overlayProcessingCloud;

  /// Overlay label while a recording whose text goes to the quick note runs (announced by screen readers)
  ///
  /// In en, this message translates to:
  /// **'Recording to note'**
  String get overlayRecordingQuickNote;

  /// Very short target name shown in the recording overlay so the user sees the text is going to the quick note, not the clipboard
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get overlayTargetQuickNote;

  /// Overlay recording line combining the elapsed time with the target name
  ///
  /// In en, this message translates to:
  /// **'{elapsed} · {target}'**
  String overlayRecordingTargetTimer(String elapsed, String target);

  /// Overlay completion message when the text was appended to the quick note — nothing was copied or pasted
  ///
  /// In en, this message translates to:
  /// **'Added to note'**
  String get overlayDoneQuickNote;

  /// No description provided for @floatingButtonHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get floatingButtonHide;

  /// No description provided for @floatingButtonQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get floatingButtonQuit;

  /// Accessibility label for the floating recording button (screen readers)
  ///
  /// In en, this message translates to:
  /// **'Recording button'**
  String get a11yRecordingButton;

  /// Accessibility label for the floating recording overlay (screen readers)
  ///
  /// In en, this message translates to:
  /// **'Recording overlay'**
  String get a11yRecordingOverlay;

  /// Accessibility label for the clipboard quick-paste side panel (screen readers)
  ///
  /// In en, this message translates to:
  /// **'Quick paste panel'**
  String get a11ySidePanel;

  /// No description provided for @trayStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get trayStatusRecording;

  /// No description provided for @trayStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get trayStatusReady;

  /// No description provided for @trayStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get trayStartRecording;

  /// No description provided for @trayStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop Recording'**
  String get trayStopRecording;

  /// No description provided for @trayOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open WhisPaste'**
  String get trayOpenApp;

  /// No description provided for @traySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get traySettings;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// No description provided for @trayMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get trayMicrophone;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get settingsComingSoon;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @hintDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss hint'**
  String get hintDismiss;

  /// No description provided for @voiceNoteButton.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNoteButton;

  /// No description provided for @voiceNoteRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording voice note…'**
  String get voiceNoteRecording;

  /// No description provided for @voiceNoteTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get voiceNoteTranscribing;

  /// No description provided for @voiceNoteAdded.
  ///
  /// In en, this message translates to:
  /// **'Voice note added'**
  String get voiceNoteAdded;

  /// No description provided for @voiceTagAdded.
  ///
  /// In en, this message translates to:
  /// **'Tag \"{tag}\" added by voice'**
  String voiceTagAdded(String tag);

  /// No description provided for @voiceCorrectionApplied.
  ///
  /// In en, this message translates to:
  /// **'Transcript corrected by voice'**
  String get voiceCorrectionApplied;

  /// No description provided for @voiceNoteEmpty.
  ///
  /// In en, this message translates to:
  /// **'No speech detected'**
  String get voiceNoteEmpty;

  /// No description provided for @voiceNoteError.
  ///
  /// In en, this message translates to:
  /// **'Voice note failed'**
  String get voiceNoteError;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: v{version}'**
  String updateAvailable(String version);

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update… {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updateReadyToInstall.
  ///
  /// In en, this message translates to:
  /// **'Update ready, click to install'**
  String get updateReadyToInstall;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check Now'**
  String get updateCheckNow;

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Install Update'**
  String get updateInstall;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// No description provided for @updateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'Release Notes'**
  String get updateViewRelease;

  /// No description provided for @updateError.
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get updateError;

  /// No description provided for @updateRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests, try again later'**
  String get updateRateLimited;

  /// No description provided for @updateStatusBarChip.
  ///
  /// In en, this message translates to:
  /// **'v{version} available'**
  String updateStatusBarChip(String version);

  /// No description provided for @settingsOverlaySize.
  ///
  /// In en, this message translates to:
  /// **'Overlay size'**
  String get settingsOverlaySize;

  /// No description provided for @settingsOverlaySizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose between detailed or minimal display'**
  String get settingsOverlaySizeSubtitle;

  /// No description provided for @settingsOverlaySizeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settingsOverlaySizeNormal;

  /// No description provided for @settingsOverlaySizeCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get settingsOverlaySizeCompact;

  /// No description provided for @settingsOverlaySizeMini.
  ///
  /// In en, this message translates to:
  /// **'Mini'**
  String get settingsOverlaySizeMini;

  /// No description provided for @settingsOverlayStyle.
  ///
  /// In en, this message translates to:
  /// **'Overlay style'**
  String get settingsOverlayStyle;

  /// No description provided for @settingsOverlayStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose between glass or a solid opaque look'**
  String get settingsOverlayStyleSubtitle;

  /// No description provided for @settingsOverlayStyleGlass.
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get settingsOverlayStyleGlass;

  /// No description provided for @settingsOverlayStyleSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get settingsOverlayStyleSolid;

  /// No description provided for @overlayRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get overlayRetry;

  /// No description provided for @overlayDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get overlayDismiss;

  /// No description provided for @overlayContextCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get overlayContextCancel;

  /// No description provided for @overlayContextSwitchNormal.
  ///
  /// In en, this message translates to:
  /// **'Switch to Normal'**
  String get overlayContextSwitchNormal;

  /// No description provided for @overlayContextSwitchCompact.
  ///
  /// In en, this message translates to:
  /// **'Switch to Compact'**
  String get overlayContextSwitchCompact;

  /// No description provided for @overlayContextSwitchMini.
  ///
  /// In en, this message translates to:
  /// **'Switch to Mini'**
  String get overlayContextSwitchMini;

  /// No description provided for @overlayContextHide.
  ///
  /// In en, this message translates to:
  /// **'Hide overlay'**
  String get overlayContextHide;

  /// No description provided for @buttonContextOpen.
  ///
  /// In en, this message translates to:
  /// **'Open WhisPaste'**
  String get buttonContextOpen;

  /// No description provided for @buttonContextStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get buttonContextStartRecording;

  /// No description provided for @buttonContextShowHistory.
  ///
  /// In en, this message translates to:
  /// **'Show History'**
  String get buttonContextShowHistory;

  /// No description provided for @buttonContextSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get buttonContextSettings;

  /// No description provided for @buttonContextQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit WhisPaste'**
  String get buttonContextQuit;

  /// No description provided for @settingsHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get settingsHistory;

  /// No description provided for @settingsHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Retention and automatic cleanup'**
  String get settingsHistorySubtitle;

  /// No description provided for @settingsHistoryMaxEntries.
  ///
  /// In en, this message translates to:
  /// **'Maximum entries'**
  String get settingsHistoryMaxEntries;

  /// No description provided for @settingsHistoryMaxEntriesUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settingsHistoryMaxEntriesUnlimited;

  /// No description provided for @settingsHistoryAutoTrashDays.
  ///
  /// In en, this message translates to:
  /// **'Auto-delete trash after'**
  String get settingsHistoryAutoTrashDays;

  /// No description provided for @settingsHistoryAutoTrashNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsHistoryAutoTrashNever;

  /// No description provided for @settingsHistoryAutoTrashDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String settingsHistoryAutoTrashDaysLabel(int count);

  /// No description provided for @settingsHistoryRetentionPreset.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get settingsHistoryRetentionPreset;

  /// No description provided for @settingsHistoryPresetMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get settingsHistoryPresetMinimal;

  /// No description provided for @settingsHistoryPresetStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get settingsHistoryPresetStandard;

  /// No description provided for @settingsHistoryPresetUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settingsHistoryPresetUnlimited;

  /// No description provided for @settingsHistoryPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsHistoryPresetCustom;

  /// No description provided for @settingsFloatingButtonSection.
  ///
  /// In en, this message translates to:
  /// **'Floating Button'**
  String get settingsFloatingButtonSection;

  /// No description provided for @settingsFloatingButtonSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Always-on-top recording button for quick access'**
  String get settingsFloatingButtonSectionSubtitle;

  /// No description provided for @settingsSttIdleTimeout.
  ///
  /// In en, this message translates to:
  /// **'Engine idle timeout'**
  String get settingsSttIdleTimeout;

  /// No description provided for @settingsSttIdleTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long the speech service stays loaded after use'**
  String get settingsSttIdleTimeoutSubtitle;

  /// No description provided for @settingsSttIdleTimeoutKeepAlive.
  ///
  /// In en, this message translates to:
  /// **'Keep alive'**
  String get settingsSttIdleTimeoutKeepAlive;

  /// No description provided for @settingsSttIdleTimeoutMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String settingsSttIdleTimeoutMinutes(int count);

  /// No description provided for @reviewPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you enjoying WhisPaste?'**
  String get reviewPromptTitle;

  /// No description provided for @reviewPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Your rating helps others discover it and keeps development going.'**
  String get reviewPromptBody;

  /// No description provided for @reviewPromptYes.
  ///
  /// In en, this message translates to:
  /// **'Loving it!'**
  String get reviewPromptYes;

  /// No description provided for @reviewPromptNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get reviewPromptNotNow;

  /// No description provided for @reviewPromptNever.
  ///
  /// In en, this message translates to:
  /// **'Never ask again'**
  String get reviewPromptNever;

  /// No description provided for @reviewPromptStarGitHub.
  ///
  /// In en, this message translates to:
  /// **'⭐ Star on GitHub'**
  String get reviewPromptStarGitHub;

  /// No description provided for @reviewPromptRateStore.
  ///
  /// In en, this message translates to:
  /// **'★ Rate on the Store'**
  String get reviewPromptRateStore;

  /// No description provided for @reviewPromptGateBody.
  ///
  /// In en, this message translates to:
  /// **'Just a quick question for us, this isn\'t a store rating.'**
  String get reviewPromptGateBody;

  /// No description provided for @reviewPromptGateYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, I like it'**
  String get reviewPromptGateYes;

  /// No description provided for @reviewPromptGateNo.
  ///
  /// In en, this message translates to:
  /// **'Not really'**
  String get reviewPromptGateNo;

  /// No description provided for @reviewSupportEntry.
  ///
  /// In en, this message translates to:
  /// **'Rate & support WhisPaste'**
  String get reviewSupportEntry;

  /// No description provided for @reviewSupportLabel.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get reviewSupportLabel;

  /// No description provided for @reviewSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your rating helps others discover WhisPaste and supports the project.'**
  String get reviewSupportSubtitle;

  /// No description provided for @reviewSupportAction.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get reviewSupportAction;

  /// No description provided for @insufficientRamTitle.
  ///
  /// In en, this message translates to:
  /// **'Not Enough Memory'**
  String get insufficientRamTitle;

  /// No description provided for @insufficientRamBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste requires at least {requiredGb} GB of RAM to run. Your system has {detectedGb} GB.\n\nWith less memory, the AI transcription engine may fail to load or crash mid-session.'**
  String insufficientRamBody(double detectedGb, int requiredGb);

  /// No description provided for @insufficientRamQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit WhisPaste'**
  String get insufficientRamQuit;

  /// No description provided for @insufficientRamLearnMore.
  ///
  /// In en, this message translates to:
  /// **'System requirements'**
  String get insufficientRamLearnMore;

  /// No description provided for @insufficientRamSystemCheck.
  ///
  /// In en, this message translates to:
  /// **'System Check'**
  String get insufficientRamSystemCheck;

  /// No description provided for @insufficientRamYourSystem.
  ///
  /// In en, this message translates to:
  /// **'Your system'**
  String get insufficientRamYourSystem;

  /// No description provided for @insufficientRamRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get insufficientRamRequired;

  /// No description provided for @hotkeyRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Hotkey registration failed, please re-bind your shortcut in Settings.'**
  String get hotkeyRegistrationFailed;

  /// No description provided for @hotkeyRegistrationFailedDefaultActive.
  ///
  /// In en, this message translates to:
  /// **'Hotkey registration failed, using Ctrl+Shift+Space as fallback. Please re-bind in Settings.'**
  String get hotkeyRegistrationFailedDefaultActive;

  /// No description provided for @hotkeyConflictWarning.
  ///
  /// In en, this message translates to:
  /// **'This shortcut is reserved by {platform} ({note}) and may not work.'**
  String hotkeyConflictWarning(String platform, String note);

  /// No description provided for @exportFormatPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Export Format'**
  String get exportFormatPickerTitle;

  /// No description provided for @exportFormatText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get exportFormatText;

  /// No description provided for @exportFormatMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get exportFormatMarkdown;

  /// No description provided for @exportFormatCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportFormatCsv;

  /// No description provided for @exportFormatJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportFormatJson;

  /// No description provided for @exportFormatWord.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get exportFormatWord;

  /// No description provided for @cpuFallbackToast.
  ///
  /// In en, this message translates to:
  /// **'Transcription is taking a little longer than usual right now, it\'s still working.'**
  String get cpuFallbackToast;

  /// No description provided for @recoveryExhaustedToast.
  ///
  /// In en, this message translates to:
  /// **'Voice service cannot start. Please restart the app or reload the voice model.'**
  String get recoveryExhaustedToast;

  /// No description provided for @recoveryExhaustedAction.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get recoveryExhaustedAction;

  /// No description provided for @recoveryVcRuntimeToast.
  ///
  /// In en, this message translates to:
  /// **'Voice service cannot start: a Windows component is missing (Microsoft Visual C++). Please install the Visual C++ Redistributable (x64) and restart WhisPaste.'**
  String get recoveryVcRuntimeToast;

  /// No description provided for @recoveryVcRuntimeAction.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get recoveryVcRuntimeAction;

  /// No description provided for @modelAbiInfoToast.
  ///
  /// In en, this message translates to:
  /// **'Reloading voice model, please wait.'**
  String get modelAbiInfoToast;

  /// No description provided for @recoveryGpuDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is now running without GPU acceleration due to a problem on the last launch. Dictation still works as usual.'**
  String get recoveryGpuDisabledToast;

  /// No description provided for @serverDownloadFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Voice service could not be downloaded. Check your internet connection?'**
  String get serverDownloadFailedToast;

  /// No description provided for @serverDownloadFailedAction.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get serverDownloadFailedAction;

  /// No description provided for @serverDownloadStalledToast.
  ///
  /// In en, this message translates to:
  /// **'Download stalled: reconnecting.'**
  String get serverDownloadStalledToast;

  /// No description provided for @historyWriteFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Entry could not be saved, please check available storage.'**
  String get historyWriteFailedToast;

  /// No description provided for @historyWriteFailedAction.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get historyWriteFailedAction;

  /// No description provided for @factoryResetFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Factory reset incomplete. Restart the app?'**
  String get factoryResetFailedToast;

  /// No description provided for @factoryResetFailedAction.
  ///
  /// In en, this message translates to:
  /// **'Quit app'**
  String get factoryResetFailedAction;

  /// No description provided for @errorSttRejectEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audio to transcribe, please record again.'**
  String get errorSttRejectEmpty;

  /// No description provided for @errorSttRejectInvalidWav.
  ///
  /// In en, this message translates to:
  /// **'Audio file is corrupted, please record again.'**
  String get errorSttRejectInvalidWav;

  /// No description provided for @errorSttRejectUnsupportedLanguage.
  ///
  /// In en, this message translates to:
  /// **'This language is not supported by the local speech model, please review the language in Settings.'**
  String get errorSttRejectUnsupportedLanguage;

  /// No description provided for @errorSttRejectPromptTooLong.
  ///
  /// In en, this message translates to:
  /// **'Custom vocabulary is too long, please shorten it in Settings.'**
  String get errorSttRejectPromptTooLong;

  /// No description provided for @settingsGpuAcceleration.
  ///
  /// In en, this message translates to:
  /// **'Graphics Acceleration'**
  String get settingsGpuAcceleration;

  /// No description provided for @settingsGpuAccelerationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Controls whether the speech service uses GPU or CPU for local recognition'**
  String get settingsGpuAccelerationSubtitle;

  /// No description provided for @settingsGpuAccelerationAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (recommended)'**
  String get settingsGpuAccelerationAuto;

  /// No description provided for @settingsGpuAccelerationEnabled.
  ///
  /// In en, this message translates to:
  /// **'GPU (force)'**
  String get settingsGpuAccelerationEnabled;

  /// No description provided for @settingsGpuAccelerationDisabled.
  ///
  /// In en, this message translates to:
  /// **'CPU only'**
  String get settingsGpuAccelerationDisabled;

  /// No description provided for @settingsSttEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get settingsSttEngine;

  /// No description provided for @settingsSttEngineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper covers 99 languages and every GPU backend; Parakeet is much faster on CPU-only hardware but covers ~25 languages and has no GPU backend yet'**
  String get settingsSttEngineSubtitle;

  /// No description provided for @settingsSttEngineWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get settingsSttEngineWhisper;

  /// No description provided for @settingsSttEngineParakeet.
  ///
  /// In en, this message translates to:
  /// **'Parakeet (fastest, ~25 languages)'**
  String get settingsSttEngineParakeet;

  /// No description provided for @parakeetModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Parakeet TDT model'**
  String get parakeetModelTitle;

  /// No description provided for @parakeetModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One-time download (~640 MB), then runs fully offline'**
  String get parakeetModelSubtitle;

  /// No description provided for @parakeetModelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get parakeetModelDownload;

  /// No description provided for @parakeetModelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get parakeetModelDownloading;

  /// No description provided for @parakeetModelInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get parakeetModelInstalled;

  /// No description provided for @parakeetModelDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get parakeetModelDelete;

  /// No description provided for @parakeetModelCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get parakeetModelCancel;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings…'**
  String get settingsSearchHint;

  /// No description provided for @settingsSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No Results'**
  String get settingsSearchNoResults;

  /// No description provided for @settingsSearchNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get settingsSearchNoResultsHint;

  /// No description provided for @settingsSearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchFieldLabel;

  /// No description provided for @settingsSearchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}}'**
  String settingsSearchResultCount(int count);

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control what data WhisPaste shares'**
  String get settingsPrivacySubtitle;

  /// No description provided for @settingsShareUsageStats.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous usage statistics'**
  String get settingsShareUsageStats;

  /// No description provided for @settingsShareUsageStatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sent cookieless and without any identifiers, help us understand how WhisPaste is used'**
  String get settingsShareUsageStatsSubtitle;

  /// No description provided for @settingsRetainRecentAudio.
  ///
  /// In en, this message translates to:
  /// **'Keep recent recordings'**
  String get settingsRetainRecentAudio;

  /// No description provided for @settingsRetainRecentAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the audio of your last 20 dictations on this device for debugging or restoring a past transcript; older recordings are deleted automatically'**
  String get settingsRetainRecentAudioSubtitle;

  /// No description provided for @storeThankYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your support!'**
  String get storeThankYouTitle;

  /// No description provided for @storeThankYouBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re really glad you\'re here. If WhisPaste makes your day a little easier, a short review means a lot to us.'**
  String get storeThankYouBody;

  /// No description provided for @storeThankYouCtaStore.
  ///
  /// In en, this message translates to:
  /// **'★ Rate on the Store'**
  String get storeThankYouCtaStore;

  /// No description provided for @storeThankYouCtaGitHub.
  ///
  /// In en, this message translates to:
  /// **'⭐ Star on GitHub'**
  String get storeThankYouCtaGitHub;

  /// No description provided for @storeThankYouDismiss.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get storeThankYouDismiss;

  /// No description provided for @featureSpotlightHeading.
  ///
  /// In en, this message translates to:
  /// **'New in WhisPaste'**
  String get featureSpotlightHeading;

  /// No description provided for @featureSpotlightDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get featureSpotlightDismiss;

  /// No description provided for @featureSpotlightSnippetPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Snippet Picker'**
  String get featureSpotlightSnippetPickerTitle;

  /// No description provided for @featureSpotlightSnippetPickerDescription.
  ///
  /// In en, this message translates to:
  /// **'Save reusable text blocks and insert them anywhere with a hotkey or a spoken trigger — no retyping needed.'**
  String get featureSpotlightSnippetPickerDescription;

  /// No description provided for @featureSpotlightSidePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Side Panel'**
  String get featureSpotlightSidePanelTitle;

  /// No description provided for @featureSpotlightSidePanelDescription.
  ///
  /// In en, this message translates to:
  /// **'Hover the screen edge to open your recent clipboard history and drag any item straight into your document.'**
  String get featureSpotlightSidePanelDescription;

  /// No description provided for @featureSpotlightChangelogLink.
  ///
  /// In en, this message translates to:
  /// **'View full changelog'**
  String get featureSpotlightChangelogLink;

  /// No description provided for @featureSpotlightReviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Review the new features'**
  String get featureSpotlightReviewLabel;

  /// No description provided for @featureSpotlightReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get featureSpotlightReviewAction;

  /// No description provided for @notesNewNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get notesNewNote;

  /// No description provided for @notesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get notesEmptyTitle;

  /// No description provided for @notesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Create a note to start collecting text from anywhere.'**
  String get notesEmptyHint;

  /// No description provided for @notesUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled note'**
  String get notesUntitled;

  /// No description provided for @notesEditorPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Start typing…'**
  String get notesEditorPlaceholder;

  /// No description provided for @notesListSemantics.
  ///
  /// In en, this message translates to:
  /// **'Notes list'**
  String get notesListSemantics;

  /// No description provided for @notesCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy note'**
  String get notesCopy;

  /// No description provided for @notesCopied.
  ///
  /// In en, this message translates to:
  /// **'Note copied'**
  String get notesCopied;

  /// No description provided for @notesFavorite.
  ///
  /// In en, this message translates to:
  /// **'Mark as favorite'**
  String get notesFavorite;

  /// No description provided for @notesUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get notesUnfavorite;

  /// No description provided for @notesQuickNoteSet.
  ///
  /// In en, this message translates to:
  /// **'Make this the quick note the hotkey appends to'**
  String get notesQuickNoteSet;

  /// No description provided for @notesQuickNoteClear.
  ///
  /// In en, this message translates to:
  /// **'Quick note — remove the mark'**
  String get notesQuickNoteClear;

  /// No description provided for @notesQuickNoteHotkeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Hotkey'**
  String get notesQuickNoteHotkeyLabel;

  /// No description provided for @notesQuickNoteHotkeyChange.
  ///
  /// In en, this message translates to:
  /// **'Change the quick-note hotkey — currently {combination}'**
  String notesQuickNoteHotkeyChange(String combination);

  /// No description provided for @notesQuickNoteHotkeyOff.
  ///
  /// In en, this message translates to:
  /// **'The quick-note hotkey is switched off.'**
  String get notesQuickNoteHotkeyOff;

  /// No description provided for @notesQuickNoteHotkeyEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn hotkey on'**
  String get notesQuickNoteHotkeyEnable;

  /// No description provided for @notesMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get notesMoveToTrash;

  /// No description provided for @notesMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to trash'**
  String get notesMovedToTrash;

  /// No description provided for @notesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get notesRestore;

  /// No description provided for @notesDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get notesDeleteForever;

  /// No description provided for @notesDeleteForeverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete note forever?'**
  String get notesDeleteForeverConfirm;

  /// No description provided for @notesTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get notesTrash;

  /// No description provided for @notesTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get notesTrashEmpty;

  /// No description provided for @notesTrashEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Deleted notes land here and aren\'t removed automatically.'**
  String get notesTrashEmptyHint;

  /// No description provided for @notesUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get notesUndo;

  /// No description provided for @notesAddTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get notesAddTag;

  /// No description provided for @notesTagPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Tag name…'**
  String get notesTagPlaceholder;

  /// No description provided for @notesSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get notesSearchPlaceholder;

  /// No description provided for @notesSearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get notesSearchFieldLabel;

  /// No description provided for @notesNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get notesNoResults;

  /// No description provided for @notesNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'No notes match \"{query}\".\nTry a different search term.'**
  String notesNoResultsHint(String query);

  /// No description provided for @notesResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String notesResultCount(int count);

  /// No description provided for @notesExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get notesExport;

  /// Markdown toolbar button — tooltip and screen-reader name.
  ///
  /// In en, this message translates to:
  /// **'Bold ({shortcut})'**
  String markdownToolbarBold(String shortcut);

  /// No description provided for @markdownToolbarItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic ({shortcut})'**
  String markdownToolbarItalic(String shortcut);

  /// No description provided for @markdownToolbarHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get markdownToolbarHeading;

  /// No description provided for @markdownToolbarBulletList.
  ///
  /// In en, this message translates to:
  /// **'Bullet list ({shortcut})'**
  String markdownToolbarBulletList(String shortcut);

  /// No description provided for @markdownToolbarNumberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get markdownToolbarNumberedList;

  /// No description provided for @markdownToolbarQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get markdownToolbarQuote;

  /// No description provided for @markdownToolbarCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get markdownToolbarCode;

  /// No description provided for @findReplaceToggle.
  ///
  /// In en, this message translates to:
  /// **'Find and replace in this text'**
  String get findReplaceToggle;

  /// No description provided for @findReplaceFindLabel.
  ///
  /// In en, this message translates to:
  /// **'Find in this text'**
  String get findReplaceFindLabel;

  /// No description provided for @findReplaceFindHint.
  ///
  /// In en, this message translates to:
  /// **'Find…'**
  String get findReplaceFindHint;

  /// No description provided for @findReplaceReplaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Replace matches with'**
  String get findReplaceReplaceLabel;

  /// No description provided for @findReplaceReplaceHint.
  ///
  /// In en, this message translates to:
  /// **'Replace with…'**
  String get findReplaceReplaceHint;

  /// No description provided for @findReplaceNext.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get findReplaceNext;

  /// No description provided for @findReplacePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get findReplacePrevious;

  /// No description provided for @findReplaceReplaceAction.
  ///
  /// In en, this message translates to:
  /// **'Replace this match'**
  String get findReplaceReplaceAction;

  /// No description provided for @findReplaceReplaceAllAction.
  ///
  /// In en, this message translates to:
  /// **'Replace all matches'**
  String get findReplaceReplaceAllAction;

  /// No description provided for @findReplaceClose.
  ///
  /// In en, this message translates to:
  /// **'Close find and replace'**
  String get findReplaceClose;

  /// No description provided for @findReplaceNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get findReplaceNoMatches;

  /// No description provided for @findReplaceMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String findReplaceMatchCount(int current, int total);

  /// No description provided for @sidePanelTranscriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Transcriptions'**
  String get sidePanelTranscriptionsTitle;

  /// No description provided for @sidePanelSnippetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Snippets'**
  String get sidePanelSnippetsTitle;

  /// No description provided for @sidePanelClipboardHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clipboard History'**
  String get sidePanelClipboardHistoryTitle;

  /// No description provided for @sidePanelClipboardHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing copied yet'**
  String get sidePanelClipboardHistoryEmpty;

  /// No description provided for @sidePanelClipboardHistoryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Anything you copy while WhisPaste is running shows up here — cleared when the app restarts.'**
  String get sidePanelClipboardHistoryEmptyHint;

  /// Accessibility label for the side panel's close button (screen readers)
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get sidePanelClose;

  /// No description provided for @sidePanelSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get sidePanelSearchHint;

  /// Accessibility label for the side panel's search field (screen readers) -- the visible hint text (sidePanelSearchHint) is not section-specific, so this names what it searches instead
  ///
  /// In en, this message translates to:
  /// **'Search this list'**
  String get sidePanelSearchFieldLabel;

  /// No description provided for @sidePanelNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get sidePanelNoMatches;

  /// No description provided for @sidePanelNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get sidePanelNoMatchesHint;

  /// No description provided for @settingsSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get settingsSmartMode;

  /// No description provided for @settingsSmartModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local text cleanup, shortening, and translation after dictation'**
  String get settingsSmartModeSubtitle;

  /// No description provided for @smartModeStandardPreset.
  ///
  /// In en, this message translates to:
  /// **'Standard preset'**
  String get smartModeStandardPreset;

  /// No description provided for @smartModePresetOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get smartModePresetOff;

  /// No description provided for @smartModePresetOffDescription.
  ///
  /// In en, this message translates to:
  /// **'No automatic post-processing — the dictated text is used exactly as transcribed.'**
  String get smartModePresetOffDescription;

  /// No description provided for @smartModePresetCleanup.
  ///
  /// In en, this message translates to:
  /// **'Cleanup'**
  String get smartModePresetCleanup;

  /// No description provided for @smartModePresetCleanupDescription.
  ///
  /// In en, this message translates to:
  /// **'Removes filler words like \"um\" and fixes punctuation and capitalization, without changing the wording, meaning, or language.'**
  String get smartModePresetCleanupDescription;

  /// No description provided for @smartModePresetConcise.
  ///
  /// In en, this message translates to:
  /// **'Concise'**
  String get smartModePresetConcise;

  /// No description provided for @smartModePresetConciseDescription.
  ///
  /// In en, this message translates to:
  /// **'Shortens the text by removing redundancy and filler while keeping every important fact, in the same language.'**
  String get smartModePresetConciseDescription;

  /// No description provided for @smartModePresetTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get smartModePresetTranslate;

  /// No description provided for @smartModePresetTranslateDescription.
  ///
  /// In en, this message translates to:
  /// **'Translates the dictated text into the target language set below.'**
  String get smartModePresetTranslateDescription;

  /// No description provided for @smartModeTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get smartModeTargetLanguage;

  /// No description provided for @smartModeTargetLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get smartModeTargetLanguageGerman;

  /// No description provided for @smartModeTargetLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get smartModeTargetLanguageEnglish;

  /// No description provided for @smartModeTargetLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get smartModeTargetLanguageSpanish;

  /// No description provided for @smartModeTargetLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get smartModeTargetLanguageFrench;

  /// No description provided for @smartModeTargetLanguagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get smartModeTargetLanguagePortuguese;

  /// No description provided for @smartModeTargetLanguageMandarin.
  ///
  /// In en, this message translates to:
  /// **'Mandarin'**
  String get smartModeTargetLanguageMandarin;

  /// No description provided for @smartModeTargetLanguageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get smartModeTargetLanguageRussian;

  /// No description provided for @smartModeDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get smartModeDownload;

  /// No description provided for @smartModeDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode model ready to use'**
  String get smartModeDownloadComplete;

  /// No description provided for @smartModeRamWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Limited memory detected'**
  String get smartModeRamWarningTitle;

  /// No description provided for @smartModeRamWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode\'s local model runs best with 8 GB of RAM or more. It may still work, but could run slowly or fail on this machine. Download anyway?'**
  String get smartModeRamWarningBody;

  /// No description provided for @smartModeRamWarningContinue.
  ///
  /// In en, this message translates to:
  /// **'Download anyway'**
  String get smartModeRamWarningContinue;

  /// No description provided for @smartModeRamWarningCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get smartModeRamWarningCancel;

  /// No description provided for @smartModeMemoryFootprintInfo.
  ///
  /// In en, this message translates to:
  /// **'Runs fully on-device. While active, it uses about 4–5 GB of RAM in addition to disk space — shared with the transcription model, so total memory use depends on which STT model you also have loaded.'**
  String get smartModeMemoryFootprintInfo;

  /// No description provided for @smartModeSpeedExampleInfo.
  ///
  /// In en, this message translates to:
  /// **'Example: a typical 50-word dictation takes roughly 1–6 seconds to process, depending on your device\'s hardware.'**
  String get smartModeSpeedExampleInfo;

  /// No description provided for @settingsHotkeyActionSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get settingsHotkeyActionSmartMode;

  /// No description provided for @settingsSmartModeHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Smart-Mode hotkey'**
  String get settingsSmartModeHotkeyEnabled;

  /// No description provided for @settingsSmartModeHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Starts a recording with a fixed preset, independent of your standard preset above. Supports push-to-talk just like the main hotkey.'**
  String get settingsSmartModeHotkeyHint;

  /// No description provided for @settingsSmartModeHotkeyPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get settingsSmartModeHotkeyPreset;

  /// No description provided for @settingsSmartModeCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Combination'**
  String get settingsSmartModeCurrentHotkey;

  /// No description provided for @settingsSmartModeHotkeyCollision.
  ///
  /// In en, this message translates to:
  /// **'This combination is already used for \"{action}\". Pick a different one.'**
  String settingsSmartModeHotkeyCollision(String action);

  /// No description provided for @settingsSmartModeHotkeyInactive.
  ///
  /// In en, this message translates to:
  /// **'This combination could not be registered — the Smart-Mode hotkey is currently not active. Pick a different combination.'**
  String get settingsSmartModeHotkeyInactive;

  /// No description provided for @smartModeOnboardingHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Try Smart Mode'**
  String get smartModeOnboardingHintTitle;

  /// No description provided for @smartModeOnboardingHintBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode can clean up, shorten, or translate your dictated text automatically — fully on-device. Download the local model now, or set it up later in Settings.'**
  String get smartModeOnboardingHintBody;

  /// No description provided for @smartModeOnboardingHintDownloadCta.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get smartModeOnboardingHintDownloadCta;

  /// No description provided for @smartModeOnboardingHintSkipCta.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get smartModeOnboardingHintSkipCta;

  /// No description provided for @smartModeUsageHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Try Smart Mode on your next dictation'**
  String get smartModeUsageHintTitle;

  /// No description provided for @smartModeUsageHintBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode can clean up, shorten, or translate text like this automatically, right on your device. Here\'s what you just dictated:'**
  String get smartModeUsageHintBody;

  /// No description provided for @smartModeUsageHintCta.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get smartModeUsageHintCta;

  /// No description provided for @smartModeUsageHintDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get smartModeUsageHintDismiss;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return L10nDe();
    case 'en':
      return L10nEn();
    case 'he':
      return L10nHe();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
