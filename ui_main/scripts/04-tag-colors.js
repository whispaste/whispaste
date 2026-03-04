/* ── Tag Color Picker ──────────────────────────────── */
function showTagColorPicker(targetEl, tagName, onColorSelected) {
  closeTagColorPicker();
  const picker = document.createElement('div');
  picker.className = 'tag-color-picker';
  picker.innerHTML = `
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

  // Position near the target element
  const rect = targetEl.getBoundingClientRect();
  picker.style.position = 'fixed';
  picker.style.top = (rect.bottom + 4) + 'px';
  picker.style.left = rect.left + 'px';
  picker.style.zIndex = '9999';

  document.body.appendChild(picker);

  // Handle clicks
  picker.querySelectorAll('[data-index]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const index = parseInt(btn.dataset.index);
      if (window.saveTagColor) {
        window.saveTagColor(tagName, index).then(() => {
          if (index < 0) {
            delete _customTagColors[tagName];
          } else {
            _customTagColors[tagName] = index;
          }
          closeTagColorPicker();
          if (onColorSelected) onColorSelected();
          if (typeof renderHistory === 'function') renderHistory();
          if (typeof updateCounts === 'function') updateCounts();
        });
      }
    });
  });

  // Close on outside click (delayed to not catch current click)
  setTimeout(() => {
    document.addEventListener('click', _closePickerOnOutsideClick);
  }, 10);
}

function _closePickerOnOutsideClick(ev) {
  if (!ev.target.closest('.tag-color-picker')) {
    closeTagColorPicker();
  }
}

function closeTagColorPicker() {
  document.querySelectorAll('.tag-color-picker').forEach(el => el.remove());
  document.removeEventListener('click', _closePickerOnOutsideClick);
}

// Event delegation: RIGHT-click on tag in entry header for color picker
document.addEventListener('contextmenu', (ev) => {
  const tag = ev.target.closest('.entry-tags-row .tag, .entry-meta .tag');
  if (tag) {
    ev.preventDefault();
    ev.stopPropagation();
    const tagName = tag.textContent.trim();
    if (!tagName) return;
    showTagColorPickerAt(ev.clientX, ev.clientY, tagName, null);
    return;
  }

  // RIGHT-click on sidebar tag for context menu
  const sidebarTag = ev.target.closest('.nav-tags .tag-sidebar-item');
  if (sidebarTag) {
    ev.preventDefault();
    ev.stopPropagation();
    const tagName = sidebarTag.dataset.tag;
    if (!tagName) return;
    showTagContextMenu(ev.clientX, ev.clientY, tagName);
  }
});

function showTagColorPickerAt(x, y, tagName, onColorSelected) {
  closeTagColorPicker();
  const picker = document.createElement('div');
  picker.className = 'tag-color-picker';
  picker.innerHTML = `
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
  picker.style.position = 'fixed';
  picker.style.top = y + 'px';
  picker.style.left = x + 'px';
  picker.style.zIndex = '9999';
  document.body.appendChild(picker);

  picker.querySelectorAll('[data-index]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const index = parseInt(btn.dataset.index);
      if (window.saveTagColor) {
        window.saveTagColor(tagName, index).then(() => {
          if (index < 0) delete _customTagColors[tagName];
          else _customTagColors[tagName] = index;
          closeTagColorPicker();
          if (onColorSelected) onColorSelected();
          if (typeof renderHistory === 'function') renderHistory();
          if (typeof updateCounts === 'function') updateCounts();
        });
      }
    });
  });
  setTimeout(() => document.addEventListener('click', _closePickerOnOutsideClick), 10);
}

function showTagContextMenu(x, y, tagName) {
  closeTagColorPicker();
  const menu = document.createElement('div');
  menu.className = 'tag-color-picker tag-context-menu';
  menu.innerHTML = `
    <div class="tcp-header">${esc(tagName)}</div>
    <button class="tcm-item" data-action="rename">${t('tag_rename') || 'Rename'}</button>
    <button class="tcm-item" data-action="color">${t('tag_color') || 'Change Color'}</button>
  `;
  menu.style.position = 'fixed';
  menu.style.top = y + 'px';
  menu.style.left = x + 'px';
  menu.style.zIndex = '9999';
  document.body.appendChild(menu);

  menu.querySelector('[data-action="rename"]').addEventListener('click', (ev) => {
    ev.stopPropagation();
    closeTagColorPicker();
    promptRenameTag(tagName);
  });
  menu.querySelector('[data-action="color"]').addEventListener('click', (ev) => {
    ev.stopPropagation();
    closeTagColorPicker();
    showTagColorPickerAt(x, y, tagName, null);
  });
  setTimeout(() => document.addEventListener('click', _closePickerOnOutsideClick), 10);
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
