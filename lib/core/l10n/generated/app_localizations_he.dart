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
  String get navHistory => 'היסטוריה';

  @override
  String get navNotes => 'פתקים';

  @override
  String get navSettings => 'הגדרות';

  @override
  String get navReplacements => 'החלפות';

  @override
  String get navSnippets => 'קטעים';

  @override
  String get navAnalytics => 'ניתוח נתונים';

  @override
  String get navAbout => 'אודות';

  @override
  String get navFeedback => 'משוב';

  @override
  String get pageHistoryTitle => 'היסטוריה';

  @override
  String get pageSettingsTitle => 'הגדרות';

  @override
  String get pageReplacementsTitle => 'החלפות';

  @override
  String get pageAnalyticsTitle => 'ניתוח נתונים';

  @override
  String get pageAboutTitle => 'אודות';

  @override
  String get pageFeedbackTitle => 'משוב';

  @override
  String get historyEmpty => 'עדיין אין הקלטות';

  @override
  String get historyEmptyHint =>
      'לחץ על כפתור ההקלטה או השתמש בקיצור המקלדת כדי להתחיל.';

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
  String get historyCopyAsMarkdown => 'העתק כ-Markdown';

  @override
  String get historyDetail => 'פרטים';

  @override
  String get historyTags => 'תגיות';

  @override
  String get historyDuration => 'משך';

  @override
  String get historyModel => 'מודל';

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
  String get historyEditing => 'עריכה';

  @override
  String get historySearchTranscriptions => 'חפש בתמלולים…';

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
    return 'אין תמלולים שמתאימים ל \"$query\".\nנסה מונח חיפוש אחר.';
  }

  @override
  String get historyTrashEmpty => 'האשפה ריקה';

  @override
  String get historyTrashEmptyHint =>
      'תמלולים שנמחקו יופיעו כאן.\nפריטים נמחקים לצמיתות אחרי 30 יום.';

  @override
  String get historyEmptyTrash => 'רוקן אשפה';

  @override
  String get historyEmptyTrashConfirm => 'לרוקן את האשפה?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'פעולה זו תמחק לצמיתות את כל הפריטים באשפה. אין דרך לבטל.';

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'האשפה רוקנה — $count פריטים נמחקו',
      one: 'האשפה רוקנה — פריט אחד נמחק',
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
  String get historySelectMultiple => 'בחר מספר';

  @override
  String get historyProcessed => 'עובד';

  @override
  String get historyOnDevice => 'במכשיר';

  @override
  String get historyUntitledRecording => 'הקלטה ללא שם';

  @override
  String get historyUntitled => 'ללא שם';

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
      'Autostart couldn\'t be registered with the operating system. This may be a permissions issue or your OS version isn\'t supported.';

  @override
  String get settingsShowNotifications => 'הצג התראות';

  @override
  String get settingsShowBackendUtilization => 'מחוון CPU/GPU בשורת הסטטוס';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'מציג אם התמלול פועל בפועל על CPU או GPU, כולל ניצול';

  @override
  String get settingsAudio => 'אודיו';

  @override
  String get settingsAudioSubtitle => 'מיקרופון והקלטה';

  @override
  String get settingsMicrophone => 'מיקרופון';

  @override
  String get settingsGain => 'עוצמת מיקרופון';

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
  String get settingsSpeechRecognition => 'זיהוי דיבור';

  @override
  String get settingsSpeechRecognitionSubtitle => 'איכות ושירות זיהוי דיבור';

  @override
  String get settingsService => 'שירות';

  @override
  String get settingsQuality => 'איכות';

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
  String get settingsAfterTranscriptionActionLabel => 'פעולה';

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
      'ההדבקה האוטומטית נחסמה על־ידי המערכת. WhisPaste זקוקה להרשאה כדי להוסיף טקסט לאפליקציות אחרות — ב־macOS ההרשאה הזו נקראת „נגישות“.';

  @override
  String get pasteFailureNoTarget =>
      'ההדבקה האוטומטית דולגה, לא זוהה חלון יעד. מקד את האפליקציה היעד לפני התחלת ההקלטה.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Paste blocked: the target app is running with administrator rights. Restart WhisPaste as an administrator to paste into that app.';

  @override
  String get pasteFailureGeneric =>
      'ההדבקה האוטומטית נכשלה. הטקסט נמצא בלוח, הדבק ידנית עם ⌘V / Ctrl+V.';

  @override
  String get pasteFailureOpenSettings => 'פתח הגדרות';

  @override
  String get pasteCapabilityCheckTitle => 'רגע…';

  @override
  String get pasteCapabilityReady => 'הכל מוכן';

  @override
  String get pasteCapabilityReadySubtitle => 'ההכתבה שלך נוחתת ישר בסמן.';

  @override
  String get pasteCapabilityPermissionMissing => 'עוד לא אושר';

  @override
  String get pasteCapabilityUnsupported =>
      'ההדבקה האוטומטית לא זמינה בפלטפורמה זו';

  @override
  String get pasteCapabilityTestButton => 'בדוק עכשיו';

  @override
  String get pasteCapabilityGrantButton => 'המשך';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste needs permission to type text into the app you\'re working in — macOS calls this permission \'Accessibility\'.';

  @override
  String get pasteCapabilityTroubleshoot => 'Having trouble?';

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
  String get pasteManualGrantAlertTitle => 'ההפעלה מחדש לא עזרה';

  @override
  String get pasteManualGrantAlertBody =>
      'WhisPaste כבר הופעל מחדש, אך הרשאת ההדבקה האוטומטית עדיין אינה נכנסת לתוקף. בדוק תחת הגדרות המערכת → פרטיות ואבטחה → נגישות אם WhisPaste מופעל שם, והפעל מחדש את המתג במידת הצורך.';

  @override
  String get pasteManualGrantAlertConfirm => 'פתח את הגדרות המערכת';

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
      'WhisPaste מוסיף את ההכתבה שלך ישירות במיקום הסמן. macOS דורש לשם כך מתג אחד שרק אתה יכול להפעיל: הגדרות המערכת → פרטיות ואבטחה → נגישות. אשר כדי לפתוח בדיוק את העמוד הזה — WhisPaste מזהה את האישור שלך אוטומטית ומפעיל את עצמו מחדש לאחר מכן במידת הצורך.';

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
      'Windows מאפשר שליחת הקשות ללא הרשאה נוספת. שלב זה רק מוודא שהחיבור פועל במכשירך.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'באפליקציות מסוימות עם הגנת UIPI/UAC, ההדבקה האוטומטית לא תעבוד. הטקסט יישאר בלוח, ויהיה עליך להדביקו עם Ctrl+V באופן ידני.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'סמן את התיבה ליד WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'הגדרות המערכת פתוחות. מצא את WhisPaste ברשימה והפעל אותו.\n\nלא ברשימה? גרור את סמל האפליקציה פנימה או לחץ על „+\".';

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
  String get settingsOverlayModeFloating => 'חלון צף (תמיד גלוי)';

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
  String get settingsShowFloatingButton => 'כפתור הקלטה צף';

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
  String get settingsPunctuationPriming => 'פריימינג פיסוק';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'מטה את Whisper לכיוון פלט מפוסק כאשר לא הוגדר אוצר מילים מותאם אישית. אין השפעה על המהירות.';

  @override
  String get settingsVadEnabled => 'חיתוך שתיקה בסוף ההקלטה';

  @override
  String get settingsVadEnabledSubtitle =>
      'מסיר שתיקה או רעש ארוכים מסוף ההקלטה לפני שWhisper מפענח אותה, כדי שלא יומצא שם משפט סיום (למשל תופעות הזיה כמו \"תודה שצפיתם\"). עלות זניחה, ניתן לכבות אם עדיפה הפלט הגולמי של Whisper.';

  @override
  String get settingsStripPunctuation => 'הסרת סימני פיסוק';

  @override
  String get settingsStripPunctuationSubtitle =>
      'מסירה נקודות, פסיקים וסימני פיסוק נוספים מכל תמלול לפני השמירה או ההדבקה. פועלת באותו אופן בכל מנוע וספק, לא רק ב-Whisper.';

  @override
  String get settingsNumericOnlyMode => 'מספרים בלבד';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'ממיר מספרים מדוברים (בגרמנית ובאנגלית) לספרות, למשל \"חמש פסיק שתיים\" הופך ל-\"5,2\". משאיר את התמלול ללא שינוי אם אינו ניתן להמרה מלאה.';

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
      'Reset, error reporting, updates, and system behavior';

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
  String get settingsFactoryReset => 'איפוס מלא';

  @override
  String get settingsFactoryResetTitle => 'איפוס מלא';

  @override
  String get settingsFactoryResetMessage =>
      'פעולה זו תמחק לצמיתות את כל הנתונים: היסטוריה, תגיות, החלפות, מודלים, לוגים והגדרות. האפליקציה תחזור למצב ראשוני.\n\nאין דרך לבטל.';

  @override
  String get settingsFactoryResetConfirm => 'מחק הכל';

  @override
  String get settingsFactoryResetSuccess => 'האפליקציה אופסה לחלוטין';

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
  String get groqRemovedToast => 'Groq STT הוסר. ספק אופס למקומי.';

  @override
  String get tccResetAfterUpdateToast =>
      'macOS איפסה את הרשאת ההדבקה האוטומטית במהלך העדכון.';

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
  String get actionDelete => 'מחק';

  @override
  String get actionDismiss => 'סגור';

  @override
  String get actionEdit => 'ערוך';

  @override
  String get actionExport => 'ייצא';

  @override
  String get actionCancel => 'בטל';

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
  String get analyticsTimeSaved => 'זמן שנחסך';

  @override
  String get analyticsAvgLatency => 'Avg. Speed';

  @override
  String get analyticsRecordingActivity => 'פעילות הקלטה';

  @override
  String get analyticsLast7Days => '7 הימים האחרונים';

  @override
  String get analyticsModelUsage => 'שימוש במודלים';

  @override
  String get analyticsDurationDistribution => 'התפלגות משך';

  @override
  String get analyticsCostSavings => 'עלות וחיסכון';

  @override
  String get analyticsLocalSavings => 'חיסכון מקומי';

  @override
  String get analyticsCloudCost => 'עלות ענן';

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
  String analyticsDurationHoursMinutes(int hours, int minutes) {
    return '$hoursש׳ $minutesד׳';
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
  String get replacementsRemoveTrigger => 'הסר ביטוי מפעיל';

  @override
  String get replacementsReplacementLabel => 'טקסט להחלפה';

  @override
  String get replacementsReplacementHint => 'לדוגמה: אגב';

  @override
  String get replacementsDeleteTitle => 'מחק קיצור';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'להסיר את הקיצור \"$trigger\"? אין דרך לבטל.';
  }

  @override
  String get snippetsSearch => 'חפש קטעים…';

  @override
  String get snippetsSearchFieldLabel => 'חפש קטעים';

  @override
  String get snippetsAdd => 'הוסף';

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
      'פתח את בורר הקטעים בזמן הכתבה כדי להוסיף את הטקסט הזה.';

  @override
  String get snippetsTitleLabel => 'כותרת';

  @override
  String get snippetsTitleHint => 'לדוגמה: חתימת אימייל';

  @override
  String get snippetsBodyLabel => 'תוכן';

  @override
  String get snippetsBodyHint => 'הטקסט שהקטע הזה מכניס…';

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
      'מילת ההפעלה מוגדרת, אבל אין עדיין קטעים — הכתבה שלה תודבק כטקסט רגיל עד שתוסיף את הקטע הראשון.';

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
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutReportIssue => 'דווח על בעיה';

  @override
  String get aboutSupportTitle => 'תמוך בפרויקט';

  @override
  String get aboutSupportDescription =>
      'WhisPaste חינמי וקוד פתוח תחת רישיון MIT. תמיכה מכסה עלויות קבועות שוטפות אמיתיות (Apple Developer Program,‏ Microsoft Partner Center ואחסון/דומיין) ששומרות עליו זמין בכל פלטפורמה.';

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
  String get aboutParakeet => 'NVIDIA Parakeet & sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Local speech recognition tuned for speed on plain CPU hardware (~25 languages).';

  @override
  String get aboutPrivacyFirst => 'פרטיות קודמת לכול';

  @override
  String get aboutPrivacyFirstDesc =>
      'ברירת מחדל: AI מקומי. הקול שלך לא עוזב את המחשב אלא אם תבחר שירות ענן.';

  @override
  String get aboutPrivacy => 'פרטיות ונתונים';

  @override
  String get aboutPrivacyLocal =>
      'כל התמלולים וההיסטוריה נשמרים מקומית, לעולם לא על שרתים חיצוניים.';

  @override
  String get aboutPrivacyCloud =>
      'ספקי ענן מקבלים אודיו או טקסט רק כשאתה משתמש בהם.';

  @override
  String get aboutPrivacyNoTracking =>
      'נתוני השימוש אנונימיים ותואמי GDPR (שרת באיחוד האירופי) וניתן לכבותם בהגדרות ← פרטיות. ללא חשבונות משתמש. בדיקות עדכון פונות ל-GitHub (גרסה ו-IP בלבד).';

  @override
  String get aboutKeyboardShortcuts => 'קיצורי מקלדת';

  @override
  String get aboutShortcutRecord => 'התחל / עצור הקלטה';

  @override
  String get aboutLinks => 'קישורים';

  @override
  String get aboutWebsite => 'אתר';

  @override
  String get aboutGitHubRepo => 'מאגר GitHub';

  @override
  String get aboutMitLicense => 'רישיון MIT';

  @override
  String get aboutViewOnGitHub => 'צפה ב-GitHub';

  @override
  String get aboutPrivacyPolicy => 'מדיניות פרטיות';

  @override
  String get aboutSystemInfo => 'מידע מערכת';

  @override
  String get aboutSystemInfoDesc => 'העתק snapshot לאבחון עבור דיווחי באגים.';

  @override
  String get aboutCopyDebugInfo => 'העתק מידע דיבאג';

  @override
  String get aboutCopied => 'הועתק!';

  @override
  String get aboutMadeWith => 'נוצר ב♥ על ידי Silvio Lindstedt';

  @override
  String get aboutOpenSource => 'קוד פתוח תחת רישיון MIT';

  @override
  String get feedbackSubtitle => 'עזור לנו לשפר את WhisPaste. כל קול חשוב.';

  @override
  String get feedbackCategoryLabel => 'על מה זה?';

  @override
  String get feedbackCategoryBug => 'דיווח באג';

  @override
  String get feedbackCategoryFeature => 'רעיון לפיצ\'ר';

  @override
  String get feedbackCategoryGeneral => 'כללי';

  @override
  String get feedbackCategoryAiQuality => 'איכות AI';

  @override
  String get feedbackRatingLabel => 'איך אתה מרגיש לגבי WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'ספר לנו יותר';

  @override
  String get feedbackPlaceholderBug => 'תאר מה קרה ומה ציפית…';

  @override
  String get feedbackPlaceholderFeature => 'מה היית רוצה לראות ב-WhisPaste?';

  @override
  String get feedbackPlaceholderAi => 'איך הייתה איכות התמלול או העיבוד?';

  @override
  String get feedbackPlaceholderGeneral => 'שתף את מחשבותיך…';

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
  String get sttStatusStandby => 'מוכן';

  @override
  String get sttStatusStarting => 'מתחיל…';

  @override
  String get sttStatusReady => 'מוכן';

  @override
  String get sttStatusError => 'שגיאה';

  @override
  String get statusBarSttTooltip => 'מנוע דיבור וסטטוס נוכחי';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'מנוע תמלול: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'לא ניתן למדוד ניצול GPU אמיתי בין מערכות הפעלה ללא הרשאות מוגברות; האחוזים המוצגים משקפים במקום זאת את פעילות ה-CPU של התהליך.';

  @override
  String get statusBarRecording => 'מקליט…';

  @override
  String get statusBarTranscribing => 'מתמלל…';

  @override
  String get statusBarDone => 'הסתיים';

  @override
  String get statusBarHotkeyTooltip => 'קיצור גלובלי: לחץ להגדרה';

  @override
  String get statusBarAutoPasteOffHint =>
      'הדבקה אוטומטית כבויה, ניתן להפעיל בהגדרות';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'הדבקה אוטומטית כבויה כעת. לחץ לפתיחת ההגדרות.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'הסתר';

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
  String get modelServerReady => 'מנוע דיבור מוכן';

  @override
  String get modelServerMissing => 'מנוע דיבור לא מותקן';

  @override
  String get modelServerWhisper => 'מנוע מקומי';

  @override
  String get modelReady => 'מוכן';

  @override
  String get modelUse => 'השתמש';

  @override
  String get modelDownload => 'הורד';

  @override
  String get modelDownloading => 'מוריד…';

  @override
  String get modelDownloadingEngine => 'מכין מנוע דיבור…';

  @override
  String get modelVerifying => 'מאמת…';

  @override
  String get modelExtracting => 'מחלץ…';

  @override
  String get modelDeleteConfirm => 'למחוק מודל זה?';

  @override
  String get modelDeleteConfirmMessage =>
      'קובץ המודל יוסר לצמיתות. תוכל להוריד שוב בכל עת.';

  @override
  String get qualityTierCompactLabel => 'מהיר וקומפקטי';

  @override
  String get qualityTierCompactDesc =>
      'תוצאות מהירות, הורדה קטנה. מעולה להערות קצרות.';

  @override
  String get qualityTierBalancedLabel => 'מאוזן';

  @override
  String get qualityTierBalancedDesc => 'מדויק ואמין להקלטה יומיומית.';

  @override
  String get qualityTierPremiumLabel => 'איכות מיטבית';

  @override
  String get qualityTierPremiumDesc => 'דיוק גבוה להקלטות ארוכות ותוכן מורכב.';

  @override
  String get qualityTierRecommended => 'מומלץ למכשיר שלך';

  @override
  String qualityTierDownloadSize(String size) {
    return 'הורדה $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'הורד מודל';

  @override
  String get qualityTierChooseDifferent => 'בחר רמת איכות אחרת';

  @override
  String get qualityTierActive => 'פעיל';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'איכות מיטבית, לוקח פי $ratio יותר זמן';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'איכות מיטבית, איטי פי $ratio מ-Small';
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
  String get qualityTierActionOverride => 'השתמש בכל זאת';

  @override
  String get qualityTierActionOverrideHint => 'השתמש ברמה זו למרות האזהרה';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

  @override
  String get settingsQualityBasic => 'בסיסי';

  @override
  String get settingsQualityBalanced => 'מאוזן';

  @override
  String get settingsQualityHigh => 'איכות גבוהה';

  @override
  String get settingsQualityBest => 'איכות מיטבית';

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
  String get settingsAdvancedModelManagement => 'ניהול מודלים מתקדם';

  @override
  String get infoEngineDownloading => 'מנוע הדיבור בהכנה. המתן רגע.';

  @override
  String get infoModelMissing => 'הורד קודם מודל דיבור בהגדרות.';

  @override
  String get infoPipelineBusy => 'WhisPaste עדיין עסוק בהקלטה הקודמת.';

  @override
  String get infoSnippetPickerEmpty =>
      'מילת ההפעלה זוהתה, אבל אין לך עדיין קטעים — הטקסט הודבק כרגיל.';

  @override
  String get infoSnippetPickerEmptyAction => 'פתח קטעים';

  @override
  String get oomRecoveryTitle => 'ההקלטה נכשלה: בעיית זיכרון GPU';

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
  String get oomRecoverySwitchCloudHint => 'השתמש בזיהוי דיבור בענן';

  @override
  String get oomRecoveryCancel => 'בטל';

  @override
  String get oomRecoveryPermanentTitle => 'זיהוי דיבור מקומי לא זמין';

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
  String get oomRecoverySwitchingCloud => 'עובר לזיהוי דיבור בענן…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'מודל $model גם נכשל. מנסה את הבא…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'איכות הופחתה: ה-GPU נגמר לו הזיכרון. עברתי למודל קל יותר.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'ה-GPU נגמר לו הזיכרון. עברתי למצב CPU.';

  @override
  String get errorSttServerConnectionLost =>
      'מנוע הדיבור נעצר באופן בלתי צפוי. נסה שוב.';

  @override
  String get errorSttCudaOom => 'ה-GPU נגמר לו הזיכרון. האיכות הופחתה.';

  @override
  String get errorCloudAuth =>
      'מפתח ה-API חסר או שגוי. בדוק אותו בהגדרות ← זיהוי דיבור.';

  @override
  String get errorCloudQuota =>
      'הגעת למגבלת הקצב של ספק הענן. המתן רגע ונסה שוב.';

  @override
  String get errorOnboardingNotCompleted => 'סיים קודם את אשף ההתקנה.';

  @override
  String get errorSttModelNotFound => 'מודל דיבור לא נמצא. הורד אותו בהגדרות.';

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
  String get errorSttServerFailed => 'מנוע הדיבור לא הצליח להתחיל';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'מודל הדיבור אינו תואם לסביבת הריצה המותקנת. הורד מחדש את מודל הדיבור בהגדרות.';

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
      'מנוע הדיבור נכשל הן ב-GPU והן ב-CPU. הפעל מחדש את האפליקציה או הורד מחדש את המודל.';

  @override
  String get errorPipelineTimeout =>
      'ההקלטה נמשכה יותר מדי. נסה הקלטה קצרה יותר.';

  @override
  String get errorWavFileNotCreated => 'לא הצלחתי לשמור קובץ אודיו. נסה שוב.';

  @override
  String get errorWavFileEmpty => 'לא נלכד אודיו. בדוק את המיקרופון.';

  @override
  String get errorSttStartTimeout =>
      'מנוע הדיבור עדיין מתחיל. נסה שוב בעוד רגע.';

  @override
  String get errorTranscriptionTimeout =>
      'התמלול לקח יותר מדי זמן. נסה הקלטה קצרה יותר.';

  @override
  String get errorMicPermissionDenied =>
      'נדרש גישה למיקרופון. אפשר בהגדרות המערכת.';

  @override
  String get errorRecordingStartFailed => 'לא הצלחתי להתחיל הקלטה. נסה שוב.';

  @override
  String get errorGeneric => 'משהו השתבש. נסה שוב.';

  @override
  String get modelDownloadFailed => 'הורדה נכשלה. בדוק חיבור אינטרנט.';

  @override
  String get statusSttLoading => 'טוען מודל…';

  @override
  String get statusSttReady => 'מודל מוכן';

  @override
  String get historyDuplicate => 'שכפל';

  @override
  String get historyDuplicated => 'רשומה שוכפלה';

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
      'Tip: say “tag: name” or “correct: text” while recording.';

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
  String get tagManageEmpty => 'עדיין לא נוצרו תגיות.';

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
  String get settingsKeyboardShortcut => 'קיצור מקלדת';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'קיצור גלובלי להתחלת ועצירת הקלטה';

  @override
  String get settingsHotkeyEnabled => 'הפעל קיצור גלובלי';

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
  String get settingsHotkeyRecorderModifierHint =>
      'כל שילוב מקשי Modifier אפשרי: למשל Alt+Space, Ctrl+Alt+V, או Ctrl+Alt+Shift+R';

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
  String get settingsQuickNoteHotkeyEnabled => 'קיצור לפתק מהיר';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'הטקסט המוכתב מתווסף לפתק המסומן כפתק מהיר. את הפתק הזה בוחרים באזור \"פתקים\".';

  @override
  String get settingsQuickNoteCurrentHotkey => 'צירוף מקשים';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'הצירוף הזה כבר משמש עבור \"$action\". בחר צירוף אחר.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'לא ניתן היה לרשום את הצירוף הזה — הקיצור לפתק מהיר אינו פעיל כרגע. בחר צירוף אחר.';

  @override
  String get settingsHotkeyActionSnippetPicker => 'בוחר הקטעים';

  @override
  String get settingsSnippetPickerHotkeyEnabled => 'קיצור לבוחר הקטעים';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'פותח את בוחר הקטעים מיד — בלי הקלטה ובלי מילת ההפעלה המדוברת.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'צירוף מקשים';

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
  String get settingsErrorReporting => 'דיווח שגיאות';

  @override
  String get settingsErrorReportingSubtitle =>
      'עזור לשפר את WhisPaste על ידי שליחת דיווחי קריסה אנונימיים';

  @override
  String get settingsAutoPasteDelay => 'השהיית הדבקה אוטומטית';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'זמן המתנה לפני הדבקה לחלון הפעיל';

  @override
  String get settingsAutoPasteBlocklist => 'רשימת חסימה להדבקה אוטומטית';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'מזהי אפליקציות מופרדים בפסיקים שבהם הדבקה אוטומטית כבויה';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'לדוגמה: com.apple.Terminal, com.1password';

  @override
  String get settingsCheckUpdates => 'בדוק עדכונים';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'בדוק אוטומטית גרסאות חדשות בהפעלה';

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
  String get onboardingPrivacyTitle => 'עזרו לנו לשפר את WhisPaste';

  @override
  String get onboardingPrivacyHint =>
      'האודיו והטקסט נשארים מקומיים. רק נתוני שימוש אנונימיים נשלחים לשרת באירוח עצמי באיחוד האירופי — בהתאם ל-GDPR.';

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
  String get onboardingAppearancePageTitle => 'הפעלה';

  @override
  String get onboardingBeat1Title => 'לחץ על הקיצור, דבר, סיימת';

  @override
  String get onboardingBeat1Caption =>
      'ההקלטה מתחילה מיד – המילים שלך הופכות לטקסט ישירות במיקום הסמן.';

  @override
  String get onboardingBeat2Title => 'פועל מקומית, על החומרה שלך';

  @override
  String get onboardingBeat2Caption =>
      'התמלול מתבצע במכשיר שלך – בלי צורך באינטרנט.';

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
  String get onboardingModelTitle => 'הגדר זיהוי דיבור';

  @override
  String get onboardingModelSubtitle =>
      'הורד את מנוע הדיבור כדי להקליט offline. הקול שלך לא עוזב את המכשיר.';

  @override
  String get onboardingModelRecommended => 'מומלץ';

  @override
  String get onboardingModelChangeLater =>
      'תוכל לשנות את האיכות מאוחר יותר בהגדרות';

  @override
  String get onboardingModelDownloading => 'מוריד…';

  @override
  String get onboardingModelReady => 'מודל מוכן';

  @override
  String get onboardingModelGpuCpuFallback =>
      'האצת GPU מיטבית אינה זמינה, האפליקציה תשתמש במעבד';

  @override
  String get onboardingModelEngineParakeetLabel => 'מהיר ואירופי';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'הדרך המהירה ביותר לטקסט בכ-25 שפות אירופיות, כולל גרמנית. פועל היטב בכל חומרה, גם ללא GPU.';

  @override
  String get onboardingModelEngineWhisperLabel => 'כל 99 השפות';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'הכיסוי הרחב ביותר של שפות, בתוספת אוצר מילים מותאם אישית וכיוונון פיסוק לשמות, ראשי תיבות ומונחים מקצועיים.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'עדיין לא תומך בשפה שבחרת';

  @override
  String get onboardingTestRecordingTitle => 'Give it a try';

  @override
  String get onboardingTestRecordingSubtitle =>
      'לחץ על הכפתור למטה ואמור משפט. הטקסט מופיע בשדה הבדיקה. גם הקיצור שלך עובד.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Your hotkey';

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
    return 'רק בדיקה, הטקסט נשאר בשדה הזה — הקלטות נעצרות אוטומטית אחרי $seconds שניות, ניתן לשנות זאת בהגדרות ← $section.';
  }

  @override
  String get onboardingReadyTitle => 'הכל מוכן!';

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
  String get onboardingReadyStep3CopyOnly =>
      'הטקסט בלוח, לחץ ⌘V / Ctrl+V כדי להדביק';

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste מעביר הקשר מההקלטה הקודמת עד עשר דקות קדימה. לפני מעבר מהיר לנושא אחר לגמרי, כדאי הפסקה קצרה, אחרת התוצאה הבאה עלולה להיות מוטה.';

  @override
  String get onboardingReadyAutostartToggle => 'הפעלת WhisPaste בהתחברות';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'כבוי כברירת מחדל, ניתן להפעיל בכל עת בהגדרות';

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
  String get onboardingStartUsing => 'בוא נתחיל';

  @override
  String get onboardingReviewExit => 'סגירת המבוא';

  @override
  String get onboardingReviewDone => 'סיום';

  @override
  String get onboardingReviewEntry => 'מבוא';

  @override
  String get onboardingReviewSubtitle =>
      'אפשר לעבור שוב על חמשת שלבי ההגדרה בכל עת — דבר לא משתנה אלא אם תשנו אותו.';

  @override
  String get onboardingReviewLabel => 'צפייה חוזרת במבוא';

  @override
  String get onboardingReviewAction => 'פתיחה';

  @override
  String get onboardingRevisionNoticeTitle =>
      'יש עדכון ל-WhisPaste — ההגדרות שלכם נשארות כפי שהן.';

  @override
  String get onboardingRevisionExit => 'יציאה מהמבוא';

  @override
  String get onboardingRevisionExitConfirmTitle => 'לצאת מהמבוא?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'מסלול העדכון מוצג פעם אחת בלבד, ולכן מה שתדלגו עליו עכשיו לא יוגדר עבורכם. אפשר לפתוח את אותם שלבים בכל עת דרך ״הגדרות״ ואז ״מבוא״, וכל הגדרה שמופיעה בהם קיימת גם בעמוד ההגדרות עצמו. מה שכבר הגדרתם נשאר כפי שהוא.';

  @override
  String get onboardingRevisionExitConfirmAction => 'יציאה';

  @override
  String get overlayRecording => 'מקליט';

  @override
  String get overlayTranscribing => 'מתמלל…';

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
  String get traySettings => 'הגדרות';

  @override
  String get trayQuit => 'צא';

  @override
  String get trayMicrophone => 'מיקרופון';

  @override
  String get settingsComingSoon => 'בקרוב';

  @override
  String get undo => 'בטל';

  @override
  String get hintDismiss => 'Dismiss hint';

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
  String get voiceNoteEmpty => 'לא זוהה דיבור';

  @override
  String get voiceNoteError => 'הערת קול נכשלה';

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
  String get buttonContextShowHistory => 'הצג היסטוריה';

  @override
  String get buttonContextSettings => 'הגדרות';

  @override
  String get buttonContextQuit => 'צא מ-WhisPaste';

  @override
  String get settingsHistory => 'היסטוריה';

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
  String get settingsFloatingButtonSection => 'כפתור צף';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'כפתור הקלטה תמיד עליון לגישה מהירה';

  @override
  String get settingsSttIdleTimeout => 'זמן המתנה של מנוע';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'כמה זמן המנוע נשאר טעון אחרי שימוש';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'תמיד פעיל';

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
  String get reviewPromptStarGitHub => '⭐ כוכב ב-GitHub';

  @override
  String get reviewPromptRateStore => '★ דרג בחנות';

  @override
  String get reviewPromptGateBody => 'רק שאלה קצרה אלינו, זו אינה דירוג בחנות.';

  @override
  String get reviewPromptGateYes => 'כן, אני אוהב את זה';

  @override
  String get reviewPromptGateNo => 'לא ממש';

  @override
  String get reviewSupportEntry => 'דרגו ותמוכו ב-WhisPaste';

  @override
  String get reviewSupportLabel => 'הדירוג שלך';

  @override
  String get reviewSupportSubtitle =>
      'הדירוג שלך עוזר לאחרים לגלות את WhisPaste ותומך בפרויקט.';

  @override
  String get reviewSupportAction => 'דרגו';

  @override
  String get insufficientRamTitle => 'אין מספיק זיכרון';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'WhisPaste דורש לפחות $requiredGb GB RAM. למערכת שלך יש $detectedGbString GB.\n\nעם פחות זיכרון, מנוע ה-AI עלול להיכשל.';
  }

  @override
  String get insufficientRamQuit => 'צא מ-WhisPaste';

  @override
  String get insufficientRamLearnMore => 'דרישות מערכת';

  @override
  String get insufficientRamSystemCheck => 'בדיקת מערכת';

  @override
  String get insufficientRamYourSystem => 'המערכת שלך';

  @override
  String get insufficientRamRequired => 'נדרש';

  @override
  String get hotkeyRegistrationFailed =>
      'רישום קיצור הדרך נכשל, הגדר מחדש את הקיצור בהגדרות.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'רישום קיצור הדרך נכשל, Ctrl+Shift+Space משמש כברירת מחדל. הגדר מחדש בהגדרות.';

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
      'Transcription is taking a little longer than usual right now, it\'s still working.';

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
  String get modelAbiInfoToast => 'Reloading voice model, please wait.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste is now running without GPU acceleration due to a problem on the last launch. Dictation still works as usual.';

  @override
  String get serverDownloadFailedToast =>
      'Voice service could not be downloaded. Check your internet connection?';

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
  String get factoryResetFailedToast =>
      'Factory reset incomplete. Restart the app?';

  @override
  String get factoryResetFailedAction => 'Quit app';

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
      'קובע אם שירות הדיבור ישתמש ב-GPU או CPU לזיהוי מקומי';

  @override
  String get settingsGpuAccelerationAuto => 'אוטומטי (מומלץ)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (כפוי)';

  @override
  String get settingsGpuAccelerationDisabled => 'CPU בלבד';

  @override
  String get settingsSttEngine => 'Engine';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper covers 99 languages and every GPU backend; Parakeet is much faster on CPU-only hardware but covers ~25 languages and has no GPU backend yet';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet (fastest, ~25 languages)';

  @override
  String get parakeetModelTitle => 'Parakeet TDT model';

  @override
  String get parakeetModelSubtitle =>
      'One-time download (~640 MB), then runs fully offline';

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
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsPrivacySubtitle => 'Control what data WhisPaste shares';

  @override
  String get settingsShareUsageStats => 'Share anonymous usage statistics';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Sent cookieless and without any identifiers, help us understand how WhisPaste is used';

  @override
  String get settingsRetainRecentAudio => 'Keep recent recordings';

  @override
  String get settingsRetainRecentAudioSubtitle =>
      'Keep the audio of your last 20 dictations on this device for debugging or restoring a past transcript; older recordings are deleted automatically';

  @override
  String get storeThankYouTitle => 'תודה על תמיכתך!';

  @override
  String get storeThankYouBody =>
      'אנחנו שמחים שאתה איתנו. אם WhisPaste עוזר לך בעבודה, דירוג קצר יעשה עבורנו הבדל גדול.';

  @override
  String get storeThankYouCtaStore => '★ דרג בחנות';

  @override
  String get storeThankYouCtaGitHub => '⭐ כוכב ב-GitHub';

  @override
  String get storeThankYouDismiss => 'סגור';

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
}
