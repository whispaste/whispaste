// Custom Templates — user-defined smart mode presets
(function() {
  let customTemplates = {};
  let templateMetas = {};

  async function loadCustomTemplates() {
    try {
      const raw = await window.getCustomTemplates();
      customTemplates = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!customTemplates || typeof customTemplates !== 'object') customTemplates = {};
    } catch (e) {
      customTemplates = {};
    }
    try {
      if (window.getTemplateMetas) {
        const raw = await window.getTemplateMetas();
        templateMetas = typeof raw === 'string' ? JSON.parse(raw) : raw;
        if (!templateMetas || typeof templateMetas !== 'object') templateMetas = {};
      }
    } catch (e) {
      templateMetas = {};
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
    list.innerHTML = entries.map(([name, prompt]) => {
      const meta = templateMetas[name] || {};
      const descPreview = meta.description ? esc(meta.description.length > 60 ? meta.description.slice(0, 60) + '…' : meta.description) : '';
      return `
      <div class="custom-template-row">
        <div class="custom-template-info">
          <span class="custom-template-name">${esc(name)}</span>
          ${descPreview ? `<span class="custom-template-prompt" title="${esc(meta.description)}">${descPreview}</span>` : `<span class="custom-template-prompt" title="${esc(prompt)}">${esc(prompt.length > 100 ? prompt.slice(0, 100) + '…' : prompt)}</span>`}
        </div>
        <div class="custom-template-actions">
          <button class="btn-icon custom-template-edit" data-name="${esc(name)}" title="${t('edit') || 'Edit'}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
          </button>
          <button class="btn-icon custom-template-delete" data-name="${esc(name)}" title="${t('replacementsDelete')}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
          </button>
        </div>
      </div>`;
    }).join('');
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

  // Show a template dialog with prompt, description, and keywords fields
  function showTemplateDialog(title, opts = {}) {
    return new Promise(resolve => {
      const overlay = document.getElementById('confirmOverlay');
      if (!overlay) { resolve(null); return; }
      const dialog = overlay.querySelector('.confirm-dialog');
      const keywords = opts.keywords || [];

      dialog.innerHTML = `
        <div class="confirm-icon info">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
        </div>
        <div class="confirm-title">${title}</div>
        <div style="text-align:left;width:100%">
          <label class="form-label" style="font-size:0.82rem;font-weight:600;margin-bottom:4px;display:block">${t('customTemplateAddPromptMsg')}</label>
          <textarea id="tplDialogPrompt" class="prompt-input" rows="4" style="resize:vertical;width:100%">${esc(opts.prompt || '')}</textarea>

          <label class="form-label" style="font-size:0.82rem;font-weight:600;margin:12px 0 4px;display:block">${t('templateDescription')}</label>
          <textarea id="tplDialogDesc" class="prompt-input" rows="2" style="resize:vertical;width:100%" placeholder="${esc(t('templateDescPlaceholder'))}">${esc(opts.description || '')}</textarea>
          <p class="form-hint" style="margin:2px 0 0">${t('templateDescHelp')}</p>

          <label class="form-label" style="font-size:0.82rem;font-weight:600;margin:12px 0 4px;display:block">${t('templateKeywords')}</label>
          <div class="keyword-chips" id="tplDialogChips">${keywords.map(kw => `<span class="keyword-chip" data-kw="${esc(kw)}">${esc(kw)} <span class="keyword-chip-remove" data-kw="${esc(kw)}">&#10005;</span></span>`).join('')}</div>
          <input type="text" id="tplDialogKeywords" class="prompt-input" style="width:100%;margin-top:6px" placeholder="${esc(t('templateKeywordsPlaceholder'))}" />
          <p class="form-hint" style="margin:2px 0 0">${t('templateKeywordsHelp')}</p>
        </div>
        <div class="confirm-btns" style="margin-top:14px">
          <button class="btn btn-secondary flex-1" id="dialogCancel">${t('cancel')}</button>
          <button class="btn btn-primary flex-1" id="dialogConfirm">${t('save')}</button>
        </div>
      `;

      overlay.classList.add('show');

      const chipContainer = document.getElementById('tplDialogChips');
      const kwInput = document.getElementById('tplDialogKeywords');
      let currentKeywords = [...keywords];

      function renderChips() {
        chipContainer.innerHTML = currentKeywords.map(kw =>
          `<span class="keyword-chip" data-kw="${esc(kw)}">${esc(kw)} <span class="keyword-chip-remove" data-kw="${esc(kw)}">&#10005;</span></span>`
        ).join('');
      }

      function addKeyword(val) {
        const kw = val.trim();
        if (kw && !currentKeywords.includes(kw)) {
          currentKeywords.push(kw);
          renderChips();
        }
      }

      chipContainer.addEventListener('click', (e) => {
        const rm = e.target.closest('.keyword-chip-remove');
        if (rm) {
          currentKeywords = currentKeywords.filter(k => k !== rm.dataset.kw);
          renderChips();
        }
      });

      kwInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ',') {
          e.preventDefault();
          const parts = kwInput.value.split(',');
          parts.forEach(p => addKeyword(p));
          kwInput.value = '';
        }
      });

      kwInput.addEventListener('blur', () => {
        if (kwInput.value.trim()) {
          kwInput.value.split(',').forEach(p => addKeyword(p));
          kwInput.value = '';
        }
      });

      const promptInput = document.getElementById('tplDialogPrompt');
      if (promptInput) promptInput.focus();

      function cleanup(val) {
        overlay.classList.remove('show');
        resolve(val);
      }

      document.getElementById('dialogConfirm')?.addEventListener('click', () => {
        const prompt = document.getElementById('tplDialogPrompt')?.value || '';
        const description = document.getElementById('tplDialogDesc')?.value || '';
        // Capture any remaining text in keyword input
        if (kwInput.value.trim()) {
          kwInput.value.split(',').forEach(p => addKeyword(p));
        }
        cleanup({ prompt: prompt.trim(), description: description.trim(), keywords: currentKeywords });
      }, { once: true });

      document.getElementById('dialogCancel')?.addEventListener('click', () => cleanup(null), { once: true });
      overlay.addEventListener('click', (ev) => { if (ev.target === overlay) cleanup(null); }, { once: true });

      function onEsc(ev) {
        if (ev.key === 'Escape') { cleanup(null); document.removeEventListener('keydown', onEsc); }
      }
      document.addEventListener('keydown', onEsc);
    });
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

    const result = await showTemplateDialog(t('customTemplateAddPromptTitle'), {});
    if (!result || !result.prompt) return;

    customTemplates[key] = result.prompt;
    await window.saveCustomTemplate(key, result.prompt);

    if (window.setTemplateMeta && (result.description || result.keywords.length > 0)) {
      templateMetas[key] = { description: result.description, keywords: result.keywords };
      await window.setTemplateMeta(key, JSON.stringify(templateMetas[key]));
    }

    loadCustomTemplates();
    if (typeof _builtinPresetsCache !== 'undefined') _builtinPresetsCache = null;
  }

  async function editCustomTemplate(name) {
    const currentPrompt = customTemplates[name] || '';
    const meta = templateMetas[name] || {};

    const result = await showTemplateDialog(t('customTemplateEditTitle'), {
      prompt: currentPrompt,
      description: meta.description || '',
      keywords: meta.keywords || []
    });
    if (!result) return;
    if (!result.prompt) return;

    customTemplates[name] = result.prompt;
    await window.saveCustomTemplate(name, result.prompt);

    if (window.setTemplateMeta) {
      templateMetas[name] = { description: result.description, keywords: result.keywords };
      await window.setTemplateMeta(name, JSON.stringify(templateMetas[name]));
    }

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
    delete templateMetas[name];
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
