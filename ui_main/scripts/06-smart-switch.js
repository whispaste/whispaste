/* ── Smart Mode Quick Switcher (status bar popover) ──── */

async function showSmartSwitcher(anchor) {
  let cfg = {};
  try {
    const raw = await window.getConfig();
    cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (e) { return; }

  const isActive = !!cfg.smart_mode;
  const currentPreset = cfg.smart_mode_preset || 'cleanup';

  const presetIcons = {
    cleanup: icons.sparkles, concise: icons.minimize, translate: icons.globe,
  };

  const presetLabels = {
    cleanup: t('smartPresetCleanup'),
    concise: t('smartPresetConcise'),
    translate: t('smartPresetTranslate'),
  };

  const items = [];

  // Header with on/off toggle
  items.push({
    header: t('smartSwitcher.title'),
    headerToggle: {
      label: isActive ? t('statusbar.on') : t('statusbar.off'),
      on: isActive,
      action: async () => {
        const newState = !isActive;
        await window.setSmartPreset(newState ? currentPreset : '');
        const raw2 = await window.getConfig();
        const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
        updateStatusBar(newCfg);
        const toggle = document.getElementById('toggle-smartmode');
        if (toggle) toggle.checked = !!newCfg.smart_mode;
        showToast(newState ? t('smartSwitcher.enabled') : t('smartSwitcher.disabled'), false);
      },
    },
  });

  // Built-in preset items
  for (const id of ['cleanup', 'concise', 'translate']) {
    const active = isActive && id === currentPreset;
    items.push({
      icon: presetIcons[id] || icons.sparkles,
      label: presetLabels[id] || id,
      checked: active,
      action: async () => {
        await window.setSmartPreset(id);
        const raw2 = await window.getConfig();
        const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
        updateStatusBar(newCfg);
        const toggle = document.getElementById('toggle-smartmode');
        if (toggle) toggle.checked = true;
        const sel = document.getElementById('select-smartpreset');
        if (sel) sel.value = id;
        showToast(t('smartSwitcher.switched') + ': ' + (presetLabels[id] || id), false);
      },
    });
  }

  // Footer: settings link
  items.push({
    footer: {
      label: t('smartSwitcher.settings'),
      action: () => switchPage('settings'),
    },
  });

  showPopover(anchor, { items });
}
