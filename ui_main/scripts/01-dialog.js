/* ── Unified Dialog System ─────────────────────────── */

/** Store the element that had focus before a dialog opened */
let _dialogPreviousFocus = null;

/**
 * Show a modal dialog. Returns a Promise that resolves to the button clicked.
 * @param {Object} opts
 * @param {string} opts.title - Dialog title
 * @param {string} opts.message - Dialog message (plain text by default)
 * @param {boolean} [opts.htmlMessage] - If true, message is treated as trusted HTML
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

    _dialogPreviousFocus = document.activeElement;

    const dialog = overlay.querySelector('.confirm-dialog');
    const variant = opts.variant || 'info';
    const iconHTML = opts.icon || _defaultDialogIcon(variant);

    // Safe DOM construction — textContent for user strings, innerHTML only for trusted SVG
    dialog.textContent = '';

    const iconDiv = document.createElement('div');
    iconDiv.className = 'confirm-icon ' + variant;
    iconDiv.innerHTML = iconHTML;
    dialog.appendChild(iconDiv);

    const titleDiv = document.createElement('div');
    titleDiv.className = 'confirm-title';
    titleDiv.textContent = opts.title;
    dialog.appendChild(titleDiv);

    const msgDiv = document.createElement('div');
    msgDiv.className = 'confirm-msg';
    if (opts.htmlMessage) {
      msgDiv.innerHTML = opts.message;
    } else {
      msgDiv.textContent = opts.message;
    }
    dialog.appendChild(msgDiv);

    const btnsDiv = document.createElement('div');
    btnsDiv.className = 'confirm-btns';

    if (opts.cancelText !== null) {
      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'btn btn-secondary flex-1';
      cancelBtn.id = 'dialogCancel';
      cancelBtn.textContent = opts.cancelText || t('notebook.confirm_cancel');
      btnsDiv.appendChild(cancelBtn);
    }

    const confirmBtn = document.createElement('button');
    confirmBtn.className = 'btn btn-' + (variant === 'danger' ? 'danger' : 'primary') + ' flex-1';
    confirmBtn.id = 'dialogConfirm';
    confirmBtn.textContent = opts.confirmText || 'OK';
    btnsDiv.appendChild(confirmBtn);

    dialog.appendChild(btnsDiv);

    overlay.classList.add('show');

    function cleanup(result) {
      overlay.classList.remove('show');
      if (_dialogPreviousFocus && typeof _dialogPreviousFocus.focus === 'function') {
        _dialogPreviousFocus.focus();
        _dialogPreviousFocus = null;
      }
      resolve(result);
    }

    if (confirmBtn) confirmBtn.addEventListener('click', () => cleanup(true), { once: true });
    const cancelBtnEl = document.getElementById('dialogCancel');
    if (cancelBtnEl) cancelBtnEl.addEventListener('click', () => cleanup(false), { once: true });

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
    _dialogPreviousFocus = document.activeElement;
    const dialog = overlay.querySelector('.confirm-dialog');
    const iconHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg>';

    // Safe DOM construction
    dialog.textContent = '';

    const iconDiv = document.createElement('div');
    iconDiv.className = 'confirm-icon info';
    iconDiv.innerHTML = iconHTML;
    dialog.appendChild(iconDiv);

    const titleDiv = document.createElement('div');
    titleDiv.className = 'confirm-title';
    titleDiv.textContent = title;
    dialog.appendChild(titleDiv);

    const msgDiv = document.createElement('div');
    msgDiv.className = 'confirm-msg';
    msgDiv.textContent = message;
    dialog.appendChild(msgDiv);

    let input;
    if (opts.multiline) {
      input = document.createElement('textarea');
      input.id = 'dialogPromptInput';
      input.className = 'prompt-input';
      input.rows = 5;
      input.style.resize = 'vertical';
      input.textContent = opts.defaultValue || '';
    } else {
      input = document.createElement('input');
      input.type = 'text';
      input.id = 'dialogPromptInput';
      input.className = 'prompt-input';
      input.value = opts.defaultValue || '';
    }
    dialog.appendChild(input);

    const btnsDiv = document.createElement('div');
    btnsDiv.className = 'confirm-btns';

    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'btn btn-secondary flex-1';
    cancelBtn.id = 'dialogCancel';
    cancelBtn.textContent = t('notebook.confirm_cancel');
    btnsDiv.appendChild(cancelBtn);

    const confirmBtn = document.createElement('button');
    confirmBtn.className = 'btn btn-primary flex-1';
    confirmBtn.id = 'dialogConfirm';
    confirmBtn.textContent = opts.confirmText || 'OK';
    btnsDiv.appendChild(confirmBtn);

    dialog.appendChild(btnsDiv);

    overlay.classList.add('show');
    if (input) { input.focus(); if (input.select) input.select(); }

    function cleanup(val) {
      overlay.classList.remove('show');
      if (_dialogPreviousFocus && typeof _dialogPreviousFocus.focus === 'function') {
        _dialogPreviousFocus.focus();
        _dialogPreviousFocus = null;
      }
      resolve(val);
    }
    confirmBtn.addEventListener('click', () => cleanup(input?.value || null), { once: true });
    cancelBtn.addEventListener('click', () => cleanup(null), { once: true });
    overlay.addEventListener('click', (ev) => { if (ev.target === overlay) cleanup(null); }, { once: true });
    if (input && !opts.multiline) input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') cleanup(input.value); });
    function onEsc(ev) {
      if (ev.key === 'Escape') { cleanup(null); document.removeEventListener('keydown', onEsc); }
    }
    document.addEventListener('keydown', onEsc);
  });
}

/**
 * Show a list selection dialog using the unified dialog system.
 * @param {string} title - Dialog title
 * @param {Array<{label: string, value: string, icon?: string}>} items
 * @param {Object} [opts]
 * @param {string} [opts.message] - Optional subtitle
 * @param {string} [opts.icon] - SVG icon HTML for header badge
 * @param {string} [opts.cancelText] - Cancel button text
 * @param {string} [opts.selectedValue] - Currently selected value (highlighted)
 * @returns {Promise<string|null>} Selected value or null if cancelled
 */
function showListDialog(title, items, opts = {}) {
  return new Promise(resolve => {
    const overlay = document.getElementById('confirmOverlay');
    if (!overlay) { resolve(null); return; }
    _dialogPreviousFocus = document.activeElement;
    const dialog = overlay.querySelector('.confirm-dialog');

    const iconHTML = opts.icon || '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>';

    // Safe DOM construction
    dialog.textContent = '';

    const iconDiv = document.createElement('div');
    iconDiv.className = 'confirm-icon info';
    iconDiv.innerHTML = iconHTML;
    dialog.appendChild(iconDiv);

    const titleDiv = document.createElement('div');
    titleDiv.className = 'confirm-title';
    titleDiv.textContent = title;
    dialog.appendChild(titleDiv);

    if (opts.message) {
      const msgDiv = document.createElement('div');
      msgDiv.className = 'confirm-msg';
      msgDiv.textContent = opts.message;
      dialog.appendChild(msgDiv);
    }

    const listDiv = document.createElement('div');
    listDiv.className = 'confirm-list';
    items.forEach(item => {
      const el = document.createElement('div');
      el.className = 'confirm-list-item' + (item.value === opts.selectedValue ? ' selected' : '');
      el.dataset.listValue = item.value;
      if (item.icon) {
        const iconSpan = document.createElement('span');
        iconSpan.innerHTML = item.icon;
        el.appendChild(iconSpan);
      }
      const labelSpan = document.createElement('span');
      labelSpan.textContent = item.label;
      el.appendChild(labelSpan);
      listDiv.appendChild(el);
    });
    dialog.appendChild(listDiv);

    const btnsDiv = document.createElement('div');
    btnsDiv.className = 'confirm-btns';
    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'btn btn-secondary flex-1';
    cancelBtn.id = 'dialogCancel';
    cancelBtn.textContent = opts.cancelText || t('notebook.confirm_cancel');
    btnsDiv.appendChild(cancelBtn);
    dialog.appendChild(btnsDiv);

    overlay.classList.add('show');

    let closed = false;
    function cleanup(val) {
      if (closed) return;
      closed = true;
      overlay.classList.remove('show');
      overlay.removeEventListener('click', onOverlay);
      document.removeEventListener('keydown', onEsc);
      if (_dialogPreviousFocus && typeof _dialogPreviousFocus.focus === 'function') {
        _dialogPreviousFocus.focus();
        _dialogPreviousFocus = null;
      }
      resolve(val);
    }

    dialog.querySelectorAll('[data-list-value]').forEach(el => {
      el.addEventListener('click', () => cleanup(el.dataset.listValue), { once: true });
    });

    cancelBtn.addEventListener('click', () => cleanup(null), { once: true });

    function onOverlay(ev) { if (ev.target === overlay) cleanup(null); }
    overlay.addEventListener('click', onOverlay);

    function onEsc(ev) { if (ev.key === 'Escape') cleanup(null); }
    document.addEventListener('keydown', onEsc);
  });
}
