/* ── Feature Discovery System ─────────────────────────── */
/* Secondary onboarding: contextual tooltips on first page visit. */
/* State stored in localStorage (UI-only, no config.json). */

const _discoveryConfig = {
  analytics: {
    title: () => t('discovery.analytics.title'),
    desc: () => t('discovery.analytics.desc'),
    arrow: 'left'
  },
  replacements: {
    title: () => t('discovery.replacements.title'),
    desc: () => t('discovery.replacements.desc'),
    arrow: 'left'
  }
};

let _discoveryShowTimer = null;
let _discoveryDismissTimer = null;
let _discoveryCurrentPage = null;

function _discoveryKey(pageId) {
  return 'discovery_' + pageId + '_seen';
}

function _isDiscoverySeen(pageId) {
  try { return localStorage.getItem(_discoveryKey(pageId)) === '1'; } catch { return true; }
}

function _markDiscoverySeen(pageId) {
  try { localStorage.setItem(_discoveryKey(pageId), '1'); } catch {}
  const dot = document.querySelector(`.nav-item[data-page="${pageId}"] .discovery-dot`);
  if (dot) dot.remove();
}

function _dismissDiscovery(pageId) {
  _markDiscoverySeen(pageId);
  if (_discoveryDismissTimer) { clearTimeout(_discoveryDismissTimer); _discoveryDismissTimer = null; }
  const tooltip = document.getElementById('discoveryTooltip');
  if (tooltip) tooltip.remove();
  _discoveryCurrentPage = null;
}

function _cancelDiscoveryTimers() {
  if (_discoveryShowTimer) { clearTimeout(_discoveryShowTimer); _discoveryShowTimer = null; }
  if (_discoveryDismissTimer) { clearTimeout(_discoveryDismissTimer); _discoveryDismissTimer = null; }
}

/** Show discovery tooltip for a page (first visit only). */
function showDiscoveryForPage(pageId) {
  // Cancel any pending timers from previous page navigation
  _cancelDiscoveryTimers();

  const config = _discoveryConfig[pageId];
  if (!config || _isDiscoverySeen(pageId)) return;

  // Remove any existing tooltip
  const existing = document.getElementById('discoveryTooltip');
  if (existing) existing.remove();
  _discoveryCurrentPage = pageId;

  // Delay slightly so page content is rendered
  _discoveryShowTimer = setTimeout(() => {
    _discoveryShowTimer = null;
    // Guard: page might have changed during the delay
    if (_discoveryCurrentPage !== pageId) return;

    const tooltip = document.createElement('div');
    tooltip.id = 'discoveryTooltip';
    tooltip.className = `discovery-tooltip arrow-${config.arrow}`;
    tooltip.setAttribute('role', 'status');
    tooltip.setAttribute('aria-live', 'polite');

    const titleDiv = document.createElement('div');
    titleDiv.className = 'discovery-tooltip-title';
    titleDiv.textContent = config.title();

    const descDiv = document.createElement('div');
    descDiv.className = 'discovery-tooltip-desc';
    descDiv.textContent = config.desc();

    const actionsDiv = document.createElement('div');
    actionsDiv.className = 'discovery-tooltip-actions';
    const dismissBtn = document.createElement('button');
    dismissBtn.className = 'discovery-tooltip-dismiss';
    dismissBtn.textContent = t('discovery.gotIt');
    dismissBtn.addEventListener('click', () => _dismissDiscovery(pageId));
    actionsDiv.appendChild(dismissBtn);

    tooltip.appendChild(titleDiv);
    tooltip.appendChild(descDiv);
    tooltip.appendChild(actionsDiv);

    // Pause auto-dismiss on hover/focus
    tooltip.addEventListener('mouseenter', () => {
      if (_discoveryDismissTimer) { clearTimeout(_discoveryDismissTimer); _discoveryDismissTimer = null; }
    });
    tooltip.addEventListener('mouseleave', () => {
      if (document.body.contains(tooltip)) {
        _discoveryDismissTimer = setTimeout(() => {
          if (document.body.contains(tooltip)) _dismissDiscovery(pageId);
        }, 4000);
      }
    });

    document.body.appendChild(tooltip);

    // Position near the page content top-left
    const page = document.getElementById('page-' + pageId);
    if (page) {
      const rect = page.getBoundingClientRect();
      tooltip.style.top = (rect.top + 60) + 'px';
      tooltip.style.left = (rect.left + 24) + 'px';
    }

    // Auto-dismiss after 8 seconds (paused on hover)
    _discoveryDismissTimer = setTimeout(() => {
      if (document.body.contains(tooltip)) _dismissDiscovery(pageId);
    }, 8000);
  }, 400);
}

/** Add blue discovery dots to unvisited nav items. */
function initDiscoveryDots() {
  Object.keys(_discoveryConfig).forEach(pageId => {
    if (_isDiscoverySeen(pageId)) return;
    const navItem = document.querySelector(`.nav-item[data-page="${pageId}"]`);
    if (navItem && !navItem.querySelector('.discovery-dot')) {
      const dot = document.createElement('span');
      dot.className = 'discovery-dot';
      navItem.appendChild(dot);
    }
  });
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  // Only show discovery if onboarding is complete
  if (window._showOnboarding) return;
  initDiscoveryDots();
});
