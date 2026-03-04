/* ── Utility Functions ─────────────────────────────────── */

/** HTML-escape a string to prevent XSS */
function esc(s) {
  const d = document.createElement('div');
  d.textContent = s || '';
  return d.innerHTML;
}

/** Format a timestamp for display */
function formatTime(ts) {
  const d = new Date(ts);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' ' +
    d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/** Format seconds into human-readable duration */
function formatDuration(sec) {
  if (!sec || sec < 1) return '';
  if (sec < 60) return Math.round(sec) + 's';
  return Math.floor(sec / 60) + 'm ' + Math.round(sec % 60) + 's';
}

/** Show a toast notification */
function showToast(msg, isError) {
  const t = document.getElementById('toast');
  if (!t) return;
  t.textContent = msg;
  t.className = 'toast show' + (isError ? ' error' : '');
  setTimeout(() => t.classList.remove('show'), 2200);
}

/** Show an inline status message */
let _statusTimeout = null;
function showStatus(msg, type) {
  const el = document.getElementById('status-msg');
  if (!el) return;
  el.textContent = msg;
  el.className = 'status-msg visible ' + type;
  clearTimeout(_statusTimeout);
  _statusTimeout = setTimeout(() => {
    el.classList.remove('visible');
    setTimeout(() => { el.textContent = ''; }, 300);
  }, 3000);
}

/** Open an external URL through Go binding */
function openExternal(url) {
  if (window.openURL) window.openURL(url);
}

/** Update the transcription mode badge (Local / API) */
function updateModeBadge(cfg) {
  const badge = document.getElementById('modeBadge');
  if (!badge) return;
  const isLocal = cfg && cfg.use_local_stt;
  badge.textContent = isLocal ? t('modeLocal') : t('modeApi');
  badge.title = isLocal ? t('modeLocalTip') : t('modeApiTip');
  badge.classList.toggle('mode-local', !!isLocal);
}

/** Update global status bar indicators from config */
function updateStatusBar(cfg) {
  if (!cfg) return;
  const isLocal = cfg.use_local_stt;

  // Mode + Model combined chip
  const modeLabel = document.getElementById('statusModeLabel');
  const modeChip = document.getElementById('statusMode');
  const modelName = isLocal ? (cfg.local_model_id || 'whisper-tiny') : (cfg.model || 'whisper-1');
  const modeText = (isLocal ? t('modeLocal') : t('modeApi')) + ' · ' + modelName;
  if (modeLabel) modeLabel.textContent = modeText;
  if (modeChip) modeChip.title = isLocal ? t('modeLocalTip') : t('modeApiTip');

  // Hotkey chip
  const hotkeyLabel = document.getElementById('statusHotkeyLabel');
  const hotkeyChip = document.getElementById('statusHotkey');
  const mods = cfg.hotkey_modifiers || ['Ctrl', 'Shift'];
  const key = cfg.hotkey_key || 'V';
  if (hotkeyLabel) hotkeyLabel.textContent = mods.join('+') + '+' + key;
  if (hotkeyChip) hotkeyChip.title = t('statusbar.hotkey_tip');

  // Smart Mode chip
  const smartLabel = document.getElementById('statusSmartLabel');
  const smartChip = document.getElementById('statusSmart');
  if (smartLabel) smartLabel.textContent = cfg.smart_mode ? t('statusbar.on') : t('statusbar.off');
  if (smartChip) {
    smartChip.title = t('statusbar.smart_tip');
    smartChip.classList.toggle('accent', !!cfg.smart_mode);
  }

  // Version chip
  const versionLabel = document.getElementById('statusVersionLabel');
  if (versionLabel) {
    const ver = (translations[_currentUILang] && translations[_currentUILang]['app.version']) || 'v' + (window._appVersion || '0.1.1-alpha');
    versionLabel.textContent = ver;
  }
}

/** Navigate to settings page and scroll to a specific section */
function scrollToSettingsSection(sectionId) {
  switchPage('settings');
  setTimeout(() => {
    document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }, 100);
}

/** Lucide SVG icon fragments (reusable) */

/* ── Tag Color Palette ─────────────────────────────────── */
const TAG_COLORS = [
  { bg: 'rgba(6,182,212,0.12)',  border: 'rgba(6,182,212,0.3)',  text: '#22d3ee' },   // cyan
  { bg: 'rgba(168,85,247,0.12)', border: 'rgba(168,85,247,0.3)', text: '#a855f7' },   // purple
  { bg: 'rgba(249,115,22,0.12)', border: 'rgba(249,115,22,0.3)', text: '#f97316' },   // orange
  { bg: 'rgba(34,197,94,0.12)',  border: 'rgba(34,197,94,0.3)',  text: '#22c55e' },   // green
  { bg: 'rgba(239,68,68,0.12)',  border: 'rgba(239,68,68,0.3)',  text: '#ef4444' },   // red
  { bg: 'rgba(59,130,246,0.12)', border: 'rgba(59,130,246,0.3)', text: '#3b82f6' },   // blue
  { bg: 'rgba(236,72,153,0.12)', border: 'rgba(236,72,153,0.3)', text: '#ec4899' },   // pink
  { bg: 'rgba(234,179,8,0.12)',  border: 'rgba(234,179,8,0.3)',  text: '#eab308' },   // yellow
];

/** Get a deterministic color for a tag name */
function getTagColor(tagName) {
  let hash = 0;
  for (let i = 0; i < tagName.length; i++) {
    hash = ((hash << 5) - hash + tagName.charCodeAt(i)) | 0;
  }
  return TAG_COLORS[Math.abs(hash) % TAG_COLORS.length];
}

const icons = {
  copy: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>',
  pin: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" x2="12" y1="17" y2="22"/><path d="M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24Z"/></svg>',
  trash: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>',
  microphone: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/></svg>',
  tag: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/></svg>',
  pencil: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/></svg>',
  chevronDown: '<svg class="icon icon-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
  check: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  x: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
  files: '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 7h-3a2 2 0 0 1-2-2V2"/><path d="M9 18a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h7l4 4v10a2 2 0 0 1-2 2Z"/><path d="M3 7.6v12.8A1.6 1.6 0 0 0 4.6 22h9.8"/></svg>'
};
