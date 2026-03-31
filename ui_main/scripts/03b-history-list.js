function updateCounts() {
  const setCount = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  // Scope counts to active project
  const scoped = _activeFilters.project !== null
    ? _entries.filter(e => {
        if (_activeFilters.project === '') return !e.project_id || e.project_id === '';
        return e.project_id === _activeFilters.project;
      })
    : _entries;
  setCount('countAll', scoped.length);
  setCount('countPinned', scoped.filter(e => e.pinned).length);
  setCount('countToday', scoped.filter(e => isToday(e.timestamp)).length);
  setCount('countWeek', scoped.filter(e => isThisWeek(e.timestamp)).length);
  setCount('countOlder', scoped.filter(e => !isThisWeek(e.timestamp)).length);

  // Archived count (separate query since archived entries are loaded from different endpoint)
  if (window.getArchivedCount) {
    window.getArchivedCount().then(c => setCount('countArchived', c));
  }

  // Dynamic categories (always include persisted custom tags with count 0)
  const cats = {};
  _loadCustomTagsInto(cats);
  scoped.forEach(e => { (e.tags || []).forEach(tag => { cats[tag] = (cats[tag] || 0) + 1; }); });
  const catSection = document.getElementById('categoriesSection');
  const catList = document.getElementById('categoryList');
  if (catSection && catList) {
    if (Object.keys(cats).length > 0 || true) {
      catSection.classList.remove('hidden');

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
        tagListHTML += systemEntries.map(([name, count]) => {
          const label = systemTagLabel(name);
          const c = getTagColor(name);
          const sidebarIcon = name === 'pending'
            ? `<svg class="icon tag-icon-clr" viewBox="0 0 24 24" fill="none" stroke="${c.text}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px;flex-shrink:0"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`
            : `<svg class="icon tag-icon-clr" viewBox="0 0 24 24" fill="none" stroke="${c.text}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px;flex-shrink:0"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
          return `
          <div class="filter-item tag-sidebar-item${_activeFilters.tags.includes(name) ? ' active' : ''} system-tag-item" data-filter="cat:${esc(name)}" data-tag="${esc(name)}">
            ${sidebarIcon}
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
      _bindEntryToTagDrop(catList);
      const headerAdd = document.getElementById('sidebarAddTagHeader');
      if (headerAdd) {
        headerAdd.onclick = (ev) => {
          ev.stopPropagation();
          const bottomBtn = document.getElementById('sidebarAddTag');
          if (bottomBtn) {
            bottomBtn.scrollIntoView({ behavior: 'smooth', block: 'end' });
            setTimeout(() => bottomBtn.click(), 200); // DevSkim: ignore DS172411 — constant delay, safe callback
          }
        };
      }
    } else {
      catSection.classList.add('hidden');
    }
  }
  _updateFilterUI();
}

// Load persisted custom tags into the cats map with count 0 if not already present.

// Re-render sidebar tags when any tag mutation occurs elsewhere
window.addEventListener('tags-changed', () => { updateCounts(); });

function _renderEntryCard(e) {
  const isPending = (e.tags || []).includes('pending');
  return `
    <div class="entry${e.pinned ? ' pinned' : ''}${isPending ? ' pending' : ''}${_expandedId === e.id ? ' expanded' : ''}${_selectedIds.has(e.id) ? ' selected' : ''}" data-id="${e.id}" draggable="true">
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
        <div class="entry-actions">
          <button class="btn-icon copy" title="${t('notebook.copy')}" data-action="copy" data-id="${e.id}">${icons.copy}</button>
          <button class="btn-icon entry-more" title="${t('notebook.more_actions')}" data-action="entry-menu" data-id="${e.id}">${icons.moreVertical}</button>
        </div>
      </div>
      <div class="entry-preview-row"><div class="entry-preview">${isPending && !e.text ? '<span class="pending-hint">' + icons.refreshCw + ' ' + t('pending_transcription') + '</span>' : highlightSearch(e.text, _searchQuery)}</div><span class="entry-preview-chevron">${icons.chevronDown}</span></div>
      <div class="entry-tags-row">
        ${(e.project_id && e.project_name) ? `<span class="project-badge" data-entry-id="${e.id}" title="${t('notebook.assign_project')}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>${esc(e.project_name)}</span>` : `<span class="project-badge project-badge-empty" data-entry-id="${e.id}" title="${t('notebook.assign_project')}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>${t('notebook.project')}</span>`}
        ${(e.tags || []).map(tag => { const c = getTagColor(tag); const sys = isSystemTag(tag); const lbl = systemTagLabel(tag); return `<span class="tag${sys ? ' system-tag' : ''}" data-tag="${esc(tag)}" data-id="${e.id}" style="background:${c.bg};color:${c.text};border-color:${c.border}">${sys ? systemTagIcon(tag) : ''}${esc(lbl)}${sys ? '' : '<span class="tag-remove" data-remove-tag="' + esc(tag) + '" data-id="' + e.id + '">&times;</span>'}</span>`; }).join('')}
        <div class="tag-input-row tag-input-expanded" data-id="${e.id}">
          ${icons.tag}
          <input type="text" class="tag-input" placeholder="${t('notebook.add_tag')}" data-id="${e.id}" />
        </div>
      </div>
      <div class="entry-full">
        <div class="entry-full-text" id="text-${e.id}">${highlightSearch(e.text, _searchQuery)}</div>
        <div class="entry-text-actions">
          <button class="btn-icon" title="${t('notebook.edit_text')}" data-action="edit-text" data-id="${e.id}">${icons.pencil}</button>
        </div>

      </div>
    </div>`;
}

function startHistoryFirstDictation() {
  showToast(t('notebook.empty_recording_start'));
  if (window.startCapture) window.startCapture();
}

function openSmartModeFromEmptyState() {
  switchPage('smartmode');
}

function openSettingsFromEmptyState() {
  switchPage('settings');
}

function renderHistory() {
  const list = document.getElementById('entriesList');
  if (!list) return;
  const filtered = getFiltered();
  updateCounts();
  const searchEmptyIcon = `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>`;

  if (_entries.length === 0) {
    list.innerHTML = `<div class="empty-state">${icons.microphone}<div class="empty-state-title">${t('notebook.empty_title')}</div><p class="empty-state-text">${t('notebook.empty')}</p><div class="empty-state-actions"><button class="btn btn-primary" onclick="startHistoryFirstDictation()">${t('notebook.empty_action_record')}</button><button class="btn btn-secondary" onclick="openSmartModeFromEmptyState()">${t('notebook.empty_action_smart')}</button><button class="btn btn-secondary" onclick="openSettingsFromEmptyState()">${t('notebook.empty_action_settings')}</button></div></div>`;
    return;
  }
  if (filtered.length === 0) {
    list.innerHTML = `<div class="empty-state">${searchEmptyIcon}<div class="empty-state-title">${t('notebook.no_results_title')}</div><p class="empty-state-text">${t('notebook.no_results')}</p></div>`;
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
    el.addEventListener('click', async (ev) => {
      if (ev.target.closest('[data-action]') || ev.target.closest('.tag-input') || ev.target.closest('.tag-chip-remove') || ev.target.closest('.entry-checkbox') || ev.target.closest('.edit-textarea') || ev.target.closest('.entry-full-text') || ev.target.closest('.project-badge')) return;
      const id = el.dataset.id;
      // Pending entries: click triggers re-transcription instead of expand
      if (el.classList.contains('pending') && !_pendingRetryInFlight) {
        _pendingRetryInFlight = true;
        const hasAudio = window.hasAudio ? await window.hasAudio(id).catch(() => false) : false;
        if (hasAudio) {
          const hint = el.querySelector('.pending-hint');
          if (hint) {
            doReTranscribe(id, hint);
            return;
          }
        }
        _pendingRetryInFlight = false;
      }
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
      else if (action === 'entry-menu') _showEntryMenu(id, btn);
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
      const dd = document.querySelector('.tag-autocomplete[data-for-id="' + input.dataset.id + '"]');
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

  // Bind tag remove buttons
  list.querySelectorAll('.tag-remove').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      removeTag(btn.dataset.id, btn.dataset.removeTag);
    });
  });

  // Bind project badge click → inline project assignment
  list.querySelectorAll('.project-badge').forEach(badge => {
    badge.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const entryId = badge.dataset.entryId;
      if (entryId) showProjectAssignDialog(entryId);
    });
  });

  // Bind entry drag-to-tag
  list.querySelectorAll('.entry[draggable="true"]').forEach(el => {
    el.addEventListener('dragstart', (ev) => {
      // Suppress drag when editing text inside the entry
      if (el.querySelector('.edit-textarea')) {
        ev.preventDefault();
        return;
      }
      ev.dataTransfer.effectAllowed = 'link';
      ev.dataTransfer.setData('text/x-entry-drag', el.dataset.id);
      el.classList.add('dragging');
    });
    el.addEventListener('dragend', () => {
      el.classList.remove('dragging');
      document.querySelectorAll('.tag-drop-target, .drag-over-top, .drag-over-bottom').forEach(x => x.classList.remove('tag-drop-target', 'drag-over-top', 'drag-over-bottom'));
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
