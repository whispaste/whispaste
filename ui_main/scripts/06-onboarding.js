/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'
let _onboardingSmart = null;  // true or false

function showOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) {
    overlay.style.display = '';
    _onboardingStep = 1;
    _onboardingChoice = null;
    _onboardingSmart = null;
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

function selectOnboardingOption(choice) {
  _onboardingChoice = choice;
  document.querySelectorAll('#onboardingOverlay .onboarding-step[data-step="2"] .onboarding-option').forEach(opt => opt.classList.remove('selected'));
  const el = document.getElementById(choice === 'api' ? 'onb-api' : 'onb-local');
  if (el) el.classList.add('selected');
  const keySection = document.getElementById('onbApikeySection');
  if (keySection) keySection.style.display = choice === 'api' ? '' : 'none';
  const nextBtn = document.getElementById('onbNextStep2');
  if (nextBtn) nextBtn.disabled = false;
}

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
      // Apply STT choice
      if (_onboardingChoice === 'local') {
        cfg.use_local_stt = true;
        cfg.local_model_id = 'whisper-base';
      }
      // Apply API key if entered
      if (_onboardingChoice === 'api') {
        const keyInput = document.getElementById('onb-apikey');
        if (keyInput && keyInput.value.trim()) {
          cfg.api_key = keyInput.value.trim();
        }
      }
      // Apply Smart Mode choice
      if (_onboardingSmart === true) {
        cfg.smart_mode = true;
        cfg.smartModeProvider = 'auto';
      } else if (_onboardingSmart === false) {
        cfg.smart_mode = false;
      }
      await window.saveConfig(JSON.stringify(cfg));
    }
  } catch (e) { /* ignore */ }

  if (window.completeOnboarding) {
    await window.completeOnboarding();
  }

  hideOnboarding();

  // Navigate: if API chosen without key, go to settings for key entry
  if (_onboardingChoice === 'api' && !document.getElementById('onb-apikey')?.value?.trim()) {
    switchPage('settings');
  } else {
    switchPage('history');
  }
}

function restartOnboarding() {
  showOnboarding();
}
