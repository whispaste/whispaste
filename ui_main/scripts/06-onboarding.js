/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'
let _onboardingSmart = null;  // true or false
let _onbModelId = 'whisper-small';
let _onbModelReady = false;
let _onbDownloading = false;
let _onbPreflight = null;
let _onbPreflightRunning = false;
let _onbApiKeyValid = false;
let _onbLlmModel = 'smollm2'; // selected LLM model for smart mode
let _onbLlmReady = false;
let _onbLlmDownloading = false;

function showOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) {
    overlay.classList.remove('hidden');
    _onboardingStep = 1;
    _onboardingChoice = null;
    _onboardingSmart = null;
    _onbModelId = 'whisper-small';
    _onbModelReady = false;
    _onbDownloading = false;
    _onbPreflight = null;
    _onbPreflightRunning = false;
    _onbApiKeyValid = false;
    _onbLlmModel = 'smollm2';
    _onbLlmReady = false;
    _onbLlmDownloading = false;
    onbInitPreferences();
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
}

function nextOnboardingStep() {
  if (_onboardingStep < 4) {
    // Guard: step 3 requires LLM downloaded when smart mode is on
    if (_onboardingStep === 3 && _onboardingSmart === true && !_onbLlmReady) return;
    _onboardingStep++;
    if (_onboardingStep === 3 && _onboardingSmart === null) {
      selectOnboardingSmart(true);
    }
    if (_onboardingStep === 4) {
      const kbd = document.getElementById('onbHotkeyDisplay');
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
      setTimeout(() => onbTestApiKey(), 150);
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
    if (statusEl) { statusEl.textContent = t('preflightBlockedBadge'); statusEl.className = 'onb-model-status blocked'; }
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

  // Update model card selection
  document.querySelectorAll('.onb-model-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.modelId === _onbModelId);
  });
}

async function onbRenderModelCards() {
  const container = document.getElementById('onbModelCards');
  if (!container || !window._getModels) return;
  try {
    const allModels = await window._getModels();
    const rec = allModels.find(m => m.recommended);
    if (rec) _onbModelId = rec.id;

    const qualityLabels = {
      1: t('modelQualityBasic'),
      2: t('modelQualityGood'),
      3: t('modelQualityGreat'),
      4: t('modelQualityExcellent'),
      5: t('modelQualityBest')
    };
    container.innerHTML = allModels.map(m => {
      const selected = m.id === _onbModelId ? ' selected' : '';
      const recBadge = m.recommended ? ` · <span>${esc(t('onboarding.model_recommended'))}</span>` : '';
      const ql = qualityLabels[m.quality] || '';
      return `<div class="onb-model-card${selected}" data-model-id="${esc(m.id)}" tabindex="0" role="button" onclick="onbSelectModel('${esc(m.id)}')">
        <div class="onb-model-card-name">${esc(m.name)}</div>
        <div class="onb-model-card-meta">${esc(m.size)}${recBadge}</div>
        <div class="onb-model-card-desc">${esc(ql)}</div>
      </div>`;
    }).join('');
  } catch (e) {
    // Fallback: keep container empty, user can still proceed
  }
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
  onbUpdateModelUI();
  if (!success && errorMsg) {
    const statusEl = document.getElementById('onbModelStatus');
    if (statusEl) { statusEl.textContent = errorMsg; statusEl.className = 'onb-model-status needed'; }
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

// Hook LLM download callbacks for onboarding step 3
const _origLLMProgress = window.onLLMDownloadProgress;
window.onLLMDownloadProgress = function(phase, pct, modelID) {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && !overlay.classList.contains('hidden') && _onbLlmDownloading) {
    const bar = document.getElementById('onbLlmProgressBar');
    if (bar) bar.style.width = pct + '%';
    const label = document.getElementById('onbLlmProgressLabel');
    if (label) label.textContent = pct + '%';
  }
  if (_origLLMProgress) _origLLMProgress(phase, pct, modelID);
};

const _origLLMComplete = window.onLLMDownloadComplete;
window.onLLMDownloadComplete = function(modelID) {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && !overlay.classList.contains('hidden') && _onbLlmDownloading) {
    _onbLlmDownloading = false;
    _onbLlmReady = true;
    onbUpdateLlmUI();
  }
  if (_origLLMComplete) _origLLMComplete(modelID);
};

const _origLLMError = window.onLLMDownloadError;
window.onLLMDownloadError = function(errorMsg, modelID) {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && !overlay.classList.contains('hidden') && _onbLlmDownloading) {
    _onbLlmDownloading = false;
    onbUpdateLlmUI();
  }
  if (_origLLMError) _origLLMError(errorMsg, modelID);
};

function selectOnboardingSmart(enabled) {
  _onboardingSmart = enabled;
  document.querySelectorAll('#onboardingOverlay .onboarding-step[data-step="3"] .onboarding-option').forEach(opt => opt.classList.remove('selected'));
  const el = document.getElementById(enabled ? 'onb-smart-on' : 'onb-smart-off');
  if (el) el.classList.add('selected');
  const llmSection = document.getElementById('onbLlmModelSection');
  if (llmSection) llmSection.classList.toggle('hidden', !enabled);
  const nextBtn = document.getElementById('onbNextStep3');
  if (enabled) {
    onbCheckLLMStatus();
  } else {
    if (nextBtn) nextBtn.disabled = false;
  }
}

async function onbSelectLLMModel(modelId) {
  if (_onbLlmDownloading) return;
  _onbLlmModel = modelId;
  document.querySelectorAll('.onb-llm-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.llmId === modelId);
  });
  await onbCheckLLMStatus();
}

async function onbCheckLLMStatus() {
  _onbLlmReady = false;
  if (window.getLLMStatus) {
    try {
      const raw = await window.getLLMStatus();
      const status = typeof raw === 'string' ? JSON.parse(raw) : raw;
      const models = status.models || {};
      const m = models[_onbLlmModel];
      if (m && m.installed) _onbLlmReady = true;
    } catch (e) {}
  }
  onbUpdateLlmUI();
}

function onbUpdateLlmUI() {
  const statusEl = document.getElementById('onbLlmStatus');
  const downloadBtn = document.getElementById('onbLlmDownloadBtn');
  const progressWrap = document.getElementById('onbLlmDownloadProgress');
  const nextBtn = document.getElementById('onbNextStep3');

  if (_onbLlmDownloading) {
    if (statusEl) { statusEl.textContent = t('onboarding.smart_llm_downloading'); statusEl.className = 'onb-model-status downloading'; }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.remove('hidden');
    if (nextBtn) nextBtn.disabled = true;
  } else if (_onbLlmReady) {
    if (statusEl) { statusEl.textContent = t('onboarding.smart_llm_ready'); statusEl.className = 'onb-model-status ready'; }
    if (downloadBtn) downloadBtn.classList.add('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = false;
  } else {
    if (statusEl) { statusEl.textContent = t('onboarding.model_needed'); statusEl.className = 'onb-model-status needed'; }
    if (downloadBtn) downloadBtn.classList.remove('hidden');
    if (progressWrap) progressWrap.classList.add('hidden');
    if (nextBtn) nextBtn.disabled = true;
  }
}

async function onbDownloadLLM() {
  if (_onbLlmDownloading || !window.downloadLLM) return;
  _onbLlmDownloading = true;
  onbUpdateLlmUI();
  try {
    await window.downloadLLM(_onbLlmModel);
  } catch (e) {
    _onbLlmDownloading = false;
    onbUpdateLlmUI();
  }
}

async function finishOnboarding() {
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
      if (_onboardingSmart === true) {
        cfg.smart_mode = true;
        cfg.smart_mode_provider = 'auto';
        cfg.local_llm_model = _onbLlmModel;
      } else if (_onboardingSmart === false) {
        cfg.smart_mode = false;
      }
      await window.saveConfig(JSON.stringify(cfg));
      if (_onboardingChoice === 'api' && window.switchModel) {
        await window.switchModel(cfg.model || 'whisper-1', false);
      }
      // Persist LLM model selection
      if (_onboardingSmart && window.setLocalLLMModel) {
        try { await window.setLocalLLMModel(_onbLlmModel); } catch (e) {}
      }
    }
  } catch (e) { showToast(t('saveError'), true); }

  if (window.completeOnboarding) {
    await window.completeOnboarding();
  }

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

  if (_onboardingChoice === 'api' && !document.getElementById('onb-apikey')?.value?.trim()) {
    switchPage('settings');
  } else {
    switchPage('history');
  }
}

function restartOnboarding() {
  showOnboarding();
}

/* ── Onboarding Preferences (Language/Theme on Page 1) ── */
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
  const theme = _currentTheme || 'system';
  document.querySelectorAll('#onbThemeOptions .onb-theme-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === theme);
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
  document.querySelectorAll('#onbThemeOptions .onb-theme-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === theme);
  });
  applyTheme(theme);
  if (window.setTheme) {
    await window.setTheme(theme);
  }
}
