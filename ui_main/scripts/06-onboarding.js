/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'
let _onboardingSmart = null;  // true or false
let _onbModelId = 'whisper-base';
let _onbModelReady = false;
let _onbDownloading = false;
let _onbApiKeyValid = false;

function showOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) {
    overlay.style.display = '';
    _onboardingStep = 1;
    _onboardingChoice = null;
    _onboardingSmart = null;
    _onbModelId = 'whisper-base';
    _onbModelReady = false;
    _onbDownloading = false;
    _onbApiKeyValid = false;
    updateOnboardingStep();
  }
}

function hideOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) overlay.style.display = 'none';
}

function updateOnboardingStep() {
  document.querySelectorAll('.onboarding-step').forEach(step => {
    step.style.display = parseInt(step.dataset.step) === _onboardingStep ? '' : 'none';
  });
  // Update dots
  document.querySelectorAll('.onboarding-dots .dot').forEach((dot, i) => {
    dot.classList.toggle('active', i === _onboardingStep - 1);
  });
  applyTranslations();
}

function nextOnboardingStep() {
  if (_onboardingStep < 4) {
    _onboardingStep++;
    if (_onboardingStep === 4) {
      const kbd = document.getElementById('onbHotkeyDisplay');
      if (kbd && window.getConfig) {
        window.getConfig().then(raw => {
          const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
          if (cfg) {
            const mods = cfg.hotkey_modifiers || ['Ctrl', 'Shift'];
            const key = cfg.hotkey_key || 'V';
            kbd.textContent = mods.join('+') + '+' + key;
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
  if (keySection) keySection.style.display = choice === 'api' ? '' : 'none';
  if (modelSection) modelSection.style.display = choice === 'local' ? '' : 'none';

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
  } else if (choice === 'local') {
    await onbCheckModelStatus();
    if (nextBtn) nextBtn.disabled = !_onbModelReady;
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

function onbUpdateModelUI() {
  const statusEl = document.getElementById('onbModelStatus');
  const downloadBtn = document.getElementById('onbDownloadBtn');
  const progressWrap = document.getElementById('onbDownloadProgress');
  const nextBtn = document.getElementById('onbNextStep2');

  if (_onbDownloading) {
    if (statusEl) { statusEl.textContent = t('onboarding.model_downloading'); statusEl.className = 'onb-model-status downloading'; }
    if (downloadBtn) downloadBtn.style.display = 'none';
    if (progressWrap) progressWrap.style.display = '';
  } else if (_onbModelReady) {
    if (statusEl) { statusEl.textContent = t('onboarding.model_ready'); statusEl.className = 'onb-model-status ready'; }
    if (downloadBtn) downloadBtn.style.display = 'none';
    if (progressWrap) progressWrap.style.display = 'none';
    if (nextBtn) nextBtn.disabled = false;
  } else {
    if (statusEl) { statusEl.textContent = t('onboarding.model_needed'); statusEl.className = 'onb-model-status needed'; }
    if (downloadBtn) downloadBtn.style.display = '';
    if (progressWrap) progressWrap.style.display = 'none';
    if (nextBtn) nextBtn.disabled = true;
  }

  // Update model card selection
  document.querySelectorAll('.onb-model-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.modelId === _onbModelId);
  });
}

async function onbSelectModel(modelId) {
  if (_onbDownloading) return;
  _onbModelId = modelId;
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

async function onbTestApiKey() {
  const keyInput = document.getElementById('onb-apikey');
  const testBtn = document.getElementById('onbTestKeyBtn');
  const feedback = document.getElementById('onbApiKeyFeedback');
  const nextBtn = document.getElementById('onbNextStep2');
  const key = keyInput ? keyInput.value.trim() : '';

  if (!key) {
    if (feedback) { feedback.textContent = t('onboarding.api_key_empty') || 'Please enter an API key'; feedback.className = 'onb-api-feedback error'; }
    return;
  }
  if (testBtn) { testBtn.disabled = true; testBtn.textContent = '...'; }
  if (feedback) { feedback.textContent = ''; feedback.className = 'onb-api-feedback'; }

  try {
    const result = await window._testApiKey(key);
    if (result && result.success) {
      _onbApiKeyValid = true;
      if (feedback) { feedback.textContent = '✓ ' + (t('onboarding.api_key_valid') || 'API key is valid'); feedback.className = 'onb-api-feedback success'; }
      if (nextBtn) nextBtn.disabled = false;
    } else {
      _onbApiKeyValid = false;
      if (feedback) { feedback.textContent = '✗ ' + (result?.error || t('onboarding.api_key_invalid') || 'Invalid API key'); feedback.className = 'onb-api-feedback error'; }
      if (nextBtn) nextBtn.disabled = true;
    }
  } catch (e) {
    _onbApiKeyValid = false;
    if (feedback) { feedback.textContent = '✗ ' + (e.message || 'Test failed'); feedback.className = 'onb-api-feedback error'; }
    if (nextBtn) nextBtn.disabled = true;
  }
  if (testBtn) { testBtn.disabled = false; testBtn.textContent = t('onboarding.test_key') || 'Test Key'; }
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
  }
};

// Hook into existing download progress/complete for onboarding
const _origDownloadComplete = window.downloadComplete;
window.downloadComplete = function(modelId, success, errorMsg) {
  // Forward to onboarding handler if overlay is visible
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && overlay.style.display !== 'none') {
    window.onbDownloadComplete(modelId, success, errorMsg);
  }
  // Forward to settings handler
  if (_origDownloadComplete) _origDownloadComplete(modelId, success, errorMsg);
};

const _origUpdateModelProgress = window.updateModelProgress;
window.updateModelProgress = function(modelId, pct, fileNum, fileCount, fileName) {
  // Update onboarding progress bar if overlay is visible
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay && overlay.style.display !== 'none') {
    const bar = document.getElementById('onbProgressBar');
    if (bar) bar.style.width = pct + '%';
    const label = document.getElementById('onbProgressLabel');
    if (label) label.textContent = pct + '%';
  }
  // Forward to settings handler
  if (_origUpdateModelProgress) _origUpdateModelProgress(modelId, pct, fileNum, fileCount, fileName);
};

function selectOnboardingSmart(enabled) {
  _onboardingSmart = enabled;
  document.querySelectorAll('#onboardingOverlay .onboarding-step[data-step="3"] .onboarding-option').forEach(opt => opt.classList.remove('selected'));
  const el = document.getElementById(enabled ? 'onb-smart-on' : 'onb-smart-off');
  if (el) el.classList.add('selected');
  const note = document.getElementById('onbSmartNote');
  if (note) note.style.display = enabled ? '' : 'none';
  const nextBtn = document.getElementById('onbNextStep3');
  if (nextBtn) nextBtn.disabled = false;
}

async function finishOnboarding() {
  // Guard: don't proceed if API mode selected without validated key
  if (_onboardingChoice === 'api' && !_onbApiKeyValid) return;
  try {
    const raw = await window.getConfig();
    const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (cfg) {
      if (_onboardingChoice === 'local') {
        cfg.local_model_id = _onbModelId;
      } else if (_onboardingChoice === 'api') {
        const keyInput = document.getElementById('onb-apikey');
        if (keyInput && keyInput.value.trim()) {
          cfg.api_key = keyInput.value.trim();
        }
      }
      if (_onboardingSmart === true) {
        cfg.smart_mode = true;
        cfg.smart_mode_provider = 'auto';
      } else if (_onboardingSmart === false) {
        cfg.smart_mode = false;
      }
      await window.saveConfig(JSON.stringify(cfg));
      // Persist model selection via the dedicated switchModel binding
      if (_onboardingChoice === 'local' && window.switchModel) {
        await window.switchModel(_onbModelId, true);
      } else if (_onboardingChoice === 'api' && window.switchModel) {
        await window.switchModel(cfg.model || 'whisper-1', false);
      }
    }
  } catch (e) { console.error('Onboarding save error:', e); }

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
