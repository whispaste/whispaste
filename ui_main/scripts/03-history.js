/* ── History Page Logic ────────────────────────────────── */
let _entries = [];
let _activeFilter = 'all';
let _searchQuery = '';
let _currentSort = 'newest';
let _expandedId = null;
let _selectedIds = new Set();
let _lastCheckedIndex = -1;
let _acHighlight = -1;
let _acSeq = 0;

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
  if (_activeFilter === 'all') return true;
  if (_activeFilter === 'pinned') return e.pinned;
  if (_activeFilter === 'today') return isToday(e.timestamp);
  if (_activeFilter === 'week') return isThisWeek(e.timestamp);
  if (_activeFilter === 'older') return !isThisWeek(e.timestamp);
  if (_activeFilter === 'custom') {
    const fromVal = document.getElementById('dateFrom')?.value;
    const toVal = document.getElementById('dateTo')?.value;
    if (fromVal || toVal) {
      const fromDate = fromVal ? new Date(fromVal) : new Date(0);
      const toDate = toVal ? new Date(toVal + 'T23:59:59') : new Date();
      const d = new Date(e.timestamp);
      return d >= fromDate && d <= toDate;
    }
    return true;
  }
  if (_activeFilter.startsWith('cat:')) return (e.tags || []).includes(_activeFilter.slice(4));
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
  const dropdown = document.getElementById('sortDropdown');
  const trigger = document.getElementById('sortTrigger');
  const label = document.getElementById('sortLabel');
  if (!dropdown || !trigger) return;

  trigger.addEventListener('click', () => dropdown.classList.toggle('open'));

  dropdown.querySelectorAll('.sort-option').forEach(opt => {
    opt.addEventListener('click', () => {
      dropdown.querySelectorAll('.sort-option').forEach(o => o.classList.remove('active'));
      opt.classList.add('active');
      if (label) label.textContent = opt.textContent;
      dropdown.classList.remove('open');
      changeSort(opt.dataset.sort);
    });
  });

  document.addEventListener('click', (ev) => {
    if (!dropdown.contains(ev.target)) dropdown.classList.remove('open');
  });
}

function setFilter(f) {
  _activeFilter = f;
  document.querySelectorAll('.filter-item').forEach(el => {
    el.classList.toggle('active', el.dataset.filter === f);
  });
  const picker = document.getElementById('dateRangePicker');
  if (picker) picker.style.display = f === 'custom' ? '' : 'none';
  renderHistory();
}

function updateCounts() {
  const setCount = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  setCount('countAll', _entries.length);
  setCount('countPinned', _entries.filter(e => e.pinned).length);
  setCount('countToday', _entries.filter(e => isToday(e.timestamp)).length);
  setCount('countWeek', _entries.filter(e => isThisWeek(e.timestamp)).length);
  setCount('countOlder', _entries.filter(e => !isThisWeek(e.timestamp)).length);

  const filtered = getFiltered();
  setCount('countBadge', filtered.length);

  // Dynamic categories
  const cats = {};
  _entries.forEach(e => { (e.tags || []).forEach(tag => { cats[tag] = (cats[tag] || 0) + 1; }); });
  const catSection = document.getElementById('categoriesSection');
  const catList = document.getElementById('categoryList');
  if (catSection && catList) {
    if (Object.keys(cats).length > 0) {
      catSection.style.display = '';
      catList.innerHTML = Object.entries(cats).map(([name, count]) => {
        const label = name === 'merged' ? t('catMerged') : name === 'duplicated' ? t('catDuplicated') : name;
        const c = getTagColor(name);
        return `
        <div class="filter-item tag-sidebar-item${_activeFilter === 'cat:' + esc(name) ? ' active' : ''}" data-filter="cat:${esc(name)}" data-tag="${esc(name)}">
          <svg class="icon tag-icon-clr" viewBox="0 0 24 24" fill="none" stroke="${c.text}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px;flex-shrink:0"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="${c.text}"/></svg>
          <span class="filter-label" title="${esc(label)}">${esc(label)}</span>
          <span class="filter-count">${count}</span>
        </div>
      `;}).join('');
      catList.querySelectorAll('.filter-item').forEach(el => {
        el.addEventListener('click', () => setFilter(el.dataset.filter));
      });
    } else {
      catSection.style.display = 'none';
    }
  }
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

  list.innerHTML = filtered.map(e => `
    <div class="entry${e.pinned ? ' pinned' : ''}${_expandedId === e.id ? ' expanded' : ''}${_selectedIds.has(e.id) ? ' selected' : ''}" data-id="${e.id}">
      <div class="entry-header">
        <div class="entry-checkbox${_selectedIds.has(e.id) ? ' checked' : ''}" data-select-id="${e.id}"></div>
        <div style="flex:1;min-width:0">
          <div class="entry-title">${highlightSearch(e.title || e.text.substring(0, 60), _searchQuery)}</div>
          <div class="entry-meta">
            <span class="meta-item" title="${formatTime(e.timestamp)}"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> ${formatTime(e.timestamp)}</span>
            ${e.duration_sec ? '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 3l4 0"/><path d="M7 3l0 3"/><circle cx="7" cy="14" r="7"/><path d="M7 11v3h3"/></svg> ' + formatDuration(e.duration_sec) + '</span>' : ''}
            ${e.language ? '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20"/></svg> ' + e.language.toUpperCase() + '</span>' : ''}
            ${e.model ? '<span class="meta-item" title="' + esc(e.model) + (e.is_local ? ' (local)' : '') + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/></svg> ' + esc(e.model) + '</span>' : ''}
            ${(e.text || '').length > 0 ? '<span class="meta-item"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7V4h16v3"/><path d="M9 20h6"/><path d="M12 4v16"/></svg> ' + (e.text || '').split(/\\s+/).filter(Boolean).length + ' ' + t('meta_words') + '</span>' : ''}
          </div>
          <div class="entry-tags-row">
            ${(e.tags || []).map(tag => { const c = getTagColor(tag); return '<span class="tag" style="background:'+c.bg+';color:'+c.text+';border-color:'+c.border+'">' + esc(tag === 'merged' ? t('catMerged') : tag === 'duplicated' ? t('catDuplicated') : tag) + '</span>'; }).join('')}
          </div>
        </div>
        <span class="entry-chevron">${icons.chevronDown}</span>
        <div class="entry-actions">
          <button class="btn-icon copy" title="${t('notebook.copy')}" data-action="copy" data-id="${e.id}">${icons.copy}</button>
          <button class="btn-icon" title="${t('notebook.export')}" data-action="export" data-id="${e.id}">${icons.download}</button>
          <button class="btn-icon" title="${t('notebook.duplicate')}" data-action="duplicate" data-id="${e.id}">${icons.filePlus}</button>
          <button class="btn-icon pin${e.pinned ? ' active' : ''}" title="${e.pinned ? t('notebook.unpin') : t('notebook.pin')}" data-action="pin" data-id="${e.id}">${icons.pin}</button>
          <button class="btn-icon delete" title="${t('notebook.delete')}" data-action="delete" data-id="${e.id}">${icons.trash}</button>
          <button class="btn-icon" title="${t('smart.action')}" data-action="smart" data-id="${e.id}">${icons.sparkle}</button>
        </div>
      </div>
      <div class="entry-preview">${highlightSearch(e.text, _searchQuery)}</div>
      <div class="entry-full">
        <div class="entry-full-text" id="text-${e.id}">${highlightSearch(e.text, _searchQuery)}</div>
        <div class="entry-text-actions">
          <button class="btn-icon" title="${t('notebook.edit_text')}" data-action="edit-text" data-id="${e.id}">${icons.pencil}</button>
        </div>
        <div class="entry-tags-section">
          <div class="tag-chips-container">
            ${(e.tags || []).map(tag => { const c = getTagColor(tag); return `
              <span class="tag-chip" style="background:${c.bg};color:${c.text};border-color:${c.border}">
                ${esc(tag)}
                <span class="tag-chip-remove" data-remove-tag="${esc(tag)}" data-id="${e.id}">&times;</span>
              </span>
            `; }).join('')}
            <div class="tag-input-row">
              ${icons.tag}
              <input type="text" class="tag-input" placeholder="${t('notebook.add_tag')}" data-id="${e.id}" />
            </div>
          </div>
        </div>
      </div>
    </div>
  `).join('');

  // Bind entry click to expand/collapse
  list.querySelectorAll('.entry').forEach(el => {
    el.addEventListener('click', (ev) => {
      if (ev.target.closest('[data-action]') || ev.target.closest('.tag-input') || ev.target.closest('.tag-chip-remove') || ev.target.closest('.entry-checkbox') || ev.target.closest('.edit-textarea') || ev.target.closest('.entry-full-text')) return;
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
      if (window.deleteEntry) await window.deleteEntry(id);
      if (_expandedId === id) _expandedId = null;
      _selectedIds.delete(id);
    } catch (e) {}
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
    for (const id of _selectedIds) {
      try {
        if (window.deleteEntry) await window.deleteEntry(id);
        if (_expandedId === id) _expandedId = null;
      } catch (e) {}
    }
    _selectedIds.clear();
    updateSelectionBar();
    await loadEntries();
  }
}

function updateSelectionBar() {
  const bar = document.getElementById('selectionBar');
  const countEl = document.getElementById('selectionCount');
  const page = document.getElementById('page-history');
  if (!bar) return;
  if (_selectedIds.size > 0) {
    bar.classList.remove('hidden');
    if (page) page.classList.add('selecting');
    if (countEl) countEl.textContent = _selectedIds.size;
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
    await window.updateEntry(id, entry.title || '', JSON.stringify(tags));
    input.value = '';
    await loadEntries();
    showToast(t('notebook.tag_updated'));
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
  const existing = document.querySelector('.search-help-popover');
  if (existing) { existing.remove(); return; }

  const pop = document.createElement('div');
  pop.className = 'search-help-popover';
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

  const rect = anchor.getBoundingClientRect();
  pop.style.position = 'fixed';
  pop.style.top = (rect.bottom + 6) + 'px';
  pop.style.right = (window.innerWidth - rect.right) + 'px';
  pop.style.zIndex = '9999';

  document.body.appendChild(pop);

  setTimeout(() => {
    document.addEventListener('click', function closeHelp(ev) {
      if (!ev.target.closest('.search-help-popover') && !ev.target.closest('.search-help-btn')) {
        pop.remove();
        document.removeEventListener('click', closeHelp);
      }
    });
  }, 10);
}

async function removeTag(id, tagToRemove) {
  const entry = _entries.find(e => e.id === id);
  if (!entry) return;
  const tags = (entry.tags || []).filter(tag => tag !== tagToRemove);
  if (window.updateEntry) {
    await window.updateEntry(id, entry.title || '', JSON.stringify(tags));
    await loadEntries();
    showToast(t('notebook.tag_updated'));
  }
}

function showExportMenu(id, anchorEl) {
  // Remove any existing export menu
  document.querySelectorAll('.export-popover').forEach(el => el.remove());

  const menu = document.createElement('div');
  menu.className = 'export-popover';
  menu.innerHTML = `
    <button class="export-option" data-format="txt">${icons.files} ${t('notebook.export_txt')}</button>
    <button class="export-option" data-format="md">${icons.files} ${t('notebook.export_md')}</button>
  `;

  // Position near the button
  const rect = anchorEl.getBoundingClientRect();
  menu.style.position = 'fixed';
  menu.style.top = (rect.bottom + 4) + 'px';
  menu.style.right = (window.innerWidth - rect.right) + 'px';
  menu.style.zIndex = '1000';
  document.body.appendChild(menu);

  menu.querySelectorAll('.export-option').forEach(opt => {
    opt.addEventListener('click', async () => {
      menu.remove();
      await doExport(id, opt.dataset.format);
    });
  });

  // Close on outside click
  setTimeout(() => {
    document.addEventListener('click', function closeMenu(ev) {
      if (!menu.contains(ev.target)) {
        menu.remove();
        document.removeEventListener('click', closeMenu);
      }
    });
  }, 0);
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
