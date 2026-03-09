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

// Floating button color picker — delegated click handler
document.addEventListener('click', function(e) {
  const opt = e.target.closest('.fab-color-option');
  if (!opt) return;
  document.querySelectorAll('.fab-color-option').forEach(el => el.classList.remove('selected'));
  opt.classList.add('selected');
  if (typeof autoSave === 'function') autoSave();
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
    const row = document.getElementById('fab-color-row');
    if (row) row.classList.toggle('hidden', !e.target.checked);
    const sizeRow = document.getElementById('fab-size-row');
    if (sizeRow) sizeRow.classList.toggle('hidden', !e.target.checked);
    const fab = document.getElementById('captureBtn');
    if (fab) fab.classList.toggle('hidden', e.target.checked);
  }
});

/* ── Gather Config from Form ──────────────────────────── */
function gatherConfig() {
  return {
    api_key: document.getElementById('input-apikey')?.value || '',
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

    notify_background: document.getElementById('toggle-notify-bg')?.checked ?? true,
    notify_complete: document.getElementById('toggle-notify-complete')?.checked ?? true,
    notify_donate: document.getElementById('toggle-notify-donate')?.checked ?? true,
    input_device: document.getElementById('select-audiodevice')?.value || '',
    input_gain: parseInt(document.getElementById('range-input-gain')?.value || '100', 10) / 100.0,
    cleanup_enabled: document.getElementById('toggle-cleanup')?.checked || false,
    cleanup_max_entries: parseInt(document.getElementById('input-cleanup-max-entries')?.value || '0', 10),
    cleanup_max_age_days: parseInt(document.getElementById('input-cleanup-max-age')?.value || '0', 10),
    cleanup_include_pinned: document.getElementById('toggle-cleanup-pinned')?.checked || false,
    trim_silence: document.getElementById('toggle-trim-silence')?.checked || false,
    use_vad: document.getElementById('toggle-use-vad')?.checked || false,
    vad_sensitivity: parseInt(document.getElementById('range-vad-sensitivity')?.value || '50', 10) / 100.0,
    floating_button_enabled: document.getElementById('toggle-floating-btn')?.checked || false,
    floating_button_color: document.querySelector('.fab-color-option.selected')?.dataset?.color || 'cyan',
    floating_button_size: parseInt(document.getElementById('range-fab-size')?.value || '56', 10)
  };
}

/* ── Apply Config to Form ─────────────────────────────── */
function applyConfig(cfg) {
  if (!cfg) return;
  if (cfg.api_key != null) { const el = document.getElementById('input-apikey'); if (el) el.value = cfg.api_key; }
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
    _savedHotkeyKey = cfg.hotkey_key || 'V';
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
  renderModelList();
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
  { const el = document.getElementById('toggle-trim-silence'); if (el) el.checked = !!cfg.trim_silence; }
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
    const row = document.getElementById('fab-color-row');
    if (row) row.classList.toggle('hidden', !cfg.floating_button_enabled);
    const sizeRow = document.getElementById('fab-size-row');
    if (sizeRow) sizeRow.classList.toggle('hidden', !cfg.floating_button_enabled);
  }
  {
    const sz = cfg.floating_button_size || 56;
    const slider = document.getElementById('range-fab-size');
    const label = document.getElementById('fab-size-value');
    if (slider) slider.value = sz;
    if (label) label.textContent = sz + ' px';
  }
  {
    const el = document.getElementById('toggle-app-detection');
    if (el) el.checked = !!cfg.app_detection;
    updateAppDetectionState();
  }
}


/* ── Test Sound ───────────────────────────────────────── */
function testSound() {
  if (window._testSound) window._testSound();
}

/* ── Auto Save (debounced) ─────────────────────────────── */
function autoSave() {
  if (!_configLoaded) return;
  clearTimeout(_autoSaveTimer);
  _autoSaveTimer = setTimeout(() => saveSettings(), DEBOUNCE_MS);
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
        updateModeBadge(cfg);
        updateStatusBar(cfg);
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
