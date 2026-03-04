/* ── Onboarding Wizard ─────────────────────────────── */
let _onboardingStep = 1;
let _onboardingChoice = null; // 'api' or 'local'

function showOnboarding() {
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) {
    overlay.style.display = '';
    _onboardingStep = 1;
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
  if (_onboardingStep < 3) {
    _onboardingStep++;
    if (_onboardingStep === 3) {
      // Show the configured hotkey
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
  document.querySelectorAll('.onboarding-option').forEach(opt => opt.classList.remove('selected'));
  const el = document.getElementById(choice === 'api' ? 'onb-api' : 'onb-local');
  if (el) el.classList.add('selected');
  const nextBtn = document.getElementById('onbNextStep2');
  if (nextBtn) nextBtn.disabled = false;
}

async function finishOnboarding() {
  // Apply the selected option
  if (_onboardingChoice === 'local' && window.saveConfig) {
    try {
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (cfg) {
        cfg.use_local_stt = true;
        cfg.local_model_id = 'whisper-base';
        await window.saveConfig(JSON.stringify(cfg));
      }
    } catch (e) { /* ignore */ }
  }

  // Mark onboarding as done
  if (window.completeOnboarding) {
    await window.completeOnboarding();
  }

  hideOnboarding();

  // Navigate to appropriate page
  if (_onboardingChoice === 'api') {
    switchPage('settings');
  } else {
    switchPage('history');
  }
}
