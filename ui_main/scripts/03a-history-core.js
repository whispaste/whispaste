/* ── History Page Logic ────────────────────────────────── */
let _entries = [];
let _activeFilters = { project: null, time: null, pinned: false, archived: false, tags: [] };
let _searchQuery = '';
let _currentSort = 'newest';
let _expandedId = null;
let _selectedIds = new Set();
let _lastCheckedIndex = -1;
let _acHighlight = -1;
let _acSeq = 0;
let _pinnedCollapsed = false;
let _pendingRetryInFlight = false;
let _projects = [];

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
  // Project filter
  if (_activeFilters.project !== null) {
    if (_activeFilters.project === '') {
      if (e.project_id && e.project_id !== '') return false;
    } else {
      if (e.project_id !== _activeFilters.project) return false;
    }
  }
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
  const tags = (e.tags || []).map(t => t.toLowerCase());
  const content = title + ' ' + text;

  const tokens = parseSearchTokens(q);

  // Split tokens into text tokens and tag tokens
  const textTokens = tokens.filter(t => !t.isTag);
  const tagTokens = tokens.filter(t => t.isTag);

  // Evaluate text tokens against content
  const textMatch = evaluateSearch(textTokens, content);

  // Evaluate tag tokens: each #tag must partially match at least one tag (AND logic)
  let tagMatch = true;
  for (const tok of tagTokens) {
    const found = tags.some(t => t.includes(tok.term));
    const matches = tok.negate ? !found : found;
    if (!matches) { tagMatch = false; break; }
  }

  return textMatch && tagMatch;
}

function parseSearchTokens(query) {
  const tokens = [];
  const regex = /"([^"]+)"|(#\S+)|(\S+)/g;
  let match;
  let expectOp = null;

  while ((match = regex.exec(query)) !== null) {
    const raw = match[1] || match[2] || match[3];
    const term = raw.toLowerCase();

    if (term === 'and' || term === '&') { expectOp = 'AND'; continue; }
    if (term === 'or' || term === '|') { expectOp = 'OR'; continue; }

    let negate = false;
    let actualTerm = term;
    let isTag = false;

    // Detect #tag syntax (supports -#tag for negation)
    if (actualTerm.startsWith('-#') || actualTerm.startsWith('!#')) {
      negate = true;
      actualTerm = actualTerm.slice(2);
      isTag = true;
    } else if (actualTerm.startsWith('#')) {
      actualTerm = actualTerm.slice(1);
      isTag = true;
    } else if (actualTerm.startsWith('-') || actualTerm.startsWith('!')) {
      negate = true;
      actualTerm = actualTerm.slice(1);
    } else if (term === 'not') {
      expectOp = 'NOT';
      continue;
    }

    if (expectOp === 'NOT') {
      negate = true;
      expectOp = null;
    }

    if (!actualTerm) continue;

    tokens.push({
      term: actualTerm,
      negate,
      op: expectOp || 'AND',
      isWildcard: !isTag && actualTerm.includes('*'),
      isTag,
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
    if (_activeFilters.archived && window.getArchivedEntries) {
      const json = await window.getArchivedEntries();
      _entries = JSON.parse(json);
      if (!_entries) _entries = [];
    } else if (window.getEntries) {
      const json = await window.getEntries();
      _entries = JSON.parse(json);
      if (!_entries) _entries = [];
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
  _updateSearchHintChips();
}

function _updateSearchHintChips() {
  const hints = document.getElementById('searchHints');
  if (!hints) return;

  // Collect top tags from current entries (max 3)
  const tagCounts = {};
  for (const e of _entries) {
    for (const tag of (e.tags || [])) {
      if (tag === 'pending') continue;
      tagCounts[tag] = (tagCounts[tag] || 0) + 1;
    }
  }
  const topTags = Object.entries(tagCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([name]) => name);

  // Keep the "today" chip, add dynamic tag chips
  const todayBtn = hints.querySelector('[data-filter="today"]');
  hints.querySelectorAll('.search-hint-chip[data-tag-chip]').forEach(el => el.remove());

  for (const tag of topTags) {
    const btn = document.createElement('button');
    btn.className = 'search-hint-chip';
    btn.dataset.tagChip = tag;
    btn.textContent = '#' + tag;
    hints.appendChild(btn);
  }

  // Hide hints entirely when no entries
  if (_entries.length === 0 && todayBtn) todayBtn.style.display = 'none';
  else if (todayBtn) todayBtn.style.display = '';
}

function _onSearchHintClick(e) {
  const chip = e.target.closest('.search-hint-chip');
  if (!chip) return;

  if (chip.dataset.filter === 'today') {
    _activeFilters.time = _activeFilters.time === 'today' ? null : 'today';
    _updateFilterUI();
    renderHistory();
  } else if (chip.dataset.tagChip) {
    const tag = chip.dataset.tagChip;
    const idx = _activeFilters.tags.indexOf(tag);
    if (idx >= 0) _activeFilters.tags.splice(idx, 1);
    else _activeFilters.tags.push(tag);
    _updateFilterUI();
    renderHistory();
  }
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

async function setFilter(f) {
  const timeFilters = ['today', 'week', 'older', 'custom'];
  if (f === 'all') {
    const wasArchived = _activeFilters.archived;
    _activeFilters = { project: _activeFilters.project, time: null, pinned: false, archived: false, tags: [] };
    if (wasArchived) { _updateFilterUI(); await loadEntries(); return; }
  } else if (f === 'pinned') {
    _activeFilters.pinned = !_activeFilters.pinned;
    if (_activeFilters.pinned && _activeFilters.archived) {
      _activeFilters.archived = false;
      _updateFilterUI();
      await loadEntries();
      return;
    }
  } else if (f === 'archived') {
    _activeFilters.archived = !_activeFilters.archived;
    if (_activeFilters.archived) _activeFilters.pinned = false;
    _updateFilterUI();
    await loadEntries();
    return;
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
  if (picker) picker.classList.toggle('hidden', _activeFilters.time !== 'custom');
  renderHistory();
}

function _getActiveFilterCount() {
  let n = 0;
  if (_activeFilters.time) n++;
  if (_activeFilters.pinned) n++;
  if (_activeFilters.archived) n++;
  n += _activeFilters.tags.length;
  return n;
}

function _hasActiveFilters() {
  return _getActiveFilterCount() > 0;
}

async function clearAllFilters() {
  const wasArchived = _activeFilters.archived;
  _activeFilters = { project: _activeFilters.project, time: null, pinned: false, archived: false, tags: [] };
  const picker = document.getElementById('dateRangePicker');
  if (picker) picker.classList.add('hidden');
  _updateFilterUI();
  renderHistory();
  if (wasArchived) await loadEntries();
}

function _updateFilterUI() {
  // Time + All items
  document.querySelectorAll('.filter-item[data-filter]').forEach(el => {
    const f = el.dataset.filter;
    if (f === 'all') {
      el.classList.toggle('active', !_hasActiveFilters());
    } else if (f === 'pinned') {
      el.classList.toggle('active', _activeFilters.pinned);
    } else if (f === 'archived') {
      el.classList.toggle('active', _activeFilters.archived);
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
      bar.classList.remove('hidden');
    } else {
      bar.classList.add('hidden');
    }
  }
}
