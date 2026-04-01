/* ── Keyboard Shortcuts Help (Shift+?) ─────────────────── */

(function () {
  let _helpEl = null;
  let _previousFocus = null;

  const closeIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';

  function buildShortcutGroups() {
    return [
      {
        title: t('shortcuts.nav'),
        items: [
          { label: t('shortcuts.command_palette'), keys: ['Ctrl', 'K'] },
          { label: t('navHistory'), keys: ['Ctrl', '1'] },
          { label: t('navAnalytics'), keys: ['Ctrl', '2'] },
          { label: t('navSettings'), keys: ['Ctrl', '3'] },
          { label: t('navSmartMode'), keys: ['Ctrl', '4'] },
          { label: t('navReplacements'), keys: ['Ctrl', '5'] },
          { label: t('navAbout'), keys: ['Ctrl', '6'] },
          { label: t('shortcuts.previous_page'), keys: ['Ctrl', 'Tab'] },
        ],
      },
      {
        title: t('shortcuts.recording'),
        items: [
          { label: t('shortcuts.record_stop'), keys: ['hotkey'] },
        ],
      },
      {
        title: t('shortcuts.smartmode'),
        items: [
          { label: t('shortcuts.toggle_smartmode'), keys: ['Ctrl', 'Shift', 'S'] },
        ],
      },
      {
        title: t('shortcuts.other'),
        items: [
          { label: t('shortcuts.search_history'), keys: ['Ctrl', 'F'] },
          { label: t('shortcuts.close_dialog'), keys: ['Esc'] },
          { label: t('shortcuts.this_help'), keys: ['?'] },
        ],
      },
    ];
  }

  function renderKeys(keys) {
    if (keys.length === 1 && keys[0] === 'hotkey') {
      let hotkeyLabel = '';
      try {
        const hkEl = document.getElementById('statusHotkeyLabel');
        if (hkEl && hkEl.textContent && hkEl.textContent.trim()) {
          hotkeyLabel = hkEl.textContent.trim();
        }
      } catch (e) { /* ignore */ }
      if (!hotkeyLabel) hotkeyLabel = 'Ctrl+Shift+D';
      const parts = hotkeyLabel.split('+').map(k => k.trim()).filter(Boolean);
      return parts.map(k => '<span class="sh-kbd">' + esc(k) + '</span>').join('<span class="sh-separator">+</span>');
    }
    return keys.map(k => '<span class="sh-kbd">' + esc(k) + '</span>').join('<span class="sh-separator">+</span>');
  }

  function showShortcutsHelp() {
    if (_helpEl) return;
    _previousFocus = document.activeElement;

    const backdrop = document.createElement('div');
    backdrop.className = 'sh-backdrop';
    backdrop.addEventListener('mousedown', (e) => {
      if (e.target === backdrop) hideShortcutsHelp();
    });

    const modal = document.createElement('div');
    modal.className = 'sh-modal';
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-labelledby', 'sh-dialog-title');

    // Header
    const header = document.createElement('div');
    header.className = 'sh-header';
    header.innerHTML =
      '<span class="sh-title" id="sh-dialog-title">' + esc(t('shortcuts.title')) + '</span>' +
      '<button class="sh-close" aria-label="Close">' + closeIcon + '</button>';
    const closeBtn = header.querySelector('.sh-close');
    closeBtn.addEventListener('click', hideShortcutsHelp);

    // Content
    const content = document.createElement('div');
    content.className = 'sh-content';

    const groups = buildShortcutGroups();
    let html = '';
    for (const group of groups) {
      html += '<div class="sh-group">' + esc(group.title) + '</div>';
      for (const item of group.items) {
        html += '<div class="sh-row">';
        html += '<span class="sh-label">' + esc(item.label) + '</span>';
        html += '<span class="sh-keys">' + renderKeys(item.keys) + '</span>';
        html += '</div>';
      }
    }
    content.innerHTML = html;

    modal.appendChild(header);
    modal.appendChild(content);
    backdrop.appendChild(modal);
    document.body.appendChild(backdrop);
    _helpEl = backdrop;

    // Focus the close button for keyboard accessibility
    closeBtn.focus();
  }

  function hideShortcutsHelp() {
    if (_helpEl) {
      _helpEl.remove();
      _helpEl = null;
      // Restore focus to previous element
      if (_previousFocus && _previousFocus.focus) {
        try { _previousFocus.focus(); } catch (e) { /* ignore */ }
      }
      _previousFocus = null;
    }
  }

  // Listen for "?" key when no input focused
  document.addEventListener('keydown', (e) => {
    if (e.key === '?' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) {
      e.preventDefault();
      _helpEl ? hideShortcutsHelp() : showShortcutsHelp();
    }
    // Also close on Esc
    if (e.key === 'Escape' && _helpEl) {
      e.preventDefault();
      hideShortcutsHelp();
    }
  });

  // Expose globally for command palette integration
  window.showShortcutsHelp = showShortcutsHelp;
})();
