let _currentAudio = null;
let _playingId = null;
let _playingIndex = null;

/** Wait for an audio element to finish or get paused/interrupted. */
function _audioEnded(audio) {
  return new Promise(resolve => {
    audio.addEventListener('ended', resolve, { once: true });
    audio.addEventListener('pause', resolve, { once: true });
  });
}

/** Stop current playback and clean up state. */
function _stopCurrentPlayback() {
  if (_currentAudio) {
    _currentAudio.pause();
    _currentAudio = null;
    _resetPlayButton(_playingId);
    _playingId = null;
    _playingIndex = null;
    hideStatusbarAudio();
  }
}

function showStatusbarAudio(label) {
  const chip = document.getElementById('statusAudio');
  const lbl = document.getElementById('statusAudioLabel');
  if (chip) {
    chip.classList.remove('hidden');
    chip.title = t('statusbar.audio_stop') || 'Stop playback';
  }
  if (lbl) lbl.textContent = label || (t('statusbar.audio_playing') || 'Playing…');
}

function hideStatusbarAudio() {
  const chip = document.getElementById('statusAudio');
  if (chip) chip.classList.add('hidden');
}

function stopStatusbarAudio() {
  _stopCurrentPlayback();
  if (typeof renderHistory === 'function') renderHistory();
}
window.stopStatusbarAudio = stopStatusbarAudio;

async function doPlayAudio(id) {
  const btn = document.querySelector(`[data-action="play-audio"][data-id="${id}"]`);

  if (_currentAudio && _playingId === id) {
    _stopCurrentPlayback();
    return;
  }

  _stopCurrentPlayback();

  try {
    const dataUrl = await window.getAudioBase64(id);
    if (!dataUrl) { showToast(t('notebook.no_audio'), true); return; }
    _currentAudio = new Audio(dataUrl);
    _playingId = id;
    _playingIndex = 0;

    if (btn) {
      btn.innerHTML = icons.stop;
      btn.title = t('notebook.stop_audio');
      btn.classList.add('playing');
    }

    const audioInstance = _currentAudio;
    const capturedId = id;
    await audioInstance.play();
    showStatusbarAudio(t('statusbar.audio_playing'));
    await _audioEnded(audioInstance);

    _resetPlayButton(capturedId);
    if (_currentAudio === audioInstance) {
      _currentAudio = null;
      _playingId = null;
      _playingIndex = null;
      hideStatusbarAudio();
    }
  } catch (e) {
    showToast(t('notebook.no_audio'), true);
    _resetPlayButton(id);
    _playingId = null;
    _playingIndex = null;
    hideStatusbarAudio();
  }
}

async function doPlayAudioByIndex(id, idx) {
  if (_currentAudio && _playingId === id && _playingIndex === idx) {
    _stopCurrentPlayback();
    return;
  }

  _stopCurrentPlayback();

  try {
    const dataUrl = await window.getAudioBase64ByIndex(id, idx);
    if (!dataUrl) { showToast(t('notebook.no_audio'), true); return; }
    _currentAudio = new Audio(dataUrl);
    _playingId = id;
    _playingIndex = idx;

    const audioInstance = _currentAudio;
    const capturedId = id;
    await audioInstance.play();
    showStatusbarAudio(t('statusbar.audio_playing'));
    await _audioEnded(audioInstance);

    _resetPlayButton(capturedId);
    if (_currentAudio === audioInstance) {
      _currentAudio = null;
      _playingId = null;
      _playingIndex = null;
      hideStatusbarAudio();
    }
  } catch (e) {
    showToast(t('notebook.no_audio'), true);
    _playingId = null;
    _playingIndex = null;
    hideStatusbarAudio();
  }
}

function _resetPlayButton(id) {
  if (!id) return;
  const btn = document.querySelector(`[data-action="play-audio"][data-id="${id}"]`);
  if (btn) {
    btn.innerHTML = icons.play;
    btn.title = t('notebook.play_audio');
    btn.classList.remove('playing');
  }
}

async function doReTranscribe(id, btn) {
  if (!window.reTranscribe) { _pendingRetryInFlight = false; return; }
  const origHTML = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<svg class="icon spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>';

  showStatus(t('notebook.retranscribing') || 'Re-transcribing...', 'info');

  try {
    const result = await window.reTranscribe(id);
    if (result && result.async) {
      // Async mode — result will come via onReTranscribeResult callback
      window._reTranscribeBtn = btn;
      window._reTranscribeBtnHTML = origHTML;
      return;
    }
    // Fallback for sync mode (defensive)
    if (result && result.ok) {
      showToast(t('notebook.retranscribed'), false);
      await loadEntries();
    } else {
      showToast(result?.error || t('notebook.no_audio'), true);
    }
  } catch (e) {
    showToast(t('notebook.no_audio'), true);
  }
  btn.innerHTML = origHTML;
  btn.disabled = false;
  _pendingRetryInFlight = false;
}

// Callback from Go when async re-transcription completes
window.onReTranscribeResult = async function(id, success, errorMsg) {
  const btn = window._reTranscribeBtn;
  const origHTML = window._reTranscribeBtnHTML;

  if (success) {
    showStatus(t('notebook.retranscribed') || 'Re-transcribed', 'success');
    await loadEntries();
  } else {
    showStatus(errorMsg || t('notebook.no_audio'), 'error');
  }

  if (btn) {
    btn.innerHTML = origHTML || '';
    btn.disabled = false;
  }
  window._reTranscribeBtn = null;
  window._reTranscribeBtnHTML = null;
  _pendingRetryInFlight = false;
};
