/* ── UI Enhancements ─────────────────────────────────────
   Non-invasive hooks for new UI elements added during redesign.
   Uses MutationObservers and event delegation — no patching
   of existing functions required.
   ────────────────────────────────────────────────────────── */

(function () {
  'use strict';

  // ── Replacements Count Badge ───────────────────────────
  // Updates the badge next to the Voice Shortcuts page title.

  function updateReplacementsCount() {
    const list = document.getElementById('replacements-list');
    const badge = document.getElementById('replacements-count-badge');
    if (!list || !badge) return;

    const rows = list.querySelectorAll('.replacement-row');
    const count = rows.length;
    badge.textContent = count;
    badge.style.display = count > 0 ? '' : 'none';
  }

  const replList = document.getElementById('replacements-list');
  if (replList) {
    new MutationObserver(updateReplacementsCount).observe(replList, { childList: true, subtree: true });
  }

  // ── Settings Search ────────────────────────────────────
  // Simple client-side filter for settings cards.

  const settingsSearch = document.getElementById('settingsSearchInput');
  if (settingsSearch) {
    settingsSearch.addEventListener('input', function () {
      const query = this.value.trim().toLowerCase();
      const scroll = document.querySelector('.settings-scroll');
      if (!scroll) return;

      const cards = scroll.querySelectorAll('.card');
      const headers = scroll.querySelectorAll('.settings-section-header');
      const intros = scroll.querySelectorAll('.settings-section-intro');

      if (!query) {
        cards.forEach(c => c.style.display = '');
        headers.forEach(h => h.style.display = '');
        intros.forEach(i => i.style.display = '');
        return;
      }

      cards.forEach(card => {
        const text = card.textContent.toLowerCase();
        card.style.display = text.includes(query) ? '' : 'none';
      });

      headers.forEach(header => {
        let next = header.nextElementSibling;
        let anyVisible = false;
        while (next && !next.classList.contains('settings-section-header')) {
          if (next.classList.contains('card') && next.style.display !== 'none') {
            anyVisible = true;
          }
          next = next.nextElementSibling;
        }
        header.style.display = anyVisible ? '' : 'none';
      });

      intros.forEach(intro => {
        const prev = intro.previousElementSibling;
        if (prev && prev.classList.contains('settings-section-header')) {
          intro.style.display = prev.style.display;
        }
      });
    });
  }

  // ── Custom Templates Header Visibility ─────────────────
  // Hides the import/export actions when no custom templates exist.

  function updateCustomTemplatesHeader() {
    const grid = document.getElementById('custom-templates-grid');
    const header = document.getElementById('customTemplatesHeader');
    if (!grid || !header) return;

    const hasCustom = grid.querySelectorAll('.preset-card[data-custom-template]').length > 0;
    const actions = header.querySelector('.section-title-actions');
    if (actions) actions.style.display = hasCustom ? '' : 'none';
  }

  const customGrid = document.getElementById('custom-templates-grid');
  if (customGrid) {
    new MutationObserver(updateCustomTemplatesHeader).observe(customGrid, { childList: true });
  }

  // ── Specialized Presets Collapse ────────────────────────
  // Hides specialized presets behind a toggle to reduce cognitive load.

  const specHeader = document.getElementById('specializedPresetsHeader');
  const specGrid = document.getElementById('preset-grid-specialized');
  if (specHeader && specGrid) {
    const KEY = 'wp_specialized_expanded';
    const isExpanded = () => safeStorageGet(KEY) === '1';

    function toggleSpecialized(expand) {
      specGrid.style.display = expand ? '' : 'none';
      specHeader.classList.toggle('collapsed', !expand);
      const chevron = specHeader.querySelector('.section-title-chevron');
      if (chevron) chevron.style.transform = expand ? 'rotate(90deg)' : '';
      safeStorageSet(KEY, expand ? '1' : '0');
    }

    // Default: collapsed
    toggleSpecialized(isExpanded());
    specHeader.addEventListener('click', () => toggleSpecialized(!isExpanded()));
  }

  // ── Contextual Feature Discovery ───────────────────────
  // Shows a dismissible tip the first time a user visits a page.

  function showFeatureTip(pageId, tipKey, message) {
    const storageKey = 'wp_tip_dismissed_' + tipKey;
    if (safeStorageGet(storageKey)) return;

    const page = document.getElementById(pageId);
    if (!page) return;

    const tip = document.createElement('div');
    tip.className = 'feature-tip';
    tip.innerHTML = `
      <svg class="icon feature-tip-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
      <span class="feature-tip-text">${message}</span>
      <button class="feature-tip-close" aria-label="Dismiss">
        <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
      </button>`;
    tip.querySelector('.feature-tip-close').addEventListener('click', () => {
      tip.remove();
      safeStorageSet(storageKey, '1');
    });

    // Insert after page-header
    const header = page.querySelector('.page-header');
    if (header && header.nextSibling) {
      header.parentNode.insertBefore(tip, header.nextSibling);
    } else {
      page.prepend(tip);
    }
  }

  // Observe page visibility to trigger tips on first visit
  const pageTips = {
    'page-smartmode': ['smartmode', () => t ? t('tipSmartMode') : 'Start with Cleanup — it fixes grammar and removes filler words automatically.'],
    'page-replacements': ['shortcuts', () => t ? t('tipShortcuts') : 'Use voice shortcuts for addresses, signatures, or canned responses you dictate often.'],
    'page-analytics': ['analytics', () => t ? t('tipAnalytics') : 'Track how voice input fits your workflow and where you save the most time.']
  };

  const observer = new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.type === 'attributes' && m.attributeName === 'class') {
        const el = m.target;
        if (el.classList.contains('page') && !el.classList.contains('hidden')) {
          const cfg = pageTips[el.id];
          if (cfg) showFeatureTip(el.id, cfg[0], cfg[1]());
        }
      }
    }
  });
  document.querySelectorAll('.page').forEach(p => {
    observer.observe(p, { attributes: true, attributeFilter: ['class'] });
  });

})();
