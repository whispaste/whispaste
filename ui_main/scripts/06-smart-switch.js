/* ── Smart Mode Quick Switcher (status bar popover) ──── */

async function showSmartSwitcher(anchor) {
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

  // Load custom templates
  let customTemplates = {};
  try {
    const rawCt = await window.getCustomTemplates();
    customTemplates = typeof rawCt === 'string' ? JSON.parse(rawCt) : rawCt;
    if (!customTemplates || typeof customTemplates !== 'object') customTemplates = {};
  } catch (e) {}

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
        showToast(newState ? t('smartSwitcher.enabled') : t('smartSwitcher.disabled'), false);
      },
    },
  });

  // Built-in preset items
  for (const p of presets) {
    const active = isActive && p.id === currentPreset;
    const presetId = p.id;
    items.push({
      icon: p.icon || icons.sparkles,
      label: t('smart.preset.' + presetId),
      checked: active,
      action: async () => {
        await window.setSmartPreset(presetId);
        const raw2 = await window.getConfig();
        const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
        updateStatusBar(newCfg);
        showToast(t('smartSwitcher.switched') + ': ' + t('smart.preset.' + presetId), false);
      },
    });
  }

  // Custom template items
  const customNames = Object.keys(customTemplates);
  if (customNames.length > 0) {
    items.push({ divider: true });
    for (const name of customNames) {
      const active = isActive && name === currentPreset;
      items.push({
        icon: icons.fileText,
        label: name,
        checked: active,
        action: async () => {
          await window.setSmartPreset(name);
          const raw2 = await window.getConfig();
          const newCfg = typeof raw2 === 'string' ? JSON.parse(raw2) : raw2;
          updateStatusBar(newCfg);
          showToast(t('smartSwitcher.switched') + ': ' + name, false);
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
