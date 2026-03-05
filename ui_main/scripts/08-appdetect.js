// App Detection — per-app smart mode presets
(function() {
  let appPresets = {};

  const presetOptions = [
    'cleanup', 'concise', 'email', 'bullets', 'formal',
    'aiprompt', 'summary', 'notes', 'meeting', 'social',
    'technical', 'casual', 'translate'
  ];

  async function loadAppPresets() {
    try {
      const raw = await window.getAppPresets();
      appPresets = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!appPresets || typeof appPresets !== 'object') appPresets = {};
    } catch (e) {
      appPresets = {};
    }
    try {
      const enabled = await window.getAppDetectionEnabled();
      const toggle = document.getElementById('toggle-app-detection');
      if (toggle) toggle.checked = !!enabled;
      updateAppDetectionVisibility();
    } catch (e) {}
    renderAppPresets();
  }

  function updateAppDetectionVisibility() {
    const toggle = document.getElementById('toggle-app-detection');
    const section = document.getElementById('app-presets-section');
    if (toggle && section) {
      section.style.display = toggle.checked ? '' : 'none';
    }
  }

  function renderAppPresets() {
    const list = document.getElementById('app-presets-list');
    if (!list) return;
    const entries = Object.entries(appPresets);
    if (entries.length === 0) {
      list.innerHTML = `<p class="form-hint" style="margin:8px 0">${t('appDetectionEmpty')}</p>`;
      return;
    }
    list.innerHTML = entries.map(([app, preset]) => `
      <div class="app-preset-row">
        <span class="app-preset-name" title="${esc(app)}">${esc(app)}</span>
        <select class="form-select form-select-sm app-preset-select" data-app="${esc(app)}">
          ${presetOptions.map(p => `<option value="${p}" ${p === preset ? 'selected' : ''}>${t('preset_' + p) || p}</option>`).join('')}
        </select>
        <button class="btn-icon app-preset-delete" data-app="${esc(app)}" title="${t('replacementsDelete')}">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
        </button>
      </div>
    `).join('');
  }

  async function saveAppPresets() {
    try {
      await window.setAppPresets(JSON.stringify(appPresets));
    } catch (e) {
      console.error('Save app presets failed:', e);
    }
  }

  async function addAppPreset() {
    // Detect current foreground app as suggestion
    let suggestion = '';
    try { suggestion = await window.getActiveAppName(); } catch (e) {}

    const appName = await showPromptDialog(
      t('appDetectionAddTitle'),
      t('appDetectionAddMsg'),
      { defaultValue: suggestion, confirmText: t('replacementsAdd') }
    );
    if (!appName) return;
    const name = appName.trim().toLowerCase();
    if (!name) return;
    appPresets[name] = 'cleanup';
    saveAppPresets();
    renderAppPresets();
  }

  document.addEventListener('click', (e) => {
    if (e.target.closest('#btn-add-app-preset')) {
      addAppPreset();
      return;
    }
    const del = e.target.closest('.app-preset-delete');
    if (del) {
      delete appPresets[del.dataset.app];
      saveAppPresets();
      renderAppPresets();
      return;
    }
  });

  document.addEventListener('change', (e) => {
    if (e.target.id === 'toggle-app-detection') {
      window.setAppDetectionEnabled(e.target.checked);
      updateAppDetectionVisibility();
      return;
    }
    if (e.target.classList.contains('app-preset-select')) {
      appPresets[e.target.dataset.app] = e.target.value;
      saveAppPresets();
      return;
    }
  });

  // Load when smart mode page becomes visible
  const observer = new MutationObserver(() => {
    const page = document.getElementById('page-smartmode');
    if (page && page.style.display !== 'none') {
      loadAppPresets();
    }
  });
  document.addEventListener('DOMContentLoaded', () => {
    const page = document.getElementById('page-smartmode');
    if (page) observer.observe(page, { attributes: true, attributeFilter: ['style'] });
  });

  window.loadAppPresets = loadAppPresets;
})();
