/* ── Feature Discovery System ─────────────────────────── */
/* Secondary onboarding: contextual tooltips on first page visit. */
/* State stored in localStorage (UI-only, no config.json). */

const _discoveryConfig = {
  smartmode: {
    title: () => t('discovery.smartmode.title') || 'AI-powered refinement',
    desc: () => t('discovery.smartmode.desc') || 'Smart Mode refines your dictations with AI — try enabling it!',
    arrow: 'left'
  },
  analytics: {
    title: () => t('discovery.analytics.title') || 'Your dictation insights',
    desc: () => t('discovery.analytics.desc') || 'See your dictation patterns and productivity trends.',
    arrow: 'left'
  },
  replacements: {
    title: () => t('discovery.replacements.title') || 'Auto-correct your words',
    desc: () => t('discovery.replacements.desc') || 'Auto-correct words and phrases in every dictation.',
    arrow: 'left'
  }
};

function _discoveryKey(pageId) {
  return 'discovery_' + pageId + '_seen';
}

function _isDiscoverySeen(pageId) {
  try { return localStorage.getItem(_discoveryKey(pageId)) === '1'; } catch { return true; }
}

function _markDiscoverySeen(pageId) {
  try { localStorage.setItem(_discoveryKey(pageId), '1'); } catch {}
  // Remove nav dot
  const dot = document.querySelector(`.nav-item[data-page="${pageId}"] .discovery-dot`);
  if (dot) dot.remove();
}

function _dismissDiscovery(pageId) {
  _markDiscoverySeen(pageId);
  const tooltip = document.getElementById('discoveryTooltip');
  if (tooltip) tooltip.remove();
}

/** Show discovery tooltip for a page (first visit only). */
function showDiscoveryForPage(pageId) {
  const config = _discoveryConfig[pageId];
  if (!config || _isDiscoverySeen(pageId)) return;

  // Remove any existing tooltip
  const existing = document.getElementById('discoveryTooltip');
  if (existing) existing.remove();

  // Delay slightly so page content is rendered
  setTimeout(() => {
    const tooltip = document.createElement('div');
    tooltip.id = 'discoveryTooltip';
    tooltip.className = `discovery-tooltip arrow-${config.arrow}`;
    tooltip.innerHTML = `
      <div class="discovery-tooltip-title">${config.title()}</div>
      <div class="discovery-tooltip-desc">${config.desc()}</div>
      <div class="discovery-tooltip-actions">
        <button class="discovery-tooltip-dismiss" onclick="_dismissDiscovery('${pageId}')">${t('discovery.gotIt') || 'Got it'}</button>
      </div>
    `;

    document.body.appendChild(tooltip);

    // Position near the page content top-left
    const page = document.getElementById('page-' + pageId);
    if (page) {
      const rect = page.getBoundingClientRect();
      tooltip.style.top = (rect.top + 60) + 'px';
      tooltip.style.left = (rect.left + 24) + 'px';
    }

    // Auto-dismiss after 8 seconds
    setTimeout(() => _dismissDiscovery(pageId), 8000);
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
