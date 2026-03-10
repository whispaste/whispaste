/* ── Test Recording ───────────────────────────────────── */
let _isTesting = false;
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
    showToast(t('audioDeviceError') || 'Failed to load audio devices', true);
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
    if (meter) meter.classList.add('hidden');
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

  if (meter) meter.classList.remove('hidden');
  if (btn) btn.classList.add('recording');
  let count = 0;
  _testAudioInterval = setInterval(async () => {
    count++;
    if (count > 100) { // 10 seconds
      clearInterval(_testAudioInterval);
      _testAudioInterval = null;
      if (meter) meter.classList.add('hidden');
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

/* ── Model List Rendering ───────────────────────────────*/
async function renderModelList() {
  const container = document.getElementById('model-list');
  if (!container) return;
  
  let models = [];
  if (window._getModels) {
    try {
      const result = await window._getModels();
      models = typeof result === 'string' ? JSON.parse(result) : result;
    } catch (e) {
      showToast(t('modelLoadError') || 'Failed to load models', true);
    }
  }
  
  if (!models || models.length === 0) {
    models = [
      { id: 'whisper-base', name: 'Whisper Base', size: '57MB', downloaded: false },
      { id: 'whisper-small', name: 'Whisper Small', size: '175MB', downloaded: false }
    ];
  }
  
  container.innerHTML = models.map(m => {
    const isDownloading = _downloadingModel === m.id;
    let actionBtn;
    if (isDownloading) {
      actionBtn = `<button class="btn btn-secondary btn-sm" disabled>${t('modelDownloading')}</button>
        <div class="model-progress"><div class="model-progress-bar" id="progress-${m.id}"></div></div>`;
    } else if (m.downloaded) {
      actionBtn = `<button class="btn btn-secondary btn-sm btn-model-test" id="btn-test-stt-${m.id}" onclick="event.stopPropagation();testSTTModel('${m.id}')"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg> ${t('modelTest')}</button><span class="model-badge model-badge-success">✓ ${t('modelDownloaded')}</span><button class="btn btn-icon btn-sm btn-ghost" onclick="event.stopPropagation();confirmDeleteModel('${m.id}')" title="${t('modelDelete')}"><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>`;
    } else {
      actionBtn = `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();downloadModel('${m.id}')">${t('modelDownload')}</button>`;
    }
    return `<div class="model-item ${!m.downloaded && !isDownloading ? 'unavailable' : ''}" data-model-id="${m.id}">
      <div class="model-item-info">
        <div class="model-item-name">${m.name}</div>
        ${t('model.desc.' + m.id) ? '<div class="model-desc">' + esc(t('model.desc.' + m.id)) + '</div>' : ''}
        <div class="model-item-meta">${m.size}${!m.downloaded ? ' · ' + t('modelNotDownloaded') : ''}</div>
      </div>
      <div class="model-item-action">${actionBtn}</div>
    </div>`;
  }).join('');
}


/* ── STT Model Test ─────────────────────────────────────── */
async function testSTTModel(modelId) {
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
    renderModelList();
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