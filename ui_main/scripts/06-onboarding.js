/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'
let _onboardingSmart = null;  // true or false
let _onbModelId = 'whisper-base';
let _onbModelReady = false;
let _onbDownloading = false;

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
    if (nextBtn) nextBtn.disabled = false;
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
  try {
    const raw = await window.getConfig();
    const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (cfg) {
      if (_onboardingChoice === 'local') {
        cfg.use_local_stt = true;
        cfg.active_model_local = true;
        cfg.local_model_id = _onbModelId;
      } else if (_onboardingChoice === 'api') {
        cfg.use_local_stt = false;
        cfg.active_model_local = false;
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
