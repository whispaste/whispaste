/* ── History Page Logic ────────────────────────────────── */
let _entries = [];
let _activeFilters = { time: null, pinned: false, tags: [] };
let _searchQuery = '';
let _currentSort = 'newest';
let _expandedId = null;
let _selectedIds = new Set();
let _lastCheckedIndex = -1;
let _acHighlight = -1;
let _acSeq = 0;
let _pinnedCollapsed = false;

function isToday(ts) {
  const d = new Date(ts), now = new Date();
  return d.toDateString() === now.toDateString();
}

function isThisWeek(ts) {
  const d = new Date(ts), now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  return d >= weekAgo;
}

function matchesFilter(e) {
  // Time filter
  if (_activeFilters.time === 'today' && !isToday(e.timestamp)) return false;
  if (_activeFilters.time === 'week' && !isThisWeek(e.timestamp)) return false;
  if (_activeFilters.time === 'older' && isThisWeek(e.timestamp)) return false;
  if (_activeFilters.time === 'custom') {
    const fromVal = document.getElementById('dateFrom')?.value;
    const toVal = document.getElementById('dateTo')?.value;
    if (fromVal || toVal) {
      const fromDate = fromVal ? new Date(fromVal) : new Date(0);
      const toDate = toVal ? new Date(toVal + 'T23:59:59') : new Date();
      const d = new Date(e.timestamp);
      if (d < fromDate || d > toDate) return false;
    }
  }
  // Pinned filter
  if (_activeFilters.pinned && !e.pinned) return false;
  // Tag filters (AND logic)
  if (_activeFilters.tags.length > 0) {
    const entryTags = e.tags || [];
    for (const tag of _activeFilters.tags) {
      if (!entryTags.includes(tag)) return false;
    }
  }
  return true;
}

function matchesSearch(e) {
  if (!_searchQuery) return true;
  const q = _searchQuery.trim();
  if (!q) return true;

  const title = (e.title || '').toLowerCase();
  const text = (e.text || '').toLowerCase();
  const content = title + ' ' + text;

  const tokens = parseSearchTokens(q);
  return evaluateSearch(tokens, content);
}

function parseSearchTokens(query) {
  const tokens = [];
  const regex = /"([^"]+)"|(\S+)/g;
  let match;
  let expectOp = null;

  while ((match = regex.exec(query)) !== null) {
    const term = (match[1] || match[2]).toLowerCase();

    if (term === 'and' || term === '&') { expectOp = 'AND'; continue; }
    if (term === 'or' || term === '|') { expectOp = 'OR'; continue; }

    let negate = false;
    let actualTerm = term;
    if (term.startsWith('-') || term.startsWith('!')) {
      negate = true;
      actualTerm = term.slice(1);
    } else if (term === 'not') {
      expectOp = 'NOT';
      continue;
    }

    if (expectOp === 'NOT') {
      negate = true;
      expectOp = null;
    }

    tokens.push({
      term: actualTerm,
      negate,
      op: expectOp || 'AND',
      isWildcard: actualTerm.includes('*'),
    });
    expectOp = null;
  }
  return tokens;
}

function evaluateSearch(tokens, content) {
  if (tokens.length === 0) return true;

  let result = null;
  for (const tok of tokens) {
    let matches;
    if (tok.isWildcard) {
      const pattern = tok.term.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '\\S*');
      try {
        matches = new RegExp('(?:^|\\s|[^\\w])' + pattern + '(?:$|\\s|[^\\w])', 'i').test(content) ||
                  new RegExp('^' + pattern, 'i').test(content);
      } catch {
        matches = content.includes(tok.term.replace(/[*?]/g, ''));
      }
    } else {
      matches = content.includes(tok.term);
    }

    if (tok.negate) matches = !matches;

    if (result === null) {
      result = matches;
    } else if (tok.op === 'OR') {
      result = result || matches;
    } else {
      result = result && matches;
    }
  }
  return result ?? true;
}

function getFiltered() {
  let list = _entries.filter(e => matchesFilter(e) && matchesSearch(e));
  list.sort((a, b) => {
    if (a.pinned && !b.pinned) return -1;
    if (!a.pinned && b.pinned) return 1;
    switch (_currentSort) {
      case 'oldest': return new Date(a.timestamp) - new Date(b.timestamp);
      case 'alpha': return (a.title || a.text).localeCompare(b.title || b.text);
      case 'duration': return (b.duration_sec || 0) - (a.duration_sec || 0);
      default: return new Date(b.timestamp) - new Date(a.timestamp);
    }
  });
  return list;
}

async function loadEntries() {
  try {
    if (window.getEntries) {
      const json = await window.getEntries();
      _entries = JSON.parse(json);
    }
  } catch (e) { _entries = []; }
  await _refreshCustomTags();
  // Prune stale selections
  const entryIds = new Set(_entries.map(e => e.id));
  for (const id of _selectedIds) {
    if (!entryIds.has(id)) _selectedIds.delete(id);
  }
  updateSelectionBar();
  renderHistory();
}

function changeSort(val) {
  _currentSort = val;
  renderHistory();
}

function initSortDropdown() {
  const trigger = document.getElementById('sortTrigger');
  const label = document.getElementById('sortLabel');
  if (!trigger) return;

  trigger.addEventListener('click', () => {
    const sortOptions = [
      { value: 'newest', i18n: 'notebook.sort_newest' },
      { value: 'oldest', i18n: 'notebook.sort_oldest' },
      { value: 'alpha',  i18n: 'notebook.sort_alpha' },
      { value: 'duration', i18n: 'notebook.sort_duration' },
    ];

    const items = [];
    for (const opt of sortOptions) {
      items.push({
        label: t(opt.i18n),
        checked: _currentSort === opt.value,
        action: () => {
          _currentSort = opt.value;
          if (label) label.textContent = t(opt.i18n);
          renderHistory();
        },
      });
    }

    showPopover(trigger, { items });
  });
}

function setFilter(f) {
  const timeFilters = ['today', 'week', 'older', 'custom'];
  if (f === 'all') {
    // Reset all filters
    _activeFilters = { time: null, pinned: false, tags: [] };
  } else if (f === 'pinned') {
    _activeFilters.pinned = !_activeFilters.pinned;
  } else if (timeFilters.includes(f)) {
    // Radio-style: toggle off if same, otherwise switch
    _activeFilters.time = _activeFilters.time === f ? null : f;
  } else if (f.startsWith('cat:')) {
    const tag = f.slice(4);
    const idx = _activeFilters.tags.indexOf(tag);
    if (idx >= 0) _activeFilters.tags.splice(idx, 1);
    else _activeFilters.tags.push(tag);
  }
  _updateFilterUI();
  const picker = document.getElementById('dateRangePicker');
  if (picker) picker.style.display = _activeFilters.time === 'custom' ? '' : 'none';
  renderHistory();
}

function _getActiveFilterCount() {
  let n = 0;
  if (_activeFilters.time) n++;
  if (_activeFilters.pinned) n++;
  n += _activeFilters.tags.length;
  return n;
}

function _hasActiveFilters() {
  return _getActiveFilterCount() > 0;
}

function clearAllFilters() {
  _activeFilters = { time: null, pinned: false, tags: [] };
  const picker = document.getElementById('dateRangePicker');
  if (picker) picker.style.display = 'none';
  _updateFilterUI();
  renderHistory();
}

function _updateFilterUI() {
  // Time + All items
  document.querySelectorAll('.filter-item[data-filter]').forEach(el => {
    const f = el.dataset.filter;
    if (f === 'all') {
      el.classList.toggle('active', !_hasActiveFilters());
    } else if (f === 'pinned') {
      el.classList.toggle('active', _activeFilters.pinned);
    } else if (['today', 'week', 'older', 'custom'].includes(f)) {
      el.classList.toggle('active', _activeFilters.time === f);
    } else if (f.startsWith('cat:')) {
      el.classList.toggle('active', _activeFilters.tags.includes(f.slice(4)));
    }
  });
  // Clear filters bar
  const bar = document.getElementById('clearFiltersBar');
  const btn = document.getElementById('clearFiltersBtn');
  if (bar && btn) {
    const n = _getActiveFilterCount();
    if (n > 0) {
      const label = n === 1 ? t('notebook.filters_active') : t('notebook.filters_active_plural');
      btn.innerHTML = `${label.replace('{n}', n)} <svg class="icon" style="width:12px;height:12px;margin-left:4px;vertical-align:-1px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`;
      bar.style.display = '';
    } else {
      bar.style.display = 'none';
    }
  }
}

function updateCounts() {
  const setCount = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  setCount('countAll', _entries.length);
  setCount('countPinned', _entries.filter(e => e.pinned).length);
  setCount('countToday', _entries.filter(e => isToday(e.timestamp)).length);
  setCount('countWeek', _entries.filter(e => isThisWeek(e.timestamp)).length);
  setCount('countOlder', _entries.filter(e => !isThisWeek(e.timestamp)).length);

  // Dynamic categories (include persisted custom tags with count 0)
  const cats = {};
  _loadCustomTagsInto(cats);
  _entries.forEach(e => { (e.tags || []).forEach(tag => { cats[tag] = (cats[tag] || 0) + 1; }); });
  const catSection = document.getElementById('categoriesSection');
  const catList = document.getElementById('categoryList');
  if (catSection && catList) {
    if (Object.keys(cats).length > 0 || true) {
      catSection.style.display = '';

      // Separate system tags (top) from custom tags (ordered by _cachedCustomTags)
      const systemEntries = [];
      const customEntries = [];
      const customOrder = window._cachedCustomTags || [];
      for (const [name, count] of Object.entries(cats)) {
        if (isSystemTag(name)) systemEntries.push([name, count]);
        else customEntries.push([name, count]);
      }
      // Sort custom tags by their order in the persisted list
      customEntries.sort((a, b) => {
        const ia = customOrder.indexOf(a[0]);
        const ib = customOrder.indexOf(b[0]);
        return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
      });

      // Build tag list HTML with system tags grouped at top
      let tagListHTML = '';
      if (systemEntries.length > 0) {
        tagListHTML += `<div class="filter-section-title" style="padding-top:4px">${t('notebook.system_tags')}</div>`;
        tagListHTML += systemEntries.map(([name, count]) => {
          const label = name === 'merged' ? t('catMerged') : name === 'duplicated' ? t('catDuplicated') : name;
          const c = getTagColor(name);
          return `
          <div class="filter-item tag-sidebar-item${_activeFilters.tags.includes(name) ? ' active' : ''} system-tag-item" data-filter="cat:${esc(name)}" data-tag="${esc(name)}">
            <svg class="icon tag-icon-clr" viewBox="0 0 24 24" fill="none" stroke="${c.text}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px;flex-shrink:0"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
            <span class="filter-label" title="${esc(label)}">${esc(label)}</span>
            <span class="filter-count">${count}</span>
          </div>
        `;}).join('');
        if (customEntries.length > 0) {
          tagListHTML += '<div class="tag-group-divider"></div>';
        }
      }
      tagListHTML += customEntries.map(([name, count]) => {
        const label = name;
        const c = getTagColor(name);
        return `
        <div class="filter-item tag-sidebar-item${_activeFilters.tags.includes(name) ? ' active' : ''}" data-filter="cat:${esc(name)}" data-tag="${esc(name)}" draggable="true">
          <svg class="icon tag-icon-clr" viewBox="0 0 24 24" fill="none" stroke="${c.text}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px;flex-shrink:0"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="${c.text}"/></svg>
          <span class="filter-label" title="${esc(label)}">${esc(label)}</span>
          <span class="filter-count">${count}</span>
        </div>
      `;}).join('');
      tagListHTML += `
        <div class="sidebar-add-tag" id="sidebarAddTag">
          <svg class="icon" style="width:12px;height:12px;flex-shrink:0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
          <span class="filter-label">${t('sidebar_add_tag') || 'Add tag'}</span>
        </div>
      `;
      catList.innerHTML = tagListHTML;
      catList.querySelectorAll('.filter-item').forEach(el => {
        el.addEventListener('click', () => setFilter(el.dataset.filter));
      });
      _bindSidebarAddTag();
      _bindSidebarDragDrop(catList);
    } else {
      catSection.style.display = 'none';
    }
  }
  _updateFilterUI();
}

// Load persisted custom tags into the cats map with count 0 if not already present.
function _loadCustomTagsInto(cats) {
  try {
    if (window._cachedCustomTags) {
      window._cachedCustomTags.forEach(tag => { if (!(tag in cats)) cats[tag] = 0; });
    }
  } catch (_) {}
}

// Fetch custom tags from Go binding and cache them.
async function _refreshCustomTags() {
  try {
    if (window.getCustomTags) {
      window._cachedCustomTags = JSON.parse(await window.getCustomTags()) || [];
    }
  } catch (_) {
    window._cachedCustomTags = [];
  }
}

// Persist a new custom tag via Go binding.
async function _persistCustomTag(tag) {
  try {
    if (!window.saveCustomTags) return;
    if (!window._cachedCustomTags) await _refreshCustomTags();
    const tags = window._cachedCustomTags || [];
    if (!tags.includes(tag)) {
      tags.push(tag);
      window._cachedCustomTags = tags;
      await window.saveCustomTags(JSON.stringify(tags));
    }
  } catch (_) {}
}

/* ── Tag Autocomplete ─────────────────────────────────── */
async function _fetchCategories() {
  try {
    if (window.getCategories) return JSON.parse(await window.getCategories());
  } catch (_) {}
  return [];
}

function _showTagAutocomplete(input) {
  _closeTagAutocomplete();
  const row = input.closest('.tag-input-row');
  if (!row) return;
  const seq = ++_acSeq;
  _fetchCategories().then(cats => {
    if (seq !== _acSeq) return;               // stale request
    if (document.activeElement !== input) return; // input lost focus
    const query = input.value.trim().toLowerCase();
    const entry = _entries.find(e => e.id === input.dataset.id);
    const entryTags = (entry?.tags || []).map(tg => tg.toLowerCase());
    const filtered = cats.filter(c =>
      !isSystemTag(c) &&
      !entryTags.includes(c.toLowerCase()) &&
      (query === '' || c.toLowerCase().includes(query))
    );
    if (filtered.length === 0) return;
    _closeTagAutocomplete(); // clear any dropdown from a concurrent resolve
    const dd = document.createElement('div');
    dd.className = 'tag-autocomplete';
    dd.dataset.forId = input.dataset.id;
    _acHighlight = -1;
    filtered.forEach((tag, i) => {
      const item = document.createElement('div');
      item.className = 'tag-autocomplete-item';
      item.textContent = tag;
      item.addEventListener('mousedown', (ev) => {
        ev.preventDefault(); // keep focus on input
        input.value = tag;
        _closeTagAutocomplete();
        addTag(input);
      });
      dd.appendChild(item);
    });
    row.appendChild(dd);
  });
}

function _closeTagAutocomplete() {
  document.querySelectorAll('.tag-autocomplete').forEach(el => el.remove());
  _acHighlight = -1;
}

function _navigateAutocomplete(input, direction) {
  const dd = input.closest('.tag-input-row')?.querySelector('.tag-autocomplete');
  if (!dd) return;
  const items = dd.querySelectorAll('.tag-autocomplete-item');
  if (items.length === 0) return;
  items.forEach(i => i.classList.remove('active'));
  _acHighlight += direction;
  if (_acHighlight < 0) _acHighlight = items.length - 1;
  if (_acHighlight >= items.length) _acHighlight = 0;
  items[_acHighlight].classList.add('active');
  items[_acHighlight].scrollIntoView({ block: 'nearest' });
}

function _selectAutocompleteHighlight(input) {
  const dd = input.closest('.tag-input-row')?.querySelector('.tag-autocomplete');
  if (!dd) return false;
  const active = dd.querySelector('.tag-autocomplete-item.active');
  if (!active) return false;
  input.value = active.textContent;
  _closeTagAutocomplete();
  addTag(input);
  return true;
}

function _renderEntryCard(e) {
  return `
    <div class="entry${e.pinned ? ' pinned' : ''}${_expandedId === e.id ? ' expanded' : ''}${_selectedIds.has(e.id) ? ' selected' : ''}" data-id="${e.id}">
      <div class="entry-header">
        <div class="entry-checkbox${_selectedIds.has(e.id) ? ' checked' : ''}" data-select-id="${e.id}"></div>
        <div style="flex:1;min-width:0">
          <div class="entry-title">${highlightSearch(e.title || e.text.substring(0, 60), _searchQuery)}</div>
          <div class="entry-meta">
            <span class="meta-item" title="${formatTime(e.timestamp)}"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="4" rx="2" ry="2"/><line x1="16" x2="16" y1="2" y2="6"/><line x1="8" x2="8" y1="2" y2="6"/><line x1="3" x2="21" y1="10" y2="10"/></svg> ${formatTime(e.timestamp)}</span>
            ${e.duration_sec ? '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 3l4 0"/><path d="M7 3l0 3"/><circle cx="7" cy="14" r="7"/><path d="M7 11v3h3"/></svg> ' + formatDuration(e.duration_sec) + '</span>' : ''}
            ${e.language ? '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20"/></svg> ' + e.language.toUpperCase() + '</span>' : ''}
            ${e.model ? '<span class="meta-item" title="' + esc(e.model) + (e.is_local ? ' (local)' : '') + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/></svg> ' + esc(e.model) + '</span>' : ''}
            ${(e.text || '').length > 0 ? (() => { const wc = (e.text || '').split(/\s+/).filter(Boolean).length; return '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7V4h16v3"/><path d="M9 20h6"/><path d="M12 4v16"/></svg> ' + wc + ' ' + (wc === 1 ? t('meta_word') : t('meta_words')) + '</span>'; })() : ''}
          </div>
        </div>
        <span class="entry-chevron">${icons.chevronDown}</span>
        <div class="entry-actions">
          <button class="btn-icon copy" title="${t('notebook.copy')}" data-action="copy" data-id="${e.id}">${icons.copy}</button>
          <button class="btn-icon" title="${t('notebook.export')}" data-action="export" data-id="${e.id}">${icons.download}</button>
          <button class="btn-icon" title="${t('notebook.duplicate')}" data-action="duplicate" data-id="${e.id}">${icons.filePlus}</button>
          <button class="btn-icon audio-play" title="${t('notebook.play_audio')}" data-action="play-audio" data-id="${e.id}" style="display:none">${icons.play}</button>
          <button class="btn-icon audio-retranscribe" title="${t('notebook.retranscribe')}" data-action="retranscribe" data-id="${e.id}" style="display:none">${icons.refreshCw}</button>
          <button class="btn-icon pin${e.pinned ? ' active' : ''}" title="${e.pinned ? t('notebook.unpin') : t('notebook.pin')}" data-action="pin" data-id="${e.id}">${icons.pin}</button>
          <button class="btn-icon delete" title="${t('notebook.delete')}" data-action="delete" data-id="${e.id}">${icons.trash}</button>
          <button class="btn-icon" title="${t('smart.action')}" data-action="smart" data-id="${e.id}">${icons.sparkle}</button>
        </div>
      </div>
      <div class="entry-preview">${highlightSearch(e.text, _searchQuery)}</div>
      <div class="entry-tags-row">
        ${(e.tags || []).map(tag => { const c = getTagColor(tag); const sys = isSystemTag(tag); const lbl = tag === 'merged' ? t('catMerged') : tag === 'duplicated' ? t('catDuplicated') : tag; return '<span class="tag' + (sys ? ' system-tag' : '') + '" data-tag="' + esc(tag) + '" style="background:'+c.bg+';color:'+c.text+';border-color:'+c.border+'">' + (sys ? '<svg class="icon" style="width:10px;height:10px;vertical-align:-1px;margin-right:2px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>' : '') + esc(lbl) + '</span>'; }).join('')}
        <span class="tag-add-inline" title="${t('notebook.add_tag')}" data-id="${e.id}">+</span>
      </div>
      <div class="entry-full">
        <div class="entry-full-text" id="text-${e.id}">${highlightSearch(e.text, _searchQuery)}</div>
        <div class="entry-text-actions">
          <button class="btn-icon" title="${t('notebook.edit_text')}" data-action="edit-text" data-id="${e.id}">${icons.pencil}</button>
        </div>
        <div class="entry-tags-section">
          <div class="tag-chips-container">
            ${(e.tags || []).map(tag => { const c = getTagColor(tag); const sys = isSystemTag(tag); const lbl = tag === 'merged' ? t('catMerged') : tag === 'duplicated' ? t('catDuplicated') : tag; return `
              <span class="tag-chip${sys ? ' system-tag' : ''}" style="background:${c.bg};color:${c.text};border-color:${c.border}">
                ${sys ? '<svg class="icon" style="width:10px;height:10px;vertical-align:-1px;margin-right:2px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>' : ''}${esc(lbl)}
                ${sys ? '' : '<span class="tag-chip-remove" data-remove-tag="' + esc(tag) + '" data-id="' + e.id + '">&times;</span>'}
              </span>
            `; }).join('')}
            <div class="tag-input-row">
              ${icons.tag}
              <input type="text" class="tag-input" placeholder="${t('notebook.add_tag')}" data-id="${e.id}" />
            </div>
          </div>
        </div>
      </div>
    </div>`;
}

function renderHistory() {
  const list = document.getElementById('entriesList');
  if (!list) return;
  const filtered = getFiltered();
  updateCounts();

  if (_entries.length === 0) {
    list.innerHTML = `<div class="empty-state">${icons.microphone}<p>${t('notebook.empty')}</p></div>`;
    return;
  }
  if (filtered.length === 0) {
    list.innerHTML = `<div class="empty-state"><p>${t('notebook.no_results')}</p></div>`;
    return;
  }

  // Split into pinned and unpinned groups
  const pinnedItems = filtered.filter(e => e.pinned);
  const unpinnedItems = filtered.filter(e => !e.pinned);
  let html = '';

  if (pinnedItems.length > 0) {
    const chevronIcon = _pinnedCollapsed
      ? '<svg class="icon" style="width:14px;height:14px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>'
      : '<svg class="icon" style="width:14px;height:14px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';
    html += `<div class="pinned-section-header${_pinnedCollapsed ? ' collapsed' : ''}" id="pinnedSectionHeader">
      ${chevronIcon}
      ${icons.pin}
      <span>${t('notebook.pinned_section').replace('{n}', pinnedItems.length)}</span>
    </div>`;
    if (!_pinnedCollapsed) {
      html += pinnedItems.map(e => _renderEntryCard(e)).join('');
    }
  }
  html += unpinnedItems.map(e => _renderEntryCard(e)).join('');
  list.innerHTML = html;

  // Bind pinned section header
  const pinnedHeader = document.getElementById('pinnedSectionHeader');
  if (pinnedHeader) {
    pinnedHeader.addEventListener('click', () => {
      _pinnedCollapsed = !_pinnedCollapsed;
      renderHistory();
    });
  }

  // Bind entry click to expand/collapse
  list.querySelectorAll('.entry').forEach(el => {
    el.addEventListener('click', (ev) => {
      if (ev.target.closest('[data-action]') || ev.target.closest('.tag-input') || ev.target.closest('.tag-chip-remove') || ev.target.closest('.entry-checkbox') || ev.target.closest('.edit-textarea') || ev.target.closest('.entry-full-text') || ev.target.closest('.tag-add-inline')) return;
      const id = el.dataset.id;
      _expandedId = _expandedId === id ? null : id;
      renderHistory();
    });
  });

  // Bind checkbox clicks for multi-select (with Shift+click range selection)
  const visibleIds = filtered.map(e => e.id);
  list.querySelectorAll('.entry-checkbox').forEach(cb => {
    cb.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const id = cb.dataset.selectId;
      const currentIndex = visibleIds.indexOf(id);

      if (ev.shiftKey && _lastCheckedIndex >= 0 && currentIndex >= 0) {
        const from = Math.min(_lastCheckedIndex, currentIndex);
        const to = Math.max(_lastCheckedIndex, currentIndex);
        for (let i = from; i <= to; i++) _selectedIds.add(visibleIds[i]);
      } else {
        if (_selectedIds.has(id)) _selectedIds.delete(id);
        else _selectedIds.add(id);
      }

      if (currentIndex >= 0) _lastCheckedIndex = currentIndex;
      updateSelectionBar();
      renderHistory();
    });
  });

  // Bind action buttons
  list.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const action = btn.dataset.action;
      const id = btn.dataset.id;
      if (action === 'copy') doCopy(id);
      else if (action === 'export') showExportMenu(id, btn);
      else if (action === 'duplicate') doDuplicate(id);
      else if (action === 'pin') doPin(id);
      else if (action === 'delete') confirmDelete(id);
      else if (action === 'edit-text') startEditText(id);
      else if (action === 'smart') showSmartActionMenu(id, btn);
      else if (action === 'save-text') saveEditText(id);
      else if (action === 'cancel-text') cancelEditText(id);
      else if (action === 'play-audio') doPlayAudio(id);
      else if (action === 'retranscribe') doReTranscribe(id, btn);
    });
  });

  // Bind tag inputs
  list.querySelectorAll('.tag-input').forEach(input => {
    input.addEventListener('change', () => { _closeTagAutocomplete(); addTag(input); });
    input.addEventListener('focus', () => _showTagAutocomplete(input));
    input.addEventListener('input', () => _showTagAutocomplete(input));
    input.addEventListener('blur', () => _closeTagAutocomplete());
    input.addEventListener('keydown', (ev) => {
      const dd = input.closest('.tag-input-row')?.querySelector('.tag-autocomplete');
      if (ev.key === 'Escape') { _closeTagAutocomplete(); ev.stopPropagation(); return; }
      if (ev.key === 'Enter') { ev.preventDefault(); if (!_selectAutocompleteHighlight(input)) addTag(input); return; }
      if (!dd) return;
      if (ev.key === 'ArrowDown') { ev.preventDefault(); _navigateAutocomplete(input, 1); }
      else if (ev.key === 'ArrowUp') { ev.preventDefault(); _navigateAutocomplete(input, -1); }
    });
  });

  // Bind click-to-edit on full text
  list.querySelectorAll('.entry-full-text').forEach(el => {
    el.addEventListener('click', (ev) => {
      if (el.querySelector('textarea')) return;
      const entry = el.closest('.entry');
      if (entry) startEditText(entry.dataset.id);
    });
  });

  // Bind tag chip remove buttons
  list.querySelectorAll('.tag-chip-remove').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      removeTag(btn.dataset.id, btn.dataset.removeTag);
    });
  });

  // Bind inline tag-add "+" buttons (compact mode)
  list.querySelectorAll('.tag-add-inline').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      _showInlineTagPopover(ev.clientX, ev.clientY, btn.dataset.id);
    });
  });

  // Async: check which entries have cached audio and show play/retranscribe buttons
  _updateAudioButtons(list);
}

async function _updateAudioButtons(container) {
  if (!window.hasAudio) return;
  const playBtns = container.querySelectorAll('[data-action="play-audio"]');
  const retransBtns = container.querySelectorAll('[data-action="retranscribe"]');
  for (const btn of playBtns) {
    const id = btn.dataset.id;
    try {
      const has = await window.hasAudio(id);
      if (has) btn.style.display = '';
    } catch (e) {}
  }
  for (const btn of retransBtns) {
    const id = btn.dataset.id;
    try {
      const has = await window.hasAudio(id);
      if (has) btn.style.display = '';
    } catch (e) {}
  }
}

async function doCopy(id) {
  try {
    if (window.copyEntry) await window.copyEntry(id);
    showToast(t('notebook.copied'));
  } catch (e) { showToast('Error', true); }
}

async function doDuplicate(id) {
  if (window.duplicateEntry) {
    await window.duplicateEntry(id);
    await loadEntries();
    showToast(t('notebook.duplicated'));
  }
}

async function doPin(id) {
  try {
    if (window.pinEntry) await window.pinEntry(id);
    await loadEntries();
  } catch (e) {}
}

// Audio playback state
let _currentAudio = null;

async function doPlayAudio(id) {
  // Stop any currently playing audio
  if (_currentAudio) {
    _currentAudio.pause();
    _currentAudio = null;
  }
  try {
    const dataUrl = await window.getAudioBase64(id);
    if (!dataUrl) {
      showToast(t('notebook.no_audio'), true);
      return;
    }
    _currentAudio = new Audio(dataUrl);
    _currentAudio.play();
    _currentAudio.onended = () => { _currentAudio = null; };
  } catch (e) {
    showToast(t('notebook.no_audio'), true);
  }
}

async function doReTranscribe(id, btn) {
  if (!window.reTranscribe) return;
  const origHTML = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<svg class="icon spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>';
  try {
    const result = await window.reTranscribe(id);
    if (result && result.ok) {
      showToast(t('notebook.retranscribed'), false);
      await loadEntries();
    } else {
      showToast(result?.error || t('notebook.no_audio'), true);
    }
  } catch (e) {
    showToast(t('notebook.no_audio'), true);
  } finally {
    btn.innerHTML = origHTML;
    btn.disabled = false;
  }
}

async function mergeSelected() {
  if (_selectedIds.size < 2) {
    showToast(t('mergeTooFew'), false);
    return;
  }
  if (window._mergeEntries) {
    try {
      const result = await window._mergeEntries(JSON.stringify([..._selectedIds]));
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res.success) {
        showToast(t('mergeSuccess'), false);
        clearSelection();
        loadEntries();
      } else {
        showToast(res.error || t('statusError'), true);
      }
    } catch (e) {
      showToast(t('statusError'), true);
    }
  }
}

function startEditText(id) {
  const textEl = document.getElementById('text-' + id);
  const actionsEl = textEl?.nextElementSibling;
  if (!textEl) return;
  const currentText = textEl.textContent;
  textEl.innerHTML = `<textarea class="edit-textarea" id="edit-area-${id}">${esc(currentText)}</textarea>`;
  if (actionsEl) {
    actionsEl.innerHTML = `
      <button class="btn-icon" title="${t('notebook.save')}" data-action="save-text" data-id="${id}">${icons.check}</button>
      <button class="btn-icon" title="${t('notebook.cancel')}" data-action="cancel-text" data-id="${id}">${icons.x}</button>
    `;
    actionsEl.querySelectorAll('[data-action]').forEach(btn => {
      btn.addEventListener('mousedown', (ev) => {
        ev.preventDefault(); // prevent blur before action
      });
      btn.addEventListener('click', (ev) => {
        ev.stopPropagation();
        const ta = document.getElementById('edit-area-' + id);
        if (ta) ta._actionHandled = true;
        const action = btn.dataset.action;
        if (action === 'save-text') saveEditText(id);
        else if (action === 'cancel-text') cancelEditText(id);
      });
    });
  }
  const ta = document.getElementById('edit-area-' + id);
  if (ta) {
    ta.focus();
    ta.style.height = ta.scrollHeight + 'px';
    let saved = false;
    ta.addEventListener('blur', () => {
      if (!saved) { saved = true; saveEditText(id); }
    });
  }
}

async function saveEditText(id) {
  const ta = document.getElementById('edit-area-' + id);
  if (!ta) return;
  const newText = ta.value.trim();
  if (!newText) return;
  try {
    if (window.updateEntryText) await window.updateEntryText(id, newText);
    showToast(t('notebook.saved'));
    await loadEntries();
  } catch (e) { showToast(t('statusError'), true); }
}

function cancelEditText(id) {
  loadEntries();
}

async function confirmDelete(id) {
  const confirmed = await showConfirmDialog(
    t('notebook.confirm_title'),
    t('notebook.confirm_msg'),
    { variant: 'danger', confirmText: t('notebook.confirm_delete') }
  );
  if (confirmed) {
    try {
      let ok = true;
      if (window.deleteEntry) ok = await window.deleteEntry(id);
      if (ok) {
        if (_expandedId === id) _expandedId = null;
        _selectedIds.delete(id);
      } else {
        showToast(t('statusError'), true);
      }
    } catch (e) {
      showToast(t('statusError'), true);
    }
    updateSelectionBar();
    await loadEntries();
  }
}

async function confirmDeleteSelected() {
  const count = _selectedIds.size;
  if (count === 0) return;
  const confirmed = await showConfirmDialog(
    t('notebook.confirm_delete_multi_title').replace('{n}', count),
    t('notebook.confirm_delete_multi_msg').replace('{n}', count),
    { variant: 'danger', confirmText: t('notebook.confirm_delete') }
  );
  if (confirmed) {
    const deleted = [];
    for (const id of _selectedIds) {
      try {
        let ok = true;
        if (window.deleteEntry) ok = await window.deleteEntry(id);
        if (ok) {
          if (_expandedId === id) _expandedId = null;
          deleted.push(id);
        }
      } catch (e) {}
    }
    for (const id of deleted) _selectedIds.delete(id);
    if (deleted.length < count) {
      showToast(t('statusError'), true);
    }
    updateSelectionBar();
    await loadEntries();
  }
}

function updateSelectionBar() {
  const bar = document.getElementById('selectionBar');
  const countEl = document.getElementById('selectionCount');
  const mergeBtn = document.getElementById('mergeSelectedBtn');
  const page = document.getElementById('page-history');
  if (!bar) return;
  if (_selectedIds.size > 0) {
    bar.classList.remove('hidden');
    if (page) page.classList.add('selecting');
    if (countEl) countEl.textContent = _selectedIds.size;
    if (mergeBtn) mergeBtn.style.display = _selectedIds.size >= 2 ? '' : 'none';
  } else {
    bar.classList.add('hidden');
    if (page) page.classList.remove('selecting');
  }
}

function clearSelection() {
  _selectedIds.clear();
  _lastCheckedIndex = -1;
  updateSelectionBar();
  renderHistory();
}

function selectAllVisible() {
  const filtered = getFiltered();
  filtered.forEach(e => _selectedIds.add(e.id));
  updateSelectionBar();
  renderHistory();
}

async function addTag(input) {
  const id = input.dataset.id;
  const newTag = input.value.trim();
  if (!newTag) return;
  const entry = _entries.find(e => e.id === id);
  if (!entry) return;
  const tags = [...(entry.tags || [])];
  if (tags.includes(newTag)) { input.value = ''; return; }
  tags.push(newTag);
  if (window.updateEntry) {
    const ok = await window.updateEntry(id, entry.title || '', JSON.stringify(tags));
    if (ok) {
      input.value = '';
      if (!isSystemTag(newTag)) _persistCustomTag(newTag);
      await loadEntries();
      showToast(t('notebook.tag_updated'));
    } else {
      showToast(t('notebook.error_update') || 'Update failed', true);
    }
  }
}

function highlightSearch(text, query) {
  if (!query) return esc(text);
  const escaped = esc(text);
  const tokens = parseSearchTokens(query);
  if (tokens.length === 0) return escaped;
  const patterns = tokens
    .filter(tok => !tok.negate)
    .map(tok => {
      if (tok.isWildcard) {
        const p = tok.term.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '\\S*');
        return p;
      }
      return tok.term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    })
    .filter(p => p.length > 0);
  if (patterns.length === 0) return escaped;
  try {
    const regex = new RegExp('(' + patterns.join('|') + ')', 'gi');
    return escaped.replace(regex, '<mark class="search-hl">$1</mark>');
  } catch { return escaped; }
}

function toggleSearchHelp(anchor) {
  // If a popover is already open, just close it
  if (document.querySelector('.wp-popover.search-help-popover')) {
    hidePopovers();
    return;
  }

  const pop = showPopover(anchor, { className: 'search-help-popover' });
  pop.innerHTML = `
    <div class="shp-title">${t('searchHelpTitle') || 'Search Syntax'}</div>
    <table class="shp-table">
      <tr><td><code>word</code></td><td>${t('searchHelpBasic') || 'Basic search'}</td></tr>
      <tr><td><code>"exact phrase"</code></td><td>${t('searchHelpExact') || 'Exact match'}</td></tr>
      <tr><td><code>a AND b</code></td><td>${t('searchHelpAnd') || 'Both terms'}</td></tr>
      <tr><td><code>a OR b</code></td><td>${t('searchHelpOr') || 'Either term'}</td></tr>
      <tr><td><code>-word</code></td><td>${t('searchHelpNot') || 'Exclude term'}</td></tr>
      <tr><td><code>hel*</code></td><td>${t('searchHelpWild') || 'Wildcard'}</td></tr>
    </table>
  `;
}

async function removeTag(id, tagToRemove) {
  const entry = _entries.find(e => e.id === id);
  if (!entry) return;
  const tags = (entry.tags || []).filter(tag => tag !== tagToRemove);
  if (window.updateEntry) {
    const ok = await window.updateEntry(id, entry.title || '', JSON.stringify(tags));
    if (ok) {
      await loadEntries();
      showToast(t('notebook.tag_updated'));
    } else {
      showToast(t('notebook.error_update') || 'Update failed', true);
    }
  }
}

/* ── Inline Tag-Add Popover (compact mode "+" button) ──── */
function _showInlineTagPopover(x, y, entryId) {
  const pop = showPopoverAt(x, y, { className: 'tag-add-popover' });
  pop.innerHTML = `<div class="tag-input-row" style="padding:6px 8px;min-width:180px">
    ${icons.tag}
    <input type="text" class="tag-input" placeholder="${t('notebook.add_tag')}" data-id="${entryId}" autofocus />
  </div>`;
  const input = pop.querySelector('.tag-input');
  if (input) {
    setTimeout(() => input.focus(), 50);
    input.addEventListener('input', () => _showTagAutocomplete(input));
    input.addEventListener('focus', () => _showTagAutocomplete(input));
    input.addEventListener('blur', () => {
      _closeTagAutocomplete();
      setTimeout(() => hidePopovers(), 100);
    });
    input.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape') { hidePopovers(); ev.stopPropagation(); return; }
      if (ev.key === 'Enter') {
        ev.preventDefault();
        if (!_selectAutocompleteHighlight(input)) addTag(input);
        hidePopovers();
        return;
      }
      const dd = input.closest('.tag-input-row')?.querySelector('.tag-autocomplete');
      if (!dd) return;
      if (ev.key === 'ArrowDown') { ev.preventDefault(); _navigateAutocomplete(input, 1); }
      else if (ev.key === 'ArrowUp') { ev.preventDefault(); _navigateAutocomplete(input, -1); }
    });
  }
}

/* ── Delete Tag from All Entries ───────────────────────── */
async function deleteTagFromAll(tagName) {
  const msg = (t('tag_delete_confirm') || 'Remove tag "{tag}" from all entries?').replace('{tag}', tagName);
  const confirmed = await showConfirmDialog(
    t('tag_delete') || 'Delete Tag',
    msg,
    { variant: 'danger', confirmText: t('notebook.confirm_delete') }
  );
  if (!confirmed) return;
  if (window.deleteTag) {
    await window.deleteTag(tagName);
  }
  // Also remove from persisted custom tags
  const tags = window._cachedCustomTags || [];
  const idx = tags.indexOf(tagName);
  if (idx !== -1) {
    tags.splice(idx, 1);
    window._cachedCustomTags = tags;
    if (window.saveCustomTags) await window.saveCustomTags(JSON.stringify(tags));
  }
  await loadEntries();
  showToast(t('notebook.tag_updated'));
}

/* ── Sidebar "Add Tag" Button ──────────────────────────── */
function _bindSidebarAddTag() {
  const btn = document.getElementById('sidebarAddTag');
  if (!btn) return;
  btn.addEventListener('click', (ev) => {
    ev.stopPropagation();
    // Replace button with an inline input
    btn.innerHTML = `<input type="text" class="tag-input sidebar-tag-input" placeholder="${t('sidebar_add_tag_placeholder') || 'New tag name…'}" autofocus />`;
    const input = btn.querySelector('input');
    if (!input) return;
    setTimeout(() => input.focus(), 30);
    const commit = async () => {
      const val = input.value.trim();
      if (!val) { updateCounts(); return; }
      if (!/\w/.test(val)) { showToast(t('tag_name_invalid') || 'Invalid tag name', true); updateCounts(); return; }
      if (isSystemTag(val)) { showToast(t('tag_system') || 'System tag', true); updateCounts(); return; }
      const tags = window._cachedCustomTags || [];
      if (tags.includes(val)) { showToast(t('tag_exists') || 'Tag already exists', true); updateCounts(); return; }
      await _persistCustomTag(val);
      showToast(t('tag_added') || 'Tag added');
      updateCounts();
    };
    input.addEventListener('keydown', (ev2) => {
      if (ev2.key === 'Enter') { ev2.preventDefault(); commit(); }
      if (ev2.key === 'Escape') { ev2.stopPropagation(); updateCounts(); }
    });
    input.addEventListener('blur', () => updateCounts());
  });
}

/* ── Sidebar Drag & Drop Reorder ───────────────────────── */
let _dragTag = null;
function _bindSidebarDragDrop(catList) {
  catList.querySelectorAll('.tag-sidebar-item[draggable="true"]').forEach(el => {
    el.addEventListener('dragstart', (ev) => {
      _dragTag = el.dataset.tag;
      el.classList.add('dragging');
      ev.dataTransfer.effectAllowed = 'move';
      ev.dataTransfer.setData('text/plain', el.dataset.tag);
    });
    el.addEventListener('dragend', () => {
      el.classList.remove('dragging');
      _dragTag = null;
      catList.querySelectorAll('.drag-over').forEach(x => x.classList.remove('drag-over'));
    });
    el.addEventListener('dragover', (ev) => {
      ev.preventDefault();
      ev.dataTransfer.dropEffect = 'move';
      if (el.dataset.tag !== _dragTag && !isSystemTag(el.dataset.tag)) {
        el.classList.add('drag-over');
      }
    });
    el.addEventListener('dragleave', () => el.classList.remove('drag-over'));
    el.addEventListener('drop', (ev) => {
      ev.preventDefault();
      el.classList.remove('drag-over');
      const fromTag = _dragTag;
      const toTag = el.dataset.tag;
      if (!fromTag || fromTag === toTag || isSystemTag(toTag)) return;
      _reorderCustomTag(fromTag, toTag);
    });
  });
}

async function _reorderCustomTag(fromTag, toTag) {
  const tags = window._cachedCustomTags || [];
  const fromIdx = tags.indexOf(fromTag);
  const toIdx = tags.indexOf(toTag);
  if (fromIdx === -1 || toIdx === -1) return;
  // Insert before the drop target: adjust for index shift after removal
  tags.splice(fromIdx, 1);
  const adjustedIdx = fromIdx < toIdx ? toIdx - 1 : toIdx;
  tags.splice(adjustedIdx, 0, fromTag);
  window._cachedCustomTags = tags;
  if (window.saveCustomTags) {
    await window.saveCustomTags(JSON.stringify(tags));
  }
  updateCounts();
}

function showExportMenu(id, anchorEl) {
  showPopover(anchorEl, {
    items: [
      { icon: icons.files, label: t('notebook.export_txt'), action: () => doExport(id, 'txt') },
      { icon: icons.files, label: t('notebook.export_md'), action: () => doExport(id, 'md') },
    ],
  });
}

async function doExport(id, format) {
  try {
    if (window.exportEntry) {
      const result = await window.exportEntry(id, format);
      if (result) showToast(t('notebook.exported'));
    }
  } catch (e) { showToast('Export error', true); }
}

async function exportSelected() {
  if (_selectedIds.size === 0) return;
  // Show format selection via custom dialog
  const format = await showExportFormatDialog();
  if (!format) return;
  try {
    if (window.exportSelected) {
      const ids = JSON.stringify([..._selectedIds]);
      const result = await window.exportSelected(ids, format);
      if (result) showToast(t('notebook.exported'));
    }
  } catch (e) { showToast('Export error', true); }
}

function showExportFormatDialog() {
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'dialog-overlay';
    overlay.innerHTML = `
      <div class="dialog-box">
        <div class="dialog-title">${t('notebook.export')}</div>
        <div class="dialog-body" style="display:flex;gap:8px;justify-content:center">
          <button class="btn btn-secondary" data-fmt="txt">TXT</button>
          <button class="btn btn-primary" data-fmt="md">Markdown</button>
        </div>
        <div class="dialog-actions">
          <button class="btn btn-secondary dialog-cancel">${t('dialog.cancel') || 'Cancel'}</button>
        </div>
      </div>
    `;
    document.body.appendChild(overlay);

    overlay.querySelectorAll('[data-fmt]').forEach(btn => {
      btn.addEventListener('click', () => {
        overlay.remove();
        resolve(btn.dataset.fmt);
      });
    });
    overlay.querySelector('.dialog-cancel')?.addEventListener('click', () => {
      overlay.remove();
      resolve(null);
    });
    overlay.addEventListener('click', (ev) => {
      if (ev.target === overlay) { overlay.remove(); resolve(null); }
    });
  });
}
