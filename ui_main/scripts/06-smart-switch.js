/* ── Smart Mode Quick Switcher (status bar popover) ──── */

async function showSmartSwitcher(anchor) {
  document.querySelector('.smart-switcher-popover')?.remove();

  let cfg = {};
  try {
    const raw = await window.getConfig();
    cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (e) { return; }

  const isActive = !!cfg.smart_mode;
  const currentPreset = cfg.smart_mode_preset || 'cleanup';

  const presets = [
    { id: 'cleanup',   icon: icons.sparkles },
    { id: 'concise',   icon: icons.minimize },
    { id: 'email',     icon: icons.mail },
    { id: 'formal',    icon: icons.fileText },
    { id: 'bullets',   icon: icons.list },
    { id: 'summary',   icon: icons.fileText },
    { id: 'notes',     icon: icons.clipboard },
    { id: 'meeting',   icon: icons.users },
    { id: 'social',    icon: icons.share },
    { id: 'technical', icon: icons.code },
    { id: 'casual',    icon: icons.messageCircle },
    { id: 'translate', icon: icons.globe },
  ];

  const popover = document.createElement('div');
  popover.className = 'smart-switcher-popover';

  let html = '<div class="smart-switcher-header">';
  html += `<span>${t('smartSwitcher.title')}</span>`;
  html += `<button class="smart-switcher-toggle ${isActive ? 'on' : ''}" data-action="toggle">${isActive ? t('statusbar.on') : t('statusbar.off')}</button>`;
  html += '</div>';
  html += '<div class="smart-switcher-list">';

  for (const p of presets) {
    const active = isActive && p.id === currentPreset;
    html += `<div class="smart-switcher-item${active ? ' active' : ''}" data-preset="${p.id}">
      <span class="smart-switcher-icon">${p.icon || icons.sparkles}</span>
      <span class="smart-switcher-label">${t('smart.preset.' + p.id)}</span>
      ${active ? '<span class="smart-switcher-check">' + icons.check + '</span>' : ''}
    </div>`;
  }

  html += '</div>';
  html += '<div class="smart-switcher-footer"><a class="smart-switcher-settings">' + t('smartSwitcher.settings') + '</a></div>';

  popover.innerHTML = html;
  document.body.appendChild(popover);

  // Position above anchor
  const rect = anchor.getBoundingClientRect();
  popover.style.bottom = (window.innerHeight - rect.top + 8) + 'px';
  popover.style.left = rect.left + 'px';

  // Click handler
  popover.addEventListener('click', async (e) => {
    // Toggle on/off
    const toggleBtn = e.target.closest('[data-action="toggle"]');
    if (toggleBtn) {
      const newState = !cfg.smart_mode;
      if (newState) {
        await window.setSmartPreset(currentPreset);
      } else {
        await window.setSmartPreset('');
      }
      const raw2 = await window.getConfig();
      const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
      updateStatusBar(newCfg);
      popover.remove();
      showToast(newState ? t('smartSwitcher.enabled') : t('smartSwitcher.disabled'), false);
      return;
    }

    // Select preset
    const item = e.target.closest('.smart-switcher-item');
    if (item) {
      const preset = item.dataset.preset;
      await window.setSmartPreset(preset);
      const raw2 = await window.getConfig();
      const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
      updateStatusBar(newCfg);
      popover.remove();
      showToast(t('smartSwitcher.switched') + ': ' + t('smart.preset.' + preset), false);
      return;
    }

    // Settings link
    if (e.target.closest('.smart-switcher-settings')) {
      popover.remove();
      switchPage('smartmode');
      return;
    }
  });

  // Close on outside click
  setTimeout(() => {
    const closeHandler = (e) => {
      if (!popover.contains(e.target) && e.target !== anchor && !anchor.contains(e.target)) {
        popover.remove();
        document.removeEventListener('click', closeHandler);
      }
    };
    document.addEventListener('click', closeHandler);
  }, 10);
}
