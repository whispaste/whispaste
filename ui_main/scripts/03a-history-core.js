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
let _currentGrouping = 'date';

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
    await updateDashboardGreeting();
    checkMilestone(_entries.length);
  } catch (outerErr) {
    console.warn('loadEntries error:', outerErr);
  }
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

function _sortArrow(value) {
  return value === 'oldest' ? ' ↑' : ' ↓';
}

function _updateSortLabel(label, i18nKey, value) {
  if (!label) return;
  label.innerHTML = '';
  label.appendChild(document.createTextNode(t(i18nKey)));
  const arrow = document.createElement('span');
  arrow.className = 'sort-arrow';
  arrow.textContent = _sortArrow(value);
  label.appendChild(arrow);
}

function initSortDropdown() {
  const trigger = document.getElementById('sortTrigger');
  const label = document.getElementById('sortLabel');
  if (!trigger) return;

  const sortOptions = [
    { value: 'newest', i18n: 'notebook.sort_newest' },
    { value: 'oldest', i18n: 'notebook.sort_oldest' },
    { value: 'alpha',  i18n: 'notebook.sort_alpha' },
    { value: 'duration', i18n: 'notebook.sort_duration' },
  ];

  // Set initial arrow on the default sort
  const initial = sortOptions.find(o => o.value === _currentSort);
  if (initial) _updateSortLabel(label, initial.i18n, initial.value);

  trigger.addEventListener('click', () => {
    const items = [];
    for (const opt of sortOptions) {
      items.push({
        label: t(opt.i18n),
        checked: _currentSort === opt.value,
        action: () => {
          _currentSort = opt.value;
          _updateSortLabel(label, opt.i18n, opt.value);
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
  _renderActiveFilters();
}

function _renderActiveFilters() {
  const container = document.getElementById('activeFilters');
  if (!container) return;

  const pills = [];
  const timeLabels = {
    today: 'notebook.today',
    week: 'notebook.week',
    older: 'notebook.older',
    custom: 'notebook.custom_range',
  };

  if (_activeFilters.pinned) {
    pills.push({ label: t('notebook.pinned'), remove: () => setFilter('pinned') });
  }
  if (_activeFilters.archived) {
    pills.push({ label: t('notebook.archived'), remove: () => setFilter('archived') });
  }
  if (_activeFilters.time && timeLabels[_activeFilters.time]) {
    const timeKey = _activeFilters.time;
    pills.push({ label: t(timeLabels[timeKey]), remove: () => setFilter(timeKey) });
  }
  for (const tag of _activeFilters.tags) {
    pills.push({ label: '#' + tag, remove: () => setFilter('cat:' + tag) });
  }

  container.innerHTML = '';
  for (const pill of pills) {
    const span = document.createElement('span');
    span.className = 'filter-pill';
    span.textContent = pill.label + ' ';
    const btn = document.createElement('button');
    btn.className = 'filter-pill-remove';
    btn.type = 'button';
    btn.innerHTML = '&times;';
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      pill.remove();
    });
    span.appendChild(btn);
    container.appendChild(span);
  }
}

/* ── Collapsible Sidebar Sections ──────────────────────── */
const _COLLAPSE_KEY = 'whispaste_sidebar_collapsed';

function _getSidebarCollapseState() {
  try { return JSON.parse(localStorage.getItem(_COLLAPSE_KEY) || '{}'); } catch { return {}; }
}

function _setSidebarCollapseState(section, collapsed) {
  const state = _getSidebarCollapseState();
  state[section] = collapsed;
  safeStorageSet(_COLLAPSE_KEY, JSON.stringify(state));
}

function _toggleSidebarSection(sectionEl) {
  const key = sectionEl.dataset.section;
  if (!key) return;
  const isCollapsed = sectionEl.classList.toggle('collapsed');
  const header = sectionEl.querySelector('.sidebar-section-header');
  if (header) header.setAttribute('aria-expanded', String(!isCollapsed));
  _setSidebarCollapseState(key, isCollapsed);
  _updateSidebarSectionCounts();
}

function _updateSidebarSectionCounts() {
  // Filter section count: number of filter items (excluding "All" and custom range)
  const filterSection = document.getElementById('sidebarSectionFilters');
  const filterCountEl = document.getElementById('filterSectionCount');
  if (filterSection && filterCountEl) {
    const items = filterSection.querySelectorAll('.filter-item');
    filterCountEl.textContent = items.length;
  }
  // Tags section count: number of tag items
  const tagsSection = document.getElementById('sidebarSectionTags');
  const tagsCountEl = document.getElementById('tagsSectionCount');
  if (tagsSection && tagsCountEl) {
    const items = tagsSection.querySelectorAll('#categoryList .filter-item');
    tagsCountEl.textContent = items.length || '';
  }
}

function _initSidebarCollapse() {
  const state = _getSidebarCollapseState();
  document.querySelectorAll('.sidebar-section[data-section]').forEach(section => {
    const key = section.dataset.section;
    if (state[key]) {
      section.classList.add('collapsed');
      const header = section.querySelector('.sidebar-section-header');
      if (header) header.setAttribute('aria-expanded', 'false');
    }
    const header = section.querySelector('.sidebar-section-header');
    if (header) {
      header.addEventListener('click', () => _toggleSidebarSection(section));
      header.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          _toggleSidebarSection(section);
        }
      });
    }
  });
  _updateSidebarSectionCounts();
  // Re-count tags when the category list changes
  const catList = document.getElementById('categoryList');
  if (catList) {
    new MutationObserver(() => _updateSidebarSectionCounts())
      .observe(catList, { childList: true });
  }
}

/* ── Sidebar Hide/Show Toggle ──────────────────────────── */
const _SIDEBAR_HIDDEN_KEY = 'whispaste_sidebar_hidden';

function _initSidebarToggle() {
  const sidebar = document.querySelector('.filter-sidebar');
  const collapseBtn = document.getElementById('sidebarCollapseBtn');
  const expandBtn = document.getElementById('sidebarExpandBtn');
  if (!sidebar || !collapseBtn || !expandBtn) return;

  const hidden = safeStorageGet(_SIDEBAR_HIDDEN_KEY) === 'true';
  if (hidden) {
    sidebar.classList.add('sidebar-hidden');
    expandBtn.classList.remove('hidden');
  }

  collapseBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    sidebar.classList.add('sidebar-hidden');
    expandBtn.classList.remove('hidden');
    safeStorageSet(_SIDEBAR_HIDDEN_KEY, 'true');
  });

  expandBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    sidebar.classList.remove('sidebar-hidden');
    expandBtn.classList.add('hidden');
    safeStorageSet(_SIDEBAR_HIDDEN_KEY, 'false');
  });
}

/* ── Dashboard Greeting ────────────────────────────────── */
async function updateDashboardGreeting() {
  const el = document.getElementById('dashboardGreeting');
  if (!el) return;

  const hour = new Date().getHours();
  const day = new Date().getDay();
  const isWeekend = day === 0 || day === 6;

  // Use real statistics from daily_stats table, not loaded UI items
  let todayCount = 0;
  try {
    if (window.getAnalytics) {
      const raw = await window.getAnalytics(1);
      const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (data && data.dailyCounts) {
        const now = new Date();
        const todayStr = now.getFullYear() + '-' +
          String(now.getMonth() + 1).padStart(2, '0') + '-' +
          String(now.getDate()).padStart(2, '0');
        todayCount = data.dailyCounts[todayStr] || 0;
      }
    }
  } catch (_) {
    todayCount = _entries.filter(e => isToday(e.timestamp)).length;
  }

  let greetKey;
  if (hour < 12) greetKey = 'greeting.morning';
  else if (hour < 17) greetKey = 'greeting.afternoon';
  else greetKey = 'greeting.evening';

  let greetText = t(greetKey);

  let suffix = '';
  if (todayCount === 0) {
    if (isWeekend) {
      suffix = t('greeting.weekend');
    } else if (hour < 9) {
      suffix = t('greeting.earlybird');
    } else {
      suffix = t('greeting.ready');
    }
  } else if (todayCount === 1) {
    suffix = todayCount + ' ' + t('greeting.recording') + ' ' + t('greeting.today_suffix');
  } else if (todayCount < 10) {
    suffix = todayCount + ' ' + t('greeting.recordings') + ' ' + t('greeting.today_suffix');
  } else {
    suffix = t('greeting.productive').replace('{count}', todayCount);
  }

  el.textContent = suffix ? (greetText + ' — ' + suffix) : greetText;
}

/* ── Empty State Toggle ───────────────────────────────── */
function toggleEmptyState() {
  const el = document.getElementById('emptyState');
  const entriesList = document.getElementById('entriesList');
  if (!el) return;
  const hasEntries = _entries.length > 0;
  el.classList.toggle('hidden', hasEntries);
  if (entriesList) entriesList.classList.toggle('hidden', !hasEntries);
}
