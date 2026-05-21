export type Locale = 'de' | 'en';

export const SUPPORTED_LOCALES: readonly Locale[] = ['de', 'en'];

export const DEFAULT_LOCALE: Locale = 'de';

export const i18n: Record<string, Record<string, string>> = {
  en: {
    'meta.title.default': 'WhisPaste — Voice to text, pasted anywhere',
    'meta.description.default': 'Desktop voice-input tool — turn your voice into text, offline or with cloud providers. Free & open source.',
    'meta.title.home': 'WhisPaste — Desktop voice input, private by default',
    'meta.description.home': 'WhisPaste turns your voice into text right where your cursor is — offline-first, with optional cloud providers. Free & open source for Windows and macOS.',
    'meta.title.download': 'Download WhisPaste',
    'meta.description.download': 'Download WhisPaste for Windows and macOS — via Microsoft Store, DMG, or free from GitHub.',
    'meta.title.privacy': 'Privacy Policy — WhisPaste',
    'meta.description.privacy': 'Privacy Policy for the WhisPaste desktop application. Learn how WhisPaste handles your data.',
    'meta.title.screenshots': 'Screenshots — WhisPaste',
    'meta.description.screenshots': 'See WhisPaste in action — workspace, detail editor, Voice Snippets, settings, and analytics in light and dark theme.',
    'meta.title.impressum': 'Legal Notice — WhisPaste',
    'meta.description.impressum': 'Legal Notice (Impressum) for WhisPaste — contact information and liability disclaimers.',
    'meta.title.sponsor': 'Support WhisPaste',
    'meta.description.sponsor': 'Support WhisPaste development via GitHub Sponsors or Ko-fi. Every contribution helps keep the project free, open source, and independent.',
    'meta.title.changelog': 'Changelog — WhisPaste',
    'meta.description.changelog': "See what's new in WhisPaste. All recent updates, improvements, and fixes in one place.",
    'schema.app.description': 'Desktop voice-input tool that brings your voice into any app as text — private by default, free & open source.',
    'nav.skip': 'Skip to content',
    'hero.title1': 'Press. Speak.',
    'hero.title2': 'Done.',
    'hero.desc': 'WhisPaste turns your voice into text right where your cursor is — fully offline or with the cloud provider you choose. Free and open source.',
    'hero.download': 'Download for Windows',
    'hero.store.hint': 'Supports the project – thank you!',
    'hero.free.link': 'or download free from GitHub',
    'hero.installer': 'Installer & more options',
    'hero.meta': 'Windows · macOS · Free & open source',
    'hero.trust.anywhere': 'Open source',
    'hero.trust.private': 'Privacy-first',
    'hero.trust.nosub': 'Free to use',
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
    'howitworks.label': 'Three steps',
    'howitworks.title': 'From thought to text — three steps, that\u2019s it.',
    'howitworks.desc': 'No browser tab. No copy-paste ritual. Just speak and keep moving.',
    'howitworks.step1.label': 'Step 1',
    'howitworks.step1.title': 'Press Hotkey',
    'howitworks.step1.desc': 'Start from email, chat, docs, code, or anywhere your cursor already is.',
    'howitworks.step2.label': 'Step 2',
    'howitworks.step2.title': 'Speak naturally',
    'howitworks.step2.desc': 'WhisPaste converts your speech to text — on your device or through a cloud provider you choose.',
    'howitworks.step3.label': 'Step 3',
    'howitworks.step3.title': 'Paste, expand, or polish',
    'howitworks.step3.desc': 'Text appears at the cursor — ready to use, edit, or expand with voice shortcuts.',
    'screenshots.label': 'Screenshots',
    'screenshots.title': 'Where your voice becomes text',
    'screenshots.desc': 'Speak, organize, refine. Here\u2019s how it looks in practice.',
    'screenshots.seeAll': 'Explore all screens →',
    'screenshots.workspace': 'Your transcripts at a glance',
    'screenshots.detail': 'Edit and refine each entry',
    'screenshots.shortcuts': 'Voice Snippets that save keystrokes',
    'screenshots.hotkey': 'Start your voice input with one key',
    'screenshots.insights': 'Track how you use your voice',
    'gallery.title': 'Every screen, every detail',
    'gallery.desc': 'Five views that show the full workflow — from voice input to polished text. Switch themes to find your style.',
    'gallery.themeDark': 'Dark',
    'gallery.themeLight': 'Light',
    'gallery.platformWindows': 'Windows',
    'gallery.platformMac': 'macOS',
    'gallery.workspace': 'Your transcripts at a glance',
    'gallery.detail': 'Edit and refine each entry',
    'gallery.shortcuts': 'Voice Snippets that save keystrokes',
    'gallery.settings': 'Customize to fit your workflow',
    'gallery.analytics': 'Track how you use your voice',
    'gallery.cta': 'Get WhisPaste — it\u2019s free',
    'privacy.label': 'Trust',
    'privacy.title': 'Your voice stays yours',
    'privacy.desc': 'Local when you want it. Cloud only when you choose it. No tracking. No analytics.',
    'privacy.offline.title': 'Works offline',
    'privacy.offline.desc': 'Transcription happens right on your computer. Audio never leaves your device.',
    'privacy.telemetry.title': 'No analytics',
    'privacy.telemetry.desc': 'No analytics, no tracking. Optional crash reports help us fix issues faster — you can turn them off any time.',
    'privacy.directapi.title': 'Cloud is optional',
    'privacy.directapi.desc': 'If you use cloud transcription, audio goes straight to the provider you selected. We do not proxy it.',
    'pricing.label': 'Pricing',
    'pricing.price': 'Open Source',
    'pricing.title': 'Free & open source.',
    'pricing.desc': 'The full app is free — offline transcription, voice snippets, GPU acceleration and more. Get it from the Store to support the project, or download free from GitHub.',
    'pricing.forever': 'MIT licensed — open source, forever',
    'pricing.feature.offline': 'Offline transcription',
    'pricing.feature.snippets': 'Voice Snippets',
    'pricing.feature.gpu': 'GPU acceleration',
    'pricing.feature.history': 'History & search',
    'pricing.feature.updates': 'Auto-updates',
    'pricing.feature.opensource': 'Open source (MIT)',
    'languages.label': 'Languages',
    'languages.title': 'Speaks your language',
    'languages.desc': 'WhisPaste supports 99 languages — whether you speak in English, switch to German mid-sentence, or work in Japanese.',
    'languages.more': '+80 more',
    'faq.label': 'FAQ',
    'faq.title': 'Good questions, honest answers',
    'faq.free.q': 'Is WhisPaste really free?',
    'faq.free.a': 'Yes. WhisPaste is open source under the MIT license. The app with offline transcription, Voice Snippets, history and more is free. You can download it from GitHub. The Microsoft Store version includes automatic updates and supports the project financially.',
    'faq.offline.q': 'Does it actually work offline?',
    'faq.offline.a': 'Fully. WhisPaste includes built-in speech recognition that runs entirely on your computer. No internet needed. If you want, you can also connect a cloud provider for even better accuracy — but that\u2019s your choice, not a requirement.',
    'faq.accuracy.q': 'How accurate is the transcription?',
    'faq.accuracy.a': 'That depends on the model you pick. The small model handles everyday voice input well. Larger models are more precise but need more RAM and processing time. You can switch any time to find the right balance.',
    'faq.sysreq.q': 'What are the system requirements?',
    'faq.sysreq.a': 'Minimum: Windows\u00a010 (64-bit) or macOS\u00a010.15 Catalina\u202f+\u00a0\u00b7 8\u202fGB RAM (required, enforced at startup)\u00a0\u00b7 1\u2013\u20132\u202fGB free disk space. No GPU required \u2014 WhisPaste always falls back to CPU. Recommended: 16\u202fGB RAM\u00a0\u00b7 dedicated GPU with 2\u2013\u20134\u202fGB VRAM (NVIDIA CUDA, AMD or Intel Vulkan) for 5\u202f\u00d7 faster transcription. GPU VRAM by model: compact ~300\u202fMB \u00b7 balanced ~900\u202fMB \u00b7 premium (turbo) ~2.6\u202fGB \u00b7 ultra ~3.6\u202fGB. Apple Silicon: unified memory counts for both CPU and GPU \u2014 8\u202fGB covers the balanced model.',
    'faq.languages.q': 'Which languages are supported?',
    'faq.languages.a': 'WhisPaste supports 99 languages — from English and German to Japanese, Arabic, and Hindi. You can switch languages in settings, or let WhisPaste auto-detect what you\'re speaking.',
    'faq.privacy.q': 'Is my voice data safe?',
    'faq.privacy.a': 'Your audio never leaves your machine in local mode. If you use the cloud path, recordings go directly from your device to the provider you selected — WhisPaste does not proxy or store them. Optional crash reports are transparent and can be turned off any time.',
    'faq.windows.q': 'Is WhisPaste available on Mac or Linux?',
    'faq.windows.a': 'WhisPaste is available for Windows and macOS. A Linux version is planned.',
    'faq.smartscreen.q': 'Why does Windows show a warning when I download?',
    'faq.smartscreen.a': 'Microsoft SmartScreen warns about any new software that hasn\'t built download reputation yet — it doesn\'t mean the app is unsafe. WhisPaste is open source, and every release is built transparently through GitHub Actions. Click "More info" → "Run anyway" to proceed.',
    'faq.gatekeeper.q': 'Why does macOS warn that WhisPaste can\u2019t be verified?',
    'faq.gatekeeper.a': 'macOS Gatekeeper blocks unrecognised apps downloaded outside the App Store. WhisPaste is not yet notarized by Apple \u2014 right-click the app \u2192 \u201cOpen\u201d \u2192 confirm in the dialog to proceed. Or install via the Mac App Store, which passes all Apple security checks automatically.',
    'testimonials.label': 'Testimonials',
    'testimonials.title': 'What our users say',
    'testimonials.subtitle': 'Real feedback from real people — no names, no tracking, just honest opinions.',
    'testimonials.empty': 'No testimonials available yet — be the first to share your experience!',
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
    'download.github.btnHint': 'Download for',
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
    'download.trust.notelemetry': 'No analytics or tracking',
    'download.macos.title': 'macOS (Apple Silicon)',
    'download.macos.desc': 'Download the latest macOS release directly from GitHub. Supports Apple M-series chips natively.',
    'download.macos.button': 'Download for macOS',
    'download.macos.hint': 'After downloading, open the DMG and drag WhisPaste to your Applications folder.',
    'download.macos.gatekeeper.title': 'Note: Gatekeeper warning',
    'download.macos.gatekeeper.desc': 'macOS may show "WhisPaste can\'t be opened because it is from an unidentified developer". Right-click the app, select "Open", then click "Open" in the dialog.',
    'sponsor.title': 'Support WhisPaste',
    'sponsor.desc': 'WhisPaste is free and open source — no ads, no data collection. Your support helps keep it that way.',
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
    'sponsor.free.title': 'Free ways to help',
    'sponsor.free.desc': 'Not every contribution has to be financial. These small actions make a real difference.',
    'sponsor.free.star': 'Star on GitHub',
    'sponsor.free.star.desc': 'Shows others the project is worth checking out. Takes two seconds.',
    'sponsor.free.share': 'Tell a friend',
    'sponsor.free.share.desc': 'The best recommendation is a personal one.',
    'support.title': 'Keep WhisPaste improving',
    'support.desc': 'If WhisPaste saves you time, you can help keep it going — every bit counts.',
    'support.sponsor': 'Sponsor on GitHub',
    'support.coffee': 'Buy a Coffee',
    'support.star': 'Star on GitHub — free and just as helpful',
    'footer.impressum': 'Legal Notice',
    'footer.privacy': 'Privacy Policy',
    'footer.privacy.href': '/en/privacy/',
    'footer.license': 'MIT License',
    'footer.changelog': 'Changelog',
    'footer.sponsor': 'Sponsor',
    'changelog.title': 'What\'s New',
    'changelog.desc': 'All recent updates and improvements at a glance.',
    'changelog.latest': 'Latest',
    'changelog.highlights': 'Highlights',
    'changelog.improvements': 'Improvements',
    'changelog.allreleases': 'View all releases on GitHub',
    'changelog.1.1.3.highlight.0': 'Redesigned dashboard, Post-Processing, and Voice Snippets screens with cleaner layout',
    'changelog.1.1.3.highlight.1': 'Post-Processing and Voice Snippets now have separate AI provider settings',
    'changelog.1.1.3.highlight.2': 'Unified silence removal replaces two confusing toggles with one smart setting',
    'changelog.1.1.3.highlight.3': 'Smooth page transitions and micro-animations for a premium feel',
    'changelog.1.1.3.highlight.4': 'Auto-generated tags now use Title Case and filter out system labels',
    'changelog.1.1.3.improvement.0': 'Settings reorganized with clearer sections and more descriptive labels',
    'changelog.1.1.3.improvement.1': 'Replaced technical jargon with everyday language throughout the app',
    'changelog.1.1.3.improvement.2': 'Fixed race condition during rapid page switching',
    'changelog.1.1.2.highlight.0': 'Post-Processing now works reliably with all local AI models, including smaller ones',
    'changelog.1.1.2.highlight.1': 'The app icon displays cleanly in the Windows taskbar — no more blue corners on rounded icons',
    'changelog.1.1.2.highlight.2': 'Transcripts now paste correctly into the new Outlook app on Windows 11',
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
    'changelog.1.1.0.highlight.0': 'Post-Processing: AI-powered text refinement transforms raw transcripts into polished, context-aware text',
    'changelog.1.1.0.highlight.1': 'Voice Snippets: save and recall frequently used phrases with a single command',
    'changelog.1.1.0.highlight.2': 'Full history with search: find any past transcript instantly',
    'changelog.1.1.0.improvement.0': 'New design with premium look and feel throughout the app',
    'changelog.1.1.0.improvement.1': 'Available on the Microsoft Store for easy installation and auto-updates',
    'changelog.1.2.1.highlight.0': 'macOS app now ships with every release as a native ARM64 DMG',
    'changelog.1.2.1.highlight.1': 'CI pipeline hardened: secret scanning, narrowed permissions, golden test isolation',
    'changelog.1.2.1.highlight.2': 'Direct download links for Windows (.exe) and macOS (.dmg) on the download page',
    'changelog.1.2.1.improvement.0': 'Release build fixed for macOS — icon font tree-shaking disabled to unblock builds',
    'changelog.1.2.1.improvement.1': 'macOS Gatekeeper instructions expanded with full step-by-step guide',
    'changelog.1.2.0.highlight.0': 'Complete rewrite as a native Flutter app — truly cross-platform (Windows and macOS)',
    'changelog.1.2.0.highlight.1': 'All transcript history stored locally in SQLite — no shared config files, no data loss',
    'changelog.1.2.0.highlight.2': 'New slim recording pill overlay with live waveform and progress indicator',
    'changelog.1.2.0.highlight.3': 'Always-on-top floating button for instant voice input from any app',
    'changelog.1.2.0.highlight.4': 'Premium UI with warm gradients, frosted glass effects, and micro-animations',
    'changelog.1.2.0.highlight.5': '469+ automated tests with over 90 percent feature coverage',
    'changelog.1.2.0.improvement.0': 'All Go backend code removed — zero external dependencies',
    'changelog.1.2.0.improvement.1': 'Riverpod state management for reactive, testable architecture',
    'changelog.1.2.0.improvement.2': 'CI/CD updated for Flutter-only builds with full macOS support',
    'hero.download.windows': 'Download for Windows',
    'hero.download.macos': 'Download for macOS',
    'hero.download.macos.hint': 'Download for',
    'hero.download.macos.platform': 'macOS',
    'download.macos.gatekeeper.step1.title': 'macOS blocks the app on first launch',
    'download.macos.gatekeeper.step1.desc': 'After opening the DMG and moving WhisPaste to Applications, macOS may refuse to open it — showing "Apple cannot check it for malicious software."',
    'download.macos.gatekeeper.step2.title': 'Open Privacy & Security settings',
    'download.macos.gatekeeper.step2.desc': 'Go to Apple menu → System Settings → Privacy & Security. Scroll down to the Security section.',
    'download.macos.gatekeeper.step3.title': 'Click "Open Anyway"',
    'download.macos.gatekeeper.step3.desc': 'You will see a message about WhisPaste. Click "Open Anyway" — this button is available for about one hour after the first launch attempt.',
    'download.macos.gatekeeper.step4.title': 'Confirm and enter your password',
    'download.macos.gatekeeper.step4.desc': 'Click "Open Anyway" again in the confirmation dialog, then enter your Mac login password when prompted.',
    'download.macos.gatekeeper.why.title': 'Why does this happen?',
    'download.macos.gatekeeper.why.desc': 'WhisPaste is open source and built transparently via GitHub Actions, but it is not yet notarized by Apple. This warning appears for any app not downloaded from the Mac App Store. It does not mean the app is unsafe.',
    'carousel.press_hotkey': 'Press your hotkey',
    'carousel.speak_now': 'Speak now',
    'carousel.editor_title': 'Text Editor',
    'carousel.auto_pasted': 'Auto-pasted!',
    'carousel.tablistAria': 'Carousel slides',
    'carousel.slide1Aria': 'Slide 1: Press hotkey',
    'carousel.slide2Aria': 'Slide 2: Speak now',
    'carousel.slide3Aria': 'Slide 3: Auto-pasted',
    'carousel.overlayLocal': 'Local',
    'store.btn.getfrom': 'Get it from',
    'store.btn.msstore': 'Microsoft Store',
    'store.btn.single': 'Get it on Microsoft Store',
    'downloadModal.heading': 'Your download is starting!',
    'downloadModal.body': 'WhisPaste is free — here\'s how to help it grow:',
    'downloadModal.starGitHub': '⭐ Star on GitHub',
    'downloadModal.rateMsStore': '★ Rate on Microsoft Store',
    'downloadModal.rateAppStore': '★ Rate on Mac App Store',
    'downloadModal.support': 'Or sponsor us on GitHub / buy a coffee',
    'downloadModal.maybeLater': 'Maybe later',
    'support.reviewHeading': 'Help others discover WhisPaste',
    'support.rateMsStore': 'Rate on Microsoft Store',
    'support.rateAppStore': 'Rate on Mac App Store',
    'hero.reviewNudge': 'Love it? A ★ on GitHub or a store review makes a real difference.',
    // Breadcrumb labels — sichtbar für Crawler im `BreadcrumbList`-Schema,
    // sub-page-`BreadcrumbListSchema.astro` zieht hier den Locale-passenden
    // Eintrag. Die `home`-Bezeichnung folgt der Brand-Glossar-Konvention
    // (kein „Start"/"Startseite" → schlichtes „Home"/"Start") und bleibt mit
    // den Nav-Aria-Labels konsistent.
    'breadcrumb.home': 'Home',
    'breadcrumb.download': 'Download',
    'breadcrumb.screenshots': 'Screenshots',
    'breadcrumb.privacy': 'Privacy Policy',
    'breadcrumb.impressum': 'Legal Notice',
    'breadcrumb.sponsor': 'Support',
    'breadcrumb.changelog': 'Changelog',
  },
  de: {
    'meta.title.default': 'WhisPaste — Spracheingabe direkt am Cursor',
    'meta.description.default': 'Desktop-Sprach-Eingabe-Tool — verwandelt deine Stimme in Text, offline oder mit Cloud-Anbietern. Kostenlos & Open Source.',
    'meta.title.home': 'WhisPaste — Spracheingabe für den Desktop, von Haus aus privat',
    'meta.description.home': 'WhisPaste macht aus deiner Stimme Text — genau dort, wo dein Cursor steht. Offline-first, optional mit Cloud-Anbietern. Kostenlos & Open Source für Windows und macOS.',
    'meta.title.download': 'WhisPaste herunterladen',
    'meta.description.download': 'WhisPaste für Windows und macOS herunterladen — über den Microsoft Store, als DMG oder kostenlos von GitHub.',
    'meta.title.privacy': 'Datenschutz — WhisPaste',
    'meta.description.privacy': 'Datenschutzerklärung für WhisPaste — wie die Website und die Desktop-App mit deinen Daten umgehen.',
    'meta.title.screenshots': 'Screenshots — WhisPaste',
    'meta.description.screenshots': 'WhisPaste in Aktion — Workspace, Detail-Editor, Sprach-Snippets, Einstellungen und Analytics in hellem und dunklem Design.',
    'meta.title.impressum': 'Impressum — WhisPaste',
    'meta.description.impressum': 'Impressum von WhisPaste — Kontaktdaten und Haftungshinweise.',
    'meta.title.sponsor': 'WhisPaste unterstützen',
    'meta.description.sponsor': 'Unterstütze die WhisPaste-Entwicklung über GitHub Sponsors oder Ko-fi. Jeder Beitrag hilft, das Projekt kostenlos, Open Source und unabhängig zu halten.',
    'meta.title.changelog': 'Änderungsprotokoll — WhisPaste',
    'meta.description.changelog': 'Was ist neu in WhisPaste? Alle aktuellen Updates, Verbesserungen und Fixes an einem Ort.',
    'schema.app.description': 'Desktop-Sprach-Eingabe-Tool, das deine Stimme als Text in jede App bringt — von Haus aus privat, kostenlos & Open Source.',
    'nav.skip': 'Zum Inhalt springen',
    'hero.title1': 'Drücken. Sprechen.',
    'hero.title2': 'Fertig.',
    'hero.desc': 'WhisPaste macht aus deiner Stimme Text — genau dort, wo dein Cursor steht. Komplett offline oder mit dem Cloud-Anbieter deiner Wahl. Kostenlos und Open Source.',
    'hero.download': 'Für Windows herunterladen',
    'hero.store.hint': 'Unterstützt das Projekt – danke!',
    'hero.free.link': 'oder kostenlos von GitHub laden',
    'hero.installer': 'Installer & weitere Optionen',
    'hero.meta': 'Windows · macOS · Kostenlos & Open Source',
    'hero.trust.anywhere': 'Open Source',
    'hero.trust.private': 'Privacy-first',
    'hero.trust.nosub': 'Kostenlos nutzbar',
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
    'howitworks.label': 'Drei Schritte',
    'howitworks.title': 'Von der Idee zum Text — drei Schritte, mehr nicht.',
    'howitworks.desc': 'Kein Browser-Tab. Kein Copy-Paste-Ritual. Einfach sprechen und weitermachen.',
    'howitworks.step1.label': 'Schritt 1',
    'howitworks.step1.title': 'Tastenkürzel drücken',
    'howitworks.step1.desc': 'Starte aus Mail, Chat, Dokumenten, Code oder überall dort, wo dein Cursor schon ist.',
    'howitworks.step2.label': 'Schritt 2',
    'howitworks.step2.title': 'Natürlich sprechen',
    'howitworks.step2.desc': 'WhisPaste wandelt deine Sprache in Text um — auf deinem Rechner oder über einen Cloud-Anbieter deiner Wahl.',
    'howitworks.step3.label': 'Schritt 3',
    'howitworks.step3.title': 'Einfügen, anpassen oder verfeinern',
    'howitworks.step3.desc': 'Der Text erscheint am Cursor — direkt einsatzbereit, zum Bearbeiten oder Erweitern mit Sprach-Shortcuts.',
    'screenshots.label': 'Screenshots',
    'screenshots.title': 'Wo deine Stimme zu Text wird',
    'screenshots.desc': 'Sprechen, sortieren, verfeinern. So sieht das in der Praxis aus.',
    'screenshots.seeAll': 'Alle Ansichten entdecken →',
    'screenshots.workspace': 'Alle Transkripte auf einen Blick',
    'screenshots.detail': 'Jeden Eintrag bearbeiten und verfeinern',
    'screenshots.shortcuts': 'Sprach-Snippets, die Tippen ersparen',
    'screenshots.hotkey': 'Mit einer Taste die Spracheingabe starten',
    'screenshots.insights': 'Verfolge, wie du deine Stimme nutzt',
    'gallery.title': 'Jeder Screen, jedes Detail',
    'gallery.desc': 'Fünf Ansichten für den ganzen Workflow — vom Transkript zum fertigen Text. Wechsle das Theme und finde deinen Stil.',
    'gallery.themeDark': 'Dunkel',
    'gallery.themeLight': 'Hell',
    'gallery.platformWindows': 'Windows',
    'gallery.platformMac': 'macOS',
    'gallery.workspace': 'Alle Transkripte auf einen Blick',
    'gallery.detail': 'Jeden Eintrag bearbeiten und verfeinern',
    'gallery.shortcuts': 'Sprach-Snippets, die Tippen ersparen',
    'gallery.settings': 'Anpassbar an deinen Workflow',
    'gallery.analytics': 'Verfolge, wie du deine Stimme nutzt',
    'gallery.cta': 'WhisPaste holen — kostenlos',
    'privacy.label': 'Vertrauen',
    'privacy.title': 'Deine Stimme bleibt bei dir',
    'privacy.desc': 'Lokal, wenn du willst. Cloud nur, wenn du sie auswählst. Kein Tracking. Keine Analytics.',
    'privacy.offline.title': 'Funktioniert offline',
    'privacy.offline.desc': 'Die Transkription passiert direkt auf deinem Rechner. Audio verlässt nie dein Gerät.',
    'privacy.telemetry.title': 'Keine Analytics',
    'privacy.telemetry.desc': 'Kein Tracking, keine Analytics. Optionale Crash-Reports helfen uns, Fehler schneller zu finden — du kannst sie jederzeit abschalten.',
    'privacy.directapi.title': 'Cloud ist optional',
    'privacy.directapi.desc': 'Wenn du Cloud-Transkription nutzt, geht dein Audio direkt an den ausgewählten Anbieter. Wir leiten es nicht weiter.',
    'pricing.label': 'Preis',
    'pricing.price': 'Open Source',
    'pricing.title': 'Kostenlos & Open Source.',
    'pricing.desc': 'Die gesamte App ist kostenlos — Offline-Transkription, Sprach-Snippets, GPU-Beschleunigung und mehr. Hol sie dir aus dem Store und unterstütze das Projekt, oder lade sie kostenlos von GitHub.',
    'pricing.forever': 'MIT-lizenziert — Open Source, für immer',
    'pricing.feature.offline': 'Offline-Transkription',
    'pricing.feature.snippets': 'Sprach-Snippets',
    'pricing.feature.gpu': 'GPU-Beschleunigung',
    'pricing.feature.history': 'Verlauf & Suche',
    'pricing.feature.updates': 'Auto-Updates',
    'pricing.feature.opensource': 'Open Source (MIT)',
    'languages.label': 'Sprachen',
    'languages.title': 'Spricht deine Sprache',
    'languages.desc': 'WhisPaste unterstützt 99 Sprachen — egal ob du auf Deutsch sprichst, zwischendurch ins Englische wechselst oder auf Japanisch arbeitest.',
    'languages.more': '+80 weitere',
    'faq.label': 'FAQ',
    'faq.title': 'Gute Fragen, ehrliche Antworten',
    'faq.free.q': 'Ist WhisPaste wirklich kostenlos?',
    'faq.free.a': 'Ja. WhisPaste ist Open Source unter der MIT-Lizenz. Die App mit Offline-Transkription, Sprach-Snippets, Verlauf und mehr ist kostenlos. Du kannst sie von GitHub herunterladen. Die Microsoft-Store-Version bringt automatische Updates und unterstützt das Projekt finanziell.',
    'faq.offline.q': 'Funktioniert es wirklich offline?',
    'faq.offline.a': 'Vollständig. WhisPaste bringt eine eingebaute Spracherkennung mit, die komplett auf deinem Rechner läuft. Kein Internet nötig. Wenn du willst, kannst du auch einen Cloud-Anbieter einbinden — aber das ist deine Entscheidung, keine Voraussetzung.',
    'faq.accuracy.q': 'Wie genau ist die Transkription?',
    'faq.accuracy.a': 'Das hängt vom gewählten Modell ab. Das kleine Modell reicht für den Alltag gut aus. Größere Modelle sind präziser, brauchen aber mehr RAM und Rechenzeit. Du kannst jederzeit wechseln und das richtige Gleichgewicht finden.',
    'faq.sysreq.q': 'Was sind die Systemanforderungen?',
    'faq.sysreq.a': 'Minimum: Windows\u00a010 (64-Bit) oder macOS\u00a010.15 Catalina\u202f+\u00a0\u00b7 8\u202fGB RAM (Pflicht, wird beim Start gepr\u00fcft)\u00a0\u00b7 1\u2013\u20132\u202fGB freier Speicher. Kein GPU n\u00f6tig\u00a0\u2014 WhisPaste greift immer auf CPU zur\u00fcck. Empfohlen: 16\u202fGB RAM\u00a0\u00b7 dedizierte GPU mit 2\u2013\u20134\u202fGB VRAM (NVIDIA CUDA, AMD oder Intel Vulkan) f\u00fcr 5\u202f\u00d7 schnellere Transkription. GPU-VRAM nach Modell: kompakt ~300\u202fMB \u00b7 ausgewogen ~900\u202fMB \u00b7 Premium (Turbo) ~2,6\u202fGB \u00b7 Ultra ~3,6\u202fGB. Apple Silicon: Unified Memory gilt f\u00fcr CPU und GPU\u00a0\u2014 8\u202fGB reicht f\u00fcr das ausgewogene Modell.',
    'faq.languages.q': 'Welche Sprachen werden unterstützt?',
    'faq.languages.a': 'WhisPaste unterstützt 99 Sprachen — von Deutsch und Englisch über Japanisch und Arabisch bis Hindi. Du kannst die Sprache in den Einstellungen wählen oder WhisPaste automatisch erkennen lassen.',
    'faq.privacy.q': 'Sind meine Sprachdaten sicher?',
    'faq.privacy.a': 'Im lokalen Modus verlässt dein Audio nie deinen Rechner. Wenn du den Cloud-Weg nutzt, gehen die Aufnahmen direkt von deinem Gerät an den ausgewählten Anbieter — WhisPaste leitet nichts weiter und speichert nichts davon. Optionale Crash-Reports sind transparent und lassen sich jederzeit abschalten.',
    'faq.windows.q': 'Gibt es WhisPaste auch für Mac oder Linux?',
    'faq.windows.a': 'WhisPaste ist für Windows und macOS verfügbar. Eine Linux-Version ist geplant.',
    'faq.smartscreen.q': 'Warum zeigt Windows beim Download eine Warnung?',
    'faq.smartscreen.a': 'Microsoft SmartScreen warnt bei jeder neuen Software, die noch keine Download-Reputation aufgebaut hat — das bedeutet nicht, dass die App unsicher ist. WhisPaste ist Open Source, und jedes Release wird transparent über GitHub Actions gebaut. Klicke auf „Weitere Informationen" → „Trotzdem ausführen".',
    'faq.gatekeeper.q': 'Warum warnt macOS, dass WhisPaste nicht überprüft werden kann?',
    'faq.gatekeeper.a': 'macOS Gatekeeper blockiert unbekannte Apps, die außerhalb des App Stores heruntergeladen werden. WhisPaste ist noch nicht von Apple notarisiert\u00a0\u2014 mache einen Rechtsklick auf die App \u2192 \u201eÖffnen\u201c \u2192 im Dialog bestätigen. Alternativ kann WhisPaste aus dem Mac App Store installiert werden, das alle Apple-Sicherheitsprüfungen automatisch besteht.',
    'testimonials.label': 'Erfahrungsberichte',
    'testimonials.title': 'Was unsere Nutzer sagen',
    'testimonials.subtitle': 'Echtes Feedback von echten Menschen — keine Namen, kein Tracking, nur ehrliche Meinungen.',
    'testimonials.empty': 'Noch keine Erfahrungsberichte vorhanden — sei der Erste, der seine Erfahrung teilt!',
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
    'download.github.btnHint': 'Herunterladen für',
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
    'download.trust.notelemetry': 'Kein Tracking oder Analytics',
    'download.macos.title': 'macOS (Apple Silicon)',
    'download.macos.desc': 'Lade das neueste macOS-Release direkt von GitHub herunter. Unterstützt Apple M-Chips nativ.',
    'download.macos.button': 'Für macOS herunterladen',
    'download.macos.hint': 'Nach dem Download das DMG öffnen und WhisPaste in den Programme-Ordner ziehen.',
    'download.macos.gatekeeper.title': 'Hinweis: Gatekeeper-Warnung',
    'download.macos.gatekeeper.desc': 'macOS zeigt möglicherweise „WhisPaste kann nicht geöffnet werden, da es von einem nicht identifizierten Entwickler stammt". Rechtsklick auf die App → „Öffnen" → im Dialog „Öffnen" klicken.',
    'sponsor.title': 'WhisPaste unterstützen',
    'sponsor.desc': 'WhisPaste ist kostenlos und Open Source — keine Werbung, keine Datensammlung. Deine Unterstützung hilft, dass das so bleibt.',
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
    'sponsor.free.title': 'Kostenlos unterstützen',
    'sponsor.free.desc': 'Nicht jede Unterstützung muss finanziell sein. Diese kleinen Aktionen machen einen echten Unterschied.',
    'sponsor.free.star': 'Stern auf GitHub geben',
    'sponsor.free.star.desc': 'Zeigt anderen, dass sich das Projekt lohnt. Dauert zwei Sekunden.',
    'sponsor.free.share': 'Weitersagen',
    'sponsor.free.share.desc': 'Die beste Empfehlung ist eine persönliche.',
    'support.title': 'Hilf mit, WhisPaste besser zu machen',
    'support.desc': 'Wenn dir WhisPaste Zeit spart, kannst du helfen, es am Laufen zu halten — jeder Beitrag zählt.',
    'support.sponsor': 'Auf GitHub sponsern',
    'support.coffee': 'Kaffee ausgeben',
    'support.star': 'Stern auf GitHub geben — kostenlos und genauso hilfreich',
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
    'changelog.1.1.3.highlight.0': 'Dashboard, Nachbearbeitung und Sprach-Snippets mit aufgeräumterem Layout überarbeitet',
    'changelog.1.1.3.highlight.1': 'Nachbearbeitung und Sprach-Snippets haben jetzt getrennte KI-Anbieter-Einstellungen',
    'changelog.1.1.3.highlight.2': 'Stille-Erkennung vereinfacht — ein smarter Schalter statt zwei verwirrender Optionen',
    'changelog.1.1.3.highlight.3': 'Sanfte Seitenübergänge und Micro-Animationen für ein hochwertigeres Gefühl',
    'changelog.1.1.3.highlight.4': 'Automatisch generierte Tags nutzen jetzt Großschreibung und filtern System-Labels',
    'changelog.1.1.3.improvement.0': 'Einstellungen in klarere Bereiche mit verständlicheren Beschreibungen aufgeteilt',
    'changelog.1.1.3.improvement.1': 'Fachbegriffe durch alltagstaugliche Sprache in der gesamten App ersetzt',
    'changelog.1.1.3.improvement.2': 'Race-Condition beim schnellen Seitenwechsel behoben',
    'changelog.1.1.2.highlight.0': 'Nachbearbeitung funktioniert jetzt zuverlässig mit allen lokalen KI-Modellen, auch kleineren',
    'changelog.1.1.2.highlight.1': 'Das App-Icon wird sauber in der Windows-Taskleiste angezeigt — keine blauen Ecken mehr',
    'changelog.1.1.2.highlight.2': 'Transkripte werden jetzt korrekt in das neue Outlook unter Windows 11 eingefügt',
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
    'changelog.1.1.0.highlight.0': 'Nachbearbeitung: KI-gestützte Textverfeinerung verwandelt rohe Transkripte in polierten, kontextbewussten Text',
    'changelog.1.1.0.highlight.1': 'Sprach-Snippets: häufig genutzte Phrasen speichern und mit einem Befehl abrufen',
    'changelog.1.1.0.highlight.2': 'Vollständiger Verlauf mit Suche: jedes vergangene Transkript sofort finden',
    'changelog.1.1.0.improvement.0': 'Neues Design mit Premium-Look in der gesamten App',
    'changelog.1.1.0.improvement.1': 'Im Microsoft Store verfügbar für einfache Installation und Auto-Updates',
    'changelog.1.2.1.highlight.0': 'macOS-App wird mit jedem Release als nativer ARM64-DMG ausgeliefert',
    'changelog.1.2.1.highlight.1': 'CI-Pipeline gehärtet: Secret-Scanning, eingeschränkte Berechtigungen, isolierte Screenshot-Tests',
    'changelog.1.2.1.highlight.2': 'Direkte Download-Links für Windows (.exe) und macOS (.dmg) auf der Download-Seite',
    'changelog.1.2.1.improvement.0': 'Release-Build für macOS behoben — Icon-Font-Tree-Shaking deaktiviert',
    'changelog.1.2.1.improvement.1': 'macOS-Gatekeeper-Anleitung mit vollständiger Schritt-für-Schritt-Anleitung erweitert',
    'changelog.1.2.0.highlight.0': 'Kompletter Neuschrieb als native Flutter-App — wirklich plattformübergreifend (Windows und macOS)',
    'changelog.1.2.0.highlight.1': 'Gesamter Transkript-Verlauf lokal in SQLite gespeichert — keine geteilten Konfigdateien, kein Datenverlust',
    'changelog.1.2.0.highlight.2': 'Neue schlanke Aufnahme-Pille mit Live-Wellenform und Fortschrittsanzeige',
    'changelog.1.2.0.highlight.3': 'Schwebende Schaltfläche immer im Vordergrund für sofortige Spracheingabe aus jeder App',
    'changelog.1.2.0.highlight.4': 'Premium-UI mit warmen Verläufen, Milchglas-Effekten und Micro-Animationen',
    'changelog.1.2.0.highlight.5': '469+ automatisierte Tests mit über 90 Prozent Funktionsabdeckung',
    'changelog.1.2.0.improvement.0': 'Gesamter Go-Backend-Code entfernt — keine externen Abhängigkeiten mehr',
    'changelog.1.2.0.improvement.1': 'Riverpod State Management für reaktive, testbare Architektur',
    'changelog.1.2.0.improvement.2': 'CI/CD für reine Flutter-Builds mit vollständiger macOS-Unterstützung aktualisiert',
    'hero.download.windows': 'Für Windows herunterladen',
    'hero.download.macos': 'Für macOS herunterladen',
    'hero.download.macos.hint': 'Herunterladen für',
    'hero.download.macos.platform': 'macOS',
    'download.macos.gatekeeper.step1.title': 'macOS blockiert die App beim ersten Start',
    'download.macos.gatekeeper.step1.desc': 'Nach dem Öffnen des DMG und dem Verschieben von WhisPaste in die Programme kann macOS die App möglicherweise nicht öffnen — mit der Meldung „Apple kann die App nicht auf Schadsoftware überprüfen."',
    'download.macos.gatekeeper.step2.title': 'Datenschutz & Sicherheit öffnen',
    'download.macos.gatekeeper.step2.desc': 'Gehe zu Apple-Menü → Systemeinstellungen → Datenschutz & Sicherheit. Scrolle nach unten zum Bereich „Sicherheit".',
    'download.macos.gatekeeper.step3.title': '„Dennoch öffnen" klicken',
    'download.macos.gatekeeper.step3.desc': 'Du siehst eine Meldung zu WhisPaste. Klicke auf „Dennoch öffnen" — diese Schaltfläche ist etwa eine Stunde nach dem ersten Startversuch verfügbar.',
    'download.macos.gatekeeper.step4.title': 'Bestätigen und Passwort eingeben',
    'download.macos.gatekeeper.step4.desc': 'Klicke im Bestätigungsdialog erneut auf „Dennoch öffnen" und gib dann dein Mac-Anmeldepasswort ein.',
    'download.macos.gatekeeper.why.title': 'Warum passiert das?',
    'download.macos.gatekeeper.why.desc': 'WhisPaste ist Open Source und wird transparent über GitHub Actions gebaut, aber noch nicht von Apple notarisiert. Diese Warnung erscheint bei jeder App, die nicht aus dem Mac App Store stammt. Das bedeutet nicht, dass die App unsicher ist.',
    'carousel.press_hotkey': 'Drücke dein Tastenkürzel',
    'carousel.speak_now': 'Sprich jetzt',
    'carousel.editor_title': 'Texteditor',
    'carousel.auto_pasted': 'Automatisch eingefügt!',
    'carousel.tablistAria': 'Carousel-Folien',
    'carousel.slide1Aria': 'Folie 1: Tastenkürzel drücken',
    'carousel.slide2Aria': 'Folie 2: Jetzt sprechen',
    'carousel.slide3Aria': 'Folie 3: Automatisch eingefügt',
    'carousel.overlayLocal': 'Lokal',
    'store.btn.getfrom': 'Hol es im',
    'store.btn.msstore': 'Microsoft Store',
    'store.btn.single': 'Hol es im Microsoft Store',
    'downloadModal.heading': 'Dein Download startet gleich!',
    'downloadModal.body': 'WhisPaste ist kostenlos — so kannst du helfen:',
    'downloadModal.starGitHub': '⭐ Auf GitHub einen Stern geben',
    'downloadModal.rateMsStore': '★ Im Microsoft Store bewerten',
    'downloadModal.rateAppStore': '★ Im Mac App Store bewerten',
    'downloadModal.support': 'Oder über GitHub sponsern / Kaffee spendieren',
    'downloadModal.maybeLater': 'Vielleicht später',
    'support.reviewHeading': 'Hilf anderen, WhisPaste zu entdecken',
    'support.rateMsStore': 'Im Microsoft Store bewerten',
    'support.rateAppStore': 'Im Mac App Store bewerten',
    'hero.reviewNudge': 'Gefällt sie dir? Ein ★ auf GitHub oder eine Store-Bewertung macht einen echten Unterschied.',
    // Breadcrumb-Labels — siehe Kommentar im EN-Block. Spiegelt die deutschen
    // Sub-Page-Titel; bewusst kurz gehalten, weil Breadcrumbs in Rich Results
    // als knappe Pfad-Hierarchie angezeigt werden.
    'breadcrumb.home': 'Start',
    'breadcrumb.download': 'Download',
    'breadcrumb.screenshots': 'Screenshots',
    'breadcrumb.privacy': 'Datenschutz',
    'breadcrumb.impressum': 'Impressum',
    'breadcrumb.sponsor': 'Unterstützen',
    'breadcrumb.changelog': 'Änderungsprotokoll',
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

/**
 * Reads the URL-derived locale from `<html lang>`. Slice 03 wires the Astro
 * i18n router so the server emits the locale-correct `lang` attribute per
 * URL (`/` → `de`, `/en/` → `en`). When that attribute is present it wins —
 * the page must not flicker into a different locale just because the user
 * has a localStorage preference from an earlier visit.
 */
function langFromHtml(): string | null {
  if (typeof document === 'undefined') return null;
  const attr = document.documentElement.getAttribute('lang');
  if (attr === 'de' || attr === 'en') return attr;
  return null;
}

function loadInitialLang(): string {
  if (typeof window === 'undefined' || typeof localStorage === 'undefined') {
    return 'de';
  }
  // Allow deep-linking with ?lang=en or ?lang=de (e.g. from the desktop app)
  const params = new URLSearchParams(window.location.search);
  const paramLang = params.get('lang');
  if (paramLang && ['en', 'de'].includes(paramLang)) {
    localStorage.setItem('whispaste-lang', paramLang);
    return paramLang;
  }
  // URL-derived locale takes precedence over stored preference so the
  // initial `<html lang>` matches the page we actually rendered.
  const fromHtml = langFromHtml();
  if (fromHtml) {
    localStorage.setItem('whispaste-lang', fromHtml);
    return fromHtml;
  }
  return localStorage.getItem('whispaste-lang') || detectBrowserLang();
}

export let currentLang: string = loadInitialLang();

/**
 * Maps the current URL path to the equivalent path in the other locale.
 * Used by `toggleLang()` so the language switch becomes a real cross-locale
 * navigation rather than a client-side text swap. Pages with locale-specific
 * slugs (Datenschutz ↔ Privacy) override this in their own page script.
 */
function otherLocalePath(targetLang: 'de' | 'en'): string {
  if (typeof window === 'undefined') return '/';
  const path = window.location.pathname;
  if (targetLang === 'en') {
    if (path.startsWith('/en/') || path === '/en') return path;
    if (path === '/') return '/en/';
    return `/en${path}`;
  }
  // targetLang === 'de'
  if (path === '/en/' || path === '/en') return '/';
  if (path.startsWith('/en/')) return path.replace(/^\/en/, '');
  return path;
}

export function toggleLang() {
  const next = currentLang === 'en' ? 'de' : 'en';
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem('whispaste-lang', next);
  }
  // Cross-locale navigation: jump to the matching URL in the target locale
  // so the server-rendered HTML is locale-correct on the next paint.
  if (typeof window !== 'undefined' && typeof window.location !== 'undefined') {
    const targetPath = otherLocalePath(next);
    if (targetPath !== window.location.pathname) {
      window.location.assign(targetPath);
      return;
    }
  }
  // Fallback: same path, just retoggle in place (only reached in non-browser
  // contexts or when the page has no DE/EN counterpart).
  currentLang = next;
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
if (typeof window !== 'undefined') {
  (window as any).toggleLang = toggleLang;
  (window as any).currentLang = currentLang;

  // Keep window.currentLang in sync
  const origToggle = toggleLang;
  (window as any).toggleLang = function() {
    origToggle();
    (window as any).currentLang = currentLang;
  };
}

/**
 * Server-side translation helper. Resolves a key in the requested locale and
 * returns the translation, falling back to English when a key is missing in
 * the requested locale and to the raw key when no translation exists at all.
 *
 * Consumed by `.astro` components to render locale-correct text during SSR so
 * crawlers see the right language without depending on the client-side
 * `applyLang()` toggle (which still works as progressive enhancement once
 * JavaScript loads).
 */
export function t(lang: string | undefined, key: string): string {
  const locale: Locale =
    lang === 'en' || lang === 'de' ? lang : DEFAULT_LOCALE;
  return i18n[locale]?.[key] ?? i18n.en?.[key] ?? key;
}

/**
 * Returns the canonical absolute URL for a given page-relative path under the
 * requested locale. The German default locale is served at the root, English
 * is prefixed with `/en/`. Always returns a trailing slash for directory-style
 * URLs (consistent with Astro's default behaviour for static builds).
 *
 * @param locale - target locale.
 * @param baseSlug - path segment relative to the site root (no leading or
 *   trailing slash; use `''` for the home page). Examples: `''`, `download`,
 *   `datenschutz`.
 */
export function localePath(locale: Locale, baseSlug: string): string {
  const slug = baseSlug.replace(/^\/+|\/+$/g, '');
  if (locale === 'de') {
    return slug.length === 0 ? '/' : `/${slug}/`;
  }
  return slug.length === 0 ? '/en/' : `/en/${slug}/`;
}
