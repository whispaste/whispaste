/* ── Model Switcher Popover ────────────────────────────── */

async function showModelSwitcher(anchor) {
  // Remove existing popover
  document.querySelector('.model-switcher-popover')?.remove();

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

  const popover = document.createElement('div');
  popover.className = 'model-switcher-popover';

  let html = '<div class="model-switcher-header">' + t('modelSwitcher.title') + '</div>';
  html += '<div class="model-switcher-list">';

  for (const m of models) {
    const isActive = m.id === currentModel && m.isLocal === isLocal;
    html += `<div class="model-switcher-item${isActive ? ' active' : ''}" data-model-id="${esc(m.id)}" data-is-local="${m.isLocal}">
      <div class="model-switcher-name">${esc(m.name)}</div>
      <div class="model-switcher-meta">${esc(m.meta)}</div>
      ${isActive ? '<span class="model-switcher-check">' + icons.check + '</span>' : ''}
    </div>`;
  }

  html += '</div>';
  html += '<div class="model-switcher-footer"><a class="model-switcher-settings">' + t('modelSwitcher.settings') + '</a></div>';

  popover.innerHTML = html;
  document.body.appendChild(popover);

  // Position above the anchor
  const rect = anchor.getBoundingClientRect();
  popover.style.bottom = (window.innerHeight - rect.top + 8) + 'px';
  popover.style.left = rect.left + 'px';

  // Click handler for model selection
  popover.addEventListener('click', async (e) => {
    const item = e.target.closest('.model-switcher-item');
    if (item) {
      const modelId = item.dataset.modelId;
      const wantLocal = item.dataset.isLocal === 'true';
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
      popover.remove();
      return;
    }

    const settingsLink = e.target.closest('.model-switcher-settings');
    if (settingsLink) {
      popover.remove();
      scrollToSettingsSection('section-model');
      return;
    }
  });

  // Close on outside click
  setTimeout(() => {
    const closeHandler = (e) => {
      if (!popover.contains(e.target) && e.target !== anchor) {
        popover.remove();
        document.removeEventListener('click', closeHandler);
      }
    };
    document.addEventListener('click', closeHandler);
  }, 10);
}
