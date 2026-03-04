/* ── Settings Page Logic ───────────────────────────────── */

// Preserved config fields not editable via form controls
let _savedHotkeyMods = ['Ctrl', 'Shift'];
let _savedHotkeyKey = 'V';
let _savedModel = 'whisper-1';
let _savedUILang = '';
let _savedAPIEndpoint = '';
let _downloadingModel = null;

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
    ui_language: _savedUILang,
    theme: document.getElementById('select-theme')?.value || 'system',
    max_record_sec: document.getElementById('check-unlimited-duration')?.checked ? 0 : parseInt(document.getElementById('range-max-duration')?.value || '120', 10),
    smart_mode: document.getElementById('toggle-smartmode')?.checked || false,
    smart_mode_preset: document.getElementById('select-smartpreset')?.value || 'cleanup',
    smart_mode_prompt: document.getElementById('input-smartprompt')?.value || '',
    smart_mode_target: document.getElementById('select-smarttarget')?.value || 'en',
    use_local_stt: document.getElementById('toggle-localstt')?.checked || false,
    local_model_id: document.querySelector('[name="local-model"]:checked')?.value || 'whisper-tiny'
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
    const lbl = document.getElementById('max-duration-value');
    const chk = document.getElementById('check-unlimited-duration');
    if (cfg.max_record_sec === 0) {
      if (chk) chk.checked = true;
      toggleUnlimited(true);
    } else {
      if (chk) chk.checked = false;
      if (slider) { slider.value = cfg.max_record_sec; if (lbl) lbl.textContent = cfg.max_record_sec + 's'; }
      toggleUnlimited(false);
    }
  }
  if (cfg.smart_mode != null) {
    const el = document.getElementById('toggle-smartmode');
    if (el) el.checked = cfg.smart_mode;
    updateSmartModeVisibility();
  }
  if (cfg.smart_mode_preset) {
    const el = document.getElementById('select-smartpreset');
    if (el) el.value = cfg.smart_mode_preset;
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
}

/* ── Radio Card Selection ─────────────────────────────── */
function selectMode(mode) {
  document.querySelectorAll('[name="mode"]').forEach(r => {
    const card = r.closest('.radio-card');
    const selected = r.value === mode;
    r.checked = selected;
    if (card) card.setAttribute('aria-checked', selected ? 'true' : 'false');
  });
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
    setTimeout(() => cancelHotkeyRecording(), 300);
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

/* ── Unlimited Duration ───────────────────────────────── */
function toggleUnlimited(checked) {
  const slider = document.getElementById('range-max-duration');
  const label = document.getElementById('max-duration-value');
  if (checked) {
    if (slider) { slider.disabled = true; slider.style.opacity = '0.4'; }
    if (label) label.textContent = '∞';
  } else {
    if (slider) { slider.disabled = false; slider.style.opacity = '1'; }
    if (label && slider) label.textContent = slider.value + 's';
  }
}

/* ── Smart Mode Visibility ────────────────────────────── */
function updateSmartModeVisibility() {
  const on = document.getElementById('toggle-smartmode')?.checked;
  const section = document.getElementById('smart-mode-options');
  if (section) {
    if (on) section.classList.add('visible');
    else section.classList.remove('visible');
  }
  if (on) updateSmartPresetVisibility();
}

function updateSmartPresetVisibility() {
  const preset = document.getElementById('select-smartpreset')?.value;
  const targetRow = document.getElementById('smart-target-row');
  const promptRow = document.getElementById('smart-prompt-row');
  if (targetRow) targetRow.style.display = preset === 'translate' ? 'block' : 'none';
  if (promptRow) promptRow.style.display = preset === 'custom' ? 'block' : 'none';
}

/* ── Test Sound ───────────────────────────────────────── */
function testSound() {
  if (window._testSound) window._testSound();
}

/* ── Save Settings ────────────────────────────────────── */
async function saveSettings() {
  const btn = document.getElementById('btn-save');
  if (btn) btn.disabled = true;
  try {
    const cfg = gatherConfig();
    if (window.saveConfig) {
      const result = await window.saveConfig(JSON.stringify(cfg));
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showStatus(t('statusSaved'), 'success');
      } else {
        showStatus(res?.error || t('statusError'), 'error');
      }
    } else {
      showStatus(t('statusSaved'), 'success');
    }
  } catch (err) {
    showStatus(t('statusError'), 'error');
  } finally {
    if (btn) btn.disabled = false;
  }
}

/* ── Cancel / Close ───────────────────────────────────── */
function cancelSettings() {
  if (window.closeWindow) window.closeWindow();
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
      { id: 'whisper-tiny', name: 'Whisper Tiny', size: '39MB', downloaded: false },
      { id: 'whisper-base', name: 'Whisper Base', size: '74MB', downloaded: false },
      { id: 'whisper-small', name: 'Whisper Small', size: '244MB', downloaded: false }
    ];
  }
  
  const selectedModel = document.querySelector('[name="local-model"]:checked')?.value || 'whisper-tiny';
  
  container.innerHTML = models.map(m => {
    const isSelected = m.id === selectedModel;
    const isDownloading = _downloadingModel === m.id;
    let actionBtn;
    if (isDownloading) {
      actionBtn = `<button class="btn btn-secondary btn-sm" disabled>${t('modelDownloading')}</button>
        <div class="model-progress"><div class="model-progress-bar" id="progress-${m.id}"></div></div>`;
    } else if (m.downloaded) {
      actionBtn = `<button class="btn btn-secondary btn-sm" onclick="deleteModel('${m.id}')" title="${t('modelDelete')}">${t('modelDownloaded')}</button>`;
    } else {
      actionBtn = `<button class="btn btn-primary btn-sm" onclick="downloadModel('${m.id}')">${t('modelDownload')}</button>`;
    }
    return `<div class="model-item ${isSelected ? 'active' : ''}">
      <input type="radio" name="local-model" value="${m.id}" class="model-item-radio" ${isSelected ? 'checked' : ''} ${!m.downloaded ? 'disabled' : ''} onchange="selectLocalModel('${m.id}')">
      <div class="model-item-info">
        <div class="model-item-name">${m.name}</div>
        <div class="model-item-meta">${m.size}</div>
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
}

async function downloadModel(id) {
  _downloadingModel = id;
  renderModelList();
  
  if (window._downloadModel) {
    try {
      const result = await window._downloadModel(id);
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showStatus(t('modelDownloadDone'), 'success');
        _downloadingModel = null;
        await renderModelList();
        selectLocalModel(id);
        const radio = document.querySelector(`[name="local-model"][value="${id}"]`);
        if (radio) radio.disabled = false;
      } else {
        showStatus(res?.error || t('modelDownloadError'), 'error');
        _downloadingModel = null;
        renderModelList();
      }
    } catch (e) {
      showStatus(t('modelDownloadError'), 'error');
      _downloadingModel = null;
      renderModelList();
    }
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

// Go calls this to update download progress
window.updateModelProgress = function(modelId, pct) {
  const bar = document.getElementById('progress-' + modelId);
  if (bar) bar.style.width = pct + '%';
};
