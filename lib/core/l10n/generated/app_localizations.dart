import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_he.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';

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
    Locale('es'),
    Locale('he'),
    Locale('pt'),
    Locale('ru'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste'**
  String get appName;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
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
  /// **'Dictionary'**
  String get navReplacements;

  /// No description provided for @navSnippets.
  ///
  /// In en, this message translates to:
  /// **'Snippets'**
  String get navSnippets;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get navAnalytics;

  /// No description provided for @navHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get navHelp;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// Screen reader name of an open button that opens the named target, e.g. 'Open Privacy policy'.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String actionOpenNamed(String name);

  /// No description provided for @helpTabManual.
  ///
  /// In en, this message translates to:
  /// **'Handbook'**
  String get helpTabManual;

  /// No description provided for @helpTabIntro.
  ///
  /// In en, this message translates to:
  /// **'Introduction'**
  String get helpTabIntro;

  /// No description provided for @helpTabSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get helpTabSupport;

  /// No description provided for @helpTabDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get helpTabDiagnostics;

  /// No description provided for @manualSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search the handbook'**
  String get manualSearchHint;

  /// No description provided for @manualSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chapter matches this search.'**
  String get manualSearchEmpty;

  /// Live status under the handbook search: how many chapters match.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No chapters found} =1{1 chapter found} other{{count} chapters found}}'**
  String manualSearchResultCount(int count);

  /// No description provided for @navFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get navFeedback;

  /// No description provided for @pageHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get pageHistoryTitle;

  /// No description provided for @pageSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get pageSettingsTitle;

  /// No description provided for @pageReplacementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get pageReplacementsTitle;

  /// No description provided for @pageAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get pageAnalyticsTitle;

  /// No description provided for @pageAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About WhisPaste'**
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

  /// No description provided for @historyPrivacyGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings hidden'**
  String get historyPrivacyGateTitle;

  /// No description provided for @historyPrivacyGateHint.
  ///
  /// In en, this message translates to:
  /// **'Transcriptions and audio are only hidden, not deleted, until you choose to show them.'**
  String get historyPrivacyGateHint;

  /// No description provided for @historyPrivacyGateShow.
  ///
  /// In en, this message translates to:
  /// **'Show recordings'**
  String get historyPrivacyGateShow;

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
  /// **'This week'**
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
  /// **'Delete permanently'**
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

  /// Success toast after a history export. {path} is the full path of the written file.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String historyExportDone(String path);

  /// Error toast when a history export fails. Gives the next step instead of the raw system error.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Check that the target folder is writable and try again.'**
  String get historyExportFailed;

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
  /// **'Speech model'**
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

  /// Approximate word count shown in a history list row. Plural-aware: the count selects the form, so a translator can phrase '1 word' differently from 'N words'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{approx. 1 word} other{approx. {count} words}}'**
  String historyListWordCount(int count);

  /// Tooltip and label of the single overflow button that replaces the selection, sort and view controls when the History filter row is too narrow for them.
  ///
  /// In en, this message translates to:
  /// **'View and selection'**
  String get historyToolsMenu;

  /// No description provided for @historyEditing.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get historyEditing;

  /// No description provided for @historySearchTranscriptions.
  ///
  /// In en, this message translates to:
  /// **'Search recordings…'**
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
  /// **'No entries match \"{query}\".\nTry a different search term.'**
  String historyNoResultsHint(String query);

  /// No description provided for @historyTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get historyTrashEmpty;

  /// No description provided for @historyTrashEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Deleted transcriptions will appear here.\n{days, plural, =0{Items stay until you delete them for good.} =1{Items are permanently removed after 1 day.} other{Items are permanently removed after {days} days.}}'**
  String historyTrashEmptyHint(int days);

  /// No description provided for @historyEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get historyEmptyTrash;

  /// No description provided for @historyEmptyTrashConfirm.
  ///
  /// In en, this message translates to:
  /// **'Empty trash?'**
  String get historyEmptyTrashConfirm;

  /// No description provided for @historyEmptyTrashConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transcription will be permanently deleted. Any saved audio file for it is removed no later than 30 days after recording. This action cannot be undone.} other{{count} transcriptions will be permanently deleted. Any saved audio files for them are removed no later than 30 days after recording. This action cannot be undone.}}'**
  String historyEmptyTrashConfirmMessage(int count);

  /// No description provided for @historyDeletePermanentlyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get historyDeletePermanentlyConfirm;

  /// No description provided for @historyDeletePermanentlyConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transcription and its saved audio will be permanently deleted. This action cannot be undone.} other{{count} transcriptions and their saved audio will be permanently deleted. This action cannot be undone.}}'**
  String historyDeletePermanentlyConfirmMessage(int count);

  /// Success toast after emptying the trash. The count is a placeholder inside the message rather than a parenthesis appended in Dart: a translator has to be able to move it (Hebrew reads right-to-left, so a trailing '(3)' lands on the wrong side of the sentence) and to choose the plural form for it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Trash emptied — 1 transcription deleted} other{Trash emptied — {count} transcriptions deleted}}'**
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

  /// Confirmation after a single entry is restored from the trash or taken out of the archive.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get historyRestored;

  /// No description provided for @historyBulkArchived.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transcription archived} other{{count} transcriptions archived}}'**
  String historyBulkArchived(int count);

  /// No description provided for @historyBulkMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transcription moved to trash} other{{count} transcriptions moved to trash}}'**
  String historyBulkMovedToTrash(int count);

  /// No description provided for @historyBulkRestored.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transcription restored} other{{count} transcriptions restored}}'**
  String historyBulkRestored(int count);

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

  /// Action in an empty history filter view that resets the filter to All.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get historyShowAll;

  /// Tooltip and screen reader name of the overflow menu in the history detail header.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get historyMoreActions;

  /// Field label 'Tags' in the Markdown copy of a history entry.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get historyMdTags;

  /// Field label 'Date' in the Markdown copy of a history entry.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get historyMdDate;

  /// Field label 'Model' in the Markdown copy of a history entry.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get historyMdModel;

  /// No description provided for @historyPinToTop.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get historyPinToTop;

  /// No description provided for @historyUnpin.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
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
  /// **'Select all'**
  String get historySelectAll;

  /// No description provided for @historyDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
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

  /// Switch in Interface settings that lifts a 'Never ask again' choice for the rating reminder.
  ///
  /// In en, this message translates to:
  /// **'Show the rating reminder again'**
  String get settingsReviewPromptRestore;

  /// Subtitle of the rating reminder switch: explains that the usual pauses still apply.
  ///
  /// In en, this message translates to:
  /// **'You chose “Never ask again”. Turning this on allows the reminder again; the usual pauses still apply.'**
  String get settingsReviewPromptRestoreSubtitle;

  /// No description provided for @settingsLaunchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Launch at startup'**
  String get settingsLaunchAtStartup;

  /// No description provided for @settingsStartMinimized.
  ///
  /// In en, this message translates to:
  /// **'Start minimized'**
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
  /// **'Show notifications'**
  String get settingsShowNotifications;

  /// No description provided for @settingsShowBackendUtilization.
  ///
  /// In en, this message translates to:
  /// **'Processing indicator in status bar'**
  String get settingsShowBackendUtilization;

  /// No description provided for @settingsShowBackendUtilizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows whether the processor or the graphics card is doing the work.'**
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
  /// **'Microphone sensitivity'**
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
  /// **'Hold to record'**
  String get settingsHoldToRecord;

  /// No description provided for @pushToTalkUnavailableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get pushToTalkUnavailableTooltip;

  /// Tooltip on the disabled push-to-talk switch on Linux when neither XInput2 nor the GlobalShortcuts portal reports key-up. Keep the CLI command whispaste --toggle untranslated.
  ///
  /// In en, this message translates to:
  /// **'Your desktop doesn\'t report key releases here. Bind “whispaste --toggle” to a key combination in your system settings instead.'**
  String get pushToTalkUnavailableLinuxTooltip;

  /// Badge next to a settings option that works but is not yet verified on every desktop (e.g. Linux push-to-talk).
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get settingsExperimentalBadge;

  /// No description provided for @settingsHoldOrTap.
  ///
  /// In en, this message translates to:
  /// **'Tap or hold'**
  String get settingsHoldOrTap;

  /// No description provided for @settingsHoldOrTapHint.
  ///
  /// In en, this message translates to:
  /// **'A short tap starts and stops recording; holding records until you let go.'**
  String get settingsHoldOrTapHint;

  /// No description provided for @settingsSpeechRecognition.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition'**
  String get settingsSpeechRecognition;

  /// No description provided for @settingsSpeechRecognitionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition quality and service'**
  String get settingsSpeechRecognitionSubtitle;

  /// No description provided for @settingsService.
  ///
  /// In en, this message translates to:
  /// **'Recognition runs on'**
  String get settingsService;

  /// No description provided for @settingsQuality.
  ///
  /// In en, this message translates to:
  /// **'Speed & accuracy'**
  String get settingsQuality;

  /// No description provided for @settingsRecordingSafety.
  ///
  /// In en, this message translates to:
  /// **'Recording safety'**
  String get settingsRecordingSafety;

  /// No description provided for @settingsRecordingSafetySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic checks and safeguards'**
  String get settingsRecordingSafetySubtitle;

  /// No description provided for @settingsDeadMicTimeout.
  ///
  /// In en, this message translates to:
  /// **'Silent mic detection'**
  String get settingsDeadMicTimeout;

  /// No description provided for @settingsDeadMicTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'Stop recording if no audio detected within this time (seconds). 0 = disabled.'**
  String get settingsDeadMicTimeoutHint;

  /// No description provided for @settingsAutoStopSilence.
  ///
  /// In en, this message translates to:
  /// **'Auto-Stop after silence'**
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
  /// **'System default'**
  String get settingsMicSystemDefault;

  /// No description provided for @settingsMicSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Audio input is managed by your system settings'**
  String get settingsMicSystemHint;

  /// No description provided for @settingsServiceOnDevicePrivate.
  ///
  /// In en, this message translates to:
  /// **'Locally on device'**
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
  /// **'Sound & feedback'**
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
  /// **'Record start sound'**
  String get settingsRecordStartSound;

  /// No description provided for @settingsRecordStopSound.
  ///
  /// In en, this message translates to:
  /// **'Record stop sound'**
  String get settingsRecordStopSound;

  /// No description provided for @settingsTranscriptionCompleteSound.
  ///
  /// In en, this message translates to:
  /// **'Transcription complete sound'**
  String get settingsTranscriptionCompleteSound;

  /// No description provided for @settingsDurationWarningSound.
  ///
  /// In en, this message translates to:
  /// **'Duration limit warning'**
  String get settingsDurationWarningSound;

  /// No description provided for @settingsSoundVolume.
  ///
  /// In en, this message translates to:
  /// **'Sound volume'**
  String get settingsSoundVolume;

  /// No description provided for @settingsAfterTranscription.
  ///
  /// In en, this message translates to:
  /// **'After transcription'**
  String get settingsAfterTranscription;

  /// No description provided for @settingsAfterTranscriptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What happens with the transcribed text'**
  String get settingsAfterTranscriptionSubtitle;

  /// No description provided for @settingsAfterTranscriptionActionLabel.
  ///
  /// In en, this message translates to:
  /// **'After recording'**
  String get settingsAfterTranscriptionActionLabel;

  /// No description provided for @settingsAfterTranscriptionClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get settingsAfterTranscriptionClipboard;

  /// No description provided for @settingsAfterTranscriptionPaste.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste at cursor'**
  String get settingsAfterTranscriptionPaste;

  /// No description provided for @settingsAfterTranscriptionBoth.
  ///
  /// In en, this message translates to:
  /// **'Copy & Auto-Paste'**
  String get settingsAfterTranscriptionBoth;

  /// No description provided for @settingsAfterTranscriptionNothing.
  ///
  /// In en, this message translates to:
  /// **'Do nothing'**
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
  /// **'Auto-Paste failed. The transcript is on the clipboard, paste it manually with {paste}.'**
  String pasteFailureGeneric(String paste);

  /// No description provided for @pasteFailureOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get pasteFailureOpenSettings;

  /// No description provided for @pendingAudioSaveLater.
  ///
  /// In en, this message translates to:
  /// **'The recording could not be saved to Recordings. The audio is kept and saved again the next time WhisPaste starts.'**
  String get pendingAudioSaveLater;

  /// No description provided for @pendingAudioRecovered.
  ///
  /// In en, this message translates to:
  /// **'A recording that could not be saved before is now in Recordings.'**
  String get pendingAudioRecovered;

  /// No description provided for @pasteNotificationNoTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Auto-Paste skipped'**
  String get pasteNotificationNoTargetTitle;

  /// No description provided for @pasteNotificationNoTargetBody.
  ///
  /// In en, this message translates to:
  /// **'No target app detected. Focus the destination app first, then start recording. The text is on the clipboard.'**
  String get pasteNotificationNoTargetBody;

  /// No description provided for @pasteNotificationNoTargetTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste: Target app missing'**
  String get pasteNotificationNoTargetTray;

  /// No description provided for @silentMicrophoneNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: No microphone signal'**
  String get silentMicrophoneNotificationTitle;

  /// No description provided for @silentMicrophoneNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'The microphone delivers no sound. Check the selected microphone or whether it is muted. Recording continues.'**
  String get silentMicrophoneNotificationBody;

  /// No description provided for @pasteNotificationRestartNeededTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Restart needed'**
  String get pasteNotificationRestartNeededTitle;

  /// No description provided for @pasteNotificationRestartNeededBody.
  ///
  /// In en, this message translates to:
  /// **'The permission was granted, but WhisPaste is still running the old state. Click here to restart WhisPaste.'**
  String get pasteNotificationRestartNeededBody;

  /// No description provided for @pasteNotificationRestartNeededTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked — restart needed'**
  String get pasteNotificationRestartNeededTray;

  /// No description provided for @pasteNotificationPermissionBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Auto-Paste blocked'**
  String get pasteNotificationPermissionBlockedTitle;

  /// No description provided for @pasteNotificationPermissionResetEntryBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'. Click here: WhisPaste will clear a possibly stale entry and let macOS ask again.'**
  String get pasteNotificationPermissionResetEntryBody;

  /// No description provided for @pasteNotificationPermissionOpenSettingsBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste needs permission to insert text into other apps — macOS calls this permission \'Accessibility\'. Click here or the tray icon to open System Settings.'**
  String get pasteNotificationPermissionOpenSettingsBody;

  /// No description provided for @pasteNotificationPermissionBlockedTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked — open System Settings'**
  String get pasteNotificationPermissionBlockedTray;

  /// No description provided for @pasteNotificationElevationBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Auto-Paste blocked'**
  String get pasteNotificationElevationBlockedTitle;

  /// No description provided for @pasteNotificationElevationBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'The target app is running with administrator rights. Restart WhisPaste as an administrator too, to paste into that app.'**
  String get pasteNotificationElevationBlockedBody;

  /// No description provided for @pasteNotificationElevationBlockedTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked — administrator needed'**
  String get pasteNotificationElevationBlockedTray;

  /// No description provided for @pasteNotificationFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Auto-Paste failed'**
  String get pasteNotificationFailedTitle;

  /// No description provided for @pasteNotificationFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The system blocked the paste key. The text is on the clipboard. Paste it yourself with {paste}.'**
  String pasteNotificationFailedBody(String paste);

  /// No description provided for @pasteNotificationFailedTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste failed'**
  String get pasteNotificationFailedTray;

  /// No description provided for @pasteNotificationLinuxUinputBody.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste can\'t use the virtual keyboard device /dev/uinput yet. The text is on the clipboard, paste it with {paste}. Click here to set it up.'**
  String pasteNotificationLinuxUinputBody(String paste);

  /// No description provided for @pasteNotificationLinuxUinputTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked — setup needed'**
  String get pasteNotificationLinuxUinputTray;

  /// No description provided for @pasteNotificationLinuxNoDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste unavailable: this system has no virtual keyboard device for it. The text is on the clipboard, paste it with {paste}. Click here for the Auto-Paste settings.'**
  String pasteNotificationLinuxNoDeviceBody(String paste);

  /// No description provided for @pasteNotificationLinuxNoDeviceTray.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste unavailable'**
  String get pasteNotificationLinuxNoDeviceTray;

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
  /// **'Your text lands right at the cursor.'**
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

  /// No description provided for @pasteCapabilityUnavailableLinux.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste isn\'t possible here right now'**
  String get pasteCapabilityUnavailableLinux;

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

  /// No description provided for @pasteStaleEntryGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the old WhisPaste entry'**
  String get pasteStaleEntryGuideTitle;

  /// No description provided for @pasteStaleEntryGuideBody.
  ///
  /// In en, this message translates to:
  /// **'macOS is still holding on to the Auto-Paste permission of an earlier WhisPaste version. That entry can\'t be switched on — it has to be removed once:\n\n1. Select “WhisPaste” in the list.\n2. Click “−” below the list.\n3. Come back to WhisPaste.\n\nAfter a restart, macOS asks you again — just allow it.'**
  String get pasteStaleEntryGuideBody;

  /// No description provided for @pasteStaleEntryGuideConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get pasteStaleEntryGuideConfirm;

  /// No description provided for @pasteStaleEntryRestartTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart WhisPaste'**
  String get pasteStaleEntryRestartTitle;

  /// No description provided for @pasteStaleEntryRestartBody.
  ///
  /// In en, this message translates to:
  /// **'Once the old entry is gone, restart WhisPaste. macOS then asks for the permission again — confirm it and switch WhisPaste on.'**
  String get pasteStaleEntryRestartBody;

  /// No description provided for @pasteStaleEntryRestartConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restart WhisPaste'**
  String get pasteStaleEntryRestartConfirm;

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
  /// **'WhisPaste inserts your text right at the cursor. macOS requires one switch for that which only you can flip: System Settings → Privacy & Security → Accessibility. Confirm to open exactly that page — WhisPaste detects your approval automatically and restarts itself afterwards if needed.'**
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
  /// **'No permission needed on Windows — just choose whether WhisPaste should insert your text for you.'**
  String get onboardingPasteSubtitleWin;

  /// Auto-Paste page subtitle on Linux, which has no system permission dialog.
  ///
  /// In en, this message translates to:
  /// **'On Linux no system dialog asks for permission. Below you can see whether you need to set up anything for it.'**
  String get onboardingPasteSubtitleLinux;

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
  /// **'Auto-Paste presses Ctrl+V for you after each recording, so the text lands right where you\'re typing. Verified working on this machine — turn it on below.'**
  String get onboardingPasteWhyWin;

  /// No description provided for @onboardingPasteWhyWinUipi.
  ///
  /// In en, this message translates to:
  /// **'In programs running as administrator, Auto-Paste won\'t work. The text then stays on the clipboard, and you paste it yourself with Ctrl+V.'**
  String get onboardingPasteWhyWinUipi;

  /// No description provided for @onboardingPasteWinOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste is on'**
  String get onboardingPasteWinOnTitle;

  /// No description provided for @onboardingPasteWinOnDetail.
  ///
  /// In en, this message translates to:
  /// **'After each recording, WhisPaste presses Ctrl+V for you — the text lands right at your cursor. A copy stays on the clipboard, too.'**
  String get onboardingPasteWinOnDetail;

  /// No description provided for @onboardingPasteLinuxNative.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste needs your permission for the virtual keyboard (/dev/uinput). With the .deb package, choose “Allow (administrator password)” and enter your administrator password; otherwise copy the command and run it once in a terminal. You can remove the permission again in the settings.'**
  String get onboardingPasteLinuxNative;

  /// No description provided for @onboardingPasteLinuxFlatpak.
  ///
  /// In en, this message translates to:
  /// **'In the Flatpak build, --device=all makes /dev/input/* and /dev/uinput visible inside the sandbox. WhisPaste itself reads no input devices. If your user has read rights on the host (e.g. as a member of the input group), the app could read keystrokes of other programs. Auto-paste also needs write access to /dev/uinput on the host: copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules, which gives access only to the signed-in session. The command needs administrator rights (sudo) and changes the system. If you do not want this, leave auto-paste off and paste the text by hand.'**
  String get onboardingPasteLinuxFlatpak;

  /// No description provided for @onboardingPasteLinuxSnap.
  ///
  /// In en, this message translates to:
  /// **'In the Snap build, run this once in a terminal: sudo snap connect whispaste:uinput. Until then, auto-paste only copies the text.'**
  String get onboardingPasteLinuxSnap;

  /// No description provided for @onboardingPasteLinuxAppImage.
  ///
  /// In en, this message translates to:
  /// **'The AppImage needs access to /dev/uinput (the virtual keyboard device). Copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/ and runs sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. The rule gives write access only to the signed-in session. The command needs administrator rights (sudo) and changes the system. Until then, auto-paste only copies the text.'**
  String get onboardingPasteLinuxAppImage;

  /// No description provided for @onboardingPasteWinEnableCta.
  ///
  /// In en, this message translates to:
  /// **'Turn on Auto-Paste'**
  String get onboardingPasteWinEnableCta;

  /// No description provided for @onboardingPasteWinAdminCaveat.
  ///
  /// In en, this message translates to:
  /// **'In programs running as administrator, Auto-Paste won\'t work. The text then stays on the clipboard, and you paste it yourself with Ctrl+V.'**
  String get onboardingPasteWinAdminCaveat;

  /// No description provided for @onboardingPasteLinuxClipboardFallback.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste is on. Until access is set up, WhisPaste puts the text on the clipboard, and you paste it yourself with Ctrl+V.'**
  String get onboardingPasteLinuxClipboardFallback;

  /// No description provided for @onboardingPasteLinuxUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'The text goes to the clipboard. Paste it with {shortcut}.'**
  String onboardingPasteLinuxUnavailableDetail(Object shortcut);

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
  /// **'Recording overlay'**
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
  /// **'Floating (always visible)'**
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
  /// **'Where the recording overlay appears when recording starts'**
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
  /// **'Floating button'**
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
  /// **'Recognition language'**
  String get settingsRecognitionLanguage;

  /// No description provided for @settingsCustomVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Custom vocabulary'**
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

  /// No description provided for @settingsCustomVocabularyBudgetCounter.
  ///
  /// In en, this message translates to:
  /// **'~{count} of {budget} used'**
  String settingsCustomVocabularyBudgetCounter(int count, int budget);

  /// No description provided for @settingsCustomVocabularyBudgetWarning.
  ///
  /// In en, this message translates to:
  /// **'If the list takes up more than {budget}, the rest is left out automatically.'**
  String settingsCustomVocabularyBudgetWarning(int budget);

  /// No description provided for @settingsPunctuationPriming.
  ///
  /// In en, this message translates to:
  /// **'Punctuation priming'**
  String get settingsPunctuationPriming;

  /// No description provided for @settingsPunctuationPrimingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Makes the recognition more likely to add punctuation when no custom vocabulary is set. Speed is not affected.'**
  String get settingsPunctuationPrimingSubtitle;

  /// No description provided for @settingsVadEnabled.
  ///
  /// In en, this message translates to:
  /// **'Trim trailing silence'**
  String get settingsVadEnabled;

  /// No description provided for @settingsVadEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cuts long silence and noise at the end of a recording, so the recognition can\'t invent a closing sentence (e.g. “Thanks for watching”).'**
  String get settingsVadEnabledSubtitle;

  /// No description provided for @settingsStripPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Strip punctuation'**
  String get settingsStripPunctuation;

  /// No description provided for @settingsStripPunctuationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes periods, commas, and other sentence punctuation from every transcript before it\'s saved or pasted. Numbers like 3.5 stay as they are. Works the same for every recognition method.'**
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

  /// No description provided for @settingsRemoveFillerWords.
  ///
  /// In en, this message translates to:
  /// **'Remove filler words'**
  String get settingsRemoveFillerWords;

  /// No description provided for @settingsRemoveFillerWordsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes hesitation sounds such as \"uh\", \"um\" and \"erm\" before the transcript is saved or pasted. Only unambiguous English and German fillers; words that can carry meaning are never touched.'**
  String get settingsRemoveFillerWordsSubtitle;

  /// No description provided for @settingsVoiceLineBreaks.
  ///
  /// In en, this message translates to:
  /// **'Spoken line breaks'**
  String get settingsVoiceLineBreaks;

  /// No description provided for @settingsVoiceLineBreaksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turns spoken commands such as \"new paragraph\" and \"new line\" into real line breaks. Uses the transcription language, or all supported languages with auto-detect.'**
  String get settingsVoiceLineBreaksSubtitle;

  /// No description provided for @settingsSpokenPunctuation.
  ///
  /// In en, this message translates to:
  /// **'Spoken punctuation'**
  String get settingsSpokenPunctuation;

  /// No description provided for @settingsSpokenPunctuationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If you say \"comma\" or \"full stop\" as a word in a sentence, check the text afterwards.'**
  String get settingsSpokenPunctuationSubtitle;

  /// No description provided for @settingsAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsAppLanguage;

  /// No description provided for @settingsSttModels.
  ///
  /// In en, this message translates to:
  /// **'Speech models'**
  String get settingsSttModels;

  /// No description provided for @settingsOpenAiApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key'**
  String get settingsOpenAiApiKey;

  /// No description provided for @settingsDeepgramApiKey.
  ///
  /// In en, this message translates to:
  /// **'Deepgram API key'**
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
  /// **'Reset to defaults'**
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
  /// **'Reset everything'**
  String get settingsFactoryReset;

  /// No description provided for @settingsFactoryResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Factory reset'**
  String get settingsFactoryResetTitle;

  /// No description provided for @settingsFactoryResetMessage.
  ///
  /// In en, this message translates to:
  /// **'This immediately deletes: transcriptions with their tags and notes, saved audio files, Dictionary, Snippets, Statistics, API keys, downloaded models, logs and settings. The app will return to its initial state.\n\nThe app cannot restore any of it. Files are removed with a normal delete and not overwritten, so specialist tools may be able to recover parts of them.'**
  String get settingsFactoryResetMessage;

  /// No description provided for @settingsFactoryResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
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
  /// **'Stopping speech model…'**
  String get settingsFactoryResetPhaseStoppingSubprocess;

  /// No description provided for @settingsFactoryResetPhaseDeletingModels.
  ///
  /// In en, this message translates to:
  /// **'Deleting voice models…'**
  String get settingsFactoryResetPhaseDeletingModels;

  /// No description provided for @settingsFactoryResetPhaseDeletingAudio.
  ///
  /// In en, this message translates to:
  /// **'Deleting recordings…'**
  String get settingsFactoryResetPhaseDeletingAudio;

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
  /// **'The reset is incomplete. Affected: {areas}. You can try again.'**
  String settingsFactoryResetFailedMessage(String areas);

  /// No description provided for @factoryResetAreaDb.
  ///
  /// In en, this message translates to:
  /// **'Transcriptions, Notes, Dictionary, Snippets and Statistics'**
  String get factoryResetAreaDb;

  /// No description provided for @factoryResetAreaAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio files'**
  String get factoryResetAreaAudio;

  /// No description provided for @factoryResetAreaModels.
  ///
  /// In en, this message translates to:
  /// **'Models and logs'**
  String get factoryResetAreaModels;

  /// No description provided for @factoryResetAreaSecure.
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get factoryResetAreaSecure;

  /// No description provided for @factoryResetAreaSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get factoryResetAreaSettings;

  /// No description provided for @factoryResetAreaProcess.
  ///
  /// In en, this message translates to:
  /// **'Background process'**
  String get factoryResetAreaProcess;

  /// No description provided for @factoryResetRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get factoryResetRetryAction;

  /// No description provided for @factoryResetKeyringHint.
  ///
  /// In en, this message translates to:
  /// **'The API keys could not be removed from the keyring. If needed, delete the entries starting with “wp_” yourself in your system\'s password manager.'**
  String get factoryResetKeyringHint;

  /// No description provided for @settingsPortabilitySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & transfer'**
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
  /// **'This replaces your current settings — including interface, speech-model configuration, behavior, text replacements, and snippets — with the contents of {path}. Your API keys are left untouched.'**
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
  /// **'The cloud provider you used has been removed. Speech recognition now runs on this device.'**
  String get groqRemovedToast;

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

  /// No description provided for @statusSelectionEdited.
  ///
  /// In en, this message translates to:
  /// **'Selection edited'**
  String get statusSelectionEdited;

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

  /// No description provided for @unsavedInputTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get unsavedInputTitle;

  /// No description provided for @unsavedInputMessage.
  ///
  /// In en, this message translates to:
  /// **'The text you entered is not saved yet.'**
  String get unsavedInputMessage;

  /// No description provided for @unsavedInputDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get unsavedInputDiscard;

  /// No description provided for @trayUnavailableMinimizedHint.
  ///
  /// In en, this message translates to:
  /// **'The tray icon is unavailable. WhisPaste was minimized and keeps running.'**
  String get trayUnavailableMinimizedHint;

  /// No description provided for @settingsSaveFailedToast.
  ///
  /// In en, this message translates to:
  /// **'The setting could not be saved. The previous value is kept.'**
  String get settingsSaveFailedToast;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

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
  /// **'Send feedback'**
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

  /// Empty state title when the selected analytics period has no recordings. The period selector stays visible above it.
  ///
  /// In en, this message translates to:
  /// **'No recordings in this period'**
  String get analyticsNoRecordingsInPeriod;

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
  /// **'Total recordings'**
  String get analyticsTotalRecordings;

  /// No description provided for @analyticsTotalDuration.
  ///
  /// In en, this message translates to:
  /// **'Total duration'**
  String get analyticsTotalDuration;

  /// No description provided for @analyticsWordsDictated.
  ///
  /// In en, this message translates to:
  /// **'Words transcribed'**
  String get analyticsWordsDictated;

  /// No description provided for @analyticsTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Time saved (estimate)'**
  String get analyticsTimeSaved;

  /// No description provided for @analyticsAvgLatency.
  ///
  /// In en, this message translates to:
  /// **'Avg. time to text'**
  String get analyticsAvgLatency;

  /// No description provided for @analyticsRecordingActivity.
  ///
  /// In en, this message translates to:
  /// **'Recording activity'**
  String get analyticsRecordingActivity;

  /// No description provided for @analyticsLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get analyticsLast7Days;

  /// Shown above the 7-day activity chart when no recordings fall into the last 7 days.
  ///
  /// In en, this message translates to:
  /// **'No recordings in the last 7 days'**
  String get analyticsWeekEmpty;

  /// No description provided for @analyticsModelUsage.
  ///
  /// In en, this message translates to:
  /// **'Speech model usage'**
  String get analyticsModelUsage;

  /// Shown in the model usage panel when the selected period has no model data.
  ///
  /// In en, this message translates to:
  /// **'No model data in this period'**
  String get analyticsNoModelData;

  /// Screen reader label for the statistics loading skeleton.
  ///
  /// In en, this message translates to:
  /// **'Loading statistics'**
  String get analyticsLoading;

  /// No description provided for @analyticsDurationDistribution.
  ///
  /// In en, this message translates to:
  /// **'Duration distribution'**
  String get analyticsDurationDistribution;

  /// No description provided for @analyticsCostSavings.
  ///
  /// In en, this message translates to:
  /// **'Cost & savings'**
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

  /// Note under the cost and savings panel: the figures are estimates from list prices, not billed amounts.
  ///
  /// In en, this message translates to:
  /// **'Estimated from list prices per transcription'**
  String get analyticsEstimateNote;

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
  /// **'Reset statistics'**
  String get analyticsResetTitle;

  /// No description provided for @analyticsResetMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all analytics data? This action cannot be undone.'**
  String get analyticsResetMessage;

  /// No description provided for @analyticsResetDone.
  ///
  /// In en, this message translates to:
  /// **'Statistics were reset.'**
  String get analyticsResetDone;

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
  /// **'Edit replacement'**
  String get replacementsEditShortcut;

  /// No description provided for @replacementsNewShortcut.
  ///
  /// In en, this message translates to:
  /// **'New replacement'**
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

  /// Hint in the replacement dialog while no trigger phrase is entered
  ///
  /// In en, this message translates to:
  /// **'Add at least one trigger phrase.'**
  String get replacementsMissingTrigger;

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

  /// Hint in the replacement dialog while the replacement text is empty
  ///
  /// In en, this message translates to:
  /// **'Enter the replacement text.'**
  String get replacementsMissingReplacement;

  /// No description provided for @replacementsReplacementHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. by the way'**
  String get replacementsReplacementHint;

  /// No description provided for @replacementsReplacementHelper.
  ///
  /// In en, this message translates to:
  /// **'Use \\n for a line break and \\n\\n for a blank line. To keep a literal backslash-n, write \\\\n.'**
  String get replacementsReplacementHelper;

  /// No description provided for @replacementsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete replacement'**
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

  /// No description provided for @replacementsLearnedBadge.
  ///
  /// In en, this message translates to:
  /// **'Learned'**
  String get replacementsLearnedBadge;

  /// No description provided for @correctionLearningToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Learn from corrections'**
  String get correctionLearningToggleLabel;

  /// No description provided for @correctionLearningToggleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Watching repeated corrections for suggestions'**
  String get correctionLearningToggleEnabled;

  /// No description provided for @correctionLearningToggleDisabled.
  ///
  /// In en, this message translates to:
  /// **'Not watching corrections for suggestions'**
  String get correctionLearningToggleDisabled;

  /// No description provided for @correctionLearningHowTo.
  ///
  /// In en, this message translates to:
  /// **'While recording a note in Recordings, say “correct: …” (or “korrektur: …”) followed by the fixed text to overwrite it. Fix the same thing twice and WhisPaste offers it here as an automatic replacement.'**
  String get correctionLearningHowTo;

  /// No description provided for @correctionCandidatesCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested from your corrections'**
  String get correctionCandidatesCardTitle;

  /// No description provided for @correctionCandidatesCardHint.
  ///
  /// In en, this message translates to:
  /// **'{count} suggestion(s) from corrections you repeated — review before they become replacements.'**
  String correctionCandidatesCardHint(int count);

  /// No description provided for @correctionCandidatesReviewButton.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get correctionCandidatesReviewButton;

  /// No description provided for @correctionCandidatesReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review learned corrections'**
  String get correctionCandidatesReviewTitle;

  /// No description provided for @correctionCandidatesReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} correction(s) you repeated — accept the ones WhisPaste should apply automatically from now on. Nothing changes until you confirm.'**
  String correctionCandidatesReviewSubtitle(int count);

  /// No description provided for @correctionCandidatesCommitSummary.
  ///
  /// In en, this message translates to:
  /// **'Added {added} learned replacement(s)'**
  String correctionCandidatesCommitSummary(int added);

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
  /// **'How close a spoken phrase must sound like a trigger to still count as a match. Strict only catches near-identical wording, so almost nothing gets replaced by accident, but a mumbled trigger may slip through unmatched. Standard is a balanced default for everyday use. Tolerant also catches noticeably different pronunciation or phrasing, at a higher risk of matching something you did not mean to replace.'**
  String get replacementsFuzzyToleranceHint;

  /// No description provided for @replacementsFuzzyTooShortWarning.
  ///
  /// In en, this message translates to:
  /// **'Trigger phrases under {minLength} characters cannot use similar matching — too many false hits.'**
  String replacementsFuzzyTooShortWarning(int minLength);

  /// Shown when a dictionary entry would reuse a trigger that another entry already has. {trigger} is the existing trigger phrase, {replacement} the entry that already uses it.
  ///
  /// In en, this message translates to:
  /// **'The trigger “{trigger}” already exists (replacement: “{replacement}”).'**
  String replacementsDuplicateTrigger(String trigger, String replacement);

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

  /// Suffix appended to the title of a duplicated snippet, e.g. 'Signature (Kopie)'.
  ///
  /// In en, this message translates to:
  /// **'(copy)'**
  String get snippetCopySuffix;

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
  /// **'Edit snippet'**
  String get snippetsEditSnippet;

  /// No description provided for @snippetsNewSnippet.
  ///
  /// In en, this message translates to:
  /// **'New snippet'**
  String get snippetsNewSnippet;

  /// No description provided for @snippetsDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Open the snippet picker while recording to insert this text.'**
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
  /// **'Not all fields appear in the template yet — their spoken text would go unused.'**
  String get snippetsTemplateMissingFieldsWarning;

  /// Hint under the save button when the snippet has no title yet
  ///
  /// In en, this message translates to:
  /// **'Title is missing'**
  String get snippetsSaveMissingTitle;

  /// Hint under the save button when a static snippet has no text yet
  ///
  /// In en, this message translates to:
  /// **'Text is missing'**
  String get snippetsSaveMissingBody;

  /// Warning when two fields of an interactive snippet share a name
  ///
  /// In en, this message translates to:
  /// **'Each field needs a different name.'**
  String get snippetsFieldsDuplicateWarning;

  /// No description provided for @snippetsInteractiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Interactive'**
  String get snippetsInteractiveBadge;

  /// No description provided for @interactiveSnippetBriefingLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 field} other{{count} fields}} · Enter to start'**
  String interactiveSnippetBriefingLabel(int count);

  /// No description provided for @interactiveSnippetBriefingHint.
  ///
  /// In en, this message translates to:
  /// **'Field 1: {name} · Esc: cancel'**
  String interactiveSnippetBriefingHint(String name);

  /// No description provided for @interactiveSnippetAnnounceLabel.
  ///
  /// In en, this message translates to:
  /// **'Field {index}/{count}: {name}'**
  String interactiveSnippetAnnounceLabel(int index, int count, String name);

  /// No description provided for @interactiveSnippetAnnounceHint.
  ///
  /// In en, this message translates to:
  /// **'Get ready to speak…'**
  String get interactiveSnippetAnnounceHint;

  /// No description provided for @interactiveSnippetSpeakNowLabel.
  ///
  /// In en, this message translates to:
  /// **'{index}/{count}: {name}'**
  String interactiveSnippetSpeakNowLabel(String name, int index, int count);

  /// No description provided for @interactiveSnippetAdvance.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get interactiveSnippetAdvance;

  /// No description provided for @snippetsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete snippet'**
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
  /// **'The trigger word is set, but there are no snippets yet — saying it inserts the word as normal text until you add your first snippet.'**
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
  /// **'What\'s new'**
  String get aboutWhatsNew;

  /// No description provided for @aboutReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report issue'**
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
  /// **'Local speech recognition, GPU-accelerated where available (Metal, Vulkan, CUDA) and on the CPU otherwise (~25 languages).'**
  String get aboutParakeetDesc;

  /// No description provided for @aboutParakeetModelCredit.
  ///
  /// In en, this message translates to:
  /// **'Model: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0'**
  String get aboutParakeetModelCredit;

  /// No description provided for @aboutParakeetGgufCredit.
  ///
  /// In en, this message translates to:
  /// **'GGUF conversion: ggml-org, MIT'**
  String get aboutParakeetGgufCredit;

  /// No description provided for @aboutLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get aboutLinks;

  /// No description provided for @helpLegalTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get helpLegalTitle;

  /// No description provided for @helpDiagnosticsPublicNote.
  ///
  /// In en, this message translates to:
  /// **'GitHub issues are public. Check the report before you paste it.'**
  String get helpDiagnosticsPublicNote;

  /// No description provided for @helpDiagnosticsBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building report …'**
  String get helpDiagnosticsBuilding;

  /// No description provided for @tabsScrollBack.
  ///
  /// In en, this message translates to:
  /// **'Show earlier tabs'**
  String get tabsScrollBack;

  /// No description provided for @tabsScrollForward.
  ///
  /// In en, this message translates to:
  /// **'Show more tabs'**
  String get tabsScrollForward;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutGitHubRepo.
  ///
  /// In en, this message translates to:
  /// **'GitHub repository'**
  String get aboutGitHubRepo;

  /// No description provided for @aboutFollowOnX.
  ///
  /// In en, this message translates to:
  /// **'Follow on X'**
  String get aboutFollowOnX;

  /// No description provided for @aboutMitLicense.
  ///
  /// In en, this message translates to:
  /// **'MIT license'**
  String get aboutMitLicense;

  /// About page row that opens the in-app list of third-party licenses (fonts, models, packages).
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get aboutThirdPartyLicenses;

  /// No description provided for @aboutThirdPartyLicensesDetail.
  ///
  /// In en, this message translates to:
  /// **'Fonts and models'**
  String get aboutThirdPartyLicensesDetail;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutImprint.
  ///
  /// In en, this message translates to:
  /// **'Legal notice'**
  String get aboutImprint;

  /// No description provided for @aboutSystemInfo.
  ///
  /// In en, this message translates to:
  /// **'System info'**
  String get aboutSystemInfo;

  /// No description provided for @aboutSystemInfoDesc.
  ///
  /// In en, this message translates to:
  /// **'Copy a compact diagnostics snapshot for bug reports.'**
  String get aboutSystemInfoDesc;

  /// No description provided for @aboutDiagnosticsContentsTitle.
  ///
  /// In en, this message translates to:
  /// **'What the report contains'**
  String get aboutDiagnosticsContentsTitle;

  /// No description provided for @aboutDiagnosticsContentsDesc.
  ///
  /// In en, this message translates to:
  /// **'App version, operating system, program path without your user name, speech model (variant, model, status, last error), GPU, model files and the last 40 log lines. API keys and tokens are blacked out in the log lines.'**
  String get aboutDiagnosticsContentsDesc;

  /// No description provided for @aboutDiagnosticsPreviewShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get aboutDiagnosticsPreviewShow;

  /// No description provided for @aboutDiagnosticsPreviewHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get aboutDiagnosticsPreviewHide;

  /// No description provided for @aboutDiagnosticsIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics incomplete: {error}'**
  String aboutDiagnosticsIncomplete(String error);

  /// No description provided for @aboutCopyDebugInfo.
  ///
  /// In en, this message translates to:
  /// **'Copy debug info'**
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
  /// **'Open source under the MIT license'**
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
  /// **'Send feedback'**
  String get feedbackSubmit;

  /// Visible hint under the disabled send button naming the first missing item; {what} is a short clause
  ///
  /// In en, this message translates to:
  /// **'To send, please {what}.'**
  String feedbackSubmitMissing(String what);

  /// Missing-item clause: no category chosen
  ///
  /// In en, this message translates to:
  /// **'choose what it is about'**
  String get feedbackMissingCategory;

  /// No description provided for @feedbackMissingRating.
  ///
  /// In en, this message translates to:
  /// **'rate how you feel about WhisPaste'**
  String get feedbackMissingRating;

  /// Missing-item clause: the message is empty
  ///
  /// In en, this message translates to:
  /// **'write a message'**
  String get feedbackMissingComment;

  /// Missing-item clause: the optional email address is not valid
  ///
  /// In en, this message translates to:
  /// **'correct the email address or leave it empty'**
  String get feedbackMissingEmail;

  /// Small marker next to the labels of the required feedback fields
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get feedbackRequiredMarker;

  /// No description provided for @feedbackPublishConsentLabel.
  ///
  /// In en, this message translates to:
  /// **'I allow my feedback to appear anonymously as a quote on the website.'**
  String get feedbackPublishConsentLabel;

  /// No description provided for @feedbackPublishConsentExplanation.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Only your text and rating are shown, never your name or email. You can withdraw this at any time with one click on the Feedback page in the app.'**
  String get feedbackPublishConsentExplanation;

  /// No description provided for @feedbackPublishReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Quotes are written like a rating: what you like and where there is still room to improve. Bug reports and wishes belong to Problem or Idea and are never published.'**
  String get feedbackPublishReviewHint;

  /// No description provided for @feedbackWithdrawConsentLabel.
  ///
  /// In en, this message translates to:
  /// **'Withdraw consent'**
  String get feedbackWithdrawConsentLabel;

  /// No description provided for @feedbackWithdrawConsentHelp.
  ///
  /// In en, this message translates to:
  /// **'Applies to feedback you sent with consent from this device. The quote disappears from the website within about 24 hours.'**
  String get feedbackWithdrawConsentHelp;

  /// No description provided for @feedbackWithdrawConsentPending.
  ///
  /// In en, this message translates to:
  /// **'The withdrawal is saved and will be sent once WhisPaste runs with an internet connection (for up to 30 days); otherwise please withdraw by e-mail.'**
  String get feedbackWithdrawConsentPending;

  /// No description provided for @feedbackWithdrawNoCode.
  ///
  /// In en, this message translates to:
  /// **'No withdrawal code is stored on this device – withdraw by e-mail'**
  String get feedbackWithdrawNoCode;

  /// No description provided for @feedbackWithdrawEntrySending.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal from {date} is being sent …'**
  String feedbackWithdrawEntrySending(Object date);

  /// No description provided for @feedbackWithdrawEntryFailed.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal from {date} not delivered – withdraw by e-mail'**
  String feedbackWithdrawEntryFailed(Object date);

  /// No description provided for @feedbackWithdrawConsentUndelivered.
  ///
  /// In en, this message translates to:
  /// **'The withdrawal could not be delivered – please withdraw by e-mail.'**
  String get feedbackWithdrawConsentUndelivered;

  /// No description provided for @feedbackWithdrawEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Withdraw by e-mail'**
  String get feedbackWithdrawEmailLabel;

  /// No description provided for @feedbackWithdrawEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Withdraw my consent to quote my feedback'**
  String get feedbackWithdrawEmailSubject;

  /// No description provided for @feedbackWithdrawEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Please withdraw my consent to quote my feedback.'**
  String get feedbackWithdrawEmailBody;

  /// No description provided for @feedbackWithdrawEmailDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Feedback date:'**
  String get feedbackWithdrawEmailDateLabel;

  /// No description provided for @feedbackWithdrawEmailReferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal reference:'**
  String get feedbackWithdrawEmailReferenceLabel;

  /// No description provided for @feedbackWithdrawEmailSentLabel.
  ///
  /// In en, this message translates to:
  /// **'I have sent the e-mail'**
  String get feedbackWithdrawEmailSentLabel;

  /// No description provided for @feedbackWithdrawEmailLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'No e-mail app found. Please send the prepared message to this address:'**
  String get feedbackWithdrawEmailLaunchFailed;

  /// No description provided for @feedbackWithdrawEmailCopyLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy address and message'**
  String get feedbackWithdrawEmailCopyLabel;

  /// No description provided for @feedbackWithdrawEmailCopied.
  ///
  /// In en, this message translates to:
  /// **'Address and message copied.'**
  String get feedbackWithdrawEmailCopied;

  /// No description provided for @feedbackWithdrawLocked.
  ///
  /// In en, this message translates to:
  /// **'Your system\'s credential store cannot be read right now. WhisPaste cannot send the consents and withdrawals kept there. Please withdraw by e-mail; the prepared e-mail contains the references needed.'**
  String get feedbackWithdrawLocked;

  /// No description provided for @feedbackWithdrawConsentDone.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal sent. The quote disappears from the website within about 24 hours, at the next daily update.'**
  String get feedbackWithdrawConsentDone;

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
  /// **'After: Copy & paste'**
  String get statusBarAfterBoth;

  /// No description provided for @statusBarAfterNothing.
  ///
  /// In en, this message translates to:
  /// **'After: Manual'**
  String get statusBarAfterNothing;

  /// No description provided for @dockOutputCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get dockOutputCopy;

  /// No description provided for @dockOutputPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get dockOutputPaste;

  /// No description provided for @dockOutputBoth.
  ///
  /// In en, this message translates to:
  /// **'Copy & paste'**
  String get dockOutputBoth;

  /// No description provided for @dockOutputNothing.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get dockOutputNothing;

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
  /// **'Speech model status'**
  String get statusBarSttTooltip;

  /// No description provided for @statusBarSttBackendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Recognition runs on: {backend}'**
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
  /// **'Processing…'**
  String get statusBarTranscribing;

  /// No description provided for @statusBarRefining.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get statusBarRefining;

  /// No description provided for @statusBarHotkeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey: click to configure'**
  String get statusBarHotkeyTooltip;

  /// No description provided for @statusBarAutoPasteOffHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on Auto-Paste…'**
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

  /// No description provided for @statusBarAutomationApiChipLabel.
  ///
  /// In en, this message translates to:
  /// **'Automation: {port}'**
  String statusBarAutomationApiChipLabel(int port);

  /// No description provided for @statusBarAutomationApiChipLabelError.
  ///
  /// In en, this message translates to:
  /// **'Automation: error'**
  String get statusBarAutomationApiChipLabelError;

  /// No description provided for @statusBarAutomationApiTooltip.
  ///
  /// In en, this message translates to:
  /// **'Automation API active on port {port}'**
  String statusBarAutomationApiTooltip(int port);

  /// No description provided for @statusBarAutomationApiTooltipFallback.
  ///
  /// In en, this message translates to:
  /// **'Automation API active on port {port} (port {requestedPort} was in use)'**
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort);

  /// No description provided for @statusBarAutomationApiTooltipError.
  ///
  /// In en, this message translates to:
  /// **'Automation API: no free port found'**
  String get statusBarAutomationApiTooltipError;

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
  /// **'Speech model ready'**
  String get modelServerReady;

  /// No description provided for @modelServerMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech model not installed'**
  String get modelServerMissing;

  /// No description provided for @modelServerWhisper.
  ///
  /// In en, this message translates to:
  /// **'Local speech model'**
  String get modelServerWhisper;

  /// No description provided for @modelReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get modelReady;

  /// No description provided for @modelDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Speech model ready to use'**
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
  /// **'Preparing speech model…'**
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
  /// **'Delete this speech model?'**
  String get modelDeleteConfirm;

  /// No description provided for @modelDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The speech model file is deleted from this device. You can re-download it any time.'**
  String get modelDeleteConfirmMessage;

  /// No description provided for @modelTierDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete these models?'**
  String get modelTierDeleteConfirm;

  /// No description provided for @modelTierDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 model ({size}) is deleted from this device. You can re-download it any time.} other{{count} models ({size}) are deleted from this device. You can re-download them any time.}}'**
  String modelTierDeleteConfirmMessage(int count, String size);

  /// No description provided for @qualityTierCompactLabel.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
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
  /// **'Accurate'**
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

  /// No description provided for @qualityTierRecommendedMeasured.
  ///
  /// In en, this message translates to:
  /// **'Measured for your device'**
  String get qualityTierRecommendedMeasured;

  /// No description provided for @qualityTierDownloadSize.
  ///
  /// In en, this message translates to:
  /// **'{size} download'**
  String qualityTierDownloadSize(String size);

  /// No description provided for @qualityTierDownloadAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Download speech model'**
  String get qualityTierDownloadAndContinue;

  /// No description provided for @qualityTierChooseDifferent.
  ///
  /// In en, this message translates to:
  /// **'Choose a different tier'**
  String get qualityTierChooseDifferent;

  /// No description provided for @qualityTierActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get qualityTierActive;

  /// No description provided for @qualityTierInfoSlow.
  ///
  /// In en, this message translates to:
  /// **'Accurate, takes noticeably longer to process on this computer'**
  String get qualityTierInfoSlow;

  /// No description provided for @qualityTierInfoSlowEstimate.
  ///
  /// In en, this message translates to:
  /// **'Accurate, probably takes noticeably longer on this computer (estimate)'**
  String get qualityTierInfoSlowEstimate;

  /// No description provided for @qualityTierInfoSlowerThanCompact.
  ///
  /// In en, this message translates to:
  /// **'Accurate, takes ~{ratio}x longer than Fast'**
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

  /// No description provided for @benchmarkRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Measures how fast each installed tier runs on this computer. The results set the speed hints and the recommendation.'**
  String get benchmarkRowSubtitle;

  /// No description provided for @benchmarkRunningStep.
  ///
  /// In en, this message translates to:
  /// **'Running… step {step} of {total}: {tier}'**
  String benchmarkRunningStep(int step, int total, String tier);

  /// No description provided for @benchmarkCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel benchmark'**
  String get benchmarkCancel;

  /// No description provided for @benchmarkCancelled.
  ///
  /// In en, this message translates to:
  /// **'Benchmark cancelled. Tiers measured so far are saved.'**
  String get benchmarkCancelled;

  /// No description provided for @benchmarkDone.
  ///
  /// In en, this message translates to:
  /// **'Measurement complete: {count, plural, =1{1 tier measured} other{{count} tiers measured}}.'**
  String benchmarkDone(int count);

  /// No description provided for @benchmarkLastMeasured.
  ///
  /// In en, this message translates to:
  /// **'Last measured: {when}'**
  String benchmarkLastMeasured(String when);

  /// No description provided for @benchmarkBackendLine.
  ///
  /// In en, this message translates to:
  /// **'Compute path: {backend}'**
  String benchmarkBackendLine(String backend);

  /// No description provided for @benchmarkBackendCpu.
  ///
  /// In en, this message translates to:
  /// **'Processor (CPU)'**
  String get benchmarkBackendCpu;

  /// No description provided for @benchmarkBackendGpu.
  ///
  /// In en, this message translates to:
  /// **'Graphics card ({name})'**
  String benchmarkBackendGpu(String name);

  /// No description provided for @benchmarkTierResult.
  ///
  /// In en, this message translates to:
  /// **'{tier}: {seconds} s processing per second of audio'**
  String benchmarkTierResult(String tier, String seconds);

  /// No description provided for @benchmarkNoResult.
  ///
  /// In en, this message translates to:
  /// **'No measurement yet. Run the benchmark to get speed hints for this computer.'**
  String get benchmarkNoResult;

  /// No description provided for @benchmarkStaleNotice.
  ///
  /// In en, this message translates to:
  /// **'These results are from another computer or an earlier version. They are measured again in the background.'**
  String get benchmarkStaleNotice;

  /// No description provided for @benchmarkParakeetNotMeasured.
  ///
  /// In en, this message translates to:
  /// **'The benchmark measures Whisper models. Parakeet is not measured.'**
  String get benchmarkParakeetNotMeasured;

  /// No description provided for @benchmarkRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommended after measuring: {tier}'**
  String benchmarkRecommendation(String tier);

  /// No description provided for @benchmarkSwitchTo.
  ///
  /// In en, this message translates to:
  /// **'Switch to {tier}'**
  String benchmarkSwitchTo(String tier);

  /// No description provided for @benchmarkErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'The benchmark cannot run during a recording. Start it again afterwards.'**
  String get benchmarkErrorBusy;

  /// No description provided for @benchmarkErrorNoModel.
  ///
  /// In en, this message translates to:
  /// **'No tier is installed. Download a speech model first.'**
  String get benchmarkErrorNoModel;

  /// No description provided for @benchmarkErrorFailed.
  ///
  /// In en, this message translates to:
  /// **'The benchmark could not be completed.'**
  String get benchmarkErrorFailed;

  /// No description provided for @benchmarkRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get benchmarkRetry;

  /// No description provided for @qualityTierActionOverride.
  ///
  /// In en, this message translates to:
  /// **'Use anyway'**
  String get qualityTierActionOverride;

  /// No description provided for @qualityTierActionOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Use this tier despite the warning'**
  String get qualityTierActionOverrideHint;

  /// No description provided for @qualityTierModelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Whisper {modelName} · {size}'**
  String qualityTierModelTooltip(String modelName, String size);

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
  /// **'High quality'**
  String get settingsQualityHigh;

  /// No description provided for @settingsQualityBest.
  ///
  /// In en, this message translates to:
  /// **'Accurate'**
  String get settingsQualityBest;

  /// No description provided for @settingsQualityMaximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum accuracy'**
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
  /// **'Advanced speech model settings'**
  String get settingsAdvancedModelManagement;

  /// No description provided for @infoEngineDownloading.
  ///
  /// In en, this message translates to:
  /// **'Speech model is being prepared. Please wait a moment.'**
  String get infoEngineDownloading;

  /// No description provided for @infoModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Please download a speech model in Settings first.'**
  String get infoModelMissing;

  /// No description provided for @infoModelMissingSelected.
  ///
  /// In en, this message translates to:
  /// **'The selected speech model ({size}) isn\'t downloaded yet.'**
  String infoModelMissingSelected(String size);

  /// No description provided for @infoModelMissingDownload.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get infoModelMissingDownload;

  /// No description provided for @statusBarModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech model missing'**
  String get statusBarModelMissing;

  /// No description provided for @statusBarModelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading speech model… {percent} %'**
  String statusBarModelDownloading(int percent);

  /// No description provided for @modelDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get modelDownloadAction;

  /// No description provided for @modelMissingDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Missing — download'**
  String get modelMissingDownloadAction;

  /// No description provided for @infoPipelineBusy.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is still busy with the previous recording.'**
  String get infoPipelineBusy;

  /// No description provided for @infoSnippetPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any snippets yet. Create one, and the picker will open.'**
  String get infoSnippetPickerEmpty;

  /// No description provided for @infoSnippetPickerEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Open snippets'**
  String get infoSnippetPickerEmptyAction;

  /// No description provided for @oomRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped: graphics card is out of memory'**
  String get oomRecoveryTitle;

  /// No description provided for @oomRecoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Choose how to proceed:'**
  String get oomRecoveryMessage;

  /// No description provided for @oomRecoveryTrySmaller.
  ///
  /// In en, this message translates to:
  /// **'Try smaller speech model'**
  String get oomRecoveryTrySmaller;

  /// No description provided for @oomRecoveryTrySmallerHint.
  ///
  /// In en, this message translates to:
  /// **'Switch to {model} and retry recording'**
  String oomRecoveryTrySmallerHint(String model);

  /// No description provided for @oomRecoverySwitchCloud.
  ///
  /// In en, this message translates to:
  /// **'Switch to cloud'**
  String get oomRecoverySwitchCloud;

  /// No description provided for @oomRecoverySwitchCloudHint.
  ///
  /// In en, this message translates to:
  /// **'Use a cloud speech model instead'**
  String get oomRecoverySwitchCloudHint;

  /// No description provided for @oomRecoveryCloudNotice.
  ///
  /// In en, this message translates to:
  /// **'Recordings are then sent to {provider}.'**
  String oomRecoveryCloudNotice(String provider);

  /// No description provided for @oomRecoveryCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get oomRecoveryCancel;

  /// No description provided for @oomRecoveryPermanentTitle.
  ///
  /// In en, this message translates to:
  /// **'Local speech model unavailable'**
  String get oomRecoveryPermanentTitle;

  /// No description provided for @oomRecoveryPermanentMessage.
  ///
  /// In en, this message translates to:
  /// **'All local models failed due to GPU memory limits. Please switch to a cloud speech model in settings.'**
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
  /// **'Switching to a cloud speech model…'**
  String get oomRecoverySwitchingCloud;

  /// No description provided for @oomRecoveryAttemptFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech model {model} also failed. Trying next option…'**
  String oomRecoveryAttemptFailed(String model);

  /// Shown when the user picks 'Try a smaller model' but no smaller model is available (UIA-SHL-06). Says why and what to do next.
  ///
  /// In en, this message translates to:
  /// **'No smaller model is available. Choose another model in Settings or use cloud speech recognition.'**
  String get oomRecoveryNoSmallerModel;

  /// No description provided for @infoSttCudaOomFallbackModel.
  ///
  /// In en, this message translates to:
  /// **'Quality reduced: your GPU ran out of memory. Switched to a lighter speech model.'**
  String get infoSttCudaOomFallbackModel;

  /// No description provided for @infoSttCudaOomFallbackCpu.
  ///
  /// In en, this message translates to:
  /// **'Your GPU ran out of memory. Switched to CPU mode for reliability.'**
  String get infoSttCudaOomFallbackCpu;

  /// No description provided for @errorSttServerConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Speech model stopped unexpectedly. Please try again.'**
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

  /// Same as errorCloudTimeout, but shown when a local model is installed: it names the offline fallback.
  ///
  /// In en, this message translates to:
  /// **'The cloud service took too long to answer. Check your connection, or dictate offline with your local speech model.'**
  String get errorCloudTimeoutLocal;

  /// Error toast when the cloud speech service did not answer in time. Shown when no local model is installed.
  ///
  /// In en, this message translates to:
  /// **'The cloud service took too long to answer. Check your connection and try again.'**
  String get errorCloudTimeout;

  /// Same as errorCloudNetwork, but shown when a local model is installed: it names the offline fallback.
  ///
  /// In en, this message translates to:
  /// **'The cloud service could not be reached. Check your internet connection, or dictate offline with your local speech model.'**
  String get errorCloudNetworkLocal;

  /// Error toast when the cloud speech service cannot be reached. Shown when no local model is installed, so the hint points to checking the connection.
  ///
  /// In en, this message translates to:
  /// **'The cloud service could not be reached. Check your internet connection and try again.'**
  String get errorCloudNetwork;

  /// Error toast when a dictation could not be appended to the quick note. The text was not added, so the user can copy it from the toast.
  ///
  /// In en, this message translates to:
  /// **'The quick note could not be saved, so the text was not added to it. Copy the text and paste it into the note.'**
  String get errorQuickNoteAppendFailed;

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

  /// Error toast when the speech model could not be loaded, even after a CPU retry. Suggests a restart, then a new download.
  ///
  /// In en, this message translates to:
  /// **'The speech model could not be loaded. Restart WhisPaste. If it still fails, download the speech model again in Settings.'**
  String get errorSttModelLoadFailed;

  /// Error toast when the speech model file is missing from disk. Directs the user to download it in Settings.
  ///
  /// In en, this message translates to:
  /// **'The speech model file is missing. Download the speech model in Settings.'**
  String get errorSttModelFileMissing;

  /// Error toast when the speech model file on disk is damaged. Directs the user to download it again in Settings.
  ///
  /// In en, this message translates to:
  /// **'The speech model file is damaged. Download the speech model again in Settings.'**
  String get errorSttModelCorrupted;

  /// Error toast when the speech engine is still running a native call after a model switch or quit was requested. Tells the user to restart the app.
  ///
  /// In en, this message translates to:
  /// **'The speech engine is still busy with an earlier dictation. Restart WhisPaste to use it again.'**
  String get errorSttEngineRestartNeeded;

  /// Error toast when a retry of a kept recording fails again. The recording stays for another try.
  ///
  /// In en, this message translates to:
  /// **'Transcribing again failed. The recording is kept for another try.'**
  String get pendingRetryFailed;

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
  /// **'Speech model failed to start'**
  String get errorSttServerFailed;

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
  /// **'Speech model failed on both GPU and CPU. Please restart the app or re-download the speech model.'**
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
  /// **'Speech model is still starting. Please try again in a moment.'**
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

  /// No description provided for @errorNoMicrophone.
  ///
  /// In en, this message translates to:
  /// **'No microphone found. Connect a microphone and try again.'**
  String get errorNoMicrophone;

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

  /// Refusal before a model download starts when the disk has less than 1.2 times the download size free. needed and free are formatted sizes such as '1.2 GB'.
  ///
  /// In en, this message translates to:
  /// **'Not enough disk space for this download: needs {needed}, {free} free. The download did not start.'**
  String modelDownloadDiskSpaceShort(String needed, String free);

  /// No description provided for @modelDeleteInUse.
  ///
  /// In en, this message translates to:
  /// **'The speech model file is in use by another program and could not be deleted. Close it and try again.'**
  String get modelDeleteInUse;

  /// No description provided for @statusSttLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading speech model…'**
  String get statusSttLoading;

  /// No description provided for @statusSttReady.
  ///
  /// In en, this message translates to:
  /// **'Speech model ready'**
  String get statusSttReady;

  /// Model download error: the file arrived damaged (size or hash check failed) and was deleted.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was damaged and has been removed. Please download it again.'**
  String get modelDownloadFailedChecksum;

  /// Model download error: the file could not be written to disk (disk full or no permission).
  ///
  /// In en, this message translates to:
  /// **'The file could not be saved. Check that there is enough free disk space.'**
  String get modelDownloadFailedStorage;

  /// Model download error with no more specific cause the user can act on.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Please try again.'**
  String get modelDownloadFailedUnknown;

  /// Button under the onboarding model download progress bar; stops the running download and returns to the engine choice.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get onboardingModelDownloadCancel;

  /// Title of the warning shown before the onboarding model download when the disk has less free space than the model needs.
  ///
  /// In en, this message translates to:
  /// **'Low disk space'**
  String get onboardingModelDiskSpaceTitle;

  /// Body of the low-disk-space warning before a model download. needed and free are formatted sizes such as '639 MB' or '1.2 GB'.
  ///
  /// In en, this message translates to:
  /// **'The model needs {needed}, but only {free} is free. The download will probably fail.'**
  String onboardingModelDiskSpaceBody(String needed, String free);

  /// Confirm button of the low-disk-space warning: start the model download anyway.
  ///
  /// In en, this message translates to:
  /// **'Download anyway'**
  String get onboardingModelDiskSpaceContinue;

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

  /// No description provided for @historyTakeAsNote.
  ///
  /// In en, this message translates to:
  /// **'Take over as note'**
  String get historyTakeAsNote;

  /// No description provided for @historyTakenAsNote.
  ///
  /// In en, this message translates to:
  /// **'Taken over as note'**
  String get historyTakenAsNote;

  /// No description provided for @historyOpenNote.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get historyOpenNote;

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

  /// No description provided for @smartModeUndoToastMessage.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode applied'**
  String get smartModeUndoToastMessage;

  /// No description provided for @smartModeUndoAction.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get smartModeUndoAction;

  /// No description provided for @smartModeBusy.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode is still running'**
  String get smartModeBusy;

  /// No description provided for @smartModeBusyRetry.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode is still running – please try again in a moment'**
  String get smartModeBusyRetry;

  /// No description provided for @smartModeNameChangeToast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 name changed} other{{count} names changed}}'**
  String smartModeNameChangeToast(int count);

  /// No description provided for @selectionUndoCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Original copied to the clipboard – paste it with {shortcut}. The previous clipboard content was replaced.'**
  String selectionUndoCopiedToClipboard(String shortcut);

  /// Shown when Undo for a smart-mode selection edit cannot run because no paste target is known.
  ///
  /// In en, this message translates to:
  /// **'Undo is not possible right now.'**
  String get selectionUndoUnavailable;

  /// No description provided for @smartModeCheckTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The check took too long – your text stays unchanged.'**
  String get smartModeCheckTimedOut;

  /// No description provided for @historySmartModeUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo Smart Mode'**
  String get historySmartModeUndo;

  /// No description provided for @historySmartModeRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Smart Mode'**
  String get historySmartModeRestore;

  /// No description provided for @historySmartModeFailedModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Text model not downloaded'**
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
  /// **'Manage tags'**
  String get tagManageTitle;

  /// No description provided for @tagManageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet. Create one by adding it to a recording.'**
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

  /// Screen-reader label of the small x button on a tag chip. {tag} is the tag name.
  ///
  /// In en, this message translates to:
  /// **'Remove tag \"{tag}\"'**
  String tagRemoveSemanticsLabel(String tag);

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
  /// **'Keyboard shortcuts'**
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

  /// Group header in the shortcut help for the recordings list (uppercase, like GENERAL and EDITING).
  ///
  /// In en, this message translates to:
  /// **'RECORDINGS LIST'**
  String get historyShortcutListGroup;

  /// Shortcut help row: arrow keys move the keyboard cursor through the recordings list.
  ///
  /// In en, this message translates to:
  /// **'Select entry'**
  String get historyShortcutMoveFocus;

  /// Shortcut help row: Ctrl+Enter opens the focused recording in the detail panel.
  ///
  /// In en, this message translates to:
  /// **'Open entry'**
  String get historyShortcutOpenEntry;

  /// Shortcut help row: Enter copies the focused recording to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy entry'**
  String get historyShortcutCopyEntry;

  /// Shortcut help row: Delete moves the focused recording to the trash.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get historyShortcutDeleteEntry;

  /// Shortcut help row: select all recordings in the list.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get historyShortcutSelectAll;

  /// Shortcut help row: Esc clears the selection in the recordings list.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get historyShortcutClearSelection;

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

  /// Shortcut help row: Esc in the transcript editor discards the edit (asks first when changed).
  ///
  /// In en, this message translates to:
  /// **'Discard edit'**
  String get historyShortcutDiscardEdit;

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
  /// **'Search tips'**
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
  /// **'Hotkey'**
  String get settingsKeyboardShortcut;

  /// Heading of the card with the main recording hotkey and its hold/tap modes.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get shortcutsGroupDictate;

  /// Heading of the card with the quick-note and snippet-picker hotkeys.
  ///
  /// In en, this message translates to:
  /// **'Notes & snippets'**
  String get shortcutsGroupNotes;

  /// Heading of the card with the Smart Mode hotkey and the edit-selection hotkey.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode & edit selection'**
  String get shortcutsGroupSmartMode;

  /// Intro above the Keyboard shortcuts area: the one place that says hotkeys work system-wide.
  ///
  /// In en, this message translates to:
  /// **'These hotkeys work system-wide: in every app, even while WhisPaste runs in the background. Each combination belongs to just one hotkey.'**
  String get shortcutsAreaIntro;

  /// No description provided for @settingsKeyboardShortcutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hotkey to start and stop recording'**
  String get settingsKeyboardShortcutSubtitle;

  /// No description provided for @settingsHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Start/stop recording'**
  String get settingsHotkeyEnabled;

  /// No description provided for @settingsCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
  String get settingsCurrentHotkey;

  /// No description provided for @settingsChangeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsChangeHotkey;

  /// No description provided for @settingsHotkeyRecorderTitle.
  ///
  /// In en, this message translates to:
  /// **'Record new hotkey'**
  String get settingsHotkeyRecorderTitle;

  /// No description provided for @settingsHotkeyRecorderHint.
  ///
  /// In en, this message translates to:
  /// **'Press the key combination you want to use…'**
  String get settingsHotkeyRecorderHint;

  /// No description provided for @settingsHotkeyRecorderModifierHint.
  ///
  /// In en, this message translates to:
  /// **'Any modifier combination works: e.g. {first}, {second}, or {third}'**
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  );

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
  /// **'Record a quick note'**
  String get settingsQuickNoteHotkeyEnabled;

  /// No description provided for @settingsQuickNoteHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Transcribed text is appended to the note marked as your quick note. You pick that note in the Notes area.'**
  String get settingsQuickNoteHotkeyHint;

  /// Setting label: when a quick note is saved, bring the main window forward and open the note.
  ///
  /// In en, this message translates to:
  /// **'Open notes in the main window'**
  String get settingsQuickNoteOpenInMainWindow;

  /// Explanation of the open-note-in-main-window setting for both states (off: background toast; on: window comes forward).
  ///
  /// In en, this message translates to:
  /// **'Off: the quick note is saved in the background and a message offers “Open note”. On: the main window comes forward and shows the note.'**
  String get settingsQuickNoteOpenInMainWindowHint;

  /// No description provided for @settingsQuickNoteCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
  String get settingsQuickNoteCurrentHotkey;

  /// No description provided for @settingsQuickNoteHotkeyCollision.
  ///
  /// In en, this message translates to:
  /// **'This combination is already used for \"{action}\". Pick a different one.'**
  String settingsQuickNoteHotkeyCollision(String action);

  /// Shown under the main dictation hotkey when the chosen combination is already used by another WhisPaste hotkey. {action} is that hotkey's name.
  ///
  /// In en, this message translates to:
  /// **'This combination is already used for \"{action}\". Pick a different one.'**
  String settingsDictationHotkeyCollision(Object action);

  /// No description provided for @settingsQuickNoteHotkeyInactive.
  ///
  /// In en, this message translates to:
  /// **'This combination could not be registered — the quick-note hotkey is currently not active. Pick a different combination.'**
  String get settingsQuickNoteHotkeyInactive;

  /// Toast shown after a quick note was saved while the main window stays in the background.
  ///
  /// In en, this message translates to:
  /// **'Quick note saved'**
  String get quickNoteToastSaved;

  /// Action button on the quick-note toast; opens the note in the Notizen area.
  ///
  /// In en, this message translates to:
  /// **'Open note'**
  String get quickNoteToastOpenNote;

  /// No description provided for @settingsHotkeyActionSnippetPicker.
  ///
  /// In en, this message translates to:
  /// **'Snippet picker'**
  String get settingsHotkeyActionSnippetPicker;

  /// No description provided for @settingsSnippetPickerHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Open snippet picker'**
  String get settingsSnippetPickerHotkeyEnabled;

  /// No description provided for @settingsSnippetPickerHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Opens the snippet picker straight away — no recording, and without the spoken trigger word.'**
  String get settingsSnippetPickerHotkeyHint;

  /// No description provided for @settingsSnippetPickerCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
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
  /// **'Max recording duration'**
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
  /// **'Close to tray'**
  String get settingsCloseToTray;

  /// No description provided for @settingsCloseToTraySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep running in the system tray when closing the window'**
  String get settingsCloseToTraySubtitle;

  /// No description provided for @settingsSidePanelEnabled.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Quick-Paste panel'**
  String get settingsSidePanelEnabled;

  /// No description provided for @settingsSidePanelEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slide-out panel on hover at the chosen screen edge for transcriptions, snippets and clipboard history'**
  String get settingsSidePanelEnabledSubtitle;

  /// No description provided for @settingsSidePanelEdge.
  ///
  /// In en, this message translates to:
  /// **'Panel position'**
  String get settingsSidePanelEdge;

  /// No description provided for @settingsSidePanelEdgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which screen edge the panel docks to and slides out from'**
  String get settingsSidePanelEdgeSubtitle;

  /// No description provided for @settingsSidePanelEdgeLeft.
  ///
  /// In en, this message translates to:
  /// **'Left edge'**
  String get settingsSidePanelEdgeLeft;

  /// No description provided for @settingsSidePanelEdgeRight.
  ///
  /// In en, this message translates to:
  /// **'Right edge'**
  String get settingsSidePanelEdgeRight;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Colours of the app windows. Recording bar and overlay stay dark.'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsAppearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsAppearanceSystem;

  /// No description provided for @settingsAppearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// No description provided for @settingsAppearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// No description provided for @settingsAppearanceNavy.
  ///
  /// In en, this message translates to:
  /// **'Navy'**
  String get settingsAppearanceNavy;

  /// Name of the navy appearance card in the appearance picker.
  ///
  /// In en, this message translates to:
  /// **'Navy'**
  String get settingsAppearanceCardNavy;

  /// One-line explanation under the title of the recognition language dialog.
  ///
  /// In en, this message translates to:
  /// **'Choose the language WhisPaste expects when you record. With auto-detect on, it recognises the language itself.'**
  String get settingsLanguageDialogSubtitle;

  /// Placeholder of the language search field.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get settingsLanguageSearchHint;

  /// Heading of the panel that lists the chosen recognition language.
  ///
  /// In en, this message translates to:
  /// **'Current choice'**
  String get settingsLanguageSelectedTitle;

  /// Primary action of the recognition language dialog.
  ///
  /// In en, this message translates to:
  /// **'Save and close'**
  String get settingsLanguageSaveAndClose;

  /// Hint in the recognition language dialog explaining why Save is disabled: no language is selected yet.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one language to save.'**
  String get settingsLanguageSavePickOne;

  /// Shown when no language matches the search.
  ///
  /// In en, this message translates to:
  /// **'No language found'**
  String get settingsLanguageNoResults;

  /// Button that opens the recognition language dialog.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsLanguageChange;

  /// Secondary action that closes the recognition language dialog without saving.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsLanguageCancel;

  /// No description provided for @settingsErrorReporting.
  ///
  /// In en, this message translates to:
  /// **'Error reporting'**
  String get settingsErrorReporting;

  /// No description provided for @settingsErrorReportingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sends crash and error reports with an anonymous device ID. Never your audio or text.'**
  String get settingsErrorReportingSubtitle;

  /// No description provided for @settingsErrorReportingRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Takes effect after restarting WhisPaste.'**
  String get settingsErrorReportingRestartHint;

  /// No description provided for @settingsAutoPasteBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocklist'**
  String get settingsAutoPasteBlocklist;

  /// No description provided for @settingsAutoPasteBlocklistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Apps where text is only copied (no auto-paste). With the switch below on, the text goes to the clipboard; when off, only to Recordings. While a list is set, an app that cannot be identified counts as blocked.'**
  String get settingsAutoPasteBlocklistSubtitle;

  /// No description provided for @settingsAutoPasteBlocklistCopyToggle.
  ///
  /// In en, this message translates to:
  /// **'Copy to the clipboard when apps are blocked'**
  String get settingsAutoPasteBlocklistCopyToggle;

  /// No description provided for @settingsAutoPasteBlocklistCopyToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off: the text is only saved in Recordings.'**
  String get settingsAutoPasteBlocklistCopyToggleSubtitle;

  /// No description provided for @settingsAutoPasteBlocklistPlaceholderMac.
  ///
  /// In en, this message translates to:
  /// **'com.1password.1password, com.apple.Terminal'**
  String get settingsAutoPasteBlocklistPlaceholderMac;

  /// No description provided for @settingsAutoPasteBlocklistPlaceholderWindows.
  ///
  /// In en, this message translates to:
  /// **'1password, windowsterminal'**
  String get settingsAutoPasteBlocklistPlaceholderWindows;

  /// No description provided for @settingsAutoPasteBlocklistPlaceholderLinux.
  ///
  /// In en, this message translates to:
  /// **'1password, gnome-terminal-server'**
  String get settingsAutoPasteBlocklistPlaceholderLinux;

  /// No description provided for @settingsAutoPasteBlocklistShortPrefixWarning.
  ///
  /// In en, this message translates to:
  /// **'On the Mac, enter bundle IDs such as com.apple.Terminal. An entry without a dot only matches an identical ID.'**
  String get settingsAutoPasteBlocklistShortPrefixWarning;

  /// Block-list hint under GNOME Wayland without the WhisPaste GNOME Shell extension: the target app cannot be named, so a set list only copies.
  ///
  /// In en, this message translates to:
  /// **'Under GNOME (Wayland), WhisPaste identifies the target app only with the WhisPaste extension for GNOME – without it, while a block list is set, text is only copied'**
  String get settingsAutoPasteBlocklistNoDetectionHintGnome;

  /// Linux-only switch: Auto-Paste presses Ctrl+Shift+V (terminal paste) in every app, not only in recognised terminals.
  ///
  /// In en, this message translates to:
  /// **'Always paste with Ctrl+Shift+V'**
  String get settingsLinuxAlwaysShiftPaste;

  /// Subtitle of the always-Ctrl+Shift+V switch; warns that some apps bind the keys differently (LibreOffice: Paste Special, use the localized LibreOffice menu name).
  ///
  /// In en, this message translates to:
  /// **'The terminal shortcut, in every other app too. Some apps use these keys for something else; LibreOffice, for example, opens “Paste Special”'**
  String get settingsLinuxAlwaysShiftPasteSubtitle;

  /// Linux status line: the target app (and so terminals) can be identified on this desktop.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste identifies the target app here and pastes into terminals with Ctrl+Shift+V on its own'**
  String get settingsLinuxTargetStatusAvailable;

  /// Linux status line under GNOME Wayland without the WhisPaste extension: terminals are not recognised; suggests the always-Ctrl+Shift+V switch.
  ///
  /// In en, this message translates to:
  /// **'Under GNOME (Wayland), WhisPaste recognises terminals only with the WhisPaste extension for GNOME. Until then, switch this on if you mostly dictate into terminals'**
  String get settingsLinuxTargetStatusGnome;

  /// Linux status line on a Wayland desktop without a focus source: terminals are not recognised; suggests the always-Ctrl+Shift+V switch.
  ///
  /// In en, this message translates to:
  /// **'On this desktop, WhisPaste does not recognise terminals. Switch this on if you mostly dictate into terminals'**
  String get settingsLinuxTargetStatusUnsupported;

  /// Linux: title of the row that asks the desktop (RemoteDesktop portal) for permission to send paste shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Paste through desktop permission'**
  String get settingsLinuxPortalInputTitle;

  /// Linux portal row: explains the one-time consent dialog and that only Ctrl+V/Ctrl+C are sent.
  ///
  /// In en, this message translates to:
  /// **'Works without setup: your desktop asks once whether WhisPaste may send shortcuts. WhisPaste only sends Ctrl+V and Ctrl+C this way'**
  String get settingsLinuxPortalInputBody;

  /// Button: opens the desktop consent dialog for the portal keyboard.
  ///
  /// In en, this message translates to:
  /// **'Ask for permission'**
  String get settingsLinuxPortalInputConnect;

  /// Button: ends the portal session and forgets the consent.
  ///
  /// In en, this message translates to:
  /// **'Withdraw permission'**
  String get settingsLinuxPortalInputRevoke;

  /// Status after the user granted the portal keyboard.
  ///
  /// In en, this message translates to:
  /// **'Permission granted. WhisPaste can now paste this way'**
  String get settingsLinuxPortalInputConnected;

  /// Status after the user closed the consent dialog without granting.
  ///
  /// In en, this message translates to:
  /// **'No permission given. You can ask again at any time'**
  String get settingsLinuxPortalInputCancelled;

  /// Status when the portal session could not be set up.
  ///
  /// In en, this message translates to:
  /// **'Asking for permission did not work. Please try again later'**
  String get settingsLinuxPortalInputFailed;

  /// Linux/GNOME: title of the optional WhisPaste GNOME Shell extension row.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste extension for GNOME'**
  String get settingsLinuxGnomeExtensionTitle;

  /// Explains why the GNOME extension is needed and that it reads the app name only (privacy).
  ///
  /// In en, this message translates to:
  /// **'Under GNOME, WhisPaste learns which app is active only with this extension, for terminals and the block list. It reads the app name only, never window titles or content'**
  String get settingsLinuxGnomeExtensionBody;

  /// Button: turns the installed GNOME extension on (gnome-extensions enable).
  ///
  /// In en, this message translates to:
  /// **'Turn on the extension'**
  String get settingsLinuxGnomeExtensionEnable;

  /// Button: turns the GNOME extension off again.
  ///
  /// In en, this message translates to:
  /// **'Turn off the extension'**
  String get settingsLinuxGnomeExtensionDisable;

  /// The GNOME extension files are not on this system; points to the manual.
  ///
  /// In en, this message translates to:
  /// **'The extension is not installed here. The manual explains how to install it'**
  String get settingsLinuxGnomeExtensionNotInstalled;

  /// After turning the extension on: a log-out/log-in may be needed under Wayland.
  ///
  /// In en, this message translates to:
  /// **'Turned on. If WhisPaste does not recognise the app yet, log out and back in once'**
  String get settingsLinuxGnomeExtensionRelogin;

  /// Turning the extension on failed. {command} is a terminal command, keep it unchanged.
  ///
  /// In en, this message translates to:
  /// **'Turning it on did not work. In a terminal: {command}'**
  String settingsLinuxGnomeExtensionFailed(String command);

  /// No description provided for @settingsAutoPasteBlocklistNoDetectionHint.
  ///
  /// In en, this message translates to:
  /// **'Under Wayland, WhisPaste cannot see the active app. While an app is blocked, text is only copied, not pasted.'**
  String get settingsAutoPasteBlocklistNoDetectionHint;

  /// Note under the Auto-Paste capability on Linux Wayland sessions: WhisPaste cannot see the focused window there, so it cannot refuse or redirect a paste after a window switch (PAR-032).
  ///
  /// In en, this message translates to:
  /// **'Under Wayland, WhisPaste cannot check whether you switched windows during processing – the text goes to the window that is active when it is pasted'**
  String get settingsPasteWaylandFocusHint;

  /// No description provided for @settingsPasteBlocklistAdd.
  ///
  /// In en, this message translates to:
  /// **'Add app'**
  String get settingsPasteBlocklistAdd;

  /// No description provided for @settingsPasteBlocklistEmpty.
  ///
  /// In en, this message translates to:
  /// **'No app blocked – auto-paste works everywhere.'**
  String get settingsPasteBlocklistEmpty;

  /// No description provided for @settingsPasteBlocklistRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from the block list: {name}'**
  String settingsPasteBlocklistRemoveTooltip(String name);

  /// No description provided for @settingsPasteBlocklistPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add app to the block list'**
  String get settingsPasteBlocklistPickerTitle;

  /// No description provided for @settingsPasteBlocklistRecentHeading.
  ///
  /// In en, this message translates to:
  /// **'Recently pasted into'**
  String get settingsPasteBlocklistRecentHeading;

  /// No description provided for @settingsPasteBlocklistPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recording with a recognised app yet. Enter the app ID below.'**
  String get settingsPasteBlocklistPickerEmpty;

  /// No description provided for @settingsPasteBlocklistManualHeading.
  ///
  /// In en, this message translates to:
  /// **'Enter the app ID manually'**
  String get settingsPasteBlocklistManualHeading;

  /// No description provided for @settingsPasteBlocklistManualAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get settingsPasteBlocklistManualAdd;

  /// No description provided for @historyAutoPasteOffForApp.
  ///
  /// In en, this message translates to:
  /// **'Turn off auto-paste in this app'**
  String get historyAutoPasteOffForApp;

  /// No description provided for @settingsPasteClipboardAfter.
  ///
  /// In en, this message translates to:
  /// **'Clipboard after pasting'**
  String get settingsPasteClipboardAfter;

  /// No description provided for @settingsPasteClipboardAfterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whether your previous clipboard content comes back after a paste. If a paste cannot be confirmed in time, the transcript always stays on the clipboard.'**
  String get settingsPasteClipboardAfterSubtitle;

  /// No description provided for @settingsPasteClipboardAfterKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep the transcript'**
  String get settingsPasteClipboardAfterKeep;

  /// No description provided for @settingsPasteClipboardAfterRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore what you had copied'**
  String get settingsPasteClipboardAfterRestore;

  /// No description provided for @pasteClipboardUnsavedHint.
  ///
  /// In en, this message translates to:
  /// **'Your previous clipboard could not be kept – macOS denied access to it. Allow it under System Settings → Privacy & Security.'**
  String get pasteClipboardUnsavedHint;

  /// No description provided for @pasteClipboardUnsavedAction.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get pasteClipboardUnsavedAction;

  /// No description provided for @settingsCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckUpdates;

  /// No description provided for @settingsCheckUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check for new versions at startup and every 24 hours'**
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
  /// **'Beta updates'**
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
  /// **'Audio and text stay local. Anonymous usage statistics go to a self-hosted server in the EU, crash reports go to a service in the EU (Sentry) — GDPR-compliant.'**
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
  /// **'Set up speech model'**
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

  /// Shown on the model page instead of a silent disabled Next while no speech model is installed and none is downloading
  ///
  /// In en, this message translates to:
  /// **'Download a speech model or use a cloud provider with a saved API key to continue.'**
  String get onboardingModelNextBlocked;

  /// No description provided for @onboardingModelDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get onboardingModelDownloading;

  /// No description provided for @onboardingModelReady.
  ///
  /// In en, this message translates to:
  /// **'Speech model ready'**
  String get onboardingModelReady;

  /// No description provided for @onboardingModelGpuCpuFallback.
  ///
  /// In en, this message translates to:
  /// **'Optimised GPU acceleration unavailable, app will use the CPU'**
  String get onboardingModelGpuCpuFallback;

  /// No description provided for @onboardingModelEngineParakeetLabel.
  ///
  /// In en, this message translates to:
  /// **'Parakeet'**
  String get onboardingModelEngineParakeetLabel;

  /// No description provided for @onboardingModelEngineParakeetDesc.
  ///
  /// In en, this message translates to:
  /// **'The quickest way to text in about 25 European languages, including German. Runs well on any hardware, GPU or not.'**
  String get onboardingModelEngineParakeetDesc;

  /// Line under the spinner on the onboarding model page while the app checks CPU/GPU to recommend an engine.
  ///
  /// In en, this message translates to:
  /// **'Checking your hardware for the right recommendation…'**
  String get onboardingModelDetectingHardware;

  /// Model step: button that switches speech recognition to the cloud provider whose API key is saved (UIA-MDL-GATE G1a).
  ///
  /// In en, this message translates to:
  /// **'Use {provider}'**
  String onboardingModelUseCloud(String provider);

  /// Model step: note above the button when a cloud key is saved but the local engine is chosen.
  ///
  /// In en, this message translates to:
  /// **'An API key for {provider} is already saved. You can use it instead of a local speech model.'**
  String onboardingModelCloudKeySaved(String provider);

  /// Model step: note while a cloud provider with a saved key is chosen.
  ///
  /// In en, this message translates to:
  /// **'You use {provider} for speech recognition. You do not need a local speech model for it.'**
  String onboardingModelCloudInUse(String provider);

  /// Model step: button that switches back to the local engine.
  ///
  /// In en, this message translates to:
  /// **'Use a local speech model'**
  String get onboardingModelUseLocal;

  /// No description provided for @onboardingModelEngineWhisperLabel.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
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

  /// No description provided for @onboardingTestRecordingMicBypassConsequence.
  ///
  /// In en, this message translates to:
  /// **'The hotkey then stays untested until you use it for the first time.'**
  String get onboardingTestRecordingMicBypassConsequence;

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

  /// Replaces the 'You're All Set!' heading on the closing page while no speech model is installed
  ///
  /// In en, this message translates to:
  /// **'A speech model is still missing'**
  String get onboardingReadyNoModelTitle;

  /// Explains on the closing page why the 'all set' claim is held back: without a speech model nothing can be transcribed
  ///
  /// In en, this message translates to:
  /// **'Without a speech model or an API key WhisPaste cannot transcribe anything. Download a model or save a key, and you are all set.'**
  String get onboardingReadyNoModelBody;

  /// Button on the closing page that returns to the speech model step
  ///
  /// In en, this message translates to:
  /// **'Back to the model'**
  String get onboardingReadyBackToModel;

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
  /// **'Text is in your clipboard, press {paste} to paste'**
  String onboardingReadyStep3CopyOnly(String paste);

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
  /// **'Starts minimized in the background, ready for your hotkey'**
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

  /// Tooltip/accessible name of the chevron that unfolds the full list of update reasons on onboarding page 1.
  ///
  /// In en, this message translates to:
  /// **'Show all changes'**
  String get onboardingRevisionNoticeExpand;

  /// Tooltip/accessible name of the chevron that folds the update reasons back to two lines.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get onboardingRevisionNoticeCollapse;

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
  /// **'This update walkthrough is shown only once, so the steps you skip now won\'t be set up for you. You can reopen the same steps any time on the Help page, under “Review the introduction”, and every setting they cover also has its own place in Settings. What you already configured stays untouched.'**
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
  /// **'Processing…'**
  String get overlayTranscribing;

  /// No description provided for @overlayRefining.
  ///
  /// In en, this message translates to:
  /// **'Refining…'**
  String get overlayRefining;

  /// No description provided for @overlayStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get overlayStarting;

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
  /// **'Copied & pasted'**
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

  /// No description provided for @overlayStopAndCancelHint.
  ///
  /// In en, this message translates to:
  /// **'{hotkey} to stop · {cancelKey} to cancel'**
  String overlayStopAndCancelHint(String hotkey, String cancelKey);

  /// No description provided for @overlayDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard recording? Press {cancelKey} again'**
  String overlayDiscardConfirm(String cancelKey);

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

  /// Overlay recording line while the microphone stopped delivering signal mid-recording, e.g. unplugged (XP-5-08). Recording keeps running; disappears when the signal returns. Replaces the timer in every size; keep it short, the line does not grow.
  ///
  /// In en, this message translates to:
  /// **'No microphone signal'**
  String get overlayMicSignalLost;

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
  /// **'Start recording'**
  String get trayStartRecording;

  /// No description provided for @trayStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get trayStopRecording;

  /// No description provided for @trayOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open WhisPaste'**
  String get trayOpenApp;

  /// No description provided for @trayTranscribeFile.
  ///
  /// In en, this message translates to:
  /// **'Transcribe file…'**
  String get trayTranscribeFile;

  /// Tray menu entry that opens the clipboard quick-paste side panel without the main window
  ///
  /// In en, this message translates to:
  /// **'Open quick-paste panel'**
  String get trayOpenSidePanel;

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

  /// No description provided for @trayRecentRecordings.
  ///
  /// In en, this message translates to:
  /// **'Recent recordings'**
  String get trayRecentRecordings;

  /// No description provided for @trayUnlockRecordings.
  ///
  /// In en, this message translates to:
  /// **'Unlock recordings…'**
  String get trayUnlockRecordings;

  /// No description provided for @trayRecentMeta.
  ///
  /// In en, this message translates to:
  /// **'{time} · {count, plural, =1{1 word} other{{count} words}}'**
  String trayRecentMeta(String time, int count);

  /// No description provided for @trayFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback…'**
  String get trayFeedback;

  /// Title of the confirmation shown when the user quits from the tray during a recording or transcription (UIA-SHL-15).
  ///
  /// In en, this message translates to:
  /// **'A recording is still running'**
  String get quitDuringDictationTitle;

  /// Body of the quit confirmation during a recording or transcription: quitting stops the work and loses its text (UIA-SHL-15).
  ///
  /// In en, this message translates to:
  /// **'Quitting now stops the running recording or transcription, and its text is lost.'**
  String get quitDuringDictationMessage;

  /// No description provided for @trayMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get trayMicrophone;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
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

  /// No description provided for @voiceCorrectionUndone.
  ///
  /// In en, this message translates to:
  /// **'Correction undone'**
  String get voiceCorrectionUndone;

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

  /// No description provided for @historyVoiceNoteButtonTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voice note — say “tag: …” to add a tag, or “correct: …” to replace this transcript'**
  String get historyVoiceNoteButtonTooltip;

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
  /// **'Check now'**
  String get updateCheckNow;

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Install update'**
  String get updateInstall;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// No description provided for @updateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get updateViewRelease;

  /// No description provided for @updateError.
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get updateError;

  /// Shown in the About section after the user asked to install while a dictation runs; the install starts when the recording has ended.
  ///
  /// In en, this message translates to:
  /// **'The update installs after the recording'**
  String get updateInstallAfterRecording;

  /// Shown in the About section when the downloaded installer file is gone; the user is asked to check for updates again.
  ///
  /// In en, this message translates to:
  /// **'The installer file is missing. Check for updates again.'**
  String get updateInstallerMissing;

  /// Shown in the About section when the downloaded update could not be started; tells the user they can try again.
  ///
  /// In en, this message translates to:
  /// **'The update could not be started. Try installing it again.'**
  String get updateInstallFailed;

  /// Button label in the About section that starts the installation again after a failed launch of the downloaded installer.
  ///
  /// In en, this message translates to:
  /// **'Install again'**
  String get updateInstallRetry;

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

  /// No description provided for @settingsOverlayColors.
  ///
  /// In en, this message translates to:
  /// **'Overlay colours'**
  String get settingsOverlayColors;

  /// No description provided for @settingsOverlayBackground.
  ///
  /// In en, this message translates to:
  /// **'Overlay and button background'**
  String get settingsOverlayBackground;

  /// No description provided for @settingsOverlayBackgroundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies to the recording overlay and the floating button.'**
  String get settingsOverlayBackgroundSubtitle;

  /// No description provided for @settingsOverlayBackgroundMarine.
  ///
  /// In en, this message translates to:
  /// **'Marine'**
  String get settingsOverlayBackgroundMarine;

  /// No description provided for @settingsOverlayBackgroundGraphit.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get settingsOverlayBackgroundGraphit;

  /// No description provided for @settingsOverlayBackgroundGletscher.
  ///
  /// In en, this message translates to:
  /// **'Glacier'**
  String get settingsOverlayBackgroundGletscher;

  /// No description provided for @settingsOverlayBackgroundAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get settingsOverlayBackgroundAmber;

  /// No description provided for @settingsOverlayWave.
  ///
  /// In en, this message translates to:
  /// **'Wave colour for overlay and button'**
  String get settingsOverlayWave;

  /// No description provided for @settingsOverlayWaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies to the recording overlay and the floating button: wave and recording ring.'**
  String get settingsOverlayWaveSubtitle;

  /// No description provided for @settingsOverlayWaveCyan.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get settingsOverlayWaveCyan;

  /// No description provided for @settingsOverlayWaveViolett.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get settingsOverlayWaveViolett;

  /// No description provided for @settingsOverlayWaveNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get settingsOverlayWaveNeutral;

  /// No description provided for @settingsOverlayWaveAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get settingsOverlayWaveAmber;

  /// No description provided for @settingsOverlayWaveInk.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get settingsOverlayWaveInk;

  /// No description provided for @settingsOverlayWaveCoral.
  ///
  /// In en, this message translates to:
  /// **'Coral'**
  String get settingsOverlayWaveCoral;

  /// No description provided for @settingsOverlayWaveMint.
  ///
  /// In en, this message translates to:
  /// **'Mint'**
  String get settingsOverlayWaveMint;

  /// No description provided for @settingsOverlayWaveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not clearly visible on this background'**
  String get settingsOverlayWaveUnavailable;

  /// No description provided for @settingsOverlayWaveReplacedToast.
  ///
  /// In en, this message translates to:
  /// **'“{from}” is not clearly visible on this background. The wave was changed to “{to}”.'**
  String settingsOverlayWaveReplacedToast(String from, String to);

  /// No description provided for @settingsOverlayLiveTranscript.
  ///
  /// In en, this message translates to:
  /// **'Live transcript'**
  String get settingsOverlayLiveTranscript;

  /// No description provided for @settingsOverlayLiveTranscriptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show recognized text live while you\'re still speaking, instead of the waveform only. Uses extra CPU during recording'**
  String get settingsOverlayLiveTranscriptSubtitle;

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
  /// **'Switch to normal'**
  String get overlayContextSwitchNormal;

  /// No description provided for @overlayContextSwitchCompact.
  ///
  /// In en, this message translates to:
  /// **'Switch to compact'**
  String get overlayContextSwitchCompact;

  /// No description provided for @overlayContextSwitchMini.
  ///
  /// In en, this message translates to:
  /// **'Switch to mini'**
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
  /// **'Start recording'**
  String get buttonContextStartRecording;

  /// No description provided for @buttonContextShowHistory.
  ///
  /// In en, this message translates to:
  /// **'Show recordings'**
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
  /// **'Recordings'**
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

  /// No description provided for @settingsHistoryHideOnOpen.
  ///
  /// In en, this message translates to:
  /// **'Hide recordings on open'**
  String get settingsHistoryHideOnOpen;

  /// No description provided for @settingsHistoryHideOnOpenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows a “Show recordings” button instead of your transcriptions whenever WhisPaste starts or its window reopens. Nothing is deleted.'**
  String get settingsHistoryHideOnOpenSubtitle;

  /// No description provided for @historyPinGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings are locked'**
  String get historyPinGateTitle;

  /// No description provided for @historyPinGateHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to show your transcriptions.'**
  String get historyPinGateHint;

  /// No description provided for @historyImportUnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Unlock Recordings to transcribe the file.'**
  String get historyImportUnlockHint;

  /// No description provided for @historyPinUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get historyPinUnlock;

  /// No description provided for @historyPinDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get historyPinDialogTitle;

  /// No description provided for @historyPinDialogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your recordings are protected with a PIN.'**
  String get historyPinDialogSubtitle;

  /// No description provided for @historyPinFieldHint.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get historyPinFieldHint;

  /// No description provided for @historyPinRepeatHint.
  ///
  /// In en, this message translates to:
  /// **'Repeat PIN'**
  String get historyPinRepeatHint;

  /// No description provided for @historyPinWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN.'**
  String get historyPinWrong;

  /// No description provided for @historyPinLockedOut.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String historyPinLockedOut(int seconds);

  /// No description provided for @historyPinForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get historyPinForgot;

  /// No description provided for @historyPinForgotHint.
  ///
  /// In en, this message translates to:
  /// **'Resetting immediately deletes all transcriptions, saved audio files, notes with their versions, and note images. If a file cannot be deleted, WhisPaste shows a notice.'**
  String get historyPinForgotHint;

  /// No description provided for @historyPinForgotConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recordings and notes and remove PIN?'**
  String get historyPinForgotConfirmTitle;

  /// No description provided for @historyPinForgotConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'A forgotten PIN cannot be recovered. To reset it, all transcriptions and saved audio files (including archive and trash), all notes with their versions (including trash) and all note images are deleted immediately and permanently. Settings, snippets and replacements are kept. If a file cannot be deleted, WhisPaste shows a notice.'**
  String get historyPinForgotConfirmMessage;

  /// No description provided for @historyPinForgotLeftoverAudio.
  ///
  /// In en, this message translates to:
  /// **'Some recordings, imports or note images could not be deleted. WhisPaste removes them the next time it starts.'**
  String get historyPinForgotLeftoverAudio;

  /// No description provided for @historyPinForgotLeftoverUnqueued.
  ///
  /// In en, this message translates to:
  /// **'Some recordings or imports could not be deleted, and WhisPaste cannot retry later. Please delete them by hand. Location: {folder}'**
  String historyPinForgotLeftoverUnqueued(String folder);

  /// No description provided for @historyPinForgotMigrationCopyLeft.
  ///
  /// In en, this message translates to:
  /// **'A copy of the old database ({path}) could not be deleted. Please delete it by hand.'**
  String historyPinForgotMigrationCopyLeft(String path);

  /// No description provided for @historyPinForgotConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get historyPinForgotConfirmAction;

  /// No description provided for @historyPinSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get historyPinSetTitle;

  /// No description provided for @historyPinSetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'4–8 digits. Keeps others from casually viewing your transcriptions on this computer — it does not encrypt them.'**
  String get historyPinSetSubtitle;

  /// No description provided for @historyPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use 4 to 8 digits.'**
  String get historyPinInvalid;

  /// No description provided for @historyPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The PINs do not match.'**
  String get historyPinMismatch;

  /// No description provided for @settingsHistoryPin.
  ///
  /// In en, this message translates to:
  /// **'PIN protection'**
  String get settingsHistoryPin;

  /// No description provided for @settingsHistoryPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require a PIN to show recordings and notes, including side panel, the floating button\'s menu and automation API.'**
  String get settingsHistoryPinSubtitle;

  /// No description provided for @settingsHistoryPinChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsHistoryPinChange;

  /// No description provided for @settingsHistoryPinRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsHistoryPinRemove;

  /// No description provided for @settingsHistoryAutoLock.
  ///
  /// In en, this message translates to:
  /// **'Lock automatically'**
  String get settingsHistoryAutoLock;

  /// No description provided for @settingsHistoryAutoLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide recordings again after this much inactivity.'**
  String get settingsHistoryAutoLockSubtitle;

  /// No description provided for @settingsHistoryAutoLockNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsHistoryAutoLockNever;

  /// No description provided for @settingsHistoryAutoLockMinutes.
  ///
  /// In en, this message translates to:
  /// **'After {minutes} min'**
  String settingsHistoryAutoLockMinutes(int minutes);

  /// No description provided for @settingsFloatingButtonLookLocked.
  ///
  /// In en, this message translates to:
  /// **'Turn on the floating button to change this.'**
  String get settingsFloatingButtonLookLocked;

  /// No description provided for @settingsFloatingButtonSection.
  ///
  /// In en, this message translates to:
  /// **'Floating button'**
  String get settingsFloatingButtonSection;

  /// No description provided for @settingsFloatingButtonSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Always-on-top recording button for quick access'**
  String get settingsFloatingButtonSectionSubtitle;

  /// No description provided for @settingsFloatingButtonWaylandTitle.
  ///
  /// In en, this message translates to:
  /// **'Wayland limits'**
  String get settingsFloatingButtonWaylandTitle;

  /// No description provided for @settingsFloatingButtonWaylandLimit.
  ///
  /// In en, this message translates to:
  /// **'Under Wayland the desktop decides where the button appears and whether it stays on top. WhisPaste can only promise both to a limited extent there. Recording with a click still works, and the button does not take keyboard focus.'**
  String get settingsFloatingButtonWaylandLimit;

  /// No description provided for @settingsFloatingButtonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available on this Linux desktop: the button needs X11 or XWayland. Turning it off is still possible.'**
  String get settingsFloatingButtonUnavailable;

  /// No description provided for @settingsSttIdleTimeout.
  ///
  /// In en, this message translates to:
  /// **'Speech model idle timeout'**
  String get settingsSttIdleTimeout;

  /// No description provided for @settingsSttIdleTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long the speech model stays loaded after use'**
  String get settingsSttIdleTimeoutSubtitle;

  /// No description provided for @settingsSttIdleTimeoutKeepAlive.
  ///
  /// In en, this message translates to:
  /// **'Keep alive'**
  String get settingsSttIdleTimeoutKeepAlive;

  /// No description provided for @settingsSttKeepLoaded.
  ///
  /// In en, this message translates to:
  /// **'Keep model loaded'**
  String get settingsSttKeepLoaded;

  /// No description provided for @settingsSttKeepLoadedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A loaded model starts recording without waiting for it to load. While it is loaded, it takes up memory.'**
  String get settingsSttKeepLoadedSubtitle;

  /// No description provided for @settingsSttKeepLoadedMemory.
  ///
  /// In en, this message translates to:
  /// **'Loaded, the model needs about {size} of memory.'**
  String settingsSttKeepLoadedMemory(String size);

  /// No description provided for @settingsSttVramGateNotice.
  ///
  /// In en, this message translates to:
  /// **'The GPU memory ({vramMb} MB) is not enough for this model ({requiredMb} MB). It runs on the processor.'**
  String settingsSttVramGateNotice(int vramMb, int requiredMb);

  /// No description provided for @settingsSttKeepLoadedAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get settingsSttKeepLoadedAlways;

  /// No description provided for @settingsSttKeepLoadedAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get settingsSttKeepLoadedAutomatic;

  /// No description provided for @settingsSttKeepLoadedAfterIdle.
  ///
  /// In en, this message translates to:
  /// **'After idle time'**
  String get settingsSttKeepLoadedAfterIdle;

  /// No description provided for @settingsSttKeepLoadedUnloadAfter.
  ///
  /// In en, this message translates to:
  /// **'Unload after'**
  String get settingsSttKeepLoadedUnloadAfter;

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
  /// **'Star on GitHub'**
  String get reviewPromptStarGitHub;

  /// No description provided for @reviewPromptRateStore.
  ///
  /// In en, this message translates to:
  /// **'Rate on the Store'**
  String get reviewPromptRateStore;

  /// No description provided for @reviewSupportEntry.
  ///
  /// In en, this message translates to:
  /// **'Rate & support WhisPaste'**
  String get reviewSupportEntry;

  /// No description provided for @reviewSupportLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate the app'**
  String get reviewSupportLabel;

  /// No description provided for @reviewSupportAction.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get reviewSupportAction;

  /// No description provided for @reviewSupportGitHubLabel.
  ///
  /// In en, this message translates to:
  /// **'Support WhisPaste with a star on GitHub'**
  String get reviewSupportGitHubLabel;

  /// No description provided for @reviewSupportGitHubAction.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get reviewSupportGitHubAction;

  /// No description provided for @githubInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is open source'**
  String get githubInviteTitle;

  /// No description provided for @githubInviteBody.
  ///
  /// In en, this message translates to:
  /// **'A star on GitHub helps others find it.'**
  String get githubInviteBody;

  /// No description provided for @githubInviteOpen.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get githubInviteOpen;

  /// No description provided for @githubInviteLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get githubInviteLater;

  /// No description provided for @githubInviteNever.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get githubInviteNever;

  /// No description provided for @ideasBoardLabel.
  ///
  /// In en, this message translates to:
  /// **'Ideas & feature requests'**
  String get ideasBoardLabel;

  /// No description provided for @ideasBoardAction.
  ///
  /// In en, this message translates to:
  /// **'View board'**
  String get ideasBoardAction;

  /// No description provided for @feedbackIdeasLink.
  ///
  /// In en, this message translates to:
  /// **'Suggest & vote on ideas'**
  String get feedbackIdeasLink;

  /// No description provided for @feedbackTypeProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem'**
  String get feedbackTypeProblem;

  /// No description provided for @feedbackTypeIdea.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get feedbackTypeIdea;

  /// No description provided for @feedbackTypePraise.
  ///
  /// In en, this message translates to:
  /// **'Praise'**
  String get feedbackTypePraise;

  /// No description provided for @feedbackTypeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get feedbackTypeQuestion;

  /// No description provided for @feedbackPromptProblem.
  ///
  /// In en, this message translates to:
  /// **'What went wrong? Tell us what you did and what happened.'**
  String get feedbackPromptProblem;

  /// No description provided for @feedbackPromptIdea.
  ///
  /// In en, this message translates to:
  /// **'What would make WhisPaste better for you?'**
  String get feedbackPromptIdea;

  /// No description provided for @feedbackPromptPraise.
  ///
  /// In en, this message translates to:
  /// **'What works well for you?'**
  String get feedbackPromptPraise;

  /// No description provided for @feedbackPromptQuestion.
  ///
  /// In en, this message translates to:
  /// **'What would you like to know?'**
  String get feedbackPromptQuestion;

  /// No description provided for @feedbackDiagnosticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attach diagnostics'**
  String get feedbackDiagnosticsLabel;

  /// No description provided for @feedbackDiagnosticsExplanation.
  ///
  /// In en, this message translates to:
  /// **'Adds the app version, operating system, speech engine and backend. Recordings and transcripts are never attached.'**
  String get feedbackDiagnosticsExplanation;

  /// No description provided for @feedbackDiagnosticsPreview.
  ///
  /// In en, this message translates to:
  /// **'Show preview'**
  String get feedbackDiagnosticsPreview;

  /// No description provided for @feedbackDiagnosticsPreviewHide.
  ///
  /// In en, this message translates to:
  /// **'Hide preview'**
  String get feedbackDiagnosticsPreviewHide;

  /// No description provided for @feedbackDiagnosticsPreviewHeading.
  ///
  /// In en, this message translates to:
  /// **'This exact text is added to your message:'**
  String get feedbackDiagnosticsPreviewHeading;

  /// No description provided for @feedbackIdeaBoardHint.
  ///
  /// In en, this message translates to:
  /// **'You can also post your idea on the public ideas board and vote on others.'**
  String get feedbackIdeaBoardHint;

  /// No description provided for @feedbackTextTooLong.
  ///
  /// In en, this message translates to:
  /// **'The text is too long to attach the diagnostics. Shorten it a little.'**
  String get feedbackTextTooLong;

  /// No description provided for @hotkeyRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Hotkey registration failed. Choose a new key combination in Settings.'**
  String get hotkeyRegistrationFailed;

  /// No description provided for @hotkeyFallbackActive.
  ///
  /// In en, this message translates to:
  /// **'{taken} is already used by another app. Until you choose a different combination, {active} starts a recording.'**
  String hotkeyFallbackActive(String taken, String active);

  /// Toast when a secondary hotkey (quick note, snippet picker) is held by another app and stays off. {action} is the action's name (UIA-SHL-05).
  ///
  /// In en, this message translates to:
  /// **'Another app holds the hotkey for {action}. It stays off until you pick a free combination in Settings.'**
  String hotkeyConflictActive(String action);

  /// No description provided for @hotkeyConflictWarning.
  ///
  /// In en, this message translates to:
  /// **'This key combination is reserved by {platform} ({note}) and may not work.'**
  String hotkeyConflictWarning(String platform, String note);

  /// No description provided for @exportFormatPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose export format'**
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
  /// **'Speech model cannot start. Please restart the app or reload the speech model.'**
  String get recoveryExhaustedToast;

  /// No description provided for @recoveryExhaustedAction.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get recoveryExhaustedAction;

  /// No description provided for @recoveryVcRuntimeToast.
  ///
  /// In en, this message translates to:
  /// **'Speech model cannot start: a Windows component is missing (Microsoft Visual C++). Please install the Visual C++ Redistributable (x64) and restart WhisPaste.'**
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
  /// **'WhisPaste is now running without GPU acceleration due to a problem on the last launch. Recording still works as usual.'**
  String get recoveryGpuDisabledToast;

  /// No description provided for @serverDownloadFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Speech model could not be downloaded. Check your internet connection?'**
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
  /// **'Graphics acceleration'**
  String get settingsGpuAcceleration;

  /// No description provided for @settingsGpuAccelerationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic uses the graphics card when it is available. \"CPU only\" is slower but works on every device. Force GPU only if automatic mode doesn\'t work.'**
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
  /// **'Speech model'**
  String get settingsSttEngine;

  /// No description provided for @settingsSttEngineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper: 99 languages. Parakeet: faster, about 25 languages.'**
  String get settingsSttEngineSubtitle;

  /// No description provided for @settingsSttEngineWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get settingsSttEngineWhisper;

  /// No description provided for @settingsSttEngineParakeet.
  ///
  /// In en, this message translates to:
  /// **'Parakeet'**
  String get settingsSttEngineParakeet;

  /// Badge on the speech-recognition engine that the dictation language recommends (UIA-RT-03). One word, shown next to the engine name.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get settingsSttEngineRecommended;

  /// No description provided for @parakeetModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Parakeet model'**
  String get parakeetModelTitle;

  /// No description provided for @parakeetModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One-time download ({size}), then runs fully offline'**
  String parakeetModelSubtitle(String size);

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
  /// **'No results'**
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
  /// **'Anonymous usage counts, no cookies, not linked to you. Helps us see which features are used. Your text and audio are never included.'**
  String get settingsShareUsageStatsSubtitle;

  /// No description provided for @settingsRetainRecentAudio.
  ///
  /// In en, this message translates to:
  /// **'Keep audio of recent recordings'**
  String get settingsRetainRecentAudio;

  /// No description provided for @settingsRetainRecentAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the audio of your last {count} recordings on this device for debugging or restoring a past transcript; recordings and imported files are deleted automatically after {days} days at most'**
  String settingsRetainRecentAudioSubtitle(int count, int days);

  /// Privacy note in Settings: recordings whose transcription failed keep their audio for 24 hours for a retry, even when audio retention is off.
  ///
  /// In en, this message translates to:
  /// **'A recording whose transcription failed keeps its audio for up to 24 hours, so you can try again, even when this is off.'**
  String get pendingAudioRetentionNote;

  /// Title of the Settings section listing recordings kept for a retry.
  ///
  /// In en, this message translates to:
  /// **'Recordings waiting for a retry'**
  String get pendingAudioSectionTitle;

  /// Explanation under the title of the Settings section listing recordings kept for a retry.
  ///
  /// In en, this message translates to:
  /// **'These recordings could not be transcribed, for example because the connection dropped. The audio is deleted after 24 hours at most, or when you discard it.'**
  String get pendingAudioSectionBody;

  /// Shown in the retry list when no recording waits for a retry.
  ///
  /// In en, this message translates to:
  /// **'No recordings are waiting.'**
  String get pendingAudioEmpty;

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
  /// **'Snippet picker'**
  String get featureSpotlightSnippetPickerTitle;

  /// No description provided for @featureSpotlightSnippetPickerDescription.
  ///
  /// In en, this message translates to:
  /// **'Save reusable text blocks and insert them anywhere with a hotkey or a spoken trigger — no retyping needed.'**
  String get featureSpotlightSnippetPickerDescription;

  /// No description provided for @featureSpotlightSidePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Clipboard side panel'**
  String get featureSpotlightSidePanelTitle;

  /// No description provided for @featureSpotlightSidePanelDescription.
  ///
  /// In en, this message translates to:
  /// **'Hover the screen edge to open your recent clipboard history and drag any item straight into your document.'**
  String get featureSpotlightSidePanelDescription;

  /// No description provided for @featureSpotlightInteractiveSnippetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Interactive snippets'**
  String get featureSpotlightInteractiveSnippetsTitle;

  /// No description provided for @featureSpotlightInteractiveSnippetsDescription.
  ///
  /// In en, this message translates to:
  /// **'Snippets with blanks: WhisPaste walks you through each field — speak, press Enter for the next one, and the finished text is pasted in one piece.'**
  String get featureSpotlightInteractiveSnippetsDescription;

  /// No description provided for @featureSpotlightSmartModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get featureSpotlightSmartModeTitle;

  /// No description provided for @featureSpotlightSmartModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Clean up, shorten, or translate your text before it is pasted — fully on-device, with its own hotkey, preset, and target language.'**
  String get featureSpotlightSmartModeDescription;

  /// No description provided for @featureSpotlightHistoryPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock your recordings with a PIN'**
  String get featureSpotlightHistoryPinTitle;

  /// No description provided for @featureSpotlightHistoryPinDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep your transcriptions private behind a PIN — including the side panel and the floating button menu — with optional auto-lock after inactivity. Settings → Recordings.'**
  String get featureSpotlightHistoryPinDescription;

  /// No description provided for @featureSpotlightEditSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit selected text by voice'**
  String get featureSpotlightEditSelectionTitle;

  /// No description provided for @featureSpotlightEditSelectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Select text in any app, press the edit-selection hotkey and say what should change — or just “shorter”, “improve” or “translate”. Uses the Smart Mode text model. Off by default: turn it on under Settings → Smart Mode.'**
  String get featureSpotlightEditSelectionDescription;

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
  /// **'Move to trash'**
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
  /// **'Clipboard history'**
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

  /// No description provided for @sidePanelClipboardLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Locked by PIN'**
  String get sidePanelClipboardLockedTitle;

  /// No description provided for @sidePanelClipboardLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Copied text stays hidden while the recordings are locked. Unlock them with your PIN to see it again.'**
  String get sidePanelClipboardLockedHint;

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

  /// No description provided for @sidePanelLoadFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Close and reopen the panel to try again.'**
  String get sidePanelLoadFailedHint;

  /// No description provided for @settingsSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get settingsSmartMode;

  /// No description provided for @settingsSmartModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local text cleanup, shortening, and translation after recording'**
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
  /// **'No automatic post-processing — the text is used exactly as transcribed.'**
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
  /// **'Translates the transcribed text into the target language set below.'**
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
  /// **'Text model ready to use'**
  String get smartModeDownloadComplete;

  /// No description provided for @smartModeRamWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Limited memory detected'**
  String get smartModeRamWarningTitle;

  /// No description provided for @smartModeRamWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode\'s local text model runs best with 8 GB of RAM or more. It may still work, but could run slowly or fail on this machine. Download anyway?'**
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

  /// No description provided for @smartModeModelDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this text model?'**
  String get smartModeModelDeleteConfirm;

  /// No description provided for @smartModeModelDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The text model file is deleted from this device. You can re-download it any time.'**
  String get smartModeModelDeleteConfirmMessage;

  /// No description provided for @smartModeMemoryFootprintInfo.
  ///
  /// In en, this message translates to:
  /// **'Runs fully on-device. While active, the text model uses about 4–5 GB of RAM in addition to disk space — shared with the speech model, so total memory use depends on which speech model you also have loaded.'**
  String get smartModeMemoryFootprintInfo;

  /// No description provided for @smartModeFactGuardHint.
  ///
  /// In en, this message translates to:
  /// **'The fact guard checks numbers, dates, links, e-mail addresses and IBANs. Dictionary names stay intact. Free instructions can change names that are not in the dictionary – add them to the dictionary if they must stay.'**
  String get smartModeFactGuardHint;

  /// No description provided for @smartModeSpeedExampleInfo.
  ///
  /// In en, this message translates to:
  /// **'Example: a typical 50-word recording takes roughly 1–6 seconds to process, depending on your device\'s hardware.'**
  String get smartModeSpeedExampleInfo;

  /// Shown in Smart Mode settings when the on-device engine library is not bundled in this build (e.g. a Linux dev build); also the tooltip of the disabled on-device option.
  ///
  /// In en, this message translates to:
  /// **'On-device Smart Mode isn\'t included in this build. Switch to OpenAI, or install an official WhisPaste release.'**
  String get smartModeLocalUnavailable;

  /// No description provided for @settingsHotkeyActionSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get settingsHotkeyActionSmartMode;

  /// No description provided for @settingsSmartModeHotkeyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Record with Smart Mode'**
  String get settingsSmartModeHotkeyEnabled;

  /// No description provided for @settingsSmartModeHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Starts a recording with a fixed preset, independent of your standard preset in Smart Mode. “Hold to record” applies here too.'**
  String get settingsSmartModeHotkeyHint;

  /// No description provided for @settingsSmartModeHotkeyPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get settingsSmartModeHotkeyPreset;

  /// No description provided for @settingsSmartModeCurrentHotkey.
  ///
  /// In en, this message translates to:
  /// **'Current hotkey'**
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
  /// **'Smart Mode can clean up, shorten, or translate your text automatically — fully on-device. The local text model takes {size} on disk. Download it now, or set it up later in Settings.'**
  String smartModeOnboardingHintBody(String size);

  /// No description provided for @smartModeOnboardingHintExampleBeforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Raw text'**
  String get smartModeOnboardingHintExampleBeforeLabel;

  /// No description provided for @smartModeOnboardingHintExampleBefore.
  ///
  /// In en, this message translates to:
  /// **'so um the client meeting got moved to thursday at three pm and uh we still need the updated slides from marketing'**
  String get smartModeOnboardingHintExampleBefore;

  /// No description provided for @smartModeOnboardingHintExampleAfterLabel.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode result'**
  String get smartModeOnboardingHintExampleAfterLabel;

  /// No description provided for @smartModeOnboardingHintExampleAfter.
  ///
  /// In en, this message translates to:
  /// **'So, the client meeting got moved to Thursday at three PM, and we still need the updated slides from Marketing.'**
  String get smartModeOnboardingHintExampleAfter;

  /// No description provided for @smartModeOnboardingHintDownloadCta.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get smartModeOnboardingHintDownloadCta;

  /// No description provided for @smartModeOnboardingHintSkipCta.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get smartModeOnboardingHintSkipCta;

  /// No description provided for @smartModeUsageHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Try Smart Mode on your next recording'**
  String get smartModeUsageHintTitle;

  /// No description provided for @smartModeUsageHintBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode can clean up, shorten, or translate text like this automatically, right on your device. Here\'s what you just said:'**
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

  /// No description provided for @settingsAutomationApi.
  ///
  /// In en, this message translates to:
  /// **'Local automation API'**
  String get settingsAutomationApi;

  /// No description provided for @settingsAutomationApiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Other programs and scripts on this computer can control WhisPaste, for example start a recording. Devices on your network can\'t reach it.'**
  String get settingsAutomationApiSubtitle;

  /// No description provided for @settingsAutomationApiEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable local automation API'**
  String get settingsAutomationApiEnable;

  /// No description provided for @settingsAutomationApiEnableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Binds only to 127.0.0.1/::1 — never reachable from the network'**
  String get settingsAutomationApiEnableSubtitle;

  /// No description provided for @settingsAutomationApiStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running on port {port}'**
  String settingsAutomationApiStatusRunning(int port);

  /// No description provided for @settingsAutomationApiStatusRunningFallback.
  ///
  /// In en, this message translates to:
  /// **'Running on port {port} (port {requestedPort} was in use)'**
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  );

  /// No description provided for @settingsAutomationApiStatusStopped.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get settingsAutomationApiStatusStopped;

  /// No description provided for @settingsAutomationApiStatusError.
  ///
  /// In en, this message translates to:
  /// **'No free port found in range {start}–{end}'**
  String settingsAutomationApiStatusError(int start, int end);

  /// No description provided for @settingsAutomationApiCustomPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom port'**
  String get settingsAutomationApiCustomPortLabel;

  /// No description provided for @settingsAutomationApiCustomPortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for automatic port selection — falls back automatically if it\'s taken'**
  String get settingsAutomationApiCustomPortSubtitle;

  /// No description provided for @settingsAutomationApiCustomPortHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get settingsAutomationApiCustomPortHint;

  /// No description provided for @settingsAutomationApiCustomPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a port between 1024 and 65535'**
  String get settingsAutomationApiCustomPortInvalid;

  /// No description provided for @settingsAutomationApiToken.
  ///
  /// In en, this message translates to:
  /// **'Bearer token'**
  String get settingsAutomationApiToken;

  /// No description provided for @settingsAutomationApiTokenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send it as \"Authorization: Bearer <token>\" — every request without it is rejected'**
  String get settingsAutomationApiTokenSubtitle;

  /// No description provided for @settingsAutomationApiRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get settingsAutomationApiRegenerate;

  /// No description provided for @settingsAutomationApiRegenerateConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Regenerate token?'**
  String get settingsAutomationApiRegenerateConfirmTitle;

  /// No description provided for @settingsAutomationApiRegenerateConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The current token stops working immediately. Any script using it will need the new one.'**
  String get settingsAutomationApiRegenerateConfirmMessage;

  /// No description provided for @settingsAutomationApiCopyToken.
  ///
  /// In en, this message translates to:
  /// **'Copy token'**
  String get settingsAutomationApiCopyToken;

  /// No description provided for @settingsAutomationApiTokenCopied.
  ///
  /// In en, this message translates to:
  /// **'Token copied to clipboard'**
  String get settingsAutomationApiTokenCopied;

  /// No description provided for @settingsAutomationApiDocumentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get settingsAutomationApiDocumentation;

  /// No description provided for @settingsAutomationApiDocumentationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Endpoint reference and curl examples'**
  String get settingsAutomationApiDocumentationSubtitle;

  /// No description provided for @settingsAutomationApiDocumentationAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get settingsAutomationApiDocumentationAction;

  /// Character-count metadata chip in the History detail panel (ticket 12), analogous to historyWordCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String historyCharacterCount(int count);

  /// Tooltip for the target-app metadata chip in the History detail panel (ticket 12) — {app} is the captured bundle ID / process identifier.
  ///
  /// In en, this message translates to:
  /// **'Pasted into {app}'**
  String historyPastedInto(String app);

  /// Disclosure toggle that reveals the pre-Smart-Mode/pre-Replacements transcript in the History detail panel (ticket 12) — only shown when it differs from the final text.
  ///
  /// In en, this message translates to:
  /// **'Show original transcript'**
  String get historyShowOriginalTranscript;

  /// No description provided for @historyHideOriginalTranscript.
  ///
  /// In en, this message translates to:
  /// **'Hide original transcript'**
  String get historyHideOriginalTranscript;

  /// No description provided for @historyOriginalTranscriptLabel.
  ///
  /// In en, this message translates to:
  /// **'Original transcript'**
  String get historyOriginalTranscriptLabel;

  /// Action name of the edit-selection hotkey, used in hotkey collision messages
  ///
  /// In en, this message translates to:
  /// **'Edit selection'**
  String get settingsHotkeyActionSelectionEdit;

  /// Settings row label: toggle for the edit-selection-by-voice hotkey
  ///
  /// In en, this message translates to:
  /// **'Edit selection'**
  String get settingsSelectionEditHotkeyEnabled;

  /// Settings hint below the edit-selection hotkey toggle; the quoted words are the spoken quick-action keywords
  ///
  /// In en, this message translates to:
  /// **'Select text in any app, press this hotkey and say what to change — or just \"shorter\", \"improve\" or \"translate\". The result replaces the selection; undo in the app brings the original back. Uses the text model set up in Smart Mode.'**
  String get settingsSelectionEditHotkeyHint;

  /// Shown when the edit-selection hotkey combination could not be registered with the OS
  ///
  /// In en, this message translates to:
  /// **'This combination could not be registered — the edit-selection hotkey is currently not active. Pick a different combination.'**
  String get settingsSelectionEditHotkeyInactive;

  /// Very short target name shown in the recording overlay while recording an instruction for editing the selected text
  ///
  /// In en, this message translates to:
  /// **'Edit selection'**
  String get overlayTargetSelectionEdit;

  /// Overlay label while recording an edit-selection instruction (announced by screen readers)
  ///
  /// In en, this message translates to:
  /// **'Say what to change'**
  String get overlayRecordingSelectionEdit;

  /// Overlay hint while recording an edit-selection instruction; the listed words are the spoken quick-action keywords and must stay recognizable
  ///
  /// In en, this message translates to:
  /// **'Say what to change — or: shorter · improve · translate'**
  String get overlaySelectionEditHint;

  /// Overlay label while the selected text is being edited
  ///
  /// In en, this message translates to:
  /// **'Editing selection…'**
  String get overlayEditingSelection;

  /// Overlay completion message after the selected text was replaced
  ///
  /// In en, this message translates to:
  /// **'Selection replaced'**
  String get overlayDoneSelectionEdit;

  /// Overlay error: the edit-selection hotkey was used without any selected text
  ///
  /// In en, this message translates to:
  /// **'No text selected — select text first, then press the hotkey'**
  String get errorSelectionEditNoSelection;

  /// Overlay error: the edit-selection hotkey needs a configured Smart Mode engine
  ///
  /// In en, this message translates to:
  /// **'Set up Smart Mode first (download the local text model or add an OpenAI key) to edit selections'**
  String get errorSelectionEditNoEngine;

  /// Overlay error: this build has no auto-paste, so selections cannot be edited
  ///
  /// In en, this message translates to:
  /// **'Editing a selection needs auto-paste, which is not available in this build'**
  String get errorSelectionEditUnsupported;

  /// Overlay error: the copy shortcut could not be sent to the target app
  ///
  /// In en, this message translates to:
  /// **'Could not read the selection — check the auto-paste permission'**
  String get errorSelectionEditCopyFailed;

  /// Overlay error: the Smart Mode engine failed or timed out; nothing was replaced
  ///
  /// In en, this message translates to:
  /// **'Editing failed — your text was left unchanged'**
  String get errorSelectionEditFailed;

  /// Overlay error: a free instruction would change a protected fact it does not name; nothing was replaced
  ///
  /// In en, this message translates to:
  /// **'The edit would have changed facts your instruction does not mention — your text was left unchanged'**
  String get errorSelectionEditFactsChanged;

  /// Overlay error: a free instruction would change a protected value it does not name; {value} is the shortened value, nothing was replaced
  ///
  /// In en, this message translates to:
  /// **'The edit would change “{value}” without your instruction naming it. Name the old and new value, e.g. “change 3 to 5” — your text was left unchanged'**
  String errorSelectionEditFactsChangedValue(String value);

  /// Overlay error: the edited text could not be pasted; nothing was replaced
  ///
  /// In en, this message translates to:
  /// **'Could not replace the selection — your text was left unchanged'**
  String get errorSelectionEditPasteFailed;

  /// No description provided for @settingsCudaPackTitle.
  ///
  /// In en, this message translates to:
  /// **'NVIDIA CUDA acceleration'**
  String get settingsCudaPackTitle;

  /// No description provided for @settingsCudaPackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Faster transcription on GeForce RTX and GTX 16 cards. One-time download of {size}.'**
  String settingsCudaPackSubtitle(String size);

  /// No description provided for @settingsCudaPackInstalledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Installed. If your graphics driver is too old, WhisPaste keeps using Vulkan.'**
  String get settingsCudaPackInstalledSubtitle;

  /// No description provided for @settingsCudaPackConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'Consent required'**
  String get settingsCudaPackConsentRequired;

  /// No description provided for @settingsCudaPackConsentReview.
  ///
  /// In en, this message translates to:
  /// **'Review licence'**
  String get settingsCudaPackConsentReview;

  /// No description provided for @settingsCudaPackDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get settingsCudaPackDownload;

  /// No description provided for @settingsCudaPackDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent} %'**
  String settingsCudaPackDownloading(int percent);

  /// No description provided for @settingsCudaPackInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing …'**
  String get settingsCudaPackInstalling;

  /// No description provided for @settingsCudaPackCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get settingsCudaPackCancel;

  /// No description provided for @settingsCudaPackRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove CUDA pack'**
  String get settingsCudaPackRemove;

  /// No description provided for @settingsCudaPackRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove CUDA pack?'**
  String get settingsCudaPackRemoveConfirm;

  /// No description provided for @settingsCudaPackRemoveConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The CUDA pack is removed from this device. You can download it again any time.'**
  String get settingsCudaPackRemoveConfirmMessage;

  /// No description provided for @settingsCudaPackToggle.
  ///
  /// In en, this message translates to:
  /// **'Use CUDA'**
  String get settingsCudaPackToggle;

  /// No description provided for @settingsCudaPackErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Check your connection and try again.'**
  String get settingsCudaPackErrorNetwork;

  /// No description provided for @settingsCudaPackErrorVerification.
  ///
  /// In en, this message translates to:
  /// **'The download was damaged. Please try again.'**
  String get settingsCudaPackErrorVerification;

  /// No description provided for @settingsCudaPackErrorStorage.
  ///
  /// In en, this message translates to:
  /// **'The pack could not be saved. Check your free disk space.'**
  String get settingsCudaPackErrorStorage;

  /// No description provided for @cudaEulaDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'NVIDIA CUDA licence'**
  String get cudaEulaDialogTitle;

  /// No description provided for @cudaEulaDialogBody.
  ///
  /// In en, this message translates to:
  /// **'The CUDA pack contains NVIDIA components under the NVIDIA CUDA End User License Agreement ({version}). You agree to the full text of this version, which you can read via “Full text”. A further version at NVIDIA may differ. You need to accept it to download.'**
  String cudaEulaDialogBody(String version);

  /// No description provided for @cudaEulaDialogLink.
  ///
  /// In en, this message translates to:
  /// **'Further version at NVIDIA'**
  String get cudaEulaDialogLink;

  /// No description provided for @cudaEulaFullTextOpen.
  ///
  /// In en, this message translates to:
  /// **'Full text'**
  String get cudaEulaFullTextOpen;

  /// No description provided for @cudaEulaFullTextClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get cudaEulaFullTextClose;

  /// No description provided for @cudaEulaDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cudaEulaDialogCancel;

  /// No description provided for @cudaEulaDialogAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept and download'**
  String get cudaEulaDialogAccept;

  /// No description provided for @recoveryCudaDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'CUDA acceleration was switched off because of a problem on the last launch. WhisPaste now uses Vulkan, recording works as usual.'**
  String get recoveryCudaDisabledToast;

  /// No description provided for @recoveryGpuProbeFailedToast.
  ///
  /// In en, this message translates to:
  /// **'GPU acceleration is not used in this session: the check of the graphics card did not finish. WhisPaste transcribes on the processor. Recording works as usual.'**
  String get recoveryGpuProbeFailedToast;

  /// No description provided for @settingsGpuProbeTitle.
  ///
  /// In en, this message translates to:
  /// **'GPU check'**
  String get settingsGpuProbeTitle;

  /// No description provided for @settingsGpuProbeNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet. The check runs when the model loads for the first time.'**
  String get settingsGpuProbeNotChecked;

  /// No description provided for @settingsGpuProbeUsable.
  ///
  /// In en, this message translates to:
  /// **'Checked: the graphics card is used.'**
  String get settingsGpuProbeUsable;

  /// No description provided for @settingsGpuProbeUnusable.
  ///
  /// In en, this message translates to:
  /// **'Not usable: WhisPaste uses the processor. Check again after a driver or app update.'**
  String get settingsGpuProbeUnusable;

  /// No description provided for @settingsGpuProbeRetry.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get settingsGpuProbeRetry;

  /// No description provided for @supportPromptSnooze.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask for 90 days'**
  String get supportPromptSnooze;

  /// No description provided for @supportPayPalLabel.
  ///
  /// In en, this message translates to:
  /// **'PayPal'**
  String get supportPayPalLabel;

  /// No description provided for @supportStoreThankYouLine.
  ///
  /// In en, this message translates to:
  /// **'Thank you for buying WhisPaste in the store. Any further support is optional.'**
  String get supportStoreThankYouLine;

  /// No description provided for @supportShareText.
  ///
  /// In en, this message translates to:
  /// **'I use WhisPaste to speak text straight into my apps. Local on my computer and open source:'**
  String get supportShareText;

  /// No description provided for @supportPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Support WhisPaste'**
  String get supportPageTitle;

  /// No description provided for @supportIntroDirect.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste is free and open source. A contribution or recommendation helps the project.'**
  String get supportIntroDirect;

  /// No description provided for @supportCostsNote.
  ///
  /// In en, this message translates to:
  /// **'Contributions help cover development and the ongoing costs of publishing, hosting and the domain.'**
  String get supportCostsNote;

  /// No description provided for @supportSectionOnce.
  ///
  /// In en, this message translates to:
  /// **'One-time support'**
  String get supportSectionOnce;

  /// No description provided for @supportSectionOthers.
  ///
  /// In en, this message translates to:
  /// **'Other ways to support'**
  String get supportSectionOthers;

  /// No description provided for @supportSectionReach.
  ///
  /// In en, this message translates to:
  /// **'Recommend WhisPaste'**
  String get supportSectionReach;

  /// No description provided for @supportStoreTitleWindows.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste in the Microsoft Store'**
  String get supportStoreTitleWindows;

  /// No description provided for @supportStoreTitleMac.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste in the Mac App Store'**
  String get supportStoreTitleMac;

  /// No description provided for @supportStoreFactManaged.
  ///
  /// In en, this message translates to:
  /// **'Installation and updates are handled by the store.'**
  String get supportStoreFactManaged;

  /// No description provided for @supportStoreFactPurchase.
  ///
  /// In en, this message translates to:
  /// **'Your one-time purchase supports WhisPaste.'**
  String get supportStoreFactPurchase;

  /// No description provided for @supportStoreFactSameFeatures.
  ///
  /// In en, this message translates to:
  /// **'Same features. The direct version stays free to use.'**
  String get supportStoreFactSameFeatures;

  /// No description provided for @supportStoreCtaWindows.
  ///
  /// In en, this message translates to:
  /// **'View in Microsoft Store'**
  String get supportStoreCtaWindows;

  /// No description provided for @supportStoreCtaMac.
  ///
  /// In en, this message translates to:
  /// **'View in Mac App Store'**
  String get supportStoreCtaMac;

  /// No description provided for @supportStorePriceNote.
  ///
  /// In en, this message translates to:
  /// **'Price in the store'**
  String get supportStorePriceNote;

  /// No description provided for @supportStoreCoffeeNote.
  ///
  /// In en, this message translates to:
  /// **'A one-time purchase, roughly the price of a coffee. The store shows the current price.'**
  String get supportStoreCoffeeNote;

  /// No description provided for @supportStoreDismiss.
  ///
  /// In en, this message translates to:
  /// **'Hide store option'**
  String get supportStoreDismiss;

  /// No description provided for @supportStoreShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Show store option'**
  String get supportStoreShowAgain;

  /// No description provided for @supportSponsorsCta.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub Sponsors'**
  String get supportSponsorsCta;

  /// No description provided for @supportSponsorsNote.
  ///
  /// In en, this message translates to:
  /// **'Monthly or with an amount you choose. Pick the amount and rhythm there.'**
  String get supportSponsorsNote;

  /// No description provided for @supportKofiCta.
  ///
  /// In en, this message translates to:
  /// **'Open Ko-fi'**
  String get supportKofiCta;

  /// No description provided for @supportPayPalCta.
  ///
  /// In en, this message translates to:
  /// **'Support with PayPal'**
  String get supportPayPalCta;

  /// No description provided for @supportNativeTitle.
  ///
  /// In en, this message translates to:
  /// **'Support once in the store'**
  String get supportNativeTitle;

  /// No description provided for @supportNativeDescription.
  ///
  /// In en, this message translates to:
  /// **'A one-time amount, billed by the store. Same features, no subscription.'**
  String get supportNativeDescription;

  /// No description provided for @supportNativeCta.
  ///
  /// In en, this message translates to:
  /// **'Support once'**
  String get supportNativeCta;

  /// No description provided for @supportSheetChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose an amount'**
  String get supportSheetChoose;

  /// No description provided for @supportSheetLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading amounts …'**
  String get supportSheetLoading;

  /// No description provided for @supportSheetBuy.
  ///
  /// In en, this message translates to:
  /// **'Support for {price}'**
  String supportSheetBuy(String price);

  /// No description provided for @supportSheetPurchasing.
  ///
  /// In en, this message translates to:
  /// **'The store is confirming your purchase …'**
  String get supportSheetPurchasing;

  /// No description provided for @supportSheetThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your support!'**
  String get supportSheetThanks;

  /// No description provided for @supportSheetThanksDetail.
  ///
  /// In en, this message translates to:
  /// **'Your supporter badge is active now. All features stay available to everyone.'**
  String get supportSheetThanksDetail;

  /// No description provided for @supportSheetPending.
  ///
  /// In en, this message translates to:
  /// **'Your purchase is awaiting confirmation.'**
  String get supportSheetPending;

  /// No description provided for @supportSheetPurchaseError.
  ///
  /// In en, this message translates to:
  /// **'The purchase could not be completed. Please try again later.'**
  String get supportSheetPurchaseError;

  /// No description provided for @supportSheetPricesError.
  ///
  /// In en, this message translates to:
  /// **'Prices couldn\'t be loaded. Please try again later.'**
  String get supportSheetPricesError;

  /// No description provided for @supportSheetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No amounts are available in the store right now.'**
  String get supportSheetUnavailable;

  /// No description provided for @supportSheetRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get supportSheetRetry;

  /// No description provided for @supportSheetClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get supportSheetClose;

  /// No description provided for @supportSelfDeclareCta.
  ///
  /// In en, this message translates to:
  /// **'I already support WhisPaste'**
  String get supportSelfDeclareCta;

  /// No description provided for @supportSelfDeclareNote.
  ///
  /// In en, this message translates to:
  /// **'Just a note on this device, nothing is verified. The sponsor button in the status bar is hidden.'**
  String get supportSelfDeclareNote;

  /// No description provided for @supportSelfDeclareHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing is verified. Use this if you already contributed.'**
  String get supportSelfDeclareHint;

  /// No description provided for @supportSupporterLine.
  ///
  /// In en, this message translates to:
  /// **'You support WhisPaste. Thank you!'**
  String get supportSupporterLine;

  /// No description provided for @supportSupporterBadge.
  ///
  /// In en, this message translates to:
  /// **'Supporter'**
  String get supportSupporterBadge;

  /// No description provided for @supportRateCta.
  ///
  /// In en, this message translates to:
  /// **'Rate in the store'**
  String get supportRateCta;

  /// No description provided for @supportShareCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get supportShareCopy;

  /// No description provided for @supportShareCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get supportShareCopied;

  /// Error toast when no app or browser opened an external link (help, about, support, review and settings links).
  ///
  /// In en, this message translates to:
  /// **'The link couldn\'t be opened'**
  String get externalLinkOpenFailed;

  /// Action on the failed-link toast that copies the link address so the user can paste it into a browser.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get externalLinkCopyAddress;

  /// No description provided for @supportShareEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get supportShareEmail;

  /// No description provided for @supportChipLabel.
  ///
  /// In en, this message translates to:
  /// **'Sponsor'**
  String get supportChipLabel;

  /// No description provided for @supportChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Support WhisPaste'**
  String get supportChipTooltip;

  /// No description provided for @supportChipThanksLabel.
  ///
  /// In en, this message translates to:
  /// **'Thanks'**
  String get supportChipThanksLabel;

  /// No description provided for @supportChipThanksTooltip.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your support'**
  String get supportChipThanksTooltip;

  /// No description provided for @settingsSponsorChip.
  ///
  /// In en, this message translates to:
  /// **'Sponsor button in the status bar'**
  String get settingsSponsorChip;

  /// No description provided for @settingsSponsorChipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows the way to the support page. You can hide it at any time and show it again here.'**
  String get settingsSponsorChipSubtitle;

  /// Title of the dialog that previews multiline text before an automation inserts it.
  ///
  /// In en, this message translates to:
  /// **'Insert multiline text?'**
  String get automationPreviewTitle;

  /// Explains why the multiline preview dialog is shown.
  ///
  /// In en, this message translates to:
  /// **'An automation wants to insert text with line breaks. Check it before it reaches the active app.'**
  String get automationPreviewBody;

  /// Number of lines in the multiline text shown in the automation preview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 line} other{{count} lines}}'**
  String automationPreviewLineCount(int count);

  /// Confirm button that lets the automation insert the previewed multiline text.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get automationPreviewInsert;

  /// Cancel button that stops the automation from inserting the previewed multiline text.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get automationPreviewCancel;

  /// Heading of the integrations group in the automation settings.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get automationIntegrationsHeading;

  /// Row title for event hooks in the automation settings; also the title of the hooks dialog.
  ///
  /// In en, this message translates to:
  /// **'Send events to other apps'**
  String get automationIntegrationsHooksTitle;

  /// Explains what event hooks send, shown under the row title.
  ///
  /// In en, this message translates to:
  /// **'Send finished transcripts and changed notes to an app on this computer. Hooks keep firing even when the API server is off.'**
  String get automationIntegrationsHooksSubtitle;

  /// Number of configured event hooks, shown next to the manage button.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No hooks} one{1 hook} other{{count} hooks}}'**
  String automationIntegrationsHooksCount(int count);

  /// Button that opens the event hooks dialog.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get automationIntegrationsHooksManage;

  /// Row title for the command line and MCP entry points.
  ///
  /// In en, this message translates to:
  /// **'Command line and MCP'**
  String get automationIntegrationsCliTitle;

  /// Explains where the CLI and MCP server run. They exist only in source checkouts, not in store builds.
  ///
  /// In en, this message translates to:
  /// **'Source checkouts only. Run {path} with {token} set; the {command} command starts the MCP server.'**
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  );

  /// Intro text in the hooks dialog: hooks only reach loopback addresses, and delivery is retried once.
  ///
  /// In en, this message translates to:
  /// **'Finished transcripts and changed notes go to an app on this computer. The address has to be on this device.'**
  String get automationHooksIntro;

  /// Shown in the hooks dialog when no hook is configured.
  ///
  /// In en, this message translates to:
  /// **'No connection set up yet.'**
  String get automationHooksEmpty;

  /// Label of the URL input for a new hook.
  ///
  /// In en, this message translates to:
  /// **'Target address (this computer only)'**
  String get automationHooksUrlLabel;

  /// Label above the event checkboxes of a new hook.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get automationHooksEventsLabel;

  /// Checkbox label for the transcript.finished event.
  ///
  /// In en, this message translates to:
  /// **'Transcript finished'**
  String get automationHooksEventTranscript;

  /// Checkbox label for the note.changed event.
  ///
  /// In en, this message translates to:
  /// **'Note changed'**
  String get automationHooksEventNote;

  /// Button that adds the hook typed in the dialog.
  ///
  /// In en, this message translates to:
  /// **'Add hook'**
  String get automationHooksAdd;

  /// Tooltip and label of the button that removes one hook.
  ///
  /// In en, this message translates to:
  /// **'Remove hook'**
  String get automationHooksRemove;

  /// No description provided for @automationHooksRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this hook?'**
  String get automationHooksRemoveConfirm;

  /// No description provided for @automationHooksRemoveConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The hook is removed from the list. You can add it again later.'**
  String get automationHooksRemoveConfirmMessage;

  /// Validation message for a hook URL that is not a loopback http address.
  ///
  /// In en, this message translates to:
  /// **'Use {ipv4}, {ipv6} or {localhost} with a port, for example {example}.'**
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  );

  /// Validation message when a new hook has no event selected.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one event.'**
  String get automationHooksNoEvents;

  /// Validation message when the hook limit is reached.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {max} hooks.'**
  String automationHooksTooMany(int max);

  /// Button that closes the hooks dialog.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get automationHooksDone;

  /// No description provided for @navSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get navSmartMode;

  /// No description provided for @dockDictate.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get dockDictate;

  /// No description provided for @dockOverflow.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get dockOverflow;

  /// No description provided for @dockMenuGroupStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get dockMenuGroupStatus;

  /// No description provided for @dockMenuGroupNotices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get dockMenuGroupNotices;

  /// No description provided for @dockMenuHotkeyChange.
  ///
  /// In en, this message translates to:
  /// **'Change shortcut…'**
  String get dockMenuHotkeyChange;

  /// No description provided for @dockMenuSmartModeSettings.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode settings…'**
  String get dockMenuSmartModeSettings;

  /// No description provided for @dockMenuSttModels.
  ///
  /// In en, this message translates to:
  /// **'Manage speech models…'**
  String get dockMenuSttModels;

  /// No description provided for @dockMenuGroupCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get dockMenuGroupCloud;

  /// No description provided for @dockMenuModelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get dockMenuModelDownload;

  /// No description provided for @dockMenuModelLoading.
  ///
  /// In en, this message translates to:
  /// **'loading'**
  String get dockMenuModelLoading;

  /// No description provided for @dockMenuSttLockedReason.
  ///
  /// In en, this message translates to:
  /// **'Locked during a recording'**
  String get dockMenuSttLockedReason;

  /// Placeholder of the search field in a dock dropdown with many options.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get dockMenuSearchHint;

  /// Shown in a dock dropdown when the search matches no option.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get dockMenuSearchNoMatches;

  /// No description provided for @dockMenuAppliesNextRecording.
  ///
  /// In en, this message translates to:
  /// **'Applies from the next recording'**
  String get dockMenuAppliesNextRecording;

  /// No description provided for @dockStopDictation.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get dockStopDictation;

  /// Button that opens the file dialog to add audio files to the import queue.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get historyImportAddFiles;

  /// Hint under the import button: which audio formats are accepted and that transcription happens on this device. {formats} lists the formats this platform reads, e.g. WAV on Linux and Windows.
  ///
  /// In en, this message translates to:
  /// **'Transcribe audio files ({formats}) on this device. Drag files onto this page or add them.'**
  String historyImportDescription(String formats);

  /// Heading above the list of import jobs.
  ///
  /// In en, this message translates to:
  /// **'Import queue'**
  String get historyImportQueueTitle;

  /// Status of an import job that has not started yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get historyImportStatusQueued;

  /// Status while the file is copied into the app container.
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get historyImportStatusCopying;

  /// Status while the audio is decoded to 16 kHz mono.
  ///
  /// In en, this message translates to:
  /// **'Decoding'**
  String get historyImportStatusDecoding;

  /// Status while the speech engine transcribes the imported file.
  ///
  /// In en, this message translates to:
  /// **'Transcribing'**
  String get historyImportStatusTranscribing;

  /// Status of an import job that finished and created a history entry.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get historyImportStatusDone;

  /// Status of an import job that failed; the reason is shown below it.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get historyImportStatusFailed;

  /// Status of an import job the user cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get historyImportStatusCancelled;

  /// Reason shown when the file could not be copied into the app.
  ///
  /// In en, this message translates to:
  /// **'The file could not be copied. Check that it still exists and can be read, then try again.'**
  String get historyImportFailureCopy;

  /// Reason shown when the format cannot be decoded on this platform. Must not claim success.
  ///
  /// In en, this message translates to:
  /// **'This format is not supported on this platform. Convert the file to WAV and import it again.'**
  String get historyImportFailureUnsupported;

  /// Reason shown when a supported file cannot be decoded (corrupt or truncated).
  ///
  /// In en, this message translates to:
  /// **'The file could not be decoded. It is probably damaged or incomplete. Import another copy or convert it to WAV.'**
  String get historyImportFailureDecode;

  /// Reason shown when the file exceeds the import size or duration limit.
  ///
  /// In en, this message translates to:
  /// **'The file is too large or longer than 6 hours. Please split it into shorter parts.'**
  String get historyImportFailureInputLimit;

  /// Reason shown when the speech engine fails on the imported file. Retry is offered.
  ///
  /// In en, this message translates to:
  /// **'Transcription failed. Check speech recognition in Settings, then try again.'**
  String get historyImportFailureTranscription;

  /// Reason shown when the finished transcript could not be saved to history.
  ///
  /// In en, this message translates to:
  /// **'The transcript could not be saved. Check the free disk space, then try again.'**
  String get historyImportFailureSave;

  /// Message shown when the user picks a folder instead of audio files.
  ///
  /// In en, this message translates to:
  /// **'Folders cannot be imported. Choose the audio files inside them.'**
  String get historyImportRejectedFolder;

  /// Message shown when a picked file no longer exists.
  ///
  /// In en, this message translates to:
  /// **'The file was not found.'**
  String get historyImportRejectedNotFound;

  /// Message shown when a dropped file has an extension the import cannot read. {formats} lists the readable extensions, e.g. WAV, MP3.
  ///
  /// In en, this message translates to:
  /// **'This file type cannot be imported. Supported: {formats}.'**
  String historyImportRejectedType(String formats);

  /// Error toast when the system file dialog for the audio import cannot be opened. Names the drag-and-drop alternative.
  ///
  /// In en, this message translates to:
  /// **'The file dialog could not be opened. Try again, or drag the files onto this page.'**
  String get historyImportDialogFailed;

  /// Shown over the history page while audio files are dragged onto it.
  ///
  /// In en, this message translates to:
  /// **'Drop audio files here to transcribe them'**
  String get historyImportDropHere;

  /// Tooltip of the button that cancels an import job.
  ///
  /// In en, this message translates to:
  /// **'Cancel import'**
  String get historyImportCancel;

  /// Tooltip of the button that retries a failed or cancelled import job.
  ///
  /// In en, this message translates to:
  /// **'Retry import'**
  String get historyImportRetry;

  /// Banner offering to recover the audio of an interrupted recording.
  ///
  /// In en, this message translates to:
  /// **'An interrupted recording was found. Recover its audio and transcribe it?'**
  String get recoveryOffer;

  /// Banner for an interrupted recording whose audio was not kept because audio retention is off.
  ///
  /// In en, this message translates to:
  /// **'An interrupted recording was found, but no audio was kept because audio retention is off.'**
  String get recoveryNoAudioKept;

  /// Banner for an interrupted recording that had no audio written before it stopped.
  ///
  /// In en, this message translates to:
  /// **'An interrupted recording was found, but it holds no audio.'**
  String get recoveryNoAudioCaptured;

  /// Button that recovers the audio of an interrupted recording.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recoveryRestore;

  /// Button that discards an interrupted recording and its audio.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get recoveryDiscard;

  /// No description provided for @recoveryDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard this recording?'**
  String get recoveryDiscardConfirm;

  /// No description provided for @recoveryDiscardConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This interrupted recording is removed from this device, together with any audio it kept.'**
  String get recoveryDiscardConfirmMessage;

  /// Message shown when recovering the audio failed. The audio is kept for a retry.
  ///
  /// In en, this message translates to:
  /// **'Recovery failed. The audio was kept, so you can try again.'**
  String get recoveryFailed;

  /// Notice with the number of damaged recovery entries that were skipped. {count} is the number.
  ///
  /// In en, this message translates to:
  /// **'{count} damaged recovery entries were skipped and kept on disk.'**
  String recoverySkippedCorrupt(int count);

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsGroupApp;

  /// No description provided for @settingsGroupDictation.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get settingsGroupDictation;

  /// No description provided for @settingsGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsGroupSystem;

  /// No description provided for @settingsAreaGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsAreaGeneral;

  /// No description provided for @settingsAreaAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAreaAppearance;

  /// No description provided for @settingsAreaShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get settingsAreaShortcuts;

  /// No description provided for @settingsSmartModeShortcutLink.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcut: {combo}'**
  String settingsSmartModeShortcutLink(String combo);

  /// No description provided for @settingsAreaRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording & audio'**
  String get settingsAreaRecording;

  /// No description provided for @settingsAreaSpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition'**
  String get settingsAreaSpeech;

  /// No description provided for @settingsAreaTextInsert.
  ///
  /// In en, this message translates to:
  /// **'Text & insertion'**
  String get settingsAreaTextInsert;

  /// No description provided for @settingsAreaPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get settingsAreaPrivacy;

  /// No description provided for @settingsAreaAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAreaAdvanced;

  /// Version line under the settings navigation.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste {version}'**
  String settingsNavVersion(String version);

  /// No description provided for @settingsNavUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsNavUpToDate;

  /// No description provided for @settingsNavUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get settingsNavUpdateAvailable;

  /// No description provided for @settingsNavStoreUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates via the Store'**
  String get settingsNavStoreUpdates;

  /// No description provided for @settingsStoreUpdatesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store delivers updates for this build. Checking for updates in the app is not available here.'**
  String get settingsStoreUpdatesUnavailable;

  /// No description provided for @settingsStoreBetaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview builds are not offered in the store build.'**
  String get settingsStoreBetaUnavailable;

  /// No description provided for @settingsStoreCudaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available in the store build, driver downloads outside the store are not allowed there.'**
  String get settingsStoreCudaUnavailable;

  /// No description provided for @settingsOverlayPreview.
  ///
  /// In en, this message translates to:
  /// **'Overlay preview'**
  String get settingsOverlayPreview;

  /// No description provided for @settingsPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsPreviewTitle;

  /// No description provided for @settingsPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'This is how the overlay and button look while recording. Changes apply right away.'**
  String get settingsPreviewHint;

  /// No description provided for @settingsPreviewOverlayCaption.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get settingsPreviewOverlayCaption;

  /// No description provided for @settingsOverlayOptionsGroup.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get settingsOverlayOptionsGroup;

  /// No description provided for @settingsOverlayForm.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get settingsOverlayForm;

  /// No description provided for @settingsOverlayFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pill or rounded rectangle.'**
  String get settingsOverlayFormSubtitle;

  /// No description provided for @settingsOverlayFormPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get settingsOverlayFormPill;

  /// No description provided for @settingsOverlayFormRoundedRect.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get settingsOverlayFormRoundedRect;

  /// No description provided for @settingsOverlayWaveStyle.
  ///
  /// In en, this message translates to:
  /// **'Wave style'**
  String get settingsOverlayWaveStyle;

  /// No description provided for @settingsOverlayWaveStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How your voice is drawn in the overlay.'**
  String get settingsOverlayWaveStyleSubtitle;

  /// No description provided for @settingsOverlayWaveBars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get settingsOverlayWaveBars;

  /// No description provided for @settingsOverlayWaveLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get settingsOverlayWaveLine;

  /// No description provided for @settingsOverlayWaveDots.
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get settingsOverlayWaveDots;

  /// No description provided for @settingsOverlayWaveFluid.
  ///
  /// In en, this message translates to:
  /// **'Fluid outline'**
  String get settingsOverlayWaveFluid;

  /// No description provided for @settingsOverlayWaveFluidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The edge reacts to your voice. Off when reduce motion is on.'**
  String get settingsOverlayWaveFluidSubtitle;

  /// No description provided for @settingsOverlayShowTimer.
  ///
  /// In en, this message translates to:
  /// **'Show timer'**
  String get settingsOverlayShowTimer;

  /// No description provided for @settingsOverlayShowTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show the elapsed recording time in the overlay.'**
  String get settingsOverlayShowTimerSubtitle;

  /// No description provided for @settingsOverlayShowCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel symbol'**
  String get settingsOverlayShowCancel;

  /// No description provided for @settingsOverlayShowCancelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stop always stays visible. Esc still cancels.'**
  String get settingsOverlayShowCancelSubtitle;

  /// No description provided for @settingsOverlayOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get settingsOverlayOpacity;

  /// No description provided for @settingsOverlayOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Raised automatically when the wave would otherwise be too faint.'**
  String get settingsOverlayOpacitySubtitle;

  /// No description provided for @settingsOverlayOpacityFull.
  ///
  /// In en, this message translates to:
  /// **'100 %'**
  String get settingsOverlayOpacityFull;

  /// No description provided for @settingsOverlayOpacityReduced.
  ///
  /// In en, this message translates to:
  /// **'80 %'**
  String get settingsOverlayOpacityReduced;

  /// No description provided for @settingsOverlayOpacitySubtle.
  ///
  /// In en, this message translates to:
  /// **'60 %'**
  String get settingsOverlayOpacitySubtle;

  /// No description provided for @settingsFloatingButtonSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get settingsFloatingButtonSize;

  /// No description provided for @settingsFloatingButtonSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Diameter of the floating button'**
  String get settingsFloatingButtonSizeSubtitle;

  /// No description provided for @settingsFloatingButtonSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsFloatingButtonSizeSmall;

  /// No description provided for @settingsFloatingButtonSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get settingsFloatingButtonSizeMedium;

  /// No description provided for @settingsFloatingButtonSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsFloatingButtonSizeLarge;

  /// No description provided for @settingsFloatingButtonShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get settingsFloatingButtonShape;

  /// No description provided for @settingsFloatingButtonShapeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Round or rounded square'**
  String get settingsFloatingButtonShapeSubtitle;

  /// No description provided for @settingsFloatingButtonShapeRound.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get settingsFloatingButtonShapeRound;

  /// No description provided for @settingsFloatingButtonShapeSquare.
  ///
  /// In en, this message translates to:
  /// **'Rounded square'**
  String get settingsFloatingButtonShapeSquare;

  /// No description provided for @settingsFloatingButtonRing.
  ///
  /// In en, this message translates to:
  /// **'Recording ring'**
  String get settingsFloatingButtonRing;

  /// No description provided for @settingsFloatingButtonRingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Coloured ring around the button while recording'**
  String get settingsFloatingButtonRingSubtitle;

  /// No description provided for @settingsFloatingButtonIdleOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity when idle'**
  String get settingsFloatingButtonIdleOpacity;

  /// No description provided for @settingsFloatingButtonIdleOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How visible the button is when not recording'**
  String get settingsFloatingButtonIdleOpacitySubtitle;

  /// No description provided for @settingsFloatingButtonIdleOpacityReduced.
  ///
  /// In en, this message translates to:
  /// **'70 %'**
  String get settingsFloatingButtonIdleOpacityReduced;

  /// No description provided for @settingsFloatingButtonIdleOpacitySubtle.
  ///
  /// In en, this message translates to:
  /// **'40 %'**
  String get settingsFloatingButtonIdleOpacitySubtle;

  /// No description provided for @settingsOverlayColorsGroup.
  ///
  /// In en, this message translates to:
  /// **'Shared (colours)'**
  String get settingsOverlayColorsGroup;

  /// No description provided for @settingsAreaSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get settingsAreaSmartMode;

  /// No description provided for @settingsAreaDictionary.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get settingsAreaDictionary;

  /// No description provided for @settingsSearchEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Search in help'**
  String get settingsSearchEmptyHelp;

  /// No description provided for @dictionaryTabTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get dictionaryTabTerms;

  /// No description provided for @dictionaryTabReplacements.
  ///
  /// In en, this message translates to:
  /// **'Replacements'**
  String get dictionaryTabReplacements;

  /// No description provided for @dictionaryTabSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get dictionaryTabSuggestions;

  /// No description provided for @dictionaryTermsEffectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Passed to the speech recogniser as a hint. It can favour these spellings but never changes text by itself.'**
  String get dictionaryTermsEffectPrompt;

  /// No description provided for @dictionaryTermsEffectReplacementOnly.
  ///
  /// In en, this message translates to:
  /// **'The active speech engine takes no hints. Only replacements change the text. Your terms stay saved.'**
  String get dictionaryTermsEffectReplacementOnly;

  /// No description provided for @dictionaryTermsHelp.
  ///
  /// In en, this message translates to:
  /// **'Names, jargon and acronyms the recogniser often gets wrong. Separate them with commas or line breaks.'**
  String get dictionaryTermsHelp;

  /// No description provided for @dictionaryReplacementsHelp.
  ///
  /// In en, this message translates to:
  /// **'Only add words the recogniser actually gets wrong. Correctly recognised words stay untouched.'**
  String get dictionaryReplacementsHelp;

  /// No description provided for @dictionaryTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get dictionaryTestTitle;

  /// No description provided for @dictionaryTestInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Sample sentence'**
  String get dictionaryTestInputLabel;

  /// No description provided for @dictionaryTestInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type a sentence to see which replacements apply.'**
  String get dictionaryTestInputHint;

  /// No description provided for @dictionaryTestResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get dictionaryTestResultLabel;

  /// No description provided for @dictionaryTestNoChange.
  ///
  /// In en, this message translates to:
  /// **'No replacement applies.'**
  String get dictionaryTestNoChange;

  /// No description provided for @dictionaryCsvTitle.
  ///
  /// In en, this message translates to:
  /// **'Import and export (CSV)'**
  String get dictionaryCsvTitle;

  /// No description provided for @dictionaryCsvHint.
  ///
  /// In en, this message translates to:
  /// **'One line per entry: triggers separated by {pipe}, replacement text, match mode (exact or fuzzy), threshold.'**
  String dictionaryCsvHint(String pipe);

  /// No description provided for @dictionaryCsvImport.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get dictionaryCsvImport;

  /// No description provided for @dictionaryCsvExport.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get dictionaryCsvExport;

  /// Shown under the CSV export button while there are no replacements to export
  ///
  /// In en, this message translates to:
  /// **'There are no replacements to export yet.'**
  String get dictionaryCsvExportEmpty;

  /// No description provided for @dictionaryCsvImportTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This file is larger than 1 MB. Split it into smaller files.'**
  String get dictionaryCsvImportTooLarge;

  /// No description provided for @dictionaryCsvImportReadError.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read.'**
  String get dictionaryCsvImportReadError;

  /// No description provided for @dictionaryCsvImportNothing.
  ///
  /// In en, this message translates to:
  /// **'No valid entries found.'**
  String get dictionaryCsvImportNothing;

  /// No description provided for @dictionaryCsvErrorSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} lines were skipped because they are incomplete or invalid.'**
  String dictionaryCsvErrorSummary(int count);

  /// No description provided for @dictionaryCsvTruncated.
  ///
  /// In en, this message translates to:
  /// **'Only the first {count} entries were read.'**
  String dictionaryCsvTruncated(int count);

  /// No description provided for @dictionaryCsvImportDone.
  ///
  /// In en, this message translates to:
  /// **'{added} entries added.'**
  String dictionaryCsvImportDone(int added);

  /// Error toast when the dictionary CSV file could not be written (folder missing, no permission, disk full).
  ///
  /// In en, this message translates to:
  /// **'The CSV file couldn\'t be saved.'**
  String get dictionaryCsvExportFailed;

  /// No description provided for @dictionaryCsvExportDone.
  ///
  /// In en, this message translates to:
  /// **'{count} entries exported.'**
  String dictionaryCsvExportDone(int count);

  /// No description provided for @dictionaryCsvLineError.
  ///
  /// In en, this message translates to:
  /// **'Line {line}: {reason}'**
  String dictionaryCsvLineError(int line, String reason);

  /// No description provided for @dictionaryCsvReasonMissingFields.
  ///
  /// In en, this message translates to:
  /// **'Too few columns.'**
  String get dictionaryCsvReasonMissingFields;

  /// No description provided for @dictionaryCsvReasonEmptyTrigger.
  ///
  /// In en, this message translates to:
  /// **'No trigger phrase.'**
  String get dictionaryCsvReasonEmptyTrigger;

  /// No description provided for @dictionaryCsvReasonTriggerTooLong.
  ///
  /// In en, this message translates to:
  /// **'The trigger phrase is too long.'**
  String get dictionaryCsvReasonTriggerTooLong;

  /// No description provided for @dictionaryCsvReasonEmptyReplacement.
  ///
  /// In en, this message translates to:
  /// **'No replacement text.'**
  String get dictionaryCsvReasonEmptyReplacement;

  /// No description provided for @dictionaryCsvReasonReplacementTooLong.
  ///
  /// In en, this message translates to:
  /// **'The replacement text is too long.'**
  String get dictionaryCsvReasonReplacementTooLong;

  /// No description provided for @dictionaryCsvReasonUnknownMatchMode.
  ///
  /// In en, this message translates to:
  /// **'Match mode must be exact or fuzzy.'**
  String get dictionaryCsvReasonUnknownMatchMode;

  /// No description provided for @dictionaryCsvReasonInvalidThreshold.
  ///
  /// In en, this message translates to:
  /// **'The threshold must be strict, standard, tolerant or a number from 0.5 to 1.'**
  String get dictionaryCsvReasonInvalidThreshold;

  /// No description provided for @dictionaryCsvReasonControlCharacter.
  ///
  /// In en, this message translates to:
  /// **'The line contains a control or hidden formatting character, or a line break.'**
  String get dictionaryCsvReasonControlCharacter;

  /// No description provided for @dictionaryCsvReasonTooManyTriggers.
  ///
  /// In en, this message translates to:
  /// **'Too many trigger phrases in one line (at most {max}).'**
  String dictionaryCsvReasonTooManyTriggers(int max);

  /// No description provided for @dictionaryCsvPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the entries'**
  String get dictionaryCsvPreviewTitle;

  /// No description provided for @dictionaryDuplicateBadge.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get dictionaryDuplicateBadge;

  /// No description provided for @dictionaryDuplicateHint.
  ///
  /// In en, this message translates to:
  /// **'Another entry uses the same trigger. The entry listed first applies.'**
  String get dictionaryDuplicateHint;

  /// No description provided for @dictionaryUsageCount.
  ///
  /// In en, this message translates to:
  /// **'Used {count}×'**
  String dictionaryUsageCount(int count);

  /// No description provided for @dictionaryFavouriteLabel.
  ///
  /// In en, this message translates to:
  /// **'Favourite'**
  String get dictionaryFavouriteLabel;

  /// No description provided for @dictionarySuggestionsHint.
  ///
  /// In en, this message translates to:
  /// **'A suggestion appears once the same correction was made {count} times. Nothing is added without your confirmation.'**
  String dictionarySuggestionsHint(int count);

  /// No description provided for @dictionarySuggestionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No suggestions yet'**
  String get dictionarySuggestionsEmpty;

  /// No description provided for @dictionarySuggestionsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When you correct the same word twice, WhisPaste offers a replacement here.'**
  String get dictionarySuggestionsEmptyHint;

  /// No description provided for @dictionarySuggestionAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get dictionarySuggestionAccept;

  /// No description provided for @dictionarySuggestionReject.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dictionarySuggestionReject;

  /// No description provided for @dictionarySuggestionAccepted.
  ///
  /// In en, this message translates to:
  /// **'Replacement added.'**
  String get dictionarySuggestionAccepted;

  /// No description provided for @dictionarySuggestionRejected.
  ///
  /// In en, this message translates to:
  /// **'Suggestion dismissed. It will not come back.'**
  String get dictionarySuggestionRejected;

  /// No description provided for @dictionaryCsvPreviewIntro.
  ///
  /// In en, this message translates to:
  /// **'Entries marked “will be added” go into your list. Existing entries stay as they are.'**
  String get dictionaryCsvPreviewIntro;

  /// No description provided for @dictionaryCsvPreviewAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count} entries'**
  String dictionaryCsvPreviewAddCount(int count);

  /// No description provided for @dictionaryCsvImportEncodingError.
  ///
  /// In en, this message translates to:
  /// **'The file is not UTF-8 text.'**
  String get dictionaryCsvImportEncodingError;

  /// No description provided for @dictionaryCsvRefusedFormat.
  ///
  /// In en, this message translates to:
  /// **'This file uses a package format this app cannot read.'**
  String get dictionaryCsvRefusedFormat;

  /// No description provided for @dictionaryCsvRefusedType.
  ///
  /// In en, this message translates to:
  /// **'This file is not a replacement dictionary package.'**
  String get dictionaryCsvRefusedType;

  /// No description provided for @dictionaryCsvPackageHeader.
  ///
  /// In en, this message translates to:
  /// **'Package: {name} (created {date})'**
  String dictionaryCsvPackageHeader(String name, String date);

  /// No description provided for @dictionaryCsvPackageNone.
  ///
  /// In en, this message translates to:
  /// **'No package info (older or foreign file)'**
  String get dictionaryCsvPackageNone;

  /// No description provided for @dictionaryCsvSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'New: {added} · Duplicates: {duplicates} · Conflicts: {conflicts} · Circular references: {circular} · Invalid: {errors}'**
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  );

  /// No description provided for @dictionaryCsvStrategyLabel.
  ///
  /// In en, this message translates to:
  /// **'When a trigger already exists'**
  String get dictionaryCsvStrategyLabel;

  /// No description provided for @dictionaryCsvStrategySkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get dictionaryCsvStrategySkip;

  /// No description provided for @dictionaryCsvStrategyOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get dictionaryCsvStrategyOverwrite;

  /// No description provided for @dictionaryCsvStrategyKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get dictionaryCsvStrategyKeepBoth;

  /// No description provided for @dictionaryCsvStrategySkipHint.
  ///
  /// In en, this message translates to:
  /// **'The row is not imported. Existing entries stay unchanged.'**
  String get dictionaryCsvStrategySkipHint;

  /// No description provided for @dictionaryCsvStrategyOverwriteHint.
  ///
  /// In en, this message translates to:
  /// **'The shared trigger is removed from the old entry and the row is added. {changed} existing entries change or are deleted.'**
  String dictionaryCsvStrategyOverwriteHint(int changed);

  /// No description provided for @dictionaryCsvStrategyKeepBothHint.
  ///
  /// In en, this message translates to:
  /// **'The row is added as well. For the same trigger, the existing entry that comes first in the list still applies.'**
  String get dictionaryCsvStrategyKeepBothHint;

  /// No description provided for @dictionaryCsvStatusAdded.
  ///
  /// In en, this message translates to:
  /// **'will be added'**
  String get dictionaryCsvStatusAdded;

  /// No description provided for @dictionaryCsvStatusDuplicate.
  ///
  /// In en, this message translates to:
  /// **'already present'**
  String get dictionaryCsvStatusDuplicate;

  /// No description provided for @dictionaryCsvStatusConflictSkipped.
  ///
  /// In en, this message translates to:
  /// **'conflict, skipped'**
  String get dictionaryCsvStatusConflictSkipped;

  /// No description provided for @dictionaryCsvStatusConflictReplaced.
  ///
  /// In en, this message translates to:
  /// **'conflict, replaces the existing trigger'**
  String get dictionaryCsvStatusConflictReplaced;

  /// No description provided for @dictionaryCsvStatusConflictKept.
  ///
  /// In en, this message translates to:
  /// **'conflict, added alongside'**
  String get dictionaryCsvStatusConflictKept;

  /// No description provided for @dictionaryCsvStatusSuperseded.
  ///
  /// In en, this message translates to:
  /// **'replaced by a later row in this file'**
  String get dictionaryCsvStatusSuperseded;

  /// No description provided for @dictionaryCsvStatusCircular.
  ///
  /// In en, this message translates to:
  /// **'circular reference, not imported'**
  String get dictionaryCsvStatusCircular;

  /// No description provided for @dictionaryCsvRowWillAdd.
  ///
  /// In en, this message translates to:
  /// **'Will be added'**
  String get dictionaryCsvRowWillAdd;

  /// No description provided for @dictionaryCsvRowSkipped.
  ///
  /// In en, this message translates to:
  /// **'Duplicate, skipped'**
  String get dictionaryCsvRowSkipped;

  /// No description provided for @dictionaryCsvExportSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose entries to export'**
  String get dictionaryCsvExportSelectTitle;

  /// No description provided for @dictionaryCsvExportSelectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} entries to choose from'**
  String dictionaryCsvExportSelectSubtitle(int count);

  /// No description provided for @dictionaryCsvAllPresent.
  ///
  /// In en, this message translates to:
  /// **'All entries are already present. Nothing will be written.'**
  String get dictionaryCsvAllPresent;

  /// No description provided for @dictionaryCsvExportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export ({count})'**
  String dictionaryCsvExportConfirm(int count);

  /// No description provided for @dictionaryCsvExportTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many entries for one file: {count}. Choose fewer (at most 5000 entries, 1 MiB).'**
  String dictionaryCsvExportTooMany(int count);

  /// No description provided for @settingsBetaGroupHeading.
  ///
  /// In en, this message translates to:
  /// **'Pre-releases'**
  String get settingsBetaGroupHeading;

  /// No description provided for @analyticsWordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Wording'**
  String get analyticsWordingTitle;

  /// No description provided for @analyticsWordingPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Words: raw vs. revised'**
  String get analyticsWordingPanelTitle;

  /// No description provided for @analyticsRawWords.
  ///
  /// In en, this message translates to:
  /// **'Raw words'**
  String get analyticsRawWords;

  /// No description provided for @analyticsRevisedWords.
  ///
  /// In en, this message translates to:
  /// **'Revised words'**
  String get analyticsRevisedWords;

  /// No description provided for @analyticsTransformActions.
  ///
  /// In en, this message translates to:
  /// **'Recordings revised by actions'**
  String get analyticsTransformActions;

  /// No description provided for @analyticsCorrectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequent corrections'**
  String get analyticsCorrectionsTitle;

  /// No description provided for @analyticsNoCorrections.
  ///
  /// In en, this message translates to:
  /// **'No corrections recorded yet.'**
  String get analyticsNoCorrections;

  /// No description provided for @errorNoticeNoModelCause.
  ///
  /// In en, this message translates to:
  /// **'No speech model is installed.'**
  String get errorNoticeNoModelCause;

  /// No description provided for @errorNoticeNoModelNext.
  ///
  /// In en, this message translates to:
  /// **'Download a model in Settings, then try again.'**
  String get errorNoticeNoModelNext;

  /// No description provided for @errorNoticeMicCause.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste has no access to the microphone.'**
  String get errorNoticeMicCause;

  /// No description provided for @errorNoticeMicNext.
  ///
  /// In en, this message translates to:
  /// **'Allow access in your system settings, then try again.'**
  String get errorNoticeMicNext;

  /// No description provided for @errorNoticeTranscribeCause.
  ///
  /// In en, this message translates to:
  /// **'Transcription failed.'**
  String get errorNoticeTranscribeCause;

  /// No description provided for @errorNoticeTranscribeNext.
  ///
  /// In en, this message translates to:
  /// **'Try again. If it keeps failing, restart WhisPaste or choose another model in Settings.'**
  String get errorNoticeTranscribeNext;

  /// No description provided for @errorNoticeCpuCause.
  ///
  /// In en, this message translates to:
  /// **'The GPU could not be used for this transcription.'**
  String get errorNoticeCpuCause;

  /// No description provided for @errorNoticeCpuNext.
  ///
  /// In en, this message translates to:
  /// **'It ran on the CPU instead, which is slower. Check GPU acceleration in Settings.'**
  String get errorNoticeCpuNext;

  /// No description provided for @languageMismatchHint.
  ///
  /// In en, this message translates to:
  /// **'The detected language does not match your setting.'**
  String get languageMismatchHint;

  /// No description provided for @languageMismatchSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch language'**
  String get languageMismatchSwitch;

  /// Notice when the Parakeet engine is active but the recognition language is not in its supported set. {language} is the localized language name.
  ///
  /// In en, this message translates to:
  /// **'Parakeet cannot transcribe {language}. Switch to Whisper?'**
  String parakeetLanguageUnsupported(String language);

  /// No description provided for @parakeetLanguageSwitchToWhisper.
  ///
  /// In en, this message translates to:
  /// **'Switch to Whisper'**
  String get parakeetLanguageSwitchToWhisper;

  /// Screen reader label of the minimize button in the custom title bar (Windows and Linux).
  ///
  /// In en, this message translates to:
  /// **'Minimize window'**
  String get titleBarMinimizeLabel;

  /// Screen reader label of the close button in the custom title bar (Windows and Linux).
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get titleBarCloseLabel;

  /// Screen reader label of the maximize button in the custom title bar (Windows and Linux).
  ///
  /// In en, this message translates to:
  /// **'Maximize window'**
  String get titleBarMaximizeLabel;

  /// Screen reader label of the maximize button while the window is maximized (Windows and Linux).
  ///
  /// In en, this message translates to:
  /// **'Restore window'**
  String get titleBarRestoreLabel;

  /// No description provided for @notificationSmartModeSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: Smart Mode skipped'**
  String get notificationSmartModeSkippedTitle;

  /// Title of the system notification when another app holds the configured hotkey and the safe default is active (XP-5-09). The body reuses hotkeyFallbackActive.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: hotkey taken'**
  String get notificationHotkeyFallbackTitle;

  /// No description provided for @notificationSmartModeSkippedBody.
  ///
  /// In en, this message translates to:
  /// **'Post-processing could not be applied.'**
  String get notificationSmartModeSkippedBody;

  /// No description provided for @notificationSmartModeSkippedNoTextModel.
  ///
  /// In en, this message translates to:
  /// **'No text model is loaded, so post-processing was skipped.'**
  String get notificationSmartModeSkippedNoTextModel;

  /// No description provided for @notificationSmartModeSkippedTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Post-processing took too long.'**
  String get notificationSmartModeSkippedTimedOut;

  /// No description provided for @notificationSmartModeOutcomePasted.
  ///
  /// In en, this message translates to:
  /// **'The unedited text was pasted.'**
  String get notificationSmartModeOutcomePasted;

  /// No description provided for @notificationSmartModeOutcomeUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'It could not be confirmed whether the unedited text was pasted.'**
  String get notificationSmartModeOutcomeUnconfirmed;

  /// No description provided for @notificationSmartModeOutcomeClipboard.
  ///
  /// In en, this message translates to:
  /// **'The unedited text is on the clipboard, but it was not pasted.'**
  String get notificationSmartModeOutcomeClipboard;

  /// No description provided for @notificationSmartModeOutcomeNone.
  ///
  /// In en, this message translates to:
  /// **'The unedited text was not pasted.'**
  String get notificationSmartModeOutcomeNone;

  /// No description provided for @smartModeNoTextModelHint.
  ///
  /// In en, this message translates to:
  /// **'No text model is set up – until one is, only “Off” can be picked.'**
  String get smartModeNoTextModelHint;

  /// No description provided for @smartModeLoadTextModelAction.
  ///
  /// In en, this message translates to:
  /// **'No text model – load now'**
  String get smartModeLoadTextModelAction;

  /// No description provided for @smartModeAddOpenAiKeyAction.
  ///
  /// In en, this message translates to:
  /// **'Add OpenAI key'**
  String get smartModeAddOpenAiKeyAction;

  /// No description provided for @settingsPortabilityErrorInvalidFile.
  ///
  /// In en, this message translates to:
  /// **'The file is not a valid WhisPaste export.'**
  String get settingsPortabilityErrorInvalidFile;

  /// No description provided for @settingsPortabilityErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'The file or settings could not be processed.'**
  String get settingsPortabilityErrorGeneric;

  /// No description provided for @historyImportAudioLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get historyImportAudioLabel;

  /// No description provided for @hotkeyConflictNoteSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Spotlight'**
  String get hotkeyConflictNoteSpotlight;

  /// No description provided for @hotkeyConflictNoteAppSwitcher.
  ///
  /// In en, this message translates to:
  /// **'App Switcher'**
  String get hotkeyConflictNoteAppSwitcher;

  /// No description provided for @hotkeyConflictNoteQuitApp.
  ///
  /// In en, this message translates to:
  /// **'Quit App'**
  String get hotkeyConflictNoteQuitApp;

  /// No description provided for @hotkeyConflictNoteCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get hotkeyConflictNoteCloseWindow;

  /// No description provided for @hotkeyConflictNoteHideApp.
  ///
  /// In en, this message translates to:
  /// **'Hide App'**
  String get hotkeyConflictNoteHideApp;

  /// No description provided for @hotkeyConflictNoteMinimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize window'**
  String get hotkeyConflictNoteMinimizeWindow;

  /// No description provided for @hotkeyConflictNoteCycleWindows.
  ///
  /// In en, this message translates to:
  /// **'Cycle windows'**
  String get hotkeyConflictNoteCycleWindows;

  /// No description provided for @hotkeyConflictNoteScreenshotFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Screenshot (full screen)'**
  String get hotkeyConflictNoteScreenshotFullScreen;

  /// No description provided for @hotkeyConflictNoteScreenshotSelection.
  ///
  /// In en, this message translates to:
  /// **'Screenshot (selection)'**
  String get hotkeyConflictNoteScreenshotSelection;

  /// No description provided for @hotkeyConflictNoteScreenshotRecording.
  ///
  /// In en, this message translates to:
  /// **'Screenshot/Screen Recording'**
  String get hotkeyConflictNoteScreenshotRecording;

  /// No description provided for @hotkeyConflictNoteEmojiPicker.
  ///
  /// In en, this message translates to:
  /// **'Emoji & Symbols picker'**
  String get hotkeyConflictNoteEmojiPicker;

  /// No description provided for @hotkeyConflictNoteForceQuit.
  ///
  /// In en, this message translates to:
  /// **'Force Quit dialog'**
  String get hotkeyConflictNoteForceQuit;

  /// No description provided for @hotkeyConflictNoteLockWorkstation.
  ///
  /// In en, this message translates to:
  /// **'Lock workstation'**
  String get hotkeyConflictNoteLockWorkstation;

  /// No description provided for @hotkeyConflictNoteShowDesktop.
  ///
  /// In en, this message translates to:
  /// **'Show/Hide Desktop'**
  String get hotkeyConflictNoteShowDesktop;

  /// No description provided for @hotkeyConflictNoteFileExplorer.
  ///
  /// In en, this message translates to:
  /// **'File Explorer'**
  String get hotkeyConflictNoteFileExplorer;

  /// No description provided for @hotkeyConflictNoteRunDialog.
  ///
  /// In en, this message translates to:
  /// **'Run dialog'**
  String get hotkeyConflictNoteRunDialog;

  /// No description provided for @hotkeyConflictNoteSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get hotkeyConflictNoteSettings;

  /// No description provided for @hotkeyConflictNoteSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get hotkeyConflictNoteSearch;

  /// No description provided for @hotkeyConflictNoteTaskView.
  ///
  /// In en, this message translates to:
  /// **'Task View'**
  String get hotkeyConflictNoteTaskView;

  /// No description provided for @hotkeyConflictNoteInputLanguageSwitch.
  ///
  /// In en, this message translates to:
  /// **'Input language switch'**
  String get hotkeyConflictNoteInputLanguageSwitch;

  /// No description provided for @hotkeyConflictNoteMaximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize window'**
  String get hotkeyConflictNoteMaximizeWindow;

  /// No description provided for @hotkeyConflictNoteSnapLeft.
  ///
  /// In en, this message translates to:
  /// **'Snap window left'**
  String get hotkeyConflictNoteSnapLeft;

  /// No description provided for @hotkeyConflictNoteSnapRight.
  ///
  /// In en, this message translates to:
  /// **'Snap window right'**
  String get hotkeyConflictNoteSnapRight;

  /// No description provided for @hotkeyConflictNoteSecurityOptionsTaskManager.
  ///
  /// In en, this message translates to:
  /// **'Security options / Task Manager'**
  String get hotkeyConflictNoteSecurityOptionsTaskManager;

  /// No description provided for @hotkeyConflictNoteTaskManager.
  ///
  /// In en, this message translates to:
  /// **'Task Manager'**
  String get hotkeyConflictNoteTaskManager;

  /// No description provided for @hotkeyConflictNoteLockScreenGnomeKde.
  ///
  /// In en, this message translates to:
  /// **'Lock screen (GNOME/KDE)'**
  String get hotkeyConflictNoteLockScreenGnomeKde;

  /// No description provided for @hotkeyConflictNoteRunDialogKde.
  ///
  /// In en, this message translates to:
  /// **'Run dialog (KDE)'**
  String get hotkeyConflictNoteRunDialogKde;

  /// No description provided for @hotkeyConflictNoteLogoutShutdownDialog.
  ///
  /// In en, this message translates to:
  /// **'System logout/shutdown dialog'**
  String get hotkeyConflictNoteLogoutShutdownDialog;

  /// No description provided for @hotkeyConflictNoteOpenTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open terminal (GNOME/KDE default)'**
  String get hotkeyConflictNoteOpenTerminal;

  /// No description provided for @hotkeyConflictNoteLockScreenGnome.
  ///
  /// In en, this message translates to:
  /// **'Lock screen (GNOME)'**
  String get hotkeyConflictNoteLockScreenGnome;

  /// No description provided for @hotkeyConflictNoteActivityOverviewKde.
  ///
  /// In en, this message translates to:
  /// **'Activity overview (KDE)'**
  String get hotkeyConflictNoteActivityOverviewKde;

  /// No description provided for @settingsTextProcessingHeading.
  ///
  /// In en, this message translates to:
  /// **'Text processing'**
  String get settingsTextProcessingHeading;

  /// No description provided for @settingsShowNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reports problems, for example blocked Auto-Paste or a missing microphone signal.'**
  String get settingsShowNotificationsSubtitle;

  /// No description provided for @settingsGainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Boosts the microphone signal before it is recorded. Values that are too high can distort the recording.'**
  String get settingsGainSubtitle;

  /// No description provided for @settingsAfterTranscriptionActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What happens to the recognized text. Auto-Paste puts it right at the cursor.'**
  String get settingsAfterTranscriptionActionSubtitle;

  /// No description provided for @settingsRecognitionLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The language the recognition expects. Automatic detection works well in most cases. A fixed language is often more accurate for short recordings.'**
  String get settingsRecognitionLanguageSubtitle;

  /// No description provided for @settingsOpenAiApiKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own OpenAI key. Only needed if you use OpenAI for recognition or Smart Mode. Audio and text then go straight to OpenAI and are billed by them.'**
  String get settingsOpenAiApiKeySubtitle;

  /// No description provided for @settingsDeepgramApiKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own Deepgram key. Only needed if you use Deepgram for recognition. Audio then goes straight to Deepgram and is billed by them.'**
  String get settingsDeepgramApiKeySubtitle;

  /// No description provided for @settingsResetToDefaultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Resets all settings, API keys and statistics. Recordings, notes and models are kept.'**
  String get settingsResetToDefaultsSubtitle;

  /// No description provided for @settingsFactoryResetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Immediately deletes all transcriptions, notes, audio files, Dictionary, Snippets, models, logs and settings on this device. This can\'t be undone.'**
  String get settingsFactoryResetSubtitle;

  /// No description provided for @settingsHotkeyEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The hotkey starts a recording from any app. When it\'s off, WhisPaste ignores the hotkey.'**
  String get settingsHotkeyEnabledSubtitle;

  /// No description provided for @settingsCheckForUpdatesNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Looks for a new version right away. It\'s only installed after you confirm.'**
  String get settingsCheckForUpdatesNowSubtitle;

  /// No description provided for @settingsHistoryRetentionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How many transcriptions are kept before older ones move to the trash. Trashed transcriptions are permanently deleted after the chosen time. Favorites always stay. Saved audio files are removed no later than 30 days after recording, regardless of this setting.'**
  String get settingsHistoryRetentionSubtitle;

  /// No description provided for @smartModeTargetLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only for the Translate preset.'**
  String get smartModeTargetLanguageSubtitle;

  /// No description provided for @settingsPortabilityErrorTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is too large to import (limit: about 5 MB). Choose a settings file that WhisPaste exported.'**
  String get settingsPortabilityErrorTooLarge;

  /// No description provided for @settingsSearchKeywordsInterface.
  ///
  /// In en, this message translates to:
  /// **'theme, dark mode, light mode, appearance, language, startup, launch, minimized, notifications, system language, panel, side panel, quick paste, quick-paste, clipboard panel, panel position, screen edge, edge, dock, tray, CPU, indicator, status bar, utilization'**
  String get settingsSearchKeywordsInterface;

  /// No description provided for @settingsSearchKeywordsStt.
  ///
  /// In en, this message translates to:
  /// **'model, whisper, quality, transcription, speech recognition, local, on-device, cloud, language, timeout, vocabulary, dictionary, words, STT, voice, deepgram, openai, api key, numbers only, punctuation, priming, engine, silence, trim, filler words, filler, line break, paragraph, new line, GPU, graphics, acceleration, processor, hardware'**
  String get settingsSearchKeywordsStt;

  /// No description provided for @settingsSearchKeywordsSmartMode.
  ///
  /// In en, this message translates to:
  /// **'preset, cleanup, concise, translate, gemma, model, text model, download, post-processing, polish, edit selection, selection, selected text, rewrite'**
  String get settingsSearchKeywordsSmartMode;

  /// No description provided for @settingsSearchKeywordsAudio.
  ///
  /// In en, this message translates to:
  /// **'microphone, recording, gain, volume, push to talk, hold to record, input, mic'**
  String get settingsSearchKeywordsAudio;

  /// No description provided for @settingsSearchKeywordsAfterTranscription.
  ///
  /// In en, this message translates to:
  /// **'clipboard, paste, auto-paste, copy, action, output, do nothing, blocklist, restore clipboard, keep transcript, previous content'**
  String get settingsSearchKeywordsAfterTranscription;

  /// No description provided for @settingsSearchKeywordsOverlay.
  ///
  /// In en, this message translates to:
  /// **'overlay, floating overlay, display, status, position, waveform, top center, bottom center, start position, live transcript'**
  String get settingsSearchKeywordsOverlay;

  /// No description provided for @settingsSearchKeywordsOverlayBackground.
  ///
  /// In en, this message translates to:
  /// **'background, color, colour, marine, graphite, glacier, glass, solid, amber'**
  String get settingsSearchKeywordsOverlayBackground;

  /// No description provided for @settingsSearchKeywordsOverlayWave.
  ///
  /// In en, this message translates to:
  /// **'wave, waves, color, colour, cyan, violet, neutral, animation, amber'**
  String get settingsSearchKeywordsOverlayWave;

  /// No description provided for @settingsSearchKeywordsFloatingButton.
  ///
  /// In en, this message translates to:
  /// **'floating button, always on top, recording button, quick access, button'**
  String get settingsSearchKeywordsFloatingButton;

  /// No description provided for @settingsSearchKeywordsHotkey.
  ///
  /// In en, this message translates to:
  /// **'keyboard shortcut, hotkey, key binding, shortcut, global key, keyboard, hotkeys, keybinding'**
  String get settingsSearchKeywordsHotkey;

  /// No description provided for @settingsSearchKeywordsSound.
  ///
  /// In en, this message translates to:
  /// **'sound, audio cue, beep, volume, recording sound, notification, completion sound, cue'**
  String get settingsSearchKeywordsSound;

  /// No description provided for @settingsSearchKeywordsRecordingSafety.
  ///
  /// In en, this message translates to:
  /// **'safety, silence, auto-stop, timeout, microphone timeout, silence detection, protection, dead mic, max duration'**
  String get settingsSearchKeywordsRecordingSafety;

  /// No description provided for @settingsSearchKeywordsHistory.
  ///
  /// In en, this message translates to:
  /// **'recordings, entries, trash, cleanup, retention, maximum, auto-delete, storage, delete, hide, privacy, lock, protect, PIN protection, history'**
  String get settingsSearchKeywordsHistory;

  /// No description provided for @settingsSearchKeywordsSettingsPortability.
  ///
  /// In en, this message translates to:
  /// **'export, import, migrate, transfer, move, backup, restore, device change, portability, new computer, automatic backup, auto backup, autosave'**
  String get settingsSearchKeywordsSettingsPortability;

  /// No description provided for @settingsSearchKeywordsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'reset, defaults, factory reset'**
  String get settingsSearchKeywordsAdvanced;

  /// No description provided for @settingsSearchKeywordsAutomationApi.
  ///
  /// In en, this message translates to:
  /// **'automation, api, script, token, bearer, http, localhost, port'**
  String get settingsSearchKeywordsAutomationApi;

  /// No description provided for @settingsSearchKeywordsUpdates.
  ///
  /// In en, this message translates to:
  /// **'update, beta, channel, release channel, pre-release, check, automatic, new version, stable, version'**
  String get settingsSearchKeywordsUpdates;

  /// No description provided for @settingsSearchKeywordsOnboardingReview.
  ///
  /// In en, this message translates to:
  /// **'introduction, onboarding, setup, first run, tour, walkthrough, getting started, again, replay'**
  String get settingsSearchKeywordsOnboardingReview;

  /// No description provided for @settingsSearchKeywordsReviewSupport.
  ///
  /// In en, this message translates to:
  /// **'rate, rating, review, stars, store, support'**
  String get settingsSearchKeywordsReviewSupport;

  /// No description provided for @settingsSearchKeywordsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'privacy, analytics, statistics, tracking, anonymous, error reports, crash reports, usage stats, data, share, consent, keep recordings, recent recordings'**
  String get settingsSearchKeywordsPrivacy;

  /// No description provided for @manualNoticeLabel.
  ///
  /// In en, this message translates to:
  /// **'Message shown in the app'**
  String get manualNoticeLabel;

  /// No description provided for @manualC01Title.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get manualC01Title;

  /// No description provided for @manualC01S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Setup on first start'**
  String get manualC01S1Heading;

  /// No description provided for @manualC01S1B1.
  ///
  /// In en, this message translates to:
  /// **'On first start, WhisPaste guides you through the setup. You can go back to any step, and you can change everything later in Settings.'**
  String get manualC01S1B1;

  /// No description provided for @manualC01S1B2I1.
  ///
  /// In en, this message translates to:
  /// **'Welcome: a short overview of WhisPaste.'**
  String get manualC01S1B2I1;

  /// No description provided for @manualC01S1B2I2.
  ///
  /// In en, this message translates to:
  /// **'Privacy: what stays on your device.'**
  String get manualC01S1B2I2;

  /// No description provided for @manualC01S1B2I3.
  ///
  /// In en, this message translates to:
  /// **'Speech model: choose the speech model and download it. If an API key for a cloud provider is already saved, you can choose that provider instead.'**
  String get manualC01S1B2I3;

  /// No description provided for @manualC01S1B2I4.
  ///
  /// In en, this message translates to:
  /// **'Hotkey: set the key combination that starts a recording.'**
  String get manualC01S1B2I4;

  /// No description provided for @manualC01S1B2I5.
  ///
  /// In en, this message translates to:
  /// **'Appearance: turn start at login on or off.'**
  String get manualC01S1B2I5;

  /// No description provided for @manualC01S1B2I6.
  ///
  /// In en, this message translates to:
  /// **'{k1}: whether text is pasted automatically. On Linux, this step is skipped.'**
  String manualC01S1B2I6(String k1);

  /// No description provided for @manualC01S1B2I7.
  ///
  /// In en, this message translates to:
  /// **'Try it: a test recording, then you are ready. Without a speech model or a chosen cloud provider with an API key, finishing stays locked.'**
  String get manualC01S1B2I7;

  /// No description provided for @manualC01S2Heading.
  ///
  /// In en, this message translates to:
  /// **'System requirements'**
  String get manualC01S2Heading;

  /// No description provided for @manualC01S2B1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste needs a device with at least {ram} of memory (RAM). On devices with less, WhisPaste shows only a notice instead of the app.'**
  String manualC01S2B1(String ram);

  /// No description provided for @manualC01S2B2.
  ///
  /// In en, this message translates to:
  /// **'You need a microphone to record. In onboarding you can continue without one, but you can only record once a microphone is connected.'**
  String get manualC01S2B2;

  /// No description provided for @manualC01S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Downloading a speech model'**
  String get manualC01S3Heading;

  /// No description provided for @manualC01S3B1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste turns your speech into text, either on your device or through a cloud provider with your own key. On your device it needs a model. You start the download yourself; it does not start automatically.'**
  String get manualC01S3B1;

  /// No description provided for @manualC01S3B2I1.
  ///
  /// In en, this message translates to:
  /// **'Parakeet: fast, for European languages, about {k1}.'**
  String manualC01S3B2I1(String k1);

  /// No description provided for @manualC01S3B2I2.
  ///
  /// In en, this message translates to:
  /// **'Whisper: all 99 languages, models from about {k1} to about {k2}.'**
  String manualC01S3B2I2(String k1, String k2);

  /// No description provided for @manualC01S3B2I3.
  ///
  /// In en, this message translates to:
  /// **'The models are stored in the app’s data folder, in the {k1} subfolder.'**
  String manualC01S3B2I3(String k1);

  /// No description provided for @manualC01S3B4.
  ///
  /// In en, this message translates to:
  /// **'A Whisper model stays loaded after a recording, so the next start is faster. Under “Keep model loaded” in the speech recognition section you choose: Always (default) saves waiting time but needs the memory all the time. Automatic keeps the model loaded when your computer has enough memory, otherwise it unloads after 5 minutes. After idle time unloads it after the time you set. When memory runs short, WhisPaste unloads the model automatically and loads it again once there is room.'**
  String get manualC01S3B4;

  /// No description provided for @manualC01S3B3.
  ///
  /// In en, this message translates to:
  /// **'In the Speech recognition area, the entry “Re-run benchmark” measures how fast each installed tier runs on your computer. The results show on the model cards how much longer a tier takes and determine the recommended Whisper tier. For European languages WhisPaste recommends Parakeet instead. The test does not start during a recording.'**
  String get manualC01S3B3;

  /// No description provided for @manualC02Title.
  ///
  /// In en, this message translates to:
  /// **'Recording and pasting'**
  String get manualC02Title;

  /// No description provided for @manualC02S1Heading.
  ///
  /// In en, this message translates to:
  /// **'The hotkey'**
  String get manualC02S1Heading;

  /// No description provided for @manualC02S1B1.
  ///
  /// In en, this message translates to:
  /// **'The hotkey is a key combination that works in every program. Default: {k2} on Windows and Linux, {k3} on Mac. You can change it under Settings → Keyboard shortcuts.'**
  String manualC02S1B1(String k2, String k3);

  /// No description provided for @manualC02S1B2.
  ///
  /// In en, this message translates to:
  /// **'If another program already uses the combination, WhisPaste uses {k2} instead for the hotkey (on Mac, {k3}). The other hotkeys stay off until you set a free combination.'**
  String manualC02S1B2(String k2, String k3);

  /// No description provided for @manualC02S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Hold or toggle'**
  String get manualC02S2Heading;

  /// No description provided for @manualC02S2B1.
  ///
  /// In en, this message translates to:
  /// **'In Settings → Keyboard shortcuts, choose how the hotkey works:'**
  String get manualC02S2B1;

  /// No description provided for @manualC02S2B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Hold to record” on: hold the hotkey, speak, and release. Releasing ends the recording.'**
  String get manualC02S2B2I1;

  /// No description provided for @manualC02S2B2I2.
  ///
  /// In en, this message translates to:
  /// **'Off: one press starts the recording, a second press ends it.'**
  String get manualC02S2B2I2;

  /// No description provided for @manualC02S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Seeing the recording'**
  String get manualC02S3Heading;

  /// No description provided for @manualC02S3B1.
  ///
  /// In en, this message translates to:
  /// **'The dock at the bottom of the main window shows the current state. While recording, the main button changes to “Stop recording”, and the status area shows the current step. The dock is always there and cannot be turned off.'**
  String get manualC02S3B1;

  /// No description provided for @manualC02S3B3.
  ///
  /// In en, this message translates to:
  /// **'In a narrow window, the dock moves less important controls into the “More” menu, including the hotkey, the Auto-Paste hint, and the update notice. Everything stays reachable there.'**
  String get manualC02S3B3;

  /// No description provided for @manualC02S3B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Recording overlay” set to “Floating (always visible)”: a small waveform overlay above all programs. Default: off.'**
  String get manualC02S3B2I1;

  /// No description provided for @manualC02S3B2I2.
  ///
  /// In en, this message translates to:
  /// **'“Floating button”: a button you click to record. Default: off. On Linux under Wayland, the desktop may limit its position and whether it stays on top.'**
  String get manualC02S3B2I2;

  /// No description provided for @manualC02S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Pasting after recording'**
  String get manualC02S4Heading;

  /// No description provided for @manualC02S4B1.
  ///
  /// In en, this message translates to:
  /// **'Under “After transcription”, choose what happens after each recording:'**
  String get manualC02S4B1;

  /// No description provided for @manualC02S4B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Copy to clipboard” (default): the text goes to the clipboard, and you paste it yourself.'**
  String get manualC02S4B2I1;

  /// No description provided for @manualC02S4B2I2.
  ///
  /// In en, this message translates to:
  /// **'“Auto-Paste at cursor”: WhisPaste pastes the text at the cursor.'**
  String get manualC02S4B2I2;

  /// No description provided for @manualC02S4B2I3.
  ///
  /// In en, this message translates to:
  /// **'“Copy & Auto-Paste”: both.'**
  String get manualC02S4B2I3;

  /// No description provided for @manualC02S4B2I4.
  ///
  /// In en, this message translates to:
  /// **'“Do nothing”: WhisPaste neither copies nor pastes the text.'**
  String get manualC02S4B2I4;

  /// No description provided for @manualC02S4B3.
  ///
  /// In en, this message translates to:
  /// **'Apps on the “Auto-Paste blocklist” get no automatic pasting. The text then goes to the clipboard, or only to Recordings if “Copy to the clipboard when apps are blocked” is off.'**
  String get manualC02S4B3;

  /// No description provided for @manualC02S4B4.
  ///
  /// In en, this message translates to:
  /// **'On Windows, auto-paste does not work in programs running with administrator rights.'**
  String get manualC02S4B4;

  /// Linux clipboard history: only KDE Klipper honours the hint; other clipboard managers still record transcripts.
  ///
  /// In en, this message translates to:
  /// **'On Linux, WhisPaste marks the text with a hint that only KDE\'s Klipper honours. Other clipboard managers such as GPaste or CopyQ also store your transcripts: turn off their clipboard recording or delete the entry there.'**
  String get manualC02S4B5;

  /// No description provided for @manualC02S4B6.
  ///
  /// In en, this message translates to:
  /// **'After pasting, WhisPaste normally puts back what was on your clipboard before. Under “Clipboard after pasting” you can choose “Keep the transcript” instead: then the transcript stays on the clipboard. If a paste cannot be confirmed in time, the transcript always stays there. If macOS denies access to the clipboard, WhisPaste cannot keep the previous content and does not restore it; the transcript then stays on the clipboard. Once, a hint shows the way to System Settings.'**
  String get manualC02S4B6;

  /// No description provided for @manualC03Title.
  ///
  /// In en, this message translates to:
  /// **'Quick note'**
  String get manualC03Title;

  /// No description provided for @manualC03S1Heading.
  ///
  /// In en, this message translates to:
  /// **'What the quick note does'**
  String get manualC03S1Heading;

  /// No description provided for @manualC03S1B1.
  ///
  /// In en, this message translates to:
  /// **'The quick note is a note that WhisPaste appends new recordings to. This lets you collect thoughts or a list without creating a new note each time.'**
  String get manualC03S1B1;

  /// No description provided for @manualC03S1B2.
  ///
  /// In en, this message translates to:
  /// **'If no note is marked yet, WhisPaste creates a new one the first time and marks it.'**
  String get manualC03S1B2;

  /// No description provided for @manualC03S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Setting it up'**
  String get manualC03S2Heading;

  /// No description provided for @manualC03S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'Open the note in the Notes area and turn on “Make this the quick note the hotkey appends to”. “Quick note — remove the mark” removes the mark.'**
  String get manualC03S2B1I1;

  /// No description provided for @manualC03S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'Turn on the quick-note hotkey under Settings → Keyboard shortcuts. It is off by default. The key is {k1} ({k2}, or {k3} on Mac).'**
  String manualC03S2B1I2(String k1, String k2, String k3);

  /// No description provided for @manualC04Title.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get manualC04Title;

  /// No description provided for @manualC04S1Heading.
  ///
  /// In en, this message translates to:
  /// **'What Smart Mode does'**
  String get manualC04S1Heading;

  /// No description provided for @manualC04S1B1.
  ///
  /// In en, this message translates to:
  /// **'{k1} edits the recognized text before it is pasted. It is off by default; you turn it on yourself.'**
  String manualC04S1B1(String k1);

  /// No description provided for @manualC04S1B2.
  ///
  /// In en, this message translates to:
  /// **'By default, processing runs on your device (“Locally on device”). With “OpenAI”, the text is sent to OpenAI. The privacy chapter has the details.'**
  String get manualC04S1B2;

  /// No description provided for @manualC04S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get manualC04S2Heading;

  /// No description provided for @manualC04S2B1.
  ///
  /// In en, this message translates to:
  /// **'A preset decides what happens to the text:'**
  String get manualC04S2B1;

  /// No description provided for @manualC04S2B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Off”: no post-processing; the text stays as it was recognized.'**
  String get manualC04S2B2I1;

  /// No description provided for @manualC04S2B2I2.
  ///
  /// In en, this message translates to:
  /// **'“Cleanup”: removes filler words such as “um” and fixes punctuation and capitalization, without changing the wording, meaning, or language.'**
  String get manualC04S2B2I2;

  /// No description provided for @manualC04S2B2I3.
  ///
  /// In en, this message translates to:
  /// **'“Concise”: removes repetition and filler, keeps every important fact and the language.'**
  String get manualC04S2B2I3;

  /// No description provided for @manualC04S2B2I4.
  ///
  /// In en, this message translates to:
  /// **'“Translate”: translates the text into the target language you set.'**
  String get manualC04S2B2I4;

  /// No description provided for @manualC04S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Target language and hotkey'**
  String get manualC04S3Heading;

  /// No description provided for @manualC04S3B1.
  ///
  /// In en, this message translates to:
  /// **'For “Translate”, choose a target language: German, English, Spanish, French, Portuguese, Mandarin, or Russian. The default is English.'**
  String get manualC04S3B1;

  /// No description provided for @manualC04S3B2.
  ///
  /// In en, this message translates to:
  /// **'A separate hotkey for {k1} is off by default. It uses the preset and target language from the settings.'**
  String manualC04S3B2(String k1);

  /// No description provided for @manualC04S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get manualC04S4Heading;

  /// No description provided for @manualC04S4B1.
  ///
  /// In en, this message translates to:
  /// **'The local variant downloads a text model of about {size}. If your device has less than {ram} of RAM, WhisPaste warns before the download, but you can still download. While running, the text model needs an extra 4 to 5 GB of RAM.'**
  String manualC04S4B1(String size, String ram);

  /// No description provided for @manualC04S4B2.
  ///
  /// In en, this message translates to:
  /// **'While no text model is set up (local model not downloaded, or no OpenAI key for OpenAI), all presets except “Off” are locked. The dock and Settings name the reason and lead you to the download or the key. If post-processing still fails, WhisPaste says so and tells you whether the unedited text was pasted or is only on the clipboard.'**
  String get manualC04S4B2;

  /// No description provided for @manualC05Title.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get manualC05Title;

  /// No description provided for @manualC05S1Heading.
  ///
  /// In en, this message translates to:
  /// **'How replacements work'**
  String get manualC05S1Heading;

  /// No description provided for @manualC05S1B1.
  ///
  /// In en, this message translates to:
  /// **'A replacement automatically swaps certain words or phrases for other text in every recording.'**
  String get manualC05S1B1;

  /// No description provided for @manualC05S1B2.
  ///
  /// In en, this message translates to:
  /// **'Each replacement has one or more trigger phrases, the phrases to look for, and the new text. Enter several trigger phrases for the same text under “Trigger phrases”.'**
  String get manualC05S1B2;

  /// No description provided for @manualC05S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Matching'**
  String get manualC05S2Heading;

  /// No description provided for @manualC05S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'Exact: only the identical spelling is replaced.'**
  String get manualC05S2B1I1;

  /// No description provided for @manualC05S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'Similar: slightly different spellings are replaced too. This applies only to trigger phrases of at least 4 characters.'**
  String get manualC05S2B1I2;

  /// No description provided for @manualC05S2B1I3.
  ///
  /// In en, this message translates to:
  /// **'Tolerance (strict, standard, or tolerant): set per entry, not for all entries at once.'**
  String get manualC05S2B1I3;

  /// No description provided for @manualC05S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Import and export (CSV)'**
  String get manualC05S3Heading;

  /// No description provided for @manualC05S3B1.
  ///
  /// In en, this message translates to:
  /// **'You can back up or transfer your replacements as a CSV file. The file has the columns {k1}. Separate several trigger phrases with {k2}. A file can be at most {k3} and {k4} lines.'**
  String manualC05S3B1(String k1, String k2, String k3, String k4);

  /// No description provided for @manualC05S3B2.
  ///
  /// In en, this message translates to:
  /// **'Import and export are in the More menu (⋯) above the list. The try-it field opens from the same menu.'**
  String get manualC05S3B2;

  /// No description provided for @manualC06Title.
  ///
  /// In en, this message translates to:
  /// **'Snippets'**
  String get manualC06Title;

  /// No description provided for @manualC06S1Heading.
  ///
  /// In en, this message translates to:
  /// **'What snippets are'**
  String get manualC06S1Heading;

  /// No description provided for @manualC06S1B1.
  ///
  /// In en, this message translates to:
  /// **'A snippet is a block of text you insert with a trigger word or a hotkey, such as a signature or a standard reply.'**
  String get manualC06S1B1;

  /// No description provided for @manualC06S1B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Static”: the text is inserted exactly as you saved it.'**
  String get manualC06S1B2I1;

  /// No description provided for @manualC06S1B2I2.
  ///
  /// In en, this message translates to:
  /// **'“Interactive”: WhisPaste asks for individual fields one after another by recording, and places them in your template.'**
  String get manualC06S1B2I2;

  /// No description provided for @manualC06S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Opening the snippet picker'**
  String get manualC06S2Heading;

  /// No description provided for @manualC06S2B1.
  ///
  /// In en, this message translates to:
  /// **'There are two ways to open the picker:'**
  String get manualC06S2B1;

  /// No description provided for @manualC06S2B2I1.
  ///
  /// In en, this message translates to:
  /// **'With the picker trigger word: say only this word. It counts only if the whole recording is exactly this word. You set the trigger word on the Snippets page. Leave it empty to turn the picker off.'**
  String get manualC06S2B2I1;

  /// No description provided for @manualC06S2B2I2.
  ///
  /// In en, this message translates to:
  /// **'With the picker hotkey: off by default; turn it on under “Picker hotkey”.'**
  String get manualC06S2B2I2;

  /// No description provided for @manualC06S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Creating a snippet'**
  String get manualC06S3Heading;

  /// No description provided for @manualC06S3B1I1.
  ///
  /// In en, this message translates to:
  /// **'Create a snippet with “Add” and choose “Static” or “Interactive”.'**
  String get manualC06S3B1I1;

  /// No description provided for @manualC06S3B1I2.
  ///
  /// In en, this message translates to:
  /// **'For “Interactive”, define the fields and write the template. Put placeholders in double curly braces, such as {k1}.'**
  String manualC06S3B1I2(String k1);

  /// No description provided for @manualC07Title.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get manualC07Title;

  /// No description provided for @manualC07S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Working with notes'**
  String get manualC07S1Heading;

  /// No description provided for @manualC07S1B1.
  ///
  /// In en, this message translates to:
  /// **'The Notes area collects text, such as ideas or research. Recordings go straight into a note when you use the quick note.'**
  String get manualC07S1B1;

  /// No description provided for @manualC07S1B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Mark as favorite” highlights a note.'**
  String get manualC07S1B2I1;

  /// No description provided for @manualC07S1B2I2.
  ///
  /// In en, this message translates to:
  /// **'“Add tag” assigns a note to a category.'**
  String get manualC07S1B2I2;

  /// No description provided for @manualC07S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get manualC07S2Heading;

  /// No description provided for @manualC07S2B1.
  ///
  /// In en, this message translates to:
  /// **'“Move to trash” puts a note in the trash. It stays there until you delete it for good. The trash is never emptied automatically.'**
  String get manualC07S2B1;

  /// No description provided for @manualC07S2B2I1.
  ///
  /// In en, this message translates to:
  /// **'“Delete forever” removes the note from the trash.'**
  String get manualC07S2B2I1;

  /// No description provided for @manualC07S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Quick note'**
  String get manualC07S3Heading;

  /// No description provided for @manualC07S3B1.
  ///
  /// In en, this message translates to:
  /// **'The Notes area shows which note is the quick note. Details are in the quick note chapter.'**
  String get manualC07S3B1;

  /// No description provided for @manualC07S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Images and privacy'**
  String get manualC07S4Heading;

  /// No description provided for @manualC07S4B1.
  ///
  /// In en, this message translates to:
  /// **'When you add an image, WhisPaste removes metadata such as the location (GPS), camera data, and EXIF, XMP and IPTC information. Only the cleaned copy is stored.'**
  String get manualC07S4B1;

  /// No description provided for @notesPinGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes are locked'**
  String get notesPinGateTitle;

  /// No description provided for @notesPinGateHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to show your notes.'**
  String get notesPinGateHint;

  /// No description provided for @manualC08Title.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get manualC08Title;

  /// No description provided for @manualC08S1Heading.
  ///
  /// In en, this message translates to:
  /// **'What recordings hold'**
  String get manualC08S1Heading;

  /// No description provided for @manualC08S1B1.
  ///
  /// In en, this message translates to:
  /// **'Recordings shows every entry: the recognized text, with its date. If audio was saved, the audio file belongs to that entry.'**
  String get manualC08S1B1;

  /// No description provided for @manualC08S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Search and filter'**
  String get manualC08S2Heading;

  /// No description provided for @manualC08S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'Type {k1} to filter by tags.'**
  String manualC08S2B1I1(String k1);

  /// No description provided for @manualC08S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'Type {k1} and a language to filter by language.'**
  String manualC08S2B1I2(String k1);

  /// No description provided for @manualC08S2B1I3.
  ///
  /// In en, this message translates to:
  /// **'Or just type a keyword.'**
  String get manualC08S2B1I3;

  /// No description provided for @manualC08S2B1I4.
  ///
  /// In en, this message translates to:
  /// **'Above the list are the filters “Favorites”, “Archived”, “Trash”, and “All”.'**
  String get manualC08S2B1I4;

  /// No description provided for @manualC08S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Managing entries'**
  String get manualC08S3Heading;

  /// No description provided for @manualC08S3B1I1.
  ///
  /// In en, this message translates to:
  /// **'“Copy text” copies the text to the clipboard again.'**
  String get manualC08S3B1I1;

  /// No description provided for @manualC08S3B1I2.
  ///
  /// In en, this message translates to:
  /// **'“Add to favorites” keeps an entry at the top. “Remove from favorites” undoes that.'**
  String get manualC08S3B1I2;

  /// No description provided for @manualC08S3B1I3.
  ///
  /// In en, this message translates to:
  /// **'“Archive” moves an entry out of the main list without deleting it.'**
  String get manualC08S3B1I3;

  /// No description provided for @manualC08S3B1I4.
  ///
  /// In en, this message translates to:
  /// **'“Duplicate”, “Merge” (several entries into one), and “Select multiple” help you tidy up.'**
  String get manualC08S3B1I4;

  /// No description provided for @manualC08S3B1I5.
  ///
  /// In en, this message translates to:
  /// **'“Add annotation” and “Add tag…” add details to an entry.'**
  String get manualC08S3B1I5;

  /// No description provided for @manualC08S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get manualC08S4Heading;

  /// No description provided for @manualC08S4B1.
  ///
  /// In en, this message translates to:
  /// **'Start a voice note on the entry. Say “tag: name” to set a tag, or “correct: text” to replace the entry’s text.'**
  String get manualC08S4B1;

  /// No description provided for @manualC08S4B2.
  ///
  /// In en, this message translates to:
  /// **'A correction replaces the entry’s whole text, not just one word. “korrektur: text” works the same way. Right afterwards you can undo the change from the notice.'**
  String get manualC08S4B2;

  /// No description provided for @manualC08S5Heading.
  ///
  /// In en, this message translates to:
  /// **'PIN protection'**
  String get manualC08S5Heading;

  /// No description provided for @manualC08S5B1.
  ///
  /// In en, this message translates to:
  /// **'With “PIN protection”, a PIN is required before recordings are shown. This also applies to the side panel, the menu of the floating button, and the automation API. The PIN keeps others from casually viewing your transcriptions, but it does not encrypt them. Notes are locked the same way. With a PIN set, the tray menu lists recent recordings by time and word count instead of their first words.'**
  String get manualC08S5B1;

  /// No description provided for @manualC08S5B2.
  ///
  /// In en, this message translates to:
  /// **'A forgotten PIN cannot be recovered. To reset it, all transcriptions and saved audio files (including archive and trash), all notes with their versions, and all note images are deleted immediately. Settings, snippets, and replacements are kept.'**
  String get manualC08S5B2;

  /// No description provided for @manualC08S5B3.
  ///
  /// In en, this message translates to:
  /// **'While the recordings are locked by a PIN, the clipboard tab in the side panel shows no copied text and pastes none. Copied text comes back once you unlock them.'**
  String get manualC08S5B3;

  /// No description provided for @manualC08S6Heading.
  ///
  /// In en, this message translates to:
  /// **'Automatic emptying'**
  String get manualC08S6Heading;

  /// No description provided for @manualC08S6B1.
  ///
  /// In en, this message translates to:
  /// **'Under “Auto-delete trash after”, set how long deleted entries stay in the trash before they are removed automatically.'**
  String get manualC08S6B1;

  /// No description provided for @manualC09Title.
  ///
  /// In en, this message translates to:
  /// **'Importing audio files'**
  String get manualC09Title;

  /// No description provided for @manualC09S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Transcribing audio files'**
  String get manualC09S1Heading;

  /// No description provided for @manualC09S1B1.
  ///
  /// In en, this message translates to:
  /// **'You can have existing audio files transcribed. Choose “{k1}” and pick the file.'**
  String manualC09S1B1(String k1);

  /// No description provided for @manualC09S1B2.
  ///
  /// In en, this message translates to:
  /// **'Besides {k1}, you can import more formats depending on your system: on Mac {k2}, on Linux {k3}, on Windows {k4}.'**
  String manualC09S1B2(String k1, String k2, String k3, String k4);

  /// No description provided for @manualC09S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get manualC09S2Heading;

  /// No description provided for @manualC09S2B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: split the recording into shorter parts and import them one by one.'**
  String get manualC09S2B2;

  /// No description provided for @manualC09S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Import errors'**
  String get manualC09S3Heading;

  /// No description provided for @manualC09S3B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: try again. If that does not help, restart WhisPaste or choose another model under {k1}.'**
  String manualC09S3B2(String k1);

  /// No description provided for @manualC10Title.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get manualC10Title;

  /// No description provided for @manualC10S1Heading.
  ///
  /// In en, this message translates to:
  /// **'The areas'**
  String get manualC10S1Heading;

  /// No description provided for @manualC10S1B1.
  ///
  /// In en, this message translates to:
  /// **'The statistics have three areas: {k1}, {k2}, and {k3}.'**
  String manualC10S1B1(String k1, String k2, String k3);

  /// No description provided for @manualC10S1B2.
  ///
  /// In en, this message translates to:
  /// **'Use {k1} and {k2} to choose the time range.'**
  String manualC10S1B2(String k1, String k2);

  /// No description provided for @manualC10S2Heading.
  ///
  /// In en, this message translates to:
  /// **'What the numbers mean'**
  String get manualC10S2Heading;

  /// No description provided for @manualC10S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'{k1} and {k2} count your recordings and how long you recorded.'**
  String manualC10S2B1I1(String k1, String k2);

  /// No description provided for @manualC10S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'{k1} is a rough estimate: WhisPaste counts two thirds of the recording time as saved, because speaking is usually faster than typing. It is not a measurement.'**
  String manualC10S2B1I2(String k1);

  /// No description provided for @manualC10S2B1I3.
  ///
  /// In en, this message translates to:
  /// **'{k1}: local recordings save cloud costs. WhisPaste estimates this at {k2} per minute, a fixed reference rate.'**
  String manualC10S2B1I3(String k1, String k2);

  /// No description provided for @manualC10S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get manualC10S3Heading;

  /// No description provided for @manualC10S3B1.
  ///
  /// In en, this message translates to:
  /// **'“{k1}” deletes all statistics data. WhisPaste asks first, and this cannot be undone.'**
  String manualC10S3B1(String k1);

  /// No description provided for @manualC11Title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get manualC11Title;

  /// No description provided for @manualC11S1Heading.
  ///
  /// In en, this message translates to:
  /// **'The sections'**
  String get manualC11S1Heading;

  /// No description provided for @manualC11S1B1.
  ///
  /// In en, this message translates to:
  /// **'Settings are grouped into sections. The most important ones:'**
  String get manualC11S1B1;

  /// No description provided for @manualC11S1B2I1.
  ///
  /// In en, this message translates to:
  /// **'{k1}: how the app looks.'**
  String manualC11S1B2I1(String k1);

  /// No description provided for @manualC11S1B2I2.
  ///
  /// In en, this message translates to:
  /// **'{k1}: model and recognition language.'**
  String manualC11S1B2I2(String k1);

  /// No description provided for @manualC11S1B2I3.
  ///
  /// In en, this message translates to:
  /// **'{k1}: microphone and volume.'**
  String manualC11S1B2I3(String k1);

  /// No description provided for @manualC11S1B2I4.
  ///
  /// In en, this message translates to:
  /// **'{k1}: preset, target language, and provider.'**
  String manualC11S1B2I4(String k1);

  /// No description provided for @manualC11S1B2I5.
  ///
  /// In en, this message translates to:
  /// **'{k1}: what happens after a recording.'**
  String manualC11S1B2I5(String k1);

  /// No description provided for @manualC11S1B2I6.
  ///
  /// In en, this message translates to:
  /// **'{k1}: hotkeys.'**
  String manualC11S1B2I6(String k1);

  /// No description provided for @manualC11S1B2I7.
  ///
  /// In en, this message translates to:
  /// **'{k1}: trash period.'**
  String manualC11S1B2I7(String k1);

  /// No description provided for @manualC11S1B2I8.
  ///
  /// In en, this message translates to:
  /// **'{k1}: export, import, and automatic backup.'**
  String manualC11S1B2I8(String k1);

  /// No description provided for @manualC11S1B2I9.
  ///
  /// In en, this message translates to:
  /// **'{k1}: local API and event hooks for programs on this computer.'**
  String manualC11S1B2I9(String k1);

  /// No description provided for @manualC11S1B2I10.
  ///
  /// In en, this message translates to:
  /// **'{k1}: more options, such as reset.'**
  String manualC11S1B2I10(String k1);

  /// No description provided for @manualC11S1B2I11.
  ///
  /// In en, this message translates to:
  /// **'{k1}: version, update check, links, and licences.'**
  String manualC11S1B2I11(String k1);

  /// No description provided for @manualC11S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Back up and reset'**
  String get manualC11S2Heading;

  /// No description provided for @manualC11S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'{k1} saves your settings automatically after changes. The last five files are kept. It is off by default.'**
  String manualC11S2B1I1(String k1);

  /// No description provided for @manualC11S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'{k1} immediately deletes all transcriptions, audio files and settings and resets WhisPaste. Read the confirmation carefully before you confirm.'**
  String manualC11S2B1I2(String k1);

  /// No description provided for @manualC12Title.
  ///
  /// In en, this message translates to:
  /// **'Privacy and offline use'**
  String get manualC12Title;

  /// No description provided for @manualC12S1Heading.
  ///
  /// In en, this message translates to:
  /// **'What stays on your device'**
  String get manualC12S1Heading;

  /// No description provided for @manualC12S1B1.
  ///
  /// In en, this message translates to:
  /// **'By default, speech recognition runs on your device. Audio goes to a cloud service only when you actively choose a cloud provider. Transcriptions are stored in a local database on your device, and saved audio files as files next to it. The audio of your last {count} recordings is kept only while “{k1}” is on, and for {days} days at most.'**
  String manualC12S1B1(String k1, int count, int days);

  /// No description provided for @manualC12S1B2.
  ///
  /// In en, this message translates to:
  /// **'The update check asks GitHub for new versions. Feedback is sent only when you submit it.'**
  String get manualC12S1B2;

  /// Handbook paragraph on the audio of a failed transcription, kept for a retry for up to 24 hours.
  ///
  /// In en, this message translates to:
  /// **'If a transcription fails because the server or the connection is not available, the audio of that recording is kept for up to 24 hours, so you can try again from the error message or under Privacy. This also applies when audio retention is off. If it is on, the normal retention applies instead.'**
  String get manualC12S1B3;

  /// No description provided for @manualC12S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Cloud providers'**
  String get manualC12S2Heading;

  /// No description provided for @manualC12S2B1.
  ///
  /// In en, this message translates to:
  /// **'The providers OpenAI and Deepgram need your own API key. Enter it under {k1}.'**
  String manualC12S2B1(String k1);

  /// No description provided for @manualC12S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Usage statistics and error reports'**
  String get manualC12S3Heading;

  /// No description provided for @manualC12S3B1.
  ///
  /// In en, this message translates to:
  /// **'Two options are on by default: {k1} and {k2}. You can turn both off in {k3}.'**
  String manualC12S3B1(String k1, String k2, String k3);

  /// No description provided for @manualC13Title.
  ///
  /// In en, this message translates to:
  /// **'Hardware and performance'**
  String get manualC13Title;

  /// No description provided for @manualC13S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get manualC13S1Heading;

  /// No description provided for @manualC13S1B1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste recommends at least {k1} of memory. With less, the app still starts and recommends the “Fast” speech model.'**
  String manualC13S1B1(String k1);

  /// No description provided for @manualC13S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Graphics card'**
  String get manualC13S2Heading;

  /// No description provided for @manualC13S2B1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste uses the graphics card when it can speed up speech recognition:'**
  String get manualC13S2B1;

  /// No description provided for @manualC13S2B2I1.
  ///
  /// In en, this message translates to:
  /// **'{k1}: {k2}, Apple’s graphics interface.'**
  String manualC13S2B2I1(String k1, String k2);

  /// No description provided for @manualC13S2B2I2.
  ///
  /// In en, this message translates to:
  /// **'{k1} and {k2} with AMD or Intel graphics: {k3}, a widely used graphics interface.'**
  String manualC13S2B2I2(String k1, String k2, String k3);

  /// No description provided for @manualC13S2B2I3.
  ///
  /// In en, this message translates to:
  /// **'NVIDIA cards also use {k1}. With the optional CUDA pack, recognition also uses {k2}.'**
  String manualC13S2B2I3(String k1, String k2);

  /// No description provided for @manualC13S2B2I4.
  ///
  /// In en, this message translates to:
  /// **'Without a suitable graphics card, WhisPaste computes on the processor ({k1}). That is slower.'**
  String manualC13S2B2I4(String k1);

  /// No description provided for @manualC13S3Heading.
  ///
  /// In en, this message translates to:
  /// **'The CUDA pack'**
  String get manualC13S3Heading;

  /// No description provided for @manualC13S3B1.
  ///
  /// In en, this message translates to:
  /// **'The CUDA pack is an optional add-on for NVIDIA cards, per the app for {k1} and {k2}. It is available for {k3} and {k4} (x64). Turn it on under {k5}.'**
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5);

  /// No description provided for @manualC13S3B2.
  ///
  /// In en, this message translates to:
  /// **'The download is one-time. The app shows its size.'**
  String get manualC13S3B2;

  /// No description provided for @manualC13S3B3.
  ///
  /// In en, this message translates to:
  /// **'The pack contains NVIDIA components. Before the first download you accept the NVIDIA CUDA licence (version 2026-01-26); the consent applies to this installation. Without a valid consent the row shows “Consent required”, and WhisPaste uses Vulkan or the CPU until you accept. If the licence text or the pack changes, you are asked again.'**
  String get manualC13S3B3;

  /// No description provided for @manualC13S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Graphics acceleration'**
  String get manualC13S4Heading;

  /// No description provided for @manualC13S4B1.
  ///
  /// In en, this message translates to:
  /// **'Under {k1}, choose whether WhisPaste uses the graphics card. Processor only is usually slower.'**
  String manualC13S4B1(String k1);

  /// No description provided for @manualC13S5Heading.
  ///
  /// In en, this message translates to:
  /// **'Models and size'**
  String get manualC13S5Heading;

  /// No description provided for @manualC13S5B1.
  ///
  /// In en, this message translates to:
  /// **'The Whisper models come in three tiers: Fast, Balanced, and Accurate. More accurate tiers usually recognise better but need more processing time.'**
  String get manualC13S5B1;

  /// No description provided for @manualC14Title.
  ///
  /// In en, this message translates to:
  /// **'Troubleshooting'**
  String get manualC14Title;

  /// No description provided for @manualC14S1Heading.
  ///
  /// In en, this message translates to:
  /// **'How to read this page'**
  String get manualC14S1Heading;

  /// No description provided for @manualC14S1B1.
  ///
  /// In en, this message translates to:
  /// **'Each section starts with a notice WhisPaste shows. The wording is the app’s own text. Below it are the cause and the next step.'**
  String get manualC14S1B1;

  /// No description provided for @manualC14S2Heading.
  ///
  /// In en, this message translates to:
  /// **'No microphone access'**
  String get manualC14S2Heading;

  /// No description provided for @manualC14S2B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: allow WhisPaste microphone access in your system settings. Then start the recording again.'**
  String get manualC14S2B2;

  /// No description provided for @manualC14S3Heading.
  ///
  /// In en, this message translates to:
  /// **'No microphone found'**
  String get manualC14S3Heading;

  /// No description provided for @manualC14S3B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: connect a microphone and choose it under {k1}.'**
  String manualC14S3B2(String k1);

  /// No description provided for @manualC14S4Heading.
  ///
  /// In en, this message translates to:
  /// **'No audio captured'**
  String get manualC14S4Heading;

  /// No description provided for @manualC14S4B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: check that the right microphone is selected and the {k1} is not at zero. Then record again.'**
  String manualC14S4B2(String k1);

  /// No description provided for @manualC14S5Heading.
  ///
  /// In en, this message translates to:
  /// **'No speech model'**
  String get manualC14S5Heading;

  /// No description provided for @manualC14S5B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: download a model under {k1}, then try again.'**
  String manualC14S5B2(String k1);

  /// No description provided for @manualC14S6Heading.
  ///
  /// In en, this message translates to:
  /// **'Unknown model'**
  String get manualC14S6Heading;

  /// No description provided for @manualC14S6B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: choose an installed model under {k1}.'**
  String manualC14S6B2(String k1);

  /// No description provided for @manualC14S7Heading.
  ///
  /// In en, this message translates to:
  /// **'Transcription failed'**
  String get manualC14S7Heading;

  /// No description provided for @manualC14S7B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: try again. If that does not help, restart WhisPaste or choose another model under {k1}.'**
  String manualC14S7B2(String k1);

  /// No description provided for @manualC14S8Heading.
  ///
  /// In en, this message translates to:
  /// **'No text recognized'**
  String get manualC14S8Heading;

  /// No description provided for @manualC14S8B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: speak more clearly or a little longer and try again. Also check the microphone.'**
  String get manualC14S8B2;

  /// No description provided for @manualC14S9Heading.
  ///
  /// In en, this message translates to:
  /// **'Recording or transcription too long'**
  String get manualC14S9Heading;

  /// No description provided for @manualC14S9B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: record shorter sections.'**
  String get manualC14S9B2;

  /// No description provided for @manualC14S10Heading.
  ///
  /// In en, this message translates to:
  /// **'Cloud key missing or invalid'**
  String get manualC14S10Heading;

  /// No description provided for @manualC14S10B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: enter the key again under {k1}, or switch to on-device recognition.'**
  String manualC14S10B2(String k1);

  /// No description provided for @manualC14S11Heading.
  ///
  /// In en, this message translates to:
  /// **'Graphics memory full'**
  String get manualC14S11Heading;

  /// No description provided for @manualC14S11B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: nothing. You can choose the model again later in Settings.'**
  String get manualC14S11B2;

  /// No description provided for @manualC14S12Heading.
  ///
  /// In en, this message translates to:
  /// **'Calculated on the processor'**
  String get manualC14S12Heading;

  /// No description provided for @manualC14S12B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: usually nothing. If it happens often, check the setting under {k1} and update the graphics driver.'**
  String manualC14S12B2(String k1);

  /// No description provided for @manualC14S13Heading.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked (macOS)'**
  String get manualC14S13Heading;

  /// No description provided for @manualC14S13B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: allow WhisPaste accessibility access in the system settings. If the message stays, restart WhisPaste.'**
  String get manualC14S13B2;

  /// No description provided for @manualC14S14Heading.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste blocked (Windows)'**
  String get manualC14S14Heading;

  /// No description provided for @manualC14S14B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: start WhisPaste as an administrator too.'**
  String get manualC14S14B2;

  /// Heading of handbook chapter 14, section 15: auto-paste on Linux.
  ///
  /// In en, this message translates to:
  /// **'Auto-Paste on Linux'**
  String get manualC14S15Heading;

  /// Explains that auto-paste on Linux uses a virtual input device (uinput), and what to check when it does not work.
  ///
  /// In en, this message translates to:
  /// **'On Linux, auto-paste uses a virtual input device (uinput). If it does not work, check whether WhisPaste may access that device.'**
  String get manualC14S15B1;

  /// The .deb flow (R-02): nothing is granted on install; the user allows /dev/uinput in the app with the administrator password and can remove it again.
  ///
  /// In en, this message translates to:
  /// **'The .deb package grants no access when it is installed. Auto-paste asks first: in the setup or under Settings → After transcription, choose “Allow (administrator password)” and enter your administrator password. While the permission is in place, other programs in your session can create key presses too. “Remove permission” takes it back at any time; uninstalling removes it as well.'**
  String get manualC14S15B2;

  /// Flatpak note: what the sandbox permission gives the app. Plain language, no technical flags.
  ///
  /// In en, this message translates to:
  /// **'The Flatpak build gives the app access to the system\'s input devices so that auto-paste can work. WhisPaste itself does not read input devices.'**
  String get manualC14S15B3;

  /// Lead-in before the Snap command; the command itself follows in its own copyable block.
  ///
  /// In en, this message translates to:
  /// **'In the Snap build, run this once in a terminal:'**
  String get manualC14S15B4;

  /// AppImage setup: the copied udev command (session access only) and what happens until setup is done.
  ///
  /// In en, this message translates to:
  /// **'The AppImage needs access to /dev/uinput. In the setup or in the settings, copy the command and run it once in a terminal. It installs the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/, which gives write access only to the signed-in session. Until then, auto-paste only copies the text.'**
  String get manualC14S15B5;

  /// Handbook troubleshooting heading: terminal paste shortcut under Wayland.
  ///
  /// In en, this message translates to:
  /// **'Terminals and Wayland'**
  String get manualC14S15TerminalHeading;

  /// Handbook: Linux terminals paste with Ctrl+Shift+V; where WhisPaste recognises them on its own.
  ///
  /// In en, this message translates to:
  /// **'On Linux, terminals paste with Ctrl+Shift+V. WhisPaste recognises common terminals and uses that shortcut there on its own: under X11 and XWayland, and on KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire and other wlroots desktops.'**
  String get manualC14S15T1;

  /// Handbook: GNOME Wayland needs the optional WhisPaste GNOME extension to identify the target app.
  ///
  /// In en, this message translates to:
  /// **'Under GNOME with Wayland, WhisPaste identifies the target app only with the optional WhisPaste extension for GNOME. Without it, WhisPaste does not recognise terminals, and a block list only copies the text.'**
  String get manualC14S15T2;

  /// Handbook: fallback switch. {k1} = the switch title, {k2} = the settings section name.
  ///
  /// In en, this message translates to:
  /// **'If a terminal still shows ^V instead of the text, turn on “{k1}” under {k2}. WhisPaste then pastes with Ctrl+Shift+V everywhere. Some apps use these keys for something else; LibreOffice, for example, opens a dialog.'**
  String manualC14S15T3(String k1, String k2);

  /// Handbook: how to install and turn on the GNOME extension. {k1} = the button label.
  ///
  /// In en, this message translates to:
  /// **'Under GNOME, turn on the WhisPaste extension in the settings with {k1}. The .deb package already installs it. With Flatpak, AppImage or the tarball, install it once with the script from the unpacked Linux package, then turn it on:'**
  String manualC14S15T4(String k1);

  /// Terminal command, not translated.
  ///
  /// In en, this message translates to:
  /// **'bash install-gnome-extension.sh'**
  String get manualC14S15InstallExtCmd;

  /// Terminal command, not translated.
  ///
  /// In en, this message translates to:
  /// **'gnome-extensions enable whispaste-focus@whispaste.de'**
  String get manualC14S15EnableExtCmd;

  /// Handbook: portal paste without uinput. {k1} = button label, {k2} = settings section name.
  ///
  /// In en, this message translates to:
  /// **'Without uinput set up, for example in Flatpak, WhisPaste pastes through desktop permission: {k1} under {k2}. Your desktop asks once; you can withdraw the permission there at any time'**
  String manualC14S15T5(String k1, String k2);

  /// Linux Wayland without the GlobalShortcuts portal (GNOME before 48): notice under the hotkey. {shortcut} = the hotkey as key caps text, e.g. Ctrl+Shift+D. Keep GNOME untranslated.
  ///
  /// In en, this message translates to:
  /// **'This desktop does not let apps use system-wide shortcuts yet. WhisPaste can add {shortcut} to the GNOME keyboard shortcuts instead.'**
  String settingsDesktopShortcutGnome(String shortcut);

  /// No description provided for @settingsDesktopShortcutAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to GNOME'**
  String get settingsDesktopShortcutAdd;

  /// Shown once WhisPaste added its hotkey to the GNOME keyboard shortcuts. {shortcut} = the hotkey, e.g. Ctrl+Shift+D.
  ///
  /// In en, this message translates to:
  /// **'{shortcut} is set up in the GNOME keyboard shortcuts. If you change the hotkey, WhisPaste updates it there.'**
  String settingsDesktopShortcutInstalled(String shortcut);

  /// No description provided for @settingsDesktopShortcutRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from GNOME'**
  String get settingsDesktopShortcutRemove;

  /// No description provided for @settingsDesktopShortcutFailed.
  ///
  /// In en, this message translates to:
  /// **'The GNOME keyboard shortcuts could not be changed.'**
  String get settingsDesktopShortcutFailed;

  /// Linux Wayland desktops without the GlobalShortcuts portal where WhisPaste cannot add the shortcut itself (e.g. Sway, Flatpak). A command follows below the text.
  ///
  /// In en, this message translates to:
  /// **'This desktop does not let apps use system-wide shortcuts. Assign this command to a key combination in your system settings:'**
  String get settingsDesktopShortcutManual;

  /// No description provided for @manualC14S15HotkeyHeading.
  ///
  /// In en, this message translates to:
  /// **'Hotkey under Wayland'**
  String get manualC14S15HotkeyHeading;

  /// Handbook: hotkey under Wayland. {k1} = the button label “Add to GNOME”, {k2} = settings section name.
  ///
  /// In en, this message translates to:
  /// **'Under Wayland, an app gets system-wide shortcuts only through the desktop. KDE Plasma and GNOME 48 or newer provide them. Older GNOME versions, such as in Ubuntu 24.04, cannot: WhisPaste then offers “{k1}” under {k2} and adds the hotkey to the GNOME keyboard shortcuts.'**
  String manualC14S15H1(String k1, String k2);

  /// Handbook: manual shortcut on other Wayland desktops. {k1} = settings section name.
  ///
  /// In en, this message translates to:
  /// **'On other desktops, such as Sway or Hyprland, assign the command to a key combination yourself. Settings shows the exact command for your installation under {k1}.'**
  String manualC14S15H2(String k1);

  /// Handbook: what the Wayland hotkey notice offers. “{r}” = the Reconnect button label.
  ///
  /// In en, this message translates to:
  /// **'If the hotkey does not work in other apps, Settings and onboarding show a notice with the reason, the command for your own key combination, and a “Reconnect” button that asks the desktop again.'**
  String get manualC14S15H3;

  /// Subheading for the Flatpak build, a Linux app package format. Keep the name as is.
  ///
  /// In en, this message translates to:
  /// **'Flatpak'**
  String get manualC14S15FlatpakHeading;

  /// Security warning about access to input devices in the Flatpak build.
  ///
  /// In en, this message translates to:
  /// **'With this access, the app could in theory read keystrokes of other programs if your user can read the input devices (e.g. as a member of the input group). Members of the input group can also generate virtual input.'**
  String get manualC14S15B3W;

  /// Lead-in before the udev command block (Flatpak). The commands follow in their own copyable block.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste also needs write access to /dev/uinput on the host. Install the udev rule 71-whispaste-uinput.rules into /etc/udev/rules.d/ and then run these commands:'**
  String get manualC14S15B3S;

  /// Shell command shown in a copyable block. Keep the command unchanged.
  ///
  /// In en, this message translates to:
  /// **'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput'**
  String get manualC14S15Cmd;

  /// Label of the copy button next to a command block, also its tooltip. Use the same wording as pasteFailureLinuxUinputCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get manualCodeCopy;

  /// Confirmation toast after a command has been copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Command copied'**
  String get manualCodeCopied;

  /// No description provided for @manualCodeCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy. Select the command and copy it by hand.'**
  String get manualCodeCopyFailed;

  /// Warning that the udev rule gives write access to the signed-in session only, that the commands need administrator rights, and how to remove the rule.
  ///
  /// In en, this message translates to:
  /// **'The rule gives write access only to the signed-in session. These commands need administrator rights (sudo) and change the system. If you do not want this, leave auto-paste off and paste the text by hand. To remove the rule, use the button in the settings that copies the matching command.'**
  String get manualC14S15B3E;

  /// Subheading for the Snap build, a Linux app package format. Keep the name as is.
  ///
  /// In en, this message translates to:
  /// **'Snap'**
  String get manualC14S15SnapHeading;

  /// Shell command for the Snap build. Keep the command unchanged.
  ///
  /// In en, this message translates to:
  /// **'sudo snap connect whispaste:uinput'**
  String get manualC14S15SnapCmd;

  /// Sentence after the setup options: until setup is done, auto-paste only copies the text.
  ///
  /// In en, this message translates to:
  /// **'Until then, auto-paste only copies the text.'**
  String get manualC14S15Fallback;

  /// Subheading for the AppImage build, a Linux app package format. Keep the name as is.
  ///
  /// In en, this message translates to:
  /// **'AppImage'**
  String get manualC14S15AppImageHeading;

  /// No description provided for @manualC14S16Heading.
  ///
  /// In en, this message translates to:
  /// **'Hotkey already in use'**
  String get manualC14S16Heading;

  /// No description provided for @manualC14S16B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: choose a different combination under {k1}.'**
  String manualC14S16B2(String k1);

  /// No description provided for @manualC14S17Heading.
  ///
  /// In en, this message translates to:
  /// **'Autostart not set up'**
  String get manualC14S17Heading;

  /// No description provided for @manualC14S17B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: check the autostart permissions in your operating system. Without autostart, WhisPaste does not start on its own.'**
  String get manualC14S17B2;

  /// No description provided for @manualC14S18Heading.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup failed'**
  String get manualC14S18Heading;

  /// No description provided for @manualC14S18B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: choose a different, reachable folder under {k1}.'**
  String manualC14S18B2(String k1);

  /// No description provided for @manualC14S19Heading.
  ///
  /// In en, this message translates to:
  /// **'Factory reset incomplete'**
  String get manualC14S19Heading;

  /// No description provided for @manualC14S19B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: choose “Try again”, or restart WhisPaste and run the reset again afterwards.'**
  String get manualC14S19B2;

  /// No description provided for @manualC14S20Heading.
  ///
  /// In en, this message translates to:
  /// **'No sound detected'**
  String get manualC14S20Heading;

  /// No description provided for @manualC14S20B2.
  ///
  /// In en, this message translates to:
  /// **'What to do: check the microphone under {k1} and then record again.'**
  String manualC14S20B2(String k1);

  /// No description provided for @manualC14S21Heading.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory'**
  String get manualC14S21Heading;

  /// No description provided for @manualC14S21B1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste still starts with less memory than the recommended {k1}. The app then recommends the “Fast” speech model.'**
  String manualC14S21B1(String k1);

  /// No description provided for @manualC15Title.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get manualC15Title;

  /// No description provided for @manualC15S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Only inside WhisPaste'**
  String get manualC15S1Heading;

  /// No description provided for @manualC15S1B1.
  ///
  /// In en, this message translates to:
  /// **'These keyboard shortcuts work only while the WhisPaste window is active. The system-wide hotkey, by contrast, is set under {k2}.'**
  String manualC15S1B1(String k2);

  /// No description provided for @manualC15S1B2.
  ///
  /// In en, this message translates to:
  /// **'On Mac, {k1} usually replaces {k2}.'**
  String manualC15S1B2(String k1, String k2);

  /// Shortcut reference: the F1 key opens help.
  ///
  /// In en, this message translates to:
  /// **'F1 opens help.'**
  String get manualC15S1B3I1;

  /// Shortcut reference: the platform chord {k} also opens help.
  ///
  /// In en, this message translates to:
  /// **'{k} opens help as well.'**
  String manualC15S1B3I2(String k);

  /// No description provided for @manualC15S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get manualC15S2Heading;

  /// No description provided for @manualC15S2B1I1.
  ///
  /// In en, this message translates to:
  /// **'{k1}: delete the entry.'**
  String manualC15S2B1I1(String k1);

  /// No description provided for @manualC15S2B1I2.
  ///
  /// In en, this message translates to:
  /// **'{k1}: toggle favorite.'**
  String manualC15S2B1I2(String k1);

  /// No description provided for @manualC15S2B1I3.
  ///
  /// In en, this message translates to:
  /// **'{k1}: search.'**
  String manualC15S2B1I3(String k1);

  /// No description provided for @manualC15S2B1I4.
  ///
  /// In en, this message translates to:
  /// **'{k1}: close search or the detail view.'**
  String manualC15S2B1I4(String k1);

  /// Handbuch Kap. 15, Aufnahmen: Enter copies the focused entry. {k1} is the key name.
  ///
  /// In en, this message translates to:
  /// **'{k1}: copy the entry.'**
  String manualC15S2B1I5(String k1);

  /// Handbuch Kap. 15, Aufnahmen: Esc in the transcript editor discards the edit; unsaved changes ask first. {k1} is the key name.
  ///
  /// In en, this message translates to:
  /// **'{k1}: discard an edit. Unsaved changes ask first.'**
  String manualC15S2B1I6(String k1);

  /// No description provided for @manualC15S3Heading.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get manualC15S3Heading;

  /// No description provided for @manualC15S3B1I1.
  ///
  /// In en, this message translates to:
  /// **'{k1}: delete the entry.'**
  String manualC15S3B1I1(String k1);

  /// No description provided for @manualC15S3B1I2.
  ///
  /// In en, this message translates to:
  /// **'{k1}: create a new note.'**
  String manualC15S3B1I2(String k1);

  /// No description provided for @manualC15S3B1I3.
  ///
  /// In en, this message translates to:
  /// **'{k1}: search.'**
  String manualC15S3B1I3(String k1);

  /// No description provided for @manualC15S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Dictionary and snippets'**
  String get manualC15S4Heading;

  /// No description provided for @manualC15S4B1I1.
  ///
  /// In en, this message translates to:
  /// **'{k1}: delete the entry.'**
  String manualC15S4B1I1(String k1);

  /// Manual heading: cancelling a dictation with Esc, which is caught system-wide while a recording runs (UIA-SHL-14).
  ///
  /// In en, this message translates to:
  /// **'Cancel during a recording'**
  String get manualC15S5Heading;

  /// Manual paragraph: while a recording or transcription runs, WhisPaste catches the cancel key ({k1}, Esc) system-wide; {k2} (F12) is the alternative to choose in Settings (UIA-SHL-14).
  ///
  /// In en, this message translates to:
  /// **'While a recording or transcription runs, WhisPaste catches the {k1} key system-wide so you can cancel. {k1} then does nothing in other apps. If that bothers you, choose {k2} as the cancel key in Settings.'**
  String manualC15S5B1(String k1, String k2);

  /// No description provided for @manualC16Title.
  ///
  /// In en, this message translates to:
  /// **'Feedback and support'**
  String get manualC16Title;

  /// No description provided for @manualC16S1Heading.
  ///
  /// In en, this message translates to:
  /// **'Sending feedback'**
  String get manualC16S1Heading;

  /// No description provided for @manualC16S1B1I1.
  ///
  /// In en, this message translates to:
  /// **'Rating: required.'**
  String get manualC16S1B1I1;

  /// No description provided for @manualC16S1B1I2.
  ///
  /// In en, this message translates to:
  /// **'Type: required. Choose Problem, Idea, Praise, or Question.'**
  String get manualC16S1B1I2;

  /// No description provided for @manualC16S1B1I3.
  ///
  /// In en, this message translates to:
  /// **'Free text up to 1000 characters.'**
  String get manualC16S1B1I3;

  /// No description provided for @manualC16S1B1I4.
  ///
  /// In en, this message translates to:
  /// **'An email address is optional.'**
  String get manualC16S1B1I4;

  /// No description provided for @manualC16S1B2.
  ///
  /// In en, this message translates to:
  /// **'If you have sent feedback recently, the app shows this notice:'**
  String get manualC16S1B2;

  /// No description provided for @manualC16S2Heading.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get manualC16S2Heading;

  /// No description provided for @manualC16S2B1.
  ///
  /// In en, this message translates to:
  /// **'The {k1} tab on the Help page shows how you can support WhisPaste.'**
  String manualC16S2B1(String k1);

  /// Handbook heading: rating reminder and how to lift a 'Never ask again' choice.
  ///
  /// In en, this message translates to:
  /// **'Rating reminder'**
  String get manualC16S3Heading;

  /// Handbook paragraph: where the switch that lifts 'Never ask again' is. {k1} is the Interface area, {k2} the switch label.
  ///
  /// In en, this message translates to:
  /// **'If you chose “Never ask again” for the rating reminder, you find the switch “{k2}” under {k1}. It appears only in that case.'**
  String manualC16S3B1(String k1, String k2);

  /// No description provided for @manualC16S4B1.
  ///
  /// In en, this message translates to:
  /// **'You can send feedback from the Help tab, from the Help menu in the menu bar (macOS) or the title-bar menu (Windows and Linux), and from the tray. The form is two steps away.'**
  String get manualC16S4B1;

  /// No description provided for @manualC16S5Heading.
  ///
  /// In en, this message translates to:
  /// **'Share an idea'**
  String get manualC16S5Heading;

  /// No description provided for @manualC16S5B1.
  ///
  /// In en, this message translates to:
  /// **'Choose Idea, or open Suggest an idea from the Help menu: the type is already set. You can also post your idea on the public ideas board and vote on others.'**
  String get manualC16S5B1;

  /// No description provided for @manualC16S6Heading.
  ///
  /// In en, this message translates to:
  /// **'Write by voice'**
  String get manualC16S6Heading;

  /// No description provided for @manualC16S6B1.
  ///
  /// In en, this message translates to:
  /// **'The microphone button in the message field records your voice and inserts the recognized text at the cursor.'**
  String get manualC16S6B1;

  /// No description provided for @manualC16S7Heading.
  ///
  /// In en, this message translates to:
  /// **'What is sent'**
  String get manualC16S7Heading;

  /// No description provided for @manualC16S7B1I1.
  ///
  /// In en, this message translates to:
  /// **'The type you chose and your message.'**
  String get manualC16S7B1I1;

  /// No description provided for @manualC16S7B1I3.
  ///
  /// In en, this message translates to:
  /// **'Your e-mail address only if you entered one. It is used only for a reply and deleted after 90 days.'**
  String get manualC16S7B1I3;

  /// No description provided for @manualC16S7B1I4.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics only if you turn on Attach diagnostics: app version, operating system, speech engine and backend. Show preview displays the exact text before you send.'**
  String get manualC16S7B1I4;

  /// No description provided for @manualC16S7B1I5.
  ///
  /// In en, this message translates to:
  /// **'Only for Praise: the consent to show your praise as a quote on the website. It is off by default and you can withdraw it with one click on this page.'**
  String get manualC16S7B1I5;

  /// No description provided for @manualC16S7B2.
  ///
  /// In en, this message translates to:
  /// **'Recordings and transcripts are never attached.'**
  String get manualC16S7B2;

  /// No description provided for @manualC16S4Heading.
  ///
  /// In en, this message translates to:
  /// **'Where to find the form'**
  String get manualC16S4Heading;

  /// No description provided for @manualC16S7B1I2.
  ///
  /// In en, this message translates to:
  /// **'The rating you chose.'**
  String get manualC16S7B1I2;

  /// No description provided for @pasteFailureClipboardCopy.
  ///
  /// In en, this message translates to:
  /// **'Could not paste – the text is on the clipboard ({paste}).'**
  String pasteFailureClipboardCopy(Object paste);

  /// No description provided for @pasteFailureCheckPermission.
  ///
  /// In en, this message translates to:
  /// **'Check permission'**
  String get pasteFailureCheckPermission;

  /// No description provided for @autoPasteResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset entry and allow again?'**
  String get autoPasteResetConfirmTitle;

  /// No description provided for @autoPasteResetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'macOS stored an old entry for WhisPaste that no longer applies. WhisPaste removes only this Accessibility entry. macOS will then ask you again. Other permissions stay unchanged.'**
  String get autoPasteResetConfirmBody;

  /// No description provided for @autoPasteResetConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Reset entry and allow again'**
  String get autoPasteResetConfirmButton;

  /// No description provided for @permissionRowMicTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permissionRowMicTitle;

  /// No description provided for @permissionRowMicPurpose.
  ///
  /// In en, this message translates to:
  /// **'Records your voice. Without it nothing can be recorded.'**
  String get permissionRowMicPurpose;

  /// No description provided for @permissionRowPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste'**
  String get permissionRowPasteTitle;

  /// No description provided for @permissionRowPastePurpose.
  ///
  /// In en, this message translates to:
  /// **'Places the text at the cursor. Without it, the text lands on the clipboard.'**
  String get permissionRowPastePurpose;

  /// No description provided for @permissionRowAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get permissionRowAllow;

  /// No description provided for @permissionRowMissingSettings.
  ///
  /// In en, this message translates to:
  /// **'Missing – open Settings'**
  String get permissionRowMissingSettings;

  /// No description provided for @permissionRowGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permissionRowGranted;

  /// No description provided for @permissionRowOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get permissionRowOptional;

  /// No description provided for @autostartApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'macOS is waiting for your approval: WhisPaste only starts at login once you switch it on under Login Items.'**
  String get autostartApprovalBody;

  /// No description provided for @autostartApprovalAction.
  ///
  /// In en, this message translates to:
  /// **'Open Login Items'**
  String get autostartApprovalAction;

  /// No description provided for @pasteFailureLinuxUinputHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste needs your one-time permission for the virtual keyboard (/dev/uinput).'**
  String get pasteFailureLinuxUinputHint;

  /// No description provided for @pasteFailureLinuxUinputCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get pasteFailureLinuxUinputCopy;

  /// No description provided for @pasteFailureLinuxNoDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste is not available on this system: there is no virtual keyboard device.'**
  String get pasteFailureLinuxNoDeviceHint;

  /// No description provided for @pasteFailureLinuxUinputSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste needs one-time access to /dev/uinput. Open the Auto-Paste settings for the one-time setup.'**
  String get pasteFailureLinuxUinputSettingsHint;

  /// Notification after a .deb upgrade removed the install-time /dev/uinput access (R-02); shown once, on the first blocked paste.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste now asks before it uses the virtual keyboard /dev/uinput, so this update removed the old access. The text is on the clipboard, paste it with {paste}. Click here to allow it.'**
  String linuxUinputConsentNotice(String paste);

  /// No description provided for @linuxUinputSetupAction.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get linuxUinputSetupAction;

  /// No description provided for @linuxUinputConsentDetail.
  ///
  /// In en, this message translates to:
  /// **'To paste the text itself, WhisPaste needs a virtual keyboard. While it is allowed, other programs in your session can create key presses too. Without it, WhisPaste copies the text and you paste it yourself.'**
  String get linuxUinputConsentDetail;

  /// No description provided for @linuxUinputGrantButton.
  ///
  /// In en, this message translates to:
  /// **'Allow (administrator password)'**
  String get linuxUinputGrantButton;

  /// No description provided for @linuxUinputGrantFailed.
  ///
  /// In en, this message translates to:
  /// **'Allowing did not work. WhisPaste keeps copying the text only.'**
  String get linuxUinputGrantFailed;

  /// No description provided for @linuxUinputRevokeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove permission'**
  String get linuxUinputRevokeButton;

  /// No description provided for @linuxUinputRevokeDone.
  ///
  /// In en, this message translates to:
  /// **'Permission removed. WhisPaste now only copies the text.'**
  String get linuxUinputRevokeDone;

  /// No description provided for @settingsSecureKeysNotRemoved.
  ///
  /// In en, this message translates to:
  /// **'API keys could not be fully removed.'**
  String get settingsSecureKeysNotRemoved;

  /// No description provided for @analyticsDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String analyticsDurationHours(String hours);

  /// No description provided for @analyticsDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String analyticsDurationMinutes(String minutes);

  /// No description provided for @dockErrorCauseEngine.
  ///
  /// In en, this message translates to:
  /// **'The speech model stopped with an error.'**
  String get dockErrorCauseEngine;

  /// No description provided for @dockErrorCauseRecording.
  ///
  /// In en, this message translates to:
  /// **'The recording could not be transcribed.'**
  String get dockErrorCauseRecording;

  /// No description provided for @dockErrorAction.
  ///
  /// In en, this message translates to:
  /// **'Open speech settings to check the speech model.'**
  String get dockErrorAction;

  /// No description provided for @overlayDoneCopiedOnly.
  ///
  /// In en, this message translates to:
  /// **'Only copied – target app blocked or not recognised'**
  String get overlayDoneCopiedOnly;

  /// No description provided for @overlayDoneNotPasted.
  ///
  /// In en, this message translates to:
  /// **'Not pasted – saved in Recordings'**
  String get overlayDoneNotPasted;

  /// No description provided for @overlayDonePasteFailed.
  ///
  /// In en, this message translates to:
  /// **'Paste not possible – copy the text'**
  String get overlayDonePasteFailed;

  /// No description provided for @databaseTooNewTitle.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste cannot open your data'**
  String get databaseTooNewTitle;

  /// No description provided for @databaseTooNewCause.
  ///
  /// In en, this message translates to:
  /// **'Your data was written by a newer version of WhisPaste (database version {storedVersion}). This version supports up to version {supportedVersion}.'**
  String databaseTooNewCause(int storedVersion, int supportedVersion);

  /// No description provided for @databaseTooNewNextStep.
  ///
  /// In en, this message translates to:
  /// **'Install the latest version of WhisPaste and start it again. Nothing has been changed or deleted.'**
  String get databaseTooNewNextStep;

  /// No description provided for @databaseTooNewQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get databaseTooNewQuit;

  /// No description provided for @pasteFailureTargetChanged.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste cancelled: you switched apps during processing. The text is in the clipboard.'**
  String get pasteFailureTargetChanged;

  /// No description provided for @pasteFailureUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste not confirmed. The text is in the clipboard, paste it with {paste}.'**
  String pasteFailureUnconfirmed(String paste);

  /// No description provided for @onboardingAppearanceSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Changeable anytime under Settings → Appearance'**
  String get onboardingAppearanceSettingsHint;

  /// No description provided for @onboardingAppearanceSettingsLink.
  ///
  /// In en, this message translates to:
  /// **'Open the live preview in Settings (ends setup)'**
  String get onboardingAppearanceSettingsLink;

  /// No description provided for @onboardingAppearanceSettingsLinkRevision.
  ///
  /// In en, this message translates to:
  /// **'Open the live preview in Settings (show again later)'**
  String get onboardingAppearanceSettingsLinkRevision;

  /// Linux file dialog text the runner shows instead of GTK's English default (XP-5-13): dialog titles and the folder dialog's confirm button.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get fileDialogOpenTitle;

  /// No description provided for @fileDialogOpenFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Open files'**
  String get fileDialogOpenFilesTitle;

  /// No description provided for @fileDialogSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save file'**
  String get fileDialogSaveTitle;

  /// No description provided for @fileDialogFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get fileDialogFolderTitle;

  /// No description provided for @fileDialogSelectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get fileDialogSelectFolder;

  /// Value of the dock's language chip while the speech engine detects the language itself; keep it short.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get dockLanguageAuto;

  /// Tooltip and label of the star on a language tile that adds it to the favorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get settingsLanguageFavoriteAdd;

  /// Tooltip and label of the star on a language tile that removes it from the favorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get settingsLanguageFavoriteRemove;

  /// Hint in the language dialog shown when three favorites are already set.
  ///
  /// In en, this message translates to:
  /// **'Up to 3 favorites. Remove one to add another.'**
  String get settingsLanguageFavoritesLimit;

  /// Heading of the favorites block at the top of a dock language dropdown.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get dockMenuFavorites;

  /// Heading of the full language list below the favorites block in the dock dropdown.
  ///
  /// In en, this message translates to:
  /// **'All languages'**
  String get dockMenuAllLanguages;

  /// Label of the Speech model submenu in the tray context menu. Same term as the dock.
  ///
  /// In en, this message translates to:
  /// **'Speech model'**
  String get traySpeechModel;

  /// Tray tooltip line for the Smart Mode preset. {preset} is the localized preset name.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode: {preset}'**
  String trayTooltipSmartMode(String preset);

  /// Shown in the app when Linux has no tray host (GNOME without AppIndicator), so the tray quick switch is not silently missing.
  ///
  /// In en, this message translates to:
  /// **'The tray icon needs a tray host. On GNOME, install the AppIndicator extension; until then the quick-switch menu is not available.'**
  String get trayLinuxNoTrayHost;

  /// Label of the Language submenu in the tray context menu, next to the microphone submenu.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get trayLanguage;

  /// Last entry of the tray Language submenu. Opens the app window with the full language list in the dock.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get trayLanguageMore;

  /// No description provided for @trayProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get trayProfile;

  /// No description provided for @trayProfileAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic, by app'**
  String get trayProfileAutomatic;

  /// No description provided for @trayProfileNone.
  ///
  /// In en, this message translates to:
  /// **'No profile'**
  String get trayProfileNone;

  /// No description provided for @profileSwitchedToast.
  ///
  /// In en, this message translates to:
  /// **'Profile: {name}'**
  String profileSwitchedToast(String name);

  /// Name of the next-favorite-language hotkey in collision messages.
  ///
  /// In en, this message translates to:
  /// **'Next favorite language'**
  String get settingsHotkeyActionLanguageCycle;

  /// Title of the switch for the next-favorite-language hotkey in the Dictation card. Must not contain the word global.
  ///
  /// In en, this message translates to:
  /// **'Next favorite language'**
  String get settingsLanguageCycleHotkeyEnabled;

  /// Subtitle of the next-favorite-language switch: what the hotkey does and where favorites come from.
  ///
  /// In en, this message translates to:
  /// **'Switches the recording language to the next favorite. Star up to three languages under Speech-to-text.'**
  String get settingsLanguageCycleHotkeyHint;

  /// Shown when the chosen combination is already used by another WhisPaste hotkey. {action} is the other hotkey's name.
  ///
  /// In en, this message translates to:
  /// **'Already used by {action}. Choose another combination.'**
  String settingsLanguageCycleHotkeyCollision(String action);

  /// Shown when the registration of the next-favorite-language hotkey failed.
  ///
  /// In en, this message translates to:
  /// **'The shortcut is taken by another app or could not be registered. Choose another combination.'**
  String get settingsLanguageCycleHotkeyInactive;

  /// Notice on Linux under Wayland: the hotkey may not work system-wide there.
  ///
  /// In en, this message translates to:
  /// **'Under Wayland, this shortcut may not work in other apps. Set a desktop shortcut for it if it does not respond.'**
  String get settingsLanguageCycleHotkeyWaylandNotice;

  /// Toast after the next-favorite-language hotkey switched the dictation language. {language} is the native name of the language.
  ///
  /// In en, this message translates to:
  /// **'Recording language: {language}'**
  String languageCycleSwitchedToast(String language);

  /// Toast after the next-favorite-language hotkey was pressed while a recording runs: the new language applies from the next recording. {language} is the native name of the language.
  ///
  /// In en, this message translates to:
  /// **'Recording language: {language}. Applies from the next recording.'**
  String languageCycleSwitchedNextRecordingToast(String language);

  /// Toast when the next-favorite-language hotkey is pressed but no favorite is set. Points to the settings.
  ///
  /// In en, this message translates to:
  /// **'No favorite languages yet. Star up to three languages under Speech-to-text to use this shortcut.'**
  String get languageCycleNoFavoritesToast;

  /// Action button on the no-favorites toast that opens the speech-to-text settings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get languageCycleOpenSettings;

  /// Manual section heading: favorite speech languages.
  ///
  /// In en, this message translates to:
  /// **'Favorite languages'**
  String get manualLangFavHeading;

  /// Manual paragraph explaining the up-to-three favorite languages and where they appear.
  ///
  /// In en, this message translates to:
  /// **'In the speech recognition settings, mark up to three languages as favorites with the star in the language list. Favorites appear first in the language menu of the recording dock and in the tray menu, so you can switch in one click.'**
  String get manualLangFavB1;

  /// Manual section heading: the Language submenu in the tray menu.
  ///
  /// In en, this message translates to:
  /// **'Language in the tray menu'**
  String get manualLangTrayHeading;

  /// Manual paragraph on the tray menu Language submenu.
  ///
  /// In en, this message translates to:
  /// **'The tray menu has a Language submenu. It lists your favorites and puts a check mark on the active language. More… opens the window with the full list. Parakeet picks its own language, so the submenu is hidden there.'**
  String get manualLangTrayB1;

  /// Manual section heading: the next-favorite-language hotkey.
  ///
  /// In en, this message translates to:
  /// **'Next favorite language'**
  String get manualLangCycleHeading;

  /// Manual paragraph on the next-favorite-language hotkey, including the Wayland limit.
  ///
  /// In en, this message translates to:
  /// **'In the Dictate card you can assign a key combination that switches the recording language to the next favorite on each press. The shortcut stays off until you record a combination. Without favorites, WhisPaste points you to the setting. Under Linux with Wayland, other apps may not respond to the shortcut.'**
  String get manualLangCycleB1;

  /// Onboarding last page, Linux Wayland without the GlobalShortcuts portal: the hotkey still needs the desktop shortcut set up on the Hotkey page (XP-6-14). {shortcut} = the hotkey as key caps text, e.g. Ctrl+Shift+D.
  ///
  /// In en, this message translates to:
  /// **'{shortcut} does not work system-wide on this desktop yet. Go back to the page where you chose your hotkey to set it up.'**
  String onboardingReadyDesktopShortcutHint(String shortcut);

  /// Main window toast, GNOME on Wayland without the GlobalShortcuts portal and without WhisPaste's GNOME entry (XP-6-14). {shortcut} = the hotkey as key caps text. Keep GNOME untranslated.
  ///
  /// In en, this message translates to:
  /// **'{shortcut} works system-wide only after it is added to the GNOME keyboard shortcuts.'**
  String desktopShortcutToast(String shortcut);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended because Parakeet covers your language and is fast on any device.'**
  String get recommendationReasonLanguage;

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended from the measurement on this device.'**
  String get recommendationReasonMeasured;

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended for your Apple chip (Metal) with {memory}.'**
  String recommendationReasonApple(String memory);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended for your NVIDIA graphics card with {gb} GB of video memory (CUDA).'**
  String recommendationReasonCuda(String gb);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended for your graphics card {name} (Vulkan).'**
  String recommendationReasonVulkan(String name);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'Recommended for the processor, as there is no usable graphics card: {cores} cores, {memory}.'**
  String recommendationReasonCpu(int cores, String memory);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'{name} is software graphics, so the processor does the work: {cores} cores, {memory}.'**
  String recommendationReasonSoftware(String name, int cores, String memory);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'{gb} GB of RAM'**
  String recommendationMemory(String gb);

  /// Model recommendation reason (MV-03): one short line under the recommendation in onboarding and Settings.
  ///
  /// In en, this message translates to:
  /// **'RAM unknown'**
  String get recommendationMemoryUnknown;

  /// Dock speech selector: first entry while the selected speech model is not on disk; starts its download (UIA-MDL-GATE b).
  ///
  /// In en, this message translates to:
  /// **'No speech model – download {name} now ({size})'**
  String dockMenuDownloadMissing(String name, String size);

  /// Manual, chapter model download: what the dock, the shortcut and the engine switch do when the selected speech model is missing (UIA-MDL-GATE b, UIA-XP-7-04).
  ///
  /// In en, this message translates to:
  /// **'If the selected speech model is missing, the dock shows “Speech model missing”. The dock’s speech menu then offers it as its first entry to download, for Whisper and Parakeet alike. Pressing the shortcut without a model shows a notice with “Download now”. When you switch to Whisper in Settings and the selected Whisper model is missing, WhisPaste picks one that is already downloaded.'**
  String get manualC01S3B5;

  /// Benchmark compute path when Vulkan runs on a software renderer such as llvmpipe: the work is done by the processor, not a graphics card (UIA-XP-7-03).
  ///
  /// In en, this message translates to:
  /// **'Processor (software Vulkan, {name})'**
  String benchmarkBackendSoftwareVulkan(String name);

  /// No description provided for @menuBarMenuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuBarMenuEdit;

  /// No description provided for @menuBarMenuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuBarMenuWindow;

  /// No description provided for @menuBarEditUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get menuBarEditUndo;

  /// No description provided for @menuBarEditRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get menuBarEditRedo;

  /// No description provided for @menuBarEditCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuBarEditCut;

  /// No description provided for @menuBarEditCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuBarEditCopy;

  /// No description provided for @menuBarEditPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuBarEditPaste;

  /// No description provided for @menuBarEditSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get menuBarEditSelectAll;

  /// No description provided for @menuBarWindowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get menuBarWindowMinimize;

  /// No description provided for @menuBarWindowZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get menuBarWindowZoom;

  /// No description provided for @menuBarAppQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit WhisPaste'**
  String get menuBarAppQuit;

  /// No description provided for @menuBarMenuRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get menuBarMenuRecording;

  /// No description provided for @menuBarAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get menuBarAppSettings;

  /// No description provided for @menuBarHelpManual.
  ///
  /// In en, this message translates to:
  /// **'Open manual'**
  String get menuBarHelpManual;

  /// No description provided for @menuBarHelpFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback…'**
  String get menuBarHelpFeedback;

  /// No description provided for @menuBarHelpIdea.
  ///
  /// In en, this message translates to:
  /// **'Suggest an idea…'**
  String get menuBarHelpIdea;

  /// No description provided for @manualC15S6Heading.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get manualC15S6Heading;

  /// No description provided for @manualC15S6B1.
  ///
  /// In en, this message translates to:
  /// **'On the Mac, the most important commands are also in the menu bar at the top. The Recording menu starts and stops a recording and sets the language, speech model, Smart Mode, what happens after transcription, the microphone and the profile.'**
  String get manualC15S6B1;

  /// No description provided for @manualC15S6B2I1.
  ///
  /// In en, this message translates to:
  /// **'WhisPaste: open Settings with {k1}'**
  String manualC15S6B2I1(String k1);

  /// No description provided for @manualC15S6B2I2.
  ///
  /// In en, this message translates to:
  /// **'Edit: Cut, Copy, Paste and Select All act on the text field that has focus.'**
  String get manualC15S6B2I2;

  /// No description provided for @manualC15S6B2I3.
  ///
  /// In en, this message translates to:
  /// **'Window: minimize and zoom the main window.'**
  String get manualC15S6B2I3;

  /// No description provided for @manualC15S6B2I4.
  ///
  /// In en, this message translates to:
  /// **'Help: open the manual, send feedback and suggest an idea.'**
  String get manualC15S6B2I4;

  /// No description provided for @manualC15S6B3.
  ///
  /// In en, this message translates to:
  /// **'On Windows and Linux, the same commands are in a menu button at the top right of the title bar. Press Alt or F10 to open it, use the arrow keys to choose an entry, Enter to run it and Escape to close the menu.'**
  String get manualC15S6B3;

  /// No description provided for @menuBarAppAbout.
  ///
  /// In en, this message translates to:
  /// **'About WhisPaste'**
  String get menuBarAppAbout;

  /// No description provided for @menuBarAppHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get menuBarAppHide;

  /// No description provided for @menuBarAppHideOthers.
  ///
  /// In en, this message translates to:
  /// **'Hide Others'**
  String get menuBarAppHideOthers;

  /// No description provided for @menuBarAppShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show All'**
  String get menuBarAppShowAll;

  /// No description provided for @titleBarMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get titleBarMenuLabel;

  /// No description provided for @notesTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get notesTitleLabel;

  /// No description provided for @notesMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get notesMoreActions;

  /// No description provided for @notesVersionSaveNow.
  ///
  /// In en, this message translates to:
  /// **'Save version now'**
  String get notesVersionSaveNow;

  /// No description provided for @notesMenuMark.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get notesMenuMark;

  /// No description provided for @notesMenuAddImage.
  ///
  /// In en, this message translates to:
  /// **'Insert image'**
  String get notesMenuAddImage;

  /// No description provided for @notesMenuVersions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get notesMenuVersions;

  /// No description provided for @notesMenuSnippet.
  ///
  /// In en, this message translates to:
  /// **'Save as snippet'**
  String get notesMenuSnippet;

  /// No description provided for @notesVersionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No versions yet.'**
  String get notesVersionsEmpty;

  /// No description provided for @notesVersionTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large to preview'**
  String get notesVersionTooLarge;

  /// No description provided for @notesVersionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete version'**
  String get notesVersionDelete;

  /// No description provided for @notesVersionSaved.
  ///
  /// In en, this message translates to:
  /// **'Version saved'**
  String get notesVersionSaved;

  /// No description provided for @notesVersionUnchanged.
  ///
  /// In en, this message translates to:
  /// **'No changes since the last version.'**
  String get notesVersionUnchanged;

  /// No description provided for @notesVersionRestored.
  ///
  /// In en, this message translates to:
  /// **'Version restored'**
  String get notesVersionRestored;

  /// No description provided for @notesVersionRestoreMessage.
  ///
  /// In en, this message translates to:
  /// **'Only the title and text are restored to this version. Images stay as they are.'**
  String get notesVersionRestoreMessage;

  /// No description provided for @notesVersionDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This version is deleted permanently and cannot be recovered.'**
  String get notesVersionDeleteMessage;

  /// No description provided for @notesImageFilesLabel.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get notesImageFilesLabel;

  /// No description provided for @notesImageRejected.
  ///
  /// In en, this message translates to:
  /// **'This file is not a supported image (PNG, JPEG, GIF or WebP).'**
  String get notesImageRejected;

  /// No description provided for @notesImageRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get notesImageRemove;

  /// No description provided for @notesSnippetCreated.
  ///
  /// In en, this message translates to:
  /// **'Snippet created'**
  String get notesSnippetCreated;

  /// No description provided for @notesSnippetNothing.
  ///
  /// In en, this message translates to:
  /// **'This note has no text to save as a snippet.'**
  String get notesSnippetNothing;

  /// No description provided for @notesMarkNeedsSelection.
  ///
  /// In en, this message translates to:
  /// **'Select some text first.'**
  String get notesMarkNeedsSelection;

  /// No description provided for @notesImageLimitCount.
  ///
  /// In en, this message translates to:
  /// **'This note already has the maximum number of images.'**
  String get notesImageLimitCount;

  /// No description provided for @notesImageLimitBytes.
  ///
  /// In en, this message translates to:
  /// **'The images of this note would exceed the size limit.'**
  String get notesImageLimitBytes;

  /// No description provided for @notesImageLimitTotal.
  ///
  /// In en, this message translates to:
  /// **'Image storage is full. Remove an image to add another.'**
  String get notesImageLimitTotal;

  /// No description provided for @historyImportFailureCopyInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The file was too slow to copy or changed while it was being copied. Please try again.'**
  String get historyImportFailureCopyInterrupted;

  /// Shown when the import format has no decoder on this system.
  ///
  /// In en, this message translates to:
  /// **'This format is not available on this system. Convert the file to WAV and import it again.'**
  String get historyImportFailureDecoderUnavailable;

  /// Hint on the drop overlay while audio files are dragged over the window.
  ///
  /// In en, this message translates to:
  /// **'Drop audio files here to transcribe them'**
  String get audioDropHint;

  /// Toast for dropped folders. {names} is a comma-separated list of file names.
  ///
  /// In en, this message translates to:
  /// **'Folders cannot be imported: {names}'**
  String audioDropRejectedFolder(String names);

  /// Toast for dropped paths that no longer exist. {names} is a list of file names.
  ///
  /// In en, this message translates to:
  /// **'File not found: {names}'**
  String audioDropRejectedNotFound(String names);

  /// Toast for dropped files with an unsupported format. {formats} is the list of allowed extensions.
  ///
  /// In en, this message translates to:
  /// **'Not supported: {names}. Allowed formats: {formats}.'**
  String audioDropRejectedFormat(String names, String formats);

  /// Import refusal message (audioDropRejectedNotRegular).
  ///
  /// In en, this message translates to:
  /// **'Not an ordinary file (such as a device or pipe), cannot be imported: {names}'**
  String audioDropRejectedNotRegular(Object names);

  /// Import refusal message (audioDropRejectedTooLarge).
  ///
  /// In en, this message translates to:
  /// **'Too large (1 GB at most): {names}'**
  String audioDropRejectedTooLarge(Object names);

  /// Import refusal message (historyImportRejectedNotRegularFile).
  ///
  /// In en, this message translates to:
  /// **'This is not an ordinary file and cannot be imported.'**
  String get historyImportRejectedNotRegularFile;

  /// Import refusal message (historyImportRejectedTooLarge).
  ///
  /// In en, this message translates to:
  /// **'The file is larger than 1 GB.'**
  String get historyImportRejectedTooLarge;

  /// Import refusal or failure message (audioDropRejectedReservedName).
  ///
  /// In en, this message translates to:
  /// **'Reserved device name, cannot be imported: {names}'**
  String audioDropRejectedReservedName(Object names);

  /// Import refusal or failure message (historyImportRejectedReservedName).
  ///
  /// In en, this message translates to:
  /// **'Windows reserves this file name, so it cannot be imported. Rename the file.'**
  String get historyImportRejectedReservedName;

  /// Import refusal or failure message (historyImportFailureIo).
  ///
  /// In en, this message translates to:
  /// **'The storage is full or not writable.'**
  String get historyImportFailureIo;

  /// Fixed subtitle of the Hold-to-record switch (onboarding and Settings): explains both states, so it never reads as contradicting the title (UIA-XP-7-12).
  ///
  /// In en, this message translates to:
  /// **'On: hold the hotkey and speak, release to finish. Off: press once to start, press again to finish.'**
  String get holdToRecordExplained;

  /// No description provided for @settingsAreaProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get settingsAreaProfiles;

  /// No description provided for @profilesSectionHeading.
  ///
  /// In en, this message translates to:
  /// **'Your profiles'**
  String get profilesSectionHeading;

  /// No description provided for @profilesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Profiles switch the speech model, language, Smart Mode and the after-transcription action with a hotkey, or automatically per app.'**
  String get profilesEmptyBody;

  /// No description provided for @profilesAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Create first profile'**
  String get profilesAddFirst;

  /// No description provided for @profilesAdd.
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get profilesAdd;

  /// No description provided for @profilesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get profilesCreate;

  /// No description provided for @profilesLimitReached.
  ///
  /// In en, this message translates to:
  /// **'At most 9 profiles. Delete one to create another.'**
  String get profilesLimitReached;

  /// No description provided for @profilesActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profilesActiveBadge;

  /// No description provided for @profilesMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get profilesMoveUp;

  /// No description provided for @profilesMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get profilesMoveDown;

  /// No description provided for @profilesDragHandle.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get profilesDragHandle;

  /// No description provided for @profilesNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get profilesNewTitle;

  /// No description provided for @profilesNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profilesNameLabel;

  /// No description provided for @profilesNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get profilesNameEmpty;

  /// No description provided for @profileDetailHeading.
  ///
  /// In en, this message translates to:
  /// **'Profile settings'**
  String get profileDetailHeading;

  /// No description provided for @profileDetailModel.
  ///
  /// In en, this message translates to:
  /// **'Speech model'**
  String get profileDetailModel;

  /// No description provided for @profileDetailLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profileDetailLanguage;

  /// No description provided for @profileDetailLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies to Whisper and cloud services. Parakeet detects the language itself.'**
  String get profileDetailLanguageSubtitle;

  /// No description provided for @profileDetailSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart Mode'**
  String get profileDetailSmartMode;

  /// No description provided for @profileDetailAfter.
  ///
  /// In en, this message translates to:
  /// **'After transcription'**
  String get profileDetailAfter;

  /// No description provided for @profileDetailMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get profileDetailMicrophone;

  /// No description provided for @profileKeepUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Leave unchanged'**
  String get profileKeepUnchanged;

  /// No description provided for @profileValueUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{value} (unavailable)'**
  String profileValueUnavailable(String value);

  /// No description provided for @profileDetailHotkey.
  ///
  /// In en, this message translates to:
  /// **'Hotkey'**
  String get profileDetailHotkey;

  /// No description provided for @profileDetailHotkeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switches to this profile with this key press.'**
  String get profileDetailHotkeySubtitle;

  /// No description provided for @profileHotkeyNone.
  ///
  /// In en, this message translates to:
  /// **'No hotkey'**
  String get profileHotkeyNone;

  /// No description provided for @profileHotkeyChange.
  ///
  /// In en, this message translates to:
  /// **'Set hotkey'**
  String get profileHotkeyChange;

  /// No description provided for @profileHotkeyRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove hotkey'**
  String get profileHotkeyRemove;

  /// No description provided for @profileHotkeyNeedsModifier.
  ///
  /// In en, this message translates to:
  /// **'A profile hotkey needs at least one modifier key, such as Ctrl, Alt, Shift or Command.'**
  String get profileHotkeyNeedsModifier;

  /// No description provided for @profileHotkeyTakenByApp.
  ///
  /// In en, this message translates to:
  /// **'Already used by “{action}”. The hotkey is not active.'**
  String profileHotkeyTakenByApp(String action);

  /// No description provided for @profileHotkeyTakenByProfile.
  ///
  /// In en, this message translates to:
  /// **'Already used by the profile “{name}”. The hotkey is not active.'**
  String profileHotkeyTakenByProfile(String name);

  /// No description provided for @profileDetailApps.
  ///
  /// In en, this message translates to:
  /// **'Target apps'**
  String get profileDetailApps;

  /// No description provided for @profileDetailAppsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When one of these apps is in front while you dictate, the profile becomes active automatically.'**
  String get profileDetailAppsSubtitle;

  /// No description provided for @profileAppIdentifierLabel.
  ///
  /// In en, this message translates to:
  /// **'App identifier'**
  String get profileAppIdentifierLabel;

  /// No description provided for @profileAppAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get profileAppAdd;

  /// No description provided for @profileAppHintMac.
  ///
  /// In en, this message translates to:
  /// **'macOS: bundle ID, e.g. com.apple.mail'**
  String get profileAppHintMac;

  /// No description provided for @profileAppHintWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows: program name without .exe, e.g. chrome'**
  String get profileAppHintWindows;

  /// No description provided for @profileAppHintLinux.
  ///
  /// In en, this message translates to:
  /// **'Linux: window WM_CLASS, e.g. google-chrome. Not detectable under Wayland.'**
  String get profileAppHintLinux;

  /// No description provided for @profileAppClash.
  ///
  /// In en, this message translates to:
  /// **'This app already belongs to the profile “{name}”.'**
  String profileAppClash(String name);

  /// No description provided for @profileAppEmpty.
  ///
  /// In en, this message translates to:
  /// **'No app assigned yet.'**
  String get profileAppEmpty;

  /// No description provided for @profileAppRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove app rule'**
  String get profileAppRemove;

  /// No description provided for @profileDetailContext.
  ///
  /// In en, this message translates to:
  /// **'Read context'**
  String get profileDetailContext;

  /// No description provided for @profileDetailContextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optionally reads the selected text or the clipboard so processing fits. With cloud services only with your consent.'**
  String get profileDetailContextSubtitle;

  /// No description provided for @profileContextNone.
  ///
  /// In en, this message translates to:
  /// **'Read nothing'**
  String get profileContextNone;

  /// No description provided for @profileContextSelection.
  ///
  /// In en, this message translates to:
  /// **'Selected text'**
  String get profileContextSelection;

  /// No description provided for @profileContextClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get profileContextClipboard;

  /// No description provided for @profileConsentGiven.
  ///
  /// In en, this message translates to:
  /// **'Consent given'**
  String get profileConsentGiven;

  /// No description provided for @profileConsentMissing.
  ///
  /// In en, this message translates to:
  /// **'Consent missing, so no context is read'**
  String get profileConsentMissing;

  /// No description provided for @profileConsentWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw consent'**
  String get profileConsentWithdraw;

  /// No description provided for @profileConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Send context to a cloud service?'**
  String get profileConsentTitle;

  /// No description provided for @profileConsentBody.
  ///
  /// In en, this message translates to:
  /// **'When this profile is active, the selected text or the clipboard contents of the target window are sent to the cloud provider named in this profile, only to refine this recording. You can withdraw this consent at any time in the profile settings.'**
  String get profileConsentBody;

  /// No description provided for @profileConsentAccept.
  ///
  /// In en, this message translates to:
  /// **'Consent'**
  String get profileConsentAccept;

  /// No description provided for @profileDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete profile'**
  String get profileDeleteAction;

  /// No description provided for @profileDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profile “{name}”?'**
  String profileDeleteTitle(String name);

  /// No description provided for @profileDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'The profile and its target apps are removed. Its hotkey becomes free.'**
  String get profileDeleteMessage;

  /// No description provided for @manualProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Profiles and quick switching'**
  String get manualProfilesTitle;

  /// No description provided for @manualProfilesS1Heading.
  ///
  /// In en, this message translates to:
  /// **'Creating profiles'**
  String get manualProfilesS1Heading;

  /// No description provided for @manualProfilesS1Body.
  ///
  /// In en, this message translates to:
  /// **'A profile is a named set of recording settings. Create it under Settings → Profiles and decide for each field whether the profile sets it or leaves it unchanged.'**
  String get manualProfilesS1Body;

  /// No description provided for @manualProfilesS1B1.
  ///
  /// In en, this message translates to:
  /// **'Speech model, language, Smart Mode, after-transcription action and microphone'**
  String get manualProfilesS1B1;

  /// No description provided for @manualProfilesS1B2.
  ///
  /// In en, this message translates to:
  /// **'Up to 9 profiles. Every field can be set to “Leave unchanged”.'**
  String get manualProfilesS1B2;

  /// No description provided for @manualProfilesS2Heading.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys'**
  String get manualProfilesS2Heading;

  /// No description provided for @manualProfilesS2Body.
  ///
  /// In en, this message translates to:
  /// **'Each profile can have its own hotkey. Pressing it activates the profile, and it stays active until you choose another one or change one of its fields by hand.'**
  String get manualProfilesS2Body;

  /// No description provided for @manualProfilesS2Tip.
  ///
  /// In en, this message translates to:
  /// **'A hotkey needs a modifier key. A combination that another feature already uses stays inactive, and the profile shows it as a conflict.'**
  String get manualProfilesS2Tip;

  /// No description provided for @manualProfilesS3Heading.
  ///
  /// In en, this message translates to:
  /// **'Automatic per app'**
  String get manualProfilesS3Heading;

  /// No description provided for @manualProfilesS3Body.
  ///
  /// In en, this message translates to:
  /// **'If you add an app under target apps, the profile becomes active whenever that app is in front while you dictate. The identifier depends on the operating system:'**
  String get manualProfilesS3Body;

  /// No description provided for @manualProfilesS3Mac.
  ///
  /// In en, this message translates to:
  /// **'macOS: bundle ID, for example com.apple.mail'**
  String get manualProfilesS3Mac;

  /// No description provided for @manualProfilesS3Win.
  ///
  /// In en, this message translates to:
  /// **'Windows: program name without .exe, for example chrome'**
  String get manualProfilesS3Win;

  /// No description provided for @manualProfilesS3Linux.
  ///
  /// In en, this message translates to:
  /// **'Linux: window WM_CLASS under X11, for example google-chrome. Under Wayland WhisPaste cannot detect the app.'**
  String get manualProfilesS3Linux;

  /// No description provided for @manualProfilesS4Heading.
  ///
  /// In en, this message translates to:
  /// **'Tray and overlay'**
  String get manualProfilesS4Heading;

  /// No description provided for @manualProfilesS4Body.
  ///
  /// In en, this message translates to:
  /// **'The tray menu has a Profile submenu: “Automatic, by app” follows the rules, “No profile” switches them off, and your profiles are listed below. In the recording overlay, the name of the active profile follows the time and language, for example 0:07 · DE · Mail.'**
  String get manualProfilesS4Body;

  /// No description provided for @manualProfilesS5Heading.
  ///
  /// In en, this message translates to:
  /// **'Leave unchanged'**
  String get manualProfilesS5Heading;

  /// No description provided for @manualProfilesS5Body.
  ///
  /// In en, this message translates to:
  /// **'“Leave unchanged” means the profile does not touch this field. The value currently set in Settings applies.'**
  String get manualProfilesS5Body;

  /// No description provided for @manualProfilesS6Heading.
  ///
  /// In en, this message translates to:
  /// **'What a manual change does'**
  String get manualProfilesS6Heading;

  /// No description provided for @manualProfilesS6Body.
  ///
  /// In en, this message translates to:
  /// **'If you choose a profile in the tray or press its hotkey, it applies to all following recordings. If you then change a field the profile sets, such as the speech model, the active marker ends and the per-app rules decide again. The choice survives a restart.'**
  String get manualProfilesS6Body;

  /// No description provided for @profileAppCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture app'**
  String get profileAppCapture;

  /// No description provided for @profileAppCaptureCountdown.
  ///
  /// In en, this message translates to:
  /// **'Switch to the target app in {seconds} s …'**
  String profileAppCaptureCountdown(int seconds);

  /// No description provided for @profileAppCaptured.
  ///
  /// In en, this message translates to:
  /// **'“{identifier}” was added as target app.'**
  String profileAppCaptured(Object identifier);

  /// No description provided for @profileAppCaptureNone.
  ///
  /// In en, this message translates to:
  /// **'No other app is in front. Switch to the target app before the countdown ends.'**
  String get profileAppCaptureNone;

  /// No description provided for @profileAppCaptureUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This session cannot read the app in front (for example Wayland). Enter the identifier by hand.'**
  String get profileAppCaptureUnavailable;

  /// Name of the dictation hotkey in the Linux desktop's own global-shortcuts dialog (GNOME/KDE, Wayland). Neutral, no mode (toggle or push-to-talk).
  ///
  /// In en, this message translates to:
  /// **'WhisPaste dictation'**
  String get waylandHotkeyPortalDescription;

  /// Inline notice under the hotkey (Settings and onboarding) on Linux Wayland when the desktop portal could not identify the app, so the hotkey is not bound system-wide.
  ///
  /// In en, this message translates to:
  /// **'Your desktop could not identify WhisPaste and has not activated the hotkey, so it does not work in other apps.'**
  String get waylandHotkeyNoAppId;

  /// Inline notice under the hotkey on Linux Wayland when the desktop offers no global-shortcuts portal.
  ///
  /// In en, this message translates to:
  /// **'Your desktop does not let apps set a system-wide hotkey, so the hotkey does not work in other apps.'**
  String get waylandHotkeyUnavailable;

  /// Inline notice under the hotkey on Linux Wayland when the user or the desktop declined the global-shortcut dialog.
  ///
  /// In en, this message translates to:
  /// **'The hotkey was not confirmed in your desktop\'s dialog, so it does not work in other apps.'**
  String get waylandHotkeyDeclined;

  /// Second sentence of the Wayland hotkey notice, followed by a shell command (whispaste --toggle) the user can bind as a custom shortcut in GNOME/KDE settings.
  ///
  /// In en, this message translates to:
  /// **'You can add a keyboard shortcut in your system settings instead. Use this command:'**
  String get waylandHotkeyFallback;

  /// Button in the Wayland hotkey notice: asks the desktop again to bind the hotkey (may reopen its dialog).
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get waylandHotkeyReconnect;

  /// Button in the Wayland hotkey notice: copies the fallback command to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get waylandHotkeyCopyCommand;

  /// Label the copy button shows after the command was copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get waylandHotkeyCommandCopied;

  /// Button in the Wayland hotkey notice: opens the desktop's keyboard shortcut settings (GNOME Settings / KDE System Settings).
  ///
  /// In en, this message translates to:
  /// **'Open keyboard settings'**
  String get waylandHotkeyOpenKeyboardSettings;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'he',
    'pt',
    'ru',
  ].contains(locale.languageCode);

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
    case 'es':
      return L10nEs();
    case 'he':
      return L10nHe();
    case 'pt':
      return L10nPt();
    case 'ru':
      return L10nRu();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
