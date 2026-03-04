/* ── Page Switching ────────────────────────────────────── */
function switchPage(pageId) {
  // Update nav
  document.querySelectorAll('.nav-item').forEach(item => {
    item.classList.toggle('active', item.dataset.page === pageId);
  });
  // Show/hide pages
  document.querySelectorAll('.page').forEach(page => {
    page.style.display = page.id === 'page-' + pageId ? '' : 'none';
  });
  // Load history entries when switching to history page
  if (pageId === 'history') loadEntries();
}

/* ── Init ──────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', async () => {
  // Apply initial theme from Go injection
  const theme = window._theme || 'system';
  applyTheme(theme);

  // Set initial language
  const lang = window._lang || 'en';
  _currentUILang = lang;
  setLang(lang);
  updateLangLabel();

  // Load translations from Go (merges server-side l10n keys)
  try {
    if (window.getTranslations) {
      const trJson = await window.getTranslations();
      const serverTr = JSON.parse(trJson);
      Object.assign(translations[_currentUILang] || {}, serverTr);
      applyTranslations();
    }
  } catch (e) {}

  // Load config into settings form
  try {
    if (window.getConfig) {
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      applyConfig(cfg);
    }
  } catch (e) {
    console.warn('Failed to load config:', e);
  }

  // --- Settings page wiring ---
  // Volume slider live update
  const volSlider = document.getElementById('volume-slider');
  const volValue = document.getElementById('volume-value');
  if (volSlider && volValue) {
    volSlider.addEventListener('input', () => { volValue.textContent = volSlider.value + '%'; });
  }
  // Volume row visibility
  const soundToggle = document.getElementById('toggle-sound');
  const volRow = document.getElementById('volume-row');
  if (soundToggle && volRow) {
    const updateVolRow = () => { volRow.style.display = soundToggle.checked ? 'flex' : 'none'; };
    soundToggle.addEventListener('change', updateVolRow);
    updateVolRow();
  }
  // Max duration slider live update
  const durSlider = document.getElementById('range-max-duration');
  const durValue = document.getElementById('max-duration-value');
  const durCheck = document.getElementById('check-unlimited-duration');
  if (durSlider && durValue) {
    durSlider.addEventListener('input', () => {
      if (!durCheck?.checked) durValue.textContent = durSlider.value + 's';
    });
  }

  // --- History page wiring ---
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.addEventListener('input', (ev) => {
      _searchQuery = ev.target.value;
      renderHistory();
    });
  }
  // Sort select
  const sortSelect = document.getElementById('sortSelect');
  if (sortSelect) {
    sortSelect.addEventListener('change', () => changeSort(sortSelect.value));
  }
  // Filter items
  document.querySelectorAll('.filter-item[data-filter]').forEach(el => {
    el.addEventListener('click', () => setFilter(el.dataset.filter));
  });
  // Confirm dialog buttons
  const confirmCancel = document.getElementById('confirmCancel');
  const confirmDelete = document.getElementById('confirmDelete');
  if (confirmCancel) confirmCancel.addEventListener('click', cancelDelete);
  if (confirmDelete) confirmDelete.addEventListener('click', doDelete);

  // --- Navigation ---
  document.querySelectorAll('.nav-item[data-page]').forEach(item => {
    item.addEventListener('click', () => switchPage(item.dataset.page));
  });

  // --- Keyboard shortcuts ---
  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') {
      const overlay = document.getElementById('confirmOverlay');
      if (overlay && overlay.classList.contains('show')) {
        cancelDelete();
      } else if (_expandedId) {
        _expandedId = null;
        renderHistory();
      }
    }
    if ((ev.ctrlKey || ev.metaKey) && ev.key === 'f') {
      ev.preventDefault();
      const search = document.getElementById('searchInput');
      if (search) search.focus();
    }
  });

  // --- Start on correct page ---
  const initialPage = window._initialPage || 'history';
  switchPage(initialPage);

  // Handle smart-mode deep link
  if (window._initialSection === 'smart-mode') {
    switchPage('settings');
    setTimeout(() => {
      const smartSection = document.querySelector('[data-section="smart-mode"]');
      if (smartSection) smartSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 200);
  }

  // Reveal UI and signal Go
  document.body.classList.add('ready');
  if (window.windowReady) window.windowReady();
});
