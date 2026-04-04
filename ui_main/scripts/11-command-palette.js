/* ── Command Palette (Ctrl+K) ──────────────────────────── */

(function () {
  let _paletteEl = null;
  let _activeIndex = 0;
  let _filteredCmds = [];
  let _palettePreviousFocus = null;
  let _recentCommandIds = [];
  let _historyResults = [];
  let _historySearchTimer = null;

  const _RECENT_STORAGE_KEY = 'palette_recent';
  const _RECENT_MAX = 5;
  const _HISTORY_SEARCH_DEBOUNCE = 200;
  const _HISTORY_MAX_RESULTS = 5;

  function _loadRecent() {
    try {
      const raw = safeStorageGet(_RECENT_STORAGE_KEY);
      _recentCommandIds = raw ? JSON.parse(raw) : [];
      if (!Array.isArray(_recentCommandIds)) _recentCommandIds = [];
    } catch (e) { _recentCommandIds = []; }
  }

  function _saveRecent(cmdId) {
    if (cmdId.startsWith('history-')) return;
    _recentCommandIds = _recentCommandIds.filter(id => id !== cmdId);
    _recentCommandIds.unshift(cmdId);
    if (_recentCommandIds.length > _RECENT_MAX) _recentCommandIds.length = _RECENT_MAX;
    try { safeStorageSet(_RECENT_STORAGE_KEY, JSON.stringify(_recentCommandIds)); } catch (e) { /* ignore */ }
  }

  function _getRecentCommands(allCmds) {
    const cmdMap = {};
    for (const c of allCmds) cmdMap[c.id] = c;
    const recent = [];
    for (const id of _recentCommandIds) {
      if (cmdMap[id]) recent.push(cmdMap[id]);
    }
    return recent;
  }

  const paletteIcons = {
    command: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"/></svg>',
    toggleRight: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="12" x="2" y="6" rx="6"/><circle cx="16" cy="12" r="2"/></svg>',
    micOff: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="2" x2="22" y1="2" y2="22"/><path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"/><path d="M5 10v2a7 7 0 0 0 12 5"/><path d="M15 9.34V5a3 3 0 0 0-5.68-1.33"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12"/><line x1="12" x2="12" y1="19" y2="22"/></svg>',
    settings: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>',
    barChart: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/></svg>',
    clock: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>',
    info: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
    hash: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/></svg>',
    braces: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/><path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/></svg>',
    search: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>',
    zap: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>',
    msgSquare: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>',
  };

  // Category icons for visual grouping
  const categoryIcons = {
    'palette.cat.quickActions': paletteIcons.zap,
    'palette.cat.recording':   icons.microphone,
    'palette.cat.smartMode':   icons.sparkles,
    'palette.cat.templates':   icons.fileText,
    'palette.cat.export':      icons.files || icons.fileText,
    'palette.cat.recent':      paletteIcons.clock,
    'palette.cat.historyResults': paletteIcons.clock,
  };

  // ── Category ordering ─────────────────────────────────
  const _categoryOrder = [
    'palette.cat.quickActions',
    'palette.cat.recording',
    'palette.cat.smartMode',
    'palette.cat.templates',
    'palette.cat.export',
  ];

  function buildCommands() {
    const cmds = [
      // ── Quick Actions (highest value) ───────────────────
      { id: 'start-recording',   label: t('palette.cmd.startRecording'),  icon: icons.microphone,         category: 'palette.cat.quickActions', action: startRecordingAction },
      { id: 'copy-last',         label: t('palette.cmd.copyLast'),        icon: icons.copy,               category: 'palette.cat.quickActions', action: copyLastResultAction },
      { id: 'open-last',         label: t('palette.cmd.openLast'),        icon: paletteIcons.clock,       category: 'palette.cat.quickActions', action: openLastEntryAction },
      { id: 'toggle-autopaste',  label: t('palette.cmd.toggleAutoPaste'), icon: icons.clipboard,          category: 'palette.cat.quickActions', action: toggleAutoPasteAction },
      { id: 'search-history',    label: t('palette.cmd.searchHistory'),   icon: paletteIcons.search,      category: 'palette.cat.quickActions', action: searchHistoryAction, shortcut: 'Ctrl+F' },
      { id: 'give-feedback',     label: t('palette.cmd.giveFeedback'),    icon: paletteIcons.msgSquare,   category: 'palette.cat.quickActions', action: () => switchPage('feedback') },

      // ── Recording ───────────────────────────────────────
      { id: 'mode-ptt',    label: t('palette.cmd.modePTT'),    icon: icons.microphone,    category: 'palette.cat.recording', action: () => switchRecordMode('push_to_talk') },
      { id: 'mode-toggle', label: t('palette.cmd.modeToggle'), icon: paletteIcons.micOff,  category: 'palette.cat.recording', action: () => switchRecordMode('toggle') },

      // ── Smart Mode ──────────────────────────────────────
      { id: 'smart-toggle',      label: t('palette.cmd.smartToggle'),      icon: paletteIcons.toggleRight, category: 'palette.cat.smartMode', action: smartToggleAction, shortcut: 'Ctrl+Shift+S' },
      { id: 'preset-cleanup',    label: t('palette.cmd.presetCleanup'),    icon: icons.sparkles,           category: 'palette.cat.smartMode', action: () => setPreset('cleanup') },
      { id: 'preset-concise',    label: t('palette.cmd.presetConcise'),    icon: icons.minimize,           category: 'palette.cat.smartMode', action: () => setPreset('concise') },
      { id: 'preset-translate',  label: t('palette.cmd.presetTranslate'),  icon: icons.globe,              category: 'palette.cat.smartMode', action: () => setPreset('translate') },
    ];

    cmds.push(
      // ── Export ─────────────────────────────────────────
      { id: 'export-txt',  label: t('palette.cmd.exportTXT'),  icon: icons.fileText,       category: 'palette.cat.export', action: () => exportSelected('txt') },
      { id: 'export-md',   label: t('palette.cmd.exportMD'),   icon: paletteIcons.hash,    category: 'palette.cat.export', action: () => exportSelected('md') },
      { id: 'export-csv',  label: t('palette.cmd.exportCSV'),  icon: icons.fileText,       category: 'palette.cat.export', action: () => exportSelected('csv') },
      { id: 'export-json', label: t('palette.cmd.exportJSON'), icon: paletteIcons.braces,  category: 'palette.cat.export', action: () => exportSelected('json') },
    );

    return cmds;
  }

  // ── Actions ────────────────────────────────────────────

  function startRecordingAction() {
    if (window.startCapture) {
      window.startCapture();
    }
  }

  async function copyLastResultAction() {
    try {
      const entries = typeof _entries !== 'undefined' ? _entries : [];
      if (entries.length > 0) {
        const sorted = [...entries].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        const last = sorted[0];
        if (window.copyEntry) {
          await window.copyEntry(last.id);
          showToast(t('palette.toast.copied'), false);
        }
      } else {
        showToast(t('palette.toast.noEntries'), true);
      }
    } catch (e) {
      showToast(t('palette.toast.noEntries'), true);
    }
  }

  async function openLastEntryAction() {
    try {
      const entries = typeof _entries !== 'undefined' ? _entries : [];
      if (entries.length > 0) {
        const sorted = [...entries].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        const last = sorted[0];
        switchPage('history');
        setTimeout(() => {
          if (typeof _expandedId !== 'undefined') {
            _expandedId = last.id;
            if (typeof renderEntries === 'function') renderEntries();
            const el = document.querySelector('.entry[data-id="' + last.id + '"]');
            if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
          }
        }, 150);
      } else {
        showToast(t('palette.toast.noEntries'), true);
      }
    } catch (e) {
      showToast(t('palette.toast.noEntries'), true);
    }
  }

  async function toggleAutoPasteAction() {
    try {
      if (window.toggleAutoPaste) {
        await window.toggleAutoPaste();
        const raw = await window.getConfig();
        const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
        updateStatusBar(cfg);
        showToast(cfg.auto_paste ? t('palette.toast.autoPasteOn') : t('palette.toast.autoPasteOff'), false);
      }
    } catch (e) { /* ignore */ }
  }

  function searchHistoryAction() {
    switchPage('history');
    setTimeout(() => {
      const input = document.getElementById('searchInput');
      if (input) { input.focus(); input.select(); }
    }, 150);
  }

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
      const label = t('smart.preset.' + presetId);
      const displayName = label.startsWith('smart.preset.') ? presetId : label;
      showToast(t('smartSwitcher.switched') + ': ' + displayName, false);
    } catch (e) { /* ignore */ }
  }

  async function switchRecordMode(mode) {
    try {
      if (window.switchRecordingMode) {
        await window.switchRecordingMode(mode);
      } else {
        const raw = await window.getConfig();
        const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
        cfg.mode = mode;
        await window.saveConfig(JSON.stringify(cfg));
      }
      showToast(mode === 'push_to_talk' ? t('palette.cmd.modePTT') : t('palette.cmd.modeToggle'), false);
    } catch (e) { /* ignore */ }
  }

  function exportSelected(format) {
    if (typeof _selectedIds !== 'undefined' && _selectedIds.size > 0) {
      const ids = JSON.stringify(Array.from(_selectedIds));
      if (window.exportSelected) window.exportSelected(ids, format);
    } else {
      showToast(t('notebook.noSelection'), true);
    }
  }

  // ── History search integration ────────────────────────

  async function _searchHistoryEntries(query) {
    if (!query || query.length < 3 || !window.searchEntries) return [];
    try {
      const raw = await window.searchEntries(query);
      const results = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!Array.isArray(results)) return [];
      return results.slice(0, _HISTORY_MAX_RESULTS);
    } catch (e) { return []; }
  }

  function _historyEntryToCommand(entry) {
    const preview = (entry.text || '').substring(0, 60).replace(/\n/g, ' ');
    const ts = typeof formatRelativeTime === 'function' ? formatRelativeTime(entry.timestamp) : '';
    return {
      id: 'history-' + entry.id,
      label: preview || t('palette.historyEntry'),
      sublabel: ts,
      icon: paletteIcons.clock,
      category: 'palette.cat.historyResults',
      isHistory: true,
      action: () => {
        switchPage('history');
        setTimeout(() => {
          if (typeof _expandedId !== 'undefined') {
            _expandedId = entry.id;
            if (typeof renderEntries === 'function') renderEntries();
            const el = document.querySelector('.entry[data-id="' + entry.id + '"]');
            if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
          }
        }, 150);
      },
    };
  }

  // ── Fuzzy filter with scoring ─────────────────────────

  function fuzzyScore(query, text) {
    const q = query.toLowerCase();
    const txt = text.toLowerCase();
    if (txt === q) return 100;
    if (txt.startsWith(q)) return 90;
    if (txt.includes(q)) return 80;
    // Subsequence match
    let qi = 0;
    for (let i = 0; i < txt.length && qi < q.length; i++) {
      if (txt[i] === q[qi]) qi++;
    }
    return qi === q.length ? 60 : 0;
  }

  function fuzzyMatch(query, text) {
    return fuzzyScore(query, text) > 0;
  }

  // ── Render ─────────────────────────────────────────────

  function _renderItem(cmd, globalIdx) {
    const activeClass = globalIdx === _activeIndex ? ' cp-item-active' : '';
    const historyClass = cmd.isHistory ? ' cp-item-history' : '';
    let html = '<div class="cp-item' + activeClass + historyClass + '" data-idx="' + globalIdx + '">';
    html += '<span class="cp-item-icon">' + (cmd.icon || '') + '</span>';
    html += '<span class="cp-item-label">' + esc(cmd.label);
    if (cmd.sublabel) {
      html += '<span class="cp-item-sublabel">' + esc(cmd.sublabel) + '</span>';
    }
    html += '</span>';
    if (cmd.shortcut) {
      const localized = cmd.shortcut.split('+').map(k => formatModKey(k)).join(' + ');
      html += '<kbd class="cp-item-shortcut">' + esc(localized) + '</kbd>';
    }
    html += '</div>';
    return html;
  }

  function _renderCategoryHeader(catKey) {
    const icon = categoryIcons[catKey] || '';
    const iconHtml = icon ? '<span class="cp-category-icon">' + icon + '</span> ' : '';
    return '<div class="cp-category">' + iconHtml + esc(t(catKey)) + '</div>';
  }

  function renderPalette(query, historyHits) {
    const commands = buildCommands();
    const listEl = _paletteEl ? _paletteEl.querySelector('.cp-list') : null;
    if (!listEl) return;

    // Filter commands
    let filtered;
    if (query) {
      filtered = commands
        .map(c => ({ cmd: c, score: Math.max(fuzzyScore(query, c.label), fuzzyScore(query, t(c.category))) }))
        .filter(x => x.score > 0)
        .sort((a, b) => b.score - a.score)
        .map(x => x.cmd);
    } else {
      filtered = commands;
    }

    // Combine history results
    const histItems = (historyHits || []).map(e => _historyEntryToCommand(e));

    // No results at all?
    if (filtered.length === 0 && histItems.length === 0) {
      const emptyMsg = query && query.length > 2
        ? t('palette.noResultsHint')
        : t('palette.noResults');
      listEl.innerHTML = '<div class="cp-empty">' + esc(emptyMsg) + '</div>';
      _filteredCmds = [];
      return;
    }

    // Build display list
    const recentCmds = !query ? _getRecentCommands(commands) : [];
    let html = '';
    let globalIdx = 0;
    _filteredCmds = [];

    // ── Recent section (only when no query) ─────────────
    if (recentCmds.length > 0) {
      html += _renderCategoryHeader('palette.cat.recent');
      for (const cmd of recentCmds) {
        html += _renderItem(cmd, globalIdx);
        _filteredCmds.push(cmd);
        globalIdx++;
      }
    }

    // ── Command sections grouped by category ────────────
    const recentIds = new Set(recentCmds.map(c => c.id));
    const grouped = {};
    const cmdsToGroup = query ? filtered : commands;
    for (const cmd of cmdsToGroup) {
      if (recentIds.has(cmd.id)) continue;
      const cat = cmd.category;
      if (!grouped[cat]) grouped[cat] = [];
      grouped[cat].push(cmd);
    }

    // Render in defined order, then any remaining
    const renderedCats = new Set();
    for (const cat of _categoryOrder) {
      if (!grouped[cat]) continue;
      renderedCats.add(cat);
      html += _renderCategoryHeader(cat);
      for (const cmd of grouped[cat]) {
        html += _renderItem(cmd, globalIdx);
        _filteredCmds.push(cmd);
        globalIdx++;
      }
    }
    for (const [cat, cmds] of Object.entries(grouped)) {
      if (renderedCats.has(cat)) continue;
      html += _renderCategoryHeader(cat);
      for (const cmd of cmds) {
        html += _renderItem(cmd, globalIdx);
        _filteredCmds.push(cmd);
        globalIdx++;
      }
    }

    // ── History results section ──────────────────────────
    if (histItems.length > 0) {
      html += _renderCategoryHeader('palette.cat.historyResults');
      for (const cmd of histItems) {
        html += _renderItem(cmd, globalIdx);
        _filteredCmds.push(cmd);
        globalIdx++;
      }
    }

    listEl.innerHTML = html;
    _bindListEvents(listEl);
  }

  function _bindListEvents(listEl) {
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
    const active = listEl.querySelector('.cp-item-active');
    if (active) active.scrollIntoView({ block: 'nearest' });
  }

  function executeCommand(idx) {
    const cmd = _filteredCmds[idx];
    if (cmd) {
      _saveRecent(cmd.id);
      closePalette();
      cmd.action();
    }
  }

  // ── Debounced history search ──────────────────────────

  function _scheduleHistorySearch(query) {
    if (_historySearchTimer) clearTimeout(_historySearchTimer);
    if (!query || query.length < 3) {
      _historyResults = [];
      return;
    }
    _historySearchTimer = setTimeout(async () => {
      const results = await _searchHistoryEntries(query);
      _historyResults = results;
      if (_paletteEl) {
        const input = _paletteEl.querySelector('.cp-search');
        if (input && input.value === query) {
          renderPalette(query, results);
        }
      }
    }, _HISTORY_SEARCH_DEBOUNCE);
  }

  // ── Open / Close ───────────────────────────────────────

  async function openPalette() {
    if (_paletteEl) return;

    _palettePreviousFocus = document.activeElement;
    if (typeof hidePopovers === 'function') hidePopovers();

    _activeIndex = 0;
    _historyResults = [];
    _loadRecent();

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
    if (input) input.focus();
    renderPalette('');

    input.addEventListener('input', () => {
      _activeIndex = 0;
      const q = input.value.trim();
      renderPalette(q, _historyResults);
      _scheduleHistorySearch(q);
    });

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
    if (_historySearchTimer) { clearTimeout(_historySearchTimer); _historySearchTimer = null; }
    if (_paletteEl) {
      _paletteEl.remove();
      _paletteEl = null;
      _filteredCmds = [];
      _historyResults = [];
    }
    if (_palettePreviousFocus && typeof _palettePreviousFocus.focus === 'function') {
      _palettePreviousFocus.focus();
      _palettePreviousFocus = null;
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

  // ── Global navigation shortcuts ─────────────────────────

  document.addEventListener('keydown', function(e) {
    if (typeof _hotkeyRecording !== 'undefined' && _hotkeyRecording) return;

    // Navigation shortcuts: Ctrl+1..6
    if (e.ctrlKey && !e.shiftKey && !e.altKey && e.key >= '1' && e.key <= '6') {
      const pages = ['history', 'replacements', 'analytics', 'settings', 'about'];
      const idx = parseInt(e.key) - 1;
      if (idx >= 0 && idx < pages.length) {
        e.preventDefault();
        closePalette();
        switchPage(pages[idx]);
      }
    }
    // Smart toggle: Ctrl+Shift+S
    if (e.ctrlKey && e.shiftKey && !e.altKey && e.key.toUpperCase() === 'S') {
      e.preventDefault();
      closePalette();
      smartToggleAction();
    }
  }, true);

  // ── Status bar button ──────────────────────────────────
  // Palette chip is now static in template.html — binding handled by updateStatusBar()

  // Expose globally for other scripts
  window.openCommandPalette = openPalette;
})();
