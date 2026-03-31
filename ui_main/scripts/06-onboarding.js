/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'
let _onbPersona = null; // 'content', 'office', 'dev', 'general'
let _onbModelId = 'whisper-small';
let _onbModelReady = false;
let _onbDownloading = false;
let _onbPreflight = null;
let _onbPreflightRunning = false;
let _onbApiKeyValid = false;
let _onbTrackedEvents = new Set();
let _onbResumeAfterCapture = false;

function onbTrackEvent(name, once) {
  if (!name || !window.recordOnboardingEvent) return;
  if (once) {
    if (_onbTrackedEvents.has(name)) return;
    _onbTrackedEvents.add(name);
  }
  try { window.recordOnboardingEvent(name); } catch (e) {}
}

function onbFriendlyModeLabel() {
  if (_onboardingChoice === 'local') return t('onboarding.ready_mode_local').replace('{model}', _onbModelId || 'whisper-small');
  if (_onboardingChoice === 'api') return t('onboarding.ready_mode_api');
  return '—';
}

function onbSelectPersona(persona) {
  _onbPersona = persona;
  document.querySelectorAll('.onb-persona-card').forEach(c => {
    c.classList.toggle('active', c.dataset.persona === persona);
  });
  onbTrackEvent('onboarding_persona_' + persona, true);
}

function onbPopulateReadyState() {
  const readyMode = document.getElementById('onbReadyMode');
  if (readyMode) readyMode.textContent = onbFriendlyModeLabel();
}

function onbPopulateHotkeyDisplay(elementId) {
  const kbd = document.getElementById(elementId);
  if (kbd && window.getConfig) {
    window.getConfig().then(raw => {
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (cfg) {
        const mods = cfg.hotkey_modifiers || ['Ctrl', 'Shift'];
        const key = cfg.hotkey_key || 'D';
        kbd.textContent = formatHotkeyParts([...mods, key]).join('+');
      }
    }).catch(() => {});
  }
}

function showOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) {
    overlay.classList.remove('hidden');
    _onboardingStep = 1;
    _onboardingChoice = null;
    _onbPersona = null;
    _onbModelId = 'whisper-small';
    _onbModelReady = false;
    _onbDownloading = false;
    _onbPreflight = null;
    _onbPreflightRunning = false;
    _onbApiKeyValid = false;
    _onbTrackedEvents = new Set();
    onbInitPreferences();
    onbTrackEvent('onboarding_start', true);
    updateOnboardingStep();
  }
}

function hideOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) overlay.classList.add('hidden');
}

function updateOnboardingStep() {
  document.querySelectorAll('.onboarding-step').forEach(step => {
    step.classList.toggle('hidden', parseInt(step.dataset.step) !== _onboardingStep);
  });
  // Update dots
  document.querySelectorAll('.onboarding-dots .dot').forEach((dot, i) => {
    dot.classList.toggle('active', i === _onboardingStep - 1);
  });
  applyTranslations();
  // Auto-select "local" when entering step 2 for the first time (offline-first)
  if (_onboardingStep === 2 && _onboardingChoice === null) {
    selectOnboardingOption('local');
  }
  if (_onboardingStep === 3) {
    onbPopulateHotkeyDisplay('onbHotkeyDisplay');
  }
  if (_onboardingStep === 4) {
    onbPopulateHotkeyDisplay('onbHotkeyDisplayStep4');
    // Init theme selector state
    const theme = _currentTheme || 'system';
    document.querySelectorAll('#onbThemeOptionsStep4 .onb-theme-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.theme === theme);
    });
  }
}

function nextOnboardingStep() {
  if (_onboardingStep < 4) {
    onbTrackEvent('onboarding_step_' + _onboardingStep + '_completed');
    _onboardingStep++;
    updateOnboardingStep();
  }
}

function prevOnboardingStep() {
  if (_onboardingStep > 1) {
    _onboardingStep--;
    updateOnboardingStep();
  }
}

async function selectOnboardingOption(choice) {
  _onboardingChoice = choice;
  onbTrackEvent('onboarding_method_selected_' + choice, true);
  document.querySelectorAll('#onboardingOverlay .onboarding-step[data-step="2"] .onboarding-option').forEach(opt => opt.classList.remove('selected'));
  const el = document.getElementById(choice === 'api' ? 'onb-api' : 'onb-local');
  if (el) el.classList.add('selected');

  const keySection = document.getElementById('onbApikeySection');
  const modelSection = document.getElementById('onbModelSection');
  if (keySection) keySection.classList.toggle('hidden', choice !== 'api');
  if (modelSection) modelSection.classList.toggle('hidden', choice !== 'local');

  const nextBtn = document.getElementById('onbNextStep2');
  if (choice === 'api') {
    // Disable until key is tested successfully
    if (nextBtn) nextBtn.disabled = true;
    _onbApiKeyValid = false;
    // Reset validation when key input changes
    const keyInput = document.getElementById('onb-apikey');
    if (keyInput && !keyInput._onbChangeWired) {
      keyInput._onbChangeWired = true;
      keyInput.addEventListener('input', () => {
        _onbApiKeyValid = false;
        const fb = document.getElementById('onbApiKeyFeedback');
        if (fb) { fb.textContent = ''; fb.className = 'onb-api-feedback'; }
        const nb = document.getElementById('onbNextStep2');
        if (nb && _onboardingChoice === 'api') nb.disabled = true;
      });
    }
    // Auto-validate existing key from config (pre-populated field)
    if (keyInput && keyInput.value.trim()) {
      setTimeout(() => onbTestApiKey(), 150); // DevSkim: ignore DS172411 — constant delay, safe callback
    }
  } else if (choice === 'local') {
    await onbRenderModelCards();
    await onbRefreshPreflight();
    await onbCheckModelStatus();
    if (nextBtn) nextBtn.disabled = !!_onbPreflight?.blocking || !_onbModelReady;
  }
}

async function onbCheckModelStatus() {
  _onbModelReady = false;
  if (window._isModelDownloaded) {
    try {
      _onbModelReady = await window._isModelDownloaded(_onbModelId);
    } catch (e) {}
  }
  onbUpdateModelUI();
}

async function onbRefreshPreflight() {
  _onbPreflightRunning = true;
  onbUpdateModelUI();
  if (!window.getLocalSTTPreflight) {
    _onbPreflightRunning = false;
    _onbPreflight = null;
    onbUpdateModelUI();
    return null;
  }
  try {
    const raw = await window.getLocalSTTPreflight(_onbModelId, 'onboarding');
    _onbPreflight = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (e) {
    _onbPreflight = null;
  }
  _onbPreflightRunning = false;
  onbUpdateModelUI();
  return _onbPreflight;
}

function onbUpdateModelUI() {
  const statusEl = document.getElementById('onbModelStatus');
  const downloadBtn = document.getElementById('onbDownloadBtn');
  const progressWrap = document.getElementById('onbDownloadProgress');
  const nextBtn = document.getElementById('onbNextStep2');
  const preflightIcon = document.getElementById('onbPreflightIcon');
  const preflightText = document.getElementById('onbPreflightText');

  // Compact inline preflight status
  if (preflightIcon && preflightText) {
    const status = _onbPreflightRunning ? 'checking' : (_onbPreflight?.status || '');
    const icons = { pass: '✓', warn: '⚠', fail: '✗', checking: '…' };
    preflightIcon.textContent = icons[status] || '';
    preflightIcon.className = 'preflight-icon' + (status ? ' status-' + status : '');
    preflightText.textContent = _onbPreflightRunning ? t('preflightChecking') : (_onbPreflight?.summary || '');
  }

  if (_onbPreflightRunning) {
    if (statusEl) { statusEl.textContent = t('preflightChecking'); statusEl.className = 'onb-model-status checking'; }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = true;
  } else if (_onbPreflight?.blocking) {
    if (statusEl) {
      // Show specific reason (e.g. "engine could not start — install VC++ Runtime")
      // instead of generic "Not compatible" badge
      const reason = _onbPreflight?.message || t('preflightBlockedBadge');
      statusEl.textContent = reason;
      statusEl.className = 'onb-model-status blocked';
    }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = true;
  } else if (_onbDownloading) {
    if (statusEl) { statusEl.textContent = t('onboarding.model_downloading'); statusEl.className = 'onb-model-status downloading'; }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.remove('hidden');
  } else if (_onbModelReady) {
    if (statusEl) { statusEl.textContent = t('onboarding.model_ready'); statusEl.className = 'onb-model-status ready'; }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = false;
  } else {
    if (statusEl) { statusEl.textContent = t('onboarding.model_needed'); statusEl.className = 'onb-model-status needed'; }
    if (downloadBtn) downloadBtn.classList.remove('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = true;
  }

  // Update model row selection
  document.querySelectorAll('.onb-model-row').forEach(row => {
    row.classList.toggle('selected', row.dataset.modelId === _onbModelId);
  });
}

async function onbRenderModelCards() {
  const container = document.getElementById('onbModelCards');
  if (!container || !window._getModels) return;
  try {
    const allModels = await window._getModels();
    const rec = allModels.find(m => m.recommended);
    if (rec) _onbModelId = rec.id;

    container.innerHTML = allModels.map(m => {
      const selected = m.id === _onbModelId ? ' selected' : '';
      const recBadge = m.recommended ? `<span class="onb-badge-rec">${esc(t('onboarding.model_recommended'))}</span>` : '';
      const q = Math.max(0, Math.min(5, m.quality || 0));
      const dots = '●'.repeat(q) + '<span class="onb-quality-empty">' + '●'.repeat(5 - q) + '</span>';
      return `<div class="onb-model-row${selected}" data-model-id="${esc(m.id)}" tabindex="0" role="button" onclick="onbSelectModel('${esc(m.id)}')">
        <span class="onb-model-row-name">${esc(m.name)}${recBadge}</span>
        <span class="onb-model-row-quality">${dots}</span>
        <span class="onb-model-row-size">${esc(m.size)}</span>
      </div>`;
    }).join('');
  } catch (e) {}
}

async function onbSelectModel(modelId) {
  if (_onbDownloading) return;
  _onbModelId = modelId;
  await onbRefreshPreflight();
  await onbCheckModelStatus();
}

async function onbStartDownload() {
  if (_onbDownloading || !window._downloadModel) return;
  _onbDownloading = true;
  onbTrackEvent('onboarding_model_download_started', true);
  onbUpdateModelUI();

  try {
    await window._downloadModel(_onbModelId);
    // Actual completion comes via onbDownloadComplete callback
  } catch (e) {
    _onbDownloading = false;
    onbUpdateModelUI();
  }
}

function onbUpdateKeyPreview() {
  const input = document.getElementById('onb-apikey');
  const preview = document.getElementById('onbKeyPreview');
  if (!preview) return;
  const val = input ? input.value : '';
  // Only show masked preview when key is long enough to hide a meaningful middle
  if (val.length < 16) {
    preview.textContent = val.length > 0 ? t('onboarding.apikey_chars').replace('{n}', val.length) : '';
    return;
  }
  const head = val.slice(0, 7);
  const tail = val.slice(-4);
  preview.textContent = head + '••••••' + tail;
}

async function onbTestApiKey() {
  const keyInput = document.getElementById('onb-apikey');
  const testBtn = document.getElementById('onbTestKeyBtn');
  const feedback = document.getElementById('onbApiKeyFeedback');
  const nextBtn = document.getElementById('onbNextStep2');
  const key = keyInput ? keyInput.value.trim() : '';

  if (!key) {
    if (feedback) { feedback.textContent = t('onboarding.api_key_empty'); feedback.className = 'onb-api-feedback error'; }
    return;
  }
  if (testBtn) { testBtn.disabled = true; testBtn.textContent = '...'; }
  if (feedback) { feedback.textContent = ''; feedback.className = 'onb-api-feedback'; }

  try {
    const result = await window._testApiKey(key);
    if (result && result.success) {
      _onbApiKeyValid = true;
      if (feedback) { feedback.textContent = '✓ ' + t('onboarding.api_key_valid'); feedback.className = 'onb-api-feedback success'; }
      if (nextBtn) nextBtn.disabled = false;
    } else {
      _onbApiKeyValid = false;
      if (feedback) { feedback.textContent = '✗ ' + (result?.error || t('onboarding.api_key_invalid')); feedback.className = 'onb-api-feedback error'; }
      if (nextBtn) nextBtn.disabled = true;
    }
  } catch (e) {
    _onbApiKeyValid = false;
    if (feedback) { feedback.textContent = '✗ ' + (e.message || t('statusTestError')); feedback.className = 'onb-api-feedback error'; }
    if (nextBtn) nextBtn.disabled = true;
  }
  if (testBtn) { testBtn.disabled = false; testBtn.textContent = t('onboarding.test_key'); }
}

// Called from Go via window.onbDownloadComplete (set up as alias)
window.onbDownloadComplete = function(modelId, success, errorMsg) {
  if (modelId !== _onbModelId) return;
  _onbDownloading = false;
  _onbModelReady = success;
  if (success) onbTrackEvent('onboarding_model_download_completed', true);
  onbUpdateModelUI();
  if (!success && errorMsg) {
    const statusEl = document.getElementById('onbModelStatus');
    if (statusEl) { statusEl.textContent = errorMsg; statusEl.className = 'onb-model-status needed'; }
    // Show retry button after failed download
    const downloadBtn = document.getElementById('onbDownloadBtn');
    if (downloadBtn) downloadBtn.classList.remove('hidden');
  } else if (success) {
    onbRefreshPreflight();
  }
};

// Hook into existing download progress/complete for onboarding
const _origDownloadComplete = window.downloadComplete;
window.downloadComplete = function(modelId, success, errorMsg) {
  // Forward to onboarding handler if overlay is visible
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && !overlay.classList.contains('hidden')) {
    window.onbDownloadComplete(modelId, success, errorMsg);
  }
  // Forward to settings handler
  if (_origDownloadComplete) _origDownloadComplete(modelId, success, errorMsg);
};

const _origUpdateModelProgress = window.updateModelProgress;
window.updateModelProgress = function(modelId, pct, fileNum, fileCount, fileName) {
  // Update onboarding progress bar if overlay is visible
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && !overlay.classList.contains('hidden')) {
    const bar = document.getElementById('onbProgressBar');
    if (bar) bar.style.width = pct + '%';
    const label = document.getElementById('onbProgressLabel');
    if (label) label.textContent = pct + '%';
  }
  // Forward to settings handler
  if (_origUpdateModelProgress) _origUpdateModelProgress(modelId, pct, fileNum, fileCount, fileName);
};

async function onbSaveTranscriptionConfig() {
  try {
    const raw = await window.getConfig();
    const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!cfg) return false;

    if (_onboardingChoice === 'local' && window.switchModel) {
      const switchResult = await window.switchModel(_onbModelId, true);
      const parsed = typeof switchResult === 'string' ? JSON.parse(switchResult) : switchResult;
      if (parsed && parsed.success === false) {
        showToast(parsed.error || t('preflightBlockedBadge'), true);
        return false;
      }
    }

    if (_onboardingChoice === 'local') {
      cfg.local_model_id = _onbModelId;
      cfg.active_model_local = true;
    } else if (_onboardingChoice === 'api') {
      cfg.active_model_local = false;
      const keyInput = document.getElementById('onb-apikey');
      if (keyInput && keyInput.value.trim()) {
        cfg.api_key = keyInput.value.trim();
      }
    }

    cfg.smart_mode_target = window._lang || 'en';
    const saveResult = await window.saveConfig(JSON.stringify(cfg));
    if (saveResult && saveResult.success === false) {
      showToast(saveResult.error || t('saveError'), true);
      return false;
    }

    if (_onboardingChoice === 'api' && window.switchModel) {
      const switchResult = await window.switchModel(cfg.model || 'whisper-1', false);
      const parsed = typeof switchResult === 'string' ? JSON.parse(switchResult) : switchResult;
      if (parsed && parsed.success === false) {
        showToast(parsed.error || t('modelSwitcher.error'), true);
        return false;
      }
    }

    return true;
  } catch (e) {
    showToast(t('saveError'), true);
    return false;
  }
}

async function onbTryDictation() {
  if (_onboardingChoice === 'api' && !_onbApiKeyValid) return;
  if (_onboardingChoice === 'local' && (!_onbModelReady || _onbPreflight?.blocking)) return;

  const saved = await onbSaveTranscriptionConfig();
  if (!saved) return;

  _onbResumeAfterCapture = true;

  onbTrackEvent('onboarding_first_dictation_started', true);
  onbTrackEvent('activation_reached', true);
  showToast(t('onboarding.capture_starting'));

  setTimeout(() => { // DevSkim: ignore DS172411 — small delay before capture starts
    if (window.startCapture) window.startCapture();
  }, 200);
}

async function finishOnboarding(nextAction) {
  // Guard: don't proceed if API mode selected without validated key
  if (_onboardingChoice === 'api' && !_onbApiKeyValid) return;
  // Guard: don't proceed if local mode selected without downloaded model
  if (_onboardingChoice === 'local' && (!_onbModelReady || _onbPreflight?.blocking)) return;
  try {
    const raw = await window.getConfig();
    const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (cfg) {
      if (_onboardingChoice === 'local' && window.switchModel) {
        const switchResult = await window.switchModel(_onbModelId, true);
        const parsed = typeof switchResult === 'string' ? JSON.parse(switchResult) : switchResult;
        if (parsed && parsed.success === false) {
          showToast(parsed.error || t('preflightBlockedBadge'), true);
          return;
        }
      }
      if (_onboardingChoice === 'local') {
        cfg.local_model_id = _onbModelId;
        cfg.active_model_local = true;
      } else if (_onboardingChoice === 'api') {
        cfg.active_model_local = false;
        const keyInput = document.getElementById('onb-apikey');
        if (keyInput && keyInput.value.trim()) {
          cfg.api_key = keyInput.value.trim();
        }
      }
      // Set smart_mode_target from current language
      cfg.smart_mode_target = window._lang || 'en';
      const saveResult = await window.saveConfig(JSON.stringify(cfg));
      if (saveResult && saveResult.success === false) {
        showToast(saveResult.error || t('saveError'), true);
        return;
      }
      if (_onboardingChoice === 'api' && window.switchModel) {
        const switchResult = await window.switchModel(cfg.model || 'whisper-1', false);
        const parsed = typeof switchResult === 'string' ? JSON.parse(switchResult) : switchResult;
        if (parsed && parsed.success === false) {
          showToast(parsed.error || t('modelSwitcher.error'), true);
          return;
        }
      }
    }
  } catch (e) { showToast(t('saveError'), true); }

  if (window.completeOnboarding) {
    await window.completeOnboarding();
  }
  onbTrackEvent('onboarding_completed', true);

  hideOnboarding();

  // Reload config into UI so settings reflect onboarding choices
  try {
    if (window.getConfig) {
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      applyConfig(cfg);
      updateModeBadge(cfg);
      updateStatusBar(cfg);
    }
  } catch (e) {}

  if (nextAction === 'settings') {
    switchPage('settings');
    return;
  }

  switchPage('history');
  if (nextAction === 'capture') {
    onbTrackEvent('onboarding_first_dictation_started', true);
    onbTrackEvent('activation_reached', true);
    showToast(t('onboarding.capture_starting'));
    setTimeout(() => {
      if (window.startCapture) window.startCapture();
    }, 150); // DevSkim: ignore DS172411 — allow overlay to close before capture starts
  }
}

async function restartOnboarding() {
  if (window.resetOnboarding) await window.resetOnboarding();
  showOnboarding();
}

/* ── Onboarding Preferences (Language on Page 1, Theme on Page 4) ── */
function onbInitPreferences() {
  // Detect system language — default to 'de' if browser reports German, otherwise 'en'
  let lang = window._lang;
  if (!lang) {
    const sysLang = (navigator.language || navigator.userLanguage || 'en').toLowerCase();
    lang = sysLang.startsWith('de') ? 'de' : 'en';
    // Apply detected language so the onboarding UI is localized
    window._lang = lang;
    setLang(lang);
  }
  document.querySelectorAll('#onbLangOptions .onb-lang-card').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
}

async function onbSetLanguage(lang) {
  document.querySelectorAll('#onbLangOptions .onb-lang-card').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
  if (window.setUILanguage) {
    await window.setUILanguage(lang);
  }
  window._lang = lang;
  setLang(lang);
}

async function onbSetTheme(theme) {
  document.querySelectorAll('#onbThemeOptionsStep4 .onb-theme-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === theme);
  });
  applyTheme(theme);
  if (window.setTheme) {
    await window.setTheme(theme);
  }
}

/* ── Resume onboarding after try-dictation capture ── */
const _origOnRecordingStateChanged = typeof onRecordingStateChanged === 'function' ? onRecordingStateChanged : null;
window.onRecordingStateChanged = function(state) {
  if (_origOnRecordingStateChanged) _origOnRecordingStateChanged(state);
  if (_onbResumeAfterCapture && state === 'idle') {
    _onbResumeAfterCapture = false;
    // Mark onboarding done now — config is saved and user experienced the aha moment.
    // Step 4 is optional polish; if the app closes before it, onboarding won't repeat.
    if (window.completeOnboarding) window.completeOnboarding();
    // Advance to step 4 (onboarding overlay stayed visible the whole time)
    _onboardingStep = 4;
    updateOnboardingStep();
  }
};
