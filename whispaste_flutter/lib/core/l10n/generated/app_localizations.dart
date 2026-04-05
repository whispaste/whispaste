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

  /// No description provided for @settingsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsAudio;

  /// No description provided for @settingsMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsMicrophone;

  /// No description provided for @settingsGain.
  ///
  /// In en, this message translates to:
  /// **'Input Gain'**
  String get settingsGain;

  /// No description provided for @settingsRecordingSafety.
  ///
  /// In en, this message translates to:
  /// **'Recording Safety'**
  String get settingsRecordingSafety;

  /// No description provided for @settingsDeadMicTimeout.
  ///
  /// In en, this message translates to:
  /// **'Dead Microphone Timeout'**
  String get settingsDeadMicTimeout;

  /// No description provided for @settingsDeadMicTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'Stop recording if no audio detected within this time (seconds). 0 = disabled.'**
  String get settingsDeadMicTimeoutHint;

  /// No description provided for @settingsAutoStopSilence.
  ///
  /// In en, this message translates to:
  /// **'Auto-Stop on Silence'**
  String get settingsAutoStopSilence;

  /// No description provided for @settingsAutoStopSilenceHint.
  ///
  /// In en, this message translates to:
  /// **'Automatically stop after this many seconds of silence (after speech). 0 = disabled.'**
  String get settingsAutoStopSilenceHint;

  /// No description provided for @settingsPostProcessing.
  ///
  /// In en, this message translates to:
  /// **'Post-Processing'**
  String get settingsPostProcessing;

  /// No description provided for @settingsPostProcessingHint.
  ///
  /// In en, this message translates to:
  /// **'Automatically enhance transcribed text using AI.'**
  String get settingsPostProcessingHint;

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

  /// No description provided for @settingsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvanced;

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
