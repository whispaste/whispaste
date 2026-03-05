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
    prompt: document.getElementById('input-prompt')?.value || '',
    overlay_position: document.querySelector('[name="overlay"]:checked')?.value || 'top_center',
    play_sounds: document.getElementById('toggle-sound')?.checked || false,
    sound_volume: parseInt(document.getElementById('volume-slider')?.value || '80', 10) / 100.0,
    auto_paste: document.getElementById('toggle-autopaste')?.checked || false,
    check_updates: document.getElementById('toggle-updates')?.checked || false,
    autostart: document.getElementById('toggle-autostart')?.checked || false,
    close_to_tray: document.getElementById('toggle-close-to-tray')?.checked ?? true,
    ui_language: _savedUILang,
    theme: document.getElementById('select-theme')?.value || 'system',
    max_record_sec: parseInt(document.getElementById('range-max-duration')?.value || '120', 10),
    smart_mode: document.getElementById('toggle-smartmode')?.checked || false,
    smart_mode_preset: document.getElementById('select-smartpreset')?.value || 'cleanup',
    smart_mode_prompt: document.getElementById('input-smartprompt')?.value || '',
    smart_mode_target: document.getElementById('select-smarttarget')?.value || 'en',
    use_local_stt: document.getElementById('toggle-localstt')?.checked || false,
    local_model_id: document.querySelector('[name="local-model"]:checked')?.value || 'whisper-base',
    transcription_language: document.getElementById('select-transcription-language')?.value || '',
    notify_background: document.getElementById('toggle-notify-bg')?.checked ?? true,
    notify_complete: document.getElementById('toggle-notify-complete')?.checked ?? true,
    notify_donate: document.getElementById('toggle-notify-donate')?.checked ?? true,
    input_device: document.getElementById('select-audiodevice')?.value || '',
    input_gain: parseInt(document.getElementById('range-input-gain')?.value || '100', 10) / 100.0,
    cleanup_enabled: document.getElementById('toggle-cleanup')?.checked || false,
    cleanup_max_entries: parseInt(document.getElementById('input-cleanup-max-entries')?.value || '0', 10),
    cleanup_max_age_days: parseInt(document.getElementById('input-cleanup-max-age')?.value || '0', 10),
    trim_silence: document.getElementById('toggle-trim-silence')?.checked || false
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
  if (cfg.prompt != null) { const el = document.getElementById('input-prompt'); if (el) el.value = cfg.prompt; }
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
  if (cfg.use_local_stt != null) {
    const el = document.getElementById('toggle-localstt');
    if (el) el.checked = cfg.use_local_stt;
    updateLocalSTTVisibility();
  }
  if (cfg.local_model_id) {
    const radio = document.querySelector(`[name="local-model"][value="${cfg.local_model_id}"]`);
    if (radio) {
      radio.checked = true;
      radio.closest('.model-item')?.classList.add('active');
    }
  }
  if (cfg.transcription_language != null) { const el = document.getElementById('select-transcription-language'); if (el) el.value = cfg.transcription_language; }
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
  updateCleanupDependents();
  { const el = document.getElementById('toggle-trim-silence'); if (el) el.checked = !!cfg.trim_silence; }
}

/* ── Cleanup toggle dependency ─────────────────────── */
function updateCleanupDependents() {
  const toggle = document.getElementById('toggle-cleanup');
  const btn = document.getElementById('btn-cleanup-now');
  const hint = document.getElementById('cleanup-hint');
  if (!toggle) return;
  const enabled = toggle.checked;
  if (btn) btn.disabled = !enabled;
  if (hint) hint.style.display = enabled ? '' : 'none';
}

async function doManualCleanup() {
  const btn = document.getElementById('btn-cleanup-now');
  if (!btn || btn.disabled) return;
  try {
    const removed = await window.manualCleanup();
    if (removed > 0) {
      showToast(t('cleanupResult').replace('{count}', removed));
    } else {
      showToast(t('cleanupResultNone'));
    }
  } catch (e) {
    showToast(t('cleanupResultNone'), true);
  }
}

/* ── Close-to-Tray / NotifyBackground dependency ───── */
function updateCloseToTrayDependents() {
  const closeToTray = document.getElementById('toggle-close-to-tray');
  const notifyBg = document.getElementById('toggle-notify-bg');
  if (!closeToTray || !notifyBg) return;
  notifyBg.disabled = !closeToTray.checked;
  if (!closeToTray.checked) notifyBg.checked = false;
}

/* ── Radio Card Selection ─────────────────────────────── */
function selectMode(mode) {
  document.querySelectorAll('[name="mode"]').forEach(r => {
    const card = r.closest('.radio-card');
    const selected = r.value === mode;
    r.checked = selected;
    if (card) card.setAttribute('aria-checked', selected ? 'true' : 'false');
  });
  autoSave();
}

function handleRadioKey(e, mode) {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectMode(mode); }
}

function selectOverlay(value) {
  document.querySelectorAll('[name="overlay"]').forEach(r => {
    const card = r.closest('.radio-card');
    const selected = r.value === value;
    r.checked = selected;
    if (card) card.setAttribute('aria-checked', selected ? 'true' : 'false');
  });
  autoSave();
}

function handleOverlayKey(e, value) {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectOverlay(value); }
}

/* ── Hotkey Display & Recorder ────────────────────────── */
function setHotkeyDisplay(keys) {
  const container = document.getElementById('hotkey-display');
  if (!container) return;
  container.innerHTML = '';
  keys.forEach((key, i) => {
    if (i > 0) {
      const plus = document.createElement('span');
      plus.className = 'hotkey-plus';
      plus.textContent = '+';
      container.appendChild(plus);
    }
    const span = document.createElement('span');
    span.className = 'hotkey-key';
    span.textContent = key;
    container.appendChild(span);
  });
  container.setAttribute('aria-label', 'Current hotkey: ' + keys.join(' + '));
}

let _hotkeyRecording = false;

function startHotkeyRecording() {
  _hotkeyRecording = true;
  const recorder = document.getElementById('hotkey-recorder');
  const btn = document.getElementById('btn-change-hotkey');
  if (recorder) recorder.style.display = 'block';
  if (btn) btn.style.display = 'none';
  const preview = document.getElementById('hotkey-preview');
  if (preview) preview.innerHTML = '';
  document.addEventListener('keydown', onHotkeyKeyDown, true);
  document.addEventListener('keyup', onHotkeyKeyUp, true);
}

function cancelHotkeyRecording() {
  _hotkeyRecording = false;
  const recorder = document.getElementById('hotkey-recorder');
  const btn = document.getElementById('btn-change-hotkey');
  if (recorder) recorder.style.display = 'none';
  if (btn) btn.style.display = '';
  document.removeEventListener('keydown', onHotkeyKeyDown, true);
  document.removeEventListener('keyup', onHotkeyKeyUp, true);
}

function normalizeKey(key) {
  const keyMap = {
    ' ': 'Space', 'Enter': 'Return', 'Escape': 'Escape',
    'Delete': 'Delete', 'Tab': 'Tab', 'Backspace': 'Backspace',
    'ArrowUp': null, 'ArrowDown': null, 'ArrowLeft': null, 'ArrowRight': null,
    'PageUp': null, 'PageDown': null, 'Home': null, 'End': null, 'Insert': null,
    'Dead': null, 'Unidentified': null, 'Meta': null
  };
  if (key in keyMap) return keyMap[key];
  if (/^[a-zA-Z0-9]$/.test(key)) return key.toUpperCase();
  if (/^F([1-9]|1[0-2])$/.test(key)) return key;
  return null;
}

function onHotkeyKeyDown(e) {
  e.preventDefault();
  e.stopPropagation();
  if (e.key === 'Escape') { cancelHotkeyRecording(); return; }
  const mods = [];
  if (e.ctrlKey) mods.push('Ctrl');
  if (e.shiftKey) mods.push('Shift');
  if (e.altKey) mods.push('Alt');
  const key = e.key;
  const isModOnly = ['Control', 'Shift', 'Alt', 'Meta'].includes(key);
  const normalized = isModOnly ? null : normalizeKey(key);
  const preview = document.getElementById('hotkey-preview');
  const parts = [...mods];
  if (normalized) parts.push(normalized);
  else if (!isModOnly) parts.push(key);
  if (preview) {
    preview.innerHTML = parts.map(k => `<span class="hotkey-key">${k}</span>`).join('<span class="hotkey-plus">+</span>');
  }
  if (normalized && mods.length > 0) {
    _savedHotkeyMods = mods;
    _savedHotkeyKey = normalized;
    setHotkeyDisplay([..._savedHotkeyMods, _savedHotkeyKey]);
    setTimeout(() => { cancelHotkeyRecording(); autoSave(); }, 300);
  }
}

function onHotkeyKeyUp(e) {
  e.preventDefault();
  e.stopPropagation();
}

/* ── API Key Visibility ───────────────────────────────── */
function toggleApiKeyVisibility() {
  const input = document.getElementById('input-apikey');
  const btn = document.getElementById('btn-eye');
  if (!input || !btn) return;
  if (input.type === 'password') {
    input.type = 'text';
    btn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/></svg>';
    btn.setAttribute('aria-label', t('eyeHide'));
  } else {
    input.type = 'password';
    btn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/></svg>';
    btn.setAttribute('aria-label', t('eyeShow'));
  }
}

function copyApiKey() {
  const input = document.getElementById('input-apikey');
  if (!input || !input.value) return;
  function showCopied() {
    const btn = document.getElementById('btn-copy-key');
    if (btn) {
      const orig = btn.innerHTML;
      btn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
      btn.style.color = 'var(--accent)';
      setTimeout(() => { btn.innerHTML = orig; btn.style.color = ''; }, 1500);
    }
  }
  // WebView2 data: URLs don't have navigator.clipboard — use execCommand fallback
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(input.value).then(showCopied).catch(() => {});
  } else {
    const prev = input.type;
    input.type = 'text';
    input.select();
    if (document.execCommand('copy')) showCopied();
    input.type = prev;
    window.getSelection().removeAllRanges();
  }
}

/* ── Duration Label ────────────────────────────────────── */
function updateDurationLabel(val) {
  const lbl = document.getElementById('max-duration-value');
  if (!lbl) return;
  const v = parseInt(val, 10);
  if (v === 0) {
    lbl.textContent = '∞';
  } else {
    lbl.textContent = Math.round(v / 60) + ' min';
  }
}

/* ── Smart Mode Visibility ────────────────────────────── */
function updateSmartModeVisibility() {
  const on = document.getElementById('toggle-smartmode')?.checked;
  const section = document.getElementById('smart-mode-options');
  const howto = document.getElementById('smart-howto');
  const appDetRow = document.getElementById('smart-app-detection-row');
  const appNotice = document.getElementById('smart-app-active-notice');
  const customTplSection = document.getElementById('smart-custom-templates-section');
  if (section) section.style.display = on ? '' : 'none';
  if (howto) howto.style.display = on ? '' : 'none';
  if (appDetRow) appDetRow.style.display = on ? '' : 'none';
  if (customTplSection) customTplSection.style.display = on ? '' : 'none';
  if (!on && appNotice) appNotice.style.display = 'none';
  if (on) {
    updateSmartPresetVisibility();
    updateAppDetectionState();
  }
}

function updateAppDetectionState() {
  const appDetOn = document.getElementById('toggle-app-detection')?.checked;
  const presetGrid = document.getElementById('preset-grid');
  const presetTitle = document.querySelector('#smart-mode-options .section-title');
  const appNotice = document.getElementById('smart-app-active-notice');
  const appRules = document.getElementById('smart-app-rules-section');
  if (presetGrid) {
    presetGrid.classList.toggle('disabled-overlay', !!appDetOn);
    presetGrid.style.pointerEvents = appDetOn ? 'none' : '';
    presetGrid.style.opacity = appDetOn ? '0.45' : '';
  }
  if (presetTitle) presetTitle.style.opacity = appDetOn ? '0.45' : '';
  if (appNotice) appNotice.style.display = appDetOn ? '' : 'none';
  if (appRules) appRules.style.display = appDetOn ? '' : 'none';
}

function onAppDetectionToggle() {
  const on = document.getElementById('toggle-app-detection')?.checked;
  if (window.setAppDetectionEnabled) window.setAppDetectionEnabled(on);
  updateAppDetectionState();
  if (on && window.loadAppPresets) window.loadAppPresets();
}

function updateSmartPresetVisibility() {
  const preset = document.getElementById('select-smartpreset')?.value;
  const targetRow = document.getElementById('smart-target-row');
  const promptRow = document.getElementById('smart-prompt-row');
  if (targetRow) targetRow.style.display = preset === 'translate' ? '' : 'none';
  if (promptRow) promptRow.style.display = preset === 'custom' ? '' : 'none';
}

function selectSmartPreset(preset) {
  document.querySelectorAll('.preset-card').forEach(c => {
    c.classList.toggle('active', c.dataset.preset === preset);
  });
  const sel = document.getElementById('select-smartpreset');
  if (sel) sel.value = preset;
  const targetRow = document.getElementById('smart-target-row');
  const promptRow = document.getElementById('smart-prompt-row');
  if (targetRow) targetRow.style.display = preset === 'translate' ? '' : 'none';
  if (promptRow) promptRow.style.display = preset === 'custom' ? '' : 'none';
  autoSave();
}

/* ── View Preset Prompt ──────────────────────────────── */
let _builtinPresetsCache = null;
async function viewPresetPrompt(key) {
  if (!_builtinPresetsCache) {
    try {
      const raw = await window.getBuiltinPresets();
      _builtinPresetsCache = typeof raw === 'string' ? JSON.parse(raw) : raw;
    } catch (e) {
      _builtinPresetsCache = {};
    }
  }
  let prompt = _builtinPresetsCache[key] || '';
  if (!prompt) {
    try {
      const raw = await window.getCustomTemplates();
      const custom = typeof raw === 'string' ? JSON.parse(raw) : raw;
      prompt = custom[key] || '';
    } catch (e) {}
  }
  if (!prompt) prompt = t('smartNoPrompt') || 'No prompt defined for this preset.';
  showDialog({
    title: t('smartViewPromptTitle') || 'Preset Prompt',
    message: prompt,
    variant: 'info',
    confirmText: t('ok') || 'OK'
  });
}

/* ── Test Sound ───────────────────────────────────────── */
function testSound() {
  if (window._testSound) window._testSound();
}

/* ── Auto Save (debounced) ─────────────────────────────── */
function autoSave() {
  if (!_configLoaded) return;
  clearTimeout(_autoSaveTimer);
  _autoSaveTimer = setTimeout(() => saveSettings(), 500);
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

/* ── Test Recording ───────────────────────────────────── */
let _isTesting = false;
async function testRecording() {
  if (_isTesting) return;
  const btn = document.getElementById('btn-test');
  const icon = document.getElementById('btn-test-icon');
  const text = document.getElementById('btn-test-text');

  _isTesting = true;
  if (btn) btn.classList.add('recording');
  if (icon) icon.innerHTML = '<span style="display:inline-block;width:10px;height:10px;background:#FF3B30;border-radius:50%;animation:pulse 1.2s ease infinite"></span>';
  if (text) text.textContent = t('statusTesting');
  showStatus(t('statusTesting'), 'success');

  try {
    if (window._doTestRecording) {
      const result = await window._doTestRecording();
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showStatus(`${t('statusTestDone')}: "${res.text}"`, 'success');
      } else {
        showStatus(res?.error || t('statusTestError'), 'error');
      }
    } else {
      await new Promise(r => setTimeout(r, 2000));
      showStatus(t('statusTestDone'), 'success');
    }
  } catch (err) {
    showStatus(t('statusTestError'), 'error');
  } finally {
    _isTesting = false;
    if (btn) btn.classList.remove('recording');
    if (icon) icon.innerHTML = icons.microphone;
    if (text) text.textContent = t('btnTest');
  }
}

// Go can call this to update test status live
window.updateTestStatus = function (status) {
  showStatus(status, 'success');
};

/* ── Audio Device List ────────────────────────────────── */
async function loadAudioDevices() {
  if (!window._getAudioDevices) return;
  try {
    const result = await window._getAudioDevices();
    const devices = typeof result === 'string' ? JSON.parse(result) : result;
    const sel = document.getElementById('select-audiodevice');
    if (!sel) return;
    while (sel.options.length > 1) sel.remove(1);
    devices.forEach(d => {
      const opt = document.createElement('option');
      opt.value = d.id;
      opt.textContent = d.name;
      sel.appendChild(opt);
    });
  } catch (e) {
    console.error('Failed to load audio devices:', e);
  }
}

/* ── Test Audio Input ─────────────────────────────────── */
let _testAudioInterval = null;
async function testAudioInput() {
  const meter = document.getElementById('audioLevelMeter');
  const bar = document.getElementById('audioLevelBar');
  const btn = document.getElementById('btn-test-audio');

  // Toggle off
  if (_testAudioInterval) {
    clearInterval(_testAudioInterval);
    _testAudioInterval = null;
    if (meter) meter.style.display = 'none';
    if (btn) btn.classList.remove('recording');
    try { if (window._stopAudioMonitor) await window._stopAudioMonitor(); } catch (e) {}
    return;
  }

  // Start monitoring
  try {
    if (window._startAudioMonitor) {
      const res = await window._startAudioMonitor();
      const r = typeof res === 'string' ? JSON.parse(res) : res;
      if (!r.success) {
        showStatus(r.error || t('statusTestError'), 'error');
        return;
      }
    }
  } catch (e) {
    showStatus(t('statusTestError'), 'error');
    return;
  }

  if (meter) meter.style.display = 'block';
  if (btn) btn.classList.add('recording');
  let count = 0;
  _testAudioInterval = setInterval(async () => {
    count++;
    if (count > 100) { // 10 seconds
      clearInterval(_testAudioInterval);
      _testAudioInterval = null;
      if (meter) meter.style.display = 'none';
      if (btn) btn.classList.remove('recording');
      try { if (window._stopAudioMonitor) await window._stopAudioMonitor(); } catch (e) {}
      return;
    }
    if (window._getAudioLevel) {
      try {
        const level = await window._getAudioLevel();
        const pct = Math.min(100, Math.round(parseFloat(level) * 100));
        if (bar) {
          bar.style.width = pct + '%';
          // Color: green < 60%, yellow 60-85%, red > 85%
          if (pct > 85) bar.style.background = 'var(--clr-error, #FF3B30)';
          else if (pct > 60) bar.style.background = 'var(--clr-warning, #FF9500)';
          else bar.style.background = 'var(--clr-success, #34C759)';
        }
      } catch (e) {}
    }
  }, 100);
}

/* ── Local STT Visibility ─────────────────────────────── */
function updateLocalSTTVisibility() {
  const on = document.getElementById('toggle-localstt')?.checked;
  const section = document.getElementById('local-stt-options');
  if (section) {
    section.style.display = on ? 'block' : 'none';
  }
  if (on) renderModelList();
}

/* ── Model List Rendering ─────────────────────────────── */
async function renderModelList() {
  const container = document.getElementById('model-list');
  if (!container) return;
  
  let models = [];
  if (window._getModels) {
    try {
      const result = await window._getModels();
      models = typeof result === 'string' ? JSON.parse(result) : result;
    } catch (e) {
      console.error('Failed to get models:', e);
    }
  }
  
  if (!models || models.length === 0) {
    models = [
      { id: 'whisper-base', name: 'Whisper Base', size: '74MB', downloaded: false },
      { id: 'whisper-small', name: 'Whisper Small', size: '244MB', downloaded: false }
    ];
  }
  
  const selectedModel = document.querySelector('[name="local-model"]:checked')?.value || 'whisper-base';
  
  container.innerHTML = models.map(m => {
    const isSelected = m.id === selectedModel;
    const isDownloading = _downloadingModel === m.id;
    let actionBtn;
    if (isDownloading) {
      actionBtn = `<button class="btn btn-secondary btn-sm" disabled>${t('modelDownloading')}</button>
        <div class="model-progress"><div class="model-progress-bar" id="progress-${m.id}"></div></div>`;
    } else if (m.downloaded) {
      actionBtn = `<span class="model-badge model-badge-success">✓ ${t('modelDownloaded')}</span><button class="btn btn-icon btn-sm btn-ghost" onclick="event.stopPropagation();confirmDeleteModel('${m.id}')" title="${t('modelDelete')}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>`;
    } else {
      actionBtn = `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();downloadModel('${m.id}')">${t('modelDownload')}</button>`;
    }
    return `<div class="model-item ${isSelected ? 'active' : ''} ${!m.downloaded && !isDownloading ? 'unavailable' : ''}" data-model-id="${m.id}" onclick="onModelCardClick('${m.id}', ${m.downloaded})">
      <input type="radio" name="local-model" value="${m.id}" class="model-item-radio" ${isSelected ? 'checked' : ''} ${!m.downloaded ? 'disabled' : ''}>
      <div class="model-item-info">
        <div class="model-item-name">${m.name}</div>
        ${t('model.desc.' + m.id) ? '<div class="model-desc">' + esc(t('model.desc.' + m.id)) + '</div>' : ''}
        <div class="model-item-meta">${m.size}${!m.downloaded ? ' · ' + t('modelNotDownloaded') : ''}</div>
      </div>
      <div class="model-item-action">${actionBtn}</div>
    </div>`;
  }).join('');
}

function selectLocalModel(id) {
  document.querySelectorAll('.model-item').forEach(el => el.classList.remove('active'));
  const radio = document.querySelector(`[name="local-model"][value="${id}"]`);
  if (radio) {
    radio.checked = true;
    radio.closest('.model-item')?.classList.add('active');
  }
  autoSave();
}

function onModelCardClick(id, downloaded) {
  if (downloaded) {
    selectLocalModel(id);
  } else {
    showToast(t('modelNeedDownload'), false);
  }
}

async function downloadModel(id) {
  _downloadingModel = id;
  renderModelList();
  
  if (window._downloadModel) {
    try {
      // Non-blocking: returns {started:true} immediately, completion via downloadComplete callback
      await window._downloadModel(id);
    } catch (e) {
      showStatus(t('modelDownloadError'), 'error');
      _downloadingModel = null;
      renderModelList();
    }
  }
}

// Go calls this when an async download completes
window.downloadComplete = function(modelId, success, errorMsg) {
  if (success) {
    showStatus(t('modelDownloadDone'), 'success');
    _downloadingModel = null;
    renderModelList();
    selectLocalModel(modelId);
    const radio = document.querySelector(`[name="local-model"][value="${modelId}"]`);
    if (radio) radio.disabled = false;
  } else {
    showStatus(errorMsg || t('modelDownloadError'), 'error');
    _downloadingModel = null;
    renderModelList();
  }
};

async function confirmDeleteModel(id) {
  const confirmed = await showConfirmDialog(
    t('modelDeleteConfirm'),
    t('modelDeleteConfirm'),
    { variant: 'danger', confirmText: t('notebook.confirm_delete') }
  );
  if (confirmed) {
    deleteModel(id);
  }
}

async function deleteModel(id) {
  if (window._deleteModel) {
    try {
      const result = await window._deleteModel(id);
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showStatus(t('modelDeleted'), 'success');
        renderModelList();
      } else {
        showStatus(res?.error || t('statusError'), 'error');
      }
    } catch (e) {
      showStatus(t('statusError'), 'error');
    }
  }
}

// Go calls this to update download progress (per-file)
window.updateModelProgress = function(modelId, pct, fileNum, fileCount, fileName) {
  const bar = document.getElementById('progress-' + modelId);
  if (bar) {
    // Approximate overall progress from file position + per-file pct
    const overallPct = Math.round(((fileNum - 1) + pct / 100) / fileCount * 100);
    bar.style.width = overallPct + '%';
  }
  const item = document.querySelector(`[data-model-id="${modelId}"]`);
  if (item) {
    const btn = item.querySelector('.model-item-action .btn');
    if (btn) {
      if (pct >= 100 && fileNum >= fileCount) {
        btn.textContent = '✓ ' + t('modelDownloaded');
      } else if (fileCount > 1) {
        btn.textContent = `${t('modelDownloadFile')} ${fileNum}/${fileCount}: ${fileName} (${pct}%)`;
      } else {
        btn.textContent = `${pct}%`;
      }
    }
  }
};
