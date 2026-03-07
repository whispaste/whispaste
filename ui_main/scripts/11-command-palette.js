/* ── Command Palette (Ctrl+K) ──────────────────────────── */

(function () {
  let _paletteEl = null;
  let _activeIndex = 0;
  let _filteredCmds = [];

  const paletteIcons = {
    command: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"/></svg>',
    toggleRight: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="12" x="2" y="6" rx="6"/><circle cx="16" cy="12" r="2"/></svg>',
    micOff: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="2" x2="22" y1="2" y2="22"/><path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"/><path d="M5 10v2a7 7 0 0 0 12 5"/><path d="M15 9.34V5a3 3 0 0 0-5.68-1.33"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12"/><line x1="12" x2="12" y1="19" y2="22"/></svg>',
    settings: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>',
    barChart: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/></svg>',
    clock: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>',
    info: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
    fileTxt: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 13H8"/><path d="M16 17H8"/><path d="M16 13h-2"/></svg>',
    hash: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/></svg>',
    braces: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/><path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/></svg>',
  };

  function buildCommands() {
    return [
      // Smart Mode
      { id: 'smart-toggle',      label: t('palette.cmd.smartToggle'),      icon: paletteIcons.toggleRight, category: 'palette.cat.smartMode', action: smartToggleAction },
      { id: 'preset-cleanup',    label: t('palette.cmd.presetCleanup'),    icon: icons.sparkles,           category: 'palette.cat.smartMode', action: () => setPreset('cleanup') },
      { id: 'preset-concise',    label: t('palette.cmd.presetConcise'),    icon: icons.minimize,           category: 'palette.cat.smartMode', action: () => setPreset('concise') },
      { id: 'preset-email',      label: t('palette.cmd.presetEmail'),      icon: icons.mail,               category: 'palette.cat.smartMode', action: () => setPreset('email') },
      { id: 'preset-formal',     label: t('palette.cmd.presetFormal'),     icon: icons.fileText,           category: 'palette.cat.smartMode', action: () => setPreset('formal') },
      { id: 'preset-bullets',    label: t('palette.cmd.presetBullets'),    icon: icons.list,               category: 'palette.cat.smartMode', action: () => setPreset('bullets') },
      { id: 'preset-summary',    label: t('palette.cmd.presetSummary'),    icon: icons.fileText,           category: 'palette.cat.smartMode', action: () => setPreset('summary') },
      { id: 'preset-notes',      label: t('palette.cmd.presetNotes'),      icon: icons.clipboard,          category: 'palette.cat.smartMode', action: () => setPreset('notes') },
      { id: 'preset-meeting',    label: t('palette.cmd.presetMeeting'),    icon: icons.users,              category: 'palette.cat.smartMode', action: () => setPreset('meeting') },
      { id: 'preset-social',     label: t('palette.cmd.presetSocial'),     icon: icons.share,              category: 'palette.cat.smartMode', action: () => setPreset('social') },
      { id: 'preset-technical',  label: t('palette.cmd.presetTechnical'),  icon: icons.code,               category: 'palette.cat.smartMode', action: () => setPreset('technical') },
      { id: 'preset-casual',     label: t('palette.cmd.presetCasual'),     icon: icons.messageCircle,      category: 'palette.cat.smartMode', action: () => setPreset('casual') },
      { id: 'preset-translate',  label: t('palette.cmd.presetTranslate'),  icon: icons.globe,              category: 'palette.cat.smartMode', action: () => setPreset('translate') },

      // Recording Mode
      { id: 'mode-ptt',    label: t('palette.cmd.modePTT'),    icon: icons.microphone,    category: 'palette.cat.recording', action: () => switchRecordMode('push_to_talk') },
      { id: 'mode-toggle', label: t('palette.cmd.modeToggle'), icon: paletteIcons.micOff,  category: 'palette.cat.recording', action: () => switchRecordMode('toggle') },

      // Export
      { id: 'export-txt',  label: t('palette.cmd.exportTXT'),  icon: paletteIcons.fileTxt, category: 'palette.cat.export', action: () => exportSelected('txt') },
      { id: 'export-md',   label: t('palette.cmd.exportMD'),   icon: paletteIcons.hash,    category: 'palette.cat.export', action: () => exportSelected('md') },
      { id: 'export-csv',  label: t('palette.cmd.exportCSV'),  icon: paletteIcons.fileTxt, category: 'palette.cat.export', action: () => exportSelected('csv') },
      { id: 'export-json', label: t('palette.cmd.exportJSON'), icon: paletteIcons.braces,  category: 'palette.cat.export', action: () => exportSelected('json') },

      // Navigation
      { id: 'nav-history',      label: t('palette.cmd.navHistory'),      icon: paletteIcons.clock,    category: 'palette.cat.navigation', action: () => switchPage('history') },
      { id: 'nav-analytics',    label: t('palette.cmd.navAnalytics'),    icon: paletteIcons.barChart, category: 'palette.cat.navigation', action: () => switchPage('analytics') },
      { id: 'nav-settings',     label: t('palette.cmd.navSettings'),     icon: paletteIcons.settings, category: 'palette.cat.navigation', action: () => switchPage('settings') },
      { id: 'nav-smartmode',    label: t('palette.cmd.navSmartMode'),    icon: icons.sparkles,        category: 'palette.cat.navigation', action: () => switchPage('smartmode') },
      { id: 'nav-replacements', label: t('palette.cmd.navReplacements'), icon: icons.replace,         category: 'palette.cat.navigation', action: () => switchPage('replacements') },
      { id: 'nav-about',        label: t('palette.cmd.navAbout'),        icon: paletteIcons.info,     category: 'palette.cat.navigation', action: () => switchPage('about') },
    ];
  }

  // ── Actions ────────────────────────────────────────────

  async function smartToggleAction() {
    try {
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      const newState = !cfg.smart_mode;
      const preset = cfg.smart_mode_preset || 'cleanup';
      await window.setSmartPreset(newState ? preset : '');
      const raw2 = await window.getConfig();
      const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
      updateStatusBar(newCfg);
      showToast(newState ? t('smartSwitcher.enabled') : t('smartSwitcher.disabled'), false);
    } catch (e) { /* ignore */ }
  }

  async function setPreset(presetId) {
    try {
      await window.setSmartPreset(presetId);
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      updateStatusBar(cfg);
      showToast(t('smartSwitcher.switched') + ': ' + t('smart.preset.' + presetId), false);
    } catch (e) { /* ignore */ }
  }

  async function switchRecordMode(mode) {
    try {
      if (window.switchRecordingMode) {
        await window.switchRecordingMode(mode);
      } else {
        // Fallback: update via config
        const raw = await window.getConfig();
        const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
        cfg.mode = mode;
        await window.saveConfig(JSON.stringify(cfg));
      }
      showToast(mode === 'push_to_talk' ? t('palette.cmd.modePTT') : t('palette.cmd.modeToggle'), false);
    } catch (e) { /* ignore */ }
  }

  function exportSelected(format) {
    // Export currently selected history entries, or all visible
    if (typeof _selectedIds !== 'undefined' && _selectedIds.size > 0) {
      const ids = JSON.stringify(Array.from(_selectedIds));
      if (window.exportSelected) window.exportSelected(ids, format);
    } else {
      showToast(t('notebook.noSelection') || 'Select entries to export', true);
    }
  }

  // ── Fuzzy filter ───────────────────────────────────────

  function fuzzyMatch(query, text) {
    const q = query.toLowerCase();
    const t = text.toLowerCase();
    if (t.includes(q)) return true;
    let qi = 0;
    for (let i = 0; i < t.length && qi < q.length; i++) {
      if (t[i] === q[qi]) qi++;
    }
    return qi === q.length;
  }

  // ── Render ─────────────────────────────────────────────

  function renderPalette(query) {
    const commands = buildCommands();
    _filteredCmds = query
      ? commands.filter(c => fuzzyMatch(query, c.label) || fuzzyMatch(query, t(c.category)))
      : commands;

    const listEl = _paletteEl.querySelector('.cp-list');
    if (!listEl) return;

    if (_filteredCmds.length === 0) {
      listEl.innerHTML = '<div class="cp-empty">' + esc(t('palette.noResults')) + '</div>';
      return;
    }

    // Group by category
    const groups = {};
    for (const cmd of _filteredCmds) {
      const cat = cmd.category;
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(cmd);
    }

    let html = '';
    let globalIdx = 0;
    for (const [cat, cmds] of Object.entries(groups)) {
      html += '<div class="cp-category">' + esc(t(cat)) + '</div>';
      for (const cmd of cmds) {
        const activeClass = globalIdx === _activeIndex ? ' cp-item-active' : '';
        html += '<div class="cp-item' + activeClass + '" data-idx="' + globalIdx + '">';
        html += '<span class="cp-item-icon">' + cmd.icon + '</span>';
        html += '<span class="cp-item-label">' + esc(cmd.label) + '</span>';
        html += '</div>';
        globalIdx++;
      }
    }

    listEl.innerHTML = html;

    // Click handlers
    listEl.querySelectorAll('.cp-item').forEach(el => {
      el.addEventListener('mousedown', (e) => {
        e.preventDefault();
        const idx = parseInt(el.dataset.idx, 10);
        executeCommand(idx);
      });
      el.addEventListener('mouseenter', () => {
        _activeIndex = parseInt(el.dataset.idx, 10);
        highlightActive(listEl);
      });
    });
  }

  function highlightActive(listEl) {
    listEl.querySelectorAll('.cp-item').forEach(el => {
      el.classList.toggle('cp-item-active', parseInt(el.dataset.idx, 10) === _activeIndex);
    });
    // Scroll active into view
    const active = listEl.querySelector('.cp-item-active');
    if (active) active.scrollIntoView({ block: 'nearest' });
  }

  function executeCommand(idx) {
    const cmd = _filteredCmds[idx];
    if (cmd) {
      closePalette();
      cmd.action();
    }
  }

  // ── Open / Close ───────────────────────────────────────

  function openPalette() {
    if (_paletteEl) return;

    // Close any open popovers
    if (typeof hidePopovers === 'function') hidePopovers();

    _activeIndex = 0;

    const backdrop = document.createElement('div');
    backdrop.className = 'cp-backdrop';
    backdrop.addEventListener('mousedown', (e) => {
      if (e.target === backdrop) closePalette();
    });

    const modal = document.createElement('div');
    modal.className = 'cp-modal';

    const searchWrap = document.createElement('div');
    searchWrap.className = 'cp-search-wrap';
    searchWrap.innerHTML =
      '<svg class="icon cp-search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>' +
      '<input type="text" class="cp-search" placeholder="' + esc(t('palette.search')) + '" />';

    const list = document.createElement('div');
    list.className = 'cp-list';

    modal.appendChild(searchWrap);
    modal.appendChild(list);
    backdrop.appendChild(modal);
    document.body.appendChild(backdrop);
    _paletteEl = backdrop;

    const input = modal.querySelector('.cp-search');
    input.focus();
    renderPalette('');

    // Input handler
    input.addEventListener('input', () => {
      _activeIndex = 0;
      renderPalette(input.value);
    });

    // Keyboard navigation
    input.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        _activeIndex = Math.min(_activeIndex + 1, _filteredCmds.length - 1);
        highlightActive(list);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        _activeIndex = Math.max(_activeIndex - 1, 0);
        highlightActive(list);
      } else if (e.key === 'Enter') {
        e.preventDefault();
        executeCommand(_activeIndex);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        closePalette();
      }
    });
  }

  function closePalette() {
    if (_paletteEl) {
      _paletteEl.remove();
      _paletteEl = null;
      _filteredCmds = [];
    }
  }

  // ── Keyboard shortcut: Ctrl+K ──────────────────────────

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      e.stopPropagation();
      if (_paletteEl) {
        closePalette();
      } else {
        openPalette();
      }
    }
  });

  // ── Status bar button ──────────────────────────────────

  function addPaletteButton() {
    const statusBar = document.getElementById('globalStatusBar');
    if (!statusBar) return;
    const indicators = statusBar.querySelector('.status-indicators');
    if (!indicators) return;

    const btn = document.createElement('button');
    btn.className = 'status-chip status-chip-subtle';
    btn.id = 'statusPalette';
    btn.title = t('palette.hint');
    btn.innerHTML =
      '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"/></svg>' +
      '<span class="status-chip-label">Ctrl+K</span>';
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      openPalette();
    });

    indicators.appendChild(btn);
  }

  // Expose globally for other scripts
  window.openCommandPalette = openPalette;

  // Add button after DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', addPaletteButton);
  } else {
    addPaletteButton();
  }
})();
