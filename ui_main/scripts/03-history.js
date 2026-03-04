/* ── History Page Logic ────────────────────────────────── */
let _entries = [];
let _activeFilter = 'all';
let _searchQuery = '';
let _currentSort = 'newest';
let _expandedId = null;
let _pendingDeleteId = null;
let _selectedIds = new Set();
let _lastCheckedIndex = -1;
let _pendingDeleteIds = [];

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
  if (_activeFilter.startsWith('cat:')) return e.category === _activeFilter.slice(4);
  return true;
}

function matchesSearch(e) {
  if (!_searchQuery) return true;
  const q = _searchQuery.toLowerCase();
  return (e.title || '').toLowerCase().includes(q) || (e.text || '').toLowerCase().includes(q);
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
  _entries.forEach(e => { if (e.category) cats[e.category] = (cats[e.category] || 0) + 1; });
  const catSection = document.getElementById('categoriesSection');
  const catList = document.getElementById('categoryList');
  if (catSection && catList) {
    if (Object.keys(cats).length > 0) {
      catSection.style.display = '';
      catList.innerHTML = Object.entries(cats).map(([name, count]) => `
        <div class="filter-item${_activeFilter === 'cat:' + esc(name) ? ' active' : ''}" data-filter="cat:${esc(name)}">
          ${icons.tag}
          <span>${esc(name)}</span>
          <span class="filter-count">${count}</span>
        </div>
      `).join('');
      catList.querySelectorAll('.filter-item').forEach(el => {
        el.addEventListener('click', () => setFilter(el.dataset.filter));
      });
    } else {
      catSection.style.display = 'none';
    }
  }
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
          <div class="entry-title">${esc(e.title || e.text.substring(0, 60))}</div>
          <div class="entry-meta">
            <span>${formatTime(e.timestamp)}</span>
            ${e.duration_sec ? '<span>' + formatDuration(e.duration_sec) + '</span>' : ''}
            ${e.language ? '<span>' + e.language.toUpperCase() + '</span>' : ''}
            ${e.category ? '<span class="tag">' + esc(e.category === 'merged' ? t('catMerged') : e.category) + '</span>' : ''}
          </div>
        </div>
        <div class="entry-actions">
          <button class="btn-icon copy" title="${t('notebook.copy')}" data-action="copy" data-id="${e.id}">${icons.copy}</button>
          <button class="btn-icon pin${e.pinned ? ' active' : ''}" title="${e.pinned ? t('notebook.unpin') : t('notebook.pin')}" data-action="pin" data-id="${e.id}">${icons.pin}</button>
          <button class="btn-icon delete" title="${t('notebook.delete')}" data-action="delete" data-id="${e.id}">${icons.trash}</button>
        </div>
      </div>
      <div class="entry-preview">${esc(e.text)}</div>
      <div class="entry-full">
        <div class="entry-full-text">${esc(e.text)}</div>
        <div class="entry-tags-section">
          <div class="tag-input-row">
            ${icons.tag}
            <input type="text" class="tag-input" placeholder="${t('notebook.add_tag')}" value="${esc(e.category || '')}" data-id="${e.id}" />
          </div>
        </div>
      </div>
    </div>
  `).join('');

  // Bind entry click to expand/collapse
  list.querySelectorAll('.entry').forEach(el => {
    el.addEventListener('click', (ev) => {
      if (ev.target.closest('[data-action]') || ev.target.closest('.tag-input') || ev.target.closest('.entry-checkbox')) return;
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
      else if (action === 'pin') doPin(id);
      else if (action === 'delete') confirmDelete(id);
    });
  });

  // Bind tag inputs
  list.querySelectorAll('.tag-input').forEach(input => {
    input.addEventListener('change', () => updateTag(input));
  });
}

async function doCopy(id) {
  try {
    if (window.copyEntry) await window.copyEntry(id);
    showToast(t('notebook.copied'));
  } catch (e) { showToast('Error', true); }
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
        showToast(t('mergeSuccess'), true);
        clearSelection();
        loadEntries();
      } else {
        showToast(res.error || t('statusError'), false);
      }
    } catch (e) {
      showToast(t('statusError'), false);
    }
  }
}

function confirmDelete(id) {
  _pendingDeleteIds = id ? [id] : [];
  _pendingDeleteId = id;
  const titleEl = document.getElementById('confirmTitle');
  const msgEl = document.getElementById('confirmMsg');
  if (titleEl) titleEl.textContent = t('notebook.confirm_title');
  if (msgEl) msgEl.textContent = t('notebook.confirm_msg');
  const overlay = document.getElementById('confirmOverlay');
  if (overlay) overlay.classList.add('show');
}

function confirmDeleteSelected() {
  _pendingDeleteIds = [..._selectedIds];
  _pendingDeleteId = null;
  const titleEl = document.getElementById('confirmTitle');
  const msgEl = document.getElementById('confirmMsg');
  const count = _pendingDeleteIds.length;
  if (titleEl) titleEl.textContent = t('notebook.confirm_delete_multi_title').replace('{n}', count);
  if (msgEl) msgEl.textContent = t('notebook.confirm_delete_multi_msg').replace('{n}', count);
  const overlay = document.getElementById('confirmOverlay');
  if (overlay) overlay.classList.add('show');
}

async function doDelete() {
  const ids = _pendingDeleteIds.length > 0 ? _pendingDeleteIds : (_pendingDeleteId ? [_pendingDeleteId] : []);
  for (const id of ids) {
    try {
      if (window.deleteEntry) await window.deleteEntry(id);
      if (_expandedId === id) _expandedId = null;
      _selectedIds.delete(id);
    } catch (e) {}
  }
  _pendingDeleteId = null;
  _pendingDeleteIds = [];
  const overlay = document.getElementById('confirmOverlay');
  if (overlay) overlay.classList.remove('show');
  updateSelectionBar();
  await loadEntries();
}

function cancelDelete() {
  _pendingDeleteId = null;
  _pendingDeleteIds = [];
  const overlay = document.getElementById('confirmOverlay');
  if (overlay) overlay.classList.remove('show');
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

async function updateTag(input) {
  const id = input.dataset.id;
  const tag = input.value.trim();
  const entry = _entries.find(e => e.id === id);
  if (entry && window.updateEntry) {
    await window.updateEntry(id, entry.title || '', tag);
    await loadEntries();
    showToast(t('notebook.tag_updated'));
  }
}
