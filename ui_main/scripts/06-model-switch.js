/* ── Model Switcher Popover ────────────────────────────── */

async function showModelSwitcher(anchor) {
  // Get available models from Go
  let models = [];
  try {
    if (window.getAvailableModels) {
      const raw = await window.getAvailableModels();
      models = JSON.parse(raw);
    }
  } catch (e) { return; }

  if (models.length === 0) {
    scrollToSettingsSection('section-model');
    return;
  }

  // Get current config to know active model
  let cfg = {};
  try {
    const raw = await window.getConfig();
    cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch(e) {}

  const isLocal = cfg.use_local_stt;
  const currentModel = isLocal ? (cfg.local_model_id || 'whisper-tiny') : (cfg.model || 'whisper-1');

  // Show all models — selecting a local one will enable UseLocalSTT via switchModel binding
  const filteredModels = models;

  if (filteredModels.length === 0) {
    scrollToSettingsSection('section-model');
    return;
  }

  const items = [];
  items.push({ header: t('modelSwitcher.title') });

  for (const m of filteredModels) {
    const isActive = m.id === currentModel && m.isLocal === isLocal;
    const modelId = m.id;
    const wantLocal = m.isLocal;
    items.push({
      icon: isActive ? icons.check : '',
      label: m.name + (m.meta ? '  · ' + m.meta : ''),
      action: async () => {
        try {
          if (window.switchModel) {
            await window.switchModel(modelId, wantLocal);
            const raw = await window.getConfig();
            const newCfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
            updateModeBadge(newCfg);
            updateStatusBar(newCfg);
            showToast(t('modelSwitcher.switched'), false);
          }
        } catch(err) {
          showToast(t('modelSwitcher.error'), true);
        }
      },
    });
  }

  items.push({ divider: true });
  items.push({
    label: t('modelSwitcher.settings'),
    action: () => scrollToSettingsSection('section-model'),
  });

  showPopover(anchor, { items, className: 'model-switcher' });
}
