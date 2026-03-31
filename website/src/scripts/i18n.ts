export const i18n: Record<string, Record<string, string>> = {
  en: {
    'hero.title1': 'Press. Speak.',
    'hero.title2': 'Done.',
    'hero.desc': 'WhisPaste turns your voice into text right where your cursor is. In any Windows app, fully offline or with the cloud provider you choose. No subscription.',
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
    'privacy.desc': 'Local when you want it. Cloud only when you choose it. No analytics watching you.',
    'privacy.offline.title': 'Works offline',
    'privacy.offline.desc': 'Whisper runs on your CPU. Audio never leaves your device.',
    'privacy.telemetry.title': 'No telemetry',
    'privacy.telemetry.desc': 'No analytics, no tracking. Optional crash reports go through a secured relay and can be turned off.',
    'privacy.directapi.title': 'Cloud is optional',
    'privacy.directapi.desc': 'If you use cloud transcription, audio goes straight to the provider you selected. We do not proxy it.',
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
    'faq.offline.a': 'Fully. WhisPaste ships with local Whisper models that run entirely on your CPU. No internet connection needed. If you want, you can also use a supported cloud provider for higher accuracy — but that\'s your choice, not a requirement.',
    'faq.accuracy.q': 'How accurate is the transcription?',
    'faq.accuracy.a': 'That depends on the model you pick. The small model handles everyday dictation well. Larger models are more precise but need more RAM and processing time. You can switch any time and find your own sweet spot.',
    'faq.languages.q': 'Which languages are supported?',
    'faq.languages.a': 'Whisper supports 99 languages — from English and German to Japanese, Arabic, and Hindi. You can switch languages in settings, or let WhisPaste auto-detect what you\'re speaking.',
    'faq.privacy.q': 'Is my voice data safe?',
    'faq.privacy.a': 'Your audio never leaves your machine in local mode. If you use the cloud path, recordings go directly from your device to the provider you selected — WhisPaste does not proxy or store them. Optional crash reports are transparent and can be turned off any time.',
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
    'download.github.desc': 'Download the latest public release directly. Open source, transparent, and always free.',
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
    'download.trust.notelemetry': 'No tracking in the app',
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
    'footer.changelog': 'Changelog',
    'footer.sponsor': 'Sponsor',
    'changelog.title': 'What\'s New',
    'changelog.desc': 'All recent updates and improvements at a glance.',
    'changelog.latest': 'Latest',
    'changelog.highlights': 'Highlights',
    'changelog.improvements': 'Improvements',
    'changelog.allreleases': 'View all releases on GitHub',
    'changelog.1.1.2.highlight.0': 'Smart Mode now works reliably with all local AI models, including smaller ones',
    'changelog.1.1.2.highlight.1': 'The app icon displays cleanly in the Windows taskbar — no more blue corners on rounded icons',
    'changelog.1.1.2.highlight.2': 'Dictation now pastes correctly into the new Outlook app on Windows 11',
    'changelog.1.1.2.highlight.3': 'Custom templates can be edited and deleted again without issues',
    'changelog.1.1.2.highlight.4': 'The recording interface is smoother with a clearer result display',
    'changelog.1.1.2.improvement.0': 'The app detects potential problems earlier and reports them before you notice',
    'changelog.1.1.2.improvement.1': 'Local AI processing is more stable and recovers gracefully from errors',
    'changelog.1.1.2.improvement.2': 'Stronger privacy protections and security hardening throughout the app',
    'changelog.1.1.1.highlight.0': 'New onboarding wizard guides you through setup in just a few steps',
    'changelog.1.1.1.highlight.1': 'GPU acceleration support for NVIDIA, AMD, and Intel graphics cards',
    'changelog.1.1.1.highlight.2': 'Multiple cloud providers now available: choose between local, OpenAI, Groq, or Deepgram for transcription',
    'changelog.1.1.1.improvement.0': 'Faster model downloads with resume support for interrupted connections',
    'changelog.1.1.1.improvement.1': 'Improved setup experience with automatic hardware detection',
    'changelog.1.1.0.highlight.0': 'Smart Mode: AI-powered post-processing transforms raw dictation into polished, context-aware text',
    'changelog.1.1.0.highlight.1': 'Voice Snippets: save and recall frequently used phrases with a single command',
    'changelog.1.1.0.highlight.2': 'Full history with search: find any past dictation instantly',
    'changelog.1.1.0.improvement.0': 'New design with premium look and feel throughout the app',
    'changelog.1.1.0.improvement.1': 'Available on the Microsoft Store for easy installation and auto-updates',
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
    'hero.desc': 'WhisPaste macht aus deiner Stimme Text — genau dort, wo dein Cursor steht. In jeder Windows-App, komplett offline oder mit dem Cloud-Anbieter deiner Wahl. Ohne Abo.',
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
    'privacy.desc': 'Lokal, wenn du willst. Cloud nur, wenn du sie auswählst. Keine Analytics, die dich beobachten.',
    'privacy.offline.title': 'Funktioniert offline',
    'privacy.offline.desc': 'Whisper läuft auf deiner CPU. Audio verlässt nie dein Gerät.',
    'privacy.telemetry.title': 'Keine Telemetrie',
    'privacy.telemetry.desc': 'Kein Tracking, keine Analytics. Optionale Crash-Reports laufen über ein gesichertes Relay und lassen sich jederzeit abschalten.',
    'privacy.directapi.title': 'Cloud ist optional',
    'privacy.directapi.desc': 'Wenn du Cloud-Transkription nutzt, geht dein Audio direkt an den ausgewählten Anbieter. Wir leiten es nicht weiter.',
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
    'faq.offline.a': 'Vollständig. WhisPaste bringt lokale Whisper-Modelle mit, die komplett auf deiner CPU laufen. Kein Internet nötig. Wenn du willst, kannst du auch einen unterstützten Cloud-Anbieter nutzen — aber das ist deine Entscheidung, keine Voraussetzung.',
    'faq.accuracy.q': 'Wie genau ist die Transkription?',
    'faq.accuracy.a': 'Das hängt vom gewählten Modell ab. Das kleine Modell reicht für den Alltag gut aus. Größere Modelle sind präziser, brauchen aber mehr RAM und Rechenzeit. Du kannst jederzeit wechseln und deinen eigenen Sweet Spot finden.',
    'faq.languages.q': 'Welche Sprachen werden unterstützt?',
    'faq.languages.a': 'Whisper unterstützt 99 Sprachen — von Deutsch und Englisch über Japanisch und Arabisch bis Hindi. Du kannst die Sprache in den Einstellungen wählen oder WhisPaste automatisch erkennen lassen.',
    'faq.privacy.q': 'Sind meine Sprachdaten sicher?',
    'faq.privacy.a': 'Im lokalen Modus verlässt dein Audio nie deinen Rechner. Wenn du den Cloud-Weg nutzt, gehen die Aufnahmen direkt von deinem Gerät an den ausgewählten Anbieter — WhisPaste leitet nichts weiter und speichert nichts davon. Optionale Crash-Reports sind transparent und lassen sich jederzeit abschalten.',
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
    'download.github.desc': 'Lade das neueste öffentliche Release direkt herunter. Open Source, transparent und immer kostenlos.',
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
    'download.trust.notelemetry': 'Kein Tracking in der App',
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
    'footer.changelog': 'Änderungsprotokoll',
    'footer.sponsor': 'Sponsern',
    'changelog.title': 'Neuigkeiten',
    'changelog.desc': 'Alle aktuellen Updates und Verbesserungen auf einen Blick.',
    'changelog.latest': 'Aktuell',
    'changelog.highlights': 'Highlights',
    'changelog.improvements': 'Verbesserungen',
    'changelog.allreleases': 'Alle Releases auf GitHub ansehen',
    'changelog.1.1.2.highlight.0': 'Smart Mode funktioniert jetzt zuverlässig mit allen lokalen KI-Modellen, auch kleineren',
    'changelog.1.1.2.highlight.1': 'Das App-Icon wird sauber in der Windows-Taskleiste angezeigt — keine blauen Ecken mehr',
    'changelog.1.1.2.highlight.2': 'Diktate werden jetzt korrekt in das neue Outlook unter Windows 11 eingefügt',
    'changelog.1.1.2.highlight.3': 'Benutzerdefinierte Vorlagen lassen sich wieder problemlos bearbeiten und löschen',
    'changelog.1.1.2.highlight.4': 'Die Aufnahmeoberfläche läuft flüssiger mit klarerer Ergebnisanzeige',
    'changelog.1.1.2.improvement.0': 'Die App erkennt mögliche Probleme früher und meldet sie, bevor du sie bemerkst',
    'changelog.1.1.2.improvement.1': 'Lokale KI-Verarbeitung ist stabiler und erholt sich besser von Fehlern',
    'changelog.1.1.2.improvement.2': 'Stärkerer Datenschutz und Sicherheitshärtung in der gesamten App',
    'changelog.1.1.1.highlight.0': 'Neuer Einrichtungsassistent führt dich in wenigen Schritten durch das Setup',
    'changelog.1.1.1.highlight.1': 'GPU-Beschleunigung für NVIDIA-, AMD- und Intel-Grafikkarten',
    'changelog.1.1.1.highlight.2': 'Mehrere Cloud-Anbieter verfügbar: wähle zwischen lokal, OpenAI, Groq oder Deepgram für die Transkription',
    'changelog.1.1.1.improvement.0': 'Schnellere Modell-Downloads mit Fortsetzung bei unterbrochenen Verbindungen',
    'changelog.1.1.1.improvement.1': 'Verbesserte Einrichtung mit automatischer Hardware-Erkennung',
    'changelog.1.1.0.highlight.0': 'Smart Mode: KI-gestützte Nachbearbeitung verwandelt rohe Diktate in polierten, kontextbewussten Text',
    'changelog.1.1.0.highlight.1': 'Sprach-Snippets: häufig genutzte Phrasen speichern und mit einem Befehl abrufen',
    'changelog.1.1.0.highlight.2': 'Vollständiger Verlauf mit Suche: jedes vergangene Diktat sofort finden',
    'changelog.1.1.0.improvement.0': 'Neues Design mit Premium-Look in der gesamten App',
    'changelog.1.1.0.improvement.1': 'Im Microsoft Store verfügbar für einfache Installation und Auto-Updates',
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
