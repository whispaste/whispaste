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

// Event delegation: click on tag-chip to open color picker
document.addEventListener('click', (ev) => {
  const chip = ev.target.closest('.tag-chip');
  if (!chip) return;
  if (ev.target.closest('.tag-chip-remove')) return;

  const tagName = chip.textContent.trim().replace(/×$/, '').trim();
  if (!tagName) return;

  ev.stopPropagation();
  showTagColorPicker(chip, tagName, null);
});

// Load custom colors when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', loadCustomTagColors);
} else {
  loadCustomTagColors();
}
