async function mergeSelected() {
  if (_selectedIds.size < 2) {
    showToast(t('mergeTooFew'), false);
    return;
  }
  const btn = document.getElementById('mergeSelectedBtn');
  setLoading(btn, true);
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
    } finally {
      setLoading(btn, false);
    }
  } else {
    setLoading(btn, false);
  }
}


async function confirmDelete(id) {
  // Check if delete should archive instead
  let useArchive = false;
  try {
    if (window.getConfig) {
      const raw = await window.getConfig();
      const cfg = JSON.parse(raw);
      useArchive = cfg.delete_behavior === 'archive';
    }
  } catch (e) {}

  if (useArchive) {
    try {
      let ok = true;
      if (window.archiveEntry) ok = await window.archiveEntry(id);
      if (ok) {
        if (_expandedId === id) _expandedId = null;
        _selectedIds.delete(id);
        showToast(t('notebook.archived'), false);
      } else {
        showToast(t('statusError'), true);
      }
    } catch (e) {
      showToast(t('statusError'), true);
    }
    updateSelectionBar();
    await loadEntries();
    return;
  }

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

async function archiveSelected() {
  if (_selectedIds.size === 0) return;
  const btn = document.getElementById('archiveSelectedBtn');
  setLoading(btn, true);
  let count = 0;
  for (const id of _selectedIds) {
    try {
      if (window.archiveEntry) {
        const ok = await window.archiveEntry(id);
        if (ok) count++;
      }
    } catch (e) {}
  }
  setLoading(btn, false);
  if (count > 0) {
    const msg = _activeFilters.archived ? 'notebook.unarchive' : 'notebook.archived';
    clearSelection();
    await loadEntries();
    showToast(t(msg), false);
  }
}

async function confirmDeleteSelected() {
  const count = _selectedIds.size;
  if (count === 0) return;

  // Check if delete should archive instead
  let useArchive = false;
  try {
    if (window.getConfig) {
      const raw = await window.getConfig();
      const cfg = JSON.parse(raw);
      useArchive = cfg.delete_behavior === 'archive';
    }
  } catch (e) {}

  if (useArchive) {
    const btn = document.getElementById('deleteSelectedBtn');
    setLoading(btn, true);
    let archived = 0;
    for (const id of _selectedIds) {
      try {
        if (window.archiveEntry) {
          const ok = await window.archiveEntry(id);
          if (ok) archived++;
        }
      } catch (e) {}
    }
    setLoading(btn, false);
    if (archived > 0) {
      clearSelection();
      await loadEntries();
      showToast(t('notebook.archived'), false);
    }
    return;
  }

  const confirmed = await showConfirmDialog(
    t('notebook.confirm_delete_multi_title').replace('{n}', count),
    t('notebook.confirm_delete_multi_msg').replace('{n}', count),
    { variant: 'danger', confirmText: t('notebook.confirm_delete') }
  );
  if (confirmed) {
    const btn = document.getElementById('deleteSelectedBtn');
    setLoading(btn, true);
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
    setLoading(btn, false);
    updateSelectionBar();
    await loadEntries();
  }
}

function updateSelectionBar() {
  const bar = document.getElementById('selectionBar');
  const countEl = document.getElementById('selectionCount');
  const mergeBtn = document.getElementById('mergeSelectedBtn');
  const bulkSmartBtn = document.getElementById('bulkSmartBtn');
  const page = document.getElementById('page-history');
  if (!bar) return;
  if (_selectedIds.size > 0) {
    bar.classList.remove('hidden');
    if (page) page.classList.add('selecting');
    if (countEl) countEl.textContent = _selectedIds.size;
    const multiSelected = _selectedIds.size >= 2;
    if (mergeBtn) mergeBtn.classList.toggle('hidden', !multiSelected);
    if (bulkSmartBtn) bulkSmartBtn.classList.toggle('hidden', !multiSelected);
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


async function _showEntryMenu(id, anchorEl) {
  const entry = _entries.find(e => e.id === id);
  if (!entry) return;

  const hasAudioCached = window.hasAudio ? await window.hasAudio(id).catch(() => false) : false;
  const isPinned = entry.pinned;

  const items = [
    { icon: icons.copy, label: t('notebook.copy'), action: () => doCopy(id) },
    { icon: icons.download, label: t('notebook.export'), action: () => {
      const btn = document.querySelector(`[data-action="entry-menu"][data-id="${id}"]`);
      if (btn) showExportMenu(id, btn);
    }},
    { icon: icons.filePlus, label: t('notebook.duplicate'), action: () => doDuplicate(id) },
    { divider: true },
  ];

  if (hasAudioCached) {
    let audioCount = 1;
    if (window.getAudioCount) {
      try { audioCount = await window.getAudioCount(id); } catch(e) {}
    }

    if (audioCount > 1) {
      for (let i = 0; i < audioCount; i++) {
        const idx = i;
        const isPlaying = _playingId === id && _playingIndex === idx && _currentAudio;
        items.push({
          icon: isPlaying ? icons.stop : icons.play,
          label: isPlaying ? `${t('notebook.stop_audio')} ${idx + 1}` : `${t('notebook.play_audio')} ${idx + 1}`,
          action: () => doPlayAudioByIndex(id, idx)
        });
      }
    } else {
      const isPlaying = _playingId === id && _currentAudio;
      items.push({ icon: isPlaying ? icons.stop : icons.play, label: isPlaying ? t('notebook.stop_audio') : t('notebook.play_audio'), action: () => doPlayAudio(id) });
    }
    items.push({ icon: icons.refreshCw, label: t('notebook.retranscribe'), action: () => doReTranscribe(id, anchorEl) });
    items.push({ divider: true });
  }

  items.push({ icon: icons.pin, label: isPinned ? t('notebook.unpin') : t('notebook.pin'), action: () => doPin(id) });
  const isArchived = entry.archived;
  items.push({ icon: isArchived ? icons.archiveRestore : icons.archive, label: isArchived ? t('notebook.unarchive') : t('notebook.archive'), action: () => doArchive(id) });
  items.push({ icon: icons.sparkle, label: t('smart.action'), action: () => {
    const btn = document.querySelector(`[data-action="entry-menu"][data-id="${id}"]`);
    if (btn) showSmartActionMenu(id, btn);
  }});
  items.push({ divider: true });
  items.push({ icon: icons.trash, label: t('notebook.delete'), danger: true, action: () => confirmDelete(id) });

  showPopover(anchorEl, { items });
}

function showExportMenu(id, anchorEl) {
  showPopover(anchorEl, {
    items: [
      { icon: icons.files, label: t('notebook.export_txt'), action: () => doExport(id, 'txt') },
      { icon: icons.files, label: t('notebook.export_md'), action: () => doExport(id, 'md') },
      { icon: icons.files, label: t('notebook.export_csv'), action: () => doExport(id, 'csv') },
      { icon: icons.files, label: t('notebook.export_json'), action: () => doExport(id, 'json') },
      { icon: icons.files, label: t('notebook.export_docx'), action: () => doExport(id, 'docx') },
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
          <button class="btn btn-secondary" data-fmt="csv">CSV</button>
          <button class="btn btn-secondary" data-fmt="json">JSON</button>
          <button class="btn btn-secondary" data-fmt="docx">Word</button>
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

/* ── Project Functions ──────────────────────────────── */

async function loadProjects() {
  if (window.getProjects) {
    try {
      const data = await window.getProjects();
      _projects = JSON.parse(data || '[]');
    } catch (e) {
      _projects = [];
    }
  }
}

function renderProjectDropdown() {
  const list = document.getElementById('projectDropdownList');
  if (!list) return;

  const allCount = _entries.length;
  const noProjectCount = _entries.filter(e => !e.project_id || e.project_id === '').length;

  let html = '';

  // "All Projects" option
  html += `<div class="project-dropdown-item${_activeFilters.project === null ? ' active' : ''}" data-project-id="__all__">
    <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:14px;height:14px"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    <span>${t('notebook.all_projects')}</span>
    <span class="project-count">${allCount}</span>
  </div>`;

  // "No Project" option
  html += `<div class="project-dropdown-item${_activeFilters.project === '' ? ' active' : ''}" data-project-id="__none__">
    <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:14px;height:14px"><path d="M20 20H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2Z"/><path d="m9.5 10.5 5 5"/><path d="m14.5 10.5-5 5"/></svg>
    <span>${t('notebook.no_project')}</span>
    <span class="project-count">${noProjectCount}</span>
  </div>`;

  // Individual projects
  for (const p of _projects) {
    const count = _entries.filter(e => e.project_id === p.id).length;
    const isActive = _activeFilters.project === p.id;
    html += `<div class="project-dropdown-item${isActive ? ' active' : ''}" data-project-id="${p.id}">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:14px;height:14px"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
      <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(p.name)}</span>
      <span class="project-count">${count}</span>
      <span class="project-actions">
        <button data-project-rename="${p.id}" title="${t('notebook.rename_project')}">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px"><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/></svg>
        </button>
        <button data-project-delete="${p.id}" data-project-name="${esc(p.name)}" title="${t('notebook.delete_project')}">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:12px;height:12px"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
        </button>
      </span>
    </div>`;
  }

  // "New Project…" action
  html += `<div class="project-dropdown-item project-dropdown-add" data-project-action="add">
    <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:14px;height:14px"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
    <span>${t('notebook.new_project')}</span>
  </div>`;

  list.innerHTML = html;

  // Bind add-project handler
  list.querySelector('[data-project-action="add"]')?.addEventListener('click', async (e) => {
    e.stopPropagation();
    toggleProjectDropdown(false);
    const name = await showPromptDialog(t('notebook.new_project'), t('notebook.project_name'));
    if (!name) return;
    if (window.createProject) {
      try {
        const result = await window.createProject(name);
        showToast(t('notebook.project_created'));
        await loadProjects();
        renderProjectDropdown();
        renderHistory();
      } catch (err) {
        showToast(err.message || t('notebook.error_update'), true);
      }
    }
  });

  // Bind click handlers
  list.querySelectorAll('.project-dropdown-item').forEach(item => {
    item.addEventListener('click', (e) => {
      if (e.target.closest('[data-project-rename]') || e.target.closest('[data-project-delete]') || e.target.closest('[data-project-action]')) return;

      const pid = item.dataset.projectId;
      if (pid === '__all__') {
        _activeFilters.project = null;
      } else if (pid === '__none__') {
        _activeFilters.project = '';
      } else {
        _activeFilters.project = pid;
      }

      if (window.setLastProjectID) {
        window.setLastProjectID(pid === '__all__' ? '' : (pid === '__none__' ? '__none__' : pid));
      }

      if (window.setActiveProject) {
        const activePid = _activeFilters.project;
        window.setActiveProject(activePid && activePid !== '__all__' ? activePid : '');
      }

      // Clear tag filters — available tags change per project
      _activeFilters.tags = [];

      updateProjectLabel();
      toggleProjectDropdown(false);
      renderHistory();
    });
  });

  // Bind rename handlers
  list.querySelectorAll('[data-project-rename]').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const pid = btn.dataset.projectRename;
      const project = _projects.find(p => p.id === pid);
      if (!project) return;

      const newName = await showPromptDialog(t('notebook.rename_project'), t('notebook.project_name'), { defaultValue: project.name });
      if (!newName || newName === project.name) return;

      if (window.renameProject) {
        const ok = await window.renameProject(pid, newName);
        if (ok) {
          showToast(t('notebook.project_renamed'));
          await loadProjects();
          renderProjectDropdown();
          updateProjectLabel();
        }
      }
    });
  });

  // Bind delete handlers
  list.querySelectorAll('[data-project-delete]').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const pid = btn.dataset.projectDelete;
      const pname = btn.dataset.projectName;
      await showDeleteProjectDialog(pname, pid);
    });
  });
}

async function showDeleteProjectDialog(name, id) {
  const msg = t('notebook.delete_project_confirm').replace('{name}', esc(name));
  const checkboxLabel = t('notebook.delete_project_entries');

  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'dialog-overlay';
    overlay.innerHTML = `
      <div class="dialog-box">
        <div class="dialog-title">${t('notebook.delete_project')}</div>
        <div class="dialog-body">
          <p>${msg}</p>
          <label style="display:flex;align-items:center;gap:8px;margin-top:12px;font-size:13px;cursor:pointer">
            <input type="checkbox" id="deleteProjectEntries" style="accent-color:var(--accent)">
            <span>${checkboxLabel}</span>
          </label>
        </div>
        <div class="dialog-actions">
          <button class="btn btn-secondary dialog-cancel">${t('notebook.confirm_cancel')}</button>
          <button class="btn btn-danger dialog-confirm">${t('notebook.delete_project')}</button>
        </div>
      </div>
    `;
    document.body.appendChild(overlay);

    overlay.querySelector('.dialog-cancel').onclick = () => {
      overlay.remove();
      resolve(false);
    };

    overlay.querySelector('.dialog-confirm').onclick = async () => {
      const deleteEntries = document.getElementById('deleteProjectEntries')?.checked || false;
      overlay.remove();

      if (window.deleteProject) {
        const ok = await window.deleteProject(id, deleteEntries);
        if (ok) {
          showToast(t('notebook.project_deleted'));
          if (_activeFilters.project === id) {
            _activeFilters.project = null;
            if (window.setLastProjectID) window.setLastProjectID('');
            if (window.setActiveProject) window.setActiveProject('');
          }
          await loadProjects();
          await loadEntries();
          renderProjectDropdown();
          updateProjectLabel();
        }
      }
      resolve(true);
    };

    overlay.addEventListener('click', (ev) => {
      if (ev.target === overlay) {
        overlay.remove();
        resolve(false);
      }
    });
  });
}

function updateProjectLabel() {
  const label = document.getElementById('projectLabel');
  if (!label) return;

  if (_activeFilters.project === null) {
    label.textContent = t('notebook.all_projects');
  } else if (_activeFilters.project === '') {
    label.textContent = t('notebook.no_project');
  } else {
    const project = _projects.find(p => p.id === _activeFilters.project);
    label.textContent = project ? project.name : t('notebook.all_projects');
  }
}

function toggleProjectDropdown(show) {
  const list = document.getElementById('projectDropdownList');
  const selector = document.getElementById('projectSelector');
  if (!list || !selector) return;

  if (show === undefined) {
    show = list.classList.contains('hidden');
  }

  list.classList.toggle('hidden', !show);
  selector.classList.toggle('open', show);

  if (show) {
    renderProjectDropdown();
  }
}

function initSidebarResize() {
  const handle = document.getElementById('sidebarResizeHandle');
  const sidebar = document.querySelector('.filter-sidebar');
  if (!handle || !sidebar) return;

  // Restore saved width from config
  if (window.getSidebarWidth) {
    window.getSidebarWidth().then(w => {
      if (w >= 140 && w <= 360) sidebar.style.width = w + 'px';
    }).catch(() => {});
  }

  let startX, startWidth;

  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();
    startX = e.clientX;
    startWidth = sidebar.getBoundingClientRect().width;
    handle.classList.add('dragging');
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';

    const onMouseMove = (e) => {
      const dx = e.clientX - startX;
      const newWidth = Math.min(360, Math.max(140, startWidth + dx));
      sidebar.style.width = newWidth + 'px';
    };

    const onMouseUp = () => {
      handle.classList.remove('dragging');
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      const finalWidth = Math.round(sidebar.getBoundingClientRect().width);
      if (window.setSidebarWidth) window.setSidebarWidth(finalWidth);
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };

    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  });
}

async function initProjectSelector() {
  await loadProjects();

  // Restore last project selection
  if (window.getLastProjectID) {
    try {
      const lastId = await window.getLastProjectID();
      if (lastId === '__none__') {
        _activeFilters.project = '';
      } else if (lastId && lastId !== '') {
        if (_projects.find(p => p.id === lastId)) {
          _activeFilters.project = lastId;
        }
      }

      // Sync active project to Go backend for auto-assign
      if (window.setActiveProject) {
        const activePid = _activeFilters.project;
        window.setActiveProject(activePid && activePid !== '__all__' ? activePid : '');
      }

      updateProjectLabel();
    } catch (e) { /* ignore */ }
  }

  // Toggle dropdown on trigger click
  document.getElementById('projectTrigger')?.addEventListener('click', () => {
    toggleProjectDropdown();
  });

  // Close dropdown on outside click
  document.addEventListener('click', (e) => {
    const selector = document.getElementById('projectSelector');
    if (selector && !selector.contains(e.target)) {
      toggleProjectDropdown(false);
    }
  });
}

async function showProjectAssignDialog(entryId) {
  await loadProjects();

  const entry = _entries.find(e => e.id === entryId);
  const currentPid = entry?.project_id || '';

  const noProjectIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/></svg>';
  const folderIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>';

  const items = [
    { label: t('notebook.no_project'), value: '', icon: noProjectIcon },
    ..._projects.map(p => ({ label: p.name, value: p.id, icon: folderIcon }))
  ];

  const selected = await showListDialog(t('notebook.assign_project'), items, { selectedValue: currentPid });
  if (selected === null) return;

  if (window.setEntryProject) {
    try {
      await window.setEntryProject(entryId, selected);
      showToast(t('notebook.project_updated'));
      await loadEntries();
    } catch (err) {
      showToast(err.message || t('notebook.error_update'), true);
    }
  }
}

async function assignSelectedToProject() {
  if (_selectedIds.size === 0) return;

  await loadProjects();

  const noProjectIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/></svg>';
  const folderIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>';

  const items = [
    { label: t('notebook.no_project'), value: '', icon: noProjectIcon },
    ..._projects.map(p => ({ label: p.name, value: p.id, icon: folderIcon }))
  ];

  const selected = await showListDialog(t('notebook.assign_project'), items);
  if (selected === null) return;

  if (window.setEntriesProject) {
    const ids = Array.from(_selectedIds);
    const ok = await window.setEntriesProject(JSON.stringify(ids), selected);
    if (ok) {
      showToast(t('notebook.project_updated'));
      clearSelection();
      await loadEntries();
    }
  }
}