export const i18n: Record<string, Record<string, string>> = {
  en: {
    'hero.title1': 'Voice to text,',
    'hero.title2': 'pasted anywhere.',
    'hero.desc': 'A lightweight desktop tool that transcribes your speech — locally or via OpenAI Whisper — and pastes the result into any focused input field.',
    'hero.download': 'Download from GitHub',
    'hero.github': 'View on GitHub',
    'hero.meta': 'Portable .exe · No installer · ~8 MB · Early alpha — expect rough edges',
    'hero.portable': 'Or download portable .exe',
    'nav.features': 'Features',
    'nav.howitworks': 'How It Works',
    'features.label': 'Features',
    'features.title': 'Everything you need',
    'features.desc': 'Powerful features in a lightweight package. No bloat, no subscriptions — works offline or with your API key.',
    'howitworks.label': 'Workflow',
    'howitworks.title': 'How it works',
    'howitworks.desc': 'Three steps. Zero friction.',
    'privacy.label': 'Security',
    'privacy.title': 'Privacy first',
    'privacy.desc': 'Your data stays yours. Always.',
    'support.title': 'Support the project',
    'support.desc': 'WhisPaste is free and open source. If you find it useful, consider supporting development.',
    'support.sponsor': 'Sponsor on GitHub',
    'support.coffee': 'Buy a Coffee',
    'footer.impressum': 'Legal Notice',
    'footer.privacy': 'Privacy Policy',
    'footer.license': 'MIT License',
    'carousel.press_hotkey': 'Press your hotkey',
    'carousel.recording': 'Recording',
    'carousel.speak_now': 'Speak now',
    'carousel.editor_title': 'Text Editor',
    'carousel.auto_pasted': 'Auto-pasted!',
    'preview.label': 'App Preview',
    'preview.title': 'Designed to get out of your way',
    'preview.desc': 'A clean, modern interface that keeps everything organized — search, filter, and manage all your transcriptions in one place.'
  },
  de: {
    'hero.title1': 'Voice to Text,',
    'hero.title2': 'Paste anywhere.',
    'hero.desc': 'Ein schlankes Desktop-Tool — transkribiert Sprache lokal oder via OpenAI Whisper und fügt das Ergebnis direkt in jedes Eingabefeld ein.',
    'hero.download': 'Von GitHub herunterladen',
    'hero.github': 'Auf GitHub ansehen',
    'hero.meta': 'Portable .exe · Kein Installer · ~8 MB · Frühe Alpha – kann noch Ecken und Kanten haben',
    'hero.portable': 'Oder portable .exe herunterladen',
    'nav.features': 'Features',
    'nav.howitworks': 'So funktioniert\'s',
    'features.label': 'Features',
    'features.title': 'Alles, was du brauchst',
    'features.desc': 'Leistungsstarke Funktionen in einem schlanken Paket. Kein Ballast, kein Abo — funktioniert offline oder mit deinem API-Schlüssel.',
    'howitworks.label': 'Workflow',
    'howitworks.title': 'So funktioniert\'s',
    'howitworks.desc': 'Drei Schritte. Null Aufwand.',
    'privacy.label': 'Sicherheit',
    'privacy.title': 'Privatsphäre zuerst',
    'privacy.desc': 'Deine Daten bleiben bei dir. Immer.',
    'support.title': 'Projekt unterstützen',
    'support.desc': 'WhisPaste ist kostenlos und Open Source. Wenn es dir nützlich ist, unterstütze gerne die Entwicklung.',
    'support.sponsor': 'Auf GitHub sponsern',
    'support.coffee': 'Einen Kaffee ausgeben',
    'footer.impressum': 'Impressum',
    'footer.privacy': 'Datenschutz',
    'footer.license': 'MIT-Lizenz',
    'carousel.press_hotkey': 'Drücke deinen Hotkey',
    'carousel.recording': 'Aufnahme',
    'carousel.speak_now': 'Sprich jetzt',
    'carousel.editor_title': 'Texteditor',
    'carousel.auto_pasted': 'Automatisch eingefügt!',
    'preview.label': 'App-Vorschau',
    'preview.title': 'Entwickelt, um nicht im Weg zu sein',
    'preview.desc': 'Eine moderne Oberfläche, die alles übersichtlich hält — suche, filtere und verwalte all deine Transkriptionen an einem Ort.'
  }
};

export let currentLang: string = localStorage.getItem('whispaste-lang') || 'en';

export function toggleLang() {
  currentLang = currentLang === 'en' ? 'de' : 'en';
  localStorage.setItem('whispaste-lang', currentLang);
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
