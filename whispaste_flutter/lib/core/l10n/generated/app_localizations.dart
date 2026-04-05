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
  /// **'Pinned'**
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
  /// **'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.\n\n🔒 All data stays on your device.'**
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
  /// **'Pin to top'**
  String get historyPinToTop;

  /// No description provided for @historyUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
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

  /// No description provided for @settingsPostProcessing.
  ///
  /// In en, this message translates to:
  /// **'Text Enhancement'**
  String get settingsPostProcessing;

  /// No description provided for @settingsPostProcessingHint.
  ///
  /// In en, this message translates to:
  /// **'Improve your dictated text automatically using AI.'**
  String get settingsPostProcessingHint;

  /// No description provided for @settingsTextEnhancementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Improve your dictated text automatically'**
  String get settingsTextEnhancementSubtitle;

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

  /// No description provided for @settingsPresetCleanup.
  ///
  /// In en, this message translates to:
  /// **'Clean up'**
  String get settingsPresetCleanup;

  /// No description provided for @settingsPresetConcise.
  ///
  /// In en, this message translates to:
  /// **'Make concise'**
  String get settingsPresetConcise;

  /// No description provided for @settingsPresetTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get settingsPresetTranslate;

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

  /// No description provided for @settingsOverlayFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'Overlay & Floating Button'**
  String get settingsOverlayFloatingButton;

  /// No description provided for @settingsOverlayFloatingButtonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On-screen recording controls'**
  String get settingsOverlayFloatingButtonSubtitle;

  /// No description provided for @settingsShowOverlay.
  ///
  /// In en, this message translates to:
  /// **'Show Overlay'**
  String get settingsShowOverlay;

  /// No description provided for @settingsShowFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'Show Floating Button'**
  String get settingsShowFloatingButton;

  /// No description provided for @settingsFloatingButtonOpacity.
  ///
  /// In en, this message translates to:
  /// **'Floating Button Opacity'**
  String get settingsFloatingButtonOpacity;

  /// No description provided for @settingsFloatingButtonSize.
  ///
  /// In en, this message translates to:
  /// **'Floating Button Size'**
  String get settingsFloatingButtonSize;

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

  /// No description provided for @settingsAnthropicApiKey.
  ///
  /// In en, this message translates to:
  /// **'Anthropic API Key'**
  String get settingsAnthropicApiKey;

  /// No description provided for @settingsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvanced;

  /// No description provided for @settingsPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your recordings and text stay on your device by default. Cloud services are only used when you explicitly enable them.'**
  String get settingsPrivacyNote;

  /// No description provided for @settingsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOff;

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
  /// **'No audio detected — microphone may not be working.'**
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
  /// **'Welcome to WhisPaste'**
  String get onboardingWelcome;

  /// No description provided for @onboardingWelcomeHint.
  ///
  /// In en, this message translates to:
  /// **'Premium dictation with AI post-processing. Dictate anywhere, paste everywhere.'**
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
