export const i18n: Record<string, Record<string, string>> = {
  en: {
    'hero.title1': 'Press. Speak.',
    'hero.title2': 'Done.',
    'hero.desc': 'WhisPaste turns your voice into text — right where your cursor is. In any Windows app, offline or online, without a subscription.',
    'hero.download': 'Download for Windows',
    'hero.store.hint': 'Supports the project – thank you!',
    'hero.free.link': 'or download free from GitHub',
    'hero.installer': 'Installer & more options',
    'hero.meta': 'Windows 10/11 · Just download and run · Free & open source',
    'hero.trust.anywhere': 'Open source',
    'hero.trust.private': 'Privacy-first',
    'hero.trust.nosub': 'No subscription',
    'nav.howitworks': 'How It Works',
    'nav.pricing': 'Pricing',
    'nav.faq': 'FAQ',
    'nav.download': 'Download',
    'nav.back': '← Back',
    'nav.mainAria': 'Main navigation',
    'nav.footerAria': 'Footer navigation',
    'nav.switchLanguageAria': 'Switch language',
    'nav.toggleThemeAria': 'Toggle theme',
    'nav.toggleThemeTitle': 'Toggle theme',
    'nav.githubAria': 'WhisPaste on GitHub',
    'nav.sponsorAria': 'Support WhisPaste',
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
    'privacy.title': 'Your voice stays yours',
    'privacy.desc': 'Local transcription by default. No server in between. No analytics watching you.',
    'privacy.offline.title': 'Works offline',
    'privacy.offline.desc': 'Whisper runs on your CPU. Audio never leaves your device.',
    'privacy.telemetry.title': 'No telemetry',
    'privacy.telemetry.desc': 'No analytics, no tracking, no phone-home. Open source.',
    'privacy.directapi.title': 'Cloud is optional',
    'privacy.directapi.desc': 'If you use OpenAI, your data goes directly there. We never touch it.',
    'pricing.label': 'Pricing',
    'pricing.price': '$0',
    'pricing.title': 'Free. Forever. No catch.',
    'pricing.desc': 'No server costs, no subscription trap. WhisPaste runs on your machine, so there\'s nothing to charge you for.',
    'pricing.forever': 'forever — no trial, no limits',
    'pricing.feature.offline': 'Offline transcription',
    'pricing.feature.snippets': 'Voice Snippets',
    'pricing.feature.smartmode': 'Smart Mode',
    'pricing.feature.history': 'History & search',
    'pricing.feature.updates': 'Auto-updates',
    'pricing.feature.opensource': 'Open source (MIT)',
    'languages.label': 'Languages',
    'languages.title': 'Speaks your language',
    'languages.desc': 'WhisPaste supports 99 languages through Whisper — whether you dictate in English, switch to German mid-sentence, or work in Japanese.',
    'languages.more': '+80 more',
    'faq.label': 'FAQ',
    'faq.title': 'Good questions, honest answers',
    'faq.free.q': 'Is WhisPaste really free?',
    'faq.free.a': 'Yes — completely free, open source under the MIT license. No trial period, no feature gates, no "premium tier" later. It runs on your machine, so there are no server costs to pass on to you.',
    'faq.offline.q': 'Does it actually work offline?',
    'faq.offline.a': 'Fully. WhisPaste ships with local Whisper models that run entirely on your CPU. No internet connection needed. If you want, you can also use OpenAI\'s cloud API for higher accuracy — but that\'s your choice, not a requirement.',
    'faq.accuracy.q': 'How accurate is the transcription?',
    'faq.accuracy.a': 'That depends on the model you pick. The small model handles everyday dictation well. Larger models are more precise but need more RAM and processing time. You can switch any time and find your own sweet spot.',
    'faq.languages.q': 'Which languages are supported?',
    'faq.languages.a': 'Whisper supports 99 languages — from English and German to Japanese, Arabic, and Hindi. You can switch languages in settings, or let WhisPaste auto-detect what you\'re speaking.',
    'faq.privacy.q': 'Is my voice data safe?',
    'faq.privacy.a': 'Your audio never leaves your machine in local mode. If you use the cloud path, recordings go directly from your device to OpenAI\'s API — WhisPaste doesn\'t proxy, store, or touch them. No telemetry, no analytics, no tracking.',
    'faq.windows.q': 'Windows only — what about Mac or Linux?',
    'faq.windows.a': 'Right now, WhisPaste is built for Windows 10 and 11. macOS support is being explored. The core is designed to be portable, but a proper Mac version takes time to do right.',
    'faq.smartscreen.q': 'Why does Windows show a warning when I download?',
    'faq.smartscreen.a': 'Microsoft SmartScreen warns about any new software that hasn\'t built download reputation yet — it doesn\'t mean the app is unsafe. WhisPaste is open source, and every release is built transparently through GitHub Actions. Click "More info" → "Run anyway" to proceed.',
    'download.title': 'Download WhisPaste',
    'download.subtitle': 'Choose your preferred installation method.',
    'download.store.title': 'Microsoft Store',
    'download.store.recommended': 'Recommended',
    'download.store.desc': 'The easiest way to install WhisPaste — and supports the project.',
    'download.store.benefit1': 'Automatic updates',
    'download.store.benefit2': 'No SmartScreen warnings',
    'download.store.benefit3': 'Verified by Microsoft',
    'download.store.benefit4': 'Supports the developer',
    'download.store.hint': 'A small purchase that keeps the project alive – thank you!',
    'download.store.fallback': 'Get it from Microsoft Store',
    'download.github.title': 'Free from GitHub',
    'download.github.desc': 'Download the latest release directly. Open source and always free.',
    'download.github.button': 'Download from GitHub',
    'download.smartscreen.title': 'Important: SmartScreen warning',
    'download.smartscreen.desc': 'When downloading from GitHub, Windows may show security warnings. This is normal for new open-source software:',
    'download.step1.title': 'Browser blocks the download',
    'download.step1.desc': 'Chrome or Edge may show "not commonly downloaded". Click the arrow (↑) or "…" menu next to the download bar, then select "Keep".',
    'download.step2.title': 'SmartScreen warning appears',
    'download.step2.desc': 'When you run the installer, Windows may show "Windows protected your PC". Click "More info", then "Run anyway".',
    'download.step3.title': 'Install and run WhisPaste',
    'download.step3.desc': 'Follow the installer steps — WhisPaste will be ready in seconds.',
    'download.trust.title': 'Why the warning?',
    'download.trust.desc': 'Microsoft SmartScreen warns about any new software that hasn\'t built download reputation — regardless of whether it\'s safe. WhisPaste is fully open source and every release is built transparently through GitHub Actions.',
    'download.trust.opensource': 'Open source on GitHub',
    'download.trust.cicd': 'Built via GitHub Actions',
    'download.trust.notelemetry': 'No telemetry or tracking',
    'sponsor.title': 'Support WhisPaste',
    'sponsor.desc': 'WhisPaste is free and open source — no ads, no subscriptions, no data collection. Your support helps keep it that way.',
    'sponsor.github.title': 'GitHub Sponsors',
    'sponsor.github.subtitle': 'Monthly or one-time',
    'sponsor.github.desc': 'Support directly through GitHub. Choose a monthly tier or make a one-time contribution. Includes sponsor badge on your profile.',
    'sponsor.github.cta': 'Sponsor on GitHub',
    'sponsor.kofi.title': 'Ko-fi',
    'sponsor.kofi.subtitle': 'Buy me a coffee',
    'sponsor.kofi.desc': 'A quick one-time contribution through Ko-fi. No account needed — just pick an amount and support the project.',
    'sponsor.kofi.cta': 'Support on Ko-fi',
    'sponsor.whathelps.title': 'What your support covers',
    'sponsor.whathelps.dev': 'Active development & new features',
    'sponsor.whathelps.infra': 'Infrastructure & code signing',
    'sponsor.whathelps.free': 'Keeping WhisPaste free for everyone',
    'sponsor.whathelps.indie': 'Supporting independent open source',
    'footer.impressum': 'Legal Notice',
    'footer.privacy': 'Privacy Policy',
    'footer.privacy.href': '/privacy/',
    'footer.license': 'MIT License',
    'footer.sponsor': 'Sponsor',
    'carousel.press_hotkey': 'Press your hotkey',
    'carousel.speak_now': 'Speak now',
    'carousel.editor_title': 'Text Editor',
    'carousel.auto_pasted': 'Auto-pasted!',
    'carousel.tablistAria': 'Carousel slides',
    'carousel.slide1Aria': 'Slide 1: Press hotkey',
    'carousel.slide2Aria': 'Slide 2: Speak now',
    'carousel.slide3Aria': 'Slide 3: Auto-pasted',
  },
  de: {
    'hero.title1': 'Drücken. Sprechen.',
    'hero.title2': 'Fertig.',
    'hero.desc': 'WhisPaste macht aus deiner Stimme Text — genau dort, wo dein Cursor steht. In jeder Windows-App, offline oder online, ohne Abo.',
    'hero.download': 'Für Windows herunterladen',
    'hero.store.hint': 'Unterstützt das Projekt – danke!',
    'hero.free.link': 'oder kostenlos von GitHub laden',
    'hero.installer': 'Installer & weitere Optionen',
    'hero.meta': 'Windows 10/11 · Einfach herunterladen und starten · Kostenlos & Open Source',
    'hero.trust.anywhere': 'Open Source',
    'hero.trust.private': 'Privacy-first',
    'hero.trust.nosub': 'Kein Abo',
    'nav.howitworks': 'Wie funktioniert\u2019s',
    'nav.pricing': 'Preis',
    'nav.faq': 'FAQ',
    'nav.download': 'Download',
    'nav.back': '← Zurück',
    'nav.mainAria': 'Hauptnavigation',
    'nav.footerAria': 'Fußnavigation',
    'nav.switchLanguageAria': 'Sprache wechseln',
    'nav.toggleThemeAria': 'Designmodus wechseln',
    'nav.toggleThemeTitle': 'Designmodus wechseln',
    'nav.githubAria': 'WhisPaste auf GitHub',
    'nav.sponsorAria': 'WhisPaste unterstützen',
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
    'privacy.title': 'Deine Stimme bleibt bei dir',
    'privacy.desc': 'Lokale Transkription als Standard. Kein Server dazwischen. Keine Analytics, die dich beobachten.',
    'privacy.offline.title': 'Funktioniert offline',
    'privacy.offline.desc': 'Whisper läuft auf deiner CPU. Audio verlässt nie dein Gerät.',
    'privacy.telemetry.title': 'Keine Telemetrie',
    'privacy.telemetry.desc': 'Kein Tracking, keine Analyse, kein stilles Nachhausetelefonieren. Open Source.',
    'privacy.directapi.title': 'Cloud ist optional',
    'privacy.directapi.desc': 'Wenn du OpenAI nutzt, gehen deine Daten direkt dorthin. Wir fassen sie nie an.',
    'pricing.label': 'Preis',
    'pricing.price': '0 €',
    'pricing.title': 'Kostenlos. Für immer. Ohne Haken.',
    'pricing.desc': 'Keine Serverkosten, keine Abo-Falle. WhisPaste läuft auf deinem Rechner, also gibt es nichts, wofür wir dich zur Kasse bitten müssten.',
    'pricing.forever': 'für immer — kein Testzeitraum, keine Limits',
    'pricing.feature.offline': 'Offline-Transkription',
    'pricing.feature.snippets': 'Sprach-Snippets',
    'pricing.feature.smartmode': 'Smart-Modus',
    'pricing.feature.history': 'Verlauf & Suche',
    'pricing.feature.updates': 'Auto-Updates',
    'pricing.feature.opensource': 'Open Source (MIT)',
    'languages.label': 'Sprachen',
    'languages.title': 'Spricht deine Sprache',
    'languages.desc': 'WhisPaste unterstützt 99 Sprachen durch Whisper — egal ob du auf Deutsch diktierst, zwischendurch ins Englische wechselst oder auf Japanisch arbeitest.',
    'languages.more': '+80 weitere',
    'faq.label': 'FAQ',
    'faq.title': 'Gute Fragen, ehrliche Antworten',
    'faq.free.q': 'Ist WhisPaste wirklich kostenlos?',
    'faq.free.a': 'Ja — komplett kostenlos und Open Source unter der MIT-Lizenz. Kein Testzeitraum, keine Feature-Sperren, kein „Premium-Tier" später. Die App läuft auf deinem Rechner, also gibt es keine Serverkosten, die wir weitergeben müssten.',
    'faq.offline.q': 'Funktioniert es wirklich offline?',
    'faq.offline.a': 'Vollständig. WhisPaste bringt lokale Whisper-Modelle mit, die komplett auf deiner CPU laufen. Kein Internet nötig. Wenn du willst, kannst du auch OpenAIs Cloud-API nutzen — aber das ist deine Entscheidung, keine Voraussetzung.',
    'faq.accuracy.q': 'Wie genau ist die Transkription?',
    'faq.accuracy.a': 'Das hängt vom gewählten Modell ab. Das kleine Modell reicht für den Alltag gut aus. Größere Modelle sind präziser, brauchen aber mehr RAM und Rechenzeit. Du kannst jederzeit wechseln und deinen eigenen Sweet Spot finden.',
    'faq.languages.q': 'Welche Sprachen werden unterstützt?',
    'faq.languages.a': 'Whisper unterstützt 99 Sprachen — von Deutsch und Englisch über Japanisch und Arabisch bis Hindi. Du kannst die Sprache in den Einstellungen wählen oder WhisPaste automatisch erkennen lassen.',
    'faq.privacy.q': 'Sind meine Sprachdaten sicher?',
    'faq.privacy.a': 'Im lokalen Modus verlässt dein Audio nie deinen Rechner. Wenn du den Cloud-Weg nutzt, gehen die Aufnahmen direkt von deinem Gerät an OpenAIs API — WhisPaste leitet nichts weiter, speichert nichts und verarbeitet nichts. Keine Telemetrie, keine Analytics, kein Tracking.',
    'faq.windows.q': 'Nur Windows — was ist mit Mac oder Linux?',
    'faq.windows.a': 'Aktuell ist WhisPaste für Windows 10 und 11 gebaut. macOS-Support wird geprüft. Das Fundament ist portabel ausgelegt, aber eine saubere Mac-Version braucht ihre Zeit.',
    'faq.smartscreen.q': 'Warum zeigt Windows beim Download eine Warnung?',
    'faq.smartscreen.a': 'Microsoft SmartScreen warnt bei jeder neuen Software, die noch keine Download-Reputation aufgebaut hat — das bedeutet nicht, dass die App unsicher ist. WhisPaste ist Open Source, und jedes Release wird transparent über GitHub Actions gebaut. Klicke auf „Weitere Informationen" → „Trotzdem ausführen".',
    'download.title': 'WhisPaste herunterladen',
    'download.subtitle': 'Wähle deine bevorzugte Installationsmethode.',
    'download.store.title': 'Microsoft Store',
    'download.store.recommended': 'Empfohlen',
    'download.store.desc': 'Der einfachste Weg, WhisPaste zu installieren — und unterstützt das Projekt.',
    'download.store.benefit1': 'Automatische Updates',
    'download.store.benefit2': 'Keine SmartScreen-Warnungen',
    'download.store.benefit3': 'Von Microsoft verifiziert',
    'download.store.benefit4': 'Unterstützt den Entwickler',
    'download.store.hint': 'Ein kleiner Beitrag, der das Projekt am Leben hält – danke!',
    'download.store.fallback': 'Im Microsoft Store holen',
    'download.github.title': 'Kostenlos von GitHub',
    'download.github.desc': 'Lade das neueste Release direkt herunter. Open Source und immer kostenlos.',
    'download.github.button': 'Von GitHub herunterladen',
    'download.smartscreen.title': 'Wichtig: SmartScreen-Warnung',
    'download.smartscreen.desc': 'Beim Download von GitHub zeigt Windows möglicherweise Sicherheitswarnungen. Das ist bei neuer Open-Source-Software normal:',
    'download.step1.title': 'Browser blockiert den Download',
    'download.step1.desc': 'Chrome oder Edge zeigen eventuell „Wird nicht häufig heruntergeladen". Klicke auf den Pfeil (↑) oder das „…"-Menü neben der Downloadleiste und wähle „Beibehalten".',
    'download.step2.title': 'SmartScreen-Warnung erscheint',
    'download.step2.desc': 'Beim Starten des Installers zeigt Windows eventuell „Der Computer wurde durch Windows geschützt". Klicke auf „Weitere Informationen" → „Trotzdem ausführen".',
    'download.step3.title': 'WhisPaste installieren und starten',
    'download.step3.desc': 'Folge den Installationsschritten — WhisPaste ist in Sekunden einsatzbereit.',
    'download.trust.title': 'Warum die Warnung?',
    'download.trust.desc': 'Microsoft SmartScreen warnt bei jeder neuen Software, die noch keine Download-Reputation aufgebaut hat — unabhängig davon, ob sie sicher ist. WhisPaste ist vollständig Open Source und jedes Release wird transparent über GitHub Actions gebaut.',
    'download.trust.opensource': 'Open Source auf GitHub',
    'download.trust.cicd': 'Gebaut über GitHub Actions',
    'download.trust.notelemetry': 'Keine Telemetrie oder Tracking',
    'sponsor.title': 'WhisPaste unterstützen',
    'sponsor.desc': 'WhisPaste ist kostenlos und Open Source — keine Werbung, kein Abo, keine Datensammlung. Deine Unterstützung hilft, dass das so bleibt.',
    'sponsor.github.title': 'GitHub Sponsors',
    'sponsor.github.subtitle': 'Monatlich oder einmalig',
    'sponsor.github.desc': 'Unterstütze direkt über GitHub. Wähle eine monatliche Stufe oder leiste einen einmaligen Beitrag. Inklusive Sponsor-Badge auf deinem Profil.',
    'sponsor.github.cta': 'Auf GitHub sponsern',
    'sponsor.kofi.title': 'Ko-fi',
    'sponsor.kofi.subtitle': 'Kauf mir einen Kaffee',
    'sponsor.kofi.desc': 'Ein schneller einmaliger Beitrag über Ko-fi. Kein Konto nötig — einfach Betrag wählen und das Projekt unterstützen.',
    'sponsor.kofi.cta': 'Auf Ko-fi unterstützen',
    'sponsor.whathelps.title': 'Was deine Unterstützung bewirkt',
    'sponsor.whathelps.dev': 'Aktive Entwicklung & neue Features',
    'sponsor.whathelps.infra': 'Infrastruktur & Code-Signierung',
    'sponsor.whathelps.free': 'WhisPaste bleibt für alle kostenlos',
    'sponsor.whathelps.indie': 'Unabhängiges Open Source unterstützen',
    'footer.impressum': 'Impressum',
    'footer.privacy': 'Datenschutz',
    'footer.privacy.href': '/datenschutz/',
    'footer.license': 'MIT-Lizenz',
    'footer.sponsor': 'Sponsern',
    'carousel.press_hotkey': 'Drücke dein Tastenkürzel',
    'carousel.speak_now': 'Sprich jetzt',
    'carousel.editor_title': 'Texteditor',
    'carousel.auto_pasted': 'Automatisch eingefügt!',
    'carousel.tablistAria': 'Carousel-Folien',
    'carousel.slide1Aria': 'Folie 1: Tastenkürzel drücken',
    'carousel.slide2Aria': 'Folie 2: Jetzt sprechen',
    'carousel.slide3Aria': 'Folie 3: Automatisch eingefügt',
  }
};

function detectBrowserLang(): string {
  if (typeof navigator === 'undefined') return 'en';
  const supported = ['de', 'en'];
  const langs = (navigator.languages ?? [navigator.language]).filter(Boolean);
  for (const lang of langs) {
    const prefix = lang.split('-')[0].toLowerCase();
    if (supported.includes(prefix)) return prefix;
  }
  return 'en';
}

function loadInitialLang(): string {
  if (typeof window === 'undefined' || typeof localStorage === 'undefined') {
    return 'en';
  }
  return localStorage.getItem('whispaste-lang') || detectBrowserLang();
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
  document.querySelectorAll<HTMLElement>('.lang-toggle-btn').forEach(btn => {
    btn.textContent = currentLang === 'en' ? 'DE' : 'EN';
  });
  // Update MS Store badge language
  document.querySelectorAll('ms-store-badge').forEach(el => {
    el.setAttribute('language', currentLang);
  });
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
