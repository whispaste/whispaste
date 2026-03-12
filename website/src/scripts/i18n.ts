export const i18n: Record<string, Record<string, string>> = {
  en: {
    'hero.eyebrow': 'Hotkey dictation for real work',
    'hero.title1': 'Speak naturally.',
    'hero.title2': 'Text appears.',
    'hero.desc': 'WhisPaste brings your voice into any Windows app as text, snippets, or polished output — private by default, fast to start, and ready wherever your cursor is.',
    'hero.download': 'Download for Windows',
    'hero.github': 'View on GitHub',
    'hero.meta': 'Windows 10/11 · Installer or portable .exe · Free & open source',
    'hero.portable': 'Prefer portable? Get the standalone .exe',
    'hero.beta': 'Beta',
    'hero.trust.anywhere': 'Works in every Windows app',
    'hero.trust.private': 'Private by default',
    'hero.trust.nosub': 'No subscription',
    'nav.features': 'Why WhisPaste',
    'nav.howitworks': 'Workflow',
    'nav.back': '← Back',
    'nav.skip': 'Skip to content',
    'nav.mainAria': 'Main navigation',
    'nav.footerAria': 'Footer navigation',
    'nav.switchLanguageAria': 'Switch language',
    'nav.toggleThemeAria': 'Toggle theme',
    'nav.toggleThemeTitle': 'Toggle theme',
    'nav.githubAria': 'WhisPaste on GitHub',
    'features.label': 'Why WhisPaste',
    'features.title': 'One clean core workflow, then real depth.',
    'features.desc': 'Start with fast dictation and snippets. Go deeper only when you want cleanup, history, and power-user tools.',
    'features.core': 'Start here',
    'features.power': 'Go deeper when you need more',
    'features.hotkey.title': 'Global Hotkey',
    'features.hotkey.desc': 'Trigger dictation from anywhere with push-to-talk or toggle mode.',
    'features.autopaste.title': 'Auto-Paste',
    'features.autopaste.desc': 'Final text lands at your cursor automatically, with clipboard sync included.',
    'features.smartmode.title': 'Smart Mode',
    'features.smartmode.desc': 'Clean up, format, translate, or apply custom prompts with GPT or local LLMs.',
    'features.overlay.title': 'Premium Overlay',
    'features.overlay.desc': 'A clear recording overlay keeps status, timing, and controls visible while you speak.',
    'features.dashboard.title': 'Dashboard',
    'features.dashboard.desc': 'Search, tag, pin, archive, and organize transcriptions without losing the simple core flow.',
    'features.privacy.title': 'Privacy First',
    'features.privacy.desc': 'Stay local with Whisper models or choose cloud on purpose. No telemetry, no tracking.',
    'features.cmdpalette.title': 'Command Palette',
    'features.cmdpalette.desc': 'Press Ctrl+K to search history, trigger actions, and stay keyboard-first.',
    'features.vadexport.title': 'VAD & Export',
    'features.vadexport.desc': 'Silence trimming and exports help when dictation turns into notes, docs, or deliverables.',
    'features.snippets.title': 'Voice Snippets',
    'features.snippets.desc': 'Turn short trigger phrases into links, signatures, templates, and reusable replies.',
    'howitworks.label': 'Core flow',
    'howitworks.title': 'From thought to text in three calm steps',
    'howitworks.desc': 'No browser tab. No copy-paste ritual. Just speak and keep moving.',
    'howitworks.step1.label': 'Step 1',
    'howitworks.step1.title': 'Press Hotkey',
    'howitworks.step1.desc': 'Start from email, chat, docs, code, or anywhere your cursor already is.',
    'howitworks.step2.label': 'Step 2',
    'howitworks.step2.title': 'Speak naturally',
    'howitworks.step2.desc': 'WhisPaste transcribes locally or through the cloud path you explicitly choose.',
    'howitworks.step3.label': 'Step 3',
    'howitworks.step3.title': 'Paste, expand, or polish',
    'howitworks.step3.desc': 'Text appears at the cursor, with snippets and Smart Mode ready when you need extra help.',
    'privacy.label': 'Trust',
    'privacy.title': 'Private by default. Clear when cloud is involved.',
    'privacy.desc': 'Use local transcription for maximum control, or choose the direct OpenAI path when it fits your workflow.',
    'privacy.offline.title': 'Works offline',
    'privacy.offline.desc': 'Transcribe locally with built-in Whisper models. Your audio stays on your device and works without internet.',
    'privacy.apikey.title': 'API key stays local',
    'privacy.apikey.desc': 'If you use OpenAI, your API key stays only in your local user profile.',
    'privacy.directapi.title': 'Direct API connection',
    'privacy.directapi.desc': 'Cloud transcription goes directly from your device to OpenAI. WhisPaste does not proxy, store, or process your recordings.',
    'privacy.updates.title': 'Secure updates',
    'privacy.updates.desc': 'Updates are delivered over HTTPS and verified with SHA256 checksums before install.',
    'privacy.telemetry.title': 'No telemetry',
    'privacy.telemetry.desc': 'No analytics, no tracking, no silent phone-home. The app is open source.',
    'support.title': 'Keep WhisPaste improving',
    'support.desc': 'If WhisPaste saves you time, you can help fund polish, fixes, and more local-first improvements.',
    'support.sponsor': 'Sponsor on GitHub',
    'support.coffee': 'Buy a Coffee',
    'footer.impressum': 'Legal Notice',
    'footer.privacy': 'Privacy Policy',
    'footer.privacy.href': '/privacy/',
    'footer.license': 'MIT License',
    'carousel.press_hotkey': 'Press your hotkey',
    'carousel.recording': 'Recording',
    'carousel.speak_now': 'Speak now',
    'carousel.editor_title': 'Text Editor',
    'carousel.auto_pasted': 'Auto-pasted!',
    'carousel.tablistAria': 'Carousel slides',
    'carousel.slide1Aria': 'Slide 1: Press hotkey',
    'carousel.slide2Aria': 'Slide 2: Speak now',
    'carousel.slide3Aria': 'Slide 3: Auto-pasted',
    'mockup.searchPlaceholder': 'Search transcriptions...',
    'mockup.sortNewest': 'Newest first',
    'mockup.filterAll': 'All',
    'mockup.filterPinned': 'Pinned',
    'mockup.filterToday': 'Today',
    'mockup.filterThisWeek': 'This Week',
    'mockup.filterOlder': 'Older',
    'mockup.filterCustomRange': 'Custom Range',
    'mockup.tagsLabel': 'Tags',
    'mockup.projectsLabel': 'Projects',
    'mockup.projectWork': 'Work',
    'mockup.tagMeeting': 'meeting',
    'mockup.tagReminder': 'reminder',
    'mockup.tagProduct': 'product',
    'mockup.time2m': '2 min ago',
    'mockup.time15m': '15 min ago',
    'mockup.time1h': '1 hour ago',
    'mockup.time3h': '3 hours ago',
    'mockup.card1.title': 'Meeting notes from product sync',
    'mockup.card1.preview': 'Discussed the Q2 roadmap and prioritized the backlog items for the next sprint cycle...',
    'mockup.card2.title': 'Quick reminder about the deadline',
    'mockup.card2.preview': 'Don\'t forget to submit the final report by Friday end of day...',
    'mockup.card3.title': 'Client update email draft',
    'mockup.card3.badge': 'Email',
    'mockup.card3.preview': 'Hi team, I wanted to give you a quick update on the project status and next steps...',
    'mockup.card4.title': 'Ideas for the presentation',
    'mockup.card4.preview': 'We should start with the market analysis and then move into the competitive landscape...',
    'mockup.statusSmartMode': 'Smart Mode',
    'mockup.statusOn': 'ON',
    'mockup.statusLocal': 'Local',
    'mockup.statusCloud': 'Cloud',
    'preview.label': 'Workspace',
    'preview.title': 'A dictation workspace that stays organized',
    'preview.desc': 'Review recent captures, search fast, keep projects tidy, and reuse what matters — without turning the main flow into a bloated dashboard.'
  },
  de: {
    'hero.eyebrow': 'Diktat per Tastenkürzel für deinen Alltag',
    'hero.title1': 'Natürlich sprechen.',
    'hero.title2': 'Text erscheint.',
    'hero.desc': 'WhisPaste bringt deine Stimme als Text, Snippet oder aufbereitetes Ergebnis in jede Windows-App — standardmäßig privat, schnell startklar und genau dort, wo dein Cursor schon ist.',
    'hero.download': 'Für Windows herunterladen',
    'hero.github': 'Auf GitHub ansehen',
    'hero.meta': 'Windows 10/11 · Installer oder portable .exe · Kostenlos & Open Source',
    'hero.portable': 'Lieber portabel? Hol dir die portable .exe',
    'hero.beta': 'Beta',
    'hero.trust.anywhere': 'Funktioniert in jeder Windows-App',
    'hero.trust.private': 'Standardmäßig privat',
    'hero.trust.nosub': 'Kein Abo',
    'nav.features': 'Warum WhisPaste',
    'nav.howitworks': 'Ablauf',
    'nav.back': '← Zurück',
    'nav.skip': 'Zum Inhalt springen',
    'nav.mainAria': 'Hauptnavigation',
    'nav.footerAria': 'Fußnavigation',
    'nav.switchLanguageAria': 'Sprache wechseln',
    'nav.toggleThemeAria': 'Designmodus wechseln',
    'nav.toggleThemeTitle': 'Designmodus wechseln',
    'nav.githubAria': 'WhisPaste auf GitHub',
    'features.label': 'Warum WhisPaste',
    'features.title': 'Ein klarer Kernworkflow. Danach echte Tiefe.',
    'features.desc': 'Starte mit schnellem Diktat und Snippets. Geh nur dann tiefer, wenn du Nachbearbeitung, Verlauf und Power-Tools wirklich brauchst.',
    'features.core': 'Hier startest du',
    'features.power': 'Mehr Tiefe, wenn du sie brauchst',
    'features.hotkey.title': 'Globales Tastenkürzel',
    'features.hotkey.desc': 'Starte Diktat von überall per Push-to-Talk oder Toggle-Modus.',
    'features.autopaste.title': 'Auto-Einfügen',
    'features.autopaste.desc': 'Finaler Text landet automatisch an deinem Cursor, inklusive Zwischenablage-Sync.',
    'features.smartmode.title': 'Smart-Modus',
    'features.smartmode.desc': 'Bereinige, formatiere, übersetze oder nutze eigene Prompts mit GPT oder lokalem LLM.',
    'features.overlay.title': 'Premium-Overlay',
    'features.overlay.desc': 'Ein klares Aufnahme-Overlay hält Status, Dauer und Steuerung sichtbar, während du sprichst.',
    'features.dashboard.title': 'Dashboard',
    'features.dashboard.desc': 'Suche, tagge, pinne und organisiere Transkriptionen, ohne den einfachen Kernflow zu überladen.',
    'features.privacy.title': 'Privatsphäre zuerst',
    'features.privacy.desc': 'Bleib lokal mit Whisper-Modellen oder nutze bewusst die Cloud. Kein Tracking, keine Telemetrie.',
    'features.cmdpalette.title': 'Befehlspalette',
    'features.cmdpalette.desc': 'Drücke Strg+K, um den Verlauf zu durchsuchen, Aktionen auszuführen und konsequent per Tastatur zu arbeiten.',
    'features.vadexport.title': 'VAD & Export',
    'features.vadexport.desc': 'Stille-Erkennung und Exporte helfen, wenn aus Diktat Notizen, Dokumente oder Ergebnisse werden.',
    'features.snippets.title': 'Snippets',
    'features.snippets.desc': 'Verwandle kurze Triggerphrasen in Links, Signaturen, Vorlagen und wiederverwendbare Antworten.',
    'howitworks.label': 'Kernflow',
    'howitworks.title': 'Von Gedanken zu Text in drei ruhigen Schritten',
    'howitworks.desc': 'Kein Browser-Tab. Kein Copy-Paste-Ritual. Einfach sprechen und weitermachen.',
    'howitworks.step1.label': 'Schritt 1',
    'howitworks.step1.title': 'Tastenkürzel drücken',
    'howitworks.step1.desc': 'Starte aus Mail, Chat, Dokumenten, Code oder überall dort, wo dein Cursor schon ist.',
    'howitworks.step2.label': 'Schritt 2',
    'howitworks.step2.title': 'Natürlich sprechen',
    'howitworks.step2.desc': 'WhisPaste transkribiert lokal oder über den Cloud-Weg, den du bewusst auswählst.',
    'howitworks.step3.label': 'Schritt 3',
    'howitworks.step3.title': 'Einfügen, erweitern oder glätten',
    'howitworks.step3.desc': 'Der Text erscheint am Cursor, und Snippets oder Smart Mode helfen dir nur dann weiter, wenn du mehr willst.',
    'privacy.label': 'Vertrauen',
    'privacy.title': 'Standardmäßig privat. Klar, wenn Cloud im Spiel ist.',
    'privacy.desc': 'Nutze lokale Transkription für maximale Kontrolle oder den direkten OpenAI-Weg, wenn er besser zu deinem Workflow passt.',
    'privacy.offline.title': 'Funktioniert offline',
    'privacy.offline.desc': 'Transkribiere lokal mit integrierten Whisper-Modellen. Dein Audio bleibt auf deinem Gerät und funktioniert ohne Internet.',
    'privacy.apikey.title': 'API-Schlüssel bleibt lokal',
    'privacy.apikey.desc': 'Wenn du OpenAI nutzt, bleibt dein API-Schlüssel ausschließlich in deinem lokalen Benutzerprofil.',
    'privacy.directapi.title': 'Direkte API-Verbindung',
    'privacy.directapi.desc': 'Cloud-Transkription geht direkt von deinem Gerät zu OpenAI. WhisPaste leitet deine Aufnahmen nicht über eigene Server, speichert sie nicht und verarbeitet sie nicht selbst.',
    'privacy.updates.title': 'Sichere Updates',
    'privacy.updates.desc': 'Updates kommen per HTTPS und werden vor der Installation mit SHA256-Prüfsummen verifiziert.',
    'privacy.telemetry.title': 'Keine Telemetrie',
    'privacy.telemetry.desc': 'Keine Analyse, kein Tracking, kein stilles Nachhausetelefonieren. Die App ist Open Source.',
    'support.title': 'Hilf mit, WhisPaste weiter zu verbessern',
    'support.desc': 'Wenn WhisPaste dir Zeit spart, kannst du damit Politur, Fixes und weitere Verbesserungen für lokale Nutzung unterstützen.',
    'support.sponsor': 'Auf GitHub sponsern',
    'support.coffee': 'Einen Kaffee ausgeben',
    'footer.impressum': 'Impressum',
    'footer.privacy': 'Datenschutz',
    'footer.privacy.href': '/datenschutz/',
    'footer.license': 'MIT-Lizenz',
    'carousel.press_hotkey': 'Drücke dein Tastenkürzel',
    'carousel.recording': 'Aufnahme',
    'carousel.speak_now': 'Sprich jetzt',
    'carousel.editor_title': 'Texteditor',
    'carousel.auto_pasted': 'Automatisch eingefügt!',
    'carousel.tablistAria': 'Carousel-Folien',
    'carousel.slide1Aria': 'Folie 1: Tastenkürzel drücken',
    'carousel.slide2Aria': 'Folie 2: Jetzt sprechen',
    'carousel.slide3Aria': 'Folie 3: Automatisch eingefügt',
    'mockup.searchPlaceholder': 'Transkriptionen suchen...',
    'mockup.sortNewest': 'Neueste zuerst',
    'mockup.filterAll': 'Alle',
    'mockup.filterPinned': 'Gepinnt',
    'mockup.filterToday': 'Heute',
    'mockup.filterThisWeek': 'Diese Woche',
    'mockup.filterOlder': 'Älter',
    'mockup.filterCustomRange': 'Eigener Zeitraum',
    'mockup.tagsLabel': 'Tags',
    'mockup.projectsLabel': 'Projekte',
    'mockup.projectWork': 'Arbeit',
    'mockup.tagMeeting': 'Meeting',
    'mockup.tagReminder': 'Erinnerung',
    'mockup.tagProduct': 'Produkt',
    'mockup.time2m': 'vor 2 Min.',
    'mockup.time15m': 'vor 15 Min.',
    'mockup.time1h': 'vor 1 Std.',
    'mockup.time3h': 'vor 3 Std.',
    'mockup.card1.title': 'Meeting-Notizen vom Produkt-Sync',
    'mockup.card1.preview': 'Wir haben die Q2-Roadmap besprochen und die wichtigsten Backlog-Themen für den nächsten Sprint priorisiert...',
    'mockup.card2.title': 'Kurze Erinnerung an die Deadline',
    'mockup.card2.preview': 'Denk daran, den finalen Bericht bis Freitagabend einzureichen...',
    'mockup.card3.title': 'Entwurf für das Kundenupdate per E-Mail',
    'mockup.card3.badge': 'E-Mail',
    'mockup.card3.preview': 'Hallo zusammen, ich wollte euch kurz zum Projektstand und zu den nächsten Schritten updaten...',
    'mockup.card4.title': 'Ideen für die Präsentation',
    'mockup.card4.preview': 'Wir sollten mit der Marktanalyse starten und danach auf das Wettbewerbsumfeld eingehen...',
    'mockup.statusSmartMode': 'Smart-Modus',
    'mockup.statusOn': 'AN',
    'mockup.statusLocal': 'Lokal',
    'mockup.statusCloud': 'Cloud',
    'preview.label': 'Arbeitsbereich',
    'preview.title': 'Ein Arbeitsbereich für Diktate, der organisiert bleibt',
    'preview.desc': 'Prüfe neue Aufnahmen, suche blitzschnell, halte Projekte sauber und greife Wiederverwendbares schnell wieder auf — ohne den Hauptflow in ein überladenes Dashboard zu verwandeln.'
  }
};

function loadInitialLang(): string {
  if (typeof window === 'undefined' || typeof localStorage === 'undefined') {
    return 'en';
  }
  return localStorage.getItem('whispaste-lang') || 'en';
}

export let currentLang: string = loadInitialLang();

export function toggleLang() {
  currentLang = currentLang === 'en' ? 'de' : 'en';
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem('whispaste-lang', currentLang);
  }
  applyLang();
}

export function applyLang() {
  document.documentElement.lang = currentLang;
  const btn = document.getElementById('langToggle');
  if (btn) btn.textContent = currentLang === 'en' ? 'DE' : 'EN';
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n')!;
    if (i18n[currentLang]?.[key]) {
      el.textContent = i18n[currentLang][key];
    }
  });
  document.querySelectorAll('[data-i18n-href]').forEach(el => {
    const key = el.getAttribute('data-i18n-href')!;
    if (i18n[currentLang]?.[key]) {
      (el as HTMLAnchorElement).href = i18n[currentLang][key];
    }
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    const key = el.getAttribute('data-i18n-placeholder')!;
    if (i18n[currentLang]?.[key]) {
      (el as HTMLInputElement).placeholder = i18n[currentLang][key];
    }
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    const key = el.getAttribute('data-i18n-title')!;
    if (i18n[currentLang]?.[key]) {
      el.setAttribute('title', i18n[currentLang][key]);
    }
  });
  document.querySelectorAll('[data-i18n-aria]').forEach(el => {
    const key = el.getAttribute('data-i18n-aria')!;
    if (i18n[currentLang]?.[key]) {
      el.setAttribute('aria-label', i18n[currentLang][key]);
    }
  });
}

// Expose globally for onclick handlers
(window as any).toggleLang = toggleLang;
(window as any).currentLang = currentLang;

// Keep window.currentLang in sync
const origToggle = toggleLang;
(window as any).toggleLang = function() {
  origToggle();
  (window as any).currentLang = currentLang;
};
