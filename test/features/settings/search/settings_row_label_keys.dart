/// Label keys of the settings search coverage registry (ticket, §7.1 guard).
///
/// Each key is a primary row or card label from `app_en.arb`, mapped to the
/// settings area that holds it today. Every key must appear exactly once in
/// `kSettingsSearchTable` (as a row's label or card key).
library;

const Map<String, String> kSettingsCoverageLabelKeys = {
  // Interface
  'settingsAppLanguage': 'interface',
  'settingsCloseToTray': 'interface',
  'settingsLaunchAtStartup': 'interface',
  'settingsShowBackendUtilization': 'appearance',
  'settingsShowNotifications': 'interface',
  'settingsSidePanelEdge': 'appearance',
  'settingsSidePanelEnabled': 'appearance',
  // Speech Recognition
  'settingsCustomVocabulary': 'stt',
  'settingsGpuAcceleration': 'stt',
  'settingsNumericOnlyMode': 'stt',
  'settingsPunctuationPriming': 'stt',
  'settingsRecognitionLanguage': 'stt',
  'settingsRemoveFillerWords': 'stt',
  'settingsSttEngine': 'stt',
  'settingsStripPunctuation': 'stt',
  'settingsVadEnabled': 'stt',
  'settingsSpeechRecognition': 'stt',
  // API keys (#208)
  'settingsDeepgramApiKey': 'apiKeys',
  'settingsOpenAiApiKey': 'apiKeys',
  // Smart Mode
  'settingsSmartMode': 'smartMode',
  'settingsSmartModeHotkeyEnabled': 'smartMode',
  'settingsSelectionEditHotkeyEnabled': 'smartMode',
  // Audio
  'settingsAudio': 'audio',
  'settingsAutoLevel': 'audio',
  'settingsGain': 'audio',
  'settingsMicrophone': 'audio',
  'settingsClippingBanner': 'audio',
  // After Transcription
  'settingsAfterTranscription': 'afterTranscription',
  // Recording Overlay
  'settingsOverlayLiveTranscript': 'overlay',
  'settingsOverlaySize': 'overlay',
  'settingsOverlayStartPosition': 'overlay',
  'settingsOverlayBackground': 'overlay',
  'settingsOverlayWave': 'overlay',
  // Floating Button
  'settingsFloatingButtonSection': 'floatingButton',
  'settingsShowFloatingButton': 'floatingButton',
  // Keyboard Shortcut
  'shortcutsGroupDictate': 'hotkey',
  'settingsHotkeyEnabled': 'hotkey',
  'settingsHotkeyOperation': 'hotkey',
  'settingsQuickNoteHotkeyEnabled': 'hotkey',
  'settingsSnippetPickerHotkeyEnabled': 'hotkey',
  // Sound & Feedback
  'settingsSoundFeedback': 'sound',
  'settingsSoundVolume': 'sound',
  'settingsSoundProfile': 'sound',
  // Recording Safety
  'settingsAutoStopSilence': 'recordingSafety',
  'settingsDeadMicTimeout': 'recordingSafety',
  'settingsMaxRecordDuration': 'recordingSafety',
  'settingsRecordingSafety': 'recordingSafety',
  // History
  'settingsHistory': 'history',
  'settingsHistorySave': 'history',
  'settingsHistoryDeleteExisting': 'history',
  'settingsHistoryRetentionPreset': 'history',
  'settingsHistoryHideOnOpen': 'history',
  'settingsHistoryPin': 'history',
  'settingsHistoryAutoLock': 'history',
  // Backup & Transfer
  'settingsAutosaveLabel': 'settingsPortability',
  'settingsPortabilityExportAction': 'settingsPortability',
  'settingsPortabilityImportAction': 'settingsPortability',
  'settingsPortabilitySectionTitle': 'settingsPortability',
  // Advanced
  'settingsAdvanced': 'advanced',
  'settingsAutoPasteBlocklist': 'advanced',
  'settingsLinuxAlwaysShiftPaste': 'advanced',
  'settingsFactoryResetTitle': 'advanced',
  'settingsResetToDefaults': 'advanced',
  // Local Automation API
  'settingsAutomationApi': 'automationApi',
  'settingsAutomationApiToken': 'automationApi',
  'settingsAutomationApiCustomPortLabel': 'automationApi',
  'settingsAutomationWriteEnable': 'automationApi',
  'settingsAutomationWriteToken': 'automationApi',
  // Updates
  'settingsUpdates': 'updates',
  'settingsCheckForUpdatesNow': 'updates',
  // Privacy
  'settingsPermissions': 'privacy',
  'permissionRowMicTitle': 'privacy',
  'permissionRowPasteTitle': 'privacy',
  'permissionRowInputMonitoringTitle': 'privacy',
  'settingsPrivacy': 'privacy',
  'settingsErrorReporting': 'privacy',
  'settingsRetainRecentAudio': 'privacy',
  'settingsShareUsageStats': 'privacy',
};
