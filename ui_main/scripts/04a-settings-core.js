/* ── Settings Page Logic ───────────────────────────────── */

// Preserved config fields not editable via form controls
let _savedHotkeyMods = ['Ctrl', 'Shift'];
let _savedHotkeyKey = 'V';
let _savedModel = 'whisper-1';
let _savedUILang = '';
let _savedAPIEndpoint = '';
let _downloadingModel = null;
let _configLoaded = false;
let _autoSaveTimer = null;
const DEBOUNCE_MS = 500;

/* ── Shared Model Card Renderer ───────────────────────── */
/**
 * Renders a unified model card used by both STT and LLM sections.
 * @param {Object} m - Model data
 * @param {string} m.id - Model identifier
 * @param {string} m.name - Display name
 * @param {string} m.description - Description text
 * @param {string} m.size - Size string (e.g. "57MB")
 * @param {boolean} m.downloaded - Whether the model is installed/downloaded
 * @param {boolean} m.downloading - Whether currently downloading
 * @param {Object} opts - Rendering options
 * @param {string} opts.type - 'stt' or 'llm'
 * @param {boolean} [opts.showTest] - Show test button when downloaded
 * @returns {string} HTML string for the model card
 */
function renderModelCard(m, opts) {
  const type = opts.type;
  const isDownloading = !!m.downloading;
  const isBlocked = type === 'stt' && !!m.preflight_blocked;
  let actionHTML;

  if (isDownloading) {
    actionHTML = `<button class="btn btn-secondary btn-sm" disabled>${esc(t('modelDownloading'))}</button>
      <div class="model-progress"><div class="model-progress-bar" id="progress-${esc(m.id)}"></div></div>`;
  } else if (isBlocked) {
    const deleteBtn = m.downloaded
      ? `<button class="btn btn-icon btn-sm btn-ghost" onclick="event.stopPropagation();confirmDeleteModel('${esc(m.id)}')" title="${esc(t('modelDelete'))}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>`
      : '';
    actionHTML = `<span class="model-badge model-badge-error" title="${esc(m.preflight_message || '')}">! ${esc(t('preflightBlockedBadge'))}</span>${deleteBtn}`;
  } else if (m.downloaded) {
    const testBtn = opts.showTest
      ? `<button class="btn btn-secondary btn-sm btn-model-test" id="btn-test-${esc(type)}-${esc(m.id)}" onclick="event.stopPropagation();${type === 'stt' ? 'testSTTModel' : 'testLLMModelById'}('${esc(m.id)}')"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg> ${esc(t('modelTest'))}</button>`
      : '';
    const badgeText = type === 'stt' ? t('modelDownloaded') : t('smartLlmReady');
    const deleteHandler = type === 'stt' ? 'confirmDeleteModel' : 'confirmDeleteLLMModel';
    const deleteTitle = type === 'stt' ? t('modelDelete') : t('smartLlmDelete');
    actionHTML = `${testBtn}<span class="model-badge model-badge-success">✓ ${esc(badgeText)}</span><button class="btn btn-icon btn-sm btn-ghost" onclick="event.stopPropagation();${deleteHandler}('${esc(m.id)}')" title="${esc(deleteTitle)}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>`;
  } else {
    const downloadHandler = type === 'stt' ? 'downloadModel' : 'downloadLLMModel';
    const downloadText = type === 'stt' ? t('modelDownload') : t('smartLlmDownload');
    actionHTML = `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();${downloadHandler}('${esc(m.id)}')">${esc(downloadText)}</button>`;
  }

  const statusText = m.downloaded
    ? ''
    : ' · ' + esc(type === 'stt' ? t('modelNotDownloaded') : t('smartLlmNotInstalled'));

  const blockedNote = isBlocked ? `<div class="model-warning">${esc(m.preflight_message || t('preflightBlockedBadge'))}</div>` : '';

  // HW recommendation badge (STT only)
  let hwBadge = '';
  if (type === 'stt' && m.recommended) {
    hwBadge = `<span class="model-badge model-badge-rec">★ ${esc(t('modelRecommended'))}</span>`;
  }

  // Quality stars (STT only)
  let qualityHTML = '';
  if (type === 'stt' && m.quality) {
    const stars = '★'.repeat(m.quality) + '☆'.repeat(5 - m.quality);
    qualityHTML = `<span class="model-quality" title="${esc(t('modelQuality'))}">${stars}</span>`;
  }

  return `<div class="model-item${!m.downloaded && !isDownloading ? ' unavailable' : ''}${isBlocked ? ' preflight-blocked' : ''}${m.recommended ? ' recommended' : ''}" data-model-id="${esc(m.id)}">
    <div class="model-item-info">
      <div class="model-item-name">${esc(m.name)} ${hwBadge}</div>
      ${m.description ? '<div class="model-desc">' + esc(m.description) + '</div>' : ''}
      <div class="model-item-meta">${esc(m.size)}${qualityHTML}${statusText}</div>
      ${blockedNote}
    </div>
    <div class="model-item-action">${actionHTML}</div>
  </div>`;
}

// Floating button color picker — delegated click handler
document.addEventListener('click', function(e) {
  const opt = e.target.closest('.fab-color-option');
  if (!opt) return;
  document.querySelectorAll('.fab-color-option').forEach(el => el.classList.remove('selected'));
  opt.classList.add('selected');
  // Skip autoSave for custom — the color picker input/change events handle it
  if (opt.dataset.color === 'custom') return;
  if (typeof autoSave === 'function') autoSave();
});
// Floating button shape picker — delegated click handler
document.addEventListener('click', function(e) {
  const opt = e.target.closest('.fab-shape-option');
  if (!opt) return;
  document.querySelectorAll('.fab-shape-option').forEach(el => el.classList.remove('selected'));
  opt.classList.add('selected');
  if (typeof autoSave === 'function') autoSave();
});
// Floating button content/icon picker — delegated click handler
document.addEventListener('click', function(e) {
  const opt = e.target.closest('.fab-content-option');
  if (!opt) return;
  document.querySelectorAll('.fab-content-option').forEach(el => el.classList.remove('selected'));
  opt.classList.add('selected');
  if (typeof autoSave === 'function') autoSave();
});
// Auto-hide dropdown — show/hide timeout slider
document.addEventListener('change', function(e) {
  if (e.target.id === 'select-fab-autohide') {
    const timeoutRow = document.getElementById('fab-autohide-timeout-row');
    if (timeoutRow) timeoutRow.style.display = e.target.value === 'timeout' ? '' : 'none';
  }
});
// Sound preview button
document.addEventListener('click', function(e) {
  const btn = e.target.closest('#btn-fab-sound-preview');
  if (!btn) return;
  const sel = document.getElementById('select-fab-sound');
  if (sel && sel.value !== 'none' && typeof window.previewButtonSound === 'function') {
    window.previewButtonSound(sel.value);
  }
});
// Custom color real-time preview (fires continuously while picking)
document.addEventListener('input', function(e) {
  if (e.target.classList.contains('fab-custom-color-input')) {
    document.querySelectorAll('.fab-color-option').forEach(o => o.classList.remove('selected'));
    e.target.closest('.fab-color-option').classList.add('selected');
    if (typeof autoSave === 'function') autoSave();
  }
});
// Custom color final confirmation (fires when picker closes)
document.addEventListener('change', function(e) {
  if (e.target.classList.contains('fab-custom-color-input')) {
    document.querySelectorAll('.fab-color-option').forEach(o => o.classList.remove('selected'));
    e.target.closest('.fab-color-option').classList.add('selected');
    if (typeof autoSave === 'function') autoSave();
  }
});
// Show/hide VAD sensitivity slider when VAD toggle changes
document.addEventListener('change', function(e) {
  if (e.target.id === 'toggle-use-vad') {
    const row = document.getElementById('vad-sensitivity-row');
    if (row) row.classList.toggle('hidden', !e.target.checked);
  }
});
// Show/hide color picker when floating toggle changes
document.addEventListener('change', function(e) {
  if (e.target.id === 'toggle-floating-btn') {
    const enabled = e.target.checked;
    const ids = ['fab-color-row', 'fab-size-row', 'fab-opacity-row', 'fab-lock-row',
      'fab-border-row', 'fab-shape-row', 'fab-content-row', 'fab-animation-row',
      'fab-sound-row', 'fab-autohide-row'];
    ids.forEach(id => { const r = document.getElementById(id); if (r) r.classList.toggle('hidden', !enabled); });
    const timeoutRow = document.getElementById('fab-autohide-timeout-row');
    if (timeoutRow) timeoutRow.style.display = (enabled && document.getElementById('select-fab-autohide')?.value === 'timeout') ? '' : 'none';
    const fab = document.getElementById('captureBtn');
    if (fab) fab.classList.toggle('hidden', enabled);
  }
});

/* ── Gather Config from Form ──────────────────────────── */
function gatherConfig() {
  const sharedFieldValue = (...ids) => {
    for (const id of ids) {
      const value = document.getElementById(id)?.value;
      if (value) return value;
    }
    return '';
  };
  return {
    api_key: sharedFieldValue('input-apikey', 'input-cloud-llm-openai-apikey'),
    api_endpoint: _savedAPIEndpoint,
    hotkey_modifiers: _savedHotkeyMods,
    hotkey_key: _savedHotkeyKey,
    mode: document.querySelector('[name="mode"]:checked')?.value || 'push_to_talk',
    language: document.getElementById('select-language')?.value || '',
    model: _savedModel,
    overlay_position: document.querySelector('[name="overlay"]:checked')?.value || 'top_center',
    play_sounds: document.getElementById('toggle-sound')?.checked || false,
    sound_volume: parseInt(document.getElementById('volume-slider')?.value || '80', 10) / 100.0,
    auto_paste: document.getElementById('toggle-autopaste')?.checked || false,
    auto_paste_delay: parseInt(document.getElementById('range-auto-paste-delay')?.value || '0', 10),
    check_updates: document.getElementById('toggle-updates')?.checked || false,
    autostart: document.getElementById('toggle-autostart')?.checked || false,
    close_to_tray: document.getElementById('toggle-close-to-tray')?.checked ?? true,
    delete_behavior: document.getElementById('toggle-archive-instead')?.checked ? 'archive' : 'delete',
    ui_language: _savedUILang,
    theme: document.getElementById('select-theme')?.value || 'system',
    max_record_sec: parseInt(document.getElementById('range-max-duration')?.value || '120', 10),
    smart_mode: document.getElementById('toggle-smartmode')?.checked || false,
    smart_mode_preset: document.getElementById('select-smartpreset')?.value || 'cleanup',
    smart_mode_prompt: document.getElementById('input-smartprompt')?.value || '',
    smart_mode_target: document.getElementById('select-smarttarget')?.value || 'en',
    smart_mode_provider: document.querySelector('[name="smartProvider"]:checked')?.value || 'auto',
    text_replacement_provider: document.querySelector('[name="textReplaceProvider"]:checked')?.value || 'local',

    notify_background: document.getElementById('toggle-notify-bg')?.checked ?? true,
    notify_complete: document.getElementById('toggle-notify-complete')?.checked ?? true,
    notify_donate: document.getElementById('toggle-notify-donate')?.checked ?? true,
    input_device: document.getElementById('select-audiodevice')?.value || '',
    input_gain: parseInt(document.getElementById('range-input-gain')?.value || '100', 10) / 100.0,
    cleanup_enabled: document.getElementById('toggle-cleanup')?.checked || false,
    cleanup_max_entries: parseInt(document.getElementById('input-cleanup-max-entries')?.value || '0', 10),
    cleanup_max_age_days: parseInt(document.getElementById('input-cleanup-max-age')?.value || '0', 10),
    cleanup_include_pinned: document.getElementById('toggle-cleanup-pinned')?.checked || false,
    trim_silence: false,
    use_vad: document.getElementById('toggle-use-vad')?.checked || false,
    vad_sensitivity: parseInt(document.getElementById('range-vad-sensitivity')?.value || '50', 10) / 100.0,
    floating_button_enabled: document.getElementById('toggle-floating-btn')?.checked || false,
    floating_button_color: document.querySelector('.fab-color-option.selected')?.dataset?.color || 'cyan',
    floating_button_custom_color: document.querySelector('.fab-custom-color-input')?.value || '#22D3EE',
    floating_button_size: parseInt(document.getElementById('range-fab-size')?.value || '56', 10),
    floating_button_opacity: parseInt(document.getElementById('range-fab-opacity')?.value || '70', 10),
    floating_button_locked: document.getElementById('toggle-floating-lock')?.checked || false,
    floating_button_border: document.getElementById('toggle-floating-border')?.checked || false,
    floating_button_shape: document.querySelector('.fab-shape-option.selected')?.dataset?.shape || 'circle',
    floating_button_content: document.querySelector('.fab-content-option.selected')?.dataset?.content || 'microphone',
    floating_button_animation: document.getElementById('select-fab-animation')?.value || 'none',
    floating_button_sound: document.getElementById('select-fab-sound')?.value || 'none',
    floating_button_auto_hide: document.getElementById('select-fab-autohide')?.value || 'never',
    floating_button_auto_hide_timeout: parseInt(document.getElementById('range-fab-autohide-timeout')?.value || '10', 10),
    cloud_stt_provider: document.getElementById('select-cloud-stt-provider')?.value || 'openai',
    cloud_llm_provider: document.getElementById('select-cloud-llm-provider')?.value || 'openai',
    cloud_llm_model: document.getElementById('input-cloud-llm-model')?.value || '',
    groq_api_key: sharedFieldValue('input-groq-apikey', 'input-cloud-llm-groq-apikey'),
    deepgram_api_key: document.getElementById('input-deepgram-apikey')?.value || '',
    anthropic_api_key: document.getElementById('input-anthropic-apikey')?.value || '',
    gemini_api_key: document.getElementById('input-gemini-apikey')?.value || '',
    custom_dictionary: (document.getElementById('input-custom-dictionary')?.value || '').split(/[,\n]/).map(s => s.trim()).filter(Boolean),
    gpu_acceleration: document.getElementById('select-gpu-mode')?.value || 'auto',
    auto_tag_enabled: document.getElementById('toggle-auto-tag')?.checked ?? true,
    auto_title_enabled: document.getElementById('toggle-auto-title')?.checked ?? true
  };
}

/* ── Apply Config to Form ─────────────────────────────── */
function applyConfig(cfg) {
  if (!cfg) return;
  if (cfg.api_key != null) {
    const el = document.getElementById('input-apikey');
    if (el) el.value = cfg.api_key;
    const llmEl = document.getElementById('input-cloud-llm-openai-apikey');
    if (llmEl) llmEl.value = cfg.api_key;
  }
  if (cfg.mode) selectMode(cfg.mode);
  if (cfg.language) { const el = document.getElementById('select-language'); if (el) el.value = cfg.language; }
  if (cfg.overlay_position) selectOverlay(cfg.overlay_position);
  if (cfg.play_sounds != null) { const el = document.getElementById('toggle-sound'); if (el) el.checked = cfg.play_sounds; }
  if (cfg.sound_volume != null) {
    const pct = Math.round(cfg.sound_volume * 100);
    const slider = document.getElementById('volume-slider');
    const label = document.getElementById('volume-value');
    if (slider) slider.value = pct;
    if (label) label.textContent = pct + '%';
  }
  if (cfg.auto_paste != null) { const el = document.getElementById('toggle-autopaste'); if (el) el.checked = cfg.auto_paste; }
  { const apDelay = document.getElementById('range-auto-paste-delay'); if (apDelay) { apDelay.value = cfg.auto_paste_delay || 0; updateAutoPasteDelayLabel(apDelay.value); } }
  if (cfg.check_updates != null) { const el = document.getElementById('toggle-updates'); if (el) el.checked = cfg.check_updates; }
  if (cfg.autostart != null) { const el = document.getElementById('toggle-autostart'); if (el) el.checked = cfg.autostart; }
  { const el = document.getElementById('toggle-close-to-tray'); if (el) el.checked = cfg.close_to_tray !== false; }
  { const el = document.getElementById('toggle-archive-instead'); if (el) el.checked = cfg.delete_behavior === 'archive'; }
  updateCloseToTrayDependents();
  if (cfg.theme) {
    const el = document.getElementById('select-theme');
    if (el) el.value = cfg.theme;
    applyTheme(cfg.theme);
  }
  // Preserve non-editable fields for round-tripping
  if (cfg.hotkey_modifiers && Array.isArray(cfg.hotkey_modifiers) && cfg.hotkey_modifiers.length > 0) {
    _savedHotkeyMods = cfg.hotkey_modifiers;
    _savedHotkeyKey = cfg.hotkey_key || 'D';
  }
  setHotkeyDisplay([..._savedHotkeyMods, _savedHotkeyKey]);
  if (cfg.model) _savedModel = cfg.model;
  if (cfg.ui_language) _savedUILang = cfg.ui_language;
  if (cfg.api_endpoint != null) _savedAPIEndpoint = cfg.api_endpoint;
  if (cfg.max_record_sec != null) {
    const slider = document.getElementById('range-max-duration');
    if (slider) slider.value = cfg.max_record_sec;
    updateDurationLabel(cfg.max_record_sec);
  }
  if (cfg.smart_mode != null) {
    const el = document.getElementById('toggle-smartmode');
    if (el) el.checked = cfg.smart_mode;
    updateSmartModeVisibility();
  }
  if (cfg.smart_mode_preset) {
    const el = document.getElementById('select-smartpreset');
    if (el) el.value = cfg.smart_mode_preset;
    document.querySelectorAll('.preset-card').forEach(c => {
      c.classList.toggle('active', c.dataset.preset === cfg.smart_mode_preset);
    });
    updateSmartPresetVisibility();
  }
  if (cfg.smart_mode_prompt != null) { const el = document.getElementById('input-smartprompt'); if (el) el.value = cfg.smart_mode_prompt; }
  if (cfg.smart_mode_target) { const el = document.getElementById('select-smarttarget'); if (el) el.value = cfg.smart_mode_target; }
  {
    const provider = cfg.smart_mode_provider || 'auto';
    const safe = ['local', 'cloud', 'auto'].includes(provider) ? provider : 'auto';
    const radioVal = safe === 'auto' ? 'local' : safe;
    const radio = document.querySelector('[name="smartProvider"][value="' + radioVal + '"]');
    if (radio) radio.checked = true;
  }
  {
    const provider = cfg.text_replacement_provider || 'local';
    const safe = ['local', 'cloud'].includes(provider) ? provider : 'local';
    const radio = document.querySelector('[name="textReplaceProvider"][value="' + safe + '"]');
    if (radio) radio.checked = true;
  }
  renderModelList();
  updateLLMStatus();
  // Cache active model type for sync access (e.g. language switch badge update)
  window._activeModelLocal = !!cfg.active_model_local;

  { const el = document.getElementById('toggle-notify-bg'); if (el) el.checked = cfg.notify_background !== false; }
  { const el = document.getElementById('toggle-notify-complete'); if (el) el.checked = cfg.notify_complete !== false; }
  { const el = document.getElementById('toggle-notify-donate'); if (el) el.checked = cfg.notify_donate !== false; }
  if (cfg.input_device != null) { const el = document.getElementById('select-audiodevice'); if (el) el.value = cfg.input_device; }
  if (cfg.input_gain != null) {
    const el = document.getElementById('range-input-gain');
    const label = document.getElementById('input-gain-value');
    if (el) { el.value = Math.round(cfg.input_gain * 100); }
    if (label) { label.textContent = cfg.input_gain.toFixed(1) + 'x'; }
  }
  { const el = document.getElementById('toggle-cleanup'); if (el) el.checked = !!cfg.cleanup_enabled; }
  if (cfg.cleanup_max_entries != null) { const el = document.getElementById('input-cleanup-max-entries'); if (el) el.value = cfg.cleanup_max_entries; }
  if (cfg.cleanup_max_age_days != null) { const el = document.getElementById('input-cleanup-max-age'); if (el) el.value = cfg.cleanup_max_age_days; }
  { const el = document.getElementById('toggle-cleanup-pinned'); if (el) el.checked = !!cfg.cleanup_include_pinned; }
  updateCleanupDependents();
  { const el = document.getElementById('toggle-use-vad'); if (el) el.checked = !!cfg.use_vad; }
  {
    const sens = cfg.vad_sensitivity != null ? cfg.vad_sensitivity : 0.5;
    const slider = document.getElementById('range-vad-sensitivity');
    const label = document.getElementById('vad-sensitivity-value');
    if (slider) slider.value = Math.round(sens * 100);
    if (label) label.textContent = sens.toFixed(2);
    const row = document.getElementById('vad-sensitivity-row');
    if (row) row.classList.toggle('hidden', !cfg.use_vad);
  }
  { const el = document.getElementById('toggle-floating-btn'); if (el) el.checked = !!cfg.floating_button_enabled; }
  { const fab = document.getElementById('captureBtn'); if (fab) fab.classList.toggle('hidden', !!cfg.floating_button_enabled); }
  {
    const color = cfg.floating_button_color || 'cyan';
    document.querySelectorAll('.fab-color-option').forEach(el => {
      el.classList.toggle('selected', el.dataset.color === color);
    });
    const customInput = document.querySelector('.fab-custom-color-input');
    if (customInput && cfg.floating_button_custom_color) {
      customInput.value = cfg.floating_button_custom_color;
    }
    const row = document.getElementById('fab-color-row');
    if (row) row.classList.toggle('hidden', !cfg.floating_button_enabled);
    const sizeRow = document.getElementById('fab-size-row');
    if (sizeRow) sizeRow.classList.toggle('hidden', !cfg.floating_button_enabled);
    const opacityRow = document.getElementById('fab-opacity-row');
    if (opacityRow) opacityRow.classList.toggle('hidden', !cfg.floating_button_enabled);
    const lockRow = document.getElementById('fab-lock-row');
    if (lockRow) lockRow.classList.toggle('hidden', !cfg.floating_button_enabled);
    const borderRow = document.getElementById('fab-border-row');
    if (borderRow) borderRow.classList.toggle('hidden', !cfg.floating_button_enabled);
    const shapeRow = document.getElementById('fab-shape-row');
    if (shapeRow) shapeRow.classList.toggle('hidden', !cfg.floating_button_enabled);
  }
  {
    const sz = cfg.floating_button_size || 56;
    const slider = document.getElementById('range-fab-size');
    const label = document.getElementById('fab-size-value');
    if (slider) slider.value = sz;
    if (label) label.textContent = sz + ' px';
  }
  {
    const opacity = cfg.floating_button_opacity || 70;
    const slider = document.getElementById('range-fab-opacity');
    const label = document.getElementById('fab-opacity-value');
    if (slider) slider.value = opacity;
    if (label) label.textContent = opacity + '%';
  }
  { const el = document.getElementById('toggle-floating-lock'); if (el) el.checked = !!cfg.floating_button_locked; }
  { const el = document.getElementById('toggle-floating-border'); if (el) el.checked = !!cfg.floating_button_border; }
  {
    const shape = cfg.floating_button_shape || 'circle';
    document.querySelectorAll('.fab-shape-option').forEach(el => {
      el.classList.toggle('selected', el.dataset.shape === shape);
    });
  }
  {
    const content = cfg.floating_button_content || 'microphone';
    document.querySelectorAll('.fab-content-option').forEach(el => {
      el.classList.toggle('selected', el.dataset.content === content);
    });
    const contentRow = document.getElementById('fab-content-row');
    if (contentRow) contentRow.classList.toggle('hidden', !cfg.floating_button_enabled);
  }
  {
    const el = document.getElementById('select-fab-animation');
    if (el) el.value = cfg.floating_button_animation || 'none';
    const row = document.getElementById('fab-animation-row');
    if (row) row.classList.toggle('hidden', !cfg.floating_button_enabled);
  }
  {
    const el = document.getElementById('select-fab-sound');
    if (el) el.value = cfg.floating_button_sound || 'none';
    const row = document.getElementById('fab-sound-row');
    if (row) row.classList.toggle('hidden', !cfg.floating_button_enabled);
  }
  {
    const el = document.getElementById('select-fab-autohide');
    if (el) el.value = cfg.floating_button_auto_hide || 'never';
    const row = document.getElementById('fab-autohide-row');
    if (row) row.classList.toggle('hidden', !cfg.floating_button_enabled);
    const timeoutRow = document.getElementById('fab-autohide-timeout-row');
    if (timeoutRow) timeoutRow.style.display = (cfg.floating_button_auto_hide === 'timeout' && cfg.floating_button_enabled) ? '' : 'none';
    const timeout = cfg.floating_button_auto_hide_timeout || 10;
    const slider = document.getElementById('range-fab-autohide-timeout');
    const label = document.getElementById('fab-autohide-timeout-value');
    if (slider) slider.value = timeout;
    if (label) label.textContent = timeout + 's';
  }
  {
    const el = document.getElementById('toggle-app-detection');
    if (el) el.checked = !!cfg.app_detection;
    updateAppDetectionState();
  }
  // Cloud STT Provider
  {
    const el = document.getElementById('select-cloud-stt-provider');
    if (el && cfg.cloud_stt_provider) el.value = cfg.cloud_stt_provider;
    updateCloudSTTFields(true);
  }
  // Cloud LLM Provider
  {
    const el = document.getElementById('select-cloud-llm-provider');
    if (el && cfg.cloud_llm_provider) el.value = cfg.cloud_llm_provider;
  }
  if (cfg.cloud_llm_model != null) {
    const el = document.getElementById('input-cloud-llm-model');
    if (el) el.value = cfg.cloud_llm_model;
  }
  // Provider API keys
  if (cfg.groq_api_key != null) {
    const el = document.getElementById('input-groq-apikey');
    if (el) el.value = cfg.groq_api_key;
    const llmEl = document.getElementById('input-cloud-llm-groq-apikey');
    if (llmEl) llmEl.value = cfg.groq_api_key;
  }
  if (cfg.deepgram_api_key != null) { const el = document.getElementById('input-deepgram-apikey'); if (el) el.value = cfg.deepgram_api_key; }
  if (cfg.anthropic_api_key != null) { const el = document.getElementById('input-anthropic-apikey'); if (el) el.value = cfg.anthropic_api_key; }
  if (cfg.gemini_api_key != null) { const el = document.getElementById('input-gemini-apikey'); if (el) el.value = cfg.gemini_api_key; }
  // Custom Dictionary
  if (cfg.custom_dictionary != null && Array.isArray(cfg.custom_dictionary)) {
    const el = document.getElementById('input-custom-dictionary');
    if (el) el.value = cfg.custom_dictionary.join(', ');
  }
  // GPU Acceleration
  if (cfg.gpu_acceleration) {
    const el = document.getElementById('select-gpu-mode');
    if (el) el.value = cfg.gpu_acceleration;
  }
  renderGPUStatus();
  toggleCloudLLMSection();
  updateCloudLLMFields(true);

  // Auto-Tag & Auto-Title
  { const el = document.getElementById('toggle-auto-tag'); if (el) el.checked = cfg.auto_tag_enabled !== false; }
  { const el = document.getElementById('toggle-auto-title'); if (el) el.checked = cfg.auto_title_enabled !== false; }
}


/* ── FAB slider label helpers ─────────────────────────── */
function updateFabOpacityLabel(value) {
  const label = document.getElementById('fab-opacity-value');
  if (label) label.textContent = value + '%';
}
function updateFabAutoHideTimeoutLabel(value) {
  const label = document.getElementById('fab-autohide-timeout-value');
  if (label) label.textContent = value + 's';
}

/* ── Test Sound ───────────────────────────────────────── */
function testSound() {
  if (window._testSound) window._testSound();
}

/* ── Auto Save (debounced) ─────────────────────────────── */
function autoSave() {
  if (!_configLoaded) return;
  clearTimeout(_autoSaveTimer);
  _autoSaveTimer = setTimeout(() => saveSettings(), DEBOUNCE_MS); // DevSkim: ignore DS172411 — debounce with constant delay
}

/* ── Save Settings ────────────────────────────────────── */
async function saveSettings() {
  try {
    const cfg = gatherConfig();
    if (window.saveConfig) {
      const result = await window.saveConfig(JSON.stringify(cfg));
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showStatus(t('statusAutoSaved'), 'success');
        // Re-read full config from Go (includes active_model_local etc.)
        const freshRaw = await window.getConfig();
        const freshCfg = typeof freshRaw === 'string' ? JSON.parse(freshRaw) : freshRaw;
        updateModeBadge(freshCfg);
        updateStatusBar(freshCfg);
      } else {
        showStatus(res?.error || t('statusError'), 'error');
      }
    } else {
      showStatus(t('statusAutoSaved'), 'success');
      updateModeBadge(cfg);
      updateStatusBar(cfg);
    }
  } catch (err) {
    showStatus(t('statusError'), 'error');
  }
}

/* ── Cloud Provider Helpers ──────────────────────────── */
function updateCloudSTTFields(silent) {
  const provider = document.getElementById('select-cloud-stt-provider')?.value || 'openai';
  const openaiRow = document.getElementById('cloud-stt-openai-key-row');
  const groqRow = document.getElementById('cloud-stt-groq-key-row');
  const deepgramRow = document.getElementById('cloud-stt-deepgram-key-row');
  if (openaiRow) openaiRow.classList.toggle('hidden', provider !== 'openai');
  if (groqRow) groqRow.classList.toggle('hidden', provider !== 'groq');
  if (deepgramRow) deepgramRow.classList.toggle('hidden', provider !== 'deepgram');
  if (!silent) autoSave();
}

function updateCloudLLMFields(silent) {
  const provider = document.getElementById('select-cloud-llm-provider')?.value || 'openai';
  const openaiRow = document.getElementById('cloud-llm-openai-key-row');
  const groqRow = document.getElementById('cloud-llm-groq-key-row');
  const anthropicRow = document.getElementById('cloud-llm-anthropic-key-row');
  const geminiRow = document.getElementById('cloud-llm-gemini-key-row');
  if (openaiRow) openaiRow.classList.toggle('hidden', provider !== 'openai');
  if (groqRow) groqRow.classList.toggle('hidden', provider !== 'groq');
  if (anthropicRow) anthropicRow.classList.toggle('hidden', provider !== 'anthropic');
  if (geminiRow) geminiRow.classList.toggle('hidden', provider !== 'gemini');
  const modelInput = document.getElementById('input-cloud-llm-model');
  const modelHint = document.getElementById('cloud-llm-model-hint');
  const defaults = {
    openai: 'gpt-4o-mini',
    anthropic: 'claude-sonnet-4-20250514',
    gemini: 'gemini-2.5-flash',
    groq: 'llama-3.3-70b-versatile'
  };
  if (modelInput) modelInput.placeholder = defaults[provider] || '';
  if (modelHint) modelHint.textContent = t('cloudLLMModelHint').replace('{model}', defaults[provider] || '');
  if (!silent) autoSave();
}

function syncSharedAPIKeys(sourceId, targetId) {
  const source = document.getElementById(sourceId);
  const target = document.getElementById(targetId);
  if (!source || !target || target.value === source.value) return;
  target.value = source.value;
}

function toggleCloudLLMSection() {
  const smartCloud = document.querySelector('[name="smartProvider"][value="cloud"]')?.checked;
  const replaceCloud = document.querySelector('[name="textReplaceProvider"][value="cloud"]')?.checked;
  const card = document.getElementById('cloud-llm-card');
  if (card) card.classList.toggle('hidden', !smartCloud && !replaceCloud);
}

function toggleKeyVisibility(inputId, btn) {
  const input = document.getElementById(inputId);
  if (!input || !btn) return;
  if (input.type === 'password') {
    input.type = 'text';
    btn.setAttribute('aria-label', t('eyeHide'));
    btn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/></svg>';
  } else {
    input.type = 'password';
    btn.setAttribute('aria-label', t('eyeShow'));
    btn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/></svg>';
  }
}

async function renderGPUStatus() {
  const line = document.getElementById('gpu-status-line');
  if (!line || !window.getGPUInfo) return;
  const mode = document.getElementById('select-gpu-mode')?.value || 'auto';
  try {
    const raw = await window.getGPUInfo(mode);
    const info = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const hasGPU = info && info.available;
    if (mode === 'disabled') {
      line.innerHTML = '<span style="color:var(--text-secondary)">—</span> ' + t('gpuDisabledStatus');
    } else if (hasGPU) {
      const vram = info.vram_mb ? ' (' + info.vram_mb + ' MB VRAM)' : '';
      const sttBackend = (info.stt_backend || 'cpu').toUpperCase();
      const llmBackend = (info.llm_backend || 'cpu').toUpperCase();
      let detail = `${t('gpuStatusStt')}: ${sttBackend} · ${t('gpuStatusSmart')}: ${llmBackend}`;
      if (sttBackend === 'CPU' && llmBackend !== 'CPU') {
        detail += ` · ${t('gpuStatusMixedHint')}`;
      }
      line.innerHTML = '<span style="color:var(--accent-green)">✓</span> ' + t('gpuDetectedHardware') + ': ' + info.name + vram + ' · ' + detail;
    } else {
      line.innerHTML = '<span style="color:var(--text-secondary)">—</span> ' + t('gpuNotDetected');
    }
  } catch (e) {
    line.textContent = t('gpuDetectionFailed');
  }
}
