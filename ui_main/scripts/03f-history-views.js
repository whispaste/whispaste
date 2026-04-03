/* ── History Dashboard Views, Keyboard Nav & Grouping ── */

/* ── View Modes ──────────────────────────────────────── */
function initViewModes() {
  const btns = document.querySelectorAll('.view-btn');
  const list = document.getElementById('entriesList');
  if (!btns.length || !list) return;

  const saved = safeStorageGet('whispaste_view_mode') || 'card';
  setViewMode(saved);

  btns.forEach(btn => {
    btn.addEventListener('click', () => {
      const mode = btn.dataset.view;
      setViewMode(mode);
      safeStorageSet('whispaste_view_mode', mode);
    });
  });
}

function setViewMode(mode) {
  const list = document.getElementById('entriesList');
  const btns = document.querySelectorAll('.view-btn');
  if (!list) return;

  list.classList.remove('view-card', 'view-list', 'view-tile');
  list.classList.add('view-' + mode);

  btns.forEach(b => b.classList.toggle('active', b.dataset.view === mode));
}

/* ── Keyboard Navigation ─────────────────────────────── */
function initKeyboardNav() {
  const list = document.getElementById('entriesList');
  if (!list) return;

  document.addEventListener('keydown', (e) => {
    const historyPage = document.getElementById('page-history');
    if (!historyPage || historyPage.classList.contains('hidden')) return;
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT' || e.target.isContentEditable) return;

    const cards = Array.from(list.querySelectorAll('.entry'));
    if (!cards.length) return;

    const focused = list.querySelector('.entry.kb-focus');
    let idx = focused ? cards.indexOf(focused) : -1;

    switch (e.key) {
      case 'ArrowDown':
      case 'j':
        e.preventDefault();
        idx = Math.min(idx + 1, cards.length - 1);
        setKbFocus(cards, idx);
        break;
      case 'ArrowUp':
      case 'k':
        e.preventDefault();
        idx = Math.max(idx - 1, 0);
        setKbFocus(cards, idx);
        break;
      case 'Enter':
        if (focused) { focused.click(); }
        break;
      case ' ':
        if (focused) {
          e.preventDefault();
          const cb = focused.querySelector('.entry-checkbox');
          if (cb) { cb.click(); }
        }
        break;
      case 'p':
        if (focused) {
          const pinBtn = focused.querySelector('[data-action="pin"]');
          if (pinBtn) pinBtn.click();
        }
        break;
      case 'a':
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          if (typeof selectAllVisible === 'function') selectAllVisible();
        }
        break;
    }
  });
}

function setKbFocus(cards, idx) {
  cards.forEach(c => c.classList.remove('kb-focus'));
  if (cards[idx]) {
    cards[idx].classList.add('kb-focus');
    cards[idx].scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
}

/* ── Smart Grouping ──────────────────────────────────── */
function initGrouping() {
  const sel = document.getElementById('groupSelect');
  if (!sel) return;

  const saved = safeStorageGet('whispaste_group_mode') || 'date';
  _currentGrouping = saved;
  sel.value = saved;

  sel.addEventListener('change', () => {
    _currentGrouping = sel.value;
    safeStorageSet('whispaste_group_mode', sel.value);
    renderHistory();
  });
}

function _renderGroupedEntries(entries, groupBy) {
  const groups = _applyGrouping(entries, groupBy);
  let html = '';
  for (const group of groups) {
    const countLabel = group.entries.length === 1
      ? (t('group.entry') || 'entry')
      : (t('group.entries') || 'entries');
    const groupIds = group.entries.map(e => e.id);
    const allSelected = groupIds.every(id => _selectedIds.has(id));
    const someSelected = !allSelected && groupIds.some(id => _selectedIds.has(id));
    const cbClass = allSelected ? ' checked' : (someSelected ? ' partial' : '');
    html += `<div class="group-header"><span class="group-title">${esc(group.key)}</span><span class="group-count">${group.entries.length} ${countLabel}</span><div class="group-select-all${cbClass}" data-group-ids="${groupIds.join(',')}" title="${t('group.select_all') || 'Select all'}"></div></div>`;
    html += group.entries.map(e => _renderEntryCard(e)).join('');
  }
  return html;
}

function _applyGrouping(entries, groupBy) {
  const orderedKeys = [];
  const groups = {};

  entries.forEach(e => {
    let key;
    switch (groupBy) {
      case 'date':
        key = _formatGroupDate(e.timestamp);
        break;
      case 'project':
        key = e.project_name || (t('group.no_project') || 'No Project');
        break;
      case 'language':
        key = e.language ? e.language.toUpperCase() : (t('group.unknown') || 'Unknown');
        break;
      default:
        key = '';
    }
    if (!groups[key]) {
      groups[key] = [];
      orderedKeys.push(key);
    }
    groups[key].push(e);
  });

  return orderedKeys.map(key => ({ key, entries: groups[key] }));
}

function _formatGroupDate(timestamp) {
  const d = new Date(timestamp);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diff = Math.floor((startOfToday - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
  if (diff === 0) return t('group.today') || 'Today';
  if (diff === 1) return t('group.yesterday') || 'Yesterday';
  if (diff < 7) return t('group.this_week') || 'This Week';
  if (diff < 30) return t('group.this_month') || 'This Month';
  return d.toLocaleDateString();
}

/* ── Enhanced Selection Bar (X of Y selected) ────────── */
function _patchSelectionTotal() {
  const totalEl = document.getElementById('selectionTotal');
  if (!totalEl) return;
  if (_selectedIds.size > 0) {
    const total = getFiltered().length;
    totalEl.textContent = ' ' + (t('group.of') || 'of') + ' ' + total;
  } else {
    totalEl.textContent = '';
  }
}

/* ── Initialization ──────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
  initViewModes();
  initKeyboardNav();
  initGrouping();

  // Patch updateSelectionBar to show "X of Y"
  if (typeof updateSelectionBar === 'function') {
    const _origUpdateSelectionBar = updateSelectionBar;
    updateSelectionBar = function() {
      _origUpdateSelectionBar();
      _patchSelectionTotal();
    };
  }
});
