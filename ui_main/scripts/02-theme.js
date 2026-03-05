/* ── Theme Management ──────────────────────────────────── */
let _currentTheme = 'system';

function resolveTheme(theme) {
  if (theme === 'system') {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return theme;
}

function applyTheme(theme) {
  _currentTheme = theme;
  const eff = resolveTheme(theme);
  if (eff === 'dark') {
    document.documentElement.setAttribute('data-theme', 'dark');
  } else {
    document.documentElement.removeAttribute('data-theme');
  }
  // Update theme toggle icon in sidebar
  const iconEl = document.getElementById('themeIcon');
  if (iconEl) {
    if (eff === 'dark') {
      iconEl.innerHTML = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>';
    } else {
      iconEl.innerHTML = '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>';
    }
  }
  // Update brand icon for theme
  const brandIcon = document.getElementById('brandIcon');
  if (brandIcon) {
    brandIcon.src = eff === 'dark'
      ? brandIcon.dataset.darkSrc
      : brandIcon.dataset.lightSrc;
  }
  // Update about page logo for theme
  const aboutLogo = document.getElementById('aboutLogo');
  if (aboutLogo) {
    aboutLogo.src = eff === 'dark'
      ? aboutLogo.dataset.darkSrc
      : aboutLogo.dataset.lightSrc;
  }
}

/** Cycle theme: system → dark → light → system */
function toggleTheme() {
  if (_currentTheme === 'system') _currentTheme = 'dark';
  else if (_currentTheme === 'dark') _currentTheme = 'light';
  else _currentTheme = 'system';
  applyTheme(_currentTheme);
  try { if (window.setTheme) window.setTheme(_currentTheme); } catch (e) {}
}

/** Listen for OS theme changes (affects system mode) */
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (_currentTheme === 'system') applyTheme('system');
});

/* ── Language Toggle ──────────────────────────────────── */
let _currentUILang = 'en';

function updateLangLabel() {
  const el = document.getElementById('langLabel');
  if (el) el.textContent = _currentUILang.toUpperCase();
}

async function toggleLang() {
  _currentUILang = _currentUILang === 'en' ? 'de' : 'en';
  updateLangLabel();
  setLang(_currentUILang);
  try {
    if (window.setUILanguage) await window.setUILanguage(_currentUILang);
  } catch (e) {}
  // Reload translations from Go (these may include server-side l10n keys)
  try {
    if (window.getTranslations) {
      const trJson = await window.getTranslations();
      const serverTr = JSON.parse(trJson);
      // Merge server translations into our local translations
      Object.assign(translations[_currentUILang] || {}, serverTr);
    }
  } catch (e) {}
  applyTranslations();
  // Re-render history if on that page
  if (typeof renderHistory === 'function') renderHistory();
  // Update mode badge text for new language
  if (typeof updateModeBadge === 'function') {
    const isLocal = window._activeModelLocal;
    updateModeBadge({ active_model_local: !!isLocal });
  }
}
