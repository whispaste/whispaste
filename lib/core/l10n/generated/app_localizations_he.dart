// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class L10nHe extends L10n {
  L10nHe([String locale = 'he']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'הקלטות';

  @override
  String get navNotes => 'פתקים';

  @override
  String get navSettings => 'הגדרות';

  @override
  String get navReplacements => 'מילון';

  @override
  String get navSnippets => 'קטעים';

  @override
  String get navAnalytics => 'סטטיסטיקה';

  @override
  String get navHelp => 'עזרה';

  @override
  String get actionOpen => 'פתיחה';

  @override
  String actionOpenNamed(String name) {
    return 'פתח את $name';
  }

  @override
  String get helpTabManual => 'מדריך';

  @override
  String get helpTabIntro => 'היכרות';

  @override
  String get helpTabSupport => 'תמיכה';

  @override
  String get helpTabDiagnostics => 'אבחון';

  @override
  String get manualSearchHint => 'חיפוש במדריך';

  @override
  String get manualSearchEmpty => 'אין פרק שמתאים לחיפוש.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נמצאו $count פרקים',
      one: 'נמצא פרק אחד',
      zero: 'לא נמצאו פרקים',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'משוב';

  @override
  String get pageHistoryTitle => 'הקלטות';

  @override
  String get pageSettingsTitle => 'הגדרות';

  @override
  String get pageReplacementsTitle => 'מילון';

  @override
  String get pageAnalyticsTitle => 'ניתוח נתונים';

  @override
  String get pageAboutTitle => 'אודות WhisPaste';

  @override
  String get pageFeedbackTitle => 'משוב';

  @override
  String get historyEmpty => 'אין עדיין הקלטות';

  @override
  String get historyEmptyHint =>
      'לחץ על כפתור ההקלטה או השתמש בקיצור המקלדת כדי להתחיל.';

  @override
  String get historyPrivacyGateTitle => 'ההקלטות מוסתרות';

  @override
  String get historyPrivacyGateHint =>
      'התמלולים והאודיו רק מוסתרים, לא נמחקים, עד שתבחר להציג אותם.';

  @override
  String get historyPrivacyGateShow => 'הצגת הקלטות';

  @override
  String get historySearch => 'חיפוש…';

  @override
  String get historyPinned => 'מועדפים';

  @override
  String get historyToday => 'היום';

  @override
  String get historyYesterday => 'אתמול';

  @override
  String get historyThisWeek => 'השבוע';

  @override
  String get historyOlder => 'ישן יותר';

  @override
  String get historyAll => 'הכל';

  @override
  String get historyTrash => 'אשפה';

  @override
  String get historyArchive => 'ארכיון';

  @override
  String get historyArchived => 'בארכיון';

  @override
  String get historyList => 'רשימה';

  @override
  String get historyCards => 'כרטיסים';

  @override
  String get historyCompact => 'קומפקטי';

  @override
  String historyItemsSelected(int count) {
    return '$count נבחרו';
  }

  @override
  String get historyMerge => 'מזג';

  @override
  String get historyRestore => 'שחזר';

  @override
  String get historyDeleteForever => 'מחק לצמיתות';

  @override
  String get historyDeletePermanently => 'מחק לצמיתות';

  @override
  String get historyUnarchive => 'הוצא מהארכיון';

  @override
  String get historyExport => 'ייצא';

  @override
  String get historyExportAction => 'ייצא…';

  @override
  String historyExportDone(String path) {
    return 'יוצא אל $path';
  }

  @override
  String get historyExportFailed =>
      'הייצוא נכשל. בדוק שאפשר לכתוב לתיקיית היעד ונסה שוב.';

  @override
  String get historyCopyAsMarkdown => 'העתק כ-Markdown';

  @override
  String get historyDetail => 'פרטים';

  @override
  String get historyTags => 'תגיות';

  @override
  String get historyDuration => 'משך';

  @override
  String get historyModel => 'מודל זיהוי דיבור';

  @override
  String get historyWords => 'מילים';

  @override
  String get historyCharacters => 'תווים';

  @override
  String historyWordCount(int count) {
    return '$count מילים';
  }

  @override
  String historyReadingTime(int minutes) {
    return '$minutes דק\' קריאה';
  }

  @override
  String get historyReadingTimeUnder1 => 'פחות מדקה קריאה';

  @override
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'כ-$count מילים',
      one: 'כ-מילה אחת',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'תצוגה ובחירה';

  @override
  String get historyEditing => 'עריכה';

  @override
  String get historySearchTranscriptions => 'חפש בהקלטות…';

  @override
  String get historySearchFieldLabel => 'חפש בתמלולים';

  @override
  String get historyNewRecording => 'הקלטה חדשה';

  @override
  String get historyStopRecording => 'עצור הקלטה';

  @override
  String get historyNoResults => 'אין תוצאות';

  @override
  String historyNoResultsHint(String query) {
    return 'אין רשומות שמתאימות ל \"$query\".\nנסה מונח חיפוש אחר.';
  }

  @override
  String get historyTrashEmpty => 'האשפה ריקה';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'פריטים נמחקים לצמיתות אחרי $days ימים.',
      two: 'פריטים נמחקים לצמיתות אחרי יומיים.',
      one: 'פריטים נמחקים לצמיתות אחרי יום אחד.',
      zero: 'פריטים יישארו עד שתמחק אותם לצמיתות.',
    );
    return 'תמלולים שנמחקו יופיעו כאן.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'רוקן אשפה';

  @override
  String get historyEmptyTrashConfirm => 'לרוקן את האשפה?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count תמלולים יימחקו לצמיתות. קבצי אודיו שנשמרו עבורם יימחקו לכל היותר 30 יום לאחר ההקלטה. אין דרך לבטל.',
      two:
          'שני תמלולים יימחקו לצמיתות. קבצי אודיו שנשמרו עבורם יימחקו לכל היותר 30 יום לאחר ההקלטה. אין דרך לבטל.',
      one:
          'תמלול אחד יימחק לצמיתות. קובץ אודיו שנשמר עבורו יימחק לכל היותר 30 יום לאחר ההקלטה. אין דרך לבטל.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => 'למחוק לצמיתות?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count תמלולים יימחקו לצמיתות, יחד עם האודיו השמור שלהם. אין דרך לבטל את הפעולה.',
      one:
          'תמלול אחד יימחק לצמיתות, יחד עם האודיו השמור שלו. אין דרך לבטל את הפעולה.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'האשפה רוקנה — $count תמלולים נמחקו',
      one: 'האשפה רוקנה — תמלול אחד נמחק',
    );
    return '$_temp0';
  }

  @override
  String get historyNoArchivedItems => 'אין פריטים בארכיון';

  @override
  String get historyNoArchivedItemsHint =>
      'העבר תמלולים לארכיון כדי לשמור אותם\nבלי שיופיעו ברשימה הראשית.';

  @override
  String get historyNoRecordingsHint =>
      'לחץ על כפתור ההקלטה או השתמש בקיצור כדי להתחיל.\nהתמלולים שלך יופיעו כאן.';

  @override
  String get historyNoPinned => 'עדיין אין מועדפים';

  @override
  String get historyNoPinnedHint =>
      'סמן תמלול כמועדף כדי למצוא אותו כאן במהירות.';

  @override
  String get historyNoToday => 'לא הוקלט היום';

  @override
  String get historyNoTodayHint => 'הקלטות מהיום יופיעו כאן.';

  @override
  String get historyNoThisWeek => 'לא הוקלט השבוע';

  @override
  String get historyNoThisWeekHint => 'הקלטות מהשבוע יופיעו כאן.';

  @override
  String get historyCopiedToClipboard => 'הועתק ללוח';

  @override
  String get historyMovedToTrash => 'הועבר לאשפה';

  @override
  String get historyRestored => 'שוחזר';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'הועברו לארכיון תמללים: $count',
      one: 'תמלול אחד הועבר לארכיון',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'הועברו לאשפה תמללים: $count',
      one: 'תמלול אחד הועבר לאשפה',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'שוחזרו תמללים: $count',
      one: 'תמלול אחד שוחזר',
    );
    return '$_temp0';
  }

  @override
  String get historyUndo => 'בטל';

  @override
  String get historyEntriesMerged => 'רשומות מוזגו';

  @override
  String historyMergeConfirm(int count) {
    return 'למזג $count רשומות?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'הרשומות הנבחרות ימוזגו לאחת. אין דרך לבטל.';

  @override
  String get historyExitSelection => 'צא מבחירה';

  @override
  String get historySelectMultiple => 'בחר כמה פריטים';

  @override
  String get historyProcessed => 'עובד';

  @override
  String get historyOnDevice => 'במכשיר';

  @override
  String get historyUntitledRecording => 'הקלטה ללא שם';

  @override
  String get historyUntitled => 'ללא שם';

  @override
  String get historyShowAll => 'הצג הכול';

  @override
  String get historyMoreActions => 'פעולות נוספות';

  @override
  String get historyMdTags => 'תגיות';

  @override
  String get historyMdDate => 'תאריך';

  @override
  String get historyMdModel => 'מודל';

  @override
  String get historyPinToTop => 'הוסף למועדפים';

  @override
  String get historyUnpin => 'הסר ממועדפים';

  @override
  String get historyCopyText => 'העתק טקסט';

  @override
  String get historyClose => 'סגור';

  @override
  String get historyLanguageLabel => 'שפה';

  @override
  String historyResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תוצאות',
      one: 'תוצאה אחת',
    );
    return '$_temp0';
  }

  @override
  String get historySelectAll => 'בחר הכל';

  @override
  String get historyDeselectAll => 'בטל בחירה';

  @override
  String get settingsInterface => 'ממשק';

  @override
  String get settingsInterfaceSubtitle => 'מראה והתנהגות';

  @override
  String get settingsReviewPromptRestore => 'הצג שוב את תזכורת הדירוג';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'בחרת „אל תשאל שוב“. הפעלה מחדש מאפשרת את התזכורת; ההפסקות הרגילות ממשיכות לחול.';

  @override
  String get settingsLaunchAtStartup => 'הפעל עם ההפעלה';

  @override
  String get settingsStartMinimized => 'התחל ממוזער';

  @override
  String get settingsStartMinimizedSubtitle => 'התחל ברקע כשהמחשב נדלק';

  @override
  String get settingsAutostartNever => 'לעולם לא';

  @override
  String get settingsAutostartNormal => 'רגיל';

  @override
  String get settingsAutostartMinimized => 'ממוזער';

  @override
  String get settingsAutostartSyncFailed =>
      'לא ניתן היה לרשום את ההפעלה האוטומטית במערכת ההפעלה. ייתכן שמדובר בבעיית הרשאות או שגרסת מערכת ההפעלה שלך אינה נתמכת.';

  @override
  String get settingsShowNotifications => 'הצג התראות';

  @override
  String get settingsShowBackendUtilization => 'מחוון עיבוד בשורת הסטטוס';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'מציג אם המעבד או כרטיס המסך עובדים כרגע.';

  @override
  String get settingsAudio => 'אודיו';

  @override
  String get settingsAudioSubtitle => 'מיקרופון והקלטה';

  @override
  String get settingsMicrophone => 'מיקרופון';

  @override
  String get settingsGain => 'רגישות המיקרופון';

  @override
  String get settingsClippingBanner =>
      'בהקלטה האחרונה הייתה רוויה. להפחית את העוצמה?';

  @override
  String get settingsClippingDismiss => 'הבנתי';

  @override
  String get settingsHoldToRecord => 'החזק להקלטה';

  @override
  String get pushToTalkUnavailableTooltip => 'לא זמין בפלטפורמה זו';

  @override
  String get pushToTalkUnavailableLinuxTooltip =>
      'שולחן העבודה שלך לא מדווח כאן על שחרור מקשים. במקום זאת, הקצה את \"whispaste --toggle\" לקיצור מקלדת בהגדרות המערכת.';

  @override
  String get settingsExperimentalBadge => 'ניסיוני';

  @override
  String get settingsHoldOrTap => 'הקשה או החזקה';

  @override
  String get settingsHoldOrTapHint =>
      'הקשה קצרה מתחילה ועוצרת את ההקלטה; החזקה מקליטה עד שמשחררים.';

  @override
  String get settingsSpeechRecognition => 'זיהוי דיבור';

  @override
  String get settingsSpeechRecognitionSubtitle => 'איכות ושירות זיהוי דיבור';

  @override
  String get settingsService => 'הזיהוי פועל על';

  @override
  String get settingsQuality => 'מהירות ודיוק';

  @override
  String get settingsRecordingSafety => 'בטיחות הקלטה';

  @override
  String get settingsRecordingSafetySubtitle => 'בדיקות אוטומטיות והגנות';

  @override
  String get settingsDeadMicTimeout => 'זיהוי מיקרופון שקט';

  @override
  String get settingsDeadMicTimeoutHint =>
      'עצור הקלטה אם אין אודיו בתוך זמן זה (שניות). 0 = כבוי.';

  @override
  String get settingsAutoStopSilence => 'עצירה אוטומטית אחרי שקט';

  @override
  String get settingsAutoStopSilenceHint =>
      'עצור אוטומטית אחרי X שניות של שקט. 0 = כבוי.';

  @override
  String get settingsEnabled => 'פעיל';

  @override
  String get settingsStyle => 'סגנון';

  @override
  String get settingsMicSystemDefault => 'ברירת מחדל של המערכת';

  @override
  String get settingsMicSystemHint => 'הקלט השמע מנוהל בהגדרות המערכת';

  @override
  String get settingsServiceOnDevicePrivate => 'מקומי במכשיר';

  @override
  String get settingsLanguageAutoDetect => 'זיהוי אוטומטי';

  @override
  String get settingsLanguageEnglish => 'אנגלית';

  @override
  String get settingsLanguageGerman => 'גרמנית';

  @override
  String get settingsLanguageFrench => 'צרפתית';

  @override
  String get settingsLanguageSpanish => 'ספרדית';

  @override
  String get settingsLanguageHebrew => 'עברית';

  @override
  String get settingsSoundFeedback => 'צלילים ומשוב';

  @override
  String get settingsSoundFeedbackSubtitle => 'צלילים לאירועי הקלטה';

  @override
  String get settingsSoundsEnabled => 'צלילים';

  @override
  String get settingsRecordStartSound => 'צליל התחלת הקלטה';

  @override
  String get settingsRecordStopSound => 'צליל סיום הקלטה';

  @override
  String get settingsTranscriptionCompleteSound => 'צליל סיום תמלול';

  @override
  String get settingsDurationWarningSound => 'אזהרת משך מקסימלי';

  @override
  String get settingsSoundVolume => 'עוצמת צליל';

  @override
  String get settingsAfterTranscription => 'אחרי תמלול';

  @override
  String get settingsAfterTranscriptionSubtitle => 'מה לעשות עם הטקסט שתומלל';

  @override
  String get settingsAfterTranscriptionActionLabel => 'אחרי ההקלטה';

  @override
  String get settingsAfterTranscriptionClipboard => 'העתק ללוח';

  @override
  String get settingsAfterTranscriptionPaste => 'הדבק אוטומטי במקום הסמן';

  @override
  String get settingsAfterTranscriptionBoth => 'העתק + הדבק אוטומטי';

  @override
  String get settingsAfterTranscriptionNothing => 'לא לעשות כלום';

  @override
  String get pasteFailurePermissionMissing =>
      'ההדבקה האוטומטית נחסמה על־ידי המערכת. WhisPaste זקוקה להרשאה כדי להוסיף טקסט לאפליקציות אחרות — ב־macOS ההרשאה הזו נקראת \"נגישות\".';

  @override
  String get pasteFailureNoTarget =>
      'ההדבקה האוטומטית דולגה, לא זוהה חלון יעד. מקד את האפליקציה היעד לפני התחלת ההקלטה.';

  @override
  String get pasteFailureElevationBlocked =>
      'ההדבקה האוטומטית נחסמה: האפליקציה היעד פועלת בהרשאות מנהל. הפעל את WhisPaste גם כמנהל כדי להדביק בה.';

  @override
  String pasteFailureGeneric(String paste) {
    return 'ההדבקה האוטומטית נכשלה. הטקסט נמצא בלוח, הדבק ידנית עם $paste.';
  }

  @override
  String get pasteFailureOpenSettings => 'פתח הגדרות';

  @override
  String get pendingAudioSaveLater =>
      'לא ניתן היה לשמור את ההקלטה בהקלטות. ההקלטה נשמרת ותישמר שוב בפעם הבאה ש-WhisPaste ייפתח.';

  @override
  String get pendingAudioRecovered =>
      'הקלטה שלא ניתן היה לשמור קודם נמצאת כעת בהקלטות.';

  @override
  String get pasteNotificationNoTargetTitle =>
      'WhisPaste: ההדבקה האוטומטית דולגה';

  @override
  String get pasteNotificationNoTargetBody =>
      'לא זוהתה אפליקציית יעד. עבור קודם לאפליקציית היעד, ואז התחל להקליט. הטקסט נמצא בלוח.';

  @override
  String get pasteNotificationNoTargetTray =>
      'הדבקה אוטומטית: אפליקציית היעד חסרה';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: אין אות מהמיקרופון';

  @override
  String get silentMicrophoneNotificationBody =>
      'המיקרופון אינו מעביר קול. בדוק את המיקרופון שנבחר ואם הוא מושתק. ההקלטה נמשכת.';

  @override
  String get pasteNotificationRestartNeededTitle =>
      'WhisPaste: נדרשת הפעלה מחדש';

  @override
  String get pasteNotificationRestartNeededBody =>
      'ההרשאה ניתנה, אבל WhisPaste עדיין פועלת עם המצב הישן. לחץ כאן כדי להפעיל מחדש את WhisPaste.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'ההדבקה האוטומטית חסומה — נדרשת הפעלה מחדש';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: ההדבקה האוטומטית חסומה';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'WhisPaste זקוקה להרשאה כדי להכניס טקסט לאפליקציות אחרות — ב-macOS ההרשאה הזו נקראת \"נגישות\". לחץ כאן: WhisPaste תנקה רשומה שאולי אינה עדכנית ותאפשר ל-macOS לבקש שוב.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'WhisPaste זקוקה להרשאה כדי להכניס טקסט לאפליקציות אחרות — ב-macOS ההרשאה הזו נקראת \"נגישות\". לחץ כאן או על סמל המגש כדי לפתוח את הגדרות המערכת.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'ההדבקה האוטומטית חסומה — פתח את הגדרות המערכת';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: ההדבקה האוטומטית חסומה';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'אפליקציית היעד פועלת עם הרשאות מנהל. כדי להדביק בה, הפעל מחדש גם את WhisPaste כמנהל.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'ההדבקה האוטומטית חסומה — נדרשות הרשאות מנהל';

  @override
  String get pasteNotificationFailedTitle =>
      'WhisPaste: ההדבקה האוטומטית נכשלה';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'המערכת חסמה את מקש ההדבקה. הטקסט נמצא בלוח הגזירים. הדבק אותו בעצמך עם $paste.';
  }

  @override
  String get pasteNotificationFailedTray => 'ההדבקה האוטומטית נכשלה';

  @override
  String get pasteNotificationClipboardHint => 'הטקסט נמצא בלוח ההעתקה.';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'WhisPaste עדיין לא יכולה להשתמש במקלדת הווירטואלית /dev/uinput. הטקסט נמצא בלוח הגזירים, הדבק אותו עם $paste. לחץ כאן כדי להגדיר זאת.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'ההדבקה האוטומטית חסומה — נדרשת הגדרה';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'ההדבקה האוטומטית אינה זמינה: במערכת הזו אין מקלדת וירטואלית שנדרשת לה. הטקסט נמצא בלוח הגזירים, הדבק אותו עם $paste. לחץ כאן לפתיחת הגדרות ההדבקה האוטומטית.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray =>
      'ההדבקה האוטומטית אינה זמינה';

  @override
  String get pasteCapabilityCheckTitle => 'רגע…';

  @override
  String get pasteCapabilityReady => 'הכל מוכן';

  @override
  String get pasteCapabilityReadySubtitle => 'הטקסט שלך נוחת ישר בסמן.';

  @override
  String get pasteCapabilityPermissionMissing => 'עוד לא אושר';

  @override
  String get pasteCapabilityUnsupported =>
      'ההדבקה האוטומטית לא זמינה בפלטפורמה זו';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'ההדבקה האוטומטית אינה אפשרית כאן כרגע';

  @override
  String get pasteCapabilityTestButton => 'בדוק עכשיו';

  @override
  String get pasteCapabilityGrantButton => 'המשך';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste זקוקה להרשאה כדי להקליד טקסט באפליקציה שבה אתה עובד — ב-macOS ההרשאה הזו נקראת \"נגישות\".';

  @override
  String get pasteCapabilityTroubleshoot => 'יש בעיה?';

  @override
  String get pasteCapabilityRepairHint =>
      'לפעמים macOS זוכר רשומה ישנה ושוכח את האישור החדש. אפס את הרשומה. macOS ישאל אותך מחדש בצורה נקייה.';

  @override
  String get pasteCapabilityRepairButton => 'אפס רשומה';

  @override
  String get pasteCapabilityRestartButton => 'הפעל מחדש את WhisPaste';

  @override
  String get pasteCapabilityRestartTitle => 'כמעט שם — הפעל מחדש את WhisPaste';

  @override
  String get pasteCapabilityRestartBody =>
      'אם הפעלת את ההרשאה, macOS מחיל אותה רק על אפליקציה שהופעלה מחדש. לחיצה אחת — WhisPaste ייסגר ויחזור מיד.';

  @override
  String get pasteRestartAlertTitle => 'הפעל מחדש את WhisPaste עכשיו';

  @override
  String get pasteRestartAlertBody =>
      'הרשאת ההדבקה האוטומטית הוגדרה, אך macOS מחיל אותה רק לאחר הפעלה מחדש. WhisPaste ייסגר ויחזור מיד.';

  @override
  String get pasteRestartAlertConfirm => 'הפעל מחדש עכשיו';

  @override
  String get pasteStaleEntryGuideTitle => 'הסר את הרשומה הישנה של WhisPaste';

  @override
  String get pasteStaleEntryGuideBody =>
      'macOS עדיין שומר את הרשאת ההדבקה האוטומטית של גרסה קודמת של WhisPaste. אי אפשר להפעיל את הרשומה הזו — יש להסיר אותה פעם אחת:\n\n1. בחר ב-\"WhisPaste\" ברשימה.\n2. לחץ על \"−\" מתחת לרשימה.\n3. חזור ל-WhisPaste.\n\nלאחר הפעלה מחדש macOS ישאל שוב — פשוט אשר.';

  @override
  String get pasteStaleEntryGuideConfirm => 'פתח את הגדרות המערכת';

  @override
  String get pasteStaleEntryRestartTitle => 'הפעל מחדש את WhisPaste';

  @override
  String get pasteStaleEntryRestartBody =>
      'לאחר שהרשומה הישנה הוסרה, הפעל מחדש את WhisPaste. macOS יבקש את ההרשאה שוב — אשר אותה והפעל את WhisPaste.';

  @override
  String get pasteStaleEntryRestartConfirm => 'הפעל מחדש את WhisPaste';

  @override
  String get permissionAlertLaterButton => 'לא עכשיו';

  @override
  String get micGateAlertTitle => 'חסרה גישה למיקרופון';

  @override
  String get micGateAlertBody =>
      'WhisPaste לא יכול להקליט ללא גישה למיקרופון. אשר כדי לפתוח את הגדרות המערכת → פרטיות ואבטחה → מיקרופון — הפעל שם את המתג עבור WhisPaste. WhisPaste מזהה את האישור שלך אוטומטית.';

  @override
  String get micGateAlertBodyGeneric =>
      'WhisPaste לא יכול להקליט ללא גישה למיקרופון. אנא אפשר ל-WhisPaste גישה למיקרופון בהגדרות הפרטיות של המערכת — WhisPaste מזהה את האישור שלך אוטומטית.';

  @override
  String get micGateAlertConfirm => 'פתח הגדרות';

  @override
  String get micGateRestartAlertTitle => 'הפעל מחדש את WhisPaste לסיום';

  @override
  String get micGateRestartAlertBody =>
      'הגישה למיקרופון אושרה, אך מופע WhisPaste הפועל כעת עדיין לא יכול לקלוט אותה. WhisPaste ייסגר ויחזור מיד — הכל נשאר כפי שהוא.';

  @override
  String get micGateRestartAlertConfirm => 'הפעל מחדש עכשיו';

  @override
  String get autoPasteGateAlertTitle => 'חסר מתג אחד להדבקה אוטומטית';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste מוסיף את הטקסט שלך ישירות במיקום הסמן. macOS דורש לשם כך מתג אחד שרק אתה יכול להפעיל: הגדרות המערכת → פרטיות ואבטחה → נגישות. אשר כדי לפתוח בדיוק את העמוד הזה — WhisPaste מזהה את האישור שלך אוטומטית ומפעיל את עצמו מחדש לאחר מכן במידת הצורך.';

  @override
  String get autoPasteGateAlertConfirm => 'פתח את הגדרות המערכת';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'ההפעלה מחדש לא החילה את ההרשאה';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'פתח שוב את ההרשאה ובדוק תחת הגדרות המערכת → פרטיות ואבטחה → נגישות ש-WhisPaste מופעל שם באמת. הפעל מחדש את המתג, ואז WhisPaste יופעל מחדש פעם נוספת.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נוקו $count רשומות ישנות. נסה הדבקה כדי לראות בקשות חדשות.',
      one: 'נוקתה רשומה ישנה אחת. נסה הדבקה כדי לראות בקשה חדשה.',
      zero: 'לא נמצאו רשומות ישנות. נסה הדבקה.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'לא נמצאה רשומה ישנה. סביר להניח שהפעלה מחדש תעזור עכשיו.';

  @override
  String get pasteCapabilityRepairFailed =>
      'לא ניתן היה להריץ איפוס הרשאות של macOS. הסר את WhisPaste ידנית מ־הגדרות מערכת → נגישות.';

  @override
  String get onboardingPasteTitle => 'כדי שהטקסט שלך ינחת איפה שאתה מקליד';

  @override
  String get onboardingPasteSubtitle =>
      'macOS ישאל אותך בעוד רגע אם WhisPaste מורשה. אמור כן, וזהו.';

  @override
  String get onboardingPasteSubtitleWin =>
      'ב-Windows לא נדרשת הרשאה — רק בחר אם WhisPaste ידביק עבורך את הטקסט המוכתב באופן אוטומטי.';

  @override
  String get onboardingPasteSubtitleLinux =>
      'ב-Linux אין חלון מערכת שמבקש הרשאה. למטה מצוין אם צריך להגדיר משהו בשביל זה.';

  @override
  String get onboardingPasteChipReady => 'הדבקה אוטומטית מוכנה';

  @override
  String get onboardingPasteChipPending => 'גישה להדבקה אוטומטית ממתינה';

  @override
  String get onboardingPasteChipAction => 'הדבקה אוטומטית: נדרשת פעולה';

  @override
  String get onboardingPasteGrantCta => 'אפשר הדבקה אוטומטית';

  @override
  String get onboardingPasteSkip => 'רק להעתיק לעת עתה, בלי הדבקה אוטומטית';

  @override
  String get onboardingPasteWhyMac =>
      'בלי אישור, הטקסט יועתק ללוח. תצטרך להדביק ידנית עם ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'הדבקה אוטומטית מקישה Ctrl+V עבורך אחרי כל הקלטה, כך שהטקסט מגיע ישירות למקום שבו אתה כותב. נבדק ופועל במחשב הזה — הפעל למטה.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'בתוכניות שרצות כמנהל מערכת, ההדבקה האוטומטית לא תעבוד. הטקסט יישאר בלוח הגזירים, ותצטרך להדביק אותו בעצמך עם Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'הדבקה אוטומטית פעילה';

  @override
  String get onboardingPasteWinOnDetail =>
      'אחרי כל הקלטה WhisPaste מקיש Ctrl+V עבורך — הטקסט מגיע ישירות למיקום הסמן. עותק נשאר גם בלוח הגזירים.';

  @override
  String get onboardingPasteLinuxNative =>
      'הדבקה אוטומטית צריכה את ההרשאה שלך למקלדת הווירטואלית (/dev/uinput). עם חבילת ה-.deb, בחר „לאפשר (סיסמת מנהל)” והזן את סיסמת המנהל; אחרת העתק את הפקודה והרץ אותה פעם אחת בטרמינל. אפשר להסיר את ההרשאה בהגדרות.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'בגרסת Flatpak, ‏--device=all חושף את /dev/input/* ואת /dev/uinput בתוך ארגז החול. WhisPaste עצמה לא קוראת התקני קלט. אם למשתמש שלך יש הרשאות קריאה במחשב (למשל כחבר בקבוצה input), האפליקציה עלולה לקרוא הקשות של תוכנות אחרות. הדבקה אוטומטית צריכה גם הרשאת כתיבה ל-/dev/uinput במחשב: העתק את הפקודה והרץ אותה פעם אחת בטרמינל. היא מתקינה את כלל ה-udev ‏71-whispaste-uinput.rules, שנותן גישה רק להפעלה המחוברת. הפקודה דורשת הרשאות מנהל (sudo) ומשנה את המערכת. אם אינך רוצה בכך, השאר את ההדבקה האוטומטית כבויה והדבק את הטקסט ידנית.';

  @override
  String get onboardingPasteLinuxSnap =>
      'בגרסת Snap, הריצו פעם אחת בטרמינל: sudo snap connect whispaste:uinput. עד אז, הדבקה אוטומטית רק מעתיקה את הטקסט.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'ה-AppImage צריך גישה ל-/dev/uinput (המקלדת הווירטואלית). העתק את הפקודה והרץ אותה פעם אחת בטרמינל. היא מתקינה את כלל ה-udev ‏71-whispaste-uinput.rules אל /etc/udev/rules.d/ ומריצה sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. הכלל נותן הרשאת כתיבה רק להפעלה המחוברת. הפקודה דורשת הרשאות מנהל (sudo) ומשנה את המערכת. עד אז, הדבקה אוטומטית רק מעתיקה את הטקסט.';

  @override
  String get onboardingPasteWinEnableCta => 'הפעל את ההדבקה האוטומטית';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'בתוכניות שרצות כמנהל מערכת, ההדבקה האוטומטית לא תעבוד. הטקסט יישאר בלוח הגזירים, ותצטרך להדביק אותו בעצמך עם Ctrl+V.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'ההדבקה האוטומטית פעילה. עד שהגישה תוגדר, WhisPaste ישים את הטקסט בלוח הגזירים, ותדביק אותו בעצמך עם Ctrl+V.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'הטקסט נשמר בלוח. הדבק אותו עם $shortcut.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'סמן את התיבה ליד WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'הגדרות המערכת פתוחות. מצא את WhisPaste ברשימה והפעל אותו.\n\nלא ברשימה? גרור את סמל האפליקציה פנימה או לחץ על \"+\".';

  @override
  String get onboardingPasteTestTitle => 'נסה הדבקה אוטומטית';

  @override
  String get onboardingPasteTestSubtitle =>
      'הקש על הכפתור. טקסט ההדגמה אמור להופיע בשדה למטה.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste מקליד בשבילך.';

  @override
  String get onboardingPasteTestSuccess =>
      'ההדבקה האוטומטית פועלת! לחץ על הבא להמשך.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'לא זוהה שדה קלט. לחץ על השדה למטה ונסה שוב.';

  @override
  String get onboardingPasteTestFailure =>
      'הבדיקה נכשלה. נסה להפעיל מחדש את האפליקציה, או המשך ללא בדיקה.';

  @override
  String get onboardingPasteTestSkip => 'המשך ללא בדיקה';

  @override
  String get settingsOverlayFloatingButton => 'שכבת הקלטה צפה';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'איך להציג סטטוס הקלטה בזמן דיבור';

  @override
  String get settingsShowOverlay => 'תצוגת סטטוס הקלטה';

  @override
  String get settingsShowOverlaySubtitle => 'איפה להציג משוב חי בזמן דיבור';

  @override
  String get settingsOverlayModeFloating => 'צף (תמיד גלוי)';

  @override
  String get settingsOverlayModeOff => 'כבוי';

  @override
  String get settingsOverlayStartPosition => 'מיקום התחלתי של השכבה';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'איפה השכבה הצפה תופיע בתחילת הקלטה';

  @override
  String get settingsOverlayStartTopCenter => 'למעלה במרכז';

  @override
  String get settingsOverlayStartBottomCenter => 'למטה במרכז';

  @override
  String get settingsOverlayStartLastPosition => 'זכור מיקום אחרון';

  @override
  String get settingsShowFloatingButton => 'כפתור צף';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'כפתור קטן תמיד עליון להתחלת/עצירת הקלטה';

  @override
  String get settingsLanguage => 'שפה';

  @override
  String get settingsRecognitionLanguage => 'שפת זיהוי';

  @override
  String get settingsCustomVocabulary => 'אוצר מילים מותאם';

  @override
  String get settingsCustomVocabularyHint => 'שמות, מונחים טכניים: משפר דיוק';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'לדוגמה: WhisPaste, Kubernetes, ד\"ר כהן';

  @override
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return '~$count מתוך $budget בשימוש';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'אם הרשימה תופסת יותר מ-$budget, השאר מושמט אוטומטית.';
  }

  @override
  String get settingsPunctuationPriming => 'פריימינג פיסוק';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'גורם לזיהוי להוסיף יותר סימני פיסוק כשלא הוגדר אוצר מילים מותאם אישית. המהירות לא משתנה.';

  @override
  String get settingsVadEnabled => 'חיתוך שתיקה בסוף ההקלטה';

  @override
  String get settingsVadEnabledSubtitle =>
      'חותך שתיקה ארוכה ורעש בסוף הקלטה, כדי שהזיהוי לא ימציא משפט סיום (למשל „תודה שצפית“).';

  @override
  String get settingsStripPunctuation => 'הסרת סימני פיסוק';

  @override
  String get settingsStripPunctuationSubtitle =>
      'האפשרות הזו מסירה נקודות, פסיקים וסימני פיסוק נוספים מכל תמלול לפני השמירה או ההדבקה. מספרים כמו 3.5 נשארים ללא שינוי. היא פועלת באותו אופן בכל שיטות הזיהוי.';

  @override
  String get settingsNumericOnlyMode => 'מספרים בלבד';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'ממיר מספרים מדוברים (בגרמנית ובאנגלית) לספרות, למשל \"חמש פסיק שתיים\" הופך ל-\"5,2\". משאיר את התמלול ללא שינוי אם אינו ניתן להמרה מלאה.';

  @override
  String get settingsRemoveFillerWords => 'הסרת מילות מילוי';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'מסירה צלילי היסוס כמו \"uh\", \"um\" ו-\"äh\" לפני שהתמלול נשמר או מודבק. רק מילות מילוי חד-משמעיות באנגלית ובגרמנית; מילים שיכולות לשאת משמעות לא משתנות.';

  @override
  String get settingsVoiceLineBreaks => 'מעברי שורה בקול';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'הופך פקודות קוליות כמו \"פסקה חדשה\" ו\"שורה חדשה\" למעברי שורה אמיתיים. פועל לפי שפת התמלול, ובזיהוי אוטומטי לפי כל השפות הנתמכות.';

  @override
  String get settingsSpokenPunctuation => 'סימני פיסוק בקול';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'אם אתה אומר „פסיק“ או „נקודה“ כמילה בתוך משפט, בדוק את הטקסט אחר כך.';

  @override
  String get settingsAppLanguage => 'שפת האפליקציה';

  @override
  String get settingsSttModels => 'מודלי זיהוי דיבור';

  @override
  String get settingsOpenAiApiKey => 'מפתח OpenAI';

  @override
  String get settingsDeepgramApiKey => 'מפתח Deepgram';

  @override
  String get settingsToggleApiKeyVisibility => 'הצג/הסתר מפתח API';

  @override
  String get settingsAdvanced => 'מתקדם';

  @override
  String get settingsAdvancedSubtitle =>
      'איפוס, דיווח שגיאות, עדכונים והתנהגות המערכת';

  @override
  String get settingsResetToDefaults => 'אפס להגדרות ברירת מחדל';

  @override
  String get settingsResetTitle => 'איפוס הגדרות';

  @override
  String get settingsResetMessage =>
      'כל ההגדרות יחזרו לברירת מחדל. מפתחות API יוסרו. אין דרך לבטל.';

  @override
  String get settingsResetConfirm => 'אפס';

  @override
  String get settingsResetSuccess => 'ההגדרות אופסו';

  @override
  String get settingsFactoryReset => 'איפוס הכול';

  @override
  String get settingsFactoryResetTitle => 'איפוס מלא';

  @override
  String get settingsFactoryResetMessage =>
      'פעולה זו תמחק מיד: תמלולים עם התגיות והפתקים שלהם, קבצי אודיו שנשמרו, מילון, קטעים, סטטיסטיקה, מפתחות API, מודלים שהורדו, יומנים והגדרות. האפליקציה תחזור למצב ההתחלתי.\n\nהאפליקציה לא יכולה לשחזר דבר מכל זה. הקבצים נמחקים במחיקה רגילה ולא נדרסים, ולכן כלים מיוחדים עשויים לשחזר חלקים מהם.';

  @override
  String get settingsFactoryResetConfirm => 'מחק הכל';

  @override
  String get settingsFactoryResetSuccess => 'האפליקציה אופסה לחלוטין';

  @override
  String get settingsFactoryResetProgressTitle => 'מבצע איפוס של WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'עוצר את מודל זיהוי הדיבור…';

  @override
  String get settingsFactoryResetPhaseDeletingModels => 'מוחק את מודלי הקול…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio => 'מוחק הקלטות…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase =>
      'מוחק את מסד הנתונים…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'מנקה את פרטי ההתחברות השמורים…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'משחזר את ההגדרות לברירת המחדל…';

  @override
  String settingsFactoryResetFailedMessage(String areas) {
    return 'האיפוס לא הושלם. מושפע: $areas. אפשר לנסות שוב.';
  }

  @override
  String get factoryResetAreaDb => 'תמלולים, פתקים, מילון, קטעים וסטטיסטיקה';

  @override
  String get factoryResetAreaAudio => 'קבצי אודיו';

  @override
  String get factoryResetAreaModels => 'מודלים ויומנים';

  @override
  String get factoryResetAreaSecure => 'מפתחות API';

  @override
  String get factoryResetAreaSettings => 'הגדרות';

  @override
  String get factoryResetAreaProcess => 'תהליך רקע';

  @override
  String get factoryResetRetryAction => 'נסה שוב';

  @override
  String get factoryResetKeyringHint =>
      'לא ניתן היה להסיר את מפתחות ה-API ממחזיק המפתחות. במידת הצורך, מחק בעצמך את הרשומות שמתחילות ב-„wp_” במנהל הסיסמאות של המערכת.';

  @override
  String get settingsPortabilitySectionTitle => 'גיבוי והעברה';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'שמור גיבוי של הגדרות WhisPaste שלך או קח אותן איתך למחשב אחר';

  @override
  String get settingsPortabilityExportAction => 'ייצוא';

  @override
  String get settingsPortabilityImportAction => 'ייבוא';

  @override
  String get settingsPortabilityExportLocationLabel => 'יעד הייצוא';

  @override
  String get settingsPortabilityImportLocationLabel => 'מקור הייבוא';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'המיקום ייבחר בייצוא הראשון';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'המיקום ייבחר בייבוא הראשון';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'בחירת יעד ייצוא אחר (עדיין לא מתבצע ייצוא)';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'בחירת מקור ייבוא אחר (עדיין לא מתבצע ייבוא)';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'ההגדרות יוצאו אל $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'הייצוא נכשל: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle => 'לייבא הגדרות?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'פעולה זו תחליף את ההגדרות הנוכחיות שלך — כולל ממשק, תצורת זיהוי הדיבור, התנהגות, החלפות טקסט וקטעים — בתוכן של $path. מפתחות ה-API שלך לא ייפגעו.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'ההגדרות יובאו מ-$path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'לא נמצא קובץ ייצוא ב-$path. ייצא הגדרות תחילה, או העתק לשם קובץ ייצוא.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'הייבוא נכשל: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'גיבוי אוטומטי';

  @override
  String get settingsAutosaveHint =>
      'שומר את ההגדרות שלך בתיקייה שנבחרה כמה שניות אחרי כל שינוי';

  @override
  String get settingsAutosaveChooseFolder =>
      'בחירת תיקייה אחרת לגיבוי האוטומטי (עדיין לא מתבצע גיבוי)';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'הגיבוי האחרון: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'עדיין אין גיבוי';

  @override
  String get settingsAutosaveLastRunFailed => 'הגיבוי נכשל';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'הניסיון האחרון נכשל — הגיבוי האחרון: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'הגיבוי האוטומטי נכשל: התיקייה שנבחרה אינה זמינה.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'הגיבוי האוטומטי נכשל: $reason';
  }

  @override
  String get groqRemovedToast =>
      'ספק הענן שבו השתמשת הוסר. זיהוי הדיבור פועל כעת במכשיר הזה.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמלולים הועברו מ-WhisPaste 1.x',
      one: 'תמלול אחד הועבר מ-WhisPaste 1.x',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'כבוי';

  @override
  String get settingsOn => 'פעיל';

  @override
  String get statusReady => 'מוכן';

  @override
  String get statusRecording => 'מקליט…';

  @override
  String get statusTranscribing => 'מתמלל…';

  @override
  String get statusProcessing => 'מעבד…';

  @override
  String get statusTranscriptionDone => 'תמלול הושלם';

  @override
  String get statusSelectionEdited => 'הבחירה נערכה';

  @override
  String get statusCopied => 'הועתק!';

  @override
  String get statusLocal => 'מקומי';

  @override
  String get statusCloud => 'ענן';

  @override
  String get statusOnline => 'מחובר';

  @override
  String get statusOffline => 'מנותק';

  @override
  String get recordingGuardFailed =>
      'לא זוהה אודיו. נסה שוב. לפעמים המיקרופון צריך רגע להתחמם.';

  @override
  String get recordingAutoStopped => 'ההקלטה נעצרה: זוהה שקט.';

  @override
  String get actionCopy => 'העתק';

  @override
  String get actionDuplicate => 'שכפל';

  @override
  String get actionDelete => 'מחק';

  @override
  String get actionDismiss => 'סגור';

  @override
  String get actionEdit => 'ערוך';

  @override
  String get actionExport => 'ייצא';

  @override
  String get unsavedInputTitle => 'להשליך את השינויים?';

  @override
  String get unsavedInputMessage => 'הטקסט שהקלדת עוד לא נשמר.';

  @override
  String get unsavedInputDiscard => 'השלך';

  @override
  String get trayUnavailableMinimizedHint =>
      'סמל מגש המערכת אינו זמין. WhisPaste מוזער וממשיך לפעול.';

  @override
  String get settingsSaveFailedToast =>
      'לא ניתן לשמור את ההגדרה. נשמר הערך הקודם.';

  @override
  String get actionCancel => 'בטל';

  @override
  String get actionClose => 'סגור';

  @override
  String get actionConfirm => 'אישור';

  @override
  String get actionSave => 'שמור';

  @override
  String get actionRetry => 'נסה שנית';

  @override
  String get actionClearSearch => 'נקה חיפוש';

  @override
  String get tooltipLanguage => 'שפה';

  @override
  String aboutVersion(String version) {
    return 'גרסה $version';
  }

  @override
  String get onboardingWelcome => 'דבר פעם אחת. הדבק בכל מקום.';

  @override
  String get feedbackTitle => 'שלח משוב';

  @override
  String get feedbackHint => 'ספר לנו מה דעתך. אנחנו קוראים כל הודעה.';

  @override
  String get analyticsPreviewBanner =>
      'תצוגה מקדימה: נתונים לדוגמה. ניתוח אמיתי יופיע אחרי שתתחיל להקליט.';

  @override
  String get analyticsEmptyTitle => 'עדיין אין הקלטות';

  @override
  String get analyticsEmptySubtitle =>
      'התחל להקליט כדי לראות כאן ניתוח נתונים.';

  @override
  String get analyticsNoRecordingsInPeriod => 'אין הקלטות בתקופה הזו';

  @override
  String get analyticsOverview => 'סקירה';

  @override
  String get analyticsOverviewSubtitle => 'סטטיסטיקות ההקלטה שלך במבט חטוף';

  @override
  String get analyticsActivity => 'פעילות';

  @override
  String get analyticsInsights => 'תובנות';

  @override
  String get analyticsTotalRecordings => 'סה\"כ הקלטות';

  @override
  String get analyticsTotalDuration => 'סה\"כ זמן';

  @override
  String get analyticsWordsDictated => 'מילים שתומללו';

  @override
  String get analyticsTimeSaved => 'זמן שנחסך (הערכה)';

  @override
  String get analyticsAvgLatency => 'זמן ממוצע עד לטקסט';

  @override
  String get analyticsRecordingActivity => 'פעילות הקלטה';

  @override
  String get analyticsLast7Days => '7 הימים האחרונים';

  @override
  String get analyticsWeekEmpty => 'לא הייתה הקלטה ב-7 הימים האחרונים';

  @override
  String get analyticsModelUsage => 'שימוש במודלי זיהוי דיבור';

  @override
  String get analyticsNoModelData => 'עדיין אין נתוני מודלים בתקופה הזו';

  @override
  String get analyticsLoading => 'טוען סטטיסטיקה';

  @override
  String get analyticsDurationDistribution => 'התפלגות משך';

  @override
  String get analyticsCostSavings => 'עלות וחיסכון';

  @override
  String get analyticsLocalSavings => 'חיסכון מקומי';

  @override
  String get analyticsCloudCost => 'עלות ענן';

  @override
  String get analyticsEstimateNote => 'הערכה לפי מחירי המחירון לכל תמלול';

  @override
  String get analyticsPeriod7d => '7 ימים';

  @override
  String get analyticsPeriod30d => '30 יום';

  @override
  String get analyticsPeriod90d => '90 יום';

  @override
  String get analyticsPeriodAll => 'כל הזמן';

  @override
  String get analyticsReset => 'אפס';

  @override
  String get analyticsResetTitle => 'איפוס סטטיסטיקות';

  @override
  String get analyticsResetMessage =>
      'האם אתה בטוח שברצונך לנקות את כל נתוני הניתוח? אין דרך לבטל.';

  @override
  String get analyticsResetDone => 'הסטטיסטיקה אופסה.';

  @override
  String get analyticsDayMon => 'ב\'';

  @override
  String get analyticsDayTue => 'ג\'';

  @override
  String get analyticsDayWed => 'ד\'';

  @override
  String get analyticsDayThu => 'ה\'';

  @override
  String get analyticsDayFri => 'ו\'';

  @override
  String get analyticsDaySat => 'ש\'';

  @override
  String get analyticsDaySun => 'א\'';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta השבוע';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta לעומת החודש הקודם';
  }

  @override
  String get analyticsDurationLt15s => 'פחות מ-15 שניות';

  @override
  String get analyticsDuration15To30s => '15-30 שניות';

  @override
  String get analyticsDuration30To60s => '30-60 שניות';

  @override
  String get analyticsDuration1To3m => '1-3 דקות';

  @override
  String get analyticsDurationGt3m => 'יותר מ-3 דקות';

  @override
  String analyticsSavedAmount(String amount) {
    return '$amount נחסך';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount הוצא';
  }

  @override
  String get replacementsSearch => 'חפש החלפות…';

  @override
  String get replacementsSearchFieldLabel => 'חפש החלפות';

  @override
  String get replacementsAdd => 'הוסף';

  @override
  String get replacementsEmpty => 'עדיין אין החלפות';

  @override
  String get replacementsEmptyHint =>
      'הוסף החלפות כדי להחליף אוטומטית מילים בזמן הקלטה.\nדוגמה: \"btw\" → \"אגב\"';

  @override
  String get replacementsNoMatches => 'אין התאמות';

  @override
  String get replacementsNoMatchesHint => 'נסה מונח חיפוש אחר.';

  @override
  String get replacementsToggleLabel => 'הפעל החלפות';

  @override
  String get replacementsToggleEnabled => 'ההחלפות פעילות';

  @override
  String get replacementsToggleDisabled => 'ההחלפות כבויות';

  @override
  String get replacementsEnableBannerTitle => 'ההחלפות מושבתות';

  @override
  String get replacementsEnableBannerHint =>
      'הפעל אותם כדי שהביטויים יוחלפו אוטומטית.';

  @override
  String get replacementsEnableAction => 'הפעל';

  @override
  String get replacementsDisableAction => 'כבה';

  @override
  String get replacementsEditShortcut => 'ערוך החלפה';

  @override
  String get replacementsNewShortcut => 'החלפה חדשה';

  @override
  String get replacementsDialogHint =>
      'כל אחד מהביטויים המפעילים יוחלף אוטומטית בזמן הקלטה.';

  @override
  String get replacementsTriggerLabel => 'ביטויים מפעילים';

  @override
  String get replacementsTriggerHint => 'לדוגמה: btw';

  @override
  String get replacementsAddTrigger => 'הוסף ביטוי מפעיל';

  @override
  String get replacementsMissingTrigger => 'הוסיפו לפחות ביטוי מפעיל אחד.';

  @override
  String get replacementsRemoveTrigger => 'הסר ביטוי מפעיל';

  @override
  String get replacementsReplacementLabel => 'טקסט להחלפה';

  @override
  String get replacementsMissingReplacement => 'הזינו את טקסט ההחלפה.';

  @override
  String get replacementsReplacementHint => 'לדוגמה: אגב';

  @override
  String get replacementsReplacementHelper =>
      'השתמש ב-\\n למעבר שורה וב-\\n\\n לשורה ריקה. לשמירת backslash-n כטקסט רגיל כתוב \\\\n.';

  @override
  String get replacementsDeleteTitle => 'מחק קיצור';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'להסיר את הקיצור \"$trigger\"? אין דרך לבטל.';
  }

  @override
  String get replacementsImportFromFolder => 'ייבוא מתיקייה';

  @override
  String get replacementsImportHint =>
      'סורק תיקיית פרויקט לזיהוי מזהים ומוסיף אותם כהחלפות מקורבות (fuzzy) — שום דבר לא יוצא מהמכשיר שלך.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return 'נמצאו $found, נוספו $added, $skipped כפילויות דולגו';
  }

  @override
  String get replacementsImportScanning =>
      'סורק את התיקייה — זה עשוי לקחת רגע בפרויקטים גדולים…';

  @override
  String get replacementsImportError =>
      'הייבוא נכשל — לא ניתן היה לסרוק את התיקייה.';

  @override
  String get replacementsImportedBadge => 'יובא';

  @override
  String get replacementsLearnedBadge => 'נלמד';

  @override
  String get correctionLearningToggleLabel => 'למידה מתיקונים';

  @override
  String get correctionLearningToggleEnabled =>
      'תיקוני קול חזרים נבדקים להצעות';

  @override
  String get correctionLearningToggleDisabled =>
      'תיקוני קול אינם נבדקים להצעות';

  @override
  String get correctionLearningHowTo =>
      'בזמן הקלטת הערה בהקלטות, אמור \"correct: …\" (או \"korrektur: …\") ואחריו את הטקסט המתוקן כדי לדרוס אותו. תקן את אותו הדבר פעמיים, ו-WhisPaste תציע אותו כאן כהחלפה אוטומטית.';

  @override
  String get correctionCandidatesCardTitle => 'הצעות מהתיקונים שלך';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count הצעות מתיקוני קול חזרים — יש לבדוק לפני שהן הופכות להחלפות.';
  }

  @override
  String get correctionCandidatesReviewButton => 'בדיקה';

  @override
  String get correctionCandidatesReviewTitle => 'סקירת תיקונים שנלמדו';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תיקונים שחזרת עליהם',
      one: 'תיקון אחד שחזרת עליו',
    );
    return '$_temp0 — אשר את אלה ש-WhisPaste תחיל מעכשיו אוטומטית. שום דבר לא משתנה עד שתאשר.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return 'נוספו $added החלפות נלמדות';
  }

  @override
  String get replacementsImportNothingFound =>
      'לא נמצאו מזהים חדשים בתיקייה זו.';

  @override
  String get replacementsImportReviewTitle => 'בחר מה לייבא';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return 'נמצאו $count מועמדים — בחר אילו יהפכו להחלפות. שום דבר לא יתווסף עד שתאשר.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'סינון מועמדים';

  @override
  String get replacementsImportReviewSelectAllFiltered => 'בחר את כל המוצגים';

  @override
  String get replacementsImportReviewDeselectAll => 'בטל בחירת הכול';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return '$selected מתוך $total נבחרו';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'אין מועמדים התואמים לסינון שלך.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'ייבא נבחרים ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'התאמה';

  @override
  String get replacementsMatchModeExact => 'מדויק';

  @override
  String get replacementsMatchModeFuzzy => 'דומה';

  @override
  String get replacementsFuzzyToleranceLabel => 'סבילות';

  @override
  String get replacementsFuzzyToleranceStrict => 'מחמיר';

  @override
  String get replacementsFuzzyToleranceStandard => 'רגיל';

  @override
  String get replacementsFuzzyToleranceTolerant => 'סובלני';

  @override
  String get replacementsFuzzyToleranceHint =>
      'עד כמה דומה צריך להישמע ביטוי מוכתב לטריגר כדי שעדיין ייחשב כהתאמה. מחמיר תופס רק ניסוח כמעט זהה, כך שכמעט שום דבר לא מוחלף בטעות, אך טריגר שנאמר בצורה לא ברורה עלול לחמוק בלי התאמה. רגיל הוא ברירת מחדל מאוזנת לשימוש יומיומי. סובלני תופס גם הגייה או ניסוח שונים באופן ניכר, בסיכון גבוה יותר להתאמת משהו שלא היה מיועד להחלפה.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'לביטויי הפעלה מתחת ל-$minLength תווים אי אפשר להשתמש בהתאמה מקורבת — זה יוצר יותר מדי התאמות שגויות.';
  }

  @override
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'הטריגר „$trigger“ כבר קיים (החלפה: „$replacement“).';
  }

  @override
  String get snippetsSearch => 'חפש קטעים…';

  @override
  String get snippetsSearchFieldLabel => 'חפש קטעים';

  @override
  String get snippetsAdd => 'הוסף';

  @override
  String get snippetCopySuffix => '(עותק)';

  @override
  String get snippetsEmpty => 'עדיין אין קטעים';

  @override
  String get snippetsEmptyHint =>
      'הוסף קטע כדי לעשות שימוש חוזר מהיר בבלוק טקסט — כמו חתימה או תשובה סטנדרטית.';

  @override
  String get snippetsNoMatches => 'אין התאמות';

  @override
  String get snippetsNoMatchesHint => 'נסה מונח חיפוש אחר.';

  @override
  String get snippetsEditSnippet => 'ערוך קטע';

  @override
  String get snippetsNewSnippet => 'קטע חדש';

  @override
  String get snippetsDialogHint =>
      'פתח את בורר הקטעים בזמן הקלטה כדי להוסיף את הטקסט הזה.';

  @override
  String get snippetsTitleLabel => 'כותרת';

  @override
  String get snippetsTitleHint => 'לדוגמה: חתימת אימייל';

  @override
  String get snippetsBodyLabel => 'תוכן';

  @override
  String get snippetsBodyHint => 'הטקסט שהקטע הזה מכניס…';

  @override
  String get snippetsKindLabel => 'סוג';

  @override
  String get snippetsKindStatic => 'סטטי';

  @override
  String get snippetsKindInteractive => 'אינטראקטיבי';

  @override
  String get snippetsFieldsLabel => 'שדות';

  @override
  String get snippetsFieldsHint =>
      'תונחה דרך כל שדה בזה אחר זה, עם הקלטה קצרה משלו.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'שם לשדה $number';
  }

  @override
  String get snippetsFieldMoveUp => 'הזז שדה למעלה';

  @override
  String get snippetsFieldMoveDown => 'הזז שדה למטה';

  @override
  String get snippetsFieldRemove => 'הסר שדה';

  @override
  String get snippetsFieldAdd => 'הוסף שדה';

  @override
  String get snippetsFieldInsertIntoTemplate => 'הוסף לתוך התבנית';

  @override
  String snippetsFieldsMinWarning(int min) {
    return 'קטע אינטראקטיבי דורש לפחות $min שדות בעלי שם.';
  }

  @override
  String get snippetsTemplateLabel => 'תבנית';

  @override
  String get snippetsTemplateHint =>
      'כתוב את טקסט הקטע, ולאחר מכן השתמש בכפתור ההוספה של כל שדה כדי למקם אותו במקום הרצוי.';

  @override
  String get snippetsTemplateFieldHint =>
      'כתוב כאן את הטקסט שלך והוסף שדות באמצעות הכפתורים שלמעלה.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'לא כל השדות מופיעים עדיין בתבנית — הטקסט המוכתב שלהם יישאר בלתי מנוצל.';

  @override
  String get snippetsSaveMissingTitle => 'חסרה כותרת';

  @override
  String get snippetsSaveMissingBody => 'חסר טקסט';

  @override
  String get snippetsFieldsDuplicateWarning => 'לכל שדה צריך להיות שם שונה.';

  @override
  String get snippetsInteractiveBadge => 'אינטראקטיבי';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count שדות',
      one: 'שדה אחד',
    );
    return '$_temp0 · Enter מתחיל';
  }

  @override
  String interactiveSnippetBriefingHint(String name) {
    return 'שדה 1: $name · Esc: ביטול';
  }

  @override
  String interactiveSnippetAnnounceLabel(int index, int count, String name) {
    return 'שדה $index/$count: $name';
  }

  @override
  String get interactiveSnippetAnnounceHint => 'התכונן לדבר…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'הבא';

  @override
  String get snippetsDeleteTitle => 'מחק קטע';

  @override
  String snippetsDeleteMessage(String title) {
    return 'להסיר את הקטע \"$title\"? אין דרך לבטל.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'מילת הפעלה לבוחר הקטעים';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'אמור רק את המילה הזו כדי לפתוח את בוחר הקטעים. השאר ריק כדי לכבות את הבוחר.';

  @override
  String get snippetsPickerTriggerHint => 'לדוגמה: קטע';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'מילת ההפעלה מוגדרת, אבל אין עדיין קטעים — אמירתה תודבק כטקסט רגיל עד שתוסיף את הקטע הראשון.';

  @override
  String get snippetsPickerSettingsLink => 'מילת ההפעלה והקיצור בהגדרות';

  @override
  String get snippetsPickerHotkeyLabel => 'קיצור לבוחר';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'פותח את הבוחר מיד — הדרך השנייה לאותו חלון.';

  @override
  String get snippetsPickerHotkeyOff => 'הקיצור לבוחר כבוי.';

  @override
  String get snippetsPickerHotkeyEnable => 'הפעלת הקיצור';

  @override
  String get snippetsPickerUnavailable =>
      'בוחר הקטעים עדיין אינו זמין בפלטפורמה הזו.';

  @override
  String get snippetsPickerSemanticsLabel => 'בוחר הקטעים';

  @override
  String get snippetsPickerInsertAction => 'הוסף';

  @override
  String get aboutTagline => 'מדיבור לטקסט, מיד.';

  @override
  String get aboutWhatsNew => 'מה חדש';

  @override
  String get aboutReportIssue => 'דווח על בעיה';

  @override
  String get aboutSupportTitle => 'תמוך בפרויקט';

  @override
  String get aboutSupportDescription =>
      'WhisPaste חינמי וקוד פתוח תחת רישיון MIT. תמיכה מכסה עלויות קבועות שוטפות אמיתיות (Apple Developer Program, Microsoft Partner Center ואחסון/דומיין) ששומרות עליו זמין בכל פלטפורמה.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'כוכב ב-GitHub';

  @override
  String get aboutSponsorsTitle => 'ספונסרים';

  @override
  String get supportPromptRecurringTitle => 'להפוך את זה לתמיכה חודשית?';

  @override
  String get supportPromptRecurringDescription =>
      'תודה שכבר תמכת ב-WhisPaste. אם תרצה, תוכל להפוך את זה לתמיכה חודשית קטנה שממשיכה לכסות את ההוצאות הקבועות שלנו.';

  @override
  String get aboutBuiltWith => 'נבנה עם';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'ממשק חוצה פלטפורמות עם Flutter. AI מקומי דרך whisper.cpp ו-llama.cpp.';

  @override
  String get aboutWhisper => 'whisper.cpp ו-OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'זיהוי דיבור מקומי וענן: מהיר, מדויק, רב-לשוני.';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet ו-sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'זיהוי דיבור מקומי, מואץ ב-GPU היכן שזמין (Metal, Vulkan, CUDA) ובמעבד אחרת (כ-25 שפות).';

  @override
  String get aboutParakeetModelCredit =>
      'מודל: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'המרה ל-GGUF: ggml-org, MIT';

  @override
  String get aboutLinks => 'קישורים';

  @override
  String get helpLegalTitle => 'משפטי';

  @override
  String get helpDiagnosticsPublicNote =>
      'בעיות ב-GitHub הן ציבוריות. בדקו את הדוח לפני ההדבקה.';

  @override
  String get helpDiagnosticsBuilding => 'הדוח נוצר …';

  @override
  String get tabsScrollBack => 'הצג לשוניות קודמות';

  @override
  String get tabsScrollForward => 'הצג לשוניות נוספות';

  @override
  String get aboutWebsite => 'אתר';

  @override
  String get aboutGitHubRepo => 'מאגר GitHub';

  @override
  String get aboutFollowOnX => 'עקוב ב-X';

  @override
  String get aboutMitLicense => 'רישיון MIT';

  @override
  String get aboutThirdPartyLicenses => 'רישיונות צד שלישי';

  @override
  String get aboutThirdPartyLicensesDetail => 'גופנים ומודלים';

  @override
  String get aboutPrivacyPolicy => 'מדיניות פרטיות';

  @override
  String get aboutImprint => 'הודעה משפטית';

  @override
  String get aboutSystemInfo => 'מידע מערכת';

  @override
  String get aboutSystemInfoDesc => 'העתק snapshot לאבחון עבור דיווחי באגים.';

  @override
  String get aboutDiagnosticsContentsTitle => 'מה כלול בדוח';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'גרסת האפליקציה, מערכת ההפעלה, נתיב התוכנה ללא שם המשתמש שלך, מודל זיהוי דיבור (וריאנט, מודל, מצב, שגיאה אחרונה), GPU, קבצי מודל ו-40 שורות היומן האחרונות. מפתחות וטוקנים מוסתרים בשורות היומן.';

  @override
  String get aboutDiagnosticsPreviewShow => 'הצג';

  @override
  String get aboutDiagnosticsPreviewHide => 'הסתר';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'האבחון לא הושלם: $error';
  }

  @override
  String get aboutCopyDebugInfo => 'העתק מידע דיבאג';

  @override
  String get aboutCopied => 'הועתק!';

  @override
  String get aboutMadeWith => 'נוצר ב♥ על ידי WhisPaste';

  @override
  String get aboutOpenSource => 'קוד פתוח תחת רישיון MIT';

  @override
  String get feedbackSubtitle => 'עזור לנו לשפר את WhisPaste. כל קול חשוב.';

  @override
  String get feedbackCategoryLabel => 'על מה זה?';

  @override
  String get feedbackRatingLabel => 'איך אתה מרגיש לגבי WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'ספר לנו יותר';

  @override
  String get feedbackContactEmailLabel => 'אימייל (אופציונלי)';

  @override
  String get feedbackContactEmailExplanation =>
      'רק אם תרצה שנחזור אליך. נשתמש בו אך ורק כדי להגיב למשוב הזה, לעולם לא לשיווק, והוא יימחק לאחר 90 יום.';

  @override
  String get feedbackContactEmailPlaceholder => 'you@example.com';

  @override
  String get feedbackContactEmailInvalid =>
      'נא להזין כתובת אימייל תקינה, או להשאיר ריק.';

  @override
  String get feedbackContactLanguageLabel => 'שפת המענה';

  @override
  String get feedbackContactLanguageHint => 'באיזו שפה נוכל לחזור אליך?';

  @override
  String get feedbackSubmit => 'שלח משוב';

  @override
  String feedbackSubmitMissing(String what) {
    return 'כדי לשלוח, $what.';
  }

  @override
  String get feedbackMissingCategory => 'בחרו במה מדובר';

  @override
  String get feedbackMissingRating => 'דרגו איך אתם מרגישים עם WhisPaste';

  @override
  String get feedbackMissingComment => 'כתבו הודעה';

  @override
  String get feedbackMissingEmail =>
      'תקנו את כתובת האימייל או השאירו את השדה ריק';

  @override
  String get feedbackRequiredMarker => 'חובה';

  @override
  String get feedbackPublishConsentLabel =>
      'אני מאשר/ת שהמשוב שלי יופיע באתר כציטוט בעילום שם.';

  @override
  String get feedbackPublishConsentExplanation =>
      'כבוי כברירת מחדל. מוצגים רק הטקסט והדירוג שלך, לעולם לא השם או הדואר האלקטרוני. אפשר לבטל את ההסכמה בכל עת בלחיצה אחת בעמוד המשוב באפליקציה.';

  @override
  String get feedbackPublishReviewHint =>
      'ציטוטים נכתבים כמו דירוג: מה שאהבת ומה עדיין אפשר לשפר. דיווחי תקלות ורעיונות שייכים ל«בעיה» או ל«רעיון» ולעולם לא מתפרסמים.';

  @override
  String get feedbackWithdrawConsentLabel => 'לבטל את ההסכמה';

  @override
  String get feedbackWithdrawConsentHelp =>
      'חל על משובים שנשלחו עם הסכמה מהמכשיר הזה. הציטוט יוסר מהאתר תוך כ-24 שעות.';

  @override
  String get feedbackWithdrawConsentPending =>
      'הביטול נשמר ויישלח כאשר WhisPaste פועל עם חיבור לאינטרנט (עד 30 יום); אחרת בטל באמצעות דוא״ל.';

  @override
  String get feedbackWithdrawNoCode =>
      'אין קוד ביטול שמור במכשיר הזה – בטל באמצעות דוא״ל';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'הביטול מ־$date נשלח…';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'הביטול מ־$date לא נמסר – בטל באמצעות דוא״ל';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'לא ניתן היה למסור את הביטול – בטל באמצעות דוא״ל.';

  @override
  String get feedbackWithdrawEmailLabel => 'ביטול בדוא״ל';

  @override
  String get feedbackWithdrawEmailSubject => 'ביטול ההסכמה לציטוט המשוב שלי';

  @override
  String get feedbackWithdrawEmailBody =>
      'נא לבטל את ההסכמה שלי לציטוט המשוב שלי.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'תאריך המשוב:';

  @override
  String get feedbackWithdrawEmailReferenceLabel => 'מזהה ביטול:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'שלחתי את הדוא״ל';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'לא נמצאה אפליקציית דוא״ל. שלח את ההודעה המוכנה לכתובת הזו:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'העתקת הכתובת וההודעה';

  @override
  String get feedbackWithdrawEmailCopied => 'הכתובת וההודעה הועתקו.';

  @override
  String get feedbackWithdrawLocked =>
      'לא ניתן לקרוא כרגע את מאגר האישורים של המערכת. WhisPaste אינו יכול לשלוח הסכמות וביטולים השמורים בו. בטל באמצעות דוא״ל; הדוא״ל המוכן כולל את המזהים הדרושים.';

  @override
  String get feedbackWithdrawConsentDone =>
      'הביטול נשלח. הציטוט יוסר מהאתר תוך כ-24 שעות, בעדכון היומי הבא.';

  @override
  String get feedbackPrivacyNote =>
      'אנונימי כברירת מחדל, ניתן לזיהוי רק אם תוסיף את האימייל שלך למעלה.';

  @override
  String get feedbackThankYou => 'תודה!';

  @override
  String get feedbackThankYouMessage =>
      'המשוב שלך עוזר לנו לשפר את WhisPaste\nלכולם.';

  @override
  String get feedbackSendAnother => 'שלח עוד אחד';

  @override
  String get feedbackRatingFrustrated => 'מתוסכל';

  @override
  String get feedbackRatingMeh => 'בסדר גמור';

  @override
  String get feedbackRatingOkay => 'סביר';

  @override
  String get feedbackRatingHappy => 'שמח';

  @override
  String get feedbackRatingLoveIt => 'אוהב מאוד!';

  @override
  String get feedbackSubmitting => 'שולח…';

  @override
  String get feedbackErrorRateLimited =>
      'כבר שלחת משוב לאחרונה. נסה שוב מאוחר יותר.';

  @override
  String get feedbackErrorNetwork => 'לא הצלחנו להתחבר. בדוק חיבור אינטרנט.';

  @override
  String get feedbackErrorServer => 'משהו השתבש. נסה שוב מאוחר יותר.';

  @override
  String get feedbackErrorNotConfigured => 'משוב אינו זמין בגרסה זו.';

  @override
  String get statusBarOnDevice => 'מקומי';

  @override
  String get statusBarOverlayFloating => 'שכבה: צפה';

  @override
  String get statusBarOverlayOff => 'שכבה: כבויה';

  @override
  String get statusBarAfterCopy => 'אחרי: העתק';

  @override
  String get statusBarAfterPaste => 'אחרי: הדבק';

  @override
  String get statusBarAfterBoth => 'אחרי: העתק + הדבק';

  @override
  String get statusBarAfterNothing => 'אחרי: ידני';

  @override
  String get dockOutputCopy => 'העתק';

  @override
  String get dockOutputPaste => 'הדבק';

  @override
  String get dockOutputBoth => 'העתק + הדבק';

  @override
  String get dockOutputNothing => 'ידני';

  @override
  String get sttStatusStarting => 'מתחיל…';

  @override
  String get sttStatusReady => 'מוכן';

  @override
  String get sttStatusError => 'שגיאה';

  @override
  String get statusBarSttTooltip => 'סטטוס מודל זיהוי הדיבור';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'הזיהוי פועל על: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'לא ניתן למדוד ניצול GPU אמיתי בין מערכות הפעלה ללא הרשאות מוגברות; האחוזים המוצגים משקפים במקום זאת את פעילות ה-CPU של התהליך.';

  @override
  String get statusBarRecording => 'מקליט…';

  @override
  String get statusBarTranscribing => 'מעבד…';

  @override
  String get statusBarRefining => 'מעבד…';

  @override
  String get statusBarHotkeyTooltip => 'קיצור גלובלי: לחץ להגדרה';

  @override
  String get statusBarAutoPasteOffHint => 'הפעלת הדבקה אוטומטית…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'הדבקה אוטומטית כבויה כעת. לחץ לפתיחת ההגדרות.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'הסתר';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'אוטומציה: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'אוטומציה: שגיאה';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'ממשק האוטומציה פעיל בפורט $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'ממשק האוטומציה פעיל בפורט $port (פורט $requestedPort היה תפוס)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'ממשק האוטומציה: לא נמצא פורט פנוי';

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
  String get shortcutKeySpace => 'רווח';

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
  String get modelServerReady => 'מודל זיהוי דיבור מוכן';

  @override
  String get modelServerMissing => 'מודל זיהוי דיבור לא מותקן';

  @override
  String get modelServerWhisper => 'מודל זיהוי דיבור מקומי';

  @override
  String get modelReady => 'מוכן';

  @override
  String get modelDownloadComplete => 'המודל מוכן לשימוש';

  @override
  String get modelUse => 'השתמש';

  @override
  String get modelDownload => 'הורד';

  @override
  String get modelDownloading => 'מוריד…';

  @override
  String get modelDownloadingEngine => 'מכין מודל זיהוי דיבור…';

  @override
  String get modelVerifying => 'מאמת…';

  @override
  String get modelExtracting => 'מחלץ…';

  @override
  String get modelDeleteConfirm => 'למחוק מודל זיהוי דיבור זה?';

  @override
  String get modelDeleteConfirmMessage =>
      'קובץ המודל נמחק ממכשיר זה. תוכל להוריד אותו שוב בכל עת.';

  @override
  String get modelTierDeleteConfirm => 'למחוק את המודלים האלה?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count מודלים ($size) יימחקו מהמכשיר הזה. אפשר להוריד אותם שוב בכל עת.',
      one: 'מודל אחד ($size) יימחק מהמכשיר הזה. אפשר להוריד אותו שוב בכל עת.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'מהיר';

  @override
  String get qualityTierCompactDesc =>
      'תוצאות מהירות, הורדה קטנה. מעולה להערות קצרות.';

  @override
  String get qualityTierBalancedLabel => 'מאוזן';

  @override
  String get qualityTierBalancedDesc => 'מדויק ואמין להקלטה יומיומית.';

  @override
  String get qualityTierPremiumLabel => 'מדויק';

  @override
  String get qualityTierPremiumDesc => 'דיוק גבוה להקלטות ארוכות ותוכן מורכב.';

  @override
  String get qualityTierRecommended => 'מומלץ למכשיר שלך';

  @override
  String get qualityTierRecommendedMeasured => 'נמדד למכשיר שלך';

  @override
  String qualityTierDownloadSize(String size) {
    return 'הורדה $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'הורד מודל זיהוי דיבור';

  @override
  String get qualityTierChooseDifferent => 'בחר רמה אחרת';

  @override
  String get qualityTierActive => 'פעיל';

  @override
  String get qualityTierInfoSlow =>
      'מדויק, לוקח הרבה יותר זמן בעיבוד במחשב הזה';

  @override
  String get qualityTierInfoSlowEstimate =>
      'מדויק, כנראה לוקח הרבה יותר זמן במחשב הזה (הערכה)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'מדויק, איטי פי $ratio ממהיר';
  }

  @override
  String get qualityTierInfoModerate => 'איזון טוב בין מהירות לאיכות';

  @override
  String get qualityTierBenchmarkReRun => 'הרץ בדיקה מחדש';

  @override
  String get qualityTierBenchmarkRun => 'הרץ בדיקת ביצועים';

  @override
  String get qualityTierInfoBenchmarking => 'בודק ביצועים…';

  @override
  String get benchmarkRowSubtitle =>
      'מודד באיזו מהירות רץ כל רמה מותקנת במחשב הזה. התוצאות קובעות את הרמזים למהירות ואת ההמלצה.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'פועל… שלב $step מתוך $total: $tier';
  }

  @override
  String get benchmarkCancel => 'בטל בדיקה';

  @override
  String get benchmarkCancelled => 'הבדיקה בוטלה. הרמות שנמדדו עד כה נשמרו.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נמדדו $count רמות',
      one: 'נמדדה רמה אחת',
    );
    return 'המדידה הושלמה: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'נמדד לאחרונה: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'אופן החישוב: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'מעבד (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'כרטיס מסך ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds שנ׳ עיבוד לכל שנייה של אודיו';
  }

  @override
  String get benchmarkNoResult =>
      'עדיין אין מדידה. הפעל את הבדיקה כדי לקבל רמזים למהירות במחשב הזה.';

  @override
  String get benchmarkStaleNotice =>
      'התוצאות הללו הגיעו ממחשב אחר או מגרסה קודמת. הן ימדדו מחדש ברקע.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'המדידה חלה על מודלי Whisper. Parakeet אינו נמדד.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'מומלץ לאחר המדידה: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'עבור אל $tier';
  }

  @override
  String get benchmarkErrorBusy =>
      'לא ניתן להריץ את הבדיקה במהלך הקלטה. הפעל אותה שוב אחר כך.';

  @override
  String get benchmarkErrorNoModel =>
      'לא מותקנת אף רמה. הורד קודם מודל זיהוי דיבור.';

  @override
  String get benchmarkErrorFailed => 'לא ניתן היה להשלים את הבדיקה.';

  @override
  String get benchmarkRetry => 'נסה שוב';

  @override
  String get qualityTierActionOverride => 'השתמש בכל זאת';

  @override
  String get qualityTierActionOverrideHint => 'להשתמש ברמה זו למרות האזהרה';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'בסיסי';

  @override
  String get settingsQualityBalanced => 'מאוזן';

  @override
  String get settingsQualityHigh => 'איכות גבוהה';

  @override
  String get settingsQualityBest => 'מדויק';

  @override
  String get settingsQualityMaximum => 'דיוק מקסימלי';

  @override
  String get settingsQualityRecommended => '★ מומלץ';

  @override
  String get settingsModelStatusReady => 'מודל מוכן';

  @override
  String get settingsModelStatusNeeded => 'המודל יורד כשתתחיל להקליט';

  @override
  String get settingsModelStatusDownloading => 'מוריד מודל…';

  @override
  String get settingsAdvancedModelManagement =>
      'ניהול מתקדם של מודלי זיהוי דיבור';

  @override
  String get infoEngineDownloading => 'מודל זיהוי הדיבור בהכנה. המתן רגע.';

  @override
  String get infoModelMissing => 'הורד קודם מודל דיבור בהגדרות.';

  @override
  String infoModelMissingSelected(String size) {
    return 'מודל הדיבור שנבחר ($size) עדיין לא הורד.';
  }

  @override
  String get infoModelMissingDownload => 'הורד עכשיו';

  @override
  String get statusBarModelMissing => 'מודל זיהוי הדיבור חסר';

  @override
  String statusBarModelDownloading(int percent) {
    return 'מוריד מודל זיהוי דיבור… $percent%';
  }

  @override
  String get modelDownloadAction => 'הורד';

  @override
  String get modelMissingDownloadAction => 'חסר — הורד';

  @override
  String get infoPipelineBusy => 'WhisPaste עדיין עסוק בהקלטה הקודמת.';

  @override
  String get infoSnippetPickerEmpty =>
      'אין לך עדיין קטעים. צור קטע, ואז ייפתח הבורר.';

  @override
  String get infoSnippetPickerEmptyAction => 'פתח קטעים';

  @override
  String get oomRecoveryTitle => 'ההקלטה הופסקה: לכרטיס המסך אין מספיק זיכרון';

  @override
  String get oomRecoveryMessage => 'ה-GPU נגמר לו הזיכרון. בחר כיצד להמשיך:';

  @override
  String get oomRecoveryTrySmaller => 'נסה מודל קטן יותר';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'עבור ל-$model ונסה שוב';
  }

  @override
  String get oomRecoverySwitchCloud => 'עבור לענן';

  @override
  String get oomRecoverySwitchCloudHint => 'השתמש במודל זיהוי דיבור בענן';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'ההקלטות ישלחו אז ל-$provider.';
  }

  @override
  String get oomRecoveryCancel => 'בטל';

  @override
  String get oomRecoveryPermanentTitle => 'מודל זיהוי דיבור מקומי לא זמין';

  @override
  String get oomRecoveryPermanentMessage =>
      'כל המודלים המקומיים נכשלו בגלל הגבלת זיכרון GPU. עבור לענן בהגדרות.';

  @override
  String get oomRecoveryPermanentCloud => 'פתח הגדרות';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'עובר ל-$model…';
  }

  @override
  String get oomRecoverySwitchingCloud => 'עובר למודל זיהוי דיבור בענן…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'מודל $model גם נכשל. מנסה את הבא…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'אין מודל קטן יותר זמין. בחר מודל אחר בהגדרות או השתמש בזיהוי דיבור בענן.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'איכות הופחתה: ה-GPU נגמר לו הזיכרון. עברתי למודל קל יותר.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'ה-GPU נגמר לו הזיכרון. עברתי למצב CPU.';

  @override
  String get errorSttServerConnectionLost =>
      'מודל זיהוי הדיבור נעצר באופן בלתי צפוי. נסה שוב.';

  @override
  String get errorSttCudaOom => 'ה-GPU נגמר לו הזיכרון. האיכות הופחתה.';

  @override
  String get errorCloudAuth =>
      'מפתח ה-API חסר או שגוי. בדוק אותו בהגדרות ← זיהוי דיבור.';

  @override
  String get errorCloudQuota =>
      'הגעת למגבלת הקצב של ספק הענן. המתן רגע ונסה שוב.';

  @override
  String get errorCloudTimeoutLocal =>
      'שירות הענן לא הגיב בזמן. בדוק את החיבור שלך, או הכתב ללא חיבור עם המודל המקומי.';

  @override
  String get errorCloudTimeout =>
      'שירות הענן לא הגיב בזמן. בדוק את החיבור שלך ונסה שוב.';

  @override
  String get errorCloudNetworkLocal =>
      'לא ניתן להתחבר לשירות הענן. בדוק את חיבור האינטרנט שלך, או הכתב ללא חיבור עם המודל המקומי.';

  @override
  String get errorCloudNetwork =>
      'לא ניתן להתחבר לשירות הענן. בדוק את חיבור האינטרנט שלך ונסה שוב.';

  @override
  String get errorQuickNoteAppendFailed =>
      'לא ניתן היה לשמור את ההערה המהירה, ולכן הטקסט לא נוסף אליה. העתק את הטקסט והדבק אותו בהערה.';

  @override
  String get errorOnboardingNotCompleted => 'סיים קודם את אשף ההתקנה.';

  @override
  String get errorSttModelNotFound => 'מודל דיבור לא נמצא. הורד אותו בהגדרות.';

  @override
  String get errorSttModelLoadFailed =>
      'לא ניתן לטעון את מודל הדיבור. הפעל מחדש את WhisPaste. אם הבעיה נמשכת, הורד שוב את מודל הדיבור בהגדרות.';

  @override
  String get errorSttModelFileMissing =>
      'קובץ מודל הדיבור חסר. הורד את מודל הדיבור בהגדרות.';

  @override
  String get errorSttModelCorrupted =>
      'קובץ מודל הדיבור פגום. הורד מחדש את מודל הדיבור בהגדרות.';

  @override
  String get errorSttEngineRestartNeeded =>
      'מנוע הדיבור עדיין עסוק בהכתבה קודמת. הפעל מחדש את WhisPaste כדי להשתמש בו שוב.';

  @override
  String get pendingRetryFailed =>
      'התמלול החוזר נכשל. ההקלטה נשמרת לניסיון נוסף.';

  @override
  String get errorSttModelUnknown =>
      'מודל דיבור לא ידוע. בחר מודל תקין בהגדרות.';

  @override
  String get errorRecordingFailed => 'לא הצלחתי להתחיל הקלטה, נסה שוב';

  @override
  String get errorNoAudioRecorded => 'לא הוקלט אודיו, נסה שוב';

  @override
  String get errorTranscriptionEmpty => 'התמלול חזר ריק, נסה שוב';

  @override
  String get errorSttServerFailed => 'מודל זיהוי הדיבור לא הצליח להתחיל';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'מודל הדיבור נראה פגום. מוריד עותק חדש אוטומטית.';

  @override
  String get errorSttDllMissing => 'רכיב מערכת נדרש חסר. מנסה מחדש עם מצב CPU.';

  @override
  String get errorSttGpuFatal => 'האצת GPU נכשלה. מנסה מחדש עם מצב CPU.';

  @override
  String get errorSttHeapCorruption =>
      'אירעה שגיאת זיכרון. מנסה מחדש עם מצב CPU.';

  @override
  String get errorSttCpuFallbackFailed =>
      'מודל זיהוי הדיבור נכשל הן ב-GPU והן ב-CPU. הפעל מחדש את האפליקציה או הורד מחדש את המודל.';

  @override
  String get errorPipelineTimeout =>
      'ההקלטה נמשכה יותר מדי. נסה הקלטה קצרה יותר.';

  @override
  String get errorWavFileNotCreated => 'לא הצלחתי לשמור קובץ אודיו. נסה שוב.';

  @override
  String get errorWavFileEmpty => 'לא נלכד אודיו. בדוק את המיקרופון.';

  @override
  String get errorSttStartTimeout =>
      'מודל זיהוי הדיבור עדיין מתחיל. נסה שוב בעוד רגע.';

  @override
  String get errorTranscriptionTimeout =>
      'התמלול לקח יותר מדי זמן. נסה הקלטה קצרה יותר.';

  @override
  String get errorMicPermissionDenied =>
      'נדרש גישה למיקרופון. אפשר בהגדרות המערכת.';

  @override
  String get errorRecordingStartFailed => 'לא הצלחתי להתחיל הקלטה. נסה שוב.';

  @override
  String get errorNoMicrophone => 'לא נמצא מיקרופון. חבר מיקרופון ונסה שוב.';

  @override
  String get errorGeneric => 'משהו השתבש. נסה שוב.';

  @override
  String get modelDownloadFailed => 'הורדה נכשלה. בדוק חיבור אינטרנט.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'אין מספיק מקום פנוי בדיסק להורדה: נדרשים $needed, פנויים $free. ההורדה לא התחילה.';
  }

  @override
  String get modelDeleteInUse =>
      'קובץ המודל בשימוש על ידי תוכנה אחרת ולא ניתן היה למחוק אותו. סגור אותה ונסה שוב.';

  @override
  String get statusSttLoading => 'טוען מודל זיהוי דיבור…';

  @override
  String get statusSttReady => 'מודל זיהוי דיבור מוכן';

  @override
  String get modelDownloadFailedChecksum =>
      'הקובץ שהורד היה פגום ונמחק. יש להוריד אותו שוב.';

  @override
  String get modelDownloadFailedStorage =>
      'לא ניתן היה לשמור את הקובץ. יש לוודא שיש מספיק מקום פנוי בדיסק.';

  @override
  String get modelDownloadFailedUnknown => 'ההורדה נכשלה. יש לנסות שוב.';

  @override
  String get onboardingModelDownloadCancel => 'ביטול ההורדה';

  @override
  String get onboardingModelDiskSpaceTitle => 'מעט מקום פנוי בדיסק';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'המודל צריך $needed, אבל פנויים רק $free. סביר שההורדה תיכשל.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'להוריד בכל זאת';

  @override
  String get historyDuplicate => 'שכפל';

  @override
  String get historyDuplicated => 'רשומה שוכפלה';

  @override
  String get historyTakeAsNote => 'העבר להערה';

  @override
  String get historyTakenAsNote => 'הועבר להערה';

  @override
  String get historyOpenNote => 'פתח';

  @override
  String get historyViewRaw => 'מקורי';

  @override
  String get historyViewEdited => 'ערוך';

  @override
  String get historyApplySmartModePreset => 'החל תבנית Smart Mode';

  @override
  String get historySmartModeApplied => 'Smart Mode הוחל';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode הוחל';

  @override
  String get smartModeUndoAction => 'בטל';

  @override
  String get smartModeBusy => 'Smart Mode עדיין פועל';

  @override
  String get smartModeBusyRetry => 'Smart Mode עדיין פועל – נסו שוב בעוד רגע';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count שמות שונו',
      one: 'שם אחד שונה',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'המקור הועתק ללוח – הדביקו עם $shortcut. התוכן הקודם של הלוח הוחלף.';
  }

  @override
  String get selectionUndoUnavailable => 'ביטול אינו אפשרי כרגע.';

  @override
  String get smartModeCheckTimedOut =>
      'הבדיקה נמשכה יותר מדי זמן – הטקסט שלך נשאר ללא שינוי.';

  @override
  String get historySmartModeUndo => 'בטל Smart Mode';

  @override
  String get historySmartModeRestore => 'שחזר Smart Mode';

  @override
  String get historySmartModeFailedModelMissing => 'מודל טקסט לא הורד';

  @override
  String get historySmartModeFailedTimeout => 'Smart Mode ארך זמן רב מדי';

  @override
  String get historySmartModeFailedGeneric => 'Smart Mode נכשל — נסה שוב';

  @override
  String get historySmartModeSelectTargetLanguage => 'בחר שפת יעד';

  @override
  String get historyAddNote => 'הוסף הערה';

  @override
  String get historyEditNote => 'ערוך הערה';

  @override
  String get historyNotes => 'הערות';

  @override
  String get historyNotePlaceholder => 'כתוב הערה…';

  @override
  String get historyVoiceNoteHint =>
      'טיפ: אמור \"tag: שם\" או \"correct: טקסט\" בזמן ההקלטה.';

  @override
  String get historyNoteAdded => 'הערה נוספה';

  @override
  String get historyNoteDeleted => 'הערה נמחקה';

  @override
  String get historyCopiedAsMarkdown => 'הועתק כ-Markdown';

  @override
  String get historyAddTag => 'הוסף תגית…';

  @override
  String get historySearchTags => 'חפש או צור…';

  @override
  String get historyNoteEdited => 'נערך';

  @override
  String get historyTagAdded => 'תגית נוספה';

  @override
  String get historyTagRemoved => 'תגית הוסרה';

  @override
  String historyCreateTag(Object tag) {
    return 'צור \"$tag\"';
  }

  @override
  String get historyManageTags => 'נהל תגיות';

  @override
  String get tagManageTitle => 'ניהול תגיות';

  @override
  String get tagManageEmpty =>
      'עדיין אין תגיות. תגית נוצרת כשמוסיפים אותה לפריט הקלטה.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count רשומות',
      one: 'רשומה אחת',
      zero: 'לא בשימוש',
    );
    return '$_temp0';
  }

  @override
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'עוד $count תגיות',
      one: 'תגית נוספת אחת',
    );
    return '$_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => 'למחוק תגית?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count רשומות',
      one: 'רשומה אחת',
    );
    return 'התגית \"$name\" משמשת ב-$_temp0. היא תוסר מכולן.';
  }

  @override
  String tagDeleted(String name) {
    return 'תגית \"$name\" נמחקה';
  }

  @override
  String tagRemoveSemanticsLabel(String tag) {
    return 'הסרת התג \"$tag\"';
  }

  @override
  String get tagDeleteUnusedTitle => 'למחוק תגיות שאינן בשימוש?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תגיות',
      one: 'תגית אחת',
    );
    return '$_temp0 שאינן בשימוש יימחקו לצמיתות.';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return 'מחק $count שאינן בשימוש';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תגיות',
      one: 'תגית אחת',
    );
    return '$_temp0 נמחקו';
  }

  @override
  String get historyEditTranscript => 'ערוך תמלול';

  @override
  String get historyTranscriptSaved => 'תמלול נשמר';

  @override
  String get historySaveTranscript => 'שמור';

  @override
  String get historyShortcutHelp => 'קיצורי מקלדת';

  @override
  String get historyShortcutGeneral => 'כללי';

  @override
  String get historyShortcutTags => 'התמקד בשדה תגיות';

  @override
  String get historyShortcutNotes => 'הוסף הערה';

  @override
  String get historyShortcutPin => 'מועדף / הסר מועדף';

  @override
  String get historyShortcutClose => 'שמור וסגור';

  @override
  String get historyShortcutListGroup => 'רשימת ההקלטות';

  @override
  String get historyShortcutMoveFocus => 'בחירת פריט';

  @override
  String get historyShortcutOpenEntry => 'פתיחת פריט';

  @override
  String get historyShortcutCopyEntry => 'העתקת פריט';

  @override
  String get historyShortcutDeleteEntry => 'מחיקת פריט';

  @override
  String get historyShortcutSelectAll => 'בחירת הכול';

  @override
  String get historyShortcutClearSelection => 'ביטול הבחירה';

  @override
  String get historyShortcutEditing => 'עריכה';

  @override
  String get historyShortcutToggleEdit => 'החלף מצב עריכה';

  @override
  String get historyShortcutSave => 'שמור תמלול';

  @override
  String get historyShortcutBold => 'מודגש';

  @override
  String get historyShortcutItalic => 'נטוי';

  @override
  String get historyShortcutCopy => 'העתק ללוח';

  @override
  String get historyShortcutEditTitle => 'ערוך כותרת';

  @override
  String get historyShortcutDiscardEdit => 'ביטול העריכה';

  @override
  String get historyEditTitle => 'ערוך כותרת';

  @override
  String get historyTitlePlaceholder => 'הזן כותרת…';

  @override
  String get historyTitleSaved => 'כותרת נשמרה';

  @override
  String get historySearchHelpTitle => 'טיפים לחיפוש';

  @override
  String get historySearchHelpTags => 'הקלד # כדי לסנן לפי תגיות';

  @override
  String get historySearchHelpLang => 'הקלד lang: כדי לסנן לפי שפה';

  @override
  String get historySearchHelpFreeText => 'או פשוט הקלד מילת מפתח';

  @override
  String get historySearchQuickTags => 'תגיות פופולריות';

  @override
  String get historyRecentSearches => 'חיפושים אחרונים';

  @override
  String get historyRemoveRecentSearch => 'הסר חיפוש אחרון';

  @override
  String get historyRemoveFilter => 'הסר מסנן';

  @override
  String get historyQuickActions => 'מסננים מהירים';

  @override
  String get historyQuickActionAllLangs => 'כל השפות';

  @override
  String get historyQuickActionFavorites => 'מועדפים בלבד';

  @override
  String get historySortNewest => 'חדש ביותר';

  @override
  String get historySortOldest => 'ישן ביותר';

  @override
  String get historySortLongest => 'ארוך ביותר';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'סנן לפי תגית';

  @override
  String get historySearchSuggestLang => 'סנן לפי שפה';

  @override
  String get settingsKeyboardShortcut => 'קיצור';

  @override
  String get shortcutsGroupDictate => 'הכתבה';

  @override
  String get shortcutsGroupNotes => 'פתקים וקטעים';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode ועריכת הבחירה';

  @override
  String get shortcutsAreaIntro =>
      'המקשים האלה פועלים במערכת כולה: בכמעט כל אפליקציה, גם כש-WhisPaste רץ ברקע. כל שילוב שייך למקש אחד בלבד.';

  @override
  String get settingsKeyboardShortcutSubtitle => 'קיצור להתחלת ועצירת הקלטה';

  @override
  String get settingsHotkeyEnabled => 'התחלת/עצירת הקלטה';

  @override
  String get settingsCurrentHotkey => 'קיצור נוכחי';

  @override
  String get settingsChangeHotkey => 'שנה';

  @override
  String get settingsHotkeyRecorderTitle => 'הקלט קיצור חדש';

  @override
  String get settingsHotkeyRecorderHint =>
      'לחץ על שילוב המקשים שברצונך להשתמש…';

  @override
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'כל שילוב מקשי Modifier אפשרי: למשל $first, $second, או $third';
  }

  @override
  String get settingsHotkeyRecorderCancel => 'בטל';

  @override
  String get settingsHotkeyRecorderSave => 'שמור';

  @override
  String get settingsHotkeyRecorderClear => 'נקה';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'לא ניתן לשמור מקש זה כקיצור דרך. נסה אות, ספרה, מקש פונקציה (F1-F12) או מקש חץ.';

  @override
  String get settingsHotkeyActionRecording => 'התחלת/עצירת הקלטה';

  @override
  String get settingsHotkeyActionQuickNote => 'פתק מהיר';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'הקלטה לפתק מהיר';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'הטקסט המוכתב מתווסף לפתק המסומן כפתק מהיר. את הפתק הזה בוחרים באזור \"פתקים\".';

  @override
  String get settingsQuickNoteOpenInMainWindow => 'פתיחת הערות בחלון הראשי';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'כבוי: הערה מהירה נשמרת ברקע, והודעה מציעה „פתח הערה“. מופעל: החלון הראשי עולה לפני השטח ומציג את ההערה.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'קיצור נוכחי';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'הצירוף הזה כבר משמש עבור \"$action\". בחר צירוף אחר.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'הצירוף הזה כבר משמש עבור \"$action\". בחר צירוף אחר.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'לא ניתן היה לרשום את הצירוף הזה — הקיצור לפתק מהיר אינו פעיל כרגע. בחר צירוף אחר.';

  @override
  String get quickNoteToastSaved => 'ההערה המהירה נשמרה';

  @override
  String get quickNoteToastOpenNote => 'פתח הערה';

  @override
  String get settingsHotkeyActionSnippetPicker => 'בוחר הקטעים';

  @override
  String get settingsSnippetPickerHotkeyEnabled => 'פתיחת בוחר הקטעים';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'פותח את בוחר הקטעים מיד — בלי הקלטה ובלי מילת ההפעלה המדוברת.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'קיצור נוכחי';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'הצירוף הזה כבר משמש עבור \"$action\". בחר צירוף אחר.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'לא ניתן היה לרשום את הצירוף הזה — הקיצור לבוחר הקטעים אינו פעיל כרגע. בחר צירוף אחר.';

  @override
  String get settingsMaxRecordDuration => 'משך הקלטה מקסימלי';

  @override
  String get settingsMaxRecordDurationSubtitle => 'עצירה אוטומטית אחרי זמן זה';

  @override
  String get settingsMaxRecordDurationUnlimited => 'ללא הגבלה';

  @override
  String get settingsCloseToTray => 'סגור למגש';

  @override
  String get settingsCloseToTraySubtitle =>
      'המשך לפעול במגש המערכת כשסוגרים את החלון';

  @override
  String get settingsSidePanelEnabled => 'סרגל הדבקה מהירה';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'סרגל שנפתח בהצבעה על קצה המסך שנבחר, לתמלולים, קטעים והיסטוריית לוח הגזירים';

  @override
  String get settingsSidePanelEdge => 'מיקום הסרגל';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'לאיזה קצה מסך הסרגל מעוגן ומתוכו הוא נגלל';

  @override
  String get settingsSidePanelEdgeLeft => 'קצה שמאלי';

  @override
  String get settingsSidePanelEdgeRight => 'קצה ימני';

  @override
  String get settingsAppearance => 'מראה';

  @override
  String get settingsAppearanceSubtitle =>
      'צבעי חלונות האפליקציה. סרגל ההקלטה והשכבה הצפה נשארים כהים.';

  @override
  String get settingsAppearanceSystem => 'לפי המערכת';

  @override
  String get settingsAppearanceLight => 'בהיר';

  @override
  String get settingsAppearanceDark => 'כהה';

  @override
  String get settingsAppearanceNavy => 'כחול ים';

  @override
  String get settingsAppearanceCardNavy => 'כחול ים';

  @override
  String get settingsLanguageDialogSubtitle =>
      'בחר את השפה ש-WhisPaste מצפה לה בזמן ההקלטה. כשהזיהוי האוטומטי פעיל, היא מזהה את השפה בעצמה.';

  @override
  String get settingsLanguageSearchHint => 'חיפוש שפות';

  @override
  String get settingsLanguageSelectedTitle => 'נבחר';

  @override
  String get settingsLanguageSaveAndClose => 'שמירה וסגירה';

  @override
  String get settingsLanguageSavePickOne => 'בחר לפחות שפה אחת כדי לשמור.';

  @override
  String get settingsLanguageNoResults => 'לא נמצאה שפה';

  @override
  String get settingsLanguageChange => 'שינוי';

  @override
  String get settingsLanguageCancel => 'ביטול';

  @override
  String get settingsErrorReporting => 'דיווח שגיאות';

  @override
  String get settingsErrorReportingSubtitle =>
      'שולח דיווחים על קריסות ושגיאות, עם מזהה מכשיר אנונימי. לעולם לא את האודיו או הטקסט שלך.';

  @override
  String get settingsErrorReportingRestartHint =>
      'ייכנס לתוקף לאחר הפעלה מחדש של WhisPaste.';

  @override
  String get settingsAutoPasteBlocklist => 'רשימת חסימה להדבקה אוטומטית';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'אפליקציות שבהן הטקסט רק מועתק (ללא הדבקה אוטומטית). כשהמתג שלמטה פעיל, הטקסט נכנס ללוח ההעתקה; כשהוא כבוי, רק להקלטות. בזמן שהרשימה מוגדרת, אפליקציה שלא זוהתה נחשבת חסומה.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'להעתיק ללוח ההעתקה באפליקציות חסומות';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'כבוי: הטקסט נשמר רק בהקלטות.';

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
      'ב-Mac יש להזין מזהי חבילה, למשל com.apple.Terminal. רשומה ללא נקודה תואמת רק מזהה זהה.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'ב-GNOME (Wayland), WhisPaste מזהה את אפליקציית היעד רק עם תוסף WhisPaste ל-GNOME; בלעדיו, כשרשימת חסימה פעילה, הטקסט רק מועתק';

  @override
  String get settingsLinuxAlwaysShiftPaste => 'תמיד להדביק עם Ctrl+Shift+V';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'קיצור הדרך של מסופים, גם בכל שאר האפליקציות. יש אפליקציות שמשתמשות במקשים האלה לדבר אחר; LibreOffice, למשל, פותח את \"הדבקה מיוחדת\"';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'כאן WhisPaste מזהה את אפליקציית היעד ומדביק במסופים עם Ctrl+Shift+V בעצמו';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'ב-GNOME (Wayland), WhisPaste מזהה מסופים רק עם תוסף WhisPaste ל-GNOME. עד אז, הפעל אם אתה מכתיב בעיקר למסופים';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'בשולחן העבודה הזה WhisPaste אינו מזהה מסופים. הפעל אם אתה מכתיב בעיקר למסופים';

  @override
  String get settingsLinuxPortalInputTitle => 'הדבקה דרך הרשאת שולחן העבודה';

  @override
  String get settingsLinuxPortalInputBody =>
      'עובד בלי הגדרה: שולחן העבודה שואל פעם אחת אם WhisPaste רשאי לשלוח קיצורי מקשים. WhisPaste שולח כך רק Ctrl+V ו-Ctrl+C';

  @override
  String get settingsLinuxPortalInputConnect => 'בקש הרשאה';

  @override
  String get settingsLinuxPortalInputRevoke => 'בטל הרשאה';

  @override
  String get settingsLinuxPortalInputConnected =>
      'ההרשאה ניתנה. WhisPaste יכול עכשיו להדביק בדרך זו';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'לא ניתנה הרשאה. אפשר לבקש שוב בכל עת';

  @override
  String get settingsLinuxPortalInputFailed =>
      'בקשת ההרשאה לא הצליחה. נסה שוב מאוחר יותר';

  @override
  String get settingsLinuxGnomeExtensionTitle => 'תוסף WhisPaste ל-GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'ב-GNOME, WhisPaste יודע איזו אפליקציה פעילה רק עם התוסף הזה, למשל עבור מסופים ורשימת החסימה. הוא קורא רק את שם האפליקציה, לעולם לא כותרות חלונות או תוכן';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'הפעל את התוסף';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'כבה את התוסף';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'התוסף אינו מותקן כאן. המדריך מסביר איך להתקין אותו';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'הופעל. אם WhisPaste עדיין לא מזהה את האפליקציה, התנתק והתחבר מחדש פעם אחת';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'ההפעלה לא הצליחה. במסוף: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'ב־Wayland, WhisPaste אינו רואה את האפליקציה הפעילה. כל עוד יש אפליקציות חסומות, הטקסט רק מועתק ולא מודבק.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'תחת Wayland, WhisPaste אינו יכול לבדוק אם החלפת חלון במהלך העיבוד: הטקסט נכנס לחלון שפעיל בזמן ההדבקה';

  @override
  String get settingsPasteBlocklistAdd => 'הוספת אפליקציה';

  @override
  String get settingsPasteBlocklistEmpty =>
      'אין אפליקציה חסומה – ההדבקה האוטומטית פועלת בכמעט כל מקום.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'הסרה מרשימת החסימה: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle =>
      'הוספת אפליקציה לרשימת החסימה';

  @override
  String get settingsPasteBlocklistRecentHeading => 'הוכתב לאחרונה ב־';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'עדיין אין הכתבות עם אפליקציה שזוהתה. הזינו למטה את מזהה האפליקציה.';

  @override
  String get settingsPasteBlocklistManualHeading => 'הזנת מזהה ידנית';

  @override
  String get settingsPasteBlocklistManualAdd => 'הוספה';

  @override
  String get historyAutoPasteOffForApp =>
      'כיבוי ההדבקה האוטומטית באפליקציה הזו';

  @override
  String get settingsPasteClipboardAfter => 'לוח ההעתקה אחרי ההדבקה';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'האם התוכן שהיה בלוח ההעתקה לפני ההדבקה יחזור אחריה. אם לא ניתן לאשר את ההדבקה בזמן, התמלול יישאר תמיד בלוח ההעתקה.';

  @override
  String get settingsPasteClipboardAfterKeep => 'להשאיר את התמלול';

  @override
  String get settingsPasteClipboardAfterRestore => 'להחזיר את מה שהעתקת';

  @override
  String get pasteClipboardUnsavedHint =>
      'לא ניתן היה לשמור את תוכן לוח ההעתקה הקודם – macOS סירב לגישה. אפשר בהגדרות המערכת → פרטיות ואבטחה.';

  @override
  String get pasteClipboardUnsavedAction => 'פתיחת הגדרות המערכת';

  @override
  String get settingsCheckUpdates => 'בדוק עדכונים';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'בדוק גרסאות חדשות בהפעלה וכל 24 שעות';

  @override
  String get settingsCheckForUpdatesNow => 'בדוק עדכונים עכשיו';

  @override
  String get settingsUpdates => 'עדכונים';

  @override
  String get settingsUpdatesSubtitle => 'ערוץ גרסאות ובדיקת עדכונים';

  @override
  String get settingsBetaUpdates => 'עדכוני בטא';

  @override
  String get settingsBetaUpdatesSubtitle => 'קבל גרסאות טרום-הפצה שנבדקו פחות.';

  @override
  String get settingsStableRevertHintMessage =>
      'לא ניתן לחזור אוטומטית לגרסה היציבה. כבר מותקנת אצלך גרסת בטא חדשה יותר.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'הורדה ידנית של הגרסה היציבה $stableVersion';
  }

  @override
  String get onboardingNext => 'הבא';

  @override
  String get onboardingBack => 'חזור';

  @override
  String get onboardingPrivacyTitle => 'עזור לנו לשפר את WhisPaste';

  @override
  String get onboardingPrivacyHint =>
      'האודיו והטקסט נשארים מקומיים. נתוני שימוש אנונימיים נשלחים לשרת באירוח עצמי באיחוד האירופי, ודיווחי קריסה לשירות באיחוד האירופי (Sentry) — בהתאם ל-GDPR.';

  @override
  String get onboardingPrivacyToggle => 'שיתוף נתוני שימוש אנונימיים';

  @override
  String get onboardingPrivacyToggleHint =>
      'פעיל כברירת מחדל, ניתן לכבות בכל עת';

  @override
  String get onboardingPrivacyCrashToggle => 'שליחת דיווחי קריסה אנונימיים';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'עוזר לתקן באגים, פעיל כברירת מחדל, ניתן לכבות בכל עת';

  @override
  String onboardingStepOf(int current, int total) {
    return 'שלב $current מתוך $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'מראה';

  @override
  String get onboardingAppearancePageSubtitle =>
      'איך האפליקציה מופעלת, ואיך נראית שכבת ההקלטה.';

  @override
  String get onboardingBeat1Title => 'לחץ על הקיצור, דבר, סיימת';

  @override
  String get onboardingBeat1Caption =>
      'ההקלטה מתחילה מיד – המילים שלך הופכות לטקסט ישירות במיקום הסמן.';

  @override
  String get onboardingBeat2Title => 'פועל מקומית, על החומרה שלך';

  @override
  String get onboardingBeat2Caption =>
      'כברירת מחדל, זיהוי הדיבור פועל במכשיר שלך – וההקלטות נשארות בו.';

  @override
  String get onboardingBeat3Title => 'בכל מקום שבו אתה מקליד';

  @override
  String get onboardingBeat3Caption =>
      'דפדפן, אימייל, עורך – WhisPaste עובד בכל המערכת.';

  @override
  String get onboardingMicChipReady => 'המיקרופון מוכן';

  @override
  String get onboardingMicChipPending => 'גישה למיקרופון ממתינה';

  @override
  String get onboardingMicChipAction => 'מיקרופון: נדרשת פעולה';

  @override
  String get onboardingModelTitle => 'הגדר מודל זיהוי דיבור';

  @override
  String get onboardingModelSubtitle =>
      'הורד את מנוע הדיבור כדי להקליט offline. עם זיהוי מקומי, הקול שלך נשאר במכשיר.';

  @override
  String get onboardingModelRecommended => 'מומלץ';

  @override
  String get onboardingModelChangeLater =>
      'תוכל לשנות את האיכות מאוחר יותר בהגדרות';

  @override
  String get onboardingModelNextBlocked =>
      'הורד מודל זיהוי דיבור, או השתמש בספק ענן עם מפתח API שמור, כדי להמשיך.';

  @override
  String get onboardingModelDownloading => 'מוריד…';

  @override
  String get onboardingModelReady => 'מודל זיהוי דיבור מוכן';

  @override
  String get onboardingModelGpuCpuFallback =>
      'האצת GPU מיטבית אינה זמינה, האפליקציה תשתמש במעבד';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'הדרך המהירה ביותר לטקסט בכ-25 שפות אירופיות, כולל גרמנית. פועל היטב בכל חומרה, גם ללא GPU.';

  @override
  String get onboardingModelDetectingHardware =>
      'בודקים את החומרה שלך כדי להמליץ על האפשרות המתאימה…';

  @override
  String onboardingModelUseCloud(String provider) {
    return 'שימוש ב-$provider';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'כבר שמור מפתח API עבור $provider. אפשר להשתמש בו במקום מודל זיהוי דיבור מקומי.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'זיהוי הדיבור פועל דרך $provider. אין צורך במודל זיהוי דיבור מקומי.';
  }

  @override
  String get onboardingModelUseLocal => 'שימוש במודל זיהוי דיבור מקומי';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'הכיסוי הרחב ביותר של שפות, בתוספת אוצר מילים מותאם אישית וכיוונון פיסוק לשמות, ראשי תיבות ומונחים מקצועיים.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'עדיין לא תומך בשפה שבחרת';

  @override
  String get onboardingTestRecordingTitle => 'נסה עכשיו';

  @override
  String get onboardingTestRecordingSubtitle =>
      'לחץ על הכפתור למטה ואמור משפט. הטקסט מופיע בשדה הבדיקה. גם הקיצור שלך עובד.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'הקיצור שלך';

  @override
  String get onboardingTestRecordingStartCta => 'התחל הקלטה';

  @override
  String get onboardingTestRecordingStopCta => 'עצור הקלטה';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'נסה קודם הקלטה אחת כדי להמשיך.';

  @override
  String get onboardingTestRecordingMicBypassCta => 'המשך ללא מיקרופון';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'ללא מיקרופון פועל, WhisPaste עדיין לא יכול להתחיל הקלטה. אפשר להשלים זאת בכל עת דרך סטטוס המיקרופון בעמוד הזה או בהגדרות.';

  @override
  String get onboardingTestRecordingMicBypassConsequence =>
      'אז קיצור המקלדת יישאר לא נבדק עד שתשתמש בו בפעם הראשונה.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'הטקסט המדובר שלך יופיע כאן…';

  @override
  String get onboardingTestRecordingInProgress =>
      'מקליט: פשוט התחל לדבר. לחץ שוב כדי לעצור.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      'זהו! כך זה עובד בדיוק בכמעט כל אפליקציה.';

  @override
  String get onboardingTestRecordingReassurance =>
      'רק בדיקה, הטקסט נשאר בשדה הזה.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'רק בדיקה, הטקסט נשאר בשדה הזה — הקלטות נעצרות אוטומטית אחרי $seconds שניות, ניתן לשנות זאת בהגדרות ← $section.';
  }

  @override
  String get onboardingReadyTitle => 'הכל מוכן!';

  @override
  String get onboardingReadyNoModelTitle => 'עדיין חסר מודל זיהוי דיבור';

  @override
  String get onboardingReadyNoModelBody =>
      'בלי מודל זיהוי דיבור או מפתח API, WhisPaste לא יכול לתמלל כלום. הורד מודל או שמור מפתח, ואז הכול מוכן.';

  @override
  String get onboardingReadyBackToModel => 'חזרה למודל';

  @override
  String get onboardingReadySubtitle => 'ככה משתמשים ב-WhisPaste';

  @override
  String get onboardingReadyStep1 => 'לחץ על הקיצור כדי להתחיל להקליט';

  @override
  String get onboardingReadyStep2 => 'לחץ שוב כדי לעצור ולתמלל';

  @override
  String get onboardingReadyStep3AutoPaste =>
      'הטקסט זורם ישירות לאפליקציה הפעילה';

  @override
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'הטקסט בלוח, לחץ $paste כדי להדביק';
  }

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste מעביר הקשר מההקלטה הקודמת עד עשר דקות קדימה. לפני מעבר מהיר לנושא אחר לגמרי, כדאי הפסקה קצרה, אחרת התוצאה הבאה עלולה להיות מוטה.';

  @override
  String get onboardingReadyAutostartToggle => 'הפעלת WhisPaste בהתחברות';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'מופעל ממוזער ברקע, מוכן לקיצור המקשים שלך';

  @override
  String get onboardingTriggerTitle => 'איך תרצה להתחיל הקלטה?';

  @override
  String get onboardingTriggerSubtitle =>
      'הגדר את מקש הקיצור ובחר כיצד הוא מתחיל הקלטה.';

  @override
  String get onboardingTriggerCurrentHotkey => 'קיצור נוכחי';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'הקיצור כבר בשימוש';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'נראה שהקיצור שלך תפוס על ידי אפליקציה אחרת. הקלט שילוב חדש למטה כדי להמשיך.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'חזור לעמוד מקש הקיצור והקלט שם שילוב חדש.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'החזק את הקיצור ודבר, שחרר כדי לסיים';

  @override
  String get onboardingTriggerModeToggleHint =>
      'לחץ פעם אחת כדי להתחיל, לחץ שוב כדי לסיים';

  @override
  String get onboardingTriggerSystemWideHint =>
      'עובד בכל המערכת — לא רק בתוך WhisPaste.';

  @override
  String get onboardingStartUsing => 'בוא נתחיל';

  @override
  String get onboardingReviewExit => 'סגירת המבוא';

  @override
  String get onboardingReviewDone => 'סיום';

  @override
  String get onboardingReviewEntry => 'מבוא';

  @override
  String get onboardingReviewSubtitle =>
      'אפשר לעבור שוב על חמשת שלבי ההגדרה בכל עת — דבר לא משתנה אלא אם תשנה אותו.';

  @override
  String get onboardingReviewLabel => 'צפייה חוזרת במבוא';

  @override
  String get onboardingReviewAction => 'פתיחה';

  @override
  String get onboardingRevisionNoticeTitle =>
      'יש עדכון ל-WhisPaste — ההגדרות שלך נשארות כפי שהן.';

  @override
  String get onboardingRevisionNoticeExpand => 'הצגת כל החידושים';

  @override
  String get onboardingRevisionNoticeCollapse => 'הצגת פחות';

  @override
  String get onboardingRevisionExit => 'יציאה מהמבוא';

  @override
  String get onboardingRevisionExitConfirmTitle => 'לצאת מהמבוא?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'מסלול העדכון מוצג פעם אחת בלבד, ולכן מה שתדלג עליו עכשיו לא יוגדר עבורך. אפשר לפתוח את אותם שלבים בכל עת דרך עמוד ״עזרה״, תחת ״צפייה חוזרת במבוא״, וכל הגדרה שמופיעה בהם קיימת גם בעמוד ההגדרות עצמו. מה שכבר הגדרת נשאר כפי שהוא.';

  @override
  String get onboardingRevisionExitConfirmAction => 'יציאה';

  @override
  String get overlayRecording => 'מקליט';

  @override
  String get overlayTranscribing => 'מעבד…';

  @override
  String get overlayRefining => 'מעודן…';

  @override
  String get overlayStarting => 'מתחיל…';

  @override
  String get overlayDone => 'הועתק';

  @override
  String get overlayDonePasted => 'הודבק';

  @override
  String get overlayDoneBoth => 'הועתק והודבק';

  @override
  String get overlayDoneReady => 'הסתיים';

  @override
  String get overlayError => 'שגיאה';

  @override
  String get overlayCancel => 'בטל';

  @override
  String get overlayPause => 'השהה';

  @override
  String get overlayResume => 'המשך';

  @override
  String get overlayStop => 'עצור';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'לחץ $hotkey כדי לעצור';
  }

  @override
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey לעצירה · $cancelKey לביטול';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return 'לבטל את ההקלטה? לחץ $cancelKey שוב';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Enter או $hotkey: השדה הבא · Esc: ביטול';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Enter: השדה הבא · Esc: ביטול';

  @override
  String get overlayProcessingLocal => 'מקומי';

  @override
  String get overlayProcessingCloud => 'ענן';

  @override
  String get overlayRecordingQuickNote => 'מקליט לפתק';

  @override
  String get overlayTargetQuickNote => 'פתק';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayMicSignalLost => 'אין אות מהמיקרופון';

  @override
  String get overlayDoneQuickNote => 'נוסף לפתק';

  @override
  String get floatingButtonHide => 'הסתר';

  @override
  String get floatingButtonQuit => 'צא';

  @override
  String get a11yRecordingButton => 'כפתור הקלטה';

  @override
  String get a11yRecordingOverlay => 'שכבת הקלטה';

  @override
  String get a11ySidePanel => 'סרגל הדבקה מהירה';

  @override
  String get trayStatusRecording => 'מקליט…';

  @override
  String get trayStatusReady => 'מוכן';

  @override
  String get trayStartRecording => 'התחל הקלטה';

  @override
  String get trayStopRecording => 'עצור הקלטה';

  @override
  String get trayOpenApp => 'פתח WhisPaste';

  @override
  String get trayTranscribeFile => 'תמלול קובץ…';

  @override
  String get trayOpenSidePanel => 'פתיחת סרגל הדבקה מהירה';

  @override
  String get traySettings => 'הגדרות';

  @override
  String get trayQuit => 'צא';

  @override
  String get trayRecentRecordings => 'הקלטות אחרונות';

  @override
  String get trayUnlockRecordings => 'ביטול נעילת הקלטות…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מילים',
      two: 'שתי מילים',
      one: 'מילה אחת',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'שליחת משוב…';

  @override
  String get quitDuringDictationTitle => 'הקלטה עדיין פועלת';

  @override
  String get quitDuringDictationMessage =>
      'סגירה עכשיו תעצור את ההקלטה או התמלול הפועלים, והטקסט שלהם יאבד.';

  @override
  String get trayMicrophone => 'מיקרופון';

  @override
  String get settingsComingSoon => 'בקרוב';

  @override
  String get undo => 'בטל';

  @override
  String get hintDismiss => 'סגור רמז';

  @override
  String get voiceNoteButton => 'הערת קול';

  @override
  String get voiceNoteRecording => 'מקליט הערת קול…';

  @override
  String get voiceNoteTranscribing => 'מתמלל…';

  @override
  String get voiceNoteAdded => 'הערת קול נוספה';

  @override
  String voiceTagAdded(String tag) {
    return 'תגית \"$tag\" נוספה בקול';
  }

  @override
  String get voiceCorrectionApplied => 'תמלול תוקן בקול';

  @override
  String get voiceCorrectionUndone => 'התיקון בוטל';

  @override
  String get voiceNoteEmpty => 'לא זוהה דיבור';

  @override
  String get voiceNoteError => 'הערת קול נכשלה';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'הערה קולית — אמור „tag: …“ כדי להוסיף תגית, או „correct: …“ כדי להחליף את התמלול הזה';

  @override
  String updateAvailable(String version) {
    return 'עדכון זמין: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'מוריד עדכון… $percent%';
  }

  @override
  String get updateReadyToInstall => 'עדכון מוכן, לחץ להתקנה';

  @override
  String get updateUpToDate => 'יש לך את הגרסה העדכנית ביותר';

  @override
  String get updateCheckNow => 'בדוק עכשיו';

  @override
  String get updateInstall => 'התקן עדכון';

  @override
  String get updateDownload => 'הורד';

  @override
  String get updateViewRelease => 'הערות גרסה';

  @override
  String get updateError => 'בדיקת עדכון נכשלה';

  @override
  String get updateInstallAfterRecording => 'העדכון יותקן אחרי ההקלטה';

  @override
  String get updateInstallerMissing =>
      'קובץ ההתקנה חסר. בדקו שוב אם יש עדכונים.';

  @override
  String get updateInstallFailed =>
      'לא ניתן היה להפעיל את ההתקנה. נסו להתקין את העדכון שוב.';

  @override
  String get updateInstallRetry => 'התקן שוב';

  @override
  String get updateRateLimited => 'יותר מדי בקשות, נסה שוב מאוחר יותר';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version זמין';
  }

  @override
  String get settingsOverlaySize => 'גודל שכבה';

  @override
  String get settingsOverlaySizeSubtitle => 'בחר בין תצוגה מפורטת או מינימלית';

  @override
  String get settingsOverlaySizeNormal => 'רגיל';

  @override
  String get settingsOverlaySizeCompact => 'קומפקטי';

  @override
  String get settingsOverlaySizeMini => 'מיני';

  @override
  String get settingsOverlayColors => 'צבעי השכבה';

  @override
  String get settingsOverlayBackground => 'רקע של השכבה והכפתור';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'חל על השכבה של ההקלטה ועל הכפתור הצף.';

  @override
  String get settingsOverlayBackgroundMarine => 'ים';

  @override
  String get settingsOverlayBackgroundGraphit => 'גרפיט';

  @override
  String get settingsOverlayBackgroundGletscher => 'קרחון';

  @override
  String get settingsOverlayBackgroundAmber => 'ענבר';

  @override
  String get settingsOverlayWave => 'צבע הגל לשכבה ולכפתור';

  @override
  String get settingsOverlayWaveSubtitle =>
      'חל על השכבה של ההקלטה ועל הכפתור הצף: הגל וטבעת ההקלטה.';

  @override
  String get settingsOverlayWaveCyan => 'ציאן';

  @override
  String get settingsOverlayWaveViolett => 'סגול';

  @override
  String get settingsOverlayWaveNeutral => 'ניטרלי';

  @override
  String get settingsOverlayWaveAmber => 'ענבר';

  @override
  String get settingsOverlayWaveInk => 'דיו';

  @override
  String get settingsOverlayWaveCoral => 'אלמוגי';

  @override
  String get settingsOverlayWaveMint => 'נענע';

  @override
  String get settingsOverlayWaveUnavailable => 'לא נראה היטב על רקע זה';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '„$from“ לא נראה היטב על רקע זה. הגל הוחלף ל-„$to“.';
  }

  @override
  String get settingsOverlayLiveTranscript => 'תמלול חי';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'הצג את הטקסט המתמלל בזמן אמת, במקום תצוגת גל בלבד';

  @override
  String get overlayRetry => 'נסה שוב';

  @override
  String get overlayDismiss => 'סגור';

  @override
  String get overlayContextCancel => 'בטל הקלטה';

  @override
  String get overlayContextSwitchNormal => 'עבור לרגיל';

  @override
  String get overlayContextSwitchCompact => 'עבור לקומפקטי';

  @override
  String get overlayContextSwitchMini => 'עבור למיני';

  @override
  String get overlayContextHide => 'הסתר שכבה';

  @override
  String get buttonContextOpen => 'פתח את WhisPaste';

  @override
  String get buttonContextStartRecording => 'התחל הקלטה';

  @override
  String get buttonContextShowHistory => 'הצג הקלטות';

  @override
  String get buttonContextSettings => 'הגדרות';

  @override
  String get buttonContextQuit => 'צא מ-WhisPaste';

  @override
  String get settingsHistory => 'הקלטות';

  @override
  String get settingsHistorySubtitle => 'שמירה וניקוי אוטומטי';

  @override
  String get settingsHistoryMaxEntries => 'מספר רשומות מקסימלי';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'ללא הגבלה';

  @override
  String get settingsHistoryAutoTrashDays => 'מחק אשפה אוטומטית אחרי';

  @override
  String get settingsHistoryAutoTrashNever => 'לעולם לא';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ימים',
      one: 'יום אחד',
    );
    return '$_temp0';
  }

  @override
  String get settingsHistoryRetentionPreset => 'שמירה';

  @override
  String get settingsHistoryPresetMinimal => 'מינימלי';

  @override
  String get settingsHistoryPresetStandard => 'רגיל';

  @override
  String get settingsHistoryPresetUnlimited => 'ללא הגבלה';

  @override
  String get settingsHistoryPresetCustom => 'מותאם אישית';

  @override
  String get settingsHistoryHideOnOpen => 'הסתרת ההקלטות בפתיחה';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'מציג כפתור \"הצגת הקלטות\" במקום התמלולים שלך בכל פעם ש־WhisPaste מופעל או שהחלון נפתח מחדש. דבר לא נמחק.';

  @override
  String get historyPinGateTitle => 'ההקלטות נעולות';

  @override
  String get historyPinGateHint =>
      'הזן את קוד ה-PIN כדי להציג את התמלולים שלך.';

  @override
  String get historyImportUnlockHint =>
      'בטל את הנעילה של הקלטות כדי לתמלל את הקובץ.';

  @override
  String get historyPinUnlock => 'ביטול נעילה';

  @override
  String get historyPinDialogTitle => 'הזן PIN';

  @override
  String get historyPinDialogSubtitle => 'ההקלטות שלך מוגנות בקוד PIN.';

  @override
  String get historyPinFieldHint => 'PIN';

  @override
  String get historyPinRepeatHint => 'הזן PIN שוב';

  @override
  String get historyPinWrong => 'PIN שגוי.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'יותר מדי ניסיונות. נסה שוב בעוד $seconds שניות.';
  }

  @override
  String get historyPinForgot => 'שכחת את ה-PIN?';

  @override
  String get historyPinForgotHint =>
      'איפוס מוחק מיד את כל התמלולים, קובצי השמע השמורים, ההערות עם הגרסאות ותמונות ההערות. אם קובץ לא ניתן למחיקה, WhisPaste מציג הודעה.';

  @override
  String get historyPinForgotConfirmTitle =>
      'למחוק הקלטות והערות ולהסיר את קוד ה-PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'קוד PIN ששכחת אינו ניתן לשחזור. לאיפוס נמחקים מיד ולצמיתות כל התמלולים וקובצי השמע השמורים (כולל הארכיון וסל המחזור), כל ההערות עם הגרסאות (כולל סל המחזור) וכל תמונות ההערות. ההגדרות, קטעי הטקסט וההחלפות נשמרים. אם קובץ לא ניתן למחיקה, WhisPaste מציג הודעה.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'לא ניתן היה למחוק חלק מההקלטות, הייבואים או תמונות ההערות. WhisPaste יסיר אותם בהפעלה הבאה.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'לא ניתן היה למחוק חלק מההקלטות או מהייבואים, ו-WhisPaste אינו יכול לנסות שוב מאוחר יותר. יש למחוק אותם ידנית. מיקום: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'לא ניתן היה למחוק עותק של מסד הנתונים הישן ($path). יש למחוק אותו ידנית.';
  }

  @override
  String get historyPinForgotConfirmAction => 'מחק';

  @override
  String get historyPinSetTitle => 'הגדר PIN';

  @override
  String get historyPinSetSubtitle =>
      '4–8 ספרות. מונע מאחרים לצפות בקלות בתמלולים שלך במחשב זה — אך אינו מצפין אותם.';

  @override
  String get historyPinInvalid => 'השתמש ב-4 עד 8 ספרות.';

  @override
  String get historyPinMismatch => 'קודי ה-PIN אינם תואמים.';

  @override
  String get settingsHistoryPin => 'הגנת PIN';

  @override
  String get settingsHistoryPinSubtitle =>
      'לדרוש קוד PIN להצגת הקלטות והערות, כולל החלונית הצדדית, תפריט הכפתור הצף וממשק האוטומציה.';

  @override
  String get settingsHistoryPinChange => 'שנה';

  @override
  String get settingsHistoryPinRemove => 'הסר';

  @override
  String get settingsHistoryAutoLock => 'נעילה אוטומטית';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'מסתיר שוב את ההקלטות לאחר זמן חוסר פעילות זה.';

  @override
  String get settingsHistoryAutoLockNever => 'אף פעם';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'אחרי $minutes דק׳';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'הפעל את הכפתור הצף כדי לשנות את זה.';

  @override
  String get settingsFloatingButtonSection => 'כפתור צף';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'כפתור הקלטה תמיד עליון לגישה מהירה';

  @override
  String get settingsFloatingButtonWaylandTitle => 'מגבלות Wayland';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'תחת Wayland שולחן העבודה קובע איפה הכפתור מופיע ואם הוא נשאר מעל החלונות. WhisPaste יכולה להבטיח את שניהם רק במידה מוגבלת שם. הקלטה בלחיצה ממשיכה לעבוד, והכפתור לא לוקח את מיקוד המקלדת.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'לא זמין בשולחן העבודה הזה של Linux: הכפתור דורש X11 או XWayland. כיבוי נשאר אפשרי.';

  @override
  String get settingsSttIdleTimeout => 'זמן המתנה של מודל זיהוי דיבור';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'כמה זמן המודל נשאר טעון אחרי שימוש';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'תמיד פעיל';

  @override
  String get settingsSttKeepLoaded => 'להשאיר את המודל טעון';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'מודל טעון מתחיל הכתבה בלי להמתין לטעינה. כל עוד הוא טעון, הוא תופס זיכרון.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'כשהמודל טעון, הוא דורש כ-$size זיכרון.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'זיכרון כרטיס המסך ($vramMb MB) לא מספיק למודל הזה ($requiredMb MB). המודל רץ על המעבד.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'תמיד';

  @override
  String get settingsSttKeepLoadedAutomatic => 'אוטומטי';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'אחרי זמן המתנה';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'לפרוק אחרי';

  @override
  String settingsSttIdleTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count דקות',
      one: 'דקה אחת',
    );
    return '$_temp0';
  }

  @override
  String get reviewPromptTitle => 'אתה נהנה מ-WhisPaste?';

  @override
  String get reviewPromptBody =>
      'הדירוג שלך עוזר לאחרים לגלות את האפליקציה וממשיך את הפיתוח.';

  @override
  String get reviewPromptYes => 'אוהב מאוד!';

  @override
  String get reviewPromptNotNow => 'לא עכשיו';

  @override
  String get reviewPromptNever => 'אל תשאל שוב';

  @override
  String get reviewPromptStarGitHub => 'כוכב ב-GitHub';

  @override
  String get reviewPromptRateStore => 'דרג בחנות';

  @override
  String get reviewSupportEntry => 'דרג ותמוך ב-WhisPaste';

  @override
  String get reviewSupportLabel => 'דירוג האפליקציה';

  @override
  String get reviewSupportAction => 'דרג';

  @override
  String get reviewSupportGitHubLabel => 'תמוך ב-WhisPaste עם כוכב ב-GitHub';

  @override
  String get reviewSupportGitHubAction => 'צפה ב-GitHub';

  @override
  String get githubInviteTitle => 'WhisPaste הוא קוד פתוח';

  @override
  String get githubInviteBody =>
      'כוכב ב-GitHub עוזר לאחרים למצוא את האפליקציה.';

  @override
  String get githubInviteOpen => 'צפה ב-GitHub';

  @override
  String get githubInviteLater => 'אחר כך';

  @override
  String get githubInviteNever => 'אל תשאל שוב';

  @override
  String get ideasBoardLabel => 'רעיונות ובקשות לתכונות';

  @override
  String get ideasBoardAction => 'צפה בלוח';

  @override
  String get feedbackIdeasLink => 'הציע רעיונות והצבע עליהם';

  @override
  String get feedbackTypeProblem => 'בעיה';

  @override
  String get feedbackTypeIdea => 'רעיון';

  @override
  String get feedbackTypePraise => 'שבח';

  @override
  String get feedbackTypeQuestion => 'שאלה';

  @override
  String get feedbackPromptProblem => 'מה השתבש? ספרו לנו מה עשיתם ומה קרה.';

  @override
  String get feedbackPromptIdea => 'מה היה הופך את WhisPaste לטוב יותר בשבילך?';

  @override
  String get feedbackPromptPraise => 'מה עובד טוב בשבילך?';

  @override
  String get feedbackPromptQuestion => 'מה תרצה לדעת?';

  @override
  String get feedbackDiagnosticsLabel => 'צירוף אבחון';

  @override
  String get feedbackDiagnosticsExplanation =>
      'מוסיף את גרסת האפליקציה, מערכת ההפעלה, מנוע הזיהוי הקולי והעורף. הכתיבה והטקסטים שלך לעולם לא מצורפים.';

  @override
  String get feedbackDiagnosticsPreview => 'הצגת תצוגה מקדימה';

  @override
  String get feedbackDiagnosticsPreviewHide => 'הסתרת התצוגה המקדימה';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'הטקסט המדויק הזה יצורף להודעה שלך:';

  @override
  String get feedbackIdeaBoardHint =>
      'אפשר גם לפרסם את הרעיון שלך בלוח הרעיונות הציבורי ולהצביע על רעיונות של אחרים.';

  @override
  String get feedbackTextTooLong =>
      'הטקסט ארוך מדי לצירוף האבחון. קצרו אותו מעט.';

  @override
  String get hotkeyRegistrationFailed =>
      'רישום קיצור הדרך נכשל, הגדר מחדש את הקיצור בהגדרות.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken כבר בשימוש על ידי אפליקציה אחרת. עד שתבחר צירוף אחר, $active מתחיל את ההקלטה.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'אפליקציה אחרת תפסה את מקש הקיצור של $action. הוא יישאר כבוי עד שתבחר צירוף פנוי בהגדרות.';
  }

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'קיצור דרך זה שמור על ידי $platform ($note) ועלול לא לפעול.';
  }

  @override
  String get exportFormatPickerTitle => 'בחר פורמט ייצוא';

  @override
  String get exportFormatText => 'טקסט';

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
      'התמלול לוקח כרגע קצת יותר זמן מהרגיל, אך הוא עדיין פועל.';

  @override
  String get recoveryExhaustedToast =>
      'מודל זיהוי הדיבור לא יכול להתחיל. הפעל מחדש את האפליקציה או טען מחדש את מודל הקול.';

  @override
  String get recoveryExhaustedAction => 'פתח הגדרות';

  @override
  String get recoveryVcRuntimeToast =>
      'מודל זיהוי הדיבור לא יכול להתחיל: חסר רכיב של Windows (Microsoft Visual C++). התקן את Visual C++ Redistributable (x64) והפעל מחדש את WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'התקן';

  @override
  String get modelAbiInfoToast => 'טוען מחדש את מודל הקול, אנא המתן.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste פועל כעת ללא האצה בכרטיס המסך, בגלל בעיה בהפעלה האחרונה. ההקלטה ממשיכה לעבוד כרגיל.';

  @override
  String get serverDownloadFailedToast =>
      'לא ניתן היה להוריד את מודל זיהוי הדיבור. האם לבדוק את החיבור לאינטרנט?';

  @override
  String get serverDownloadFailedAction => 'נסה שוב';

  @override
  String get serverDownloadStalledToast => 'ההורדה נתקעה: מתחבר מחדש.';

  @override
  String get historyWriteFailedToast =>
      'הפריט לא נשמר. בדוק את שטח האחסון הפנוי.';

  @override
  String get historyWriteFailedAction => 'העתק אבחון';

  @override
  String get errorSttRejectEmpty => 'אין אודיו לתמלול, נסה להקליט שוב.';

  @override
  String get errorSttRejectInvalidWav => 'קובץ האודיו פגום, נסה להקליט שוב.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'השפה אינה נתמכת על ידי מנוע הדיבור המקומי, בדוק את השפה בהגדרות.';

  @override
  String get errorSttRejectPromptTooLong =>
      'אוצר המילים המותאם ארוך מדי, קצר אותו בהגדרות.';

  @override
  String get settingsGpuAcceleration => 'האצת גרפיקה';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'אוטומטי משתמש בכרטיס המסך כשהוא זמין. „רק CPU“ איטי יותר, אבל עובד בכל מכשיר. „אלץ GPU“ רק אם המצב האוטומטי לא עובד.';

  @override
  String get settingsGpuAccelerationAuto => 'אוטומטי (מומלץ)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (כפוי)';

  @override
  String get settingsGpuAccelerationDisabled => 'CPU בלבד';

  @override
  String get settingsSttEngine => 'מודל זיהוי דיבור';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 שפות. Parakeet: מהיר יותר, כ-25 שפות.';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet';

  @override
  String get settingsSttEngineRecommended => 'מומלץ';

  @override
  String get parakeetModelTitle => 'מודל Parakeet';

  @override
  String parakeetModelSubtitle(String size) {
    return 'הורדה חד-פעמית ($size), ולאחר מכן פועל לגמרי במצב לא מקוון';
  }

  @override
  String get parakeetModelDownload => 'הורד';

  @override
  String get parakeetModelDownloading => 'מוריד…';

  @override
  String get parakeetModelInstalled => 'מותקן';

  @override
  String get parakeetModelDelete => 'מחק';

  @override
  String get parakeetModelCancel => 'בטל';

  @override
  String get settingsSearchHint => 'חיפוש הגדרות…';

  @override
  String get settingsSearchNoResults => 'אין תוצאות';

  @override
  String get settingsSearchNoResultsHint => 'נסה מונח חיפוש אחר.';

  @override
  String get settingsSearchFieldLabel => 'חיפוש הגדרות';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תוצאות',
      zero: 'אין תוצאות',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'פרטיות';

  @override
  String get settingsPrivacySubtitle => 'שליטה במידע ש-WhisPaste משתף';

  @override
  String get settingsShareUsageStats => 'שיתוף סטטיסטיקות שימוש אנונימיות';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'ספירות שימוש אנונימיות, בלי עוגיות וללא קישור אליך. עוזרות לנו לראות אילו פונקציות בשימוש. הטקסט והאודיו שלך לעולם לא נכללים.';

  @override
  String get settingsRetainRecentAudio => 'שמירת אודיו של הקלטות אחרונות';

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'שמירת האודיו של $count ההקלטות האחרונות במכשיר זה, לצורך ניפוי תקלות או שחזור תמלול קודם. הקלטות וקבצים מיובאים נמחקים אוטומטית לכל היותר אחרי $days ימים';
  }

  @override
  String get pendingAudioRetentionNote =>
      'הקלטה שהתמלול שלה נכשל שומרת את האודיו עד 24 שעות כדי שתוכל לנסות שוב, גם כשהאפשרות כבויה.';

  @override
  String get pendingAudioSectionTitle => 'הקלטות הממתינות לניסיון חוזר';

  @override
  String get pendingAudioSectionBody =>
      'לא ניתן היה לתמלל את ההקלטות האלה, למשל כי החיבור נותק. האודיו נמחק תוך 24 שעות לכל היותר, או כשמוחקים אותו.';

  @override
  String get pendingAudioEmpty => 'אין הקלטות הממתינות.';

  @override
  String get featureSpotlightHeading => 'חדש ב-WhisPaste';

  @override
  String get featureSpotlightDismiss => 'הבנתי';

  @override
  String get featureSpotlightSnippetPickerTitle => 'בורר קטעים';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'שמור קטעי טקסט לשימוש חוזר והכנס אותם בכל מקום בלחיצה על מקש קיצור או במילת הפעלה קולית – בלי להקליד שוב.';

  @override
  String get featureSpotlightSidePanelTitle => 'סרגל לוח הגזירים';

  @override
  String get featureSpotlightSidePanelDescription =>
      'העבר את העכבר לקצה המסך כדי לפתוח את היסטוריית לוח הגזירים שלך וגרור כל פריט ישירות למסמך.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle => 'קטעים אינטראקטיביים';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'קטעים עם שדות למילוי: WhisPaste מוביל אותך משדה לשדה – דבר, הקש Enter למעבר לשדה הבא, והטקסט המוגמר מודבק בבת אחת.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'נקה, קצר או תרגם את הטקסט שלך לפני ההדבקה – כברירת מחדל, לגמרי במכשיר שלך, עם קיצור ייעודי ושפת יעד משלו.';

  @override
  String get featureSpotlightHistoryPinTitle => 'נעילת ההקלטות בקוד PIN';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'הגן על התמלולים שלך בקוד PIN – גם בסרגל הצד ובתפריט הכפתור הצף – עם נעילה אוטומטית אופציונלית אחרי חוסר פעילות. הגדרות ← הקלטות.';

  @override
  String get featureSpotlightEditSelectionTitle => 'עריכת טקסט מסומן בקול';

  @override
  String get featureSpotlightEditSelectionDescription =>
      'סמן טקסט בכל אפליקציה, לחץ על מקש הקיצור לעריכת הבחירה ואמור מה לשנות – או פשוט \"קצר\", \"שפר\" או \"תרגם\". משתמש במודל הטקסט של Smart Mode. כבוי כברירת מחדל: הפעל בהגדרות ← Smart Mode.';

  @override
  String get featureSpotlightChangelogLink => 'צפייה ביומן השינויים המלא';

  @override
  String get featureSpotlightReviewLabel => 'צפייה חוזרת בתכונות החדשות';

  @override
  String get featureSpotlightReviewAction => 'הצגה';

  @override
  String get notesNewNote => 'פתק חדש';

  @override
  String get notesEmptyTitle => 'עוד אין פתקים';

  @override
  String get notesEmptyHint => 'צור פתק כדי להתחיל לאסוף טקסט מכל מקום.';

  @override
  String get notesUntitled => 'פתק ללא כותרת';

  @override
  String get notesEditorPlaceholder => 'התחל להקליד…';

  @override
  String get notesListSemantics => 'רשימת פתקים';

  @override
  String get notesCopy => 'העתק פתק';

  @override
  String get notesCopied => 'הפתק הועתק';

  @override
  String get notesFavorite => 'סמן כמועדף';

  @override
  String get notesUnfavorite => 'הסר מהמועדפים';

  @override
  String get notesQuickNoteSet => 'הפוך לפתק המהיר שאליו הקיצור מוסיף טקסט';

  @override
  String get notesQuickNoteClear => 'פתק מהיר — הסר את הסימון';

  @override
  String get notesQuickNoteHotkeyLabel => 'קיצור';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'שינוי הקיצור לפתק מהיר — כרגע $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff => 'הקיצור לפתק מהיר כבוי.';

  @override
  String get notesQuickNoteHotkeyEnable => 'הפעלת הקיצור';

  @override
  String get notesMoveToTrash => 'העבר לאשפה';

  @override
  String get notesMovedToTrash => 'הועבר לאשפה';

  @override
  String get notesRestore => 'שחזר';

  @override
  String get notesDeleteForever => 'מחק לצמיתות';

  @override
  String get notesDeleteForeverConfirm => 'למחוק את הפתק לצמיתות?';

  @override
  String get notesTrash => 'אשפה';

  @override
  String get notesTrashEmpty => 'האשפה ריקה';

  @override
  String get notesTrashEmptyHint =>
      'פתקים שנמחקו מגיעים לכאן ולא מוסרים אוטומטית.';

  @override
  String get notesUndo => 'בטל';

  @override
  String get notesAddTag => 'הוסף תגית';

  @override
  String get notesTagPlaceholder => 'שם התגית…';

  @override
  String get notesSearchPlaceholder => 'חפש בפתקים…';

  @override
  String get notesSearchFieldLabel => 'חפש בפתקים';

  @override
  String get notesNoResults => 'אין תוצאות';

  @override
  String notesNoResultsHint(String query) {
    return 'אין פתקים שמתאימים ל \"$query\".\nנסה מונח חיפוש אחר.';
  }

  @override
  String notesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תוצאות',
      one: 'תוצאה אחת',
    );
    return '$_temp0';
  }

  @override
  String get notesExport => 'ייצא';

  @override
  String markdownToolbarBold(String shortcut) {
    return 'מודגש ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'נטוי ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'כותרת';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'רשימת תבליטים ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'רשימה ממוספרת';

  @override
  String get markdownToolbarQuote => 'ציטוט';

  @override
  String get markdownToolbarCode => 'קוד';

  @override
  String get findReplaceToggle => 'חיפוש והחלפה בטקסט הזה';

  @override
  String get findReplaceFindLabel => 'חיפוש בטקסט הזה';

  @override
  String get findReplaceFindHint => 'חיפוש…';

  @override
  String get findReplaceReplaceLabel => 'החלפת התוצאות ב';

  @override
  String get findReplaceReplaceHint => 'החלפה ב…';

  @override
  String get findReplaceNext => 'התוצאה הבאה';

  @override
  String get findReplacePrevious => 'התוצאה הקודמת';

  @override
  String get findReplaceReplaceAction => 'החלפת התוצאה הזו';

  @override
  String get findReplaceReplaceAllAction => 'החלפת כל התוצאות';

  @override
  String get findReplaceClose => 'סגירת חיפוש והחלפה';

  @override
  String get findReplaceNoMatches => 'אין תוצאות';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current מתוך $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'תמלולים';

  @override
  String get sidePanelSnippetsTitle => 'קטעים';

  @override
  String get sidePanelClipboardHistoryTitle => 'היסטוריית לוח הגזירים';

  @override
  String get sidePanelClipboardHistoryEmpty => 'עדיין לא הועתק כלום';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'כל מה שתעתיק בזמן ש-WhisPaste פועלת יופיע כאן — מתנקה עם הפעלה מחדש של האפליקציה.';

  @override
  String get sidePanelClipboardLockedTitle => 'נעול בקוד PIN';

  @override
  String get sidePanelClipboardLockedHint =>
      'הטקסט שהועתק מוסתר כל עוד ההקלטות נעולות. בטלו את הנעילה בקוד ה-PIN כדי לראות אותו שוב.';

  @override
  String get sidePanelClose => 'סגור סרגל';

  @override
  String get sidePanelSearchHint => 'חיפוש';

  @override
  String get sidePanelSearchFieldLabel => 'חיפוש ברשימה זו';

  @override
  String get sidePanelNoMatches => 'אין התאמות';

  @override
  String get sidePanelNoMatchesHint => 'נסה מונח חיפוש אחר.';

  @override
  String get sidePanelLoadFailedHint =>
      'סגרו את הפאנל ופתחו אותו מחדש כדי לנסות שוב.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'ניקוי טקסט, קיצור ותרגום מקומיים לאחר ההקלטה';

  @override
  String get smartModeStandardPreset => 'פריסט רגיל';

  @override
  String get smartModePresetOff => 'כבוי';

  @override
  String get smartModePresetOffDescription =>
      'אין עיבוד אוטומטי לאחר ההקלטה — הטקסט המוכתב משמש בדיוק כפי שתומלל.';

  @override
  String get smartModePresetCleanup => 'ניקוי';

  @override
  String get smartModePresetCleanupDescription =>
      'מסיר מילות מילוי כמו \"אה\" ומתקן פיסוק ורישיות, בלי לשנות את הניסוח, המשמעות או השפה.';

  @override
  String get smartModePresetConcise => 'תמצות';

  @override
  String get smartModePresetConciseDescription =>
      'מקצר את הטקסט על ידי הסרת חזרות ומילוי, תוך שמירה על כל עובדה חשובה, באותה שפה.';

  @override
  String get smartModePresetTranslate => 'תרגום';

  @override
  String get smartModePresetTranslateDescription =>
      'מתרגם את הטקסט המוכתב לשפת היעד שנקבעה למטה.';

  @override
  String get smartModeTargetLanguage => 'שפת יעד';

  @override
  String get smartModeTargetLanguageGerman => 'גרמנית';

  @override
  String get smartModeTargetLanguageEnglish => 'אנגלית';

  @override
  String get smartModeTargetLanguageSpanish => 'ספרדית';

  @override
  String get smartModeTargetLanguageFrench => 'צרפתית';

  @override
  String get smartModeTargetLanguagePortuguese => 'פורטוגזית';

  @override
  String get smartModeTargetLanguageMandarin => 'מנדרינית';

  @override
  String get smartModeTargetLanguageRussian => 'רוסית';

  @override
  String get smartModeDownload => 'הורד';

  @override
  String get smartModeDownloadComplete => 'מודל הטקסט מוכן לשימוש';

  @override
  String get smartModeRamWarningTitle => 'זוהה זיכרון מוגבל';

  @override
  String get smartModeRamWarningBody =>
      'מודל הטקסט המקומי של Smart Mode פועל בצורה הטובה ביותר עם 8GB זיכרון RAM ומעלה. הוא עשוי לעבוד גם עם פחות, אך עלול לפעול לאט או להיכשל במכשיר זה. להוריד בכל זאת?';

  @override
  String get smartModeRamWarningContinue => 'הורד בכל זאת';

  @override
  String get smartModeRamWarningCancel => 'בטל';

  @override
  String get smartModeModelDeleteConfirm => 'למחוק את מודל הטקסט הזה?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'קובץ מודל הטקסט נמחק ממכשיר זה. תוכל להוריד אותו שוב בכל עת.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'עם מודל הטקסט המקומי, הכול פועל במכשיר. בזמן פעילות מודל הטקסט צורך כ-4–5GB זיכרון RAM בנוסף לשטח האחסון — משותף עם מודל זיהוי הדיבור, כך שהצריכה הכוללת תלויה גם במודל זיהוי הדיבור שטעון.';

  @override
  String get smartModeFactGuardHint =>
      'שומר העובדות בודק מספרים, תאריכים, קישורים, כתובות דוא\"ל ו-IBAN. שמות ממילון נשמרים. הוראות חופשיות עלולות לשנות שמות שאינם במילון; הוסף אותם למילון אם הם צריכים להישאר.';

  @override
  String get smartModeSpeedExampleInfo =>
      'לדוגמה: הקלטה טיפוסית של 50 מילים אורכת כ-1–6 שניות לעיבוד, בהתאם לחומרת המכשיר שלך.';

  @override
  String get smartModeLocalUnavailable =>
      'Smart Mode המקומי אינו כלול בגרסה זו. עבור ל-OpenAI או התקן גרסה רשמית של WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'הקלטה עם Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'מתחיל הקלטה עם פריסט קבוע, ללא תלות בפריסט הרגיל ב-Smart Mode. \"החזק להקלטה\" חל גם כאן.';

  @override
  String get settingsSmartModeHotkeyPreset => 'פריסט';

  @override
  String get settingsSmartModeCurrentHotkey => 'קיצור נוכחי';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'צירוף זה כבר משמש עבור \"$action\". בחר צירוף אחר.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'לא ניתן היה לרשום צירוף זה — מקש הקיצור של Smart Mode אינו פעיל כרגע. בחר צירוף אחר.';

  @override
  String get smartModeOnboardingHintTitle => 'נסה את Smart Mode';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'Smart Mode יכול לנקות, לקצר או לתרגם את הטקסט שלך אוטומטית — כברירת מחדל, לגמרי במכשיר שלך. מודל הטקסט המקומי תופס $size בדיסק. הורד אותו עכשיו, או הגדר אותו מאוחר יותר בהגדרות.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'טקסט גולמי';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'אז אממ פגישת הלקוח נדחתה ליום חמישי בשלוש אחר הצהריים ו אה אנחנו עדיין צריכים את המצגת המעודכנת מהשיווק';

  @override
  String get smartModeOnboardingHintExampleAfterLabel => 'התוצאה של Smart Mode';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'אז, פגישת הלקוח נדחתה ליום חמישי בשלוש אחר הצהריים, ואנחנו עדיין צריכים את המצגת המעודכנת מהשיווק.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'הורדה';

  @override
  String get smartModeOnboardingHintSkipCta => 'מאוחר יותר';

  @override
  String get smartModeUsageHintTitle => 'נסה את Smart Mode בהקלטה הבאה שלך';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode יכול לנקות, לקצר או לתרגם טקסט כזה אוטומטית, ישירות במכשיר שלך. הנה מה שאמרת הרגע:';

  @override
  String get smartModeUsageHintCta => 'הגדרה';

  @override
  String get smartModeUsageHintDismiss => 'לא עכשיו';

  @override
  String get settingsAutomationApi => 'ממשק API מקומי לאוטומציה';

  @override
  String get settingsAutomationApiSubtitle =>
      'תוכניות וסקריפטים אחרים במחשב הזה יכולים לשלוט ב-WhisPaste, למשל להתחיל הקלטה. מכשירים אחרים ברשת לא יכולים להגיע אליו.';

  @override
  String get settingsAutomationApiEnable => 'הפעלת ממשק האוטומציה המקומי';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'מאזין רק ל-127.0.0.1/::1 — אף פעם לא נגיש מהרשת';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'פועל בפורט $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'פועל בפורט $port (פורט $requestedPort היה תפוס)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'לא פועל';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'לא נמצא פורט פנוי בטווח $start–$end';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'פורט מותאם אישית';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'השאר ריק לבחירת פורט אוטומטית — אם הפורט תפוס, ייבחר פורט חלופי אוטומטית';

  @override
  String get settingsAutomationApiCustomPortHint => 'אוטומטי';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'הזן פורט בין 1024 ל-65535';

  @override
  String get settingsAutomationApiToken => 'טוקן Bearer';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'שלח אותו בכותרת \"Authorization: Bearer <token>\" — כל בקשה בלעדיו נדחית';

  @override
  String get settingsAutomationApiRegenerate => 'צור מחדש';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle => 'ליצור טוקן חדש?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'הטוקן הנוכחי יפסיק לעבוד מיד. כל סקריפט שמשתמש בו יצטרך את הטוקן החדש.';

  @override
  String get settingsAutomationApiCopyToken => 'העתק טוקן';

  @override
  String get settingsAutomationApiTokenCopied => 'הטוקן הועתק ללוח';

  @override
  String get settingsAutomationApiDocumentation => 'תיעוד';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'תיעוד נקודות הקצה ודוגמאות curl';

  @override
  String get settingsAutomationApiDocumentationAction => 'פתח';

  @override
  String historyCharacterCount(int count) {
    return '$count תווים';
  }

  @override
  String historyPastedInto(String app) {
    return 'הודבק ל-$app';
  }

  @override
  String get historyShowOriginalTranscript => 'הצג תמלול מקורי';

  @override
  String get historyHideOriginalTranscript => 'הסתר תמלול מקורי';

  @override
  String get historyOriginalTranscriptLabel => 'תמלול מקורי';

  @override
  String get settingsHotkeyActionSelectionEdit => 'עריכת הבחירה';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'עריכת הבחירה';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'סמן טקסט בכל אפליקציה, לחץ על מקש הקיצור ואמור מה לשנות — או פשוט \"קצר\", \"שפר\" או \"תרגם\". התוצאה מחליפה את הבחירה; ביטול באפליקציה מחזיר את המקור. משתמש במודל הטקסט שהוגדר ב-Smart Mode.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'לא ניתן היה לרשום צירוף זה — מקש הקיצור לעריכת הבחירה אינו פעיל כרגע. בחר צירוף אחר.';

  @override
  String get overlayTargetSelectionEdit => 'בחירה';

  @override
  String get overlayRecordingSelectionEdit => 'אמור מה לשנות';

  @override
  String get overlaySelectionEditHint => 'אמור מה לשנות — או: קצר · שפר · תרגם';

  @override
  String get overlayEditingSelection => 'עורך את הבחירה…';

  @override
  String get overlayDoneSelectionEdit => 'הבחירה הוחלפה';

  @override
  String get errorSelectionEditNoSelection =>
      'לא סומן טקסט — סמן טקסט ואז לחץ על מקש הקיצור';

  @override
  String get errorSelectionEditNoEngine =>
      'כדי לערוך בחירות, הגדר קודם את Smart Mode (הורד את מודל הטקסט המקומי או הוסף מפתח OpenAI)';

  @override
  String get errorSelectionEditUnsupported =>
      'עריכת בחירה דורשת הדבקה אוטומטית, שאינה זמינה בגרסה זו';

  @override
  String get errorSelectionEditCopyFailed =>
      'לא ניתן היה לקרוא את הבחירה — בדוק את ההרשאה להדבקה אוטומטית';

  @override
  String get errorSelectionEditFailed => 'העריכה נכשלה — הטקסט שלך לא שונה';

  @override
  String get errorSelectionEditFactsChanged =>
      'העריכה הייתה משנה עובדות שההוראה שלך לא מזכירה — הטקסט שלך לא שונה';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'העריכה הייתה משנה את „$value“ בלי שההוראה שלך מזכירה אותו. ציין את הערך הישן והחדש, למשל „שנה 3 ל-5“ — הטקסט שלך לא שונה';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'לא ניתן היה להחליף את הבחירה — הטקסט שלך לא שונה';

  @override
  String get settingsCudaPackTitle => 'האצת NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'תמלול מהיר יותר בכרטיסי GeForce RTX ו-GTX 16. הורדה חד-פעמית של $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'מותקן. אם מנהל ההתקן הגרפי ישן מדי, WhisPaste ימשיך להשתמש ב-Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'נדרש אישור';

  @override
  String get settingsCudaPackConsentReview => 'בדיקת הרישיון';

  @override
  String get settingsCudaPackDownload => 'הורדה';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'מוריד $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'מתקין …';

  @override
  String get settingsCudaPackCancel => 'ביטול ההורדה';

  @override
  String get settingsCudaPackRemove => 'הסרת חבילת CUDA';

  @override
  String get settingsCudaPackRemoveConfirm => 'להסיר את חבילת CUDA?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'חבילת CUDA תוסר מהמכשיר הזה. אפשר להוריד אותה שוב בכל עת.';

  @override
  String get settingsCudaPackToggle => 'שימוש ב-CUDA';

  @override
  String get settingsCudaPackErrorNetwork =>
      'ההורדה נכשלה. בדוק את החיבור ונסה שוב.';

  @override
  String get settingsCudaPackErrorVerification =>
      'ההורדה הגיעה פגומה. נסה שוב.';

  @override
  String get settingsCudaPackErrorStorage =>
      'לא ניתן היה לשמור את החבילה. בדוק את שטח הדיסק הפנוי.';

  @override
  String get cudaEulaDialogTitle => 'רישיון NVIDIA CUDA';

  @override
  String cudaEulaDialogBody(String version) {
    return 'חבילת CUDA כוללת רכיבים של NVIDIA לפי הסכם הרישיון למשתמש הקצה של NVIDIA CUDA ($version). מאשרים את הנוסח המלא של גרסה זו, הנגיש דרך „הצגת הנוסח המלא“. גרסה אחרת באתר NVIDIA עשויה להיות שונה. יש לאשר אותו כדי להוריד.';
  }

  @override
  String get cudaEulaDialogLink => 'גרסה אחרת ב-NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'הצגת הנוסח המלא';

  @override
  String get cudaEulaFullTextClose => 'סגירה';

  @override
  String get cudaEulaDialogCancel => 'ביטול';

  @override
  String get cudaEulaDialogAccept => 'אישור והורדה';

  @override
  String get recoveryCudaDisabledToast =>
      'האצת CUDA כובתה בגלל בעיה בהפעלה האחרונה. WhisPaste משתמש כעת ב-Vulkan, וההקלטה פועלת כרגיל.';

  @override
  String get recoveryGpuProbeFailedToast =>
      'האצת כרטיס המסך אינה בשימוש בהפעלה זו: הבדיקה של כרטיס המסך לא הסתיימה. WhisPaste מתמלל במעבד. ההקלטה פועלת כרגיל.';

  @override
  String get settingsGpuProbeTitle => 'בדיקת GPU';

  @override
  String get settingsGpuProbeNotChecked =>
      'עדיין לא נבדק. הבדיקה מתבצעת בטעינת המודל הראשונה.';

  @override
  String get settingsGpuProbeUsable => 'נבדק: כרטיס המסך נמצא בשימוש.';

  @override
  String get settingsGpuProbeUnusable =>
      'לא ניתן לשימוש: WhisPaste משתמש במעבד. בדקו שוב אחרי עדכון מנהל ההתקן או האפליקציה.';

  @override
  String get settingsGpuProbeRetry => 'בדוק שוב';

  @override
  String get supportPromptSnooze => 'אל תשאל למשך 90 יום';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'תודה שרכשת את WhisPaste בחנות. כל תמיכה נוספת היא מרצון.';

  @override
  String get supportShareText =>
      'אני משתמש ב-WhisPaste כדי להכניס טקסט בדיבור ישירות לאפליקציות שלי. מקומי על המחשב ובקוד פתוח:';

  @override
  String get supportPageTitle => 'לתמוך ב-WhisPaste';

  @override
  String get supportIntroDirect =>
      'WhisPaste חינמי וקוד פתוח. תמיכה או המלצה עוזרות לפרויקט.';

  @override
  String get supportCostsNote =>
      'התמיכה שלך עוזרת לכסות את הפיתוח ואת העלויות השוטפות של פרסום, אירוח ודומיין.';

  @override
  String get supportSectionOnce => 'תמיכה חד-פעמית';

  @override
  String get supportSectionOthers => 'דרכים נוספות לתמוך';

  @override
  String get supportSectionReach => 'להמליץ על WhisPaste';

  @override
  String get supportStoreTitleWindows => 'WhisPaste ב-Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste ב-Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'ההתקנה והעדכונים מנוהלים על ידי החנות.';

  @override
  String get supportStoreFactPurchase =>
      'הרכישה החד-פעמית שלך תומכת ב-WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'אותן יכולות. הגרסה הישירה נשארת חינמית לשימוש.';

  @override
  String get supportStoreCtaWindows => 'הצג ב-Microsoft Store';

  @override
  String get supportStoreCtaMac => 'הצג ב-Mac App Store';

  @override
  String get supportStorePriceNote => 'המחיר בחנות';

  @override
  String get supportStoreCoffeeNote =>
      'רכישה חד-פעמית, בערך מחיר של קפה. החנות מציגה את המחיר העדכני.';

  @override
  String get supportStoreDismiss => 'הסתר את אפשרות החנות';

  @override
  String get supportStoreShowAgain => 'הצג את אפשרות החנות';

  @override
  String get supportSponsorsCta => 'פתח את GitHub Sponsors';

  @override
  String get supportSponsorsNote =>
      'חודשי או בסכום לבחירתך. את הסכום ואת התדירות בוחרים שם.';

  @override
  String get supportKofiCta => 'פתח את Ko-fi';

  @override
  String get supportPayPalCta => 'לתמוך דרך PayPal';

  @override
  String get supportNativeTitle => 'לתמוך פעם אחת בחנות';

  @override
  String get supportNativeDescription =>
      'סכום חד-פעמי שהחנות גובה. אותן יכולות, ללא מנוי.';

  @override
  String get supportNativeCta => 'לתמוך פעם אחת';

  @override
  String get supportSheetChoose => 'בחר סכום';

  @override
  String get supportSheetLoading => 'טוען סכומים …';

  @override
  String supportSheetBuy(String price) {
    return 'לתמוך ב-$price';
  }

  @override
  String get supportSheetPurchasing => 'החנות מאשרת את הרכישה שלך …';

  @override
  String get supportSheetThanks => 'תודה על התמיכה!';

  @override
  String get supportSheetThanksDetail =>
      'תג התומך שלך פעיל עכשיו. כל היכולות נשארות זמינות לכולם.';

  @override
  String get supportSheetPending => 'הרכישה שלך ממתינה לאישור.';

  @override
  String get supportSheetPurchaseError =>
      'לא ניתן היה להשלים את הרכישה. נסה שוב מאוחר יותר.';

  @override
  String get supportSheetPricesError =>
      'לא ניתן היה לטעון את הסכומים. נסה שוב מאוחר יותר.';

  @override
  String get supportSheetUnavailable => 'כרגע אין סכומים זמינים בחנות.';

  @override
  String get supportSheetRetry => 'נסה שוב';

  @override
  String get supportSheetClose => 'סגור';

  @override
  String get supportSelfDeclareCta => 'אני כבר תומך ב-WhisPaste';

  @override
  String get supportSelfDeclareNote =>
      'רק הערה במכשיר הזה, שום דבר לא נבדק. כפתור התמיכה בשורת המצב מוסתר.';

  @override
  String get supportSelfDeclareHint =>
      'שום דבר לא נבדק. השתמש באפשרות הזו אם כבר תרמת.';

  @override
  String get supportSupporterLine => 'אתה תומך ב-WhisPaste. תודה!';

  @override
  String get supportSupporterBadge => 'תומך';

  @override
  String get supportRateCta => 'דרג בחנות';

  @override
  String get supportShareCopy => 'העתק קישור';

  @override
  String get supportShareCopied => 'הקישור הועתק';

  @override
  String get externalLinkOpenFailed => 'לא ניתן לפתוח את הקישור';

  @override
  String get externalLinkCopyAddress => 'העתקת הכתובת';

  @override
  String get supportShareEmail => 'דוא״ל';

  @override
  String get supportChipLabel => 'ספונסר';

  @override
  String get supportChipTooltip => 'לתמוך ב-WhisPaste';

  @override
  String get supportChipThanksLabel => 'תודה';

  @override
  String get supportChipThanksTooltip => 'תודה על התמיכה';

  @override
  String get settingsSponsorChip => 'כפתור התמיכה בשורת המצב';

  @override
  String get settingsSponsorChipSubtitle =>
      'מציג את הדרך לעמוד התמיכה. אפשר להסתיר אותו בכל עת ולהציג אותו שוב כאן.';

  @override
  String get automationPreviewTitle => 'להוסיף טקסט מרובה שורות?';

  @override
  String get automationPreviewBody =>
      'האוטומציה רוצה להוסיף טקסט עם מעברי שורה. בדוק אותו לפני שהוא מגיע לאפליקציה הפעילה.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count שורות',
      one: 'שורה אחת',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'הוספה';

  @override
  String get automationPreviewCancel => 'ביטול';

  @override
  String get automationIntegrationsHeading => 'שילובים';

  @override
  String get automationIntegrationsHooksTitle =>
      'שליחת אירועים לאפליקציות אחרות';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'שולח תמלולים שהושלמו ופתקים ששונו לאפליקציה במחשב הזה. ההוקים ממשיכים לשלוח גם כששרת ה-API כבוי.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count הוקים',
      one: 'הוק אחד',
      zero: 'אין הוקים',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'ניהול';

  @override
  String get automationIntegrationsCliTitle => 'שורת פקודה ו-MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'רק מקוד המקור. הפעל את $path כש-$token מוגדר; הפקודה $command מפעילה את שרת ה-MCP.';
  }

  @override
  String get automationHooksIntro =>
      'טקסטים מוכנים והערות שהשתנו נשלחים לאפליקציה במחשב הזה. הכתובת חייבת להיות במכשיר הזה.';

  @override
  String get automationHooksEmpty => 'עדיין לא הוגדר חיבור.';

  @override
  String get automationHooksUrlLabel => 'כתובת יעד (רק המחשב הזה)';

  @override
  String get automationHooksEventsLabel => 'אירועים';

  @override
  String get automationHooksEventTranscript => 'התמלול הסתיים';

  @override
  String get automationHooksEventNote => 'הפתק שונה';

  @override
  String get automationHooksAdd => 'הוספת הוק';

  @override
  String get automationHooksRemove => 'הסרת הוק';

  @override
  String get automationHooksRemoveConfirm => 'להסיר את ה-hook הזה?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'ה-hook יוסר מהרשימה. אפשר להוסיף אותו שוב מאוחר יותר.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'השתמש ב-$ipv4, ב-$ipv6 או ב-$localhost עם יציאה, למשל $example.';
  }

  @override
  String get automationHooksNoEvents => 'בחר לפחות אירוע אחד.';

  @override
  String automationHooksTooMany(int max) {
    return 'אפשר להוסיף עד $max הוקים.';
  }

  @override
  String get automationHooksDone => 'סיום';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'הכתבה';

  @override
  String get dockOverflow => 'עוד';

  @override
  String get dockMenuGroupStatus => 'סטטוס';

  @override
  String get dockMenuGroupNotices => 'הודעות';

  @override
  String get dockMenuHotkeyChange => 'שינוי קיצור מקשים…';

  @override
  String get dockMenuSmartModeSettings => 'הגדרות מצב חכם…';

  @override
  String get dockMenuSttModels => 'ניהול מודלי זיהוי דיבור…';

  @override
  String get dockMenuGroupCloud => 'ענן';

  @override
  String get dockMenuModelDownload => 'הורדה';

  @override
  String get dockMenuModelLoading => 'נטען';

  @override
  String get dockMenuSttLockedReason => 'לא ניתן לשנות במהלך הקלטה';

  @override
  String get dockMenuSearchHint => 'חיפוש…';

  @override
  String get dockMenuSearchNoMatches => 'אין התאמות';

  @override
  String get dockMenuAppliesNextRecording => 'חל החל מההקלטה הבאה';

  @override
  String get dockStopDictation => 'עצירת ההקלטה';

  @override
  String get historyImportAddFiles => 'הוספת קבצים';

  @override
  String historyImportDescription(String formats) {
    return 'תמלול קובצי אודיו ($formats) במכשיר זה. אפשר לגרור קבצים לדף זה או להוסיף אותם.';
  }

  @override
  String get historyImportQueueTitle => 'תור ייבוא';

  @override
  String get historyImportStatusQueued => 'ממתין';

  @override
  String get historyImportStatusCopying => 'בהעתקה';

  @override
  String get historyImportStatusDecoding => 'בפענוח';

  @override
  String get historyImportStatusTranscribing => 'בתמלול';

  @override
  String get historyImportStatusDone => 'הושלם';

  @override
  String get historyImportStatusFailed => 'נכשל';

  @override
  String get historyImportStatusCancelled => 'בוטל';

  @override
  String get historyImportFailureCopy =>
      'לא ניתן להעתיק את הקובץ. בדקו שהקובץ עדיין קיים וניתן לקריאה, ונסו שוב.';

  @override
  String get historyImportFailureUnsupported =>
      'פורמט זה אינו נתמך בפלטפורמה זו. יש להמיר את הקובץ ל-WAV ולייבא אותו שוב.';

  @override
  String get historyImportFailureDecode =>
      'לא ניתן לפענח את הקובץ. ייתכן שהוא פגום או לא שלם. ייבאו עותק אחר או המירו אותו ל-WAV.';

  @override
  String get historyImportFailureInputLimit =>
      'הקובץ גדול מדי או ארוך מ-6 שעות. יש לחלק אותו לקטעים קצרים יותר.';

  @override
  String get historyImportFailureTranscription =>
      'התמלול נכשל. בדקו את זיהוי הדיבור בהגדרות ונסו שוב.';

  @override
  String get historyImportFailureSave =>
      'לא ניתן לשמור את התמלול. בדקו את שטח הדיסק הפנוי ונסו שוב.';

  @override
  String get historyImportRejectedFolder =>
      'לא ניתן לייבא תיקיות. יש לבחור את קובצי האודיו שבתוכן.';

  @override
  String get historyImportRejectedNotFound => 'הקובץ לא נמצא.';

  @override
  String historyImportRejectedType(String formats) {
    return 'לא ניתן לייבא סוג קובץ זה. נתמכים: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'לא ניתן היה לפתוח את חלון בחירת הקבצים. נסו שוב, או גררו את הקבצים לדף זה.';

  @override
  String get historyImportDropHere => 'שחררו כאן קובצי אודיו כדי לתמלל אותם';

  @override
  String get historyImportCancel => 'ביטול הייבוא';

  @override
  String get historyImportRetry => 'ניסיון חוזר לייבוא';

  @override
  String get recoveryOffer =>
      'נמצאה הקלטה שהופסקה. לשחזר את האודיו ולתמלל אותו?';

  @override
  String get recoveryNoAudioKept =>
      'נמצאה הקלטה שהופסקה, אך לא נשמר אודיו מכיוון ששמירת האודיו כבויה.';

  @override
  String get recoveryNoAudioCaptured =>
      'נמצאה הקלטה שהופסקה, אך היא לא מכילה אודיו.';

  @override
  String get recoveryRestore => 'שחזור';

  @override
  String get recoveryDiscard => 'מחיקה';

  @override
  String get recoveryDiscardConfirm => 'לזרוק את ההקלטה הזו?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'ההקלטה שנקטעה הזו תוסר מהמכשיר, יחד עם כל אודיו שנשמר עבורה.';

  @override
  String get recoveryFailed => 'השחזור נכשל. האודיו נשמר, אפשר לנסות שוב.';

  @override
  String recoverySkippedCorrupt(int count) {
    return '$count רשומות שחזור פגומות דולגו ונשארו בדיסק.';
  }

  @override
  String get settingsGroupApp => 'אפליקציה';

  @override
  String get settingsGroupDictation => 'קלט קולי';

  @override
  String get settingsGroupSystem => 'מערכת';

  @override
  String get settingsAreaGeneral => 'כללי';

  @override
  String get settingsAreaAppearance => 'מראה';

  @override
  String get settingsAreaShortcuts => 'קיצורי מקלדת';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'קיצור מקלדת: $combo';
  }

  @override
  String get settingsAreaRecording => 'הקלטה ואודיו';

  @override
  String get settingsAreaSpeech => 'זיהוי דיבור';

  @override
  String get settingsAreaTextInsert => 'טקסט והוספה';

  @override
  String get settingsAreaPrivacy => 'פרטיות ונתונים';

  @override
  String get settingsAreaAdvanced => 'מתקדם';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'מעודכן';

  @override
  String get settingsNavUpdateAvailable => 'עדכון זמין';

  @override
  String get settingsNavStoreUpdates => 'עדכונים דרך החנות';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'בגרסת החנות החנות מספקת את העדכונים. בדיקת עדכונים מתוך האפליקציה אינה זמינה כאן.';

  @override
  String get settingsStoreBetaUnavailable =>
      'גרסאות מקדימות אינן מוצעות בגרסת החנות.';

  @override
  String get settingsStoreCudaUnavailable =>
      'לא זמין בגרסת החנות: הורדות מנהלי התקן מחוץ לחנות אינן מותרות שם.';

  @override
  String get settingsOverlayPreview => 'תצוגה מקדימה של השכבה';

  @override
  String get settingsPreviewTitle => 'תצוגה מקדימה';

  @override
  String get settingsPreviewHint =>
      'כך נראים השכבה והכפתור בזמן הקלטה. השינויים נכנסים לתוקף מיד.';

  @override
  String get settingsPreviewOverlayCaption => 'שכבה';

  @override
  String get settingsOverlayOptionsGroup => 'שכבה';

  @override
  String get settingsOverlayForm => 'צורה';

  @override
  String get settingsOverlayFormSubtitle => 'קפסולה או מלבן עם פינות מעוגלות.';

  @override
  String get settingsOverlayFormPill => 'קפסולה';

  @override
  String get settingsOverlayFormRoundedRect => 'מעוגל';

  @override
  String get settingsOverlayWaveStyle => 'סגנון גל';

  @override
  String get settingsOverlayWaveStyleSubtitle => 'איך הקול שלך מוצג בשכבה.';

  @override
  String get settingsOverlayWaveBars => 'פסים';

  @override
  String get settingsOverlayWaveLine => 'קו';

  @override
  String get settingsOverlayWaveDots => 'נקודות';

  @override
  String get settingsOverlayWaveFluid => 'מתאר נע';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'הקצה מגיב לקול שלך. כבוי כשהפחתת תנועה פעילה.';

  @override
  String get settingsOverlayShowTimer => 'הצג זמן';

  @override
  String get settingsOverlayShowTimerSubtitle => 'מציג את זמן ההקלטה שחלף.';

  @override
  String get settingsOverlayShowCancel => 'סמל ביטול';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'עצירה תמיד גלויה. Esc עדיין מבטל.';

  @override
  String get settingsOverlayOpacity => 'אטימות';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'מוגבהת אוטומטית אם הגל היה חלש מדי.';

  @override
  String get settingsOverlayOpacityFull => '100%';

  @override
  String get settingsOverlayOpacityReduced => '80%';

  @override
  String get settingsOverlayOpacitySubtle => '60%';

  @override
  String get settingsFloatingButtonSize => 'גודל';

  @override
  String get settingsFloatingButtonSizeSubtitle => 'קוטר הכפתור הצף';

  @override
  String get settingsFloatingButtonSizeSmall => 'קטן';

  @override
  String get settingsFloatingButtonSizeMedium => 'בינוני';

  @override
  String get settingsFloatingButtonSizeLarge => 'גדול';

  @override
  String get settingsFloatingButtonShape => 'צורה';

  @override
  String get settingsFloatingButtonShapeSubtitle => 'עיגול או ריבוע מעוגל';

  @override
  String get settingsFloatingButtonShapeRound => 'עגול';

  @override
  String get settingsFloatingButtonShapeSquare => 'ריבוע';

  @override
  String get settingsFloatingButtonRing => 'טבעת הקלטה';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'טבעת צבעונית סביב הכפתור בזמן הקלטה';

  @override
  String get settingsFloatingButtonIdleOpacity => 'אטימות במנוחה';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'כמה בולט הכפתור כשאין הקלטה';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'משותף (צבעים)';

  @override
  String get settingsAreaSmartMode => 'מצב חכם';

  @override
  String get settingsAreaDictionary => 'מילון';

  @override
  String get settingsSearchEmptyHelp => 'חיפוש בעזרה';

  @override
  String get dictionaryTabTerms => 'מונחים';

  @override
  String get dictionaryTabReplacements => 'החלפות';

  @override
  String get dictionaryTabSuggestions => 'הצעות';

  @override
  String get dictionaryTermsEffectPrompt =>
      'מועבר לזיהוי הדיבור כרמז. הזיהוי עשוי להעדיף את צורות הכתיב האלה, אך הוא לא משנה טקסט בעצמו.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'מנוע הזיהוי הפעיל אינו מקבל רמזים. רק החלפות משנות את הטקסט. המונחים שלך נשמרים.';

  @override
  String get dictionaryTermsHelp =>
      'שמות, מונחי מקצוע וראשי תיבות שהזיהוי טועה בהם לעיתים קרובות. הפרד ביניהם בפסיקים או בשורות חדשות.';

  @override
  String get dictionaryReplacementsHelp =>
      'הוסף רק מילים שהזיהוי באמת כותב לא נכון. מילים שזוהו נכון נשארות ללא שינוי.';

  @override
  String get dictionaryTestTitle => 'ניסיון';

  @override
  String get dictionaryTestInputLabel => 'משפט לדוגמה';

  @override
  String get dictionaryTestInputHint => 'כתוב משפט כדי לראות אילו החלפות חלות.';

  @override
  String get dictionaryTestResultLabel => 'תוצאה';

  @override
  String get dictionaryTestNoChange => 'אף החלפה לא חלה.';

  @override
  String get dictionaryCsvTitle => 'ייבוא וייצוא (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'שורה לכל פריט: טריגרים מופרדים ב-$pipe, טקסט ההחלפה, מצב התאמה (exact או fuzzy), סף.';
  }

  @override
  String get dictionaryCsvImport => 'ייבוא CSV';

  @override
  String get dictionaryCsvExport => 'ייצוא CSV';

  @override
  String get dictionaryCsvExportEmpty => 'עדיין אין החלפות לייצוא.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'הקובץ גדול מ-1 MB. פצל אותו לקבצים קטנים יותר.';

  @override
  String get dictionaryCsvImportReadError => 'לא ניתן היה לקרוא את הקובץ.';

  @override
  String get dictionaryCsvImportNothing => 'לא נמצאו פריטים תקינים.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    return '$count שורות דולגו כי הן חסרות או לא תקינות.';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    return 'נקראו רק $count פריטים ראשונים.';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return 'נוספו $added פריטים.';
  }

  @override
  String get dictionaryCsvExportFailed => 'לא ניתן היה לשמור את קובץ ה-CSV.';

  @override
  String dictionaryCsvExportDone(int count) {
    return 'יוצאו $count פריטים.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'שורה $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'חסרות עמודות.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'אין טריגר.';

  @override
  String get dictionaryCsvReasonTriggerTooLong => 'הטריגר ארוך מדי.';

  @override
  String get dictionaryCsvReasonEmptyReplacement => 'אין טקסט החלפה.';

  @override
  String get dictionaryCsvReasonReplacementTooLong => 'טקסט ההחלפה ארוך מדי.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'מצב ההתאמה חייב להיות exact או fuzzy.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'הסף חייב להיות strict, standard, tolerant או מספר בין 0.5 ל-1.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'השורה מכילה תו בקרה או תו עיצוב נסתר, או שבירת שורה.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'יותר מדי טריגרים בשורה אחת (עד $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'בדיקת הפריטים';

  @override
  String get dictionaryDuplicateBadge => 'כפול';

  @override
  String get dictionaryDuplicateHint =>
      'פריט אחר משתמש באותו טריגר. פועל הפריט שמופיע ראשון ברשימה.';

  @override
  String dictionaryUsageCount(int count) {
    return 'בשימוש $count פעמים';
  }

  @override
  String get dictionaryFavouriteLabel => 'מועדף';

  @override
  String dictionarySuggestionsHint(int count) {
    return 'הצעה מופיעה כאשר אותו תיקון מופיע $count פעמים. שום דבר לא נוסף בלי אישורך.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'אין הצעות עדיין';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'אם תתקן את אותה מילה פעמיים, WhisPaste תציע כאן החלפה.';

  @override
  String get dictionarySuggestionAccept => 'אישור';

  @override
  String get dictionarySuggestionReject => 'דחייה';

  @override
  String get dictionarySuggestionAccepted => 'ההחלפה נוספה.';

  @override
  String get dictionarySuggestionRejected => 'ההצעה נדחתה. היא לא תופיע שוב.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'הפריטים שמסומנים \"יתווסף\" יכנסו לרשימה שלך. פריטים קיימים נשארים כמו שהם.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return 'הוספת $count פריטים';
  }

  @override
  String get dictionaryCsvImportEncodingError => 'הקובץ אינו טקסט UTF-8.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'הקובץ בפורמט חבילה שהאפליקציה הזו אינה יכולה לקרוא.';

  @override
  String get dictionaryCsvRefusedType => 'הקובץ אינו חבילת מילון החלפות.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'חבילה: $name (נוצרה ב-$date)';
  }

  @override
  String get dictionaryCsvPackageNone => 'אין פרטי חבילה (קובץ ישן או זר)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'חדשים: $added · כפולים: $duplicates · התנגשויות: $conflicts · הפניות מעגליות: $circular · שגויים: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel => 'כשהטריגר כבר קיים';

  @override
  String get dictionaryCsvStrategySkip => 'לדלג';

  @override
  String get dictionaryCsvStrategyOverwrite => 'לדרוס';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'לשמור את שניהם';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'השורה לא תיובא. הערכים הקיימים נשארים ללא שינוי.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'הטריגר המשותף יוסר מהערך הישן והשורה תתווסף. $changed ערכים קיימים ישתנו או יימחקו.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'השורה תתווסף גם היא. לאותו טריגר ימשיך לחול הערך הקיים שמופיע קודם ברשימה.';

  @override
  String get dictionaryCsvStatusAdded => 'ייתווסף';

  @override
  String get dictionaryCsvStatusDuplicate => 'כבר קיים';

  @override
  String get dictionaryCsvStatusConflictSkipped => 'התנגשות, מדולג';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'התנגשות, מחליף את הטריגר הקיים';

  @override
  String get dictionaryCsvStatusConflictKept => 'התנגשות, מתווספת בנוסף';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'הוחלפה על ידי שורה מאוחרת יותר בקובץ';

  @override
  String get dictionaryCsvStatusCircular => 'הפניה מעגלית, לא מיובאת';

  @override
  String get dictionaryCsvRowWillAdd => 'יתווסף';

  @override
  String get dictionaryCsvRowSkipped => 'כפילות, ידולג';

  @override
  String get dictionaryCsvExportSelectTitle => 'בחרו ערכים לייצוא';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return '$count ערכים לבחירה';
  }

  @override
  String get dictionaryCsvAllPresent => 'כל הערכים כבר קיימים. לא ייכתב דבר.';

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'ייצוא ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'יותר מדי ערכים לקובץ אחד: $count. בחרו פחות (עד 5000 ערכים, מגבלה של 1 MiB).';
  }

  @override
  String get settingsBetaGroupHeading => 'גרסאות מקדימות';

  @override
  String get analyticsWordingTitle => 'ניסוח';

  @override
  String get analyticsWordingPanelTitle => 'מילים: גולמיות מול מעובדות';

  @override
  String get analyticsRawWords => 'מילים גולמיות';

  @override
  String get analyticsRevisedWords => 'מילים מעובדות';

  @override
  String get analyticsTransformActions => 'הקלטות שעובדו בפעולות';

  @override
  String get analyticsCorrectionsTitle => 'תיקונים נפוצים';

  @override
  String get analyticsNoCorrections => 'עדיין לא נרשמו תיקונים.';

  @override
  String get errorNoticeNoModelCause => 'לא מותקן מודל זיהוי דיבור.';

  @override
  String get errorNoticeNoModelNext => 'הורד מודל בהגדרות ונסה שוב.';

  @override
  String get errorNoticeMicCause => 'ל-WhisPaste אין גישה למיקרופון.';

  @override
  String get errorNoticeMicNext => 'אשר גישה בהגדרות המערכת ונסה שוב.';

  @override
  String get errorNoticeTranscribeCause => 'התמלול נכשל.';

  @override
  String get errorNoticeTranscribeNext =>
      'נסה שוב. אם זה חוזר, הפעל מחדש את WhisPaste או בחר מודל אחר בהגדרות.';

  @override
  String get errorNoticeCpuCause => 'לא ניתן היה להשתמש ב-GPU לתמלול הזה.';

  @override
  String get errorNoticeCpuNext =>
      'התמלול רץ במקום זאת על המעבד, וזה איטי יותר. בדוק את האצת ה-GPU בהגדרות.';

  @override
  String get languageMismatchHint => 'השפה שזוהתה אינה תואמת להגדרה שלך.';

  @override
  String get languageMismatchSwitch => 'החלף שפה';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'Parakeet לא יכול לתמלל $language. לעבור ל-Whisper?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'מעבר ל-Whisper';

  @override
  String get titleBarMinimizeLabel => 'מזער חלון';

  @override
  String get titleBarCloseLabel => 'סגור חלון';

  @override
  String get titleBarMaximizeLabel => 'הגדל חלון';

  @override
  String get titleBarRestoreLabel => 'שחזר חלון';

  @override
  String get notificationSmartModeSkippedTitle => 'WhisPaste: Smart Mode דולג';

  @override
  String get notificationHotkeyFallbackTitle => 'WhisPaste: קיצור המקשים תפוס';

  @override
  String get notificationSmartModeSkippedBody =>
      'לא ניתן היה להחיל את העיבוד הנוסף.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'לא נטען מודל טקסט, לכן העיבוד הנוסף דולג.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'העיבוד הנוסף נמשך יותר מדי זמן.';

  @override
  String get notificationSmartModeOutcomePasted => 'הטקסט ללא עריכה הודבק.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'לא ניתן היה לאשר אם הטקסט ללא עריכה הודבק.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'הטקסט ללא עריכה נמצא בלוח, אך לא הודבק.';

  @override
  String get notificationSmartModeOutcomeNone => 'הטקסט ללא עריכה לא הודבק.';

  @override
  String get smartModeNoTextModelHint =>
      'לא הוגדר מודל טקסט – עד אז אפשר לבחור רק „כבוי“.';

  @override
  String get smartModeLoadTextModelAction => 'אין מודל טקסט – טען עכשיו';

  @override
  String get smartModeAddOpenAiKeyAction => 'הוסף מפתח OpenAI';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'הקובץ אינו ייצוא תקין של WhisPaste.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'לא ניתן היה לעבד את הקובץ או את ההגדרות.';

  @override
  String get historyImportAudioLabel => 'שמע';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'מעבר בין יישומים';

  @override
  String get hotkeyConflictNoteQuitApp => 'יציאה מהיישום';

  @override
  String get hotkeyConflictNoteCloseWindow => 'סגירת חלון';

  @override
  String get hotkeyConflictNoteHideApp => 'הסתרת יישום';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'מזעור חלון';

  @override
  String get hotkeyConflictNoteCycleWindows => 'מעבר בין חלונות';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen => 'צילום מסך (מסך מלא)';

  @override
  String get hotkeyConflictNoteScreenshotSelection => 'צילום מסך (בחירה)';

  @override
  String get hotkeyConflictNoteScreenshotRecording => 'צילום מסך/הקלטת מסך';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'בחירת אמוג\'י וסמלים';

  @override
  String get hotkeyConflictNoteForceQuit => 'חלון כפיית יציאה';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'נעילת המחשב';

  @override
  String get hotkeyConflictNoteShowDesktop => 'הצגת/הסתרת שולחן העבודה';

  @override
  String get hotkeyConflictNoteFileExplorer => 'סייר הקבצים';

  @override
  String get hotkeyConflictNoteRunDialog => 'תיבת הרצה';

  @override
  String get hotkeyConflictNoteSettings => 'הגדרות';

  @override
  String get hotkeyConflictNoteSearch => 'חיפוש';

  @override
  String get hotkeyConflictNoteTaskView => 'תצוגת משימות';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch => 'החלפת שפת הקלט';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'הגדלת חלון';

  @override
  String get hotkeyConflictNoteSnapLeft => 'הצמדת חלון לשמאל';

  @override
  String get hotkeyConflictNoteSnapRight => 'הצמדת חלון לימין';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'אפשרויות אבטחה / מנהל המשימות';

  @override
  String get hotkeyConflictNoteTaskManager => 'מנהל המשימות';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde => 'נעילת המסך (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'תיבת הרצה (KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'חלון הניתוק/כיבוי של המערכת';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'פתיחת טרמינל (ברירת המחדל של GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'נעילת המסך (GNOME)';

  @override
  String get hotkeyConflictNoteActivityOverviewKde => 'סקירת פעילויות (KDE)';

  @override
  String get settingsTextProcessingHeading => 'עיבוד טקסט';

  @override
  String get settingsShowNotificationsSubtitle =>
      'מדווח על בעיות, למשל הדבקה אוטומטית חסומה או אות מיקרופון חסר.';

  @override
  String get settingsGainSubtitle =>
      'מגביר את אות המיקרופון לפני ההקלטה. ערכים גבוהים מדי עלולים לעוות את ההקלטה.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'מה קורה לטקסט שזוהה. הדבקה אוטומטית מכניסה אותו ישירות למיקום הסמן.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'השפה שהזיהוי מצפה לה. זיהוי אוטומטי עובד בדרך כלל טוב. שפה קבועה לרוב מדויקת יותר בהקלטות קצרות.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'המפתח האישי שלך של OpenAI. נדרש רק אם אתה משתמש ב-OpenAI לזיהוי או ל-Smart Mode. אודיו וטקסט נשלחים אז ישירות ל-OpenAI ומחויבים על ידה.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'המפתח האישי שלך של Deepgram. נדרש רק אם אתה משתמש ב-Deepgram לזיהוי. האודיו נשלח אז ישירות ל-Deepgram ומחויב על ידה.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'מאפס את כל ההגדרות, מפתחות ה-API והסטטיסטיקות. ההקלטות, ההערות והמודלים נשמרים.';

  @override
  String get settingsFactoryResetSubtitle =>
      'מוחק מיד את כל התמלולים, הפתקים, קבצי האודיו, המילון, הקטעים, המודלים, היומנים וההגדרות במכשיר הזה. אי אפשר לבטל.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'קיצור גלובלי מתחיל הקלטה מכל אפליקציה. כשהוא כבוי, WhisPaste מתעלם ממנו.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'בודק מיד אם יש גרסה חדשה. ההתקנה מתבצעת רק לאחר אישורך.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'כמה תמלולים נשמרים לפני שהישנים יועברו לאשפה. באשפה התמלולים נמחקים לצמיתות אחרי הזמן שנבחר. מועדפים נשמרים תמיד. קבצי אודיו שנשמרו נמחקים לכל היותר 30 יום לאחר ההקלטה, ללא קשר להגדרה זו.';

  @override
  String get smartModeTargetLanguageSubtitle => 'רק לפריסט תרגום.';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'הקובץ גדול מדי לייבוא (הגבול: כ-5 MB). בחר קובץ הגדרות שייצא WhisPaste.';

  @override
  String get settingsSearchKeywordsInterface =>
      'ערכת נושא, מצב כהה, מצב בהיר, מראה, שפה, הפעלה אוטומטית, מזערי, התראות, שפת המערכת, לוח, פאנל צד, הדבקה מהירה, מיקום הלוח, קצה המסך, מגש, מעבד, מחוון, שורת מצב';

  @override
  String get settingsSearchKeywordsStt =>
      'מודל, Whisper, איכות, תמלול, זיהוי דיבור, מקומי, במכשיר, ענן, שפה, זמן המתנה, אוצר מילים, מילון, מילים, STT, זיהוי דיבור, Deepgram, OpenAI, מפתח API, מספרים בלבד, פיסוק, מנוע, שתיקה, חיתוך, מילות מילוי, שורה חדשה, פסקה, שורה, GPU, גרפיקה, האצה, מעבד, חומרה';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'פריסט, ניקוי, קיצור, תרגום, Gemma, מודל, מודל טקסט, הורדה, עיבוד לאחר מכן, ליטוש, עריכת בחירה, בחירה, טקסט מסומן, כתיבה מחדש';

  @override
  String get settingsSearchKeywordsAudio =>
      'מיקרופון, הקלטה, הגברה, עוצמה, לחץ לדבר, החזק להקלטה, כניסה';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'לוח הגזירים, הדבקה, הדבקה אוטומטית, העתקה, פעולה, פלט, לא לעשות כלום, רשימת חסימה, שחזור לוח ההעתקה, השארת התמלול, תוכן קודם';

  @override
  String get settingsSearchKeywordsOverlay =>
      'שכבה, צף, תצוגה, סטטוס, מיקום, חלון, מרכז למעלה, מרכז למטה, מיקום התחלתי, תמלול חי';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'רקע, צבע, ים, גרפיט, קרחון, זכוכית, אטום, ענבר';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'גל, גלים, צבע, ציאן, סגול, ניטרלי, אנימציה, ענבר';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'כפתור, צף, תמיד גלוי, כפתור הקלטה, גישה מהירה';

  @override
  String get settingsSearchKeywordsHotkey =>
      'קיצור מקלדת, שילוב מקשים, קיצור גלובלי, מקש גלובלי, קיצור, מקלדת, מקשים, הקצאת מקשים';

  @override
  String get settingsSearchKeywordsSound =>
      'צליל, טון, שמע, אות, ביפ, עוצמה, צליל הקלטה, התראה, צליל סיום, רמז';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'בטיחות, שתיקה, עצירה אוטומטית, זמן המתנה, זמן המתנה למיקרופון, זיהוי שתיקה, הגנה, מיקרופון ללא אות, משך מקסימלי';

  @override
  String get settingsSearchKeywordsHistory =>
      'הקלטות, פריטים, אשפה, ניקוי, שמירה, מקסימום, מחיקה אוטומטית, מחיקה, אחסון, הסתרה, פרטיות, PIN, נעילה, נעל, הגנה, היסטוריה';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'ייצוא, ייבוא, העברה, הזזה, גיבוי, שחזור, החלפת מכשיר, ניידות, מחשב חדש, גיבוי אוטומטי, שמירה אוטומטית';

  @override
  String get settingsSearchKeywordsAdvanced =>
      'איפוס, ברירות מחדל, איפוס למפעל';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'אוטומציה, API, סקריפט, טוקן, Bearer, HTTP, localhost, פורט';

  @override
  String get settingsSearchKeywordsUpdates =>
      'עדכון, בטא, ערוץ, ערוץ שחרור, גרסה מקדימה, בדיקה, אוטומטי, גרסה חדשה, יציב, גרסה';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'היכרות, התחלה, הגדרה ראשונית, הגדרה, סיור, טור, שוב, מחדש, צעדים ראשונים';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'דירוג, לדרג, כוכבים, חנות, לתמוך, ביקורת';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'פרטיות, אנליטיקה, סטטיסטיקה, מעקב, אנונימי, דיווחי שגיאות, דיווחי קריסה, נתוני שימוש, נתונים, שיתוף, הסכמה, שמירת הקלטות, הקלטות אחרונות';

  @override
  String get manualNoticeLabel => 'הודעה שמוצגת באפליקציה';

  @override
  String get manualC01Title => 'תחילת העבודה';

  @override
  String get manualC01S1Heading => 'הגדרה בהפעלה הראשונה';

  @override
  String get manualC01S1B1 =>
      'בהפעלה הראשונה, WhisPaste מוביל אותך דרך ההגדרה. אפשר לחזור לכל שלב, וכל דבר אפשר לשנות אחר כך בהגדרות.';

  @override
  String get manualC01S1B2I1 => 'ברוכים הבאים: סקירה קצרה של WhisPaste.';

  @override
  String get manualC01S1B2I2 => 'פרטיות: מה נשאר במכשיר שלך.';

  @override
  String get manualC01S1B2I3 =>
      'מודל זיהוי דיבור: בוחרים מודל ומורידים אותו. אם כבר שמור מפתח API של ספק ענן, אפשר לבחור בספק הזה במקום.';

  @override
  String get manualC01S1B2I4 => 'הקיצור: קובעים את קיצור המקלדת שמתחיל הקלטה.';

  @override
  String get manualC01S1B2I5 =>
      'מראה: הפעלה או כיבוי של הפעלה עם כניסה למערכת.';

  @override
  String manualC01S1B2I6(String k1) {
    return '$k1: האם הטקסט מודבק אוטומטית. בלינוקס שלב זה מדולג.';
  }

  @override
  String get manualC01S1B2I7 =>
      'ניסיון: הקלטת ניסיון, ואז מתחילים. בלי מודל זיהוי דיבור או ספק ענן נבחר עם מפתח API, הסיום נשאר נעול.';

  @override
  String get manualC01S2Heading => 'דרישות מערכת';

  @override
  String manualC01S2B1(String ram) {
    return 'WhisPaste דורש מכשיר עם לפחות $ram זיכרון (RAM). במכשירים עם פחות מכך WhisPaste מציג הודעה בלבד במקום האפליקציה.';
  }

  @override
  String get manualC01S2B2 =>
      'כדי להקליט צריך מיקרופון. בהגדרה הראשונית אפשר להמשיך בלעדיו, אבל להקליט אפשר רק כשמיקרופון מחובר.';

  @override
  String get manualC01S3Heading => 'הורדת מודל זיהוי הדיבור';

  @override
  String get manualC01S3B1 =>
      'WhisPaste ממיר את הדיבור שלך לטקסט על המכשיר שלך, או דרך ספק ענן עם המפתח שלך. על המכשיר צריך מודל. את ההורדה מתחיל בעצמך; היא אינה מתחילה אוטומטית.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: מהיר, לשפות אירופיות, כ-$k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: כל 99 השפות, מודלים מכ-$k1 עד כ-$k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'המודלים שמורים בתיקיית הנתונים של האפליקציה, בתת-התיקייה $k1.';
  }

  @override
  String get manualC01S3B4 =>
      'מודל Whisper נשאר טעון לאחר הכתבה, כדי שההפעלה הבאה תהיה מהירה יותר. תחת „להשאיר את המודל טעון” בקטע זיהוי הדיבור בוחרים: „תמיד” (ברירת מחדל) חוסך זמן המתנה, אך דורש זיכרון לאורך כל הזמן. „אוטומטי” משאיר את המודל טעון אם יש במחשב מספיק זיכרון, אחרת הוא מתפרק אחרי 5 דקות. „אחרי זמן המתנה” מפרק אותו אחרי הזמן שתקבע. כשהזיכרון קצר, WhisPaste מפריק את המודל אוטומטית וטוען אותו שוב כשיש מקום.';

  @override
  String get manualC01S3B3 =>
      'בקטע זיהוי דיבור, הפריט „הרץ בדיקה מחדש“ מודד באיזו מהירות רץ כל רמה מותקנת במחשב שלך. התוצאות מראות על כרטיסי המודלים כמה זמן נוסף לוקחת כל רמה, וקובעות את רמת Whisper המומלצת. לשפות אירופיות WhisPaste ממליץ על Parakeet במקום. הבדיקה לא מתחילה במהלך הקלטה.';

  @override
  String get manualC02Title => 'הקלטה והדבקה';

  @override
  String get manualC02S1Heading => 'מקש הקיצור';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'הקיצור הוא צירוף מקשים שפועל בכל תוכנה. ברירת המחדל: $k2 ב-Windows וב-Linux, $k3 ב-Mac. אפשר לשנות אותו בהגדרות, תחת קיצורי מקלדת.';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'אם תוכנה אחרת כבר משתמשת בצירוף, WhisPaste משתמש במקומו ב-$k2 עבור הקיצור (ב-Mac: $k3). שאר קיצורי הדרך נשארים כבויים עד שתקבע צירוף פנוי.';
  }

  @override
  String get manualC02S2Heading => 'החזקה או החלפה';

  @override
  String get manualC02S2B1 =>
      'בהגדרות, תחת קיצורי מקלדת, בוחרים איך פועל הקיצור:';

  @override
  String get manualC02S2B2I1 =>
      '„החזק להקלטה“ פעיל: מחזיקים את הקיצור, מדברים ומשחררים. בשחרור ההקלטה מסתיימת.';

  @override
  String get manualC02S2B2I2 =>
      'כבוי: לחיצה אחת מתחילה את ההקלטה, לחיצה שנייה מסיימת.';

  @override
  String get manualC02S3Heading => 'לראות את ההקלטה';

  @override
  String get manualC02S3B1 =>
      'הדוק בתחתית החלון הראשי מציג את המצב הנוכחי. בזמן הקלטה, הכפתור מתחלף ל„עצירת ההקלטה“, ואזור המצב מציג את השלב הנוכחי. הדוק תמיד מוצג ואי אפשר לכבות אותו.';

  @override
  String get manualC02S3B3 =>
      'בחלון צר, הדוק מעביר אמצעי שליטה פחות חשובים לתפריט „עוד“, ובהם מקש הקיצור, הרמז ל-Auto-Paste והודעת העדכון. הכול נשאר זמין שם.';

  @override
  String get manualC02S3B2I1 =>
      '„שכבת הקלטה צפה“ על „צף (תמיד גלוי)“: שכבת צורת גל קטנה מעל כל התוכניות. ברירת מחדל: כבוי.';

  @override
  String get manualC02S3B2I2 =>
      '„כפתור צף“: כפתור שמקליטים בלחיצה. ברירת מחדל: כבוי. ב-Linux עם Wayland, שולחן העבודה עשוי להגביל את המיקום ואת השארת הכפתור מעל החלונות.';

  @override
  String get manualC02S4Heading => 'הדבקה אחרי ההקלטה';

  @override
  String get manualC02S4B1 => 'תחת „אחרי תמלול“ בוחרים מה קורה אחרי כל הקלטה:';

  @override
  String get manualC02S4B2I1 =>
      '„העתק ללוח“ (ברירת מחדל): הטקסט נכנס ללוח הגזירים, ואתה מדביק אותו בעצמך.';

  @override
  String get manualC02S4B2I2 =>
      '„הדבק אוטומטי במקום הסמן“: WhisPaste מדביק את הטקסט במקום הסמן.';

  @override
  String get manualC02S4B2I3 => '„העתק + הדבק אוטומטי“: שניהם.';

  @override
  String get manualC02S4B2I4 =>
      '„לא לעשות כלום“: WhisPaste לא מעתיק ולא מדביק את הטקסט.';

  @override
  String get manualC02S4B3 =>
      'לאפליקציות ב„רשימת חסימה להדבקה אוטומטית“ אין הדבקה אוטומטית. הטקסט נכנס אז ללוח ההעתקה, או רק להקלטות אם „להעתיק ללוח ההעתקה באפליקציות חסומות“ כבוי. הזן אפליקציה אחת בכל שורה בשדה. אם הדבקה נכשלת, WhisPaste מציג הודעה והטקסט נשאר בלוח ההעתקה.';

  @override
  String get manualC02S4B4 =>
      'ב-Windows הדבקה אוטומטית לא פועלת בתוכניות שרצות עם הרשאות מנהל.';

  @override
  String get manualC02S4B5 =>
      'בלינוקס, WhisPaste מסמן את הטקסט ברמז שרק Klipper של KDE מכבד. מנהלי לוח גזירים אחרים, כמו GPaste או CopyQ, שומרים בכל זאת את התמלולים: כבו שם את הרישום של לוח הגזירים או מחקו את הפריט.';

  @override
  String get manualC02S4B6 =>
      'אחרי ההדבקה WhisPaste מחזיר בדרך כלל את מה שהיה בלוח ההעתקה קודם. תחת „לוח ההעתקה אחרי ההדבקה“ אפשר לבחור „להשאיר את התמלול“: אז הטקסט המתומלל נשאר בלוח ההעתקה. אם ההדבקה לא אושרה בזמן, התמלול נשאר שם תמיד. אם macOS מסרב לגישה ללוח ההעתקה, WhisPaste לא יכול לשמור את התוכן הקודם ולא מחזיר אותו; התמלול נשאר אז בלוח ההעתקה. פעם אחת מופיעה הודעה עם הדרך להגדרות המערכת.';

  @override
  String get manualC03Title => 'פתק מהיר';

  @override
  String get manualC03S1Heading => 'מה הפתק המהיר עושה';

  @override
  String get manualC03S1B1 =>
      'הפתק המהיר הוא פתק ש-WhisPaste מוסיף אליו הקלטות חדשות. כך אוספים מחשבות או רשימה בלי ליצור פתק חדש בכל פעם.';

  @override
  String get manualC03S1B2 =>
      'אם עוד אין פתק מסומן, WhisPaste יוצר פתק בפעם הראשונה ומסמן אותו.';

  @override
  String get manualC03S2Heading => 'הגדרה';

  @override
  String get manualC03S2B1I1 =>
      'פתח את הפתק באזור הפתקים והפעל „הפוך לפתק המהיר שאליו הקיצור מוסיף טקסט“. „פתק מהיר — הסר את הסימון“ מסיר את הסימון.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'מפעילים את הקיצור לפתק מהיר בהגדרות, תחת קיצורי מקלדת. הוא כבוי כברירת מחדל. המקש הוא $k1 ($k2, וב-Mac $k3).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'מה Smart Mode עושה';

  @override
  String manualC04S1B1(String k1) {
    return '$k1 עורך את הטקסט שזוהה לפני ההדבקה. הוא כבוי כברירת מחדל, ומפעילים אותו בעצמך.';
  }

  @override
  String get manualC04S1B2 =>
      'כברירת מחדל העיבוד רץ במכשיר שלך („מקומי במכשיר“). עם „OpenAI“ הטקסט נשלח ל-OpenAI. הפרטים בפרק הפרטיות.';

  @override
  String get manualC04S2Heading => 'פריסטים';

  @override
  String get manualC04S2B1 => 'פריסט קובע מה קורה לטקסט:';

  @override
  String get manualC04S2B2I1 => '„כבוי“: בלי עיבוד נוסף, הטקסט נשאר כפי שזוהה.';

  @override
  String get manualC04S2B2I2 =>
      '„ניקוי“: מסיר מילות מילוי ומתקן פיסוק והאותיות הגדולות, בלי לשנות את הניסוח, המשמעות או השפה.';

  @override
  String get manualC04S2B2I3 =>
      '„תמצות“: מסיר חזרות ומילות מילוי ושומר על כל העובדות החשובות ועל השפה.';

  @override
  String get manualC04S2B2I4 => '„תרגום“: מתרגם את הטקסט לשפת היעד שבחרת.';

  @override
  String get manualC04S3Heading => 'שפת יעד וקיצור';

  @override
  String get manualC04S3B1 =>
      'עבור „תרגום“ בוחרים שפת יעד: גרמנית, אנגלית, ספרדית, צרפתית, פורטוגזית, מנדרינית או רוסית. ברירת המחדל היא אנגלית.';

  @override
  String manualC04S3B2(String k1) {
    return 'קיצור נפרד עבור $k1 כבוי כברירת מחדל. הוא משתמש בפריסט ובשפת היעד מההגדרות.';
  }

  @override
  String get manualC04S4Heading => 'משאבים';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'הגרסה המקומית מורידה מודל טקסט של כ-$size. אם למכשיר יש פחות מ-$ram RAM, WhisPaste מזהיר לפני ההורדה, אבל אפשר להוריד בכל זאת. בזמן פעולה מודל הטקסט צורך עוד 4 עד 5 GB RAM.';
  }

  @override
  String get manualC04S4B2 =>
      'כל עוד לא הוגדר מודל טקסט (מקומי שלא הורד, או OpenAI ללא מפתח), כל הפריסטים מלבד „כבוי“ נעולים. התפריט בדוק וההגדרות מציינים את הסיבה ומובילים להורדה או להזנת המפתח. אם העיבוד הנוסף נכשל בכל זאת, WhisPaste מדווח על כך ומציין אם הטקסט ללא עריכה הודבק או נמצא רק בלוח.';

  @override
  String get manualC05Title => 'מילון';

  @override
  String get manualC05S1Heading => 'איך החלפות עובדות';

  @override
  String get manualC05S1B1 =>
      'החלפה מחליפה אוטומטית מילים או ביטויים מסוימים בטקסט אחר, בכל הקלטה.';

  @override
  String get manualC05S1B2 =>
      'לכל החלפה יש ביטוי מפעיל אחד או יותר, כלומר הביטויים לזיהוי, והטקסט החדש. מזינים כמה ביטויים מפעילים לאותו טקסט תחת „ביטויים מפעילים“.';

  @override
  String get manualC05S2Heading => 'התאמה';

  @override
  String get manualC05S2B1I1 => 'מדויקת: מוחלפת רק הכתיבה הזהה לחלוטין.';

  @override
  String get manualC05S2B1I2 =>
      'דומה: מוחלפות גם כתיבות קצת שונות. זה חל רק על ביטויים מפעילים של לפחות 4 תווים.';

  @override
  String get manualC05S2B1I3 =>
      'סבילות (קפדנית, רגילה או סלחנית): נקבעת לכל פריט בנפרד, לא לכולם יחד.';

  @override
  String get manualC05S3Heading => 'ייבוא וייצוא (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'אפשר לגבות או להעביר את ההחלפות כקובץ CSV. לקובץ העמודות $k1. מפרידים בין כמה ביטויים מפעילים באמצעות $k2. הקובץ יכול להיות עד $k3 ועד $k4 שורות.';
  }

  @override
  String get manualC05S3B2 =>
      'ייבוא וייצוא נמצאים בתפריט עוד (⋯) מעל הרשימה. שדה הבדיקה נפתח גם הוא מאותו תפריט.';

  @override
  String get manualC06Title => 'קטעים';

  @override
  String get manualC06S1Heading => 'מה הם קטעים';

  @override
  String get manualC06S1B1 =>
      'קטע הוא בלוק טקסט שמכניסים בעזרת מילת הפעלה או קיצור, למשל חתימה או תשובה סטנדרטית.';

  @override
  String get manualC06S1B2I1 => '„סטטי“: הטקסט מוכנס בדיוק כפי ששמרת אותו.';

  @override
  String get manualC06S1B2I2 =>
      '„אינטראקטיבי“: WhisPaste מבקש שדות בזה אחר זה באמצעות הקלטה, ומכניס אותם לתבנית שלך.';

  @override
  String get manualC06S2Heading => 'פתיחת בוחר הקטעים';

  @override
  String get manualC06S2B1 => 'יש שתי דרכים לפתוח את הבוחר:';

  @override
  String get manualC06S2B2I1 =>
      'עם מילת ההפעלה של הבוחר: אומרים רק את המילה הזו. היא נחשבת רק אם כל ההקלטה היא בדיוק המילה הזו. מגדירים אותה בהגדרות, בקטע קיצורי מקלדת, בקבוצה פתקים וקטעים, מתחת לקיצור הבוחר; השאר ריק כדי לכבות את הבוחר.';

  @override
  String get manualC06S2B2I2 =>
      'עם הקיצור של הבוחר: כבוי כברירת מחדל; מפעילים אותו תחת „קיצור לבוחר“.';

  @override
  String get manualC06S3Heading => 'יצירת קטע';

  @override
  String get manualC06S3B1I1 =>
      'יוצרים קטע עם „הוסף“ ובוחרים „סטטי“ או „אינטראקטיבי“.';

  @override
  String manualC06S3B1I2(String k1) {
    return 'ב„אינטראקטיבי“ מגדירים את השדות וכותבים את התבנית. מציבים סמני מיקום בסוגריים מסולסלים כפולים, למשל $k1.';
  }

  @override
  String get manualC07Title => 'פתקים';

  @override
  String get manualC07S1Heading => 'עבודה עם פתקים';

  @override
  String get manualC07S1B1 =>
      'באזור הפתקים אוספים טקסט, למשל רעיונות או מחקר. כשמשתמשים בפתק המהיר, ההקלטות נכנסות ישר לפתק.';

  @override
  String get manualC07S1B2I1 => '„סמן כמועדף“ מבליט פתק.';

  @override
  String get manualC07S1B2I2 => '„הוסף תגית“ משייך פתק לקטגוריה.';

  @override
  String get manualC07S2Heading => 'אשפה';

  @override
  String get manualC07S2B1 =>
      '„העבר לאשפה“ מעביר פתק לאשפה. הוא נשאר שם עד שמוחקים אותו סופית. האשפה אינה מתרוקנת אוטומטית.';

  @override
  String get manualC07S2B2I1 => '„מחק לצמיתות“ מסיר את הפתק מהאשפה.';

  @override
  String get manualC07S3Heading => 'פתק מהיר';

  @override
  String get manualC07S3B1 =>
      'באזור הפתקים רואים איזה פתק הוא הפתק המהיר. הפרטים בפרק הפתק המהיר.';

  @override
  String get manualC07S4Heading => 'תמונות ופרטיות';

  @override
  String get manualC07S4B1 =>
      'בהוספת תמונה, WhisPaste מסירה מטא-נתונים כמו מיקום (GPS), נתוני מצלמה ומידע EXIF, XMP ו-IPTC. נשמרת רק הגרסה הנקייה.';

  @override
  String get notesPinGateTitle => 'ההערות נעולות';

  @override
  String get notesPinGateHint => 'הזן את קוד ה-PIN כדי להציג את ההערות שלך.';

  @override
  String get manualC08Title => 'הקלטות';

  @override
  String get manualC08S1Heading => 'מה יש בהקלטות';

  @override
  String get manualC08S1B1 =>
      'בהקלטות מופיע כל פריט: הטקסט שזוהה, עם התאריך. אם נשמר אודיו, קובץ האודיו שייך לפריט הזה.';

  @override
  String get manualC08S2Heading => 'חיפוש וסינון';

  @override
  String manualC08S2B1I1(String k1) {
    return 'הקלד $k1 כדי לסנן לפי תגיות.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'הקלד $k1 ושפה כדי לסנן לפי שפה.';
  }

  @override
  String get manualC08S2B1I3 => 'או פשוט הקלד מילת מפתח.';

  @override
  String get manualC08S2B1I4 =>
      'מעל הרשימה נמצאים המסננים „מועדפים“, „בארכיון“, „אשפה“ ו„הכל“.';

  @override
  String get manualC08S3Heading => 'ניהול פריטים';

  @override
  String get manualC08S3B1I1 => '„העתק טקסט“ מעתיק שוב את הטקסט ללוח.';

  @override
  String get manualC08S3B1I2 =>
      '„הוסף למועדפים“ מצמיד פריט למעלה. „הסר ממועדפים“ מבטל את זה.';

  @override
  String get manualC08S3B1I3 =>
      '„ארכיון“ מוציא פריט מהרשימה הראשית בלי למחוק אותו.';

  @override
  String get manualC08S3B1I4 =>
      '„שכפל“, „מזג“ (כמה פריטים לאחד) ו„בחר כמה פריטים“ עוזרים לסדר.';

  @override
  String get manualC08S3B1I5 =>
      '„הוסף הערה“ ו„הוסף תגית…“ מוסיפים פרטים לפריט.';

  @override
  String get manualC08S4Heading => 'הערה קולית';

  @override
  String get manualC08S4B1 =>
      'מפעילים הערה קולית על הפריט. אומרים „tag: שם“ כדי להגדיר תגית, או „correct: טקסט“ כדי להחליף את הטקסט של הפריט.';

  @override
  String get manualC08S4B2 =>
      'תיקון מחליף את כל הטקסט של הפריט, לא רק מילה אחת. „korrektur: טקסט“ פועל באותו אופן. מיד אחר כך אפשר לבטל את השינוי מתוך ההודעה.';

  @override
  String get manualC08S5Heading => 'הגנת PIN';

  @override
  String get manualC08S5B1 =>
      'עם „הגנת PIN“ נדרש PIN לפני הצגת ההקלטות. זה חל גם על הפאנל הצדדי, על תפריט הכפתור הצף ועל ממשק ה-API לאוטומציה. ה-PIN מונע מאחרים לצפות בתמלולים בקלות, אבל אינו מצפין אותם. גם ההערות נעולות באותו אופן. כשמוגדר PIN, תפריט מגש המערכת מציג את ההקלטות האחרונות רק עם השעה ומספר המילים, בלי תחילת הטקסט.';

  @override
  String get manualC08S5B2 =>
      'קוד PIN ששכחת אינו ניתן לשחזור. לאיפוס נמחקים מיד כל התמלולים וקובצי השמע השמורים (כולל הארכיון וסל המחזור), כל ההערות עם הגרסאות וכל תמונות ההערות. ההגדרות, קטעי הטקסט וההחלפות נשמרים.';

  @override
  String get manualC08S5B3 =>
      'בזמן שההקלטות נעולות בקוד PIN, לשונית הלוח בפאנל הצדדי אינה מציגה טקסט שהועתק ואינה מדביקה אותו. הטקסט חוזר להופיע לאחר ביטול הנעילה.';

  @override
  String get manualC08S6Heading => 'ריקון אוטומטי';

  @override
  String get manualC08S6B1 =>
      'תחת „מחק אשפה אוטומטית אחרי“ קובעים כמה זמן פריטים שנמחקו נשארים באשפה לפני שהם מוסרים אוטומטית.';

  @override
  String get manualC09Title => 'ייבוא קובצי אודיו';

  @override
  String get manualC09S1Heading => 'תמלול קובצי אודיו';

  @override
  String manualC09S1B1(String k1) {
    return 'אפשר לתמלל קובצי אודיו קיימים. בוחרים „$k1“ ובוחרים את הקובץ.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'בנוסף ל-$k1, אפשר לייבא פורמטים נוספים לפי המערכת: ב-Mac $k2, ב-Linux $k3, ב-Windows $k4.';
  }

  @override
  String get manualC09S2Heading => 'מגבלות';

  @override
  String get manualC09S2B2 =>
      'מה לעשות: לחלק את ההקלטה לחלקים קצרים ולייבא אותם אחד אחד.';

  @override
  String get manualC09S3Heading => 'שגיאות ייבוא';

  @override
  String manualC09S3B2(String k1) {
    return 'מה לעשות: לנסות שוב. אם זה לא עוזר, להפעיל מחדש את WhisPaste או לבחור מודל אחר תחת $k1.';
  }

  @override
  String get manualC10Title => 'סטטיסטיקה';

  @override
  String get manualC10S1Heading => 'האזורים';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'בסטטיסטיקה שלושה אזורים: $k1, $k2 ו-$k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'עם $k1 ו-$k2 בוחרים את טווח הזמן.';
  }

  @override
  String get manualC10S2Heading => 'מה המספרים אומרים';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 ו-$k2 סופרים את ההקלטות שלך ואת משך ההקלטה.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 היא הערכה גסה: WhisPaste סופר שני שלישים מזמן ההקלטה כחסכון, כי דיבור בדרך כלל מהיר יותר מהקלדה. זו אינה מדידה.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: הקלטות מקומיות חוסכות עלויות ענן. WhisPaste מעריך זאת ב-$k2 לדקה, תעריף ייחוס קבוע.';
  }

  @override
  String get manualC10S3Heading => 'איפוס';

  @override
  String manualC10S3B1(String k1) {
    return '„$k1“ מוחק את כל נתוני הסטטיסטיקה. WhisPaste שואל לפני כן, ואי אפשר לבטל את זה.';
  }

  @override
  String get manualC11Title => 'הגדרות';

  @override
  String get manualC11S1Heading => 'החלקים';

  @override
  String get manualC11S1B1 => 'ההגדרות מחולקות לחלקים. החשובים ביותר:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: המראה של האפליקציה.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: מודל ושפת זיהוי.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: מיקרופון ועוצמה.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: פריסט, שפת יעד וספק.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: מה קורה אחרי הקלטה.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: קיצורים.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: משך השמירה באשפה.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: ייצוא, ייבוא וגיבוי אוטומטי.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: ממשק API מקומי וחיבורי אירועים לתוכניות במחשב הזה.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: אפשרויות נוספות, כמו איפוס.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: גרסה, בדיקת עדכונים, קישורים ורישיונות.';
  }

  @override
  String get manualC11S2Heading => 'גיבוי ואיפוס';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 שומר את ההגדרות אוטומטית אחרי שינויים. חמשת הקבצים האחרונים נשמרים. כבוי כברירת מחדל.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 מוחק מיד את כל התמלולים, קבצי האודיו וההגדרות ומאפס את WhisPaste. קרא את האישור בעיון לפני שתאשר.';
  }

  @override
  String get manualC12Title => 'פרטיות ושימוש לא מקוון';

  @override
  String get manualC12S1Heading => 'מה נשאר במכשיר שלך';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'כברירת מחדל זיהוי הדיבור רץ במכשיר שלך. אודיו נשלח לשירות ענן רק אם בוחרים בספק ענן באופן פעיל. התמלולים נשמרים במסד נתונים מקומי במכשיר שלך, וקבצי האודיו השמורים — כקבצים לצידו. האודיו של $count ההקלטות האחרונות נשמר רק כאשר „$k1“ פעיל, למשך $days ימים לכל היותר.';
  }

  @override
  String get manualC12S1B2 =>
      'בדיקת העדכונים שואלת את GitHub אם יש גרסאות חדשות. משוב נשלח רק כשלוחצים על שליחה.';

  @override
  String get manualC12S1B3 =>
      'אם תמלול נכשל כי השרת או החיבור אינם זמינים, האודיו של ההקלטה נשמר עד 24 שעות כדי שתוכל לנסות שוב מהודעת השגיאה או בפרטיות. זה חל גם כששמירת האודיו כבויה. אם היא דלוקה, חלה שמירה רגילה.';

  @override
  String get manualC12S2Heading => 'ספקי ענן';

  @override
  String manualC12S2B1(String k1) {
    return 'הספקים OpenAI ו-Deepgram צריכים מפתח API משלך. מזינים אותו תחת $k1.';
  }

  @override
  String get manualC12S3Heading => 'סטטיסטיקות שימוש ודיווחי שגיאות';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'שתי אפשרויות פעילות כברירת מחדל: $k1 ו-$k2. אפשר לכבות את שתיהן ב-$k3.';
  }

  @override
  String get manualC13Title => 'חומרה וביצועים';

  @override
  String get manualC13S1Heading => 'זיכרון';

  @override
  String manualC13S1B1(String k1) {
    return 'WhisPaste ממליץ על לפחות $k1 זיכרון. עם פחות מזה האפליקציה נפתחת בכל זאת ומציעה את מודל הדיבור “מהיר”.';
  }

  @override
  String get manualC13S2Heading => 'כרטיס מסך';

  @override
  String get manualC13S2B1 =>
      'WhisPaste משתמש בכרטיס המסך כשהוא יכול להאיץ את זיהוי הדיבור:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, ממשק הגרפיקה של Apple.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 ו-$k2 עם גרפיקה של AMD או Intel: $k3, ממשק גרפי נפוץ.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'כרטיסי NVIDIA משתמשים גם ב-$k1. עם חבילת CUDA האופציונלית, הזיהוי משתמש גם ב-$k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'בלי כרטיס מסך מתאים, WhisPaste מחשב במעבד ($k1). זה איטי יותר.';
  }

  @override
  String get manualC13S3Heading => 'חבילת CUDA';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'חבילת CUDA היא תוספת אופציונלית לכרטיסי NVIDIA, לפי האפליקציה ל-$k1 ול-$k2. היא זמינה ל-$k3 ול-$k4 (x64). מפעילים אותה תחת $k5.';
  }

  @override
  String get manualC13S3B2 => 'ההורדה חד-פעמית. האפליקציה מציגה את הגודל.';

  @override
  String get manualC13S3B3 =>
      'החבילה כוללת רכיבים של NVIDIA. לפני ההורדה הראשונה מאשרים את הרישיון של NVIDIA ל-CUDA (גרסה 2026-01-26); האישור חל על ההתקנה הזו. בלי אישור תקף השורה מציגה „נדרש אישור“, ו-WhisPaste משתמש ב-Vulkan או במעבד עד לאישור. אם נוסח הרישיון או החבילה ישתנו, ישאלו שוב.';

  @override
  String get manualC13S4Heading => 'האצה גרפית';

  @override
  String manualC13S4B1(String k1) {
    return 'תחת $k1 בוחרים אם WhisPaste משתמש בכרטיס המסך. רק במעבד בדרך כלל איטי יותר.';
  }

  @override
  String get manualC13S5Heading => 'מודלים וגודל';

  @override
  String get manualC13S5B1 =>
      'מודלי Whisper זמינים בשלוש רמות: מהיר, מאוזן ומדויק. הרמות המדויקות יותר בדרך כלל מזהות טוב יותר, אבל דורשות זמן עיבוד רב יותר.';

  @override
  String get manualC14Title => 'פתרון בעיות';

  @override
  String get manualC14S1Heading => 'איך לקרוא את הדף הזה';

  @override
  String get manualC14S1B1 =>
      'כל חלק מתחיל בהודעה ש-WhisPaste מציג. הניסוח הוא הטקסט המקורי של האפליקציה. מתחתיו מופיעים הסיבה והצעד הבא.';

  @override
  String get manualC14S2Heading => 'אין גישה למיקרופון';

  @override
  String get manualC14S2B2 =>
      'מה לעשות: לאשר ל-WhisPaste גישה למיקרופון בהגדרות המערכת. אחר כך להתחיל הקלטה מחדש.';

  @override
  String get manualC14S3Heading => 'לא נמצא מיקרופון';

  @override
  String manualC14S3B2(String k1) {
    return 'מה לעשות: לחבר מיקרופון ולבחור אותו תחת $k1.';
  }

  @override
  String get manualC14S4Heading => 'לא נקלט אודיו';

  @override
  String manualC14S4B2(String k1) {
    return 'מה לעשות: לבדוק שנבחר המיקרופון הנכון ושה-$k1 לא על אפס. אחר כך להקליט שוב.';
  }

  @override
  String get manualC14S5Heading => 'אין מודל זיהוי דיבור';

  @override
  String manualC14S5B2(String k1) {
    return 'מה לעשות: להוריד מודל תחת $k1 ולנסות שוב.';
  }

  @override
  String get manualC14S6Heading => 'מודל לא ידוע';

  @override
  String manualC14S6B2(String k1) {
    return 'מה לעשות: לבחור מודל מותקן תחת $k1.';
  }

  @override
  String get manualC14S7Heading => 'התמלול נכשל';

  @override
  String manualC14S7B2(String k1) {
    return 'מה לעשות: לנסות שוב. אם זה לא עוזר, להפעיל מחדש את WhisPaste או לבחור מודל אחר תחת $k1.';
  }

  @override
  String get manualC14S8Heading => 'לא זוהה טקסט';

  @override
  String get manualC14S8B2 =>
      'מה לעשות: לדבר בבירור יותר או קצת יותר זמן, ולנסות שוב. לבדוק גם את המיקרופון.';

  @override
  String get manualC14S9Heading => 'ההקלטה או התמלול ארוכים מדי';

  @override
  String get manualC14S9B2 => 'מה לעשות: להקליט קטעים קצרים יותר.';

  @override
  String get manualC14S10Heading => 'מפתח ענן חסר או לא תקין';

  @override
  String manualC14S10B2(String k1) {
    return 'מה לעשות: להזין את המפתח מחדש תחת $k1, או לעבור לזיהוי במכשיר.';
  }

  @override
  String get manualC14S11Heading => 'זיכרון הגרפיקה מלא';

  @override
  String get manualC14S11B2 =>
      'מה לעשות: אין צורך לעשות דבר. אפשר לבחור שוב את המודל בהגדרות בהמשך.';

  @override
  String get manualC14S12Heading => 'חושב במעבד';

  @override
  String manualC14S12B2(String k1) {
    return 'מה לעשות: בדרך כלל אין צורך לעשות דבר. אם זה קורה הרבה, לבדוק את ההגדרה תחת $k1 ולעדכן את מנהל ההתקן של כרטיס המסך.';
  }

  @override
  String get manualC14S13Heading => 'הדבקה אוטומטית נחסמה (macOS)';

  @override
  String get manualC14S13B2 =>
      'מה לעשות: לאשר ל-WhisPaste נגישות בהגדרות המערכת. אם ההודעה נשארת, להפעיל מחדש את WhisPaste.';

  @override
  String get manualC14S14Heading => 'הדבקה אוטומטית נחסמה (Windows)';

  @override
  String get manualC14S14B2 => 'מה לעשות: להפעיל גם את WhisPaste כמנהל.';

  @override
  String get manualC14S15Heading => 'הדבקה אוטומטית בלינוקס';

  @override
  String get manualC14S15B1 =>
      'בלינוקס הדבקה אוטומטית משתמשת בהתקן קלט וירטואלי (uinput). אם זה לא עובד, בדוק אם ל-WhisPaste מותר לגשת להתקן הזה.';

  @override
  String get manualC14S15B2 =>
      'חבילת ה-.deb לא נותנת שום גישה בזמן ההתקנה. הדבקה אוטומטית שואלת קודם: בהגדרה הראשונית או בהגדרות → אחרי התמלול, בחר „לאפשר (סיסמת מנהל)” והזן את סיסמת המנהל. כל עוד ההרשאה קיימת, גם תוכנות אחרות בהפעלה שלך יכולות ליצור הקשות. „הסרת ההרשאה” מבטלת אותה בכל עת; גם הסרת ההתקנה מסירה אותה.';

  @override
  String get manualC14S15B3 =>
      'בגרסת Flatpak האפליקציה מקבלת גישה להתקני הקלט של המערכת, כדי שההדבקה האוטומטית תוכל לעבוד. WhisPaste עצמה אינה קוראת התקני קלט.';

  @override
  String get manualC14S15B4 => 'בגרסת Snap, הרץ פעם אחת בטרמינל:';

  @override
  String get manualC14S15B5 =>
      'ה-AppImage צריך גישה ל-/dev/uinput. בהגדרה הראשונית או בהגדרות, העתק את הפקודה והרץ אותה פעם אחת בטרמינל. היא מתקינה את כלל ה-udev ‏71-whispaste-uinput.rules אל /etc/udev/rules.d/, שנותן הרשאת כתיבה רק להפעלה המחוברת. עד אז, הדבקה אוטומטית רק מעתיקה את הטקסט.';

  @override
  String get manualC14S15TerminalHeading => 'מסופים ו-Wayland';

  @override
  String get manualC14S15T1 =>
      'ב-Linux, מסופים מדביקים עם Ctrl+Shift+V. WhisPaste מזהה מסופים נפוצים ומשתמש שם בקיצור הזה בעצמו: תחת X11 ו-XWayland, וב-KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire ושולחנות wlroots אחרים.';

  @override
  String get manualC14S15T2 =>
      'ב-GNOME עם Wayland, WhisPaste מזהה את אפליקציית היעד רק עם תוסף WhisPaste האופציונלי ל-GNOME. בלעדיו WhisPaste אינו מזהה מסופים, ורשימת חסימה רק מעתיקה את הטקסט.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'אם מסוף עדיין מציג ^V במקום הטקסט, הפעל את \"$k1\" תחת $k2. אז WhisPaste מדביק בכל מקום עם Ctrl+Shift+V. יש אפליקציות שמשתמשות במקשים האלה לדבר אחר; LibreOffice, למשל, פותח חלון דו-שיח.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'ב-GNOME, הפעל את תוסף WhisPaste בהגדרות עם $k1. חבילת ה-.deb כבר מתקינה אותו. עם Flatpak, AppImage או קובץ ה-tarball, התקן אותו פעם אחת עם הסקריפט מחבילת Linux שחולצה, ואז הפעל אותו:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'בלי uinput מוגדר, למשל ב-Flatpak, WhisPaste מדביק דרך הרשאת שולחן העבודה: $k1 תחת $k2. שולחן העבודה שואל פעם אחת; אפשר לבטל שם את ההרשאה בכל עת';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'שולחן העבודה הזה עדיין לא מאפשר לאפליקציות להשתמש בקיצורים לכל המערכת. במקום זאת, WhisPaste יכולה להוסיף את $shortcut לקיצורי המקלדת של GNOME.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'הוספה ל-GNOME';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut מוגדר בקיצורי המקלדת של GNOME. אם תשנה את הקיצור, WhisPaste תעדכן אותו גם שם.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'הסרה מ-GNOME';

  @override
  String get settingsDesktopShortcutFailed =>
      'לא ניתן היה לשנות את קיצורי המקלדת של GNOME.';

  @override
  String get settingsDesktopShortcutManual =>
      'שולחן העבודה הזה לא מאפשר לאפליקציות להשתמש בקיצורים לכל המערכת. הקצה את הפקודה הזו לצירוף מקשים בהגדרות המערכת:';

  @override
  String get manualC14S15HotkeyHeading => 'קיצור גלובלי ב-Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'ב-Wayland, אפליקציה מקבלת קיצורים לכל המערכת רק דרך שולחן העבודה. KDE Plasma ו-GNOME 48 ומעלה מספקים אותם. גרסאות GNOME ישנות יותר, למשל ב-Ubuntu 24.04, לא: אז WhisPaste מציעה את \"$k1\" תחת $k2 ומוסיפה את הקיצור לקיצורי המקלדת של GNOME.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'בשולחנות עבודה אחרים, כמו Sway או Hyprland, הקצה את הפקודה לצירוף מקשים בעצמך. ההגדרות מציגות תחת $k1 את הפקודה המדויקת להתקנה שלך.';
  }

  @override
  String get manualC14S15H3 =>
      'אם מקש הקיצור לא פועל באפליקציות אחרות, ההגדרות וההיכרות הראשונית מציגות הודעה עם הסיבה, הפקודה לקיצור מקלדת משלכם והלחצן «חיבור מחדש», שמבקש שוב מהשולחן את הקיצור.';

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'עם הגישה הזו, האפליקציה יכולה תיאורטית לקרוא הקשות של תוכנות אחרות, אם למשתמש שלך יש הרשאת קריאה להתקני הקלט (למשל כחבר בקבוצה input). חברי הקבוצה input יכולים גם ליצור קלט וירטואלי.';

  @override
  String get manualC14S15B3S =>
      'להדבקה אוטומטית המחשב צריך גם הרשאת כתיבה ל-/dev/uinput: התקן את כלל udev 71-whispaste-uinput.rules ב-/etc/udev/rules.d/ והרץ אחר כך את הפקודות האלה:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'העתקת הפקודה';

  @override
  String get manualCodeCopied => 'הפקודה הועתקה';

  @override
  String get manualCodeCopyFailed =>
      'ההעתקה נכשלה. סמנו את הפקודה והעתיקו אותה ידנית.';

  @override
  String get manualC14S15B3E =>
      'הכלל נותן הרשאת כתיבה רק להפעלה המחוברת. הפקודות האלה דורשות הרשאות מנהל (sudo) ומשנות את המערכת. אם אינך רוצה בכך, השאר את ההדבקה האוטומטית כבויה והדבק את הטקסט ידנית. כדי להסיר את הכלל, השתמש בכפתור בהגדרות שמעתיק את הפקודה המתאימה.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'עד אז, הדבקה אוטומטית רק מעתיקה את הטקסט.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'הקיצור כבר תפוס';

  @override
  String manualC14S16B2(String k1) {
    return 'מה לעשות: לבחור צירוף אחר תחת $k1.';
  }

  @override
  String get manualC14S17Heading => 'הפעלה אוטומטית לא הוגדרה';

  @override
  String get manualC14S17B2 =>
      'מה לעשות: לבדוק את ההרשאות להפעלה אוטומטית במערכת ההפעלה. בלי זה WhisPaste לא נפתח לבד.';

  @override
  String get manualC14S18Heading => 'הגיבוי האוטומטי נכשל';

  @override
  String manualC14S18B2(String k1) {
    return 'מה לעשות: לבחור תיקייה אחרת וזמינה תחת $k1.';
  }

  @override
  String get manualC14S19Heading => 'איפוס להגדרות היצרן לא הושלם';

  @override
  String get manualC14S19B2 =>
      'מה לעשות: לבחור “נסה שוב”, או להפעיל מחדש את WhisPaste ולהריץ את האיפוס שוב אחר כך.';

  @override
  String get manualC14S20Heading => 'לא זוהה צליל';

  @override
  String manualC14S20B2(String k1) {
    return 'מה לעשות: לבדוק את המיקרופון תחת $k1 ולהקליט שוב.';
  }

  @override
  String get manualC14S21Heading => 'אין מספיק זיכרון';

  @override
  String manualC14S21B1(String k1) {
    return 'WhisPaste נפתחת גם עם פחות זיכרון ממה שמומלץ ($k1). במקרה כזה האפליקציה מציעה את מודל הדיבור “מהיר”.';
  }

  @override
  String get manualC15Title => 'קיצורי מקלדת';

  @override
  String get manualC15S1Heading => 'רק בתוך WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'קיצורי המקלדת האלה פועלים רק כשחלון WhisPaste פעיל. את הקיצור הכללי במערכת מגדירים תחת $k2.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'ב-Mac, $k1 בדרך כלל מחליף את $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 פותח את העזרה.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k פותח גם הוא את העזרה.';
  }

  @override
  String get manualC15S2Heading => 'הקלטות';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: למחוק את הפריט.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: להחליף מועדף.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: לחפש.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: לסגור חיפוש או תצוגת פרטים.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: העתקת הפריט.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: ביטול העריכה. אם יש שינויים שלא נשמרו, תתבקש לאשר קודם.';
  }

  @override
  String get manualC15S3Heading => 'פתקים';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: למחוק את הפריט.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: ליצור פתק חדש.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: לחפש.';
  }

  @override
  String get manualC15S4Heading => 'מילון וקטעים';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: למחוק את הפריט.';
  }

  @override
  String get manualC15S5Heading => 'ביטול במהלך הקלטה';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'בזמן הקלטה או תמלול, WhisPaste תופס את מקש $k1 בכל המערכת כדי שתוכל לבטל. אז $k1 לא עושה כלום באפליקציות אחרות. אם זה מפריע לך, בחר ב-$k2 כמקש הביטול בהגדרות.';
  }

  @override
  String get manualC16Title => 'משוב ותמיכה';

  @override
  String get manualC16S1Heading => 'שליחת משוב';

  @override
  String get manualC16S1B1I1 => 'דירוג: חובה.';

  @override
  String get manualC16S1B1I2 => 'סוג: חובה. בחרו בין בעיה, רעיון, שבח או שאלה.';

  @override
  String get manualC16S1B1I3 => 'טקסט חופשי עד 1000 תווים.';

  @override
  String get manualC16S1B1I4 => 'כתובת דוא״ל היא אופציונלית.';

  @override
  String get manualC16S1B2 =>
      'אם שלחת משוב לאחרונה, האפליקציה מציגה את ההודעה הזו:';

  @override
  String get manualC16S2Heading => 'תמיכה';

  @override
  String manualC16S2B1(String k1) {
    return 'הכרטיסייה $k1 בעזרה מראה איך אפשר לתמוך ב-WhisPaste.';
  }

  @override
  String get manualC16S3Heading => 'תזכורת דירוג';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'אם בחרת „אל תשאל שוב“ בתזכורת הדירוג, תמצא את המתג „$k2“ תחת $k1. הוא מופיע רק במקרה הזה.';
  }

  @override
  String get manualC16S4B1 =>
      'אפשר לשלוח משוב מלשונית העזרה, מתפריט העזרה בשורת התפריטים (macOS) או מתפריט שורת הכותרת (Windows ו-Linux), וגם מאזור ההודעות. הטופס נמצא בשני צעדים.';

  @override
  String get manualC16S5Heading => 'שיתוף רעיון';

  @override
  String get manualC16S5B1 =>
      'בחרו רעיון, או פתחו הצעת רעיון מתפריט העזרה: הסוג כבר נבחר. אפשר גם לפרסם את הרעיון בלוח הרעיונות הציבורי ולהצביע על רעיונות של אחרים.';

  @override
  String get manualC16S6Heading => 'כתיבה בקול';

  @override
  String get manualC16S6B1 =>
      'לחצן המיקרופון בשדה ההודעה מקליט את קולכם ומכניס את הטקסט שזוהה למיקום הסמן.';

  @override
  String get manualC16S7Heading => 'מה נשלח';

  @override
  String get manualC16S7B1I1 => 'הסוג שבחרתם וההודעה שלכם.';

  @override
  String get manualC16S7B1I3 =>
      'כתובת הדוא\"ל רק אם הזנתם אותה. היא משמשת לתשובה בלבד ונמחקת אחרי 90 יום.';

  @override
  String get manualC16S7B1I4 =>
      'אבחון רק אם הפעלתם צירוף אבחון: גרסת האפליקציה, מערכת ההפעלה, מנוע הזיהוי הקולי והעורף. הצגת תצוגה מקדימה מראה את הטקסט המדויק לפני השליחה.';

  @override
  String get manualC16S7B1I5 =>
      'רק בשבח: ההסכמה להציג את השבח שלך כציטוט באתר. היא כבויה כברירת מחדל, ואפשר לבטל אותה בלחיצה אחת בעמוד הזה.';

  @override
  String get manualC16S7B2 => 'הקלטות ותמלילים לעולם לא מצורפים.';

  @override
  String get manualC16S4Heading => 'איפה נמצא הטופס';

  @override
  String get manualC16S7B1I2 => 'הדירוג שבחרתם.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'לא ניתן להדביק – הטקסט נמצא בלוח ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'בדוק הרשאה';

  @override
  String get autoPasteResetConfirmTitle => 'לאפס את הרשומה ולאשר מחדש?';

  @override
  String get autoPasteResetConfirmBody =>
      'macOS שמר רשומה ישנה של WhisPaste שכבר לא תקפה. WhisPaste תסיר רק את הרשומה הזו בנגישות. לאחר מכן macOS ישאל אותך שוב. הרשאות אחרות לא ישתנו.';

  @override
  String get autoPasteResetConfirmButton => 'אפס רשומה ואשר מחדש';

  @override
  String get permissionRowMicTitle => 'מיקרופון';

  @override
  String get permissionRowMicPurpose =>
      'מקליט את קולך. בלי ההרשאה אי אפשר להקליט.';

  @override
  String get permissionRowPasteTitle => 'הדבקה אוטומטית';

  @override
  String get permissionRowPastePurpose =>
      'מכניס את הטקסט ישירות למיקום הסמן. בלעדיה הטקסט נשמר בלוח.';

  @override
  String get permissionRowAllow => 'לאפשר';

  @override
  String get permissionRowMissingSettings => 'חסר – פתיחת ההגדרות';

  @override
  String get permissionRowGranted => 'מאושר';

  @override
  String get permissionRowOptional => 'אופציונלי';

  @override
  String get autostartApprovalBody =>
      'macOS ממתין לאישורך: WhisPaste ייפתח בכניסה למערכת רק אחרי שתפעיל אותו ב\'פריטי כניסה\'.';

  @override
  String get autostartApprovalAction => 'פתיחת פריטי כניסה';

  @override
  String get pasteFailureLinuxUinputHint =>
      'הדבקה אוטומטית צריכה את ההרשאה שלך, פעם אחת, למקלדת הווירטואלית (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'העתקת הפקודה';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'הדבקה אוטומטית אינה זמינה במערכת הזו: אין התקן מקלדת וירטואלי.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'הדבקה אוטומטית צריכה גישה חד-פעמית ל-/dev/uinput. פתח את הגדרות ההדבקה האוטומטית להגדרה החד-פעמית.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'הדבקה אוטומטית שואלת עכשיו לפני שהיא משתמשת במקלדת הווירטואלית /dev/uinput, ולכן העדכון הזה הסיר את הגישה הקודמת. הטקסט נמצא בלוח הגזירים, הדבק אותו עם $paste. לחץ כאן כדי לאפשר זאת.';
  }

  @override
  String get linuxUinputSetupAction => 'הגדרה';

  @override
  String get linuxUinputConsentDetail =>
      'כדי להדביק את הטקסט בעצמה, WhisPaste צריכה מקלדת וירטואלית. כל עוד היא מאושרת, גם תוכנות אחרות בהפעלה שלך יכולות ליצור הקשות. בלי הרשאה, WhisPaste מעתיקה את הטקסט ואתה מדביק אותו בעצמך.';

  @override
  String get linuxUinputGrantButton => 'לאפשר (סיסמת מנהל)';

  @override
  String get linuxUinputGrantFailed =>
      'מתן ההרשאה לא הצליח. WhisPaste ממשיכה רק להעתיק את הטקסט.';

  @override
  String get linuxUinputRevokeButton => 'הסרת ההרשאה';

  @override
  String get linuxUinputRevokeDone =>
      'ההרשאה הוסרה. עכשיו WhisPaste רק מעתיקה את הטקסט.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'לא ניתן היה להסיר את מפתחות ה-API במלואם.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours ש׳';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes ד׳';
  }

  @override
  String get dockErrorCauseEngine => 'מודל זיהוי הדיבור נעצר עם שגיאה.';

  @override
  String get dockErrorCauseRecording => 'לא ניתן היה לתמלל את ההקלטה.';

  @override
  String get dockErrorAction => 'פתח הגדרות דיבור כדי לבדוק את המודל.';

  @override
  String get overlayDoneCopiedOnly =>
      'הועתק בלבד – אפליקציית היעד חסומה או לא זוהתה';

  @override
  String get overlayDoneNotPasted => 'לא הודבק – נשמר בהקלטות';

  @override
  String get overlayDonePasteFailed => 'הדבקה לא אפשרית – העתק את הטקסט';

  @override
  String get databaseTooNewTitle => 'WhisPaste אינו יכול לפתוח את הנתונים שלך';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'הנתונים נכתבו בגרסה חדשה יותר של WhisPaste (גרסת מסד נתונים $storedVersion). גרסה זו תומכת עד גרסה $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'התקן את הגרסה העדכנית של WhisPaste והפעל את האפליקציה מחדש. שום דבר לא שונה ולא נמחק.';

  @override
  String get databaseTooNewQuit => 'יציאה';

  @override
  String get pasteFailureTargetChanged =>
      'ההדבקה האוטומטית בוטלה: עברת לאפליקציה אחרת בזמן העיבוד. הטקסט נמצא בלוח.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'ההדבקה האוטומטית לא אושרה. הטקסט נמצא בלוח, הדבק אותו עם $paste.';
  }

  @override
  String get onboardingAppearanceSettingsHint =>
      'אפשר לשנות בכל עת בהגדרות, בלשונית מראה';

  @override
  String get onboardingAppearanceSettingsLink =>
      'פתיחת התצוגה המקדימה בהגדרות (מסיים את ההגדרה)';

  @override
  String get onboardingAppearanceSettingsLinkRevision =>
      'פתיחת התצוגה המקדימה בהגדרות (להציג שוב בהמשך)';

  @override
  String get fileDialogOpenTitle => 'פתיחת קובץ';

  @override
  String get fileDialogOpenFilesTitle => 'פתיחת קבצים';

  @override
  String get fileDialogSaveTitle => 'שמירת קובץ';

  @override
  String get fileDialogFolderTitle => 'בחירת תיקייה';

  @override
  String get fileDialogSelectFolder => 'בחירה';

  @override
  String get dockLanguageAuto => 'אוטומטי';

  @override
  String get settingsLanguageFavoriteAdd => 'הוסף למועדפים';

  @override
  String get settingsLanguageFavoriteRemove => 'הסר מהמועדפים';

  @override
  String get settingsLanguageFavoritesLimit =>
      'עד 3 מועדפים. הסר אחד כדי להוסיף אחר.';

  @override
  String get dockMenuFavorites => 'מועדפים';

  @override
  String get dockMenuAllLanguages => 'כל השפות';

  @override
  String get traySpeechModel => 'מודל דיבור';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'סמל המגש דורש מארח מגש. ב-GNOME יש להתקין את התוספת AppIndicator; עד אז תפריט ההחלפה המהירה אינו זמין.';

  @override
  String get trayLanguage => 'שפה';

  @override
  String get trayLanguageMore => 'עוד…';

  @override
  String get trayProfile => 'פרופיל';

  @override
  String get trayProfileAutomatic => 'אוטומטי לפי אפליקציה';

  @override
  String get trayProfileNone => 'ללא פרופיל';

  @override
  String profileSwitchedToast(String name) {
    return 'פרופיל: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'השפה המועדפת הבאה';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'השפה המועדפת הבאה';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'מחליף את שפת ההכתבה לשפה המועדפת הבאה. אפשר לסמן עד שלוש שפות כמועדפות תחת דיבור לטקסט.';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'כבר בשימוש על ידי $action. בחר צירוף אחר.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'הקיצור תפוס על ידי אפליקציה אחרת או שלא ניתן לרשום אותו. בחר צירוף אחר.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'ב-Wayland ייתכן שהקיצור לא יעבוד באפליקציות אחרות. אם הוא לא מגיב, הגדר קיצור שולחן עבודה.';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'שפת הכתבה: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'שפת הכתבה: $language. חל החל מההקלטה הבאה.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'עדיין אין שפות מועדפות. סמן עד שלוש שפות תחת דיבור לטקסט כדי להשתמש בקיצור.';

  @override
  String get languageCycleOpenSettings => 'פתח הגדרות';

  @override
  String get manualLangFavHeading => 'שפות מועדפות';

  @override
  String get manualLangFavB1 =>
      'בהגדרות זיהוי הדיבור, סמן עד שלוש שפות כמועדפות בעזרת הכוכב ברשימת השפות. המועדפות מופיעות בראש תפריט השפות של סרגל ההקלטה ובתפריט מגש המערכת, כדי שתוכל להחליף בלחיצה אחת.';

  @override
  String get manualLangTrayHeading => 'שפה בתפריט מגש המערכת';

  @override
  String get manualLangTrayB1 =>
      'בתפריט מגש המערכת יש תת-תפריט שפה. הוא מציג את המועדפות שלך ומסמן בסימון וי את השפה הפעילה. עוד… פותח את החלון עם הרשימה המלאה. Parakeet בוחר שפה בעצמו, לכן התת-תפריט מוסתר שם.';

  @override
  String get manualLangCycleHeading => 'השפה המועדפת הבאה';

  @override
  String get manualLangCycleB1 =>
      'בכרטיסייה הכתבה אפשר להגדיר צירוף מקשים שמחליף את שפת ההכתבה לשפה המועדפת הבאה בכל לחיצה. הקיצור כבוי עד שמקליטים צירוף. בלי מועדפים, WhisPaste מצביעה על ההגדרה. ב-Linux עם Wayland ייתכן שאפליקציות אחרות לא יגיבו לקיצור.';

  @override
  String onboardingReadyDesktopShortcutHint(String shortcut) {
    return '$shortcut עדיין לא עובד בכל המערכת בשולחן העבודה הזה. חזרו לדף שבו בחרתם את קיצור המקשים כדי להגדיר אותו.';
  }

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut יעבוד בכל המערכת רק אחרי שיתווסף לקיצורי המקלדת של GNOME.';
  }

  @override
  String get recommendationReasonLanguage =>
      'מומלץ כי Parakeet תומך בשפה שלך ומהיר בכל מכשיר.';

  @override
  String get recommendationReasonMeasured => 'מומלץ לפי המדידה במכשיר הזה.';

  @override
  String recommendationReasonApple(String memory) {
    return 'מומלץ לשבב Apple שלך (Metal) עם $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'מומלץ לכרטיס המסך NVIDIA שלך עם $gb GB זיכרון גרפי (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'מומלץ לכרטיס המסך $name שלך (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'מומלץ למעבד, כי אין כרטיס מסך שאפשר להשתמש בו: $cores ליבות, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name הוא גרפיקה בתוכנה, ולכן המעבד עושה את העבודה: $cores ליבות, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb GB זיכרון RAM';
  }

  @override
  String get recommendationMemoryUnknown => 'זיכרון RAM לא ידוע';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'אין מודל זיהוי דיבור – להוריד את $name עכשיו ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'אם מודל זיהוי הדיבור שנבחר חסר, הסרגל מציג „מודל זיהוי הדיבור חסר“. תפריט הדיבור בסרגל מציע אותו אז כפריט הראשון להורדה, גם ל־Whisper וגם ל־Parakeet. לחיצה על קיצור המקשים בלי מודל מציגה הודעה עם „הורד עכשיו“. אם עוברים ל־Whisper בהגדרות והמודל שנבחר חסר, WhisPaste בוחר מודל Whisper שכבר הורד.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'מעבד (Vulkan בתוכנה, $name)';
  }

  @override
  String get menuBarMenuEdit => 'עריכה';

  @override
  String get menuBarMenuWindow => 'חלון';

  @override
  String get menuBarEditUndo => 'בטל';

  @override
  String get menuBarEditRedo => 'בצע שוב';

  @override
  String get menuBarEditCut => 'גזור';

  @override
  String get menuBarEditCopy => 'העתק';

  @override
  String get menuBarEditPaste => 'הדבק';

  @override
  String get menuBarEditSelectAll => 'בחר הכול';

  @override
  String get menuBarWindowMinimize => 'מזער';

  @override
  String get menuBarWindowZoom => 'הגדל';

  @override
  String get menuBarAppQuit => 'יציאה מ-WhisPaste';

  @override
  String get menuBarMenuRecording => 'הקלטה';

  @override
  String get menuBarAppSettings => 'הגדרות…';

  @override
  String get menuBarHelpManual => 'פתיחת המדריך';

  @override
  String get menuBarHelpFeedback => 'שליחת משוב…';

  @override
  String get menuBarHelpIdea => 'הצעת רעיון…';

  @override
  String get manualC15S6Heading => 'תפריט';

  @override
  String get manualC15S6B1 =>
      'ב-Mac הפקודות החשובות ביותר נמצאות גם בשורת התפריט שבראש המסך. התפריט «הקלטה» מתחיל ומסיים הקלטה ומגדיר שפה, מודל דיבור, Smart Mode, פעולה אחרי התמלול, מיקרופון ופרופיל.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: פתיחת ההגדרות עם $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'עריכה: גזירה, העתקה, הדבקה ובחירת הכול פועלות על שדה הטקסט הפעיל.';

  @override
  String get manualC15S6B2I3 => 'חלון: מזעור והגדלה של החלון הראשי.';

  @override
  String get manualC15S6B2I4 => 'עזרה: פתיחת המדריך, שליחת משוב והצעת רעיון.';

  @override
  String get manualC15S6B3 =>
      'ב-Windows וב-Linux אותן פקודות נמצאות בלחצן תפריט בפינה הימנית העליונה של שורת הכותרת. פותחים אותו עם Alt או F10, בוחרים פריט עם מקשי החצים, מפעילים עם Enter וסוגרים עם Escape.';

  @override
  String get menuBarAppAbout => 'אודות WhisPaste';

  @override
  String get menuBarAppHide => 'הסתר';

  @override
  String get menuBarAppHideOthers => 'הסתר אחרים';

  @override
  String get menuBarAppShowAll => 'הצג הכול';

  @override
  String get titleBarMenuLabel => 'תפריט';

  @override
  String get notesTitleLabel => 'כותרת';

  @override
  String get notesMoreActions => 'פעולות נוספות';

  @override
  String get notesVersionSaveNow => 'שמור גרסה עכשיו';

  @override
  String get notesMenuMark => 'סמן בהדגשה';

  @override
  String get notesMenuAddImage => 'הוסף תמונה';

  @override
  String get notesMenuVersions => 'גרסאות';

  @override
  String get notesMenuSnippet => 'שמור כקטע';

  @override
  String get notesVersionsEmpty => 'אין עדיין גרסאות.';

  @override
  String get notesVersionTooLarge => 'גדול מדי לתצוגה מקדימה';

  @override
  String get notesVersionDelete => 'מחק גרסה';

  @override
  String get notesVersionSaved => 'הגרסה נשמרה';

  @override
  String get notesVersionUnchanged => 'אין שינויים מאז הגרסה האחרונה.';

  @override
  String get notesVersionRestored => 'הגרסה שוחזרה';

  @override
  String get notesVersionRestoreMessage =>
      'משוחזרים רק הכותרת והטקסט של גרסה זו. התמונות נשארות כמות שהן.';

  @override
  String get notesVersionDeleteMessage =>
      'גרסה זו תימחק לצמיתות ולא ניתן יהיה לשחזר אותה.';

  @override
  String get notesImageFilesLabel => 'תמונות';

  @override
  String get notesImageRejected =>
      'קובץ זה אינו תמונה נתמכת (PNG, JPEG, GIF או WebP).';

  @override
  String get notesImageRemove => 'הסר תמונה';

  @override
  String get notesSnippetCreated => 'קטע נוצר';

  @override
  String get notesSnippetNothing => 'לפתק זה אין טקסט לשמירה כקטע.';

  @override
  String get notesMarkNeedsSelection => 'קודם סמן טקסט.';

  @override
  String get notesImageLimitCount => 'לפתק זה כבר יש את מספר התמונות המרבי.';

  @override
  String get notesImageLimitBytes => 'התמונות של פתק זה יחרגו ממגבלת הגודל.';

  @override
  String get notesImageLimitTotal =>
      'אחסון התמונות מלא. הסר תמונה כדי להוסיף אחרת.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'הקובץ הועתק לאט מדי או השתנה במהלך ההעתקה. נסו שוב.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'פורמט זה אינו זמין במערכת זו. יש להמיר את הקובץ ל-WAV ולייבא אותו שוב.';

  @override
  String get audioDropHint => 'שחררו כאן קבצי אודיו כדי לתמלל אותם';

  @override
  String audioDropRejectedFolder(String names) {
    return 'לא ניתן לייבא תיקיות: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'הקובץ לא נמצא: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'לא נתמך: $names. פורמטים מותרים: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'אינו קובץ רגיל, לא ניתן לייבא: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'גדול מדי (עד 1 GB): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'זהו אינו קובץ רגיל ולא ניתן לייבאו.';

  @override
  String get historyImportRejectedTooLarge => 'הקובץ גדול מ-1 GB.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'שם התקן שמור, לא ניתן לייבא: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'שם הקובץ שמור ב-Windows ולא ניתן לייבאו. יש לשנות את שם הקובץ.';

  @override
  String get historyImportFailureIo => 'האחסון מלא או שאין אפשרות לכתוב.';

  @override
  String get holdToRecordExplained =>
      'מופעל: החזק את הקיצור ודבר, שחרר כדי לסיים. כבוי: לחץ פעם אחת כדי להתחיל ולחץ שוב כדי לסיים.';

  @override
  String get settingsAreaProfiles => 'פרופילים';

  @override
  String get profilesSectionHeading => 'הפרופילים שלך';

  @override
  String get profilesEmptyBody =>
      'פרופילים מחליפים את מודל הדיבור, השפה, Smart Mode ואת הפעולה אחרי התמלול במקש קיצור, או אוטומטית לפי אפליקציה.';

  @override
  String get profilesAddFirst => 'יצירת הפרופיל הראשון';

  @override
  String get profilesAdd => 'יצירת פרופיל';

  @override
  String get profilesCreate => 'יצירה';

  @override
  String get profilesLimitReached =>
      'עד 9 פרופילים. מחקו פרופיל כדי ליצור פרופיל חדש.';

  @override
  String get profilesActiveBadge => 'פעיל';

  @override
  String get profilesMoveUp => 'הזזה למעלה';

  @override
  String get profilesMoveDown => 'הזזה למטה';

  @override
  String get profilesDragHandle => 'גררו כדי לסדר מחדש';

  @override
  String get profilesNewTitle => 'פרופיל חדש';

  @override
  String get profilesNameLabel => 'שם';

  @override
  String get profilesNameEmpty => 'הזינו שם.';

  @override
  String get profileDetailHeading => 'הגדרות הפרופיל';

  @override
  String get profileDetailModel => 'מודל דיבור';

  @override
  String get profileDetailLanguage => 'שפה';

  @override
  String get profileDetailLanguageSubtitle =>
      'חל על Whisper ועל שירותי ענן. Parakeet מזהה את השפה בעצמו.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'אחרי התמלול';

  @override
  String get profileDetailMicrophone => 'מיקרופון';

  @override
  String get profileKeepUnchanged => 'להשאיר ללא שינוי';

  @override
  String profileValueUnavailable(String value) {
    return '$value (לא זמין)';
  }

  @override
  String get profileDetailHotkey => 'מקש קיצור';

  @override
  String get profileDetailHotkeySubtitle =>
      'מעבר לפרופיל הזה בלחיצה על מקש הקיצור.';

  @override
  String get profileHotkeyNone => 'ללא מקש קיצור';

  @override
  String get profileHotkeyChange => 'הגדרת מקש קיצור';

  @override
  String get profileHotkeyRemove => 'הסרת מקש הקיצור';

  @override
  String get profileHotkeyNeedsModifier =>
      'למקש קיצור של פרופיל צריך לפחות מקש שינוי אחד, כמו Ctrl, Alt, Shift או Command.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'כבר בשימוש ב-„$action“. מקש הקיצור לא פעיל.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'כבר בשימוש בפרופיל „$name“. מקש הקיצור לא פעיל.';
  }

  @override
  String get profileDetailApps => 'אפליקציות יעד';

  @override
  String get profileDetailAppsSubtitle =>
      'כשאחת מהאפליקציות האלה בחזית בזמן הכתבה, הפרופיל מופעל אוטומטית.';

  @override
  String get profileAppIdentifierLabel => 'מזהה האפליקציה';

  @override
  String get profileAppAdd => 'הוספה';

  @override
  String get profileAppHintMac => 'macOS: מזהה החבילה, למשל com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: שם התוכנית בלי .exe, למשל chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: WM_CLASS של החלון, למשל google-chrome. לא ניתן לזיהוי ב-Wayland.';

  @override
  String profileAppClash(String name) {
    return 'האפליקציה הזו כבר שייכת לפרופיל „$name“.';
  }

  @override
  String get profileAppEmpty => 'עדיין לא שויכה אפליקציה.';

  @override
  String get profileAppRemove => 'הסרת כלל האפליקציה';

  @override
  String get profileDetailContext => 'קריאת הקשר';

  @override
  String get profileDetailContextSubtitle =>
      'קורא אופציונלית טקסט מסומן או את הלוח, כדי שהעיבוד יתאים. בשירותי ענן רק באישורך.';

  @override
  String get profileContextNone => 'לא לקרוא כלום';

  @override
  String get profileContextSelection => 'טקסט מסומן';

  @override
  String get profileContextClipboard => 'לוח';

  @override
  String get profileConsentGiven => 'הסכמה ניתנה';

  @override
  String get profileConsentMissing => 'חסרה הסכמה, לכן לא נקרא הקשר';

  @override
  String get profileConsentWithdraw => 'ביטול הסכמה';

  @override
  String get profileConsentTitle => 'לשלוח הקשר לשירות ענן?';

  @override
  String get profileConsentBody =>
      'כשהפרופיל הזה פעיל, הטקסט המסומן או תוכן הלוח של חלון היעד נשלחים לספק הענן שצוין בפרופיל הזה, רק כדי לשפר את הכתבה הזו. ניתן לבטל את ההסכמה בכל עת בהגדרות הפרופיל.';

  @override
  String get profileConsentAccept => 'הסכמה';

  @override
  String get profileDeleteAction => 'מחיקת הפרופיל';

  @override
  String profileDeleteTitle(String name) {
    return 'למחוק את הפרופיל „$name“?';
  }

  @override
  String get profileDeleteMessage =>
      'הפרופיל והאפליקציות שלו יוסרו. מקש הקיצור שלו יתפנה.';

  @override
  String get manualProfilesTitle => 'פרופילים והחלפה מהירה';

  @override
  String get manualProfilesS1Heading => 'יצירת פרופילים';

  @override
  String get manualProfilesS1Body =>
      'פרופיל הוא קבוצה בעלת שם של הגדרות כתיבה בהכתבה. יוצרים אותו תחת הגדרות ← פרופילים, ולכל שדה מחליטים אם הפרופיל קובע אותו או משאיר ללא שינוי.';

  @override
  String get manualProfilesS1B1 =>
      'מודל דיבור, שפה, Smart Mode, פעולה אחרי התמלול ומיקרופון';

  @override
  String get manualProfilesS1B2 =>
      'עד 9 פרופילים. כל שדה יכול להיות במצב „להשאיר ללא שינוי“.';

  @override
  String get manualProfilesS2Heading => 'מקשי קיצור';

  @override
  String get manualProfilesS2Body =>
      'לכל פרופיל יכול להיות מקש קיצור משלו. לחיצה עליו מפעילה את הפרופיל, והוא נשאר פעיל עד שתבחרו פרופיל אחר או תשנו ידנית אחד משדותיו.';

  @override
  String get manualProfilesS2Tip =>
      'מקש קיצור צריך מקש שינוי. שילוב שכבר בשימוש בתכונה אחרת נשאר לא פעיל, והפרופיל מציג אותו כהתנגשות.';

  @override
  String get manualProfilesS3Heading => 'אוטומטית לפי אפליקציה';

  @override
  String get manualProfilesS3Body =>
      'אם מוסיפים אפליקציה תחת אפליקציות יעד, הפרופיל מופעל בכל פעם שהאפליקציה הזו בחזית בזמן הכתבה. המזהה תלוי במערכת ההפעלה:';

  @override
  String get manualProfilesS3Mac => 'macOS: מזהה החבילה, למשל com.apple.mail';

  @override
  String get manualProfilesS3Win => 'Windows: שם התוכנית בלי .exe, למשל chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: WM_CLASS של החלון ב-X11, למשל google-chrome. ב-Wayland ‏WhisPaste לא יכול לזהות את האפליקציה.';

  @override
  String get manualProfilesS4Heading => 'מגש וכיתוב על המסך';

  @override
  String get manualProfilesS4Body =>
      'בתפריט המגש יש תת-תפריט פרופיל: „אוטומטי לפי אפליקציה“ פועל לפי הכללים, „ללא פרופיל“ מכבה אותם, ומתחתיהם הפרופילים שלכם. בכיתוב ההקלטה מופיע שם הפרופיל הפעיל אחרי השעה והשפה, למשל 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'להשאיר ללא שינוי';

  @override
  String get manualProfilesS5Body =>
      '„להשאיר ללא שינוי“ פירושו שהפרופיל לא נוגע בשדה הזה. נשאר בתוקף הערך שמוגדר כרגע בהגדרות.';

  @override
  String get manualProfilesS6Heading => 'מה עושה החלפה ידנית';

  @override
  String get manualProfilesS6Body =>
      'אם בוחרים פרופיל בתפריט המגש או לוחצים על מקש הקיצור שלו, הוא חל על כל הכתבות הבאות. אם משנים אחר כך שדה שהפרופיל קובע, כמו מודל הדיבור, הסימון פעיל מתבטל וכללי כל אפליקציה מחליטים שוב. הבחירה נשמרת גם אחרי הפעלה מחדש.';

  @override
  String get profileAppCapture => 'לכידת אפליקציה';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'עבור לאפליקציית היעד בעוד $seconds שניות …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '„$identifier“ נוספה כאפליקציית יעד.';
  }

  @override
  String get profileAppCaptureNone =>
      'אין אפליקציה אחרת בחזית. עבור לאפליקציית היעד לפני שהספירה לאחור מסתיימת.';

  @override
  String get profileAppCaptureUnavailable =>
      'הסשן הזה לא יכול לקרוא את האפליקציה שבחזית (למשל Wayland). הזן את המזהה ידנית.';

  @override
  String get waylandHotkeyPortalDescription => 'הכתבה ב-WhisPaste';

  @override
  String get waylandHotkeyNoAppId =>
      'שולחן העבודה לא הצליח לזהות את WhisPaste ולא הפעיל את הקיצור, ולכן הוא לא פועל באפליקציות אחרות.';

  @override
  String get waylandHotkeyUnavailable =>
      'שולחן העבודה לא מאפשר לאפליקציות להגדיר קיצור גלובלי, ולכן הקיצור לא פועל באפליקציות אחרות.';

  @override
  String get waylandHotkeyDeclined =>
      'הקיצור לא אושר בחלון הדו-שיח של שולחן העבודה, ולכן הוא לא פועל באפליקציות אחרות.';

  @override
  String get waylandHotkeyFallback =>
      'במקום זאת אפשר להוסיף קיצור מקשים בהגדרות המערכת עם הפקודה הזו:';

  @override
  String get waylandHotkeyReconnect => 'חיבור מחדש';

  @override
  String get waylandHotkeyCopyCommand => 'העתקת הפקודה';

  @override
  String get waylandHotkeyCommandCopied => 'הועתק';

  @override
  String get waylandHotkeyOpenKeyboardSettings => 'פתיחת הגדרות המקלדת';

  @override
  String get sttEngineRestartHint =>
      'זיהוי הדיבור תקוע. הפעל מחדש את WhisPaste: סגור אותו מתפריט המגש (יציאה) ופתח אותו שוב.';
}
