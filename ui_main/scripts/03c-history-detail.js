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
      window.dispatchEvent(new Event('tags-changed'));
    }
  } catch (_) {}
}

/* ── Tag Autocomplete ─────────────────────────────────── */
async function _fetchCategories() {
  try {
    const cats = window.getCategories ? JSON.parse(await window.getCategories()) : [];
    // Merge custom tags so zero-count tags appear in autocomplete
    const custom = window._cachedCustomTags || [];
    custom.forEach(tag => { if (!cats.includes(tag)) cats.push(tag); });
    return cats;
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
    // Sort by sidebar order (_cachedCustomTags)
    const order = window._cachedCustomTags || [];
    filtered.sort((a, b) => {
      const ia = order.indexOf(a);
      const ib = order.indexOf(b);
      return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
    });
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
    // Position fixed relative to viewport to escape stacking contexts
    const rect = row.getBoundingClientRect();
    dd.style.position = 'fixed';
    dd.style.top = (rect.bottom + 4) + 'px';
    dd.style.left = rect.left + 'px';
    dd.style.width = rect.width + 'px';
    document.body.appendChild(dd);

    // Close on scroll so the dropdown doesn't float detached
    const scrollParent = row.closest('.entries-area');
    if (scrollParent) {
      scrollParent.addEventListener('scroll', () => _closeTagAutocomplete(), { once: true, passive: true });
    }
  });
}

function _closeTagAutocomplete() {
  document.querySelectorAll('.tag-autocomplete').forEach(el => el.remove());
  _acHighlight = -1;
}

function _navigateAutocomplete(input, direction) {
  const dd = document.querySelector('.tag-autocomplete[data-for-id="' + input.dataset.id + '"]');
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
  const dd = document.querySelector('.tag-autocomplete[data-for-id="' + input.dataset.id + '"]');
  if (!dd) return false;
  const active = dd.querySelector('.tag-autocomplete-item.active');
  if (!active) return false;
  input.value = active.textContent;
  _closeTagAutocomplete();
  addTag(input);
  return true;
}


async function doCopy(id, triggerBtn) {
  if (!triggerBtn) {
    // Fallback: direct copy when no anchor for menu
    try {
      if (window.copyEntry) await window.copyEntry(id);
      showToast(t('notebook.copied'));
    } catch (e) { showToast(t('statusError'), true); }
    return;
  }
  showPopover(triggerBtn, {
    items: [
      { icon: icons.copy, label: t('notebook.copy_text'), action: async () => {
        try {
          if (window.copyEntry) await window.copyEntry(id);
          showCopyFeedback(triggerBtn);
        } catch (e) { showToast(t('statusError'), true); }
      }},
      { icon: icons.files, label: t('notebook.copy_markdown'), action: async () => {
        try {
          if (window.copyEntryMarkdown) await window.copyEntryMarkdown(id);
          showCopyFeedback(triggerBtn);
        } catch (e) { showToast(t('statusError'), true); }
      }},
    ],
  });
}

function showCopyFeedback(button) {
  const parent = button.parentElement;
  const existing = parent.querySelector('.copy-feedback');
  if (existing) existing.remove();

  const feedback = document.createElement('span');
  feedback.className = 'copy-feedback';
  feedback.textContent = '\u2713 ' + t('notebook.copied');
  parent.style.position = 'relative';
  parent.appendChild(feedback);

  requestAnimationFrame(() => feedback.classList.add('show'));

  setTimeout(() => {
    feedback.classList.add('fade-out');
    setTimeout(() => feedback.remove(), 300);
  }, 1500);
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

async function doArchive(id) {
  if (window.archiveEntry) {
    const entry = _entries.find(e => e.id === id);
    const wasArchived = entry && entry.archived;
    const ok = await window.archiveEntry(id);
    if (ok) {
      await loadEntries();
      showToast(t(wasArchived ? 'notebook.unarchive' : 'notebook.archived'), false);
    }
  }
}

// Audio playback state

function startEditText(id) {
  const textEl = document.getElementById('text-' + id);
  const actionsEl = textEl?.nextElementSibling;
  if (!textEl) return;
  const entryEl = textEl.closest('.entry');
  if (entryEl) entryEl.setAttribute('draggable', 'false');
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
    if (window.updateEntryText) await window.updateEntryText(id, newText, '');
    showToast(t('notebook.saved'));
    await loadEntries();
  } catch (e) { showToast(t('statusError'), true); }
}

function cancelEditText(id) {
  loadEntries();
}

// Focus the contenteditable title in the header
function focusDetailTitle(id) {
  const titleEl = document.querySelector('.entry-title[data-entry-id="' + id + '"]');
  if (titleEl) {
    titleEl.focus();
    const range = document.createRange();
    range.selectNodeContents(titleEl);
    range.collapse(false);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }
}

// Inline title editing on card view (non-expanded)
function startEditTitleCard(id, btn) {
  const entry = _entries.find(e => e.id === id);
  if (!entry) return;
  const wrapper = btn.closest('.entry-title-wrapper');
  if (!wrapper) return;
  const titleSpan = wrapper.querySelector('.entry-title');
  if (!titleSpan) return;

  const original = entry.title || entry.text.substring(0, 60);
  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'edit-title-input';
  input.value = original;

  titleSpan.replaceWith(input);
  btn.style.display = 'none';
  input.focus();
  input.select();

  let saved = false;
  const save = async () => {
    if (saved) return;
    saved = true;
    const newTitle = input.value.trim();
    if (newTitle && newTitle !== original) {
      const ok = await window.updateEntry(id, newTitle, JSON.stringify(entry.tags || []));
      if (ok) {
        entry.title = newTitle;
        showToast(t('notebook.saved'));
      }
    }
    await loadEntries();
  };

  input.addEventListener('blur', save);
  input.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') { ev.preventDefault(); input.blur(); }
    if (ev.key === 'Escape') { input.value = original; input.blur(); }
  });
  input.addEventListener('click', (ev) => ev.stopPropagation());
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

/* ── Delete Tag from All Entries───────────────────────── */
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
  window.dispatchEvent(new Event('tags-changed'));
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
    setTimeout(() => input.focus(), 30); // DevSkim: ignore DS172411 — constant delay, safe callback
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
      ev.dataTransfer.setData('text/x-tag-reorder', el.dataset.tag);
    });
    el.addEventListener('dragend', () => {
      el.classList.remove('dragging');
      _dragTag = null;
      catList.querySelectorAll('.drag-over-top, .drag-over-bottom').forEach(x => {
        x.classList.remove('drag-over-top', 'drag-over-bottom');
      });
    });
    el.addEventListener('dragover', (ev) => {
      if (!_dragTag) return; // only handle tag reorder, not entry drags
      ev.preventDefault();
      ev.dataTransfer.dropEffect = 'move';
      if (el.dataset.tag === _dragTag || isSystemTag(el.dataset.tag)) return;
      const rect = el.getBoundingClientRect();
      const midY = rect.top + rect.height / 2;
      el.classList.remove('drag-over-top', 'drag-over-bottom');
      if (ev.clientY < midY) {
        el.classList.add('drag-over-top');
      } else {
        el.classList.add('drag-over-bottom');
      }
    });
    el.addEventListener('dragleave', () => {
      el.classList.remove('drag-over-top', 'drag-over-bottom');
    });
    el.addEventListener('drop', (ev) => {
      ev.preventDefault();
      const isTop = el.classList.contains('drag-over-top');
      el.classList.remove('drag-over-top', 'drag-over-bottom');
      const fromTag = _dragTag;
      const toTag = el.dataset.tag;
      if (!fromTag || fromTag === toTag || isSystemTag(toTag)) return;
      _reorderCustomTag(fromTag, toTag, isTop);
    });
  });
}

async function _reorderCustomTag(fromTag, toTag, insertBefore) {
  const tags = window._cachedCustomTags || [];
  // Bootstrap: ensure both tags exist in the ordering array
  if (!tags.includes(fromTag)) tags.push(fromTag);
  if (!tags.includes(toTag)) tags.push(toTag);
  const fromIdx = tags.indexOf(fromTag);
  if (fromIdx === tags.indexOf(toTag)) return;
  tags.splice(fromIdx, 1);
  // Recalculate toIdx after removal
  const toIdx = tags.indexOf(toTag);
  const insertIdx = insertBefore ? toIdx : toIdx + 1;
  tags.splice(insertIdx, 0, fromTag);
  window._cachedCustomTags = tags;
  if (window.saveCustomTags) {
    await window.saveCustomTags(JSON.stringify(tags));
  }
  updateCounts();
}

/* ── Entry-to-Tag Drop (assign tag via drag) ──────────── */
function _bindEntryToTagDrop(catList) {
  catList.querySelectorAll('.tag-sidebar-item').forEach(el => {
    el.addEventListener('dragover', (ev) => {
      if (_dragTag) return;
      ev.preventDefault();
      ev.dataTransfer.dropEffect = 'link';
      el.classList.add('tag-drop-target');
    });
    el.addEventListener('dragleave', () => {
      el.classList.remove('tag-drop-target');
    });
    el.addEventListener('drop', (ev) => {
      el.classList.remove('tag-drop-target');
      const entryId = ev.dataTransfer.getData('text/x-entry-drag');
      if (!entryId) return;
      ev.preventDefault();
      ev.stopPropagation();
      const tagName = el.dataset.tag;
      if (!tagName) return;
      _assignTagToEntry(entryId, tagName);
    });
  });
}

async function _assignTagToEntry(entryId, tagName) {
  const entry = _entries.find(e => e.id === entryId);
  if (!entry) return;
  const tags = entry.tags ? [...entry.tags] : [];
  if (tags.includes(tagName)) {
    showToast(t('notebook.tag_already_assigned') || 'Tag already assigned');
    return;
  }
  tags.push(tagName);
  if (window.updateEntry) {
    const ok = await window.updateEntry(entryId, entry.title || '', JSON.stringify(tags));
    if (ok) {
      if (!isSystemTag(tagName)) await _persistCustomTag(tagName);
      await loadEntries();
      showToast(t('notebook.tag_updated'));
    } else {
      showToast(t('notebook.error_update') || 'Update failed', true);
    }
  }
}
