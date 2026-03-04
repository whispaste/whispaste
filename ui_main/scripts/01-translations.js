/* ── Translations ──────────────────────────────────────── */
const translations = {
  en: {
    // Navigation
    navHistory: 'History',
    navSettings: 'Settings',
    navAbout: 'About',

    // Settings — General
    settingsTitle: 'Settings',
    cardApiKey: 'API Key',
    labelApiKey: 'OpenAI API Key',
    hintApiKey: 'Need a key?',
    hintApiKeyLink: 'Get your API key →',
    cardMode: 'Recording Mode',
    modePush: 'Push to Talk',
    modePushDesc: 'Hold the hotkey to record',
    modeToggle: 'Toggle',
    modeToggleDesc: 'Press to start, press again to stop',
    cardHotkey: 'Hotkey',
    labelHotkey: 'Current Hotkey',
    cardLanguage: 'Transcription Language',
    labelLanguage: 'Language',
    langAuto: 'Auto-detect',
    langEn: 'English',
    langDe: 'German',
    langEs: 'Spanish',
    langFr: 'French',
    langIt: 'Italian',
    langPt: 'Portuguese',
    langJa: 'Japanese',
    langZh: 'Chinese',
    langKo: 'Korean',
    langRu: 'Russian',
    langAr: 'Arabic',
    langHi: 'Hindi',
    cardOverlay: 'Overlay Position',
    overlayTop: 'Top Center',
    overlayTopDesc: 'Fixed at top of screen',
    overlayCursor: 'Near Cursor',
    overlayCursorDesc: 'Follows mouse position',
    cardFeedback: 'Preferences',
    labelSound: 'Sound Feedback',
    descSound: 'Play sounds when recording starts and stops',
    labelVolume: 'Volume',
    labelAutoPaste: 'Auto-paste',
    descAutoPaste: 'Automatically paste transcription into focused field',
    labelCheckUpdates: 'Check for updates',
    descCheckUpdates: 'Automatically check for new versions',
    labelAutostart: 'Start with Windows',
    descAutostart: 'Launch WhisPaste automatically when you sign in',
    labelTheme: 'Theme',
    themeSystem: 'System',
    themeLight: 'Light',
    themeDark: 'Dark',

    // Settings — Smart Mode
    cardSmartMode: 'Smart Mode',
    labelSmartMode: 'AI Post-Processing',
    descSmartMode: 'Process transcription with GPT-4o-mini for grammar, formatting, or translation',
    labelSmartPreset: 'Preset',
    smartCleanup: 'Cleanup (grammar & punctuation)',
    smartEmail: 'Email (formal)',
    smartBullets: 'Bullet Points',
    smartFormal: 'Formal Letter',
    smartTranslate: 'Translate',
    smartCustom: 'Custom Prompt',
    labelSmartTarget: 'Target Language',
    labelSmartPrompt: 'Custom Prompt',

    // Settings — Advanced
    cardAdvanced: 'Advanced',
    labelPrompt: 'Whisper Prompt',
    descPrompt: 'Improve accuracy for domain-specific terms (e.g. Kubernetes, kubectl)',
    labelMaxDuration: 'Max Recording Duration',
    labelUnlimited: '∞ Unlimited',

    // Settings — Actions
    btnTest: 'Test',
    btnCancel: 'Cancel',
    btnSave: 'Save',
    statusSaved: 'Settings saved ✓',
    statusError: 'Error saving settings',
    statusTesting: 'Recording…',
    statusTestDone: 'Test complete',
    statusTestError: 'Test failed',
    eyeShow: 'Show API key',
    eyeHide: 'Hide API key',
    btnChangeHotkey: 'Change',
    hotkeyRecording: 'Press your desired key combination…',
    hotkeyHint: 'Press Escape to cancel',

    // Settings — Local STT
    cardLocalSTT: 'Local Transcription',
    labelLocalSTT: 'Use Local Model',
    descLocalSTT: 'Transcribe offline using a local Whisper model — no API key required',
    labelLocalModel: 'Model',
    modelDownload: 'Download',
    modelDownloading: 'Downloading…',
    modelDownloaded: 'Downloaded',
    modelDelete: 'Delete model',
    modelDownloadDone: 'Model downloaded successfully',
    modelDownloadError: 'Model download failed',
    modelDeleted: 'Model deleted',
    modelNotDownloaded: 'not downloaded',
    modelNeedDownload: 'Download the model first to select it',

    // Mode badge
    modeLocal: 'Local',
    modeApi: 'API',
    modeLocalTip: 'Transcription via local Whisper model (offline)',
    modeApiTip: 'Transcription via OpenAI Whisper API',

    // About
    aboutDesc: 'A fast, lightweight voice-to-text tool for Windows. Record speech and instantly paste the transcription anywhere.',
    aboutLicense: 'Open Source – MIT License',
    aboutGithub: 'GitHub',
    aboutIssue: 'Report Issue',
    aboutCreditsTitle: 'Credits',
    aboutCreditsText: 'Made by Silvio Lindstedt. Powered by OpenAI Whisper API. Built with Go and WebView2.',
    aboutSupportTitle: 'Support this project',
    aboutSupportText: 'WhisPaste is free and open source. If you find it useful, please consider supporting its development!',
    aboutCostTitle: 'API Costs',
    aboutCostText: 'Whisper is billed per audio minute (~$0.006/min). A short sentence costs fractions of a cent; typical monthly usage is $1–5.',
    costOccasional: 'Occasional (~5 min/day)',
    costRegular: 'Regular (~20 min/day)',
    costHeavy: 'Heavy (~60 min/day)',

    // Notebook
    'notebook.title': 'History',
    'notebook.search': 'Search transcriptions…',
    'notebook.all': 'All',
    'notebook.pinned': 'Pinned',
    'notebook.today': 'Today',
    'notebook.week': 'This Week',
    'notebook.older': 'Older',
    'notebook.categories': 'Tags',
    'notebook.sort_newest': 'Newest first',
    'notebook.sort_oldest': 'Oldest first',
    'notebook.sort_alpha': 'Alphabetical',
    'notebook.sort_duration': 'By duration',
    'notebook.empty': 'No entries yet.',
    'notebook.no_results': 'No matching entries.',
    'notebook.copy': 'Copy',
    'notebook.pin': 'Pin',
    'notebook.unpin': 'Unpin',
    'notebook.delete': 'Delete',
    'notebook.copied': 'Copied!',
    'notebook.tag_updated': 'Tag updated',
    'notebook.add_tag': 'Add tag…',
    'notebook.confirm_title': 'Delete Entry',
    'notebook.confirm_msg': 'This entry will be permanently deleted.',
    'notebook.confirm_cancel': 'Cancel',
    'notebook.confirm_delete': 'Delete',
    'notebook.selected': 'selected',
    'notebook.delete_selected': 'Delete',
    'notebook.confirm_delete_multi_title': 'Delete {n} Entries',
    'notebook.confirm_delete_multi_msg': '{n} entries will be permanently deleted.'
  },
  de: {
    // Navigation
    navHistory: 'Verlauf',
    navSettings: 'Einstellungen',
    navAbout: 'Über',

    // Settings — General
    settingsTitle: 'Einstellungen',
    cardApiKey: 'API-Schlüssel',
    labelApiKey: 'OpenAI API-Schlüssel',
    hintApiKey: 'Schlüssel benötigt?',
    hintApiKeyLink: 'API-Schlüssel erhalten →',
    cardMode: 'Aufnahmemodus',
    modePush: 'Push to Talk',
    modePushDesc: 'Hotkey gedrückt halten zum Aufnehmen',
    modeToggle: 'Umschalten',
    modeToggleDesc: 'Drücken zum Starten, erneut drücken zum Stoppen',
    cardHotkey: 'Tastenkürzel',
    labelHotkey: 'Aktuelles Tastenkürzel',
    cardLanguage: 'Transkriptionssprache',
    labelLanguage: 'Sprache',
    langAuto: 'Automatisch erkennen',
    langEn: 'Englisch',
    langDe: 'Deutsch',
    langEs: 'Spanisch',
    langFr: 'Französisch',
    langIt: 'Italienisch',
    langPt: 'Portugiesisch',
    langJa: 'Japanisch',
    langZh: 'Chinesisch',
    langKo: 'Koreanisch',
    langRu: 'Russisch',
    langAr: 'Arabisch',
    langHi: 'Hindi',
    cardOverlay: 'Overlay-Position',
    overlayTop: 'Oben Mitte',
    overlayTopDesc: 'Fest am oberen Bildschirmrand',
    overlayCursor: 'Beim Cursor',
    overlayCursorDesc: 'Folgt der Mausposition',
    cardFeedback: 'Einstellungen',
    labelSound: 'Tonsignale',
    descSound: 'Töne abspielen beim Starten und Stoppen der Aufnahme',
    labelVolume: 'Lautstärke',
    labelAutoPaste: 'Auto-Einfügen',
    descAutoPaste: 'Transkription automatisch ins aktive Feld einfügen',
    labelCheckUpdates: 'Nach Updates suchen',
    descCheckUpdates: 'Automatisch nach neuen Versionen suchen',
    labelAutostart: 'Mit Windows starten',
    descAutostart: 'WhisPaste beim Anmelden automatisch starten',
    labelTheme: 'Erscheinungsbild',
    themeSystem: 'System',
    themeLight: 'Hell',
    themeDark: 'Dunkel',

    // Settings — Smart Mode
    cardSmartMode: 'Smart Modus',
    labelSmartMode: 'KI-Nachbearbeitung',
    descSmartMode: 'Transkription mit GPT-4o-mini für Grammatik, Formatierung oder Übersetzung verarbeiten',
    labelSmartPreset: 'Vorlage',
    smartCleanup: 'Bereinigung (Grammatik & Zeichensetzung)',
    smartEmail: 'E-Mail (formell)',
    smartBullets: 'Aufzählung',
    smartFormal: 'Formeller Brief',
    smartTranslate: 'Übersetzen',
    smartCustom: 'Eigene Anweisung',
    labelSmartTarget: 'Zielsprache',
    labelSmartPrompt: 'Eigene Anweisung',

    // Settings — Advanced
    cardAdvanced: 'Erweitert',
    labelPrompt: 'Whisper-Prompt',
    descPrompt: 'Genauigkeit für Fachbegriffe verbessern (z.B. Kubernetes, kubectl)',
    labelMaxDuration: 'Maximale Aufnahmedauer',
    labelUnlimited: '∞ Unbegrenzt',

    // Settings — Actions
    btnTest: 'Testen',
    btnCancel: 'Abbrechen',
    btnSave: 'Speichern',
    statusSaved: 'Einstellungen gespeichert ✓',
    statusError: 'Fehler beim Speichern',
    statusTesting: 'Aufnahme…',
    statusTestDone: 'Test abgeschlossen',
    statusTestError: 'Test fehlgeschlagen',
    eyeShow: 'API-Schlüssel anzeigen',
    eyeHide: 'API-Schlüssel verbergen',
    btnChangeHotkey: 'Ändern',
    hotkeyRecording: 'Gewünschte Tastenkombination drücken…',
    hotkeyHint: 'Escape zum Abbrechen',

    // Settings — Local STT  
    cardLocalSTT: 'Lokale Transkription',
    labelLocalSTT: 'Lokales Modell verwenden',
    descLocalSTT: 'Offline transkribieren mit einem lokalen Whisper-Modell — kein API-Schlüssel erforderlich',
    labelLocalModel: 'Modell',
    modelDownload: 'Herunterladen',
    modelDownloading: 'Wird heruntergeladen…',
    modelDownloaded: 'Heruntergeladen',
    modelDelete: 'Modell löschen',
    modelDownloadDone: 'Modell erfolgreich heruntergeladen',
    modelDownloadError: 'Modell-Download fehlgeschlagen',
    modelDeleted: 'Modell gelöscht',
    modelNotDownloaded: 'nicht heruntergeladen',
    modelNeedDownload: 'Modell zuerst herunterladen, um es auszuwählen',

    // Mode badge
    modeLocal: 'Lokal',
    modeApi: 'API',
    modeLocalTip: 'Transkription über lokales Whisper-Modell (offline)',
    modeApiTip: 'Transkription über OpenAI Whisper API',

    // About
    aboutDesc: 'Ein schnelles, schlankes Sprache-zu-Text-Tool für Windows. Sprache aufnehmen und die Transkription sofort überall einfügen.',
    aboutLicense: 'Open Source – MIT-Lizenz',
    aboutGithub: 'GitHub',
    aboutIssue: 'Fehler melden',
    aboutCreditsTitle: 'Danksagungen',
    aboutCreditsText: 'Erstellt von Silvio Lindstedt. Basierend auf der OpenAI Whisper API. Entwickelt mit Go und WebView2.',
    aboutSupportTitle: 'Projekt unterstützen',
    aboutSupportText: 'WhisPaste ist kostenlos und Open Source. Wenn du es nützlich findest, unterstütze gerne die Weiterentwicklung!',
    aboutCostTitle: 'API-Kosten',
    aboutCostText: 'Whisper wird pro Audiominute abgerechnet (~0,006 $/Min). Ein kurzer Satz kostet Bruchteile eines Cents; typische Monatskosten liegen bei 1–5 €.',
    costOccasional: 'Gelegentlich (~5 Min./Tag)',
    costRegular: 'Regelmäßig (~20 Min./Tag)',
    costHeavy: 'Viel (~60 Min./Tag)',

    // Notebook
    'notebook.title': 'Verlauf',
    'notebook.search': 'Transkriptionen durchsuchen…',
    'notebook.all': 'Alle',
    'notebook.pinned': 'Angepinnt',
    'notebook.today': 'Heute',
    'notebook.week': 'Diese Woche',
    'notebook.older': 'Älter',
    'notebook.categories': 'Tags',
    'notebook.sort_newest': 'Neueste zuerst',
    'notebook.sort_oldest': 'Älteste zuerst',
    'notebook.sort_alpha': 'Alphabetisch',
    'notebook.sort_duration': 'Nach Dauer',
    'notebook.empty': 'Noch keine Einträge.',
    'notebook.no_results': 'Keine passenden Einträge.',
    'notebook.copy': 'Kopieren',
    'notebook.pin': 'Anheften',
    'notebook.unpin': 'Lösen',
    'notebook.delete': 'Löschen',
    'notebook.copied': 'Kopiert!',
    'notebook.tag_updated': 'Tag aktualisiert',
    'notebook.add_tag': 'Tag hinzufügen…',
    'notebook.confirm_title': 'Eintrag löschen',
    'notebook.confirm_msg': 'Dieser Eintrag wird dauerhaft gelöscht.',
    'notebook.confirm_cancel': 'Abbrechen',
    'notebook.confirm_delete': 'Löschen',
    'notebook.selected': 'ausgewählt',
    'notebook.delete_selected': 'Löschen',
    'notebook.confirm_delete_multi_title': '{n} Einträge löschen',
    'notebook.confirm_delete_multi_msg': '{n} Einträge werden dauerhaft gelöscht.'
  }
};

let currentLang = 'en';

/** Apply translations to all data-i18n elements */
function applyTranslations() {
  const t = translations[currentLang];
  if (!t) return;
  document.documentElement.lang = currentLang;

  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (t[key] != null) el.textContent = t[key];
  });
  document.querySelectorAll('[data-i18n-opt]').forEach(el => {
    const key = el.getAttribute('data-i18n-opt');
    if (t[key] != null) el.textContent = t[key];
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    const key = el.getAttribute('data-i18n-placeholder');
    if (t[key] != null) el.placeholder = t[key];
  });
  document.querySelectorAll('[data-i18n-tooltip]').forEach(el => {
    const key = el.getAttribute('data-i18n-tooltip');
    if (t[key] != null) el.setAttribute('data-tooltip', t[key]);
  });
}

/** Set UI language */
function setLang(lang) {
  currentLang = lang;
  applyTranslations();
}

/** Get translation value by key */
function t(key) {
  return (translations[currentLang] || {})[key] || key;
}
