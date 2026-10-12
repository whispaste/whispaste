/**
 * WhisPaste — Store Screenshot Configuration
 *
 * Defines store surfaces, screenshot story, and output destinations.
 */
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const GOLDENS = path.join(ROOT, 'website', 'public', 'screenshots');
const OUTPUT = path.join(__dirname, 'output');
const WEBSITE_SCREENSHOTS_ROOT = path.join(ROOT, 'website', 'public', 'screenshots');
const WEBSITE_STORE_SCREENSHOTS = path.join(WEBSITE_SCREENSHOTS_ROOT, 'store');
const WEBSITE_UI_SCREENSHOTS = path.join(WEBSITE_SCREENSHOTS_ROOT, 'ui');

/**
 * Store copy language → app-UI language whose golden screenshots are used.
 *
 * The app UI is localized only for en, de and ru (lib/core/l10n). Every other
 * store language shows the English UI inside its localized composite, which
 * is the honest choice: the UI itself is not translated there.
 */
const UI_LANG = {
  en: 'en',
  de: 'de',
  es: 'en',
  pt: 'en',
  it: 'en',
  ru: 'ru',
  zh: 'en',
};

/** Every language a composite is rendered for (`generate.cjs --lang=all`). */
const ALL_LANGS = Object.keys(UI_LANG);

/**
 * Languages whose composites are also copied into website/public/screenshots/.
 * The other languages only feed the store uploads (see submit-ms-store.ps1 and
 * fastlane/screenshots), so the website output stays en/de-only.
 */
const WEBSITE_LANGS = ['en', 'de'];

const STORE_SIZES = {
  microsoft: {
    width: 1920,
    height: 1080,
    label: 'Microsoft Store',
    orientation: 'landscape',
    // Goldens base path under website/public/screenshots/ (empty = root)
    goldenBase: '',
  },
  mac: {
    // Mac App Store: minimum 1280×800 (16:10), max 2560×1600.
    // 1440×900 matches the 13" MacBook Air/Pro display exactly.
    width: 1440,
    height: 900,
    label: 'Mac App Store',
    orientation: 'landscape',
    // Mac goldens live under macStoreScreenshots/ subdir
    goldenBase: 'mac/',
  },
  iphone_6_9: {
    width: 1320,
    height: 2868,
    label: 'Apple App Store 6.9"',
    orientation: 'portrait',
    enabled: false,
    goldenBase: '',
  },
  play_phone: {
    width: 1080,
    height: 1920,
    label: 'Google Play Phone',
    orientation: 'portrait',
    enabled: false,
    goldenBase: '',
  },
};

const ENABLED_STORES = ['microsoft', 'mac'];
const FUTURE_STORES = ['iphone_6_9', 'play_phone'];

const SCREENS = [
  {
    // Poster/hero screen: brand statement + app icon, no app window.
    // Rendered via the dedicated `.screen.hero` layout in template.html.
    id: 'hero',
    type: 'hero',
    headline: {
      en: 'Speak, and WhisPaste\ntypes into <em>any app</em>',
      de: 'Sprich, und WhisPaste\nschreibt in <em>jede App</em>',
      es: 'Habla, y WhisPaste\nescribe en <em>cualquier app</em>',
      pt: 'Fale, e o WhisPaste\ndigita em <em>qualquer app</em>',
      it: 'Parla, e WhisPaste\nscrive in <em>qualsiasi app</em>',
      ru: 'Говори — и WhisPaste\nпечатает в <em>любом приложении</em>',
      zh: '说出来，WhisPaste\n就能输入到<em>任何应用</em>',
    },
    subtitle: {
      en: 'Press your hotkey, talk, and the finished text lands right at your cursor.',
      de: 'Drück dein Kürzel, sprich, und der fertige Text landet direkt an deinem Cursor.',
      es: 'Pulsa tu atajo, habla, y el texto terminado aparece justo en tu cursor.',
      pt: 'Pressione seu atalho, fale, e o texto final aparece bem no seu cursor.',
      it: 'Premi la tua scorciatoia, parla, e il testo finito appare proprio sul tuo cursore.',
      ru: 'Нажми горячую клавишу, говори, и готовый текст появится прямо у курсора.',
      zh: '按下快捷键、开始说话，完成的文字就会直接出现在光标处。',
    },
    badges: {
      // Price/procurement-neutral only (maintainer rule, 2026-07-29): this
      // hero ships across distribution channels with DIFFERENT price models,
      // so no purchase/free/price wording may ever appear in these badges.
      en: ['Works offline', 'No account needed', 'Open source'],
      de: ['Funktioniert offline', 'Kein Konto nötig', 'Open Source'],
      es: ['Funciona sin conexión', 'Sin cuenta necesaria', 'Código abierto'],
      pt: ['Funciona offline', 'Sem necessidade de conta', 'Código aberto'],
      it: ['Funziona offline', 'Nessun account richiesto', 'Open source'],
      ru: ['Работает офлайн', 'Аккаунт не нужен', 'Открытый исходный код'],
      zh: ['可离线使用', '无需账户', '开源'],
    },
    theme: 'dark',
  },
  {
    id: 'workspace-overview',
    screenshot: {
      en: 'en/dark/01_workspace_overview.png',
      de: 'de/dark/01_workspace_overview.png',
      ru: 'ru/dark/01_workspace_overview.png',
    },
    composition: 'center',
    windowScale: 0.78,
    category: {
      en: 'WORKSPACE',
      de: 'WORKSPACE',
      es: 'ESPACIO DE TRABAJO',
      pt: 'ESPAÇO DE TRABALHO',
      it: 'AREA DI LAVORO',
      ru: 'ЗАПИСИ',
      zh: '工作区',
    },
    headline: {
      en: 'Keep every recording\nclose at hand',
      de: 'Halte jede Aufnahme\ngriffbereit',
      es: 'Mantén cada grabación\nal alcance de la mano',
      pt: 'Tenha cada gravação\nsempre por perto',
      it: 'Tieni ogni registrazione\na portata di mano',
      ru: 'Держи каждую запись\nпод рукой',
      zh: '让每段录音\n触手可及',
    },
    subtitle: {
      en: 'Search, tag, favorite, and archive what you said when the day gets busy.',
      de: 'Suche, tagge, favorisiere und archiviere deine Aufnahmen, wenn der Tag voller wird.',
      es: 'Busca, etiqueta, marca como favorito y archiva lo que dijiste cuando el día se llena.',
      pt: 'Pesquise, marque, favorite e arquive o que você falou quando o dia ficar corrido.',
      it: 'Cerca, tagga, aggiungi ai preferiti e archivia ciò che hai detto quando la giornata si complica.',
      ru: 'Ищи, помечай, добавляй в избранное и архивируй то, что наговорил, когда день становится загруженным.',
      zh: '在忙碌的日子里，搜索、标记、收藏并归档你说过的内容。',
    },
    theme: 'dark',
  },
  {
    id: 'workspace-detail',
    screenshot: {
      en: 'en/dark/02_workspace_detail.png',
      de: 'de/dark/02_workspace_detail.png',
      ru: 'ru/dark/02_workspace_detail.png',
    },
    composition: 'left',
    windowScale: 0.86,
    category: {
      en: 'DETAIL',
      de: 'DETAIL',
      es: 'DETALLE',
      pt: 'DETALHE',
      it: 'DETTAGLIO',
      ru: 'ДЕТАЛИ',
      zh: '详情',
    },
    headline: {
      en: 'Open one thought\nand finish it',
      de: 'Öffne einen Gedanken\nund bring ihn zu Ende',
      es: 'Abre un pensamiento\ny termínalo',
      pt: 'Abra um pensamento\ne conclua-o',
      it: 'Apri un pensiero\ne portalo a termine',
      ru: 'Открой мысль\nи доведи её до конца',
      zh: '打开一段想法\n把它完成',
    },
    subtitle: {
      en: 'Review one recording, clean it up, and keep the final text ready to paste.',
      de: 'Prüfe eine Aufnahme, bring sie in Form und halte den finalen Text direkt einsatzbereit.',
      es: 'Revisa una grabación, límpiala y deja el texto final listo para pegar.',
      pt: 'Revise uma gravação, ajuste-a e deixe o texto final pronto para colar.',
      it: 'Rivedi una registrazione, sistemala e tieni pronto il testo finale da incollare.',
      ru: 'Просмотри запись, приведи её в порядок и держи финальный текст готовым к вставке.',
      zh: '查看一段录音、整理润色，并让最终文本随时可以粘贴。',
    },
    theme: 'dark',
  },
  {
    id: 'voice-shortcuts',
    screenshot: {
      en: 'en/dark/03_voice_shortcuts.png',
      de: 'de/dark/03_voice_shortcuts.png',
      ru: 'ru/dark/03_voice_shortcuts.png',
    },
    composition: 'right',
    windowScale: 0.86,
    category: {
      en: 'VOICE SHORTCUTS',
      de: 'SPRACH-SHORTCUTS',
      es: 'ATAJOS DE VOZ',
      pt: 'ATALHOS DE VOZ',
      it: 'SCORCIATOIE VOCALI',
      ru: 'ГОЛОСОВЫЕ ЯРЛЫКИ',
      zh: '语音快捷短语',
    },
    headline: {
      en: 'Reuse the phrases\nyou type every day',
      de: 'Nutze die Phrasen wieder,\ndie du täglich brauchst',
      es: 'Reutiliza las frases\nque escribes a diario',
      pt: 'Reutilize as frases\nque você digita todo dia',
      it: 'Riusa le frasi\nche digiti ogni giorno',
      ru: 'Используй снова фразы,\nкоторые печатаешь каждый день',
      zh: '重复使用你每天\n都在输入的短语',
    },
    subtitle: {
      en: 'Say a trigger phrase and WhisPaste inserts the full text automatically.',
      de: 'Sag eine Auslösephrase, WhisPaste fügt den ganzen Text automatisch ein.',
      es: 'Di una frase de activación y WhisPaste inserta el texto completo automáticamente.',
      pt: 'Diga uma frase de gatilho e o WhisPaste insere o texto completo automaticamente.',
      it: 'Di\' una frase di attivazione e WhisPaste inserisce automaticamente il testo completo.',
      ru: 'Произнеси фразу-триггер, и WhisPaste автоматически вставит весь текст.',
      zh: '说出触发短语，WhisPaste 会自动插入完整文本。',
    },
    theme: 'dark',
  },
  {
    id: 'hotkey-settings',
    screenshot: {
      en: 'en/dark/04_settings.png',
      de: 'de/dark/04_settings.png',
      ru: 'ru/dark/04_settings.png',
    },
    composition: 'left',
    windowScale: 0.9,
    category: {
      en: 'SETUP',
      de: 'EINRICHTUNG',
      es: 'CONFIGURACIÓN',
      pt: 'CONFIGURAÇÃO',
      it: 'CONFIGURAZIONE',
      ru: 'НАСТРОЙКА',
      zh: '设置',
    },
    headline: {
      en: 'Choose a shortcut\nthat fits your flow',
      de: 'Wähle ein Kürzel,\ndas zu deinem Ablauf passt',
      es: 'Elige un atajo\nque encaje con tu flujo',
      pt: 'Escolha um atalho\nque combine com o seu fluxo',
      it: 'Scegli una scorciatoia\nadatta al tuo flusso',
      ru: 'Выбери сочетание клавиш,\nподходящее твоему процессу',
      zh: '选择适合你工作流程\n的快捷键',
    },
    subtitle: {
      en: 'Keep recording one key combo away and turn it off whenever you do not need it.',
      de: 'Halte die Aufnahme nur eine Tastenkombination entfernt und schalte sie ab, wenn du sie nicht brauchst.',
      es: 'Ten la grabación a una combinación de teclas de distancia y desactívala cuando no la necesites.',
      pt: 'Deixe a gravação a uma combinação de teclas de distância e desligue-a quando não precisar.',
      it: 'Tieni la registrazione a una combinazione di tasti di distanza e disattivala quando non serve.',
      ru: 'Запись всегда в одном сочетании клавиш, а когда она не нужна, её можно выключить.',
      zh: '让录音只需一组按键即可开始，不需要时随时可以关闭。',
    },
    theme: 'dark',
  },
  {
    id: 'time-saved',
    screenshot: {
      en: 'en/dark/05_analytics.png',
      de: 'de/dark/05_analytics.png',
      ru: 'ru/dark/05_analytics.png',
    },
    composition: 'center',
    windowScale: 0.86,
    category: {
      en: 'INSIGHTS',
      de: 'EINBLICKE',
      es: 'ESTADÍSTICAS',
      pt: 'ESTATÍSTICAS',
      it: 'STATISTICHE',
      ru: 'СТАТИСТИКА',
      zh: '数据洞察',
    },
    headline: {
      en: 'See how much time\nvoice gives back',
      de: 'Sieh, wie viel Zeit\ndir Stimme zurückgibt',
      es: 'Mira cuánto tiempo\nte devuelve la voz',
      pt: 'Veja quanto tempo\na voz devolve para você',
      it: 'Scopri quanto tempo\nti restituisce la voce',
      ru: 'Посмотри, сколько времени\nвозвращает голос',
      zh: '看看语音为你\n节省了多少时间',
    },
    subtitle: {
      en: 'Track usage, activity, and the minutes you save when speaking replaces typing.',
      de: 'Behalte Nutzung, Aktivität und die Minuten im Blick, die Sprache statt Tippen spart.',
      es: 'Sigue el uso, la actividad y los minutos que ahorras cuando hablar sustituye a escribir.',
      pt: 'Acompanhe o uso, a atividade e os minutos economizados quando falar substitui digitar.',
      it: 'Tieni d\'occhio utilizzo, attività e i minuti che risparmi quando parlare sostituisce scrivere.',
      ru: 'Следи за использованием, активностью и минутами, которые экономишь, когда речь заменяет набор текста.',
      zh: '跟踪使用情况、活动，以及用语音代替打字所节省的时间。',
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
  ENABLED_STORES,
  FUTURE_STORES,
  SCREENS,
  DESIGN,
  ASSET_PATHS,
  UI_LANG,
  ALL_LANGS,
  WEBSITE_LANGS,
  ROOT,
  OUTPUT,
  GOLDENS,
  WEBSITE_SCREENSHOTS_ROOT,
  WEBSITE_STORE_SCREENSHOTS,
  WEBSITE_UI_SCREENSHOTS,
};
