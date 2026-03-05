/* ── Unified Dialog System ─────────────────────────── */

/**
 * Show a modal dialog. Returns a Promise that resolves to the button clicked.
 * @param {Object} opts
 * @param {string} opts.title - Dialog title
 * @param {string} opts.message - Dialog message
 * @param {string} [opts.icon] - SVG icon HTML (optional)
 * @param {string} [opts.variant] - 'danger' | 'info' | 'warning' (default: 'info')
 * @param {string} [opts.confirmText] - Confirm button text (default: 'OK')
 * @param {string} [opts.cancelText] - Cancel button text (default: 'Cancel', null = no cancel button)
 * @returns {Promise<boolean>} true if confirmed, false if cancelled
 */
function showDialog(opts) {
  return new Promise(resolve => {
    const overlay = document.getElementById('confirmOverlay');
    if (!overlay) { resolve(false); return; }

    const dialog = overlay.querySelector('.confirm-dialog');
    const variant = opts.variant || 'info';

    const iconHTML = opts.icon || _defaultDialogIcon(variant);

    dialog.innerHTML = `
      <div class="confirm-icon ${variant}">${iconHTML}</div>
      <div class="confirm-title">${opts.title}</div>
      <div class="confirm-msg">${opts.message}</div>
      <div class="confirm-btns">
        ${opts.cancelText !== null ? `<button class="btn btn-secondary flex-1" id="dialogCancel">${opts.cancelText || t('notebook.confirm_cancel')}</button>` : ''}
        <button class="btn btn-${variant === 'danger' ? 'danger' : 'primary'} flex-1" id="dialogConfirm">${opts.confirmText || 'OK'}</button>
      </div>
    `;

    overlay.classList.add('show');

    function cleanup(result) {
      overlay.classList.remove('show');
      resolve(result);
    }

    const confirmBtn = document.getElementById('dialogConfirm');
    const cancelBtn = document.getElementById('dialogCancel');

    if (confirmBtn) confirmBtn.addEventListener('click', () => cleanup(true), { once: true });
    if (cancelBtn) cancelBtn.addEventListener('click', () => cleanup(false), { once: true });

    overlay.addEventListener('click', (ev) => {
      if (ev.target === overlay) cleanup(false);
    }, { once: true });

    function onEsc(ev) {
      if (ev.key === 'Escape') { cleanup(false); document.removeEventListener('keydown', onEsc); }
    }
    document.addEventListener('keydown', onEsc);
  });
}

function _defaultDialogIcon(variant) {
  if (variant === 'danger') {
    return '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>';
  }
  if (variant === 'warning') {
    return '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>';
  }
  return '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>';
}

/** Shorthand: show a confirmation dialog */
async function showConfirmDialog(title, message, opts = {}) {
  return showDialog({
    title,
    message,
    variant: opts.variant || 'danger',
    confirmText: opts.confirmText || t('notebook.confirm_delete'),
    cancelText: opts.cancelText !== undefined ? opts.cancelText : t('notebook.confirm_cancel'),
    icon: opts.icon,
  });
}

// Backward-compatible stubs for 05-init.js references
function cancelDelete() {
  const overlay = document.getElementById('confirmOverlay');
  if (overlay) overlay.classList.remove('show');
}
function doDelete() {}

/** Shorthand: show an alert dialog (no cancel button) */
async function showAlertDialog(title, message, opts = {}) {
  return showDialog({
    title,
    message,
    variant: opts.variant || 'info',
    confirmText: opts.confirmText || 'OK',
    cancelText: null,
    icon: opts.icon,
  });
}

/** Prompt dialog: returns user-entered string or null if cancelled */
function showPromptDialog(title, message, opts = {}) {
  return new Promise(resolve => {
    const overlay = document.getElementById('confirmOverlay');
    if (!overlay) { resolve(null); return; }
    const dialog = overlay.querySelector('.confirm-dialog');
    const iconHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg>';
    const inputHTML = opts.multiline
      ? `<textarea id="dialogPromptInput" class="prompt-input" rows="5" style="resize:vertical">${esc(opts.defaultValue || '')}</textarea>`
      : `<input type="text" id="dialogPromptInput" class="prompt-input" value="${esc(opts.defaultValue || '')}" />`;
    dialog.innerHTML = `
      <div class="confirm-icon info">${iconHTML}</div>
      <div class="confirm-title">${title}</div>
      <div class="confirm-msg">${message}</div>
      ${inputHTML}
      <div class="confirm-btns">
        <button class="btn btn-secondary flex-1" id="dialogCancel">${t('notebook.confirm_cancel')}</button>
        <button class="btn btn-primary flex-1" id="dialogConfirm">${opts.confirmText || 'OK'}</button>
      </div>
    `;
    overlay.classList.add('show');
    const input = document.getElementById('dialogPromptInput');
    if (input) { input.focus(); if (input.select) input.select(); }

    function cleanup(val) {
      overlay.classList.remove('show');
      resolve(val);
    }
    document.getElementById('dialogConfirm')?.addEventListener('click', () => cleanup(input?.value || null), { once: true });
    document.getElementById('dialogCancel')?.addEventListener('click', () => cleanup(null), { once: true });
    overlay.addEventListener('click', (ev) => { if (ev.target === overlay) cleanup(null); }, { once: true });
    if (input && !opts.multiline) input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') cleanup(input.value); });
    function onEsc(ev) {
      if (ev.key === 'Escape') { cleanup(null); document.removeEventListener('keydown', onEsc); }
    }
    document.addEventListener('keydown', onEsc);
  });
}
