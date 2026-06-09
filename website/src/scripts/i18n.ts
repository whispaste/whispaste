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
    'gallery.desc': 'Five views that show the full workflow — from voice input to polished text.',
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
    'download.diagnose.title': 'Speech service not starting?',
    'download.diagnose.desc': 'Create a diagnostics report with our tool and send it to us — it helps us pinpoint the problem fast.',
    'download.diagnose.step1.title': 'Download the diagnostics tool',
    'download.diagnose.step1.desc': 'Pick the build for your system below.',
    'download.diagnose.step2.title': 'Run it',
    'download.diagnose.step2.desc': 'On Windows double-click the .exe; on macOS open the .dmg and double-click WhisPaste-Diagnose.app. It writes a report to your Desktop.',
    'download.diagnose.step3.title': 'Send us the report',
    'download.diagnose.step3.desc': 'Attach the generated file to an email so we can read the speech-service environment and the model-load test result.',
    'download.diagnose.btnHint': 'Diagnostics tool for',
    'download.diagnose.mailHint': 'Send the report to',
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
    'footer.download': 'Download',
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
    // Long-Tail use-case pages (Block E). The "useCases" breadcrumb is the
    // section index; per-page breadcrumbs add a third level (e.g. "Developers").
    'breadcrumb.useCases': 'Use Cases',
    // Programmer use-case page — i18n namespace mirrors PRD §E Block-E content.
    // Hero answers the zielgruppe.md litmus test: helping a developer in the
    // middle of a code review reply without leaving the browser or grabbing
    // the mouse.
    'useCase.programmer.breadcrumb': 'Developers',
    'useCase.programmer.seoTitle': 'WhisPaste for developers — voice input for code reviews, commits, and issues',
    'useCase.programmer.seoDescription': 'Reply to code reviews, write commit messages, and answer issues by speaking — without leaving the browser or grabbing the mouse. Local-first voice-input tool for the dev workflow.',
    'useCase.programmer.heroHeading': 'Voice input for developers — stay in the browser, keep your hands on the keyboard.',
    'useCase.programmer.heroLead': 'When you are in the middle of a code review and need to write a five-sentence reply, WhisPaste lets you speak the answer right into the GitHub textarea — without switching apps, without reaching for the mouse, without breaking your flow.',
    'useCase.programmer.section.codeReview.heading': 'Code reviews without context switches',
    'useCase.programmer.section.codeReview.body': 'A pull-request review needs nuance: a one-line "looks good" misses the point, a wall of text loses the reviewer. With WhisPaste you press your hotkey, speak the explanation while you read the diff, and the transcript lands directly in the GitHub reply field — already correctly capitalised, with code identifiers like `fooBar` preserved when you spell them out.',
    'useCase.programmer.section.gitCommits.heading': 'Commit messages and PR descriptions',
    'useCase.programmer.section.gitCommits.body': 'Conventional commits and PR bodies often deserve more than three words, but the friction of writing them slows you down. Open the editor, speak the rationale, and the transcript shows up at your cursor — ready to edit, expand with a voice snippet, or paste into your terminal.',
    'useCase.programmer.section.issueTracker.heading': 'Issue tracker, Slack, and standups',
    'useCase.programmer.section.issueTracker.body': 'Repro steps in a bug ticket, async standup notes in Slack, a quick comment on a Linear issue — all of these are short but high-friction. WhisPaste runs in the background and works everywhere your cursor goes: GitHub, GitLab, Jira, Linear, Discord, Slack, your editor. Audio stays on your machine in local mode.',
    'useCase.programmer.howTo.name': 'How to use WhisPaste in your dev workflow',
    'useCase.programmer.howTo.step1.name': 'Place your cursor in the reply field',
    'useCase.programmer.howTo.step1.text': 'Click into the GitHub review comment, the commit-message editor, or the Slack input — wherever you would normally type.',
    'useCase.programmer.howTo.step2.name': 'Press your hotkey and speak',
    'useCase.programmer.howTo.step2.text': 'Hold your configured hotkey, say your answer out loud, and release. The transcript is created locally on your machine by default.',
    'useCase.programmer.howTo.step3.name': 'The transcript appears at the cursor',
    'useCase.programmer.howTo.step3.text': 'Your text lands where you left the cursor. Edit, expand with a voice snippet, or send — no copy-paste step between voice and text.',
    'useCase.programmer.cta.label': 'Get WhisPaste — free and open source',
    'useCase.rsi.breadcrumb': 'RSI',
    'useCase.rsi.seoTitle': 'WhisPaste for RSI — voice input when typing hurts',
    'useCase.rsi.seoDescription': 'For knowledge workers with RSI: produce text by speaking instead of typing, in any app, without leaving your workflow. Local-first voice-input tool that adapts to bad-typing days.',
    'useCase.rsi.heroHeading': 'Voice input for RSI — keep working on the days your hands cannot.',
    'useCase.rsi.heroLead': 'When your wrists, fingers, or forearms are flaring up and pressing keys is no longer an option, WhisPaste lets you produce text by speaking into the same apps you already use — without switching tools, without leaving your editor, without giving up on the day.',
    'useCase.rsi.section.flow.heading': 'Stay in your workflow on bad-typing days',
    'useCase.rsi.section.flow.body': 'A flare-up does not give you warning. WhisPaste sits in the background and replaces typing wherever your cursor is: email, chat, ticketing tool, document editor. You press the hotkey once, speak in your own pace, and the transcript appears at the cursor — so a bad-hands afternoon does not turn into a lost workday.',
    'useCase.rsi.section.ergonomics.heading': 'Ergonomics without a context switch',
    'useCase.rsi.section.ergonomics.body': 'Most accessibility tools force you to leave the app you are in: a separate window, a separate clipboard, a separate paste step. WhisPaste avoids that overhead — the transcript lands where you were already working, so you keep one app open instead of three, and your shoulders, neck, and eyes stop chasing extra windows around.',
    'useCase.rsi.section.dailyVariation.heading': 'Built for days that are not the same',
    'useCase.rsi.section.dailyVariation.body': 'RSI does not progress linearly. Some days you type fine for an hour; other days the first email already hurts. WhisPaste does not demand a setup ritual: the hotkey is always there, voice input is always one press away, and you can blend typing and speaking sentence by sentence as the day allows.',
    'useCase.rsi.faq.karpaltunnel.q': 'Does WhisPaste help with carpal tunnel or tendon pain?',
    'useCase.rsi.faq.karpaltunnel.a': 'WhisPaste is not a medical treatment, but it removes the cause of a lot of typing for knowledge work. Many people with carpal tunnel, tendinitis, or general RSI use voice input as the primary way to write — WhisPaste makes that workable in apps that have no native voice support, because the transcript is delivered at the cursor like any other keystroke.',
    'useCase.rsi.faq.pauses.q': 'Does it work if I need to pause and breathe mid-sentence?',
    'useCase.rsi.faq.pauses.a': 'Yes. WhisPaste records as long as you hold the hotkey or until you stop the session. Pauses inside the recording do not break the transcript; the model handles natural speech with breaks, hesitations, and restarts. You decide when the segment ends, not a timer.',
    'useCase.rsi.faq.dayVariation.q': 'My voice changes day to day — can WhisPaste handle that?',
    'useCase.rsi.faq.dayVariation.a': 'The Whisper model that powers offline transcription is trained on a wide range of voices and conditions, including tiredness, illness, and accent variation. If a particular day produces noisier transcripts, you can also switch to a cloud provider for that session — no reconfiguration, just a setting toggle.',
    'useCase.rsi.cta.label': 'Get WhisPaste — free and open source',
    'useCase.support.breadcrumb': 'Support staff',
    'useCase.support.seoTitle': 'WhisPaste for helpdesk and support staff — voice input for ticket replies',
    'useCase.support.seoDescription': 'For helpdesk and customer-support staff: answer tickets faster by speaking the reply directly into the ticketing UI — no app switch, no copy-paste. Local-first voice-input tool.',
    'useCase.support.heroHeading': 'Voice input for support staff — answer tickets without leaving the browser.',
    'useCase.support.heroLead': 'When you are working through a queue of helpdesk tickets and need to reply with more than a canned macro, WhisPaste lets you speak the answer straight into the ticket textarea — no app switch, no copy-paste from a side window, no break in your queue rhythm.',
    'useCase.support.section.workflow.heading': 'A ticket reply that does not interrupt the queue',
    'useCase.support.section.workflow.body': 'Helpdesk work is repetitive but never identical: every reply needs a personal sentence, a specific instruction, or a fresh empathy line on top of the macro. WhisPaste fits between the macro and the send button — drop the macro, place the cursor where the personal sentence goes, press the hotkey, speak the addition, and the transcript lands inline.',
    'useCase.support.section.tools.heading': 'Works in Zendesk, Freshdesk, Intercom, and your own tools',
    'useCase.support.section.tools.body': 'WhisPaste is not a Zendesk plugin, so it does not depend on a specific ticketing vendor. It works wherever the cursor goes: web-based ticketing UIs, internal tools, Slack handoffs, escalation emails. If your team uses a mix of ticketing systems or an internal helpdesk app, the voice input behaves the same in all of them.',
    'useCase.support.section.savings.heading': 'Time saved per ticket, not per shift',
    'useCase.support.section.savings.body': 'The friction in a support reply is not the long paragraphs — it is the constant micro-typing for greetings, sign-offs, and clarifying sentences. Replacing those with two-second voice segments shaves seconds off every ticket. Over a shift of 60 to 100 tickets, those seconds add up to a meaningful reduction in keystrokes and wrist strain.',
    'useCase.support.howTo.step1.name': 'Open the ticket and place the cursor in the reply field',
    'useCase.support.howTo.step1.text': 'Pick the next ticket in your queue, drop in your macro if you use one, and click into the textarea where the personal sentence should appear.',
    'useCase.support.howTo.step2.name': 'Press the hotkey and speak the reply',
    'useCase.support.howTo.step2.text': 'Hold your configured hotkey and speak the answer — full reply or just the personalised paragraph. Release the hotkey when you are done.',
    'useCase.support.howTo.step3.name': 'Review the transcript and send',
    'useCase.support.howTo.step3.text': 'The transcript appears at the cursor. Skim it, adjust a word if needed, and send — no extra paste step, no jump back to a separate voice app.',
    'useCase.support.cta.label': 'Get WhisPaste — free and open source',
    // Explainer pages (Block E, Issue 12). Three thematic long-tail pages
    // capture the deeper technical queries around Whisper-as-a-desktop-tool,
    // offline speech-to-text, and privacy-conscious voice input. Vocabulary
    // strictly Glossar-konform — no `dictation` / `voice assistant` /
    // `voice command` / `voice translator`; the explanatory copy frames
    // WhisPaste as a `voice-input tool` with `transcripts` as the artefact.
    'explainer.whisperDesktop.breadcrumb': 'Whisper desktop',
    'explainer.whisperDesktop.seoTitle': 'Whisper as a desktop tool — local speech-to-text with WhisPaste',
    'explainer.whisperDesktop.seoDescription': 'Use OpenAI Whisper as a desktop voice-input tool on Windows and macOS — without Python, without a cloud account. WhisPaste bundles whisper.cpp, manages models, and delivers transcripts straight to your cursor.',
    'explainer.whisperDesktop.heroHeading': 'Whisper as a desktop tool — without Python, without a cloud account.',
    'explainer.whisperDesktop.heroLead': 'When you want to use OpenAI Whisper on your own machine but do not want to glue together a Python environment, manage CUDA wheels, or pay for a cloud account, WhisPaste ships whisper.cpp inside a native desktop app — one installer, one hotkey, and the transcript lands at your cursor.',
    'explainer.whisperDesktop.section.setup.heading': 'Setup: one installer, no Python environment',
    'explainer.whisperDesktop.section.setup.body': 'WhisPaste embeds whisper.cpp — the C++ port of OpenAI Whisper — directly inside the desktop binary. After install, you pick a model size from a drop-down, the app downloads it once, and from then on transcription runs fully offline on your machine. No virtualenv, no pip, no CUDA toolkit; the GPU acceleration is bundled via Vulkan or CUDA runtimes where available.',
    'explainer.whisperDesktop.section.performance.heading': 'Performance: CPU works, GPU is five times faster',
    'explainer.whisperDesktop.section.performance.body': 'whisper.cpp runs on plain CPU on every supported machine (Windows 10+, macOS 10.15+), so an 8 GB laptop without a discrete GPU is enough for the compact model. On a machine with a dedicated GPU — NVIDIA CUDA, AMD or Intel Vulkan — the same transcript is produced roughly five times faster. Apple Silicon uses unified memory, so 8 GB already covers the balanced model.',
    'explainer.whisperDesktop.section.localVsCloud.heading': 'Local vs cloud: same Whisper, different trade-offs',
    'explainer.whisperDesktop.section.localVsCloud.body': 'Local Whisper keeps audio on your machine, costs nothing per minute, and works without internet — at the price of a one-time model download and slightly more RAM. Cloud providers like OpenAI, Groq, or Deepgram trade those resources for raw speed and the largest models. WhisPaste lets you pick per session: stay local by default, switch to a cloud provider when you need maximum speed on a long recording.',
    'explainer.whisperDesktop.howTo.name': 'How to use Whisper as a desktop tool with WhisPaste',
    'explainer.whisperDesktop.howTo.step1.name': 'Install WhisPaste and pick a Whisper model',
    'explainer.whisperDesktop.howTo.step1.text': 'Download WhisPaste from the Microsoft Store, the Mac App Store, or GitHub. On first launch the setup assistant suggests a model size based on your hardware — compact for an 8 GB laptop, balanced for 16 GB with a GPU, premium for higher VRAM.',
    'explainer.whisperDesktop.howTo.step2.name': 'Let the model download once',
    'explainer.whisperDesktop.howTo.step2.text': 'WhisPaste fetches the chosen whisper.cpp model file in the background and verifies it. The download resumes after interrupted connections, so a flaky network does not force you to start over. After that, transcription runs fully offline.',
    'explainer.whisperDesktop.howTo.step3.name': 'Press your hotkey and speak',
    'explainer.whisperDesktop.howTo.step3.text': 'Place the cursor wherever you want the text, hold your configured hotkey, and speak. whisper.cpp transcribes the audio on your machine and the transcript appears at the cursor — no upload, no browser tab, no copy-paste step.',
    'explainer.whisperDesktop.cta.label': 'Get WhisPaste — free and open source',
    'explainer.offlineStt.breadcrumb': 'Offline speech-to-text',
    'explainer.offlineStt.seoTitle': 'Offline speech-to-text on Windows and macOS — WhisPaste',
    'explainer.offlineStt.seoDescription': 'Offline speech-to-text for the desktop: how local Whisper mode works, what it can and cannot do, and what RAM and CPU profile you need. Free and open source.',
    'explainer.offlineStt.heroHeading': 'Offline speech-to-text — when the audio must never leave your machine.',
    'explainer.offlineStt.heroLead': 'When you want speech-to-text on your laptop but the recording cannot leave the device — because of a client contract, a regulated industry, or simple personal preference — WhisPaste runs the entire transcription pipeline locally with whisper.cpp, so the audio is processed where it was captured and nothing is uploaded.',
    'explainer.offlineStt.section.modes.heading': 'Choosing a mode: local by default, cloud on demand',
    'explainer.offlineStt.section.modes.body': 'WhisPaste defaults to local mode. The model runs on your CPU or GPU, the audio stays on the machine, and the transcript is delivered to the cursor without a network round-trip. If you need maximum speed for a long recording, you can switch a single setting to a cloud provider — but that is an explicit choice per session, not a hidden fallback.',
    'explainer.offlineStt.section.capabilities.heading': 'What offline mode can — and what it cannot',
    'explainer.offlineStt.section.capabilities.body': 'Offline Whisper handles 99 languages, mixed-language input, accents, background noise, and natural speech with pauses and restarts. What it cannot do: real-time streaming to a server, speaker diarisation across many channels, or model sizes that exceed your available RAM. The compact model fits in roughly 300 MB of GPU VRAM, the premium turbo model in about 2.6 GB.',
    'explainer.offlineStt.section.resourceProfile.heading': 'RAM and CPU profile',
    'explainer.offlineStt.section.resourceProfile.body': 'The minimum is 8 GB of RAM and a 64-bit CPU on Windows 10 or macOS 10.15 — enough for the compact model on CPU. With 16 GB of RAM and a GPU with 2–4 GB of VRAM, the balanced model transcribes a one-minute clip in seconds. Apple Silicon shares memory between CPU and GPU, so an 8 GB Mac already handles the balanced model.',
    'explainer.offlineStt.faq.modelSize.q': 'Which model size should I pick for offline speech-to-text?',
    'explainer.offlineStt.faq.modelSize.a': 'Start with the compact model — it covers everyday speech-to-text on an 8 GB machine without a GPU. If you have 16 GB of RAM and a dedicated GPU, the balanced model gives noticeably cleaner transcripts at five times the speed. The premium and ultra models are worth it only if you have 4 GB or more of free VRAM and process long recordings.',
    'explainer.offlineStt.faq.noInternet.q': 'Does offline mode really work without any internet connection?',
    'explainer.offlineStt.faq.noInternet.a': 'Yes. After the one-time model download, WhisPaste runs whisper.cpp entirely on your machine. Aeroplane mode, an air-gapped workstation, or a flaky hotspot do not affect transcription quality at all — the only thing that needs the network is the optional auto-update check, which you can disable.',
    'explainer.offlineStt.faq.accuracy.q': 'How accurate is offline speech-to-text compared to cloud APIs?',
    'explainer.offlineStt.faq.accuracy.a': 'For everyday voice input the offline balanced and premium models match what most cloud APIs produce. Specialist domains — heavy accents, very noisy environments, rare technical vocabulary — sometimes benefit from a larger cloud model. WhisPaste lets you switch per session, so you can keep offline as the default and reach for cloud only when a recording really needs it.',
    'explainer.offlineStt.cta.label': 'Get WhisPaste — free and open source',
    'explainer.privacy.breadcrumb': 'Privacy & speech recognition',
    'explainer.privacy.seoTitle': 'Privacy-friendly speech recognition — WhisPaste',
    'explainer.privacy.seoDescription': 'How WhisPaste keeps voice input private: offline by default, direct-to-provider in cloud mode, no telemetry, no account, local transcript history. Free and open source.',
    'explainer.privacy.heroHeading': 'Speech recognition that does not leave your machine — unless you ask it to.',
    'explainer.privacy.heroLead': 'When you only want to use voice input if the recording does not leave the device, WhisPaste is built around that constraint: the default mode runs offline on your machine, there is no account to create, no telemetry to opt out of, and the transcript history lives locally in an on-disk SQLite database.',
    'explainer.privacy.section.offlineDefault.heading': 'Offline by default',
    'explainer.privacy.section.offlineDefault.body': 'After install, WhisPaste runs entirely on your machine: whisper.cpp transcribes the audio locally, the transcript is delivered to the cursor, and nothing is uploaded. You actively pick a cloud provider in the settings if you want one — there is no silent fallback that would send audio off-device because the local model is "too slow".',
    'explainer.privacy.section.directProvider.heading': 'Direct-to-provider, never via our servers',
    'explainer.privacy.section.directProvider.body': 'If you opt into a cloud provider like OpenAI, Groq, or Deepgram, the audio goes directly from your machine to that provider with your own API key. WhisPaste does not proxy or buffer the recording on any server we operate, because there is no such server. The legal terms for the audio are then governed by the provider you chose — see the linked privacy policy for the full picture.',
    'explainer.privacy.section.noTelemetry.heading': 'No account, no telemetry, local history',
    'explainer.privacy.section.noTelemetry.body': 'There is no sign-up, no login, no anonymous device ID linking sessions. Crash reports are opt-in and can be turned off at any time. The transcript history is stored in a local SQLite database under your user profile, so a privacy review only has to inspect one local file — there is no cloud account to audit. For the legal text, see the <a href="/en/privacy/">privacy policy</a>.',
    'explainer.privacy.faq.dataLeaves.q': 'Does any of my audio leave the machine in the default setup?',
    'explainer.privacy.faq.dataLeaves.a': 'No. In the default offline mode, the recording is transcribed by whisper.cpp locally and discarded. The transcript is written to the local SQLite history; the audio buffer is not persisted. No background upload, no telemetry ping with content attached.',
    'explainer.privacy.faq.account.q': 'Do I need an account to use WhisPaste?',
    'explainer.privacy.faq.account.a': 'No. WhisPaste has no user account system at all. You install the app, configure a hotkey, and start using voice input. The Microsoft Store and Mac App Store use their own platform sign-in for the installation, but the app itself never asks you to log in or link an identity.',
    'explainer.privacy.faq.historyStorage.q': 'Where is my transcript history stored?',
    'explainer.privacy.faq.historyStorage.a': 'In a local SQLite database under your user profile (`%APPDATA%` on Windows, `~/Library/Application Support` on macOS). Nothing is synced to a cloud, and there is no shared config across devices. If you uninstall WhisPaste or delete that file, the history is gone — the on-disk file is the single source of truth.',
    'explainer.privacy.cta.label': 'Get WhisPaste — free and open source',
    // Comparison pages (Block E, Issue 13). These are the ONLY pages where
    // the anti-vocabulary terms (`dictation`, `Diktiersoftware`, …) may
    // appear — and only inside the `<!-- seo-audit:contrastive -->` markers
    // that the brand-vocabulary gate strips. The copy frames WhisPaste in
    // the CONTRASTIVE role: WhisPaste is never described as a dictation
    // tool itself, only as the alternative to that category. See
    // CONTEXT.md §1 (Abgrenzungs-Tabelle) and §7 (Anti-Vokabular).
    'comparison.breadcrumb': 'Comparison',
    'comparison.dictationAlternatives.breadcrumb': 'Voice-input tool alternatives',
    'comparison.dictationAlternatives.seoTitle': 'Voice-input tool alternatives — WhisPaste, offline and cloud-free',
    'comparison.dictationAlternatives.seoDescription': 'Looking for a voice-input tool without forced cloud sign-up or vendor lock-in? WhisPaste runs offline by default and pastes the transcript at your cursor — in any app, on Windows and macOS.',
    'comparison.dictationAlternatives.heroHeading': 'A voice-input tool that fits where the classic category does not — no cloud account, no app lock-in.',
    'comparison.dictationAlternatives.heroLead': 'If every voice-typing option you have evaluated requires a paid cloud account, a vendor-specific editor, or both, WhisPaste takes a different route: it is a voice-input tool that runs offline on your machine and delivers the transcript at the cursor of whatever app you are already using.',
    'comparison.dictationAlternatives.section.whyAlternative.heading': 'Why people look past the classic category',
    'comparison.dictationAlternatives.section.whyAlternative.body': 'Classic dictation software is usually built around a vendor editor: you speak inside that editor, the transcript lives there, and exporting it elsewhere costs an extra step. The cloud sign-up adds a recurring monthly fee, and the audio is often uploaded by default. WhisPaste sidesteps that whole pattern — there is no vendor editor, no account, no monthly fee, and in the default offline mode the audio never leaves the machine.',
    'comparison.dictationAlternatives.section.differentPhilosophy.heading': 'A different philosophy: paste, do not own the editor',
    'comparison.dictationAlternatives.section.differentPhilosophy.body': 'WhisPaste is not a dictation app and does not try to replace your editor. It treats voice input as a keystroke source: press the hotkey, speak, and the transcript appears at the cursor of whichever app you were already in — Outlook, Word, VS Code, a browser textarea, a terminal. That is why it works as an alternative for people who would otherwise be locked into a dictation-software ecosystem just to use their voice.',
    'comparison.dictationAlternatives.section.decisionGuide.heading': 'When the alternative fits — and when the classic tool still wins',
    'comparison.dictationAlternatives.section.decisionGuide.body': 'WhisPaste fits if you want voice input across many apps, value an offline default, and do not need a built-in editor for legal or medical templates. The classic dictation-software category still wins if you depend on vendor-specific compliance certifications, embedded medical vocabularies, or a workflow that is built around the vendor editor — those are real reasons to stay there, and WhisPaste does not pretend to replace them.',
    'comparison.dictationAlternatives.faq.isDictationSoftware.q': 'Is WhisPaste a dictation software?',
    'comparison.dictationAlternatives.faq.isDictationSoftware.a': 'No. WhisPaste is a voice-input tool — it captures audio when you press the hotkey, transcribes it, and pastes the transcript at the cursor. There is no built-in editor, no vendor document store, no template library. The classic dictation-software category typically bundles all of those; WhisPaste deliberately does not, so it can work across any app you already use.',
    'comparison.dictationAlternatives.faq.betterThanDictation.q': 'Is WhisPaste better than classic dictation software?',
    'comparison.dictationAlternatives.faq.betterThanDictation.a': 'Better and worse are the wrong axes — the two are different categories. WhisPaste is better if you want offline operation, no account, and voice input that works across apps. Classic dictation software is better if you need vendor-specific compliance, embedded medical or legal vocabularies, or a single editor that holds every transcript. Pick by which axis matters for your work.',
    'comparison.dictationAlternatives.faq.migrateFromDictation.q': 'Can I move from a dictation-software workflow to WhisPaste?',
    'comparison.dictationAlternatives.faq.migrateFromDictation.a': 'Often yes, for the voice-input part. You stop opening the vendor editor, you press the WhisPaste hotkey in the app you actually want the text in, and the transcript lands at the cursor. The piece you lose is the vendor editor itself — templates, compliance metadata, document-management features. If those are central to your work, WhisPaste is not a full replacement; if they are not, the migration is usually a question of muscle memory rather than infrastructure.',
    'comparison.dictationAlternatives.cta.label': 'Get WhisPaste — free and open source',
    'comparison.osDictation.breadcrumb': 'WhisPaste vs. system speech-to-text',
    'comparison.osDictation.seoTitle': 'WhisPaste vs. Windows and macOS system speech-to-text — voice input compared',
    'comparison.osDictation.seoDescription': 'How WhisPaste differs from the built-in speech-to-text feature in Windows and macOS: paste at the cursor in any app, pick your speech-to-text provider, and choose between offline and cloud transcription. Free and open source.',
    'comparison.osDictation.heroHeading': 'WhisPaste vs. the built-in Windows and macOS speech-to-text feature.',
    'comparison.osDictation.heroLead': 'Windows and macOS each ship a built-in speech-to-text feature that types into the focused text field. WhisPaste covers the same surface differently: it captures the audio explicitly when you press a hotkey, gives you a choice of speech-to-text providers, and pastes the transcript at the cursor — so the categories overlap, but the trade-offs do not.',
    'comparison.osDictation.section.inlineVsPaste.heading': 'Inline typing vs. paste at the cursor',
    'comparison.osDictation.section.inlineVsPaste.body': 'The OS-built-in dictation types characters into the focused field as you speak. WhisPaste does it the other way around: it records the full audio, transcribes it, and then pastes the finished transcript at the cursor in one block. The OS approach feels more like a typewriter; the WhisPaste approach feels more like reviewing and dropping a paragraph. Neither is universally better — long, structured replies tend to benefit from the paste-at-the-end model.',
    'comparison.osDictation.section.providerChoice.heading': 'One vendor vs. a choice of providers',
    'comparison.osDictation.section.providerChoice.body': 'Built-in OS dictation runs on the OS-vendor speech-to-text stack — you cannot swap it for a different engine or a different cloud. WhisPaste lets you pick: local whisper.cpp by default, or a cloud provider like OpenAI, Deepgram, or Groq when you want maximum speed. The audio in the local case never leaves the machine; the audio in the cloud case goes directly to the provider you picked, with your own API key.',
    'comparison.osDictation.section.languageSupport.heading': 'Language coverage and switching',
    'comparison.osDictation.section.languageSupport.body': 'OS dictation supports a fixed set of languages per OS version, and switching usually means changing the system input source. WhisPaste covers 99 Whisper-supported languages, handles mixed-language input inside the same recording, and switches model or provider with a setting toggle — no OS-level keyboard-layout dance, no logout-login cycle.',
    'comparison.osDictation.faq.inAnyApp.q': 'Does the OS dictation not already work in every app?',
    'comparison.osDictation.faq.inAnyApp.a': 'It works in most text fields, but the experience is uneven: some apps accept the streamed keystrokes cleanly, others reject auto-capitalisation or punctuation, and the OS dictation cannot be triggered from contexts where the system overlay is blocked. WhisPaste sidesteps the streaming model by pasting a finished transcript — the only thing the target app needs to support is a paste, which every text field does.',
    'comparison.osDictation.faq.whenSystemDictation.q': 'When should I just use the system dictation instead?',
    'comparison.osDictation.faq.whenSystemDictation.a': 'If you only ever speak one or two sentences at a time into a single OS-supported language, and you do not care which speech engine processes the audio, the system dictation is fine and one less app to install. WhisPaste pays off when you want offline operation, multiple languages in a row, a longer transcript reviewed before paste, or a different provider than the OS vendor.',
    'comparison.osDictation.faq.multiLanguage.q': 'Can WhisPaste handle multiple languages better than the OS dictation?',
    'comparison.osDictation.faq.multiLanguage.a': 'Yes, in two ways. First, a single Whisper recording can contain code-switching (English-German, Spanish-English, etc.) and the model transcribes it as spoken, where the OS dictation usually forces a single input language per session. Second, switching the primary language is a setting toggle in WhisPaste; in the OS dictation it is tied to the system input source, which has its own UX cost.',
    'comparison.osDictation.cta.label': 'Get WhisPaste — free and open source',
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
    'gallery.desc': 'Fünf Ansichten für den ganzen Workflow — vom Transkript zum fertigen Text.',
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
    'download.diagnose.title': 'Sprachdienst startet nicht?',
    'download.diagnose.desc': 'Erstelle mit unserem Werkzeug einen Diagnose-Report und sende ihn uns — so finden wir das Problem schnell.',
    'download.diagnose.step1.title': 'Diagnose-Werkzeug herunterladen',
    'download.diagnose.step1.desc': 'Wähle unten die passende Variante für dein System.',
    'download.diagnose.step2.title': 'Ausführen',
    'download.diagnose.step2.desc': 'Unter Windows die .exe doppelklicken; unter macOS die .dmg öffnen und WhisPaste-Diagnose.app doppelklicken. Es legt einen Report auf dem Schreibtisch ab.',
    'download.diagnose.step3.title': 'Report an uns senden',
    'download.diagnose.step3.desc': 'Hänge die erzeugte Datei an eine E-Mail an — so sehen wir die Sprachdienst-Umgebung und das Ergebnis des Modell-Ladetests.',
    'download.diagnose.btnHint': 'Diagnose-Werkzeug für',
    'download.diagnose.mailHint': 'Report senden an',
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
    'footer.download': 'Download',
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
    // Long-Tail-Use-Case-Pages (Block E). „Use Cases" bleibt bewusst englisch
    // — etablierter Begriff in der dt. Tech-Sprache, kürzer als
    // „Anwendungsfälle" und konsistent mit dem PRD-§E-Pfad `/use-cases/`.
    'breadcrumb.useCases': 'Use Cases',
    // Programmierer-Use-Case — Vokabular Glossar-konform: keine „Diktat/-
    // Diktieren/Diktier-Tool"-Begriffe (Anti-Vokabular CONTEXT.md §7).
    // Stattdessen `Spracheingabe`, `Sprach-Eingabe-Tool`, `Transkript`,
    // `transkribiert`. Der Hero-Lead beantwortet den
    // `docs/zielgruppe.md`-Lackmustest („Entwickler mitten im Code-Review,
    // fünfsätzige Antwort, ohne Maus, ohne Browser-Wechsel") explizit.
    'useCase.programmer.breadcrumb': 'Entwickler',
    'useCase.programmer.seoTitle': 'WhisPaste für Entwickler — Spracheingabe für Code-Reviews, Commits und Issues',
    'useCase.programmer.seoDescription': 'Code-Reviews beantworten, Commit-Messages schreiben und Issues kommentieren — per Stimme, ohne den Browser zu wechseln und ohne zur Maus zu greifen. Offline-first Sprach-Eingabe-Tool für den Entwickler-Workflow.',
    'useCase.programmer.heroHeading': 'Spracheingabe für Entwickler — im Browser bleiben, die Finger auf der Tastatur.',
    'useCase.programmer.heroLead': 'Wenn du mitten im Code-Review steckst und eine fünfsätzige Antwort schreiben willst, lässt dich WhisPaste die Antwort direkt ins GitHub-Textfeld sprechen — ohne App-Wechsel, ohne die Maus zu greifen, ohne aus deinem Flow zu fallen.',
    'useCase.programmer.section.codeReview.heading': 'Code-Reviews ohne Kontextwechsel',
    'useCase.programmer.section.codeReview.body': 'Ein Pull-Request-Review braucht Nuancen: Ein „sieht gut aus" ist zu wenig, eine Textwand verliert den Reviewer. Mit WhisPaste drückst du dein Tastenkürzel, sprichst die Erklärung, während du den Diff liest, und das Transkript landet direkt im GitHub-Antwortfeld — schon korrekt großgeschrieben, mit Code-Identifiern wie `fooBar`, wenn du sie buchstabierst.',
    'useCase.programmer.section.gitCommits.heading': 'Commit-Messages und PR-Beschreibungen',
    'useCase.programmer.section.gitCommits.body': 'Conventional Commits und PR-Bodies verdienen oft mehr als drei Worte, aber der Aufwand, sie zu schreiben, bremst dich. Editor öffnen, Begründung sprechen — das Transkript erscheint am Cursor und ist bereit, bearbeitet, mit einem Sprach-Snippet erweitert oder ins Terminal eingefügt zu werden.',
    'useCase.programmer.section.issueTracker.heading': 'Issue-Tracker, Slack und Standups',
    'useCase.programmer.section.issueTracker.body': 'Repro-Schritte in einem Bug-Ticket, asynchrone Standup-Notizen in Slack, ein schneller Kommentar an einem Linear-Issue — alle kurz, alle reibungsanfällig. WhisPaste läuft im Hintergrund und funktioniert überall, wo dein Cursor steht: GitHub, GitLab, Jira, Linear, Discord, Slack, dein Editor. Im lokalen Modus bleibt das Audio auf deinem Rechner.',
    'useCase.programmer.howTo.name': 'So nutzt du WhisPaste im Dev-Workflow',
    'useCase.programmer.howTo.step1.name': 'Setze den Cursor ins Antwortfeld',
    'useCase.programmer.howTo.step1.text': 'Klicke ins GitHub-Review-Feld, in den Commit-Message-Editor oder ins Slack-Eingabefeld — überall dort, wo du sonst tippen würdest.',
    'useCase.programmer.howTo.step2.name': 'Tastenkürzel drücken und sprechen',
    'useCase.programmer.howTo.step2.text': 'Halte dein konfiguriertes Tastenkürzel, sprich deine Antwort aus und lass los. Das Transkript entsteht standardmäßig lokal auf deinem Rechner.',
    'useCase.programmer.howTo.step3.name': 'Das Transkript erscheint am Cursor',
    'useCase.programmer.howTo.step3.text': 'Dein Text landet dort, wo der Cursor stand. Bearbeiten, mit einem Sprach-Snippet erweitern oder direkt absenden — kein Copy-Paste zwischen Stimme und Text.',
    'useCase.programmer.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    'useCase.rsi.breadcrumb': 'RSI',
    'useCase.rsi.seoTitle': 'WhisPaste bei RSI — Spracheingabe, wenn Tippen schmerzt',
    'useCase.rsi.seoDescription': 'Für Wissensarbeitende mit RSI: Text per Stimme produzieren statt über die Tastatur — in jeder App, ohne den Workflow zu verlassen. Offline-first Sprach-Eingabe-Tool, das mit schlechten Tipp-Tagen umgehen kann.',
    'useCase.rsi.heroHeading': 'Spracheingabe bei RSI — weiterarbeiten an den Tagen, an denen deine Hände nicht mehr können.',
    'useCase.rsi.heroLead': 'Wenn Handgelenke, Finger oder Unterarme entzündet sind und das Drücken von Tasten keine Option mehr ist, lässt dich WhisPaste Text per Stimme in dieselben Apps produzieren, die du ohnehin nutzt — ohne Tool-Wechsel, ohne deinen Editor zu verlassen, ohne den Tag aufzugeben.',
    'useCase.rsi.section.flow.heading': 'Im Workflow bleiben an schlechten Tipp-Tagen',
    'useCase.rsi.section.flow.body': 'Ein RSI-Schub kündigt sich nicht an. WhisPaste läuft im Hintergrund und ersetzt das Tippen genau dort, wo dein Cursor steht: E-Mail, Chat, Ticket-Tool, Dokumenten-Editor. Du drückst einmal das Tastenkürzel, sprichst in deinem Tempo, und das Transkript erscheint am Cursor — damit aus einem schlechten Hände-Nachmittag kein verlorener Arbeitstag wird.',
    'useCase.rsi.section.ergonomics.heading': 'Ergonomie ohne Kontextwechsel',
    'useCase.rsi.section.ergonomics.body': 'Die meisten Accessibility-Tools zwingen dich, die laufende App zu verlassen: ein eigenes Fenster, eine eigene Zwischenablage, ein eigener Paste-Schritt. WhisPaste vermeidet diesen Aufwand — das Transkript landet dort, wo du ohnehin gearbeitet hast. So bleibt eine App offen statt drei, und Schultern, Nacken und Augen müssen nicht weiteren Fenstern hinterherjagen.',
    'useCase.rsi.section.dailyVariation.heading': 'Gebaut für Tage, die nicht gleich sind',
    'useCase.rsi.section.dailyVariation.body': 'RSI verläuft nicht linear. An manchen Tagen tippst du eine Stunde lang problemlos, an anderen tut bereits die erste E-Mail weh. WhisPaste verlangt kein Setup-Ritual: das Tastenkürzel ist immer da, Spracheingabe ist immer einen Druck entfernt, und du kannst Tippen und Sprechen Satz für Satz mischen — so wie der Tag es zulässt.',
    'useCase.rsi.faq.karpaltunnel.q': 'Hilft WhisPaste bei Karpaltunnel oder Sehnenscheidenentzündung?',
    'useCase.rsi.faq.karpaltunnel.a': 'WhisPaste ist keine medizinische Behandlung, nimmt aber für Wissensarbeit einen großen Teil der Tipp-Last raus. Viele Betroffene mit Karpaltunnel, Tendinitis oder allgemeinem RSI nutzen Spracheingabe als primären Schreibweg — WhisPaste macht das in Apps ohne native Sprach-Unterstützung praktikabel, weil das Transkript wie jeder andere Tastenanschlag direkt am Cursor erscheint.',
    'useCase.rsi.faq.pauses.q': 'Funktioniert das, wenn ich mitten im Satz pausieren oder durchatmen muss?',
    'useCase.rsi.faq.pauses.a': 'Ja. WhisPaste nimmt so lange auf, wie du das Tastenkürzel hältst oder bis du die Aufnahme beendest. Pausen innerhalb der Aufnahme zerschneiden das Transkript nicht; das Modell kommt mit natürlicher Sprache, Pausen, Zögern und Neuansätzen klar. Du entscheidest, wann ein Abschnitt endet — kein Timer.',
    'useCase.rsi.faq.dayVariation.q': 'Meine Stimme schwankt von Tag zu Tag — kommt WhisPaste damit zurecht?',
    'useCase.rsi.faq.dayVariation.a': 'Das Whisper-Modell, das die Offline-Transkription trägt, ist auf eine große Bandbreite von Stimmen und Bedingungen trainiert — inklusive Müdigkeit, Erkältung und Akzent-Varianz. Wenn ein Tag besonders unsaubere Transkripte produziert, kannst du für die Sitzung auch zu einem Cloud-Anbieter wechseln — kein Reconfig, nur ein Setting-Schalter.',
    'useCase.rsi.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    'useCase.support.breadcrumb': 'Support-Mitarbeiter',
    'useCase.support.seoTitle': 'WhisPaste für Support-Mitarbeitende — Spracheingabe für Ticket-Antworten',
    'useCase.support.seoDescription': 'Für Helpdesk- und Kundensupport: Tickets schneller beantworten, indem du die Antwort direkt ins Ticket-UI sprichst — ohne App-Wechsel, ohne Copy-Paste. Offline-first Sprach-Eingabe-Tool.',
    'useCase.support.heroHeading': 'Spracheingabe für Support-Mitarbeitende — Tickets beantworten, ohne den Browser zu wechseln.',
    'useCase.support.heroLead': 'Wenn du eine Warteschlange Helpdesk-Tickets abarbeitest und mehr als ein Standard-Makro brauchst, lässt dich WhisPaste die Antwort direkt ins Ticket-Textfeld sprechen — ohne App-Wechsel, ohne Copy-Paste aus einem Nebenfenster, ohne deinen Queue-Rhythmus zu unterbrechen.',
    'useCase.support.section.workflow.heading': 'Eine Ticket-Antwort, die den Queue-Rhythmus nicht unterbricht',
    'useCase.support.section.workflow.body': 'Helpdesk-Arbeit ist repetitiv, aber nie identisch: jede Antwort braucht einen persönlichen Satz, eine spezifische Anweisung oder eine frische Empathie-Zeile über dem Makro. WhisPaste passt genau zwischen Makro und Senden — Makro reinholen, Cursor an die Stelle setzen, an der der persönliche Satz hin soll, Tastenkürzel drücken, Ergänzung sprechen, und das Transkript erscheint inline.',
    'useCase.support.section.tools.heading': 'Funktioniert in Zendesk, Freshdesk, Intercom und euren eigenen Tools',
    'useCase.support.section.tools.body': 'WhisPaste ist kein Zendesk-Plugin und hängt deshalb nicht an einem bestimmten Ticketing-Anbieter. Es funktioniert überall, wo der Cursor steht: webbasierte Ticket-UIs, interne Tools, Slack-Übergaben, Eskalations-Mails. Wenn euer Team mehrere Ticketing-Systeme oder ein internes Helpdesk-Tool im Mix hat, verhält sich die Spracheingabe in allen gleich.',
    'useCase.support.section.savings.heading': 'Zeit pro Ticket sparen, nicht pro Schicht',
    'useCase.support.section.savings.body': 'Die Reibung in einer Support-Antwort sind nicht die langen Absätze — es ist das ständige Mikro-Tippen für Begrüßungen, Verabschiedungen und klärende Sätze. Wenn du diese durch zwei-Sekunden-Sprach-Segmente ersetzt, spart das in jedem Ticket Sekunden. Über eine Schicht mit 60 bis 100 Tickets summiert sich das zu spürbar weniger Tastenanschlägen und weniger Handgelenks-Belastung.',
    'useCase.support.howTo.step1.name': 'Ticket öffnen und Cursor ins Antwortfeld setzen',
    'useCase.support.howTo.step1.text': 'Nimm das nächste Ticket aus der Queue, hol dein Makro rein, falls du eins nutzt, und klicke in das Textfeld an die Stelle, an der der persönliche Satz hin soll.',
    'useCase.support.howTo.step2.name': 'Tastenkürzel drücken und Antwort sprechen',
    'useCase.support.howTo.step2.text': 'Halte dein konfiguriertes Tastenkürzel und sprich die Antwort — komplette Reply oder nur den personalisierten Absatz. Lass los, wenn du fertig bist.',
    'useCase.support.howTo.step3.name': 'Transkript prüfen und senden',
    'useCase.support.howTo.step3.text': 'Das Transkript erscheint am Cursor. Drüberlesen, ein Wort anpassen, falls nötig, und senden — kein zusätzlicher Paste-Schritt, kein Sprung zurück in eine separate Sprach-App.',
    'useCase.support.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    // Erklär-Pages (Block E, Issue 12). Drei thematische Long-Tail-Pages, die
    // tiefere technische Suchen rund um Whisper-als-Desktop-Tool, Offline-
    // Speech-to-Text und Datenschutz-bewusste Spracherkennung auffangen.
    // Vokabular strikt Glossar-konform — keine „Diktat/-Diktieren/Diktier-
    // Tool/Sprachassistent/Sprachsteuerung/Sprach-Übersetzer"-Begriffe; die
    // Erklär-Texte rahmen WhisPaste als `Sprach-Eingabe-Tool` mit
    // `Transkript` als Artefakt.
    'explainer.whisperDesktop.breadcrumb': 'Whisper Desktop',
    'explainer.whisperDesktop.seoTitle': 'Whisper als Desktop-Tool — lokale Spracherkennung mit WhisPaste',
    'explainer.whisperDesktop.seoDescription': 'OpenAI Whisper als Desktop-Sprach-Eingabe-Tool für Windows und macOS nutzen — ohne Python, ohne Cloud-Account. WhisPaste bündelt whisper.cpp, verwaltet die Modelle und liefert das Transkript direkt am Cursor.',
    'explainer.whisperDesktop.heroHeading': 'Whisper als Desktop-Tool — ohne Python, ohne Cloud-Account.',
    'explainer.whisperDesktop.heroLead': 'Wenn du OpenAI Whisper auf deinem eigenen Rechner nutzen willst, aber keine Python-Umgebung zusammenbauen, keine CUDA-Wheels verwalten und keinen Cloud-Account bezahlen möchtest, liefert WhisPaste whisper.cpp in einer nativen Desktop-App — ein Installer, ein Tastenkürzel, und das Transkript landet am Cursor.',
    'explainer.whisperDesktop.section.setup.heading': 'Setup: ein Installer, keine Python-Umgebung',
    'explainer.whisperDesktop.section.setup.body': 'WhisPaste bettet whisper.cpp — den C++-Port von OpenAI Whisper — direkt in das Desktop-Binary ein. Nach der Installation wählst du im Dropdown eine Modellgröße, die App lädt sie einmalig herunter, und ab dann läuft die Transkription vollständig offline auf deinem Rechner. Kein Virtualenv, kein pip, kein CUDA-Toolkit; die GPU-Beschleunigung kommt über Vulkan- oder CUDA-Runtimes, sofern vorhanden, bereits mit.',
    'explainer.whisperDesktop.section.performance.heading': 'Performance: CPU reicht, GPU ist fünfmal schneller',
    'explainer.whisperDesktop.section.performance.body': 'whisper.cpp läuft auf jeder unterstützten Maschine auf reiner CPU (Windows 10+, macOS 10.15+), deshalb genügt ein 8-GB-Laptop ohne dedizierte GPU für das kompakte Modell. Auf einem Rechner mit dedizierter GPU — NVIDIA CUDA, AMD oder Intel Vulkan — entsteht dasselbe Transkript ungefähr fünfmal schneller. Apple Silicon nutzt Unified Memory, weshalb 8 GB bereits für das ausgewogene Modell reichen.',
    'explainer.whisperDesktop.section.localVsCloud.heading': 'Lokal vs. Cloud: dasselbe Whisper, andere Trade-offs',
    'explainer.whisperDesktop.section.localVsCloud.body': 'Lokales Whisper behält das Audio auf dem Rechner, kostet pro Minute nichts und funktioniert ohne Internet — zum Preis eines einmaligen Modell-Downloads und etwas mehr RAM. Cloud-Anbieter wie OpenAI, Groq oder Deepgram tauschen diese Ressourcen gegen rohe Geschwindigkeit und die größten Modelle. WhisPaste lässt dich pro Sitzung wählen: standardmäßig lokal bleiben, für maximale Geschwindigkeit bei langen Aufnahmen einen Cloud-Anbieter zuschalten.',
    'explainer.whisperDesktop.howTo.name': 'So nutzt du Whisper als Desktop-Tool mit WhisPaste',
    'explainer.whisperDesktop.howTo.step1.name': 'WhisPaste installieren und Whisper-Modell wählen',
    'explainer.whisperDesktop.howTo.step1.text': 'Lade WhisPaste aus dem Microsoft Store, dem Mac App Store oder von GitHub. Beim ersten Start schlägt der Einrichtungsassistent auf Basis deiner Hardware eine Modellgröße vor — kompakt für ein 8-GB-Laptop, ausgewogen für 16 GB mit GPU, Premium für mehr VRAM.',
    'explainer.whisperDesktop.howTo.step2.name': 'Das Modell einmalig laden lassen',
    'explainer.whisperDesktop.howTo.step2.text': 'WhisPaste holt das gewählte whisper.cpp-Modell im Hintergrund und prüft die Datei. Der Download setzt nach unterbrochenen Verbindungen automatisch fort, sodass ein wackeliges Netz dich nicht zwingt, neu anzufangen. Danach läuft die Transkription vollständig offline.',
    'explainer.whisperDesktop.howTo.step3.name': 'Tastenkürzel drücken und sprechen',
    'explainer.whisperDesktop.howTo.step3.text': 'Setze den Cursor an die Stelle, an der der Text hin soll, halte dein konfiguriertes Tastenkürzel und sprich. whisper.cpp transkribiert das Audio auf deinem Rechner, und das Transkript erscheint am Cursor — kein Upload, kein Browser-Tab, kein Copy-Paste-Schritt.',
    'explainer.whisperDesktop.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    'explainer.offlineStt.breadcrumb': 'Offline-Speech-to-Text',
    'explainer.offlineStt.seoTitle': 'Offline-Speech-to-Text für Windows und macOS — WhisPaste',
    'explainer.offlineStt.seoDescription': 'Offline-Speech-to-Text auf dem Desktop: wie der lokale Whisper-Modus funktioniert, was er kann und was nicht, und welches RAM-/CPU-Profil du brauchst. Kostenlos und Open Source.',
    'explainer.offlineStt.heroHeading': 'Offline-Speech-to-Text — wenn die Aufnahme den Rechner nicht verlassen darf.',
    'explainer.offlineStt.heroLead': 'Wenn du Speech-to-Text auf deinem Laptop willst, die Aufnahme aber das Gerät nicht verlassen darf — wegen eines Kundenvertrags, einer regulierten Branche oder schlicht aus persönlicher Präferenz — fährt WhisPaste die gesamte Transkriptions-Pipeline lokal mit whisper.cpp. Das Audio wird dort verarbeitet, wo es aufgenommen wurde, und nichts wird hochgeladen.',
    'explainer.offlineStt.section.modes.heading': 'Modus-Wahl: lokal als Default, Cloud auf Abruf',
    'explainer.offlineStt.section.modes.body': 'WhisPaste startet im lokalen Modus. Das Modell läuft auf deiner CPU oder GPU, das Audio bleibt auf dem Rechner, und das Transkript wird ohne Netzwerk-Round-Trip an den Cursor geliefert. Wenn du für eine lange Aufnahme maximale Geschwindigkeit brauchst, kannst du in den Einstellungen einen Cloud-Anbieter wählen — das ist aber eine explizite Entscheidung pro Sitzung, kein versteckter Fallback.',
    'explainer.offlineStt.section.capabilities.heading': 'Was Offline kann — und was nicht',
    'explainer.offlineStt.section.capabilities.body': 'Offline-Whisper kommt mit 99 Sprachen, gemischtsprachigen Eingaben, Akzenten, Hintergrundgeräuschen und natürlicher Sprache mit Pausen und Neuansätzen klar. Was es nicht kann: Echtzeit-Streaming an einen Server, Sprecher-Diarisierung über viele Kanäle oder Modellgrößen, die deinen verfügbaren RAM überschreiten. Das kompakte Modell passt in etwa 300 MB GPU-VRAM, das Premium-Turbo-Modell in rund 2,6 GB.',
    'explainer.offlineStt.section.resourceProfile.heading': 'RAM- und CPU-Profil',
    'explainer.offlineStt.section.resourceProfile.body': 'Das Minimum sind 8 GB RAM und eine 64-Bit-CPU unter Windows 10 oder macOS 10.15 — genug für das kompakte Modell auf der CPU. Mit 16 GB RAM und einer GPU mit 2–4 GB VRAM transkribiert das ausgewogene Modell einen Ein-Minuten-Clip in Sekunden. Apple Silicon teilt sich den Speicher zwischen CPU und GPU, weshalb ein 8-GB-Mac schon das ausgewogene Modell trägt.',
    'explainer.offlineStt.faq.modelSize.q': 'Welche Modellgröße soll ich für Offline-Speech-to-Text wählen?',
    'explainer.offlineStt.faq.modelSize.a': 'Starte mit dem kompakten Modell — es deckt Alltags-Speech-to-Text auf einer 8-GB-Maschine ohne GPU ab. Wenn du 16 GB RAM und eine dedizierte GPU hast, liefert das ausgewogene Modell merklich sauberere Transkripte bei fünffacher Geschwindigkeit. Premium und Ultra lohnen sich erst, wenn du 4 GB oder mehr freies VRAM hast und längere Aufnahmen verarbeitest.',
    'explainer.offlineStt.faq.noInternet.q': 'Funktioniert der Offline-Modus wirklich ganz ohne Internet?',
    'explainer.offlineStt.faq.noInternet.a': 'Ja. Nach dem einmaligen Modell-Download läuft whisper.cpp vollständig auf deinem Rechner. Flugmodus, eine Air-gapped Workstation oder ein wackeliger Hotspot beeinflussen die Transkriptionsqualität gar nicht — das einzige, was Netz braucht, ist der optionale Auto-Update-Check, den du deaktivieren kannst.',
    'explainer.offlineStt.faq.accuracy.q': 'Wie genau ist Offline-Speech-to-Text im Vergleich zu Cloud-APIs?',
    'explainer.offlineStt.faq.accuracy.a': 'Für alltägliche Spracheingabe ziehen die Offline-Modelle „ausgewogen" und „Premium" mit dem gleich, was die meisten Cloud-APIs produzieren. Spezialdomänen — starke Akzente, sehr laute Umgebungen, seltenes Fachvokabular — profitieren manchmal von einem größeren Cloud-Modell. WhisPaste lässt dich pro Sitzung umschalten, sodass du Offline als Standard fährst und Cloud nur dann holst, wenn eine Aufnahme es wirklich braucht.',
    'explainer.offlineStt.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    'explainer.privacy.breadcrumb': 'Privatsphäre & Spracherkennung',
    'explainer.privacy.seoTitle': 'Privatsphäre-freundliche Spracherkennung — WhisPaste',
    'explainer.privacy.seoDescription': 'Wie WhisPaste Spracheingabe privat hält: offline als Standard, Direct-to-Provider im Cloud-Modus, keine Telemetrie, kein Account, lokaler Transkript-Verlauf. Kostenlos und Open Source.',
    'explainer.privacy.heroHeading': 'Spracherkennung, die den Rechner nicht verlässt — außer du willst es so.',
    'explainer.privacy.heroLead': 'Wenn du Spracheingabe nur einsetzen willst, wenn die Aufnahme das Gerät nicht verlässt, ist WhisPaste genau um diese Einschränkung herum gebaut: Der Standardmodus läuft offline auf deinem Rechner, es gibt keinen Account anzulegen, keine Telemetrie abzubestellen, und der Transkript-Verlauf liegt lokal in einer SQLite-Datenbank auf der Platte.',
    'explainer.privacy.section.offlineDefault.heading': 'Offline als Standard',
    'explainer.privacy.section.offlineDefault.body': 'Nach der Installation läuft WhisPaste vollständig auf deinem Rechner: whisper.cpp transkribiert das Audio lokal, das Transkript landet am Cursor, und nichts wird hochgeladen. Einen Cloud-Anbieter wählst du aktiv in den Einstellungen — es gibt keinen stillen Fallback, der Audio off-device schicken würde, weil das lokale Modell „zu langsam" sei.',
    'explainer.privacy.section.directProvider.heading': 'Direct-to-Provider, nie über unsere Server',
    'explainer.privacy.section.directProvider.body': 'Wenn du dich für einen Cloud-Anbieter wie OpenAI, Groq oder Deepgram entscheidest, geht das Audio direkt von deinem Rechner an diesen Anbieter — mit deinem eigenen API-Key. WhisPaste proxyt oder puffert die Aufnahme nicht auf einem Server, den wir betreiben, denn so einen Server gibt es nicht. Die rechtlichen Bedingungen für das Audio richten sich dann nach dem Anbieter, den du gewählt hast — die volle Übersicht steht in der verlinkten Datenschutzerklärung.',
    'explainer.privacy.section.noTelemetry.heading': 'Kein Account, keine Telemetrie, lokaler Verlauf',
    'explainer.privacy.section.noTelemetry.body': 'Es gibt keine Registrierung, kein Login, keine anonyme Geräte-ID, die Sitzungen verknüpft. Crash-Reports sind opt-in und jederzeit abschaltbar. Der Transkript-Verlauf liegt in einer lokalen SQLite-Datenbank unter deinem Benutzerprofil — eine Datenschutz-Prüfung muss also nur eine lokale Datei inspizieren; es gibt keinen Cloud-Account zu auditieren. Den Rechtstext findest du in der <a href="/datenschutz/">Datenschutzerklärung</a>.',
    'explainer.privacy.faq.dataLeaves.q': 'Verlässt mein Audio im Standard-Setup den Rechner?',
    'explainer.privacy.faq.dataLeaves.a': 'Nein. Im standardmäßigen Offline-Modus wird die Aufnahme von whisper.cpp lokal transkribiert und danach verworfen. Das Transkript schreibt WhisPaste in den lokalen SQLite-Verlauf; der Audio-Puffer wird nicht persistiert. Kein Hintergrund-Upload, kein Telemetrie-Ping mit Inhalt im Schlepptau.',
    'explainer.privacy.faq.account.q': 'Brauche ich einen Account, um WhisPaste zu nutzen?',
    'explainer.privacy.faq.account.a': 'Nein. WhisPaste hat überhaupt kein Account-System. Du installierst die App, konfigurierst ein Tastenkürzel und legst los. Microsoft Store und Mac App Store nutzen ihren eigenen Plattform-Login für die Installation, aber die App selbst fragt dich nie nach einem Login oder einer Identität.',
    'explainer.privacy.faq.historyStorage.q': 'Wo wird mein Transkript-Verlauf gespeichert?',
    'explainer.privacy.faq.historyStorage.a': 'In einer lokalen SQLite-Datenbank unter deinem Benutzerprofil (`%APPDATA%` unter Windows, `~/Library/Application Support` unter macOS). Nichts wird in eine Cloud synchronisiert, und es gibt keine geteilte Config über mehrere Geräte. Wenn du WhisPaste deinstallierst oder diese Datei löschst, ist der Verlauf weg — die Datei ist die einzige Quelle der Wahrheit.',
    'explainer.privacy.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    // Vergleichs-Pages (Block E, Issue 13). Das sind die EINZIGEN Pages,
    // auf denen das Anti-Vokabular (`Diktiersoftware`, `Diktat`, …) bewusst
    // auftaucht — und auch nur innerhalb der `<!-- seo-audit:contrastive -->`-
    // Marker, die der Brand-Vocabulary-Gate ausklammert. Die Copy hält
    // WhisPaste in der KONTRASTIVEN Rolle: WhisPaste wird nie selbst als
    // Diktiersoftware bezeichnet, sondern nur als Alternative zu dieser
    // Kategorie. Siehe CONTEXT.md §1 (Abgrenzungs-Tabelle) und §7
    // (Anti-Vokabular).
    'comparison.breadcrumb': 'Vergleich',
    'comparison.dictationAlternatives.breadcrumb': 'Sprach-Eingabe-Tool-Alternativen',
    'comparison.dictationAlternatives.seoTitle': 'Sprach-Eingabe-Tool-Alternativen — WhisPaste, offline und ohne Cloud-Zwang',
    'comparison.dictationAlternatives.seoDescription': 'Du suchst ein Sprach-Eingabe-Tool ohne Cloud-Pflicht oder Hersteller-Bindung? WhisPaste läuft standardmäßig offline und fügt das Transkript am Cursor ein — in jeder App, unter Windows und macOS.',
    'comparison.dictationAlternatives.heroHeading': 'Ein Sprach-Eingabe-Tool, das dort passt, wo die klassische Kategorie nicht passt — ohne Cloud-Account, ohne App-Zwang.',
    'comparison.dictationAlternatives.heroLead': 'Wenn jede Sprach-zu-Text-Option, die du dir angeschaut hast, einen kostenpflichtigen Cloud-Account, einen herstellereigenen Editor oder beides verlangt, geht WhisPaste einen anderen Weg: Es ist ein Sprach-Eingabe-Tool, das offline auf deinem Rechner läuft und das Transkript am Cursor der App einfügt, in der du ohnehin gerade arbeitest.',
    'comparison.dictationAlternatives.section.whyAlternative.heading': 'Warum viele über die klassische Kategorie hinausschauen',
    'comparison.dictationAlternatives.section.whyAlternative.body': 'Klassische Diktiersoftware ist meistens um einen Hersteller-Editor herum gebaut: Du sprichst in diesem Editor, das Diktat lebt dort, und der Export an anderer Stelle kostet einen Extra-Schritt. Der Cloud-Zwang bringt eine monatliche Gebühr mit, und das Audio wird häufig standardmäßig hochgeladen. WhisPaste umgeht dieses ganze Muster — es gibt keinen Hersteller-Editor, keinen Account, keine Monatsgebühr, und im standardmäßigen Offline-Modus verlässt das Audio den Rechner nicht.',
    'comparison.dictationAlternatives.section.differentPhilosophy.heading': 'Andere Philosophie: einfügen, nicht den Editor besitzen',
    'comparison.dictationAlternatives.section.differentPhilosophy.body': 'WhisPaste ist keine Diktiersoftware und versucht nicht, deinen Editor zu ersetzen. Es behandelt Spracheingabe als Tastenanschlag-Quelle: Hotkey drücken, sprechen, und das Transkript erscheint am Cursor der App, in der du ohnehin warst — Outlook, Word, VS Code, ein Browser-Textfeld, ein Terminal. Genau deshalb funktioniert es als Alternative für alle, die sonst im Ökosystem einer Diktiersoftware festsitzen würden, nur um ihre Stimme nutzen zu können.',
    'comparison.dictationAlternatives.section.decisionGuide.heading': 'Wann die Alternative passt — und wann das klassische Tool gewinnt',
    'comparison.dictationAlternatives.section.decisionGuide.body': 'WhisPaste passt, wenn du Spracheingabe app-übergreifend willst, einen Offline-Standard schätzt und keinen eingebauten Editor für juristische oder medizinische Vorlagen brauchst. Die klassische Diktiersoftware-Kategorie gewinnt weiterhin, wenn du auf herstellerspezifische Compliance-Zertifizierungen, eingebettete medizinische Fachvokabularien oder einen Workflow rund um den Hersteller-Editor angewiesen bist — das sind echte Gründe, dort zu bleiben, und WhisPaste tut nicht so, als würde es sie ersetzen.',
    'comparison.dictationAlternatives.faq.isDictationSoftware.q': 'Ist WhisPaste eine Diktiersoftware?',
    'comparison.dictationAlternatives.faq.isDictationSoftware.a': 'Nein. WhisPaste ist ein Sprach-Eingabe-Tool — es nimmt Audio auf, wenn du den Hotkey drückst, transkribiert es und fügt das Transkript am Cursor ein. Es gibt keinen eingebauten Editor, keinen Hersteller-Dokumentenspeicher, keine Vorlagen-Bibliothek. Die klassische Diktiersoftware-Kategorie bündelt all das typischerweise; WhisPaste verzichtet bewusst darauf, damit es in jeder App funktioniert, die du ohnehin nutzt.',
    'comparison.dictationAlternatives.faq.betterThanDictation.q': 'Ist WhisPaste besser als klassische Diktiersoftware?',
    'comparison.dictationAlternatives.faq.betterThanDictation.a': 'Besser und schlechter sind die falschen Achsen — die beiden sind unterschiedliche Kategorien. WhisPaste ist besser, wenn du Offline-Betrieb, keinen Account und app-übergreifende Spracheingabe willst. Klassische Diktiersoftware ist besser, wenn du herstellerspezifische Compliance, eingebettete medizinische oder juristische Fachvokabularien oder einen einzigen Editor brauchst, der jedes Diktat hält. Entscheide entlang der Achse, die für deine Arbeit zählt.',
    'comparison.dictationAlternatives.faq.migrateFromDictation.q': 'Kann ich von einem Diktiersoftware-Workflow auf WhisPaste umsteigen?',
    'comparison.dictationAlternatives.faq.migrateFromDictation.a': 'Für den Sprach-Eingabe-Teil meistens ja. Du öffnest den Hersteller-Editor nicht mehr, du drückst den WhisPaste-Hotkey in genau der App, in der der Text landen soll, und das Transkript erscheint am Cursor. Was du verlierst, ist der Hersteller-Editor selbst — Vorlagen, Compliance-Metadaten, Dokumentenverwaltung. Wenn das zentral für deine Arbeit ist, ist WhisPaste kein vollständiger Ersatz; wenn nicht, ist die Umstellung eher eine Frage von Muskel-Gedächtnis als von Infrastruktur.',
    'comparison.dictationAlternatives.cta.label': 'WhisPaste holen — kostenlos und Open Source',
    'comparison.osDictation.breadcrumb': 'WhisPaste vs. System-Spracheingabe',
    'comparison.osDictation.seoTitle': 'WhisPaste vs. Windows- und macOS-Spracheingabe — Spracheingabe im Vergleich',
    'comparison.osDictation.seoDescription': 'Wie WhisPaste sich von der eingebauten Spracheingabe in Windows und macOS unterscheidet: Einfügen am Cursor in jeder App, Wahl des Speech-to-Text-Anbieters, Offline- oder Cloud-Transkription. Kostenlos und Open Source.',
    'comparison.osDictation.heroHeading': 'WhisPaste vs. die eingebaute Windows- und macOS-Spracheingabe.',
    'comparison.osDictation.heroLead': 'Windows und macOS bringen jeweils eine eingebaute Spracheingabe-Funktion mit, die in das fokussierte Textfeld tippt. WhisPaste deckt dieselbe Fläche anders ab: Es nimmt das Audio explizit auf, wenn du einen Hotkey drückst, lässt dich den Speech-to-Text-Anbieter wählen und fügt das Transkript am Cursor ein — die Kategorien überlappen also, die Abwägungen nicht.',
    'comparison.osDictation.section.inlineVsPaste.heading': 'Inline-Tippen vs. Einfügen am Cursor',
    'comparison.osDictation.section.inlineVsPaste.body': 'Das OS-Diktat tippt Zeichen in das fokussierte Feld, während du sprichst. WhisPaste macht es andersherum: Es nimmt das volle Audio auf, transkribiert es und fügt das fertige Transkript dann in einem Block am Cursor ein. Der OS-Ansatz fühlt sich eher wie eine Schreibmaschine an, der WhisPaste-Ansatz eher wie das Prüfen und Ablegen eines Absatzes. Keiner ist universell besser — lange, strukturierte Antworten profitieren tendenziell vom Einfügen-am-Ende-Modell.',
    'comparison.osDictation.section.providerChoice.heading': 'Ein Hersteller vs. Wahl mehrerer Anbieter',
    'comparison.osDictation.section.providerChoice.body': 'Das eingebaute OS-Diktat läuft auf dem Speech-to-Text-Stack des OS-Herstellers — du kannst die Engine oder die Cloud nicht austauschen. WhisPaste lässt dich wählen: lokal mit whisper.cpp als Standard, oder ein Cloud-Anbieter wie OpenAI, Deepgram oder Groq, wenn du maximale Geschwindigkeit willst. Im lokalen Fall verlässt das Audio den Rechner nicht; im Cloud-Fall geht das Audio direkt zum gewählten Anbieter mit deinem eigenen API-Key.',
    'comparison.osDictation.section.languageSupport.heading': 'Sprach-Abdeckung und Wechsel',
    'comparison.osDictation.section.languageSupport.body': 'Das OS-Diktat unterstützt einen festen Satz Sprachen pro OS-Version, und ein Wechsel bedeutet meist eine Änderung der Systemeingabequelle. WhisPaste deckt 99 von Whisper unterstützte Sprachen ab, kommt mit gemischtsprachiger Eingabe in derselben Aufnahme klar und wechselt Modell oder Anbieter per Setting-Schalter — kein OS-seitiges Tastatur-Layout-Geplänkel, kein Aus- und Einloggen.',
    'comparison.osDictation.faq.inAnyApp.q': 'Funktioniert das OS-Diktat nicht ohnehin schon in jeder App?',
    'comparison.osDictation.faq.inAnyApp.a': 'In den meisten Textfeldern ja, aber die Erfahrung ist uneinheitlich: Manche Apps akzeptieren die gestreamten Tastenanschläge sauber, andere weisen Auto-Großschreibung oder Interpunktion zurück, und das OS-Diktat lässt sich aus Kontexten, in denen das System-Overlay blockiert ist, gar nicht erst auslösen. WhisPaste umgeht das Streaming-Modell, indem es ein fertiges Transkript einfügt — das Einzige, was die Ziel-App können muss, ist Einfügen, und das beherrscht jedes Textfeld.',
    'comparison.osDictation.faq.whenSystemDictation.q': 'Wann sollte ich einfach beim System-Diktat bleiben?',
    'comparison.osDictation.faq.whenSystemDictation.a': 'Wenn du immer nur ein, zwei Sätze in einer einzigen vom OS unterstützten Sprache sprichst und es dir egal ist, welche Sprach-Engine das Audio verarbeitet, ist das System-Diktat in Ordnung und eine App weniger zu installieren. WhisPaste lohnt sich, wenn du Offline-Betrieb, mehrere Sprachen nacheinander, ein längeres Transkript zur Prüfung vor dem Einfügen oder einen anderen Anbieter als den OS-Hersteller willst.',
    'comparison.osDictation.faq.multiLanguage.q': 'Kommt WhisPaste besser mit mehreren Sprachen klar als das OS-Diktat?',
    'comparison.osDictation.faq.multiLanguage.a': 'Ja, in zwei Hinsichten. Erstens kann eine einzelne Whisper-Aufnahme Code-Switching enthalten (Englisch-Deutsch, Spanisch-Englisch usw.), und das Modell transkribiert es so, wie es gesprochen wurde — das OS-Diktat erzwingt meist eine einzige Eingabesprache pro Sitzung. Zweitens ist der Wechsel der Primärsprache in WhisPaste ein Setting-Schalter; im OS-Diktat hängt er an der Systemeingabequelle, was eigene UX-Kosten verursacht.',
    'comparison.osDictation.cta.label': 'WhisPaste holen — kostenlos und Open Source',
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
