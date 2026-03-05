/* ── Tag Color Picker ──────────────────────────────── */
function showTagColorPicker(targetEl, tagName, onColorSelected) {
  showTagColorPickerAt(
    targetEl.getBoundingClientRect().left,
    targetEl.getBoundingClientRect().bottom + 4,
    tagName,
    onColorSelected,
  );
}

function _buildColorPickerContent(tagName, onColorSelected) {
  const el = document.createElement('div');
  el.innerHTML = `
    <div class="tcp-header">${esc(tagName)}</div>
    <div class="tcp-colors">
      ${TAG_COLORS.map((c, i) => `
        <button class="tcp-swatch${_customTagColors[tagName] === i ? ' active' : ''}"
                data-index="${i}"
                style="background:${c.text}"
                title="Color ${i + 1}">
        </button>
      `).join('')}
    </div>
    <button class="tcp-reset" data-index="-1">Reset</button>
  `;

  el.querySelectorAll('[data-index]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const index = parseInt(btn.dataset.index);
      if (window.saveTagColor) {
        window.saveTagColor(tagName, index).then(() => {
          if (index < 0) delete _customTagColors[tagName];
          else _customTagColors[tagName] = index;
          hidePopovers();
          if (onColorSelected) onColorSelected();
          if (typeof renderHistory === 'function') renderHistory();
          if (typeof updateCounts === 'function') updateCounts();
        });
      }
    });
  });

  return el;
}

function closeTagColorPicker() {
  hidePopovers();
}

// Event delegation: RIGHT-click on tag in entry header → unified context menu
document.addEventListener('contextmenu', (ev) => {
  const tag = ev.target.closest('.entry-tags-row .tag, .entry-meta .tag');
  if (tag) {
    ev.preventDefault();
    ev.stopPropagation();
    const tagName = tag.dataset.tag || tag.textContent.trim();
    if (!tagName) return;
    if (isSystemTag(tagName)) {
      showPopoverAt(ev.clientX, ev.clientY, {
        items: [{ header: tagName }, { label: t('tag_system') || 'System tag — cannot modify', disabled: true }],
      });
      return;
    }
    showTagContextMenu(ev.clientX, ev.clientY, tagName);
    return;
  }

  // RIGHT-click on sidebar tag → same unified context menu
  const sidebarTag = ev.target.closest('.nav-tags .tag-sidebar-item');
  if (sidebarTag) {
    ev.preventDefault();
    ev.stopPropagation();
    const tagName = sidebarTag.dataset.tag;
    if (!tagName) return;
    if (isSystemTag(tagName)) {
      showPopoverAt(ev.clientX, ev.clientY, {
        items: [{ header: tagName }, { label: t('tag_system') || 'System tag — cannot modify', disabled: true }],
      });
      return;
    }
    showTagContextMenu(ev.clientX, ev.clientY, tagName);
  }
});

function showTagColorPickerAt(x, y, tagName, onColorSelected) {
  const pop = showPopoverAt(x, y, { className: 'tag-color-picker' });
  const content = _buildColorPickerContent(tagName, onColorSelected);
  pop.innerHTML = '';
  pop.appendChild(content);
}

function showTagContextMenu(x, y, tagName) {
  showPopoverAt(x, y, {
    items: [
      { header: tagName },
      { icon: icons.pencil, label: t('tag_rename') || 'Rename', action: () => promptRenameTag(tagName) },
      { icon: icons.tag, label: t('tag_color') || 'Change Color', action: () => showTagColorPickerAt(x, y, tagName, null) },
      { divider: true },
      { icon: icons.trash, label: t('tag_delete') || 'Delete Tag', danger: true, action: () => deleteTagFromAll(tagName) },
    ],
  });
}

async function promptRenameTag(oldName) {
  const newName = await showPromptDialog(
    t('tag_rename') || 'Rename Tag',
    t('tag_rename_prompt') || 'Enter new name:',
    { defaultValue: oldName }
  );
  if (newName && newName.trim() && newName.trim() !== oldName) {
    if (window.renameTag) {
      await window.renameTag(oldName, newName.trim());
      // Also rename in persisted custom tags list
      const tags = window._cachedCustomTags || [];
      const idx = tags.indexOf(oldName);
      if (idx !== -1) {
        tags[idx] = newName.trim();
        window._cachedCustomTags = tags;
        if (window.saveCustomTags) await window.saveCustomTags(JSON.stringify(tags));
      }
      await loadEntries();
      if (typeof updateCounts === 'function') updateCounts();
    }
  }
}

// Load custom colors when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', loadCustomTagColors);
} else {
  loadCustomTagColors();
}
