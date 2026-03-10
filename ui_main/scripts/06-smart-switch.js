/* ── Smart Mode Quick Switcher (status bar popover) ──── */

async function showSmartSwitcher(anchor) {
  let cfg = {};
  try {
    const raw = await window.getConfig();
    cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (e) { return; }

  const isActive = !!cfg.smart_mode;
  const currentPreset = cfg.smart_mode_preset || 'cleanup';

  // Icon map for built-in presets
  const presetIcons = {
    cleanup: icons.sparkles, concise: icons.minimize, email: icons.mail,
    formal: icons.fileText, bullets: icons.list, aiprompt: icons.bot,
    summary: icons.fileText, notes: icons.clipboard, meeting: icons.users,
    social: icons.share, technical: icons.code, casual: icons.messageCircle,
    translate: icons.globe,
  };

  const templates = await getAllSmartTemplates();

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
        // Sync settings form checkbox to prevent auto-save from reverting
        const toggle = document.getElementById('toggle-smartmode');
        if (toggle) toggle.checked = !!newCfg.smart_mode;
        showToast(newState ? t('smartSwitcher.enabled') : t('smartSwitcher.disabled'), false);
      },
    },
  });

  // Built-in preset items
  for (const tpl of templates.filter(x => !x.isCustom)) {
    const active = isActive && tpl.id === currentPreset;
    items.push({
      icon: presetIcons[tpl.id] || icons.sparkles,
      label: tpl.label,
      checked: active,
      action: async () => {
        await window.setSmartPreset(tpl.id);
        const raw2 = await window.getConfig();
        const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
        updateStatusBar(newCfg);
        // Sync settings form to prevent auto-save from reverting
        const toggle = document.getElementById('toggle-smartmode');
        if (toggle) toggle.checked = true;
        const sel = document.getElementById('select-smartpreset');
        if (sel) sel.value = tpl.id;
        showToast(t('smartSwitcher.switched') + ': ' + tpl.label, false);
      },
    });
  }

  // Custom template items
  const customTpls = templates.filter(x => x.isCustom);
  if (customTpls.length > 0) {
    items.push({ divider: true });
    for (const tpl of customTpls) {
      const active = isActive && tpl.id === currentPreset;
      items.push({
        icon: icons.fileText,
        label: esc(tpl.label),
        checked: active,
        action: async () => {
          await window.setSmartPreset(tpl.id);
          const raw2 = await window.getConfig();
          const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
          updateStatusBar(newCfg);
          // Sync settings form to prevent auto-save from reverting
          const toggle = document.getElementById('toggle-smartmode');
          if (toggle) toggle.checked = true;
          const sel = document.getElementById('select-smartpreset');
          if (sel) sel.value = tpl.id;
          showToast(t('smartSwitcher.switched') + ': ' + esc(tpl.label), false);
        },
      });
    }
  }

  // Footer: settings link
  items.push({
    footer: {
      label: t('smartSwitcher.settings'),
      action: () => switchPage('smartmode'),
    },
  });

  showPopover(anchor, { items });
}
