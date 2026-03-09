/* ── Cleanup toggle dependency ─────────────────────── */
function updateCleanupDependents() {
  const toggle = document.getElementById('toggle-cleanup');
  const btn = document.getElementById('btn-cleanup-now');
  const hint = document.getElementById('cleanup-hint');
  if (!toggle) return;
  const enabled = toggle.checked;
  if (btn) btn.disabled = !enabled;
  if (hint) hint.classList.toggle('hidden', !enabled);
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

/* ── Test Notification Button ─────────────────────────── */
document.addEventListener('click', function(e) {
  if (e.target.closest('#btn-test-notification')) {
    if (window.testNotification) window.testNotification();
  }
});

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
    span.textContent = formatModKey(key);
    container.appendChild(span);
  });
  container.setAttribute('aria-label', 'Current hotkey: ' + formatHotkeyParts(keys).join(' + '));
}

let _hotkeyRecording = false;

function startHotkeyRecording() {
  _hotkeyRecording = true;
  const recorder = document.getElementById('hotkey-recorder');
  const btn = document.getElementById('btn-change-hotkey');
  if (recorder) recorder.classList.remove('hidden');
  if (btn) btn.classList.add('hidden');
  const preview = document.getElementById('hotkey-preview');
  if (preview) preview.innerHTML = '';
  document.addEventListener('keydown', onHotkeyKeyDown, true);
  document.addEventListener('keyup', onHotkeyKeyUp, true);
}

function cancelHotkeyRecording() {
  _hotkeyRecording = false;
  const recorder = document.getElementById('hotkey-recorder');
  const btn = document.getElementById('btn-change-hotkey');
  if (recorder) recorder.classList.add('hidden');
  if (btn) btn.classList.remove('hidden');
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
    preview.innerHTML = formatHotkeyParts(parts).map(k => `<span class="hotkey-key">${esc(k)}</span>`).join('<span class="hotkey-plus">+</span>');
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

function updateFabSizeLabel(val) {
  const lbl = document.getElementById('fab-size-value');
  if (lbl) lbl.textContent = val + ' px';
  if (typeof autoSave === 'function') autoSave();
}

/* ── Smart Mode Visibility ────────────────────────────── */
function updateSmartModeVisibility() {
  const toggle = document.getElementById('toggle-smartmode');
  const options = document.getElementById('smart-mode-options');
  const howto = document.getElementById('smart-howto');
  const appDetRow = document.getElementById('smart-app-detection-row');
  const appNotice = document.getElementById('smart-app-active-notice');

  const on = toggle ? toggle.checked : false;
  if (options) options.classList.toggle('hidden', !on);
  if (howto) howto.classList.toggle('hidden', !on);
  if (appDetRow) appDetRow.classList.toggle('hidden', !on);
  if (!on && appNotice) appNotice.classList.add('hidden');
  if (on) {
    updateSmartPresetVisibility();
    updateAppDetectionState();
    initSmartProvider();
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
  if (appNotice) appNotice.classList.toggle('hidden', !appDetOn);
  if (appRules) appRules.classList.toggle('hidden', !appDetOn);
}

function onAppDetectionToggle() {
  const on = document.getElementById('toggle-app-detection')?.checked;
  if (window.setAppDetectionEnabled) window.setAppDetectionEnabled(on);
  updateAppDetectionState();
  if (on && window.loadAppPresets) window.loadAppPresets();
  const explainer = document.getElementById('appDetectionExplainer');
  if (explainer) explainer.classList.toggle('hidden', !on);
}

function updateSmartPresetVisibility() {
  const preset = document.getElementById('select-smartpreset')?.value;
  const targetRow = document.getElementById('smart-target-row');
  const promptRow = document.getElementById('smart-prompt-row');
  if (targetRow) targetRow.classList.toggle('hidden', preset !== 'translate');
  if (promptRow) promptRow.classList.toggle('hidden', preset !== 'custom');
}

function selectSmartPreset(preset) {
  document.querySelectorAll('.preset-card').forEach(c => {
    c.classList.toggle('active', c.dataset.preset === preset);
  });
  const sel = document.getElementById('select-smartpreset');
  if (sel) sel.value = preset;
  const targetRow = document.getElementById('smart-target-row');
  const promptRow = document.getElementById('smart-prompt-row');
  if (targetRow) targetRow.classList.toggle('hidden', preset !== 'translate');
  if (promptRow) promptRow.classList.toggle('hidden', preset !== 'custom');
  autoSave();
}

/* ── Smart Mode Provider ──────────────────────────────── */

async function initSmartProvider() {
  await updateLLMStatus();
}

async function updateLLMStatus() {
  let status = { installed: false, running: false };
  try {
    if (window.getLLMStatus) {
      const raw = await window.getLLMStatus();
      status = typeof raw === 'string' ? JSON.parse(raw) : raw;
    }
  } catch (e) {}

  updateLLMBadge(status, 'llm-badge', 'llm-action-area', 'llm-progress');
  updateLLMBadge(status, 'settings-llm-badge', 'settings-llm-action-area', 'settings-llm-progress');
}

function updateLLMBadge(status, badgeId, actionId, progressId) {
  const badge = document.getElementById(badgeId);
  const actionArea = document.getElementById(actionId);
  const progress = document.getElementById(progressId);
  if (!badge) return;

  const isSettings = badgeId.startsWith('settings-');
  const downloadFn = isSettings ? 'startSettingsLLMDownload' : 'startLLMDownload';
  const connectId = isSettings ? 'settingsLlmConnectivityStatus' : 'llmConnectivityStatus';

  if (status.installed) {
    badge.className = 'llm-badge ready';
    badge.innerHTML = '<svg class="icon" style="width:12px;height:12px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> ' + t('smartLlmReady');
    if (actionArea) {
      const testBtnId = isSettings ? 'btn-test-llm-settings' : 'btn-test-llm';
      actionArea.innerHTML = `<button class="btn btn-secondary btn-sm btn-model-test" id="${testBtnId}" onclick="testLLMModel('${testBtnId}')"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg> ${t('modelTest')}</button> <button class="llm-delete-link" onclick="deleteLLM()">${t('smartLlmDelete')}</button>`;
    }
    if (progress) progress.classList.add('hidden');
  } else {
    badge.className = 'llm-badge not-installed';
    badge.textContent = t('smartLlmNotInstalled');
    if (actionArea) actionArea.innerHTML = `<button class="btn btn-primary btn-sm" onclick="${downloadFn}()">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>
      <span>${t('smartLlmDownload')}</span>
    </button>
    <div class="connectivity-status" id="${connectId}" style="display:none">
      <span class="connectivity-dot"></span>
      <span class="connectivity-text"></span>
    </div>`;
    updateConnectivityStatus(connectId);
  }
}

async function startLLMDownload() {
  const online = await updateConnectivityStatus('llmConnectivityStatus');
  if (!online) {
    showToast(t('connectivityRequired'), true);
    return;
  }
  const actionArea = document.getElementById('llm-action-area');
  const progress = document.getElementById('llm-progress');
  const badge = document.getElementById('llm-badge');
  if (actionArea) actionArea.innerHTML = '';
  if (progress) progress.classList.remove('hidden');
  if (badge) {
    badge.className = 'llm-badge not-installed';
    badge.textContent = t('smartLlmDownloading');
  }
  try {
    if (window.downloadLLM) await window.downloadLLM();
  } catch (e) {
    if (window.onLLMDownloadError) window.onLLMDownloadError(e.message || String(e));
  }
}

async function deleteLLM() {
  const ok = await showConfirmDialog(
    t('smartLlmDelete'),
    t('smartLlmDeleteConfirm')
  );
  if (!ok) return;
  try {
    if (window.deleteLLM) await window.deleteLLM();
    await updateLLMStatus();
  } catch (e) {}
}

async function testLLMModel(btnId) {
  const btn = document.getElementById(btnId);
  if (!btn || btn.disabled) return;
  btn.disabled = true;
  const origHTML = btn.innerHTML;
  btn.innerHTML = '<span class="spinner-sm"></span> ' + t('modelTesting');

  try {
    if (window._testLLMModel) {
      const result = await window._testLLMModel();
      const res = typeof result === 'string' ? JSON.parse(result) : result;
      if (res && res.success) {
        showToast(t('modelTestSuccess'), false);
      } else {
        showToast(res?.error || t('modelTestFailed'), true);
      }
    }
  } catch (e) {
    showToast(t('modelTestFailed'), true);
  } finally {
    btn.disabled = false;
    btn.innerHTML = origHTML;
  }
}

window.onLLMDownloadProgress = function(phase, pct) {
  ['', 'settings-'].forEach(prefix => {
    const fill = document.getElementById(prefix + 'llm-progress-fill');
    const text = document.getElementById(prefix + 'llm-progress-text');
    const progress = document.getElementById(prefix + 'llm-progress');
    if (progress) progress.classList.remove('hidden');
    if (fill) fill.style.width = pct + '%';
    const label = phase === 'server' ? t('smartLlmDownloadServer') : t('smartLlmDownloadModel');
    if (text) {
      text.textContent = label + ' ' + pct + '%';
      text.style.color = '';
    }
  });
};

window.onLLMDownloadError = function(errorMsg) {
  ['', 'settings-'].forEach(prefix => {
    const progress = document.getElementById(prefix + 'llm-progress');
    const text = document.getElementById(prefix + 'llm-progress-text');
    if (progress) progress.classList.remove('hidden');
    if (text) {
      text.textContent = errorMsg;
      text.style.color = 'var(--error)';
    }
  });
  updateLLMStatus();
};

window.onLLMDownloadComplete = function() {
  ['', 'settings-'].forEach(prefix => {
    const progress = document.getElementById(prefix + 'llm-progress');
    if (progress) progress.classList.add('hidden');
  });
  updateLLMStatus();
};

async function startSettingsLLMDownload() {
  const online = await updateConnectivityStatus('settingsLlmConnectivityStatus');
  if (!online) {
    showToast(t('connectivityRequired'), true);
    return;
  }
  const actionArea = document.getElementById('settings-llm-action-area');
  const progress = document.getElementById('settings-llm-progress');
  const badge = document.getElementById('settings-llm-badge');
  if (actionArea) actionArea.innerHTML = '';
  if (progress) progress.classList.remove('hidden');
  if (badge) {
    badge.className = 'llm-badge not-installed';
    badge.textContent = t('smartLlmDownloading');
  }
  try {
    if (window.downloadLLM) await window.downloadLLM();
  } catch (e) {
    if (window.onLLMDownloadError) window.onLLMDownloadError(e.message || String(e));
  }
}

async function updateConnectivityStatus(elementId) {
  const el = document.getElementById(elementId);
  if (!el || !window.checkConnectivity) return true;

  el.classList.remove('hidden');
  el.className = 'connectivity-status checking';
  const textEl = el.querySelector('.connectivity-text');
  if (textEl) textEl.textContent = t('connectivityChecking');

  try {
    const online = await window.checkConnectivity();
    if (online) {
      el.classList.remove('checking');
      el.classList.remove('offline');
      if (textEl) textEl.textContent = t('connectivityOnline');
    } else {
      el.classList.remove('checking');
      el.classList.add('offline');
      if (textEl) textEl.textContent = t('connectivityOffline');
    }
    return online;
  } catch (e) {
    el.classList.remove('checking');
    el.classList.add('offline');
    if (textEl) textEl.textContent = t('connectivityOffline');
    return false;
  }
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
  let isCustom = false;
  if (!prompt) {
    try {
      const raw = await window.getCustomTemplates();
      const custom = typeof raw === 'string' ? JSON.parse(raw) : raw;
      prompt = custom[key] || '';
      if (prompt) isCustom = true;
    } catch (e) {}
  }
  if (!prompt) prompt = t('smartNoPrompt') || 'No prompt defined for this preset.';
  // Add language note to show what actually gets sent
  const langNote = t('smartPromptLangNote') || 'Note: Your UI language setting is automatically appended to this prompt at runtime.';
  const fullMessage = esc(prompt) + '<div class="prompt-lang-note">' + esc(langNote) + '</div>';
  showDialog({
    title: (t('smartViewPromptTitle') || 'Preset Prompt') + (isCustom ? ' — ' + esc(key) : ''),
    message: fullMessage,
    variant: 'info',
    confirmText: t('ok') || 'OK'
  });
}
