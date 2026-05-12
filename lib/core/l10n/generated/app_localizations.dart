import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

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

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navReplacements.
  ///
  /// In en, this message translates to:
  /// **'Voice Shortcuts'**
  String get navReplacements;

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
  /// **'Voice Shortcuts'**
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
  /// **'Press the record button or use the hotkey to start dictating.'**
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

  /// No description provided for @historyClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get historyClearSearch;

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

  /// No description provided for @historyTrashEmptied.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied'**
  String get historyTrashEmptied;

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
  /// **'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.'**
  String get historyNoRecordingsHint;

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

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

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

  /// No description provided for @settingsShowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Show Notifications'**
  String get settingsShowNotifications;

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

  /// No description provided for @settingsHoldToRecord.
  ///
  /// In en, this message translates to:
  /// **'Hold to Record'**
  String get settingsHoldToRecord;

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

  /// No description provided for @settingsQualityFastTiny.
  ///
  /// In en, this message translates to:
  /// **'Fast (Tiny)'**
  String get settingsQualityFastTiny;

  /// No description provided for @settingsQualityBalancedSmall.
  ///
  /// In en, this message translates to:
  /// **'Balanced (Small)'**
  String get settingsQualityBalancedSmall;

  /// No description provided for @settingsQualityHighQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'High Quality (Medium)'**
  String get settingsQualityHighQualityMedium;

  /// No description provided for @settingsQualityBestLarge.
  ///
  /// In en, this message translates to:
  /// **'Best Quality (Large)'**
  String get settingsQualityBestLarge;

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

  /// No description provided for @settingsOverlayFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'Recording Overlay'**
  String get settingsOverlayFloatingButton;

  /// No description provided for @settingsOverlayFloatingButtonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control how recording status appears while you dictate'**
  String get settingsOverlayFloatingButtonSubtitle;

  /// No description provided for @settingsShowOverlay.
  ///
  /// In en, this message translates to:
  /// **'Recording status display'**
  String get settingsShowOverlay;

  /// No description provided for @settingsShowOverlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose where live recording feedback appears while you dictate'**
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

  /// No description provided for @settingsFloatingButtonOpacity.
  ///
  /// In en, this message translates to:
  /// **'Floating button opacity'**
  String get settingsFloatingButtonOpacity;

  /// No description provided for @settingsFloatingButtonOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only affects the floating button, not the recording overlay'**
  String get settingsFloatingButtonOpacitySubtitle;

  /// No description provided for @settingsFloatingOverlayOpacity.
  ///
  /// In en, this message translates to:
  /// **'Overlay opacity'**
  String get settingsFloatingOverlayOpacity;

  /// No description provided for @settingsFloatingOverlayOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Transparency of the floating recording overlay'**
  String get settingsFloatingOverlayOpacitySubtitle;

  /// No description provided for @settingsFloatingButtonSize.
  ///
  /// In en, this message translates to:
  /// **'Floating button size'**
  String get settingsFloatingButtonSize;

  /// No description provided for @settingsFloatingButtonSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how prominent the always-on-top button should feel'**
  String get settingsFloatingButtonSizeSubtitle;

  /// No description provided for @settingsSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsSizeSmall;

  /// No description provided for @settingsSizeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settingsSizeNormal;

  /// No description provided for @settingsSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsSizeLarge;

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
  /// **'Names, technical terms — improves recognition accuracy'**
  String get settingsCustomVocabularyHint;

  /// No description provided for @settingsCustomVocabularyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. WhisPaste, Kubernetes, Dr. Mueller'**
  String get settingsCustomVocabularyPlaceholder;

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

  /// No description provided for @settingsCloudProviders.
  ///
  /// In en, this message translates to:
  /// **'Cloud Providers'**
  String get settingsCloudProviders;

  /// No description provided for @settingsCloudProvidersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'API keys for online services'**
  String get settingsCloudProvidersSubtitle;

  /// No description provided for @settingsOpenAiApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API Key'**
  String get settingsOpenAiApiKey;

  /// No description provided for @settingsGroqApiKey.
  ///
  /// In en, this message translates to:
  /// **'Groq API Key'**
  String get settingsGroqApiKey;

  /// No description provided for @settingsDeepgramApiKey.
  ///
  /// In en, this message translates to:
  /// **'Deepgram API Key'**
  String get settingsDeepgramApiKey;

  /// No description provided for @settingsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvanced;

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
  /// **'This will permanently delete ALL data: dictation history, tags, projects, voice shortcuts, downloaded models, logs, and settings. The app will return to its initial state.\n\nThis cannot be undone.'**
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

  /// No description provided for @migrationComplete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 dictation migrated from WhisPaste 1.x} other{{count} dictations migrated from WhisPaste 1.x}}'**
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

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

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
  /// **'No audio detected — please try again. Sometimes the microphone needs a moment to warm up.'**
  String get recordingGuardFailed;

  /// No description provided for @recordingAutoStopped.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped — silence detected.'**
  String get recordingAutoStopped;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

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

  /// No description provided for @tooltipRecord.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get tooltipRecord;

  /// No description provided for @tooltipStopRecord.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get tooltipStopRecord;

  /// No description provided for @tooltipProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing audio…'**
  String get tooltipProcessing;

  /// No description provided for @tooltipEngineNotReady.
  ///
  /// In en, this message translates to:
  /// **'Speech engine not ready'**
  String get tooltipEngineNotReady;

  /// No description provided for @tooltipEngineDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading speech engine…'**
  String get tooltipEngineDownloading;

  /// No description provided for @tooltipModelMissing.
  ///
  /// In en, this message translates to:
  /// **'No speech model downloaded'**
  String get tooltipModelMissing;

  /// No description provided for @tooltipTheme.
  ///
  /// In en, this message translates to:
  /// **'Toggle theme'**
  String get tooltipTheme;

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

  /// No description provided for @onboardingWelcomeHint.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste turns quick thoughts into clean text for messages, emails, notes, and comments.'**
  String get onboardingWelcomeHint;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you think — we read every message.'**
  String get feedbackHint;

  /// No description provided for @analyticsPreviewBanner.
  ///
  /// In en, this message translates to:
  /// **'Preview — showing sample data. Real analytics will appear once you start recording.'**
  String get analyticsPreviewBanner;

  /// No description provided for @analyticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get analyticsEmptyTitle;

  /// No description provided for @analyticsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start dictating to see your analytics here.'**
  String get analyticsEmptySubtitle;

  /// No description provided for @analyticsOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get analyticsOverview;

  /// No description provided for @analyticsOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your dictation stats at a glance'**
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
  /// **'Words Dictated'**
  String get analyticsWordsDictated;

  /// No description provided for @analyticsTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Time Saved'**
  String get analyticsTimeSaved;

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
  /// **'15–30s'**
  String get analyticsDuration15To30s;

  /// No description provided for @analyticsDuration30To60s.
  ///
  /// In en, this message translates to:
  /// **'30–60s'**
  String get analyticsDuration30To60s;

  /// No description provided for @analyticsDuration1To3m.
  ///
  /// In en, this message translates to:
  /// **'1–3m'**
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
  /// **'Search shortcuts…'**
  String get replacementsSearch;

  /// No description provided for @replacementsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get replacementsAdd;

  /// No description provided for @replacementsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No voice shortcuts yet'**
  String get replacementsEmpty;

  /// No description provided for @replacementsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add shortcuts to auto-replace words during dictation.\nExample: \"btw\" → \"by the way\"'**
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
  /// **'Enable shortcuts'**
  String get replacementsToggleLabel;

  /// No description provided for @replacementsToggleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Voice shortcuts are active'**
  String get replacementsToggleEnabled;

  /// No description provided for @replacementsToggleDisabled.
  ///
  /// In en, this message translates to:
  /// **'Voice shortcuts are disabled'**
  String get replacementsToggleDisabled;

  /// No description provided for @replacementsEnableBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice shortcuts are turned off'**
  String get replacementsEnableBannerTitle;

  /// No description provided for @replacementsEnableBannerHint.
  ///
  /// In en, this message translates to:
  /// **'Enable them so trigger phrases are replaced automatically during dictation.'**
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

  /// No description provided for @replacementsAddShortcut.
  ///
  /// In en, this message translates to:
  /// **'Add Shortcut'**
  String get replacementsAddShortcut;

  /// No description provided for @replacementsEditShortcut.
  ///
  /// In en, this message translates to:
  /// **'Edit Shortcut'**
  String get replacementsEditShortcut;

  /// No description provided for @replacementsNewShortcut.
  ///
  /// In en, this message translates to:
  /// **'New Shortcut'**
  String get replacementsNewShortcut;

  /// No description provided for @replacementsDialogHint.
  ///
  /// In en, this message translates to:
  /// **'The trigger phrase will be replaced automatically during dictation.'**
  String get replacementsDialogHint;

  /// No description provided for @replacementsTriggerLabel.
  ///
  /// In en, this message translates to:
  /// **'Trigger phrase'**
  String get replacementsTriggerLabel;

  /// No description provided for @replacementsTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. btw'**
  String get replacementsTriggerHint;

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
  /// **'Delete Shortcut'**
  String get replacementsDeleteTitle;

  /// No description provided for @replacementsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove the shortcut \"{trigger}\"? This cannot be undone.'**
  String replacementsDeleteMessage(String trigger);

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
  /// **'WhisPaste is free and open source under the MIT license. If you find it useful, please consider supporting its development!'**
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
  /// **'Cross-platform UI with Flutter. Local AI inference via whisper.cpp and llama.cpp.'**
  String get aboutFlutterGoDesc;

  /// No description provided for @aboutWhisper.
  ///
  /// In en, this message translates to:
  /// **'whisper.cpp & OpenAI Whisper'**
  String get aboutWhisper;

  /// No description provided for @aboutWhisperDesc.
  ///
  /// In en, this message translates to:
  /// **'Local and cloud speech recognition — fast, accurate, multilingual.'**
  String get aboutWhisperDesc;

  /// No description provided for @aboutLlamaCpp.
  ///
  /// In en, this message translates to:
  /// **'llama.cpp'**
  String get aboutLlamaCpp;

  /// No description provided for @aboutLlamaCppDesc.
  ///
  /// In en, this message translates to:
  /// **'Local LLM inference for AI post-processing without cloud dependency.'**
  String get aboutLlamaCppDesc;

  /// No description provided for @aboutPrivacyFirst.
  ///
  /// In en, this message translates to:
  /// **'Privacy-first'**
  String get aboutPrivacyFirst;

  /// No description provided for @aboutPrivacyFirstDesc.
  ///
  /// In en, this message translates to:
  /// **'Local AI inference by default — your voice never leaves your device unless you choose a cloud provider.'**
  String get aboutPrivacyFirstDesc;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Data'**
  String get aboutPrivacy;

  /// No description provided for @aboutPrivacyLocal.
  ///
  /// In en, this message translates to:
  /// **'All transcriptions and history are stored locally on your device — never on external servers.'**
  String get aboutPrivacyLocal;

  /// No description provided for @aboutPrivacyCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud providers (OpenAI, Groq, Deepgram, Anthropic, Gemini) only receive audio or text when you actively use them. Their privacy policies apply.'**
  String get aboutPrivacyCloud;

  /// No description provided for @aboutPrivacyNoTracking.
  ///
  /// In en, this message translates to:
  /// **'No analytics, no tracking, no user accounts. Update checks contact GitHub (version + IP only).'**
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
  /// **'Made with ♥ by Silvio Lindstedt'**
  String get aboutMadeWith;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source under the MIT License'**
  String get aboutOpenSource;

  /// No description provided for @feedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help us improve WhisPaste — every voice matters.'**
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
  /// **'How was the transcription or post-processing quality?'**
  String get feedbackPlaceholderAi;

  /// No description provided for @feedbackPlaceholderGeneral.
  ///
  /// In en, this message translates to:
  /// **'Share your thoughts…'**
  String get feedbackPlaceholderGeneral;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackSubmit;

  /// No description provided for @feedbackPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your feedback is anonymous and encrypted.'**
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
  /// **'Speech engine and current status'**
  String get statusBarSttTooltip;

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

  /// No description provided for @statusBarProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get statusBarProcessing;

  /// No description provided for @statusBarDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusBarDone;

  /// No description provided for @statusBarHotkeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey — click to configure'**
  String get statusBarHotkeyTooltip;

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

  /// No description provided for @tooltipSwitchToLight.
  ///
  /// In en, this message translates to:
  /// **'Switch to Light Mode'**
  String get tooltipSwitchToLight;

  /// No description provided for @tooltipSwitchToDark.
  ///
  /// In en, this message translates to:
  /// **'Switch to Dark Mode'**
  String get tooltipSwitchToDark;

  /// No description provided for @modelServerReady.
  ///
  /// In en, this message translates to:
  /// **'Speech engine ready'**
  String get modelServerReady;

  /// No description provided for @modelServerMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech engine not installed'**
  String get modelServerMissing;

  /// No description provided for @modelServerWhisper.
  ///
  /// In en, this message translates to:
  /// **'Local engine'**
  String get modelServerWhisper;

  /// No description provided for @modelReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get modelReady;

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
  /// **'Preparing speech engine…'**
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

  /// No description provided for @modelSizeTiny.
  ///
  /// In en, this message translates to:
  /// **'Quick transcription for short notes'**
  String get modelSizeTiny;

  /// No description provided for @modelSizeBase.
  ///
  /// In en, this message translates to:
  /// **'Faster processing, decent accuracy'**
  String get modelSizeBase;

  /// No description provided for @modelSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Good balance of speed and accuracy'**
  String get modelSizeSmall;

  /// No description provided for @modelSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Excellent accuracy for most use cases'**
  String get modelSizeMedium;

  /// No description provided for @modelSizeLargeTurbo.
  ///
  /// In en, this message translates to:
  /// **'Best accuracy with optimized speed'**
  String get modelSizeLargeTurbo;

  /// No description provided for @modelSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Maximum accuracy, needs more resources'**
  String get modelSizeLarge;

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
  /// **'Accurate and reliable for everyday dictation. Works on most devices.'**
  String get qualityTierBalancedDesc;

  /// No description provided for @qualityTierPremiumLabel.
  ///
  /// In en, this message translates to:
  /// **'Best Quality'**
  String get qualityTierPremiumLabel;

  /// No description provided for @qualityTierPremiumDesc.
  ///
  /// In en, this message translates to:
  /// **'Top accuracy for longer dictation and complex content. Needs a capable GPU.'**
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
  /// **'Download & Continue'**
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
  /// **'Best quality — takes ~{ratio}x longer to process'**
  String qualityTierInfoSlow(String ratio);

  /// No description provided for @qualityTierInfoSlowerThanCompact.
  ///
  /// In en, this message translates to:
  /// **'Best quality — ~{ratio}x slower than Small'**
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
  /// **'Speech engine is being prepared. Please wait a moment.'**
  String get infoEngineDownloading;

  /// No description provided for @infoEngineAutoDownload.
  ///
  /// In en, this message translates to:
  /// **'Speech engine missing — downloading automatically…'**
  String get infoEngineAutoDownload;

  /// No description provided for @infoModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Please download a speech model in Settings first.'**
  String get infoModelMissing;

  /// No description provided for @oomRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording failed — GPU memory issue'**
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
  /// **'Quality reduced — your GPU ran out of memory. Switched to a lighter model.'**
  String get infoSttCudaOomFallbackModel;

  /// No description provided for @infoSttCudaOomFallbackCpu.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Switched to CPU mode for reliability.'**
  String get infoSttCudaOomFallbackCpu;

  /// No description provided for @errorSttServerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Speech engine not found. Please download a speech model in Settings.'**
  String get errorSttServerNotFound;

  /// No description provided for @errorSttServerConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Speech engine stopped unexpectedly. Please try again.'**
  String get errorSttServerConnectionLost;

  /// No description provided for @errorSttCudaOom.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Quality was reduced so the next try should work.'**
  String get errorSttCudaOom;

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
  /// **'Could not start recording — please try again'**
  String get errorRecordingFailed;

  /// No description provided for @errorNoAudioRecorded.
  ///
  /// In en, this message translates to:
  /// **'No audio recorded — please try again'**
  String get errorNoAudioRecorded;

  /// No description provided for @errorTranscriptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Transcription returned empty text — please try again'**
  String get errorTranscriptionEmpty;

  /// No description provided for @errorSttServerFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech engine failed to start'**
  String get errorSttServerFailed;

  /// No description provided for @errorSttModelIncompatibleRuntime.
  ///
  /// In en, this message translates to:
  /// **'Speech model is incompatible with the installed runtime. Please re-download the speech model in Settings.'**
  String get errorSttModelIncompatibleRuntime;

  /// No description provided for @errorSttModelCorruptedRedownloading.
  ///
  /// In en, this message translates to:
  /// **'Speech model appears corrupted — downloading a fresh copy automatically.'**
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
  /// **'Speech engine failed on both GPU and CPU. Please restart the app or re-download the model.'**
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
  /// **'Speech engine is still starting. Please try again in a moment.'**
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

  /// No description provided for @historyAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get historyAddNote;

  /// No description provided for @historyNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get historyNotes;

  /// No description provided for @historyNotePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write a note…'**
  String get historyNotePlaceholder;

  /// No description provided for @historyNoteAdded.
  ///
  /// In en, this message translates to:
  /// **'Note added'**
  String get historyNoteAdded;

  /// No description provided for @historyNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
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
  /// **'Add a note'**
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

  /// No description provided for @historySearchHintCommands.
  ///
  /// In en, this message translates to:
  /// **'Search transcriptions…'**
  String get historySearchHintCommands;

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

  /// No description provided for @settingsDefaultSttProvider.
  ///
  /// In en, this message translates to:
  /// **'Default Cloud STT'**
  String get settingsDefaultSttProvider;

  /// No description provided for @settingsDefaultSttProviderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cloud speech recognition service'**
  String get settingsDefaultSttProviderSubtitle;

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

  /// No description provided for @settingsTextReplacements.
  ///
  /// In en, this message translates to:
  /// **'Text Replacements'**
  String get settingsTextReplacements;

  /// No description provided for @settingsTextReplacementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically replace specific words or phrases after transcription'**
  String get settingsTextReplacementsSubtitle;

  /// No description provided for @settingsTextReplacementsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Text Replacements'**
  String get settingsTextReplacementsEnabled;

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

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

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

  /// No description provided for @onboardingStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepOf(int current, int total);

  /// No description provided for @onboardingThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get onboardingThemeLight;

  /// No description provided for @onboardingThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get onboardingThemeDark;

  /// No description provided for @onboardingThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get onboardingThemeSystem;

  /// No description provided for @onboardingMicTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your microphone'**
  String get onboardingMicTitle;

  /// No description provided for @onboardingMicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We need mic access so you can dictate. Your audio stays on your device.'**
  String get onboardingMicSubtitle;

  /// No description provided for @onboardingMicPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set — microphone ready!'**
  String get onboardingMicPermissionGranted;

  /// No description provided for @onboardingMicPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access denied'**
  String get onboardingMicPermissionDenied;

  /// No description provided for @onboardingMicPermissionPending.
  ///
  /// In en, this message translates to:
  /// **'Tap below to enable your microphone'**
  String get onboardingMicPermissionPending;

  /// No description provided for @onboardingMicRequestAccess.
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get onboardingMicRequestAccess;

  /// No description provided for @onboardingMicTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Your Microphone'**
  String get onboardingMicTestTitle;

  /// No description provided for @onboardingMicTestHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to start a test recording'**
  String get onboardingMicTestHint;

  /// No description provided for @onboardingMicTestRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording… speak now'**
  String get onboardingMicTestRecording;

  /// No description provided for @onboardingMicTestDone.
  ///
  /// In en, this message translates to:
  /// **'Sounds great — your mic is working perfectly!'**
  String get onboardingMicTestDone;

  /// No description provided for @onboardingMicDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio Input Device'**
  String get onboardingMicDeviceLabel;

  /// No description provided for @onboardingMicDeniedInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open your system settings to grant microphone access'**
  String get onboardingMicDeniedInstructions;

  /// No description provided for @onboardingModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up speech recognition'**
  String get onboardingModelTitle;

  /// No description provided for @onboardingModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download the speech engine to dictate offline — your voice never leaves your device.'**
  String get onboardingModelSubtitle;

  /// No description provided for @onboardingModelRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended for your device'**
  String get onboardingModelRecommended;

  /// No description provided for @onboardingModelChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can adjust quality later in Settings'**
  String get onboardingModelChangeLater;

  /// No description provided for @onboardingModelUseCloud.
  ///
  /// In en, this message translates to:
  /// **'Skip — I\'ll use a cloud service instead'**
  String get onboardingModelUseCloud;

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

  /// No description provided for @onboardingReadyStep3.
  ///
  /// In en, this message translates to:
  /// **'Text is copied to clipboard automatically'**
  String get onboardingReadyStep3;

  /// No description provided for @onboardingReadyChangeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Change Hotkey'**
  String get onboardingReadyChangeHotkey;

  /// No description provided for @onboardingReadyCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
  String get onboardingReadyCurrentHotkey;

  /// No description provided for @onboardingStartDictating.
  ///
  /// In en, this message translates to:
  /// **'Start Dictating'**
  String get onboardingStartDictating;

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

  /// No description provided for @commandPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Type a command…'**
  String get commandPaletteHint;

  /// No description provided for @commandPaletteNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get commandPaletteNoResults;

  /// No description provided for @commandPaletteExportText.
  ///
  /// In en, this message translates to:
  /// **'Export as text file'**
  String get commandPaletteExportText;

  /// No description provided for @commandPaletteExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String commandPaletteExported(String path);

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
  /// **'Update ready — click to install'**
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
  /// **'Too many requests — try again later'**
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

  /// No description provided for @settingsOverlayAutoHide.
  ///
  /// In en, this message translates to:
  /// **'Auto-hide delay'**
  String get settingsOverlayAutoHide;

  /// No description provided for @settingsOverlayAutoHideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long the overlay stays visible after completion'**
  String get settingsOverlayAutoHideSubtitle;

  /// No description provided for @settingsOverlayAutoHide2s.
  ///
  /// In en, this message translates to:
  /// **'2 seconds'**
  String get settingsOverlayAutoHide2s;

  /// No description provided for @settingsOverlayAutoHide5s.
  ///
  /// In en, this message translates to:
  /// **'5 seconds'**
  String get settingsOverlayAutoHide5s;

  /// No description provided for @settingsOverlayAutoHide10s.
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get settingsOverlayAutoHide10s;

  /// No description provided for @settingsOverlayAutoHideManual.
  ///
  /// In en, this message translates to:
  /// **'Until dismissed'**
  String get settingsOverlayAutoHideManual;

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

  /// No description provided for @overlayContextHide.
  ///
  /// In en, this message translates to:
  /// **'Hide overlay'**
  String get overlayContextHide;

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
  /// **'How long the speech engine stays loaded after use'**
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
  /// **'Hotkey registration failed — please re-bind your shortcut in Settings.'**
  String get hotkeyRegistrationFailed;

  /// No description provided for @hotkeyRegistrationFailedDefaultActive.
  ///
  /// In en, this message translates to:
  /// **'Hotkey registration failed — using Ctrl+Shift+Space as fallback. Please re-bind in Settings.'**
  String get hotkeyRegistrationFailedDefaultActive;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

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
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
