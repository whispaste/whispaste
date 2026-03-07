/* ── FAB Recording State Sync ──────────────────────────── */
const _fabMicIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/></svg>';
const _fabStopIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>';

function onRecordingStateChanged(state) {
  const fab = document.getElementById('captureBtn');
  if (!fab) return;
  const isActive = (state === 'recording' || state === 'paused');
  fab.classList.toggle('recording', isActive);
  fab.innerHTML = isActive ? _fabStopIcon : _fabMicIcon;
  fab.title = isActive ? t('fab.stop') : t('fab.record');
}

/* ── System Info (About page) ──────────────────────────── */
let _sysInfoCache = null;

async function loadSystemInfo() {
  const grid = document.getElementById('sysinfo-grid');
  if (!grid || !window.getSystemInfo) return;

  if (!_sysInfoCache) {
    try {
      const raw = await window.getSystemInfo();
      _sysInfoCache = JSON.parse(raw);
    } catch (e) { return; }
  }
  const info = _sysInfoCache;

  const rows = [
    { key: 'sysAppVersion', value: info.appVersion },
  ];
  if (info.buildCommit) rows.push({ key: 'sysBuildCommit', value: info.buildCommit.substring(0, 8) });
  if (info.buildBranch) rows.push({ key: 'sysBuildBranch', value: info.buildBranch });
  if (info.buildDate) rows.push({ key: 'sysBuildDate', value: info.buildDate });
  rows.push(
    { key: 'sysGoVersion', value: info.goVersion },
    { key: 'sysOS', value: info.os },
    { key: 'sysArch', value: info.arch },
    { key: 'sysConfigPath', value: info.configPath, isPath: true },
    { key: 'sysLogPath', value: info.logPath, isPath: true },
  );

  grid.innerHTML = rows.map(r => {
    const cls = r.isPath ? ' sysinfo-path' : '';
    const onclick = r.isPath ? ` onclick="copySysInfoValue(this)"` : '';
    return `<span class="sysinfo-label">${t(r.key)}</span><span class="sysinfo-value${cls}"${onclick}>${esc(r.value || '—')}</span>`;
  }).join('');

  // Copy button
  const btn = document.getElementById('sysinfoCopyBtn');
  if (btn) {
    btn.onclick = () => {
      const lines = rows.map(r => `${t(r.key)}: ${r.value || '—'}`);
      lines.unshift('WhisPaste Debug Info');
      lines.push(`User-Agent: ${navigator.userAgent}`);
      navigator.clipboard.writeText(lines.join('\n')).then(() => {
        showToast(t('aboutCopied'));
      });
    };
  }
}

function copySysInfoValue(el) {
  navigator.clipboard.writeText(el.textContent).then(() => {
    showToast(t('aboutCopied'));
  });
}

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
  // Load system info when switching to about page
  if (pageId === 'about') loadSystemInfo();
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
      // Hide in-app FAB when floating desktop button is active (avoids duplicate)
      const fab = document.getElementById('captureBtn');
      if (fab) fab.style.display = cfg.floating_button_enabled ? 'none' : '';
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
  // Cleanup toggle → enable/disable cleanup button
  const cleanupToggle = document.getElementById('toggle-cleanup');
  if (cleanupToggle) {
    cleanupToggle.addEventListener('change', updateCleanupDependents);
  }
  const cleanupBtn = document.getElementById('btn-cleanup-now');
  if (cleanupBtn) {
    cleanupBtn.addEventListener('click', doManualCleanup);
  }
  // Max duration slider live update (handled by oninput="updateDurationLabel()" in HTML)

  // --- History page wiring ---
  const searchInput = document.getElementById('searchInput');
  const searchClear = document.getElementById('searchClear');
  if (searchInput) {
    searchInput.addEventListener('input', (ev) => {
      _searchQuery = ev.target.value;
      if (searchClear) searchClear.style.display = searchInput.value ? '' : 'none';
      renderHistory();
    });
  }
  if (searchInput && searchClear) {
    searchClear.addEventListener('click', () => {
      searchInput.value = '';
      _searchQuery = '';
      searchClear.style.display = 'none';
      renderHistory();
    });
  }
  const helpBtn = document.getElementById('searchHelp');
  if (helpBtn) {
    helpBtn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      toggleSearchHelp(helpBtn);
    });
  }
  // Sort dropdown
  initSortDropdown();
  // Project selector
  initProjectSelector();
  // Sidebar resize
  initSidebarResize();
  // Filter items
  document.querySelectorAll('.filter-item[data-filter]').forEach(el => {
    el.addEventListener('click', () => setFilter(el.dataset.filter));
  });
  // Clear filters button
  const clearFiltersBtn = document.getElementById('clearFiltersBtn');
  if (clearFiltersBtn) clearFiltersBtn.addEventListener('click', clearAllFilters);
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

  // Show onboarding wizard on first run
  if (window._showOnboarding) {
    showOnboarding();
  }

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
