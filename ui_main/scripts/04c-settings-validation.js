/* ── Test Recording ───────────────────────────────────── */
let _isTesting = false;
let _localSTTPreflight = null;
let _localSTTModels = [];

async function fetchLocalSTTPreflight(modelId, purpose) {
  if (!window.getLocalSTTPreflight) return null;
  const raw = await window.getLocalSTTPreflight(modelId || '', purpose || 'inspect');
  return typeof raw === 'string' ? JSON.parse(raw) : raw;
}

function renderLocalSTTPreflight(preflight) {
  const card = document.getElementById('localSttPreflightCard');
  const iconEl = document.getElementById('localSttPreflightIcon');
  const summaryEl = document.getElementById('localSttPreflightSummary');
  if (!card || !iconEl || !summaryEl) return;

  card.classList.remove('is-fail', 'is-warn', 'is-pass');

  if (!preflight) {
    iconEl.innerHTML = '<span class="spinner-sm"></span>';
    summaryEl.textContent = t('preflightChecking');
    return;
  }

  card.classList.add(`is-${preflight.status}`);

  const icons = {
    pass: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>',
    warn: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" x2="12" y1="9" y2="13"/><line x1="12" x2="12.01" y1="17" y2="17"/></svg>',
    fail: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" x2="9" y1="9" y2="15"/><line x1="9" x2="15" y1="9" y2="15"/></svg>'
  };
  iconEl.innerHTML = icons[preflight.status] || icons.pass;

  // Show only the summary (message is logged server-side for diagnostics)
  summaryEl.textContent = preflight.summary || '';
}

async function refreshLocalSTTPreflight(modelId) {
  try {
    _localSTTPreflight = await fetchLocalSTTPreflight(modelId || '', modelId ? 'download' : 'inspect');
  } catch (e) {
    _localSTTPreflight = null;
  }
  if (typeof _sysInfoCache !== 'undefined') {
    _sysInfoCache = null;
  }
  renderLocalSTTPreflight(_localSTTPreflight);
  if (typeof renderModelList === 'function') {
    renderModelList();
  }
  return _localSTTPreflight;
}

async function flushAudioConfig() {
  if (!window.saveConfig || typeof gatherConfig !== 'function') {
    return true;
  }
  const result = await window.saveConfig(JSON.stringify(gatherConfig()));
  const res = typeof result === 'string' ? JSON.parse(result) : result;
  if (!res?.success) {
    showStatus(res?.error || t('statusError'), 'error');
    return false;
  }
  return true;
}

async function testRecording() {
  if (_isTesting) return;
  const btn = document.getElementById('btn-test');
  const icon = document.getElementById('btn-test-icon');
  const text = document.getElementById('btn-test-text');

  _isTesting = true;
  if (btn) btn.classList.add('recording');
  if (icon) icon.innerHTML = '<span class="recording-dot"></span>';
  if (text) text.textContent = t('statusTesting');
  showStatus(t('statusTesting'), 'success');

  try {
    if (!await flushAudioConfig()) {
      return;
    }
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
    if (text) text.textContent = t('btnTestTranscription');
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
    showToast(t('audioDeviceError'), true);
  }
}

/* ── Test Audio Input ─────────────────────────────────── */
let _testAudioInterval = null;
let _latestAudioSnapshot = { level: 0, peak: 0, average: 0, status: 'checking' };

function resetAudioHealthUI() {
  const card = document.getElementById('audioHealthCard');
  const badge = document.getElementById('audioHealthBadge');
  const message = document.getElementById('audioHealthMessage');
  const tip = document.getElementById('audioHealthTip');
  const value = document.getElementById('audioHealthValue');
  if (card) {
    card.classList.add('hidden');
    card.classList.remove('is-checking', 'is-silent', 'is-quiet', 'is-good', 'is-hot');
  }
  if (badge) badge.textContent = '';
  if (message) message.textContent = '';
  if (tip) tip.textContent = '';
  if (value) value.textContent = '0%';
}

function getAudioHealthCopy(status) {
  switch (status) {
    case 'silent':
      return {
        badge: t('audioHealthSilentBadge'),
        message: t('audioHealthSilentMessage'),
        tip: t('audioHealthSilentTip')
      };
    case 'quiet':
      return {
        badge: t('audioHealthQuietBadge'),
        message: t('audioHealthQuietMessage'),
        tip: t('audioHealthQuietTip')
      };
    case 'hot':
      return {
        badge: t('audioHealthHotBadge'),
        message: t('audioHealthHotMessage'),
        tip: t('audioHealthHotTip')
      };
    case 'good':
      return {
        badge: t('audioHealthGoodBadge'),
        message: t('audioHealthGoodMessage'),
        tip: t('audioHealthGoodTip')
      };
    default:
      return {
        badge: t('audioHealthCheckingBadge'),
        message: t('audioHealthCheckingMessage'),
        tip: t('audioHealthCheckingTip')
      };
  }
}

function renderAudioHealth(snapshot) {
  const card = document.getElementById('audioHealthCard');
  const badge = document.getElementById('audioHealthBadge');
  const message = document.getElementById('audioHealthMessage');
  const tip = document.getElementById('audioHealthTip');
  const value = document.getElementById('audioHealthValue');
  if (!card || !badge || !message || !tip || !value) return;

  const status = snapshot?.status || 'checking';
  const copy = getAudioHealthCopy(status);
  const peakPct = Math.min(100, Math.round((parseFloat(snapshot?.peak || 0) || 0) * 100));

  card.classList.remove('hidden', 'is-checking', 'is-silent', 'is-quiet', 'is-good', 'is-hot');
  card.classList.add(`is-${status}`);
  badge.textContent = copy.badge;
  message.textContent = copy.message;
  tip.textContent = copy.tip;
  value.textContent = `${peakPct}%`;
}

function renderAudioLevelBar(level) {
  const bar = document.getElementById('audioLevelBar');
  const pct = Math.min(100, Math.round((parseFloat(level) || 0) * 100));
  if (!bar) return;
  bar.style.width = pct + '%';
  if (pct > 85) bar.style.background = 'var(--error)';
  else if (pct > 60) bar.style.background = 'var(--warning)';
  else bar.style.background = 'var(--success)';
}

async function stopAudioInputMonitor({ hideMeter = true } = {}) {
  const meter = document.getElementById('audioLevelMeter');
  const btn = document.getElementById('btn-test-audio');
  if (_testAudioInterval) {
    clearInterval(_testAudioInterval);
    _testAudioInterval = null;
  }
  if (hideMeter && meter) meter.classList.add('hidden');
  if (btn) btn.classList.remove('recording');
  try {
    if (window._stopAudioMonitor) await window._stopAudioMonitor();
  } catch (e) {}
}

async function testAudioInput() {
  const meter = document.getElementById('audioLevelMeter');
  const btn = document.getElementById('btn-test-audio');

  // Toggle off
  if (_testAudioInterval) {
    await stopAudioInputMonitor();
    return;
  }

  if (!await flushAudioConfig()) {
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

  _latestAudioSnapshot = { level: 0, peak: 0, average: 0, status: 'checking' };
  if (meter) meter.classList.remove('hidden');
  if (btn) btn.classList.add('recording');
  renderAudioLevelBar(0);
  renderAudioHealth(_latestAudioSnapshot);
  let count = 0;
  _testAudioInterval = setInterval(async () => {
    count++;
    if (count > 100) { // 10 seconds
      await stopAudioInputMonitor();
      renderAudioHealth(_latestAudioSnapshot);
      return;
    }
    if (window._getAudioMonitorSnapshot) {
      try {
        const raw = await window._getAudioMonitorSnapshot();
        const snapshot = typeof raw === 'string' ? JSON.parse(raw) : raw;
        _latestAudioSnapshot = snapshot || _latestAudioSnapshot;
        renderAudioLevelBar(snapshot?.level || 0);
        renderAudioHealth(_latestAudioSnapshot);
      } catch (e) {}
    }
  }, 100);
}

/* ── Model List Rendering ───────────────────────────────*/
async function renderModelList() {
  const container = document.getElementById('model-list');
  if (!container) return;
  
  let models = [];
  if (window._getModels) {
    try {
      const result = await window._getModels();
      models = typeof result === 'string' ? JSON.parse(result) : result;
      _localSTTModels = models;
    } catch (e) {
      showToast(t('modelLoadError'), true);
    }
  }
  
  if (!models || models.length === 0) {
    models = [
      { id: 'whisper-base', name: 'Whisper Base', size: '57MB', downloaded: false },
      { id: 'whisper-small', name: 'Whisper Small', size: '181MB', downloaded: false },
      { id: 'whisper-medium', name: 'Whisper Medium', size: '514MB', downloaded: false }
    ];
  }
  
  container.innerHTML = models.map(m => renderModelCard({
    id: m.id,
    name: m.name,
    description: t('model.desc.' + m.id) || '',
    size: m.size,
    downloaded: m.downloaded,
    downloading: _downloadingModel === m.id,
    preflight_blocked: !!m.preflight_blocked,
    preflight_message: m.preflight_message || '',
    preflight_status: m.preflight_status || 'pass'
  }, { type: 'stt', showTest: true })).join('');
}


/* ── STT Model Test ─────────────────────────────────────── */
async function testSTTModel(modelId) {
  const model = _localSTTModels.find(m => m.id === modelId);
  if (model && model.preflight_blocked) {
    showToast(model.preflight_message || t('preflightBlockedBadge'), true);
    return;
  }
  const btn = document.getElementById('btn-test-stt-' + modelId);
  if (!btn || btn.disabled) return;
  btn.disabled = true;
  const origHTML = btn.innerHTML;
  btn.innerHTML = '<span class="spinner-sm"></span> ' + t('modelTesting');

  try {
    if (window._testSTTModel) {
      // Async: Go runs in goroutine and calls _onSTTTestComplete when done
      await window._testSTTModel(modelId);
    }
  } catch (e) {
    btn.disabled = false;
    btn.innerHTML = origHTML;
    showToast(t('modelTestFailed'), true);
  }
}

// Callback from Go when STT model test completes (async).
window._onSTTTestComplete = function(modelId, success, text, error) {
  const btn = document.getElementById('btn-test-stt-' + modelId);
  if (btn) {
    btn.disabled = false;
    const playIcon = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg>';
    btn.innerHTML = playIcon + ' ' + t('modelTest');
  }
  if (success) {
    showToast(t('modelTestSuccess'), false);
  } else {
    showToast(error || t('modelTestFailed'), true);
  }
};

async function downloadModel(id) {
  const model = _localSTTModels.find(m => m.id === id);
  if (model && model.preflight_blocked) {
    showToast(model.preflight_message || t('preflightBlockedBadge'), true);
    return;
  }
  if (window.checkConnectivity) {
    try {
      const online = await window.checkConnectivity();
      if (!online) {
        showToast(t('connectivityRequired'), true);
        return;
      }
    } catch (e) {}
  }
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
    refreshLocalSTTPreflight(modelId).finally(() => renderModelList());
  } else {
    showStatus(errorMsg || t('modelDownloadError'), 'error');
    _downloadingModel = null;
    refreshLocalSTTPreflight(modelId).finally(() => renderModelList());
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
        // If the deleted model was the active one, refresh status bar with new config
        if (res.wasActive && window.getConfig) {
          const raw = await window.getConfig();
          const newCfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
          updateModeBadge(newCfg);
          updateStatusBar(newCfg);
        }
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
