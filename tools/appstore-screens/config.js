/**
 * WhisPaste — Store Screenshot Configuration
 *
 * Defines store surfaces, screenshot story, and output destinations.
 */
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const GOLDENS = path.join(ROOT, 'test', 'screenshots', 'goldens', 'windowsStoreScreenshots');
const OUTPUT = path.join(__dirname, 'output');
const WEBSITE_SCREENSHOTS_ROOT = path.join(ROOT, 'website', 'public', 'screenshots');
const WEBSITE_STORE_SCREENSHOTS = path.join(WEBSITE_SCREENSHOTS_ROOT, 'store');
const WEBSITE_UI_SCREENSHOTS = path.join(WEBSITE_SCREENSHOTS_ROOT, 'ui');

const STORE_SIZES = {
  microsoft: {
    width: 1920,
    height: 1080,
    label: 'Microsoft Store',
    orientation: 'landscape',
  },
  iphone_6_9: {
    width: 1320,
    height: 2868,
    label: 'Apple App Store 6.9"',
    orientation: 'portrait',
    enabled: false,
  },
  play_phone: {
    width: 1080,
    height: 1920,
    label: 'Google Play Phone',
    orientation: 'portrait',
    enabled: false,
  },
};

const PRIMARY_STORE = 'microsoft';
const FUTURE_STORES = ['iphone_6_9', 'play_phone'];

const SCREENS = [
  {
    id: 'workspace-overview',
    screenshot: {
      en: '01_workspace_overview_dark_en.png',
      de: '01_workspace_overview_dark_de.png',
    },
    category: { en: 'WORKSPACE', de: 'WORKSPACE' },
    headline: {
      en: 'Keep every dictation\nclose at hand',
      de: 'Halte jedes Diktat\ngriffbereit',
    },
    subtitle: {
      en: 'Search, tag, favorite, and archive what you said when the day gets busy.',
      de: 'Suche, tagge, favorisiere und archiviere deine Diktate, wenn der Tag voller wird.',
    },
    theme: 'dark',
  },
  {
    id: 'workspace-detail',
    screenshot: {
      en: '02_workspace_detail_light_en.png',
      de: '02_workspace_detail_light_de.png',
    },
    category: { en: 'DETAIL', de: 'DETAIL' },
    headline: {
      en: 'Open one thought\nand finish it',
      de: 'Öffne einen Gedanken\nund bring ihn zu Ende',
    },
    subtitle: {
      en: 'Review one dictation, clean it up, and keep the final text ready to paste.',
      de: 'Prüfe ein Diktat, bring es in Form und halte den finalen Text direkt einsatzbereit.',
    },
    theme: 'light',
  },
  {
    id: 'voice-shortcuts',
    screenshot: {
      en: '03_voice_shortcuts_dark_en.png',
      de: '03_voice_shortcuts_dark_de.png',
    },
    category: { en: 'VOICE SHORTCUTS', de: 'SPRACHKÜRZEL' },
    headline: {
      en: 'Reuse the phrases\nyou type every day',
      de: 'Nutze die Phrasen\nwieder, die du täglich brauchst',
    },
    subtitle: {
      en: 'Say a trigger phrase and insert the full text automatically while dictating.',
      de: 'Sag eine Auslösephrase und füge den ganzen Text beim Diktieren automatisch ein.',
    },
    theme: 'dark',
  },
  {
    id: 'hotkey-settings',
    screenshot: {
      en: '04_hotkey_settings_light_en.png',
      de: '04_hotkey_settings_light_de.png',
    },
    category: { en: 'SETUP', de: 'EINRICHTUNG' },
    headline: {
      en: 'Choose a shortcut\nthat fits your flow',
      de: 'Wähle ein Kürzel,\ndas zu deinem Ablauf passt',
    },
    subtitle: {
      en: 'Keep recording one key combo away and turn it off whenever you do not need it.',
      de: 'Halte die Aufnahme nur eine Tastenkombination entfernt und schalte sie ab, wenn du sie nicht brauchst.',
    },
    theme: 'light',
  },
  {
    id: 'time-saved',
    screenshot: {
      en: '05_time_saved_dark_en.png',
      de: '05_time_saved_dark_de.png',
    },
    category: { en: 'INSIGHTS', de: 'EINBLICKE' },
    headline: {
      en: 'See how much time\nvoice gives back',
      de: 'Sieh, wie viel Zeit\ndir Stimme zurückgibt',
    },
    subtitle: {
      en: 'Track usage, activity, and the minutes you save when speaking replaces typing.',
      de: 'Behalte Nutzung, Aktivität und die Minuten im Blick, die Sprache statt Tippen spart.',
    },
    theme: 'dark',
  },
];

const DESIGN = {
  colors: {
    bgDark: '#0f1219',
    bgDarkAccent: '#111827',
    accent: '#38D9F0',
    accentSecondary: '#0891B2',
    textPrimary: '#f0f4f8',
    textMuted: 'rgba(240, 244, 248, 0.58)',
    textMutedLight: 'rgba(17, 24, 39, 0.62)',
    categoryColor: '#38D9F0',
  },
  fonts: {
    family: "'Inter', system-ui, sans-serif",
    importUrl:
      'https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800;900&display=swap',
  },
  window: {
    cornerRadius: 16,
    shadowBlur: 72,
    shadowColor: 'rgba(0, 0, 0, 0.42)',
    titleBarHeight: 34,
    titleBarBg: '#1a1f2e',
    titleBarBgLight: '#e9edf5',
    titleBarDots: ['#ff5f57', '#febc2e', '#28c840'],
  },
};

const ASSET_PATHS = {
  goldens: GOLDENS,
  logo: path.join(ROOT, 'website', 'public', 'app-icon.png'),
};

module.exports = {
  STORE_SIZES,
  PRIMARY_STORE,
  FUTURE_STORES,
  SCREENS,
  DESIGN,
  ASSET_PATHS,
  ROOT,
  OUTPUT,
  GOLDENS,
  WEBSITE_SCREENSHOTS_ROOT,
  WEBSITE_STORE_SCREENSHOTS,
  WEBSITE_UI_SCREENSHOTS,
};
