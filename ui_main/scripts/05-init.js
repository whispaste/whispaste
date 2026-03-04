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
  // Load analytics when switching to analytics page
  if (pageId === 'analytics') { loadAnalytics(); startAnalyticsAutoRefresh(); } else { stopAnalyticsAutoRefresh(); }
  // Auto-select first settings nav item when switching to settings
  if (pageId === 'settings') {
    const firstNav = document.querySelector('.filter-item[data-settings-section]');
    if (firstNav) {
      document.querySelectorAll('.filter-item[data-settings-section]').forEach(i => i.classList.remove('active'));
      firstNav.classList.add('active');
      const sectionId = firstNav.dataset.settingsSection;
      const target = document.getElementById(sectionId);
      if (target) target.scrollIntoView({ block: 'start' });
    }
  }
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
      updateModeBadge(cfg);
      updateStatusBar(cfg);
      loadAudioDevices();
    }
  } catch (e) {
    console.warn('Failed to load config:', e);
  }
  _configLoaded = true;

  // --- Settings page wiring ---
  // Settings nav — scroll to section on click
  document.querySelectorAll('.filter-item[data-settings-section]').forEach(item => {
    item.addEventListener('click', () => {
      const sectionId = item.dataset.settingsSection;
      const target = document.getElementById(sectionId);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      document.querySelectorAll('.filter-item[data-settings-section]').forEach(i => i.classList.remove('active'));
      item.classList.add('active');
    });
  });
  // Auto-save on change/input events in settings scroll area
  const settingsScroll = document.querySelector('.settings-scroll');
  if (settingsScroll) {
    settingsScroll.addEventListener('change', (e) => {
      if (e.target.closest('.hotkey-recorder')) return; // skip hotkey recorder
      autoSave();
    });
    settingsScroll.addEventListener('input', (e) => {
      if (e.target.matches('input[type="text"], input[type="password"], textarea')) autoSave();
    });
  }
  // Scroll-based nav highlighting
  const settingsScrollEl = document.querySelector('.settings-scroll');
  if (settingsScrollEl) {
    const sectionHeaders = settingsScrollEl.querySelectorAll('.settings-section-header');
    settingsScrollEl.addEventListener('scroll', () => {
      let activeId = null;
      sectionHeaders.forEach(header => {
        if (header.getBoundingClientRect().top <= 120) activeId = header.id;
      });
      if (activeId) {
        document.querySelectorAll('.filter-item[data-settings-section]').forEach(i => {
          i.classList.toggle('active', i.dataset.settingsSection === activeId);
        });
      }
    });
  }
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
  // Close-to-tray → toggle notify-background dependency
  const closeToTrayToggle = document.getElementById('toggle-close-to-tray');
  if (closeToTrayToggle) {
    closeToTrayToggle.addEventListener('change', updateCloseToTrayDependents);
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
  // Sort dropdown
  initSortDropdown();
  // Filter items
  document.querySelectorAll('.filter-item[data-filter]').forEach(el => {
    el.addEventListener('click', () => setFilter(el.dataset.filter));
  });
  document.getElementById('dateFrom')?.addEventListener('change', renderHistory);
  document.getElementById('dateTo')?.addEventListener('change', renderHistory);
  // Confirm dialog buttons
  const confirmCancelBtn = document.getElementById('confirmCancel');
  const confirmDeleteBtn = document.getElementById('confirmDelete');
  if (confirmCancelBtn) confirmCancelBtn.addEventListener('click', cancelDelete);
  if (confirmDeleteBtn) confirmDeleteBtn.addEventListener('click', doDelete);
  // Selection bar buttons
  const selClose = document.getElementById('selectionClose');
  const delSelected = document.getElementById('deleteSelectedBtn');
  if (selClose) selClose.addEventListener('click', clearSelection);
  if (delSelected) delSelected.addEventListener('click', confirmDeleteSelected);

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
      } else if (_selectedIds.size > 0) {
        clearSelection();
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
    switchPage('smartmode');
  }

  // Auto-save for Smart Mode page
  const smartContent = document.querySelector('.smartmode-content');
  if (smartContent) {
    smartContent.addEventListener('change', () => autoSave());
    smartContent.addEventListener('input', (e) => {
      if (e.target.matches('textarea')) autoSave();
    });
  }

  // Reveal UI and signal Go
  document.body.classList.add('ready');
  if (window.windowReady) window.windowReady();

  // Auto-refresh history when window regains focus (e.g. after recording)
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && document.getElementById('page-history')?.style.display !== 'none') {
      loadEntries();
    }
  });
});
