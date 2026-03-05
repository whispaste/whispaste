// Custom Templates — user-defined smart mode presets
(function() {
  let customTemplates = {};

  async function loadCustomTemplates() {
    try {
      const raw = await window.getCustomTemplates();
      customTemplates = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!customTemplates || typeof customTemplates !== 'object') customTemplates = {};
    } catch (e) {
      customTemplates = {};
    }
    renderCustomTemplates();
    renderCustomPresetCards();
  }

  function renderCustomTemplates() {
    const list = document.getElementById('custom-templates-list');
    if (!list) return;
    const entries = Object.entries(customTemplates);
    if (entries.length === 0) {
      list.innerHTML = `<div style="text-align:center;padding:16px 0">
        <svg class="icon" style="width:32px;height:32px;color:var(--text-tertiary);margin-bottom:8px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
        <p class="form-hint" style="margin:0">${t('customTemplateEmpty')}</p>
      </div>`;
      return;
    }
    list.innerHTML = entries.map(([name, prompt]) => `
      <div class="custom-template-row">
        <div class="custom-template-info">
          <span class="custom-template-name">${esc(name)}</span>
          <span class="custom-template-prompt" title="${esc(prompt)}">${esc(prompt.length > 100 ? prompt.slice(0, 100) + '…' : prompt)}</span>
        </div>
        <div class="custom-template-actions">
          <button class="btn-icon custom-template-edit" data-name="${esc(name)}" title="${t('edit') || 'Edit'}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
          </button>
          <button class="btn-icon custom-template-delete" data-name="${esc(name)}" title="${t('replacementsDelete')}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
          </button>
        </div>
      </div>
    `).join('');
  }

  function renderCustomPresetCards() {
    // Add custom template cards to the preset grid
    const grid = document.getElementById('preset-grid');
    if (!grid) return;
    // Remove existing custom template cards
    grid.querySelectorAll('.preset-card[data-custom-template]').forEach(c => c.remove());
    // Insert custom template cards before the "custom" card
    const customCard = grid.querySelector('.preset-card[data-preset="custom"]');
    for (const [name] of Object.entries(customTemplates)) {
      const card = document.createElement('div');
      card.className = 'preset-card';
      card.dataset.preset = name;
      card.dataset.customTemplate = 'true';
      card.onclick = () => selectSmartPreset(name);
      card.innerHTML = `
        <svg class="icon preset-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><path d="M12 18v-6"/><path d="m9 15 3-3 3 3"/></svg>
        <span class="preset-label">${esc(name)}</span>
        <span class="preset-desc">${t('customTemplateCardDesc')}</span>
        <button class="btn-preset-prompt" data-preset-key="${esc(name)}" onclick="event.stopPropagation();viewPresetPrompt('${esc(name)}')" title="View prompt">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>
        </button>
      `;
      // Highlight if currently selected
      const sel = document.getElementById('select-smartpreset');
      if (sel && sel.value === name) card.classList.add('active');
      if (customCard) {
        grid.insertBefore(card, customCard);
      } else {
        grid.appendChild(card);
      }
    }
    // Also add to the hidden <select> for form state
    const sel = document.getElementById('select-smartpreset');
    if (sel) {
      sel.querySelectorAll('option[data-custom-template]').forEach(o => o.remove());
      const customOpt = sel.querySelector('option[value="custom"]');
      for (const name of Object.keys(customTemplates)) {
        const opt = document.createElement('option');
        opt.value = name;
        opt.textContent = name;
        opt.dataset.customTemplate = 'true';
        if (customOpt) {
          sel.insertBefore(opt, customOpt);
        } else {
          sel.appendChild(opt);
        }
      }
    }
  }

  async function addCustomTemplate() {
    const name = await showPromptDialog(
      t('customTemplateAddTitle'),
      t('customTemplateAddNameMsg'),
      { confirmText: t('next') || 'Next' }
    );
    if (!name || !name.trim()) return;
    const key = name.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '-');
    if (customTemplates[key]) {
      showDialog({ title: t('error') || 'Error', message: t('customTemplateExists'), variant: 'error' });
      return;
    }
    const prompt = await showPromptDialog(
      t('customTemplateAddPromptTitle'),
      t('customTemplateAddPromptMsg'),
      { confirmText: t('save'), multiline: true }
    );
    if (!prompt || !prompt.trim()) return;
    customTemplates[key] = prompt.trim();
    await window.saveCustomTemplate(key, prompt.trim());
    loadCustomTemplates();
    // Clear cached presets so viewPresetPrompt picks up new ones
    if (typeof _builtinPresetsCache !== 'undefined') _builtinPresetsCache = null;
  }

  async function editCustomTemplate(name) {
    const currentPrompt = customTemplates[name] || '';
    const newPrompt = await showPromptDialog(
      t('customTemplateEditTitle'),
      t('customTemplateEditMsg'),
      { defaultValue: currentPrompt, confirmText: t('save'), multiline: true }
    );
    if (newPrompt === null || newPrompt === undefined) return;
    if (!newPrompt.trim()) return;
    customTemplates[name] = newPrompt.trim();
    await window.saveCustomTemplate(name, newPrompt.trim());
    loadCustomTemplates();
    if (typeof _builtinPresetsCache !== 'undefined') _builtinPresetsCache = null;
  }

  async function deleteCustomTemplate(name) {
    const ok = await showConfirmDialog(
      t('customTemplateDeleteTitle'),
      t('customTemplateDeleteMsg')
    );
    if (!ok) return;
    delete customTemplates[name];
    await window.deleteCustomTemplate(name);
    loadCustomTemplates();
  }

  document.addEventListener('click', (e) => {
    if (e.target.closest('#btn-add-custom-template')) {
      addCustomTemplate();
      return;
    }
    const editBtn = e.target.closest('.custom-template-edit');
    if (editBtn) {
      editCustomTemplate(editBtn.dataset.name);
      return;
    }
    const delBtn = e.target.closest('.custom-template-delete');
    if (delBtn) {
      deleteCustomTemplate(delBtn.dataset.name);
      return;
    }
  });

  // Load when smart mode page becomes visible
  const observer = new MutationObserver(() => {
    const page = document.getElementById('page-smartmode');
    if (page && page.style.display !== 'none') {
      loadCustomTemplates();
    }
  });
  document.addEventListener('DOMContentLoaded', () => {
    const page = document.getElementById('page-smartmode');
    if (page) observer.observe(page, { attributes: true, attributeFilter: ['style'] });
  });

  window.loadCustomTemplates = loadCustomTemplates;
})();
