/* ── Demo Mode ──────────────────────────────────────────── */
// Hidden feature for marketing screenshots.
// Activated by clicking the version number 5 times on the About page.

let _demoClickCount = 0;
let _demoClickTimer = null;

function initDemoMode() {
  // Block in Store package builds
  if (window.isStorePackage) {
    window.isStorePackage().then(store => {
      if (store) return;
      _setupDemoClickListener();
    });
  } else {
    _setupDemoClickListener();
  }
}

function _setupDemoClickListener() {
  const versionEl = document.getElementById('about-version');
  if (!versionEl) return;

  versionEl.style.cursor = 'pointer';
  versionEl.addEventListener('click', () => {
    _demoClickCount++;
    clearTimeout(_demoClickTimer);
    _demoClickTimer = setTimeout(() => { _demoClickCount = 0; }, 2000);

    if (_demoClickCount >= 5) {
      _demoClickCount = 0;
      const section = document.getElementById('demoToggleSection');
      if (section) {
        section.style.display = section.style.display === 'none' ? '' : 'none';
        // Sync toggle state
        if (window.isDemoMode) {
          window.isDemoMode().then(active => {
            const toggle = document.getElementById('demoModeToggle');
            if (toggle) toggle.checked = active;
          });
        }
      }
    }
  });
}

async function handleDemoToggle(checked) {
  if (!window.toggleDemoMode) return;

  const result = await window.toggleDemoMode();
  const toggle = document.getElementById('demoModeToggle');

  if (checked && !result) {
    // Failed to enable — reset toggle
    if (toggle) toggle.checked = false;
    return;
  }

  // Reload data on the history page
  if (typeof loadEntries === 'function') await loadEntries();
  if (typeof loadProjects === 'function') await loadProjects();

  // Show a brief notification
  const msg = checked
    ? (window._lang === 'de' ? 'Demo-Modus aktiviert' : 'Demo mode enabled')
    : (window._lang === 'de' ? 'Demo-Modus deaktiviert' : 'Demo mode disabled');
  if (typeof showToast === 'function') {
    showToast(msg);
  }
}

// Initialize on DOMContentLoaded (called from 05-init.js flow)
document.addEventListener('DOMContentLoaded', () => {
  initDemoMode();
});
