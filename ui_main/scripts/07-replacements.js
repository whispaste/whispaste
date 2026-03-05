// Text Replacements page logic
(function() {
  let replacements = [];

  async function loadReplacements() {
    try {
      const raw = await window.getTextReplacements();
      replacements = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!Array.isArray(replacements)) replacements = [];
    } catch (e) {
      replacements = [];
    }
    renderList();
    // Load toggle state
    try {
      const enabled = await window.getTextReplacementsEnabled();
      document.getElementById('replacements-toggle').checked = !!enabled;
    } catch (e) {}
  }

  function renderList() {
    const container = document.getElementById('replacements-list');
    if (!container) return;
    if (replacements.length === 0) {
      container.innerHTML = `<div class="replacements-empty">
        <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:48px;height:48px;opacity:0.3;margin-bottom:12px"><path d="M14 4c0-1.1.9-2 2-2"/><path d="M20 2c1.1 0 2 .9 2 2"/><path d="M22 8c0 1.1-.9 2-2 2"/><path d="M16 10c-1.1 0-2-.9-2-2"/><rect x="2" y="14" width="8" height="8" rx="2"/><path d="m6 6 8 8"/></svg>
        <p data-i18n="replacementsEmpty">${t('replacementsEmpty')}</p>
      </div>`;
      return;
    }
    container.innerHTML = replacements.map((r, i) => `
      <div class="replacement-row${r.enabled ? '' : ' disabled'}" data-index="${i}">
        <label class="toggle-switch toggle-sm" title="${t('replacementsToggleItem')}">
          <input type="checkbox" class="repl-toggle" data-index="${i}" ${r.enabled ? 'checked' : ''}>
          <span class="toggle-slider"></span>
        </label>
        <div class="replacement-trigger" title="${t('replacementsTrigger')}">${escapeHtml(r.trigger)}</div>
        <svg class="icon replacement-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
        <div class="replacement-value" title="${t('replacementsReplacement')}">${escapeHtml(r.replacement)}</div>
        <div class="replacement-actions">
          <button class="btn-icon repl-edit" data-index="${i}" title="${t('replacementsEdit')}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
          </button>
          <button class="btn-icon repl-delete" data-index="${i}" title="${t('replacementsDelete')}">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></svg>
          </button>
        </div>
      </div>
    `).join('');
    applyTranslations();
  }

  function escapeHtml(s) {
    const d = document.createElement('div');
    d.textContent = s || '';
    return d.innerHTML;
  }

  async function saveReplacements() {
    try {
      await window.setTextReplacements(JSON.stringify(replacements));
    } catch (e) {
      console.error('Save replacements failed:', e);
    }
  }

  function showEditDialog(index) {
    const isNew = index === -1;
    const item = isNew ? { trigger: '', replacement: '', enabled: true } : { ...replacements[index] };
    const title = isNew ? t('replacementsAddTitle') : t('replacementsEditTitle');

    const formHtml = `
      <div class="repl-dialog-form">
        <label class="repl-dialog-label">${t('replacementsTrigger')}</label>
        <input type="text" id="repl-trigger-input" class="repl-dialog-input" value="${escapeHtml(item.trigger)}" placeholder="${t('replacementsTriggerPlaceholder')}" autocomplete="off">
        <label class="repl-dialog-label">${t('replacementsReplacement')}</label>
        <input type="text" id="repl-value-input" class="repl-dialog-input" value="${escapeHtml(item.replacement)}" placeholder="${t('replacementsReplacementPlaceholder')}" autocomplete="off">
      </div>
    `;

    // Use the unified dialog system
    const overlay = document.getElementById('confirmOverlay');
    if (!overlay) return;
    const dialog = overlay.querySelector('.confirm-dialog');
    dialog.innerHTML = `
      <div class="confirm-icon info"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4c0-1.1.9-2 2-2"/><path d="M20 2c1.1 0 2 .9 2 2"/><path d="M22 8c0 1.1-.9 2-2 2"/><path d="M16 10c-1.1 0-2-.9-2-2"/><rect x="2" y="14" width="8" height="8" rx="2"/><path d="m6 6 8 8"/></svg></div>
      <div class="confirm-title">${title}</div>
      <div class="confirm-msg">${formHtml}</div>
      <div class="confirm-btns">
        <button class="btn btn-secondary flex-1" id="dialogCancel">${t('cancel')}</button>
        <button class="btn btn-primary flex-1" id="dialogConfirm">${isNew ? t('replacementsAdd') : t('save')}</button>
      </div>
    `;
    overlay.classList.add('show');

    setTimeout(() => {
      const inp = document.getElementById('repl-trigger-input');
      if (inp) inp.focus();
    }, 100);

    function cleanup() { overlay.classList.remove('show'); }

    document.getElementById('dialogConfirm')?.addEventListener('click', () => {
      const trigger = document.getElementById('repl-trigger-input').value.trim();
      const replacement = document.getElementById('repl-value-input').value;
      if (!trigger) return;
      if (isNew) {
        replacements.push({ trigger, replacement, enabled: true });
      } else {
        replacements[index].trigger = trigger;
        replacements[index].replacement = replacement;
      }
      saveReplacements();
      renderList();
      cleanup();
    }, { once: true });

    document.getElementById('dialogCancel')?.addEventListener('click', () => cleanup(), { once: true });
    overlay.addEventListener('click', (ev) => { if (ev.target === overlay) cleanup(); }, { once: true });
  }

  // Event delegation
  document.addEventListener('click', async (e) => {
    const addBtn = e.target.closest('#replacements-add-btn');
    if (addBtn) {
      showEditDialog(-1);
      return;
    }
    const editBtn = e.target.closest('.repl-edit');
    if (editBtn) {
      showEditDialog(parseInt(editBtn.dataset.index));
      return;
    }
    const deleteBtn = e.target.closest('.repl-delete');
    if (deleteBtn) {
      const idx = parseInt(deleteBtn.dataset.index);
      const confirmed = await showConfirmDialog(
        t('replacementsDeleteTitle'),
        t('replacementsDeleteConfirm').replace('{trigger}', escapeHtml(replacements[idx].trigger)),
        { confirmText: t('replacementsDelete'), cancelText: t('cancel') }
      );
      if (confirmed) {
        replacements.splice(idx, 1);
        saveReplacements();
        renderList();
      }
      return;
    }
  });

  document.addEventListener('change', (e) => {
    if (e.target.classList.contains('repl-toggle')) {
      const idx = parseInt(e.target.dataset.index);
      replacements[idx].enabled = e.target.checked;
      saveReplacements();
      renderList();
      return;
    }
    if (e.target.id === 'replacements-toggle') {
      window.setTextReplacementsEnabled(e.target.checked);
      return;
    }
  });

  // Auto-load when page becomes visible
  const observer = new MutationObserver(() => {
    const page = document.getElementById('page-replacements');
    if (page && page.style.display !== 'none') {
      loadReplacements();
    }
  });
  document.addEventListener('DOMContentLoaded', () => {
    const page = document.getElementById('page-replacements');
    if (page) observer.observe(page, { attributes: true, attributeFilter: ['style'] });
  });

  window.loadReplacements = loadReplacements;
})();
