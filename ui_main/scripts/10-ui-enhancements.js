/* ── UI Enhancements ─────────────────────────────────────
   Non-invasive hooks for new UI elements added during redesign.
   Uses MutationObservers and event delegation — no patching
   of existing functions required.
   ────────────────────────────────────────────────────────── */

(function () {
  'use strict';

  // ── History Stats Row ──────────────────────────────────
  // Updates the compact stats row above the history list.
  // Fires whenever #entriesList content changes.

  function updateHistoryStats() {
    const list = document.getElementById('entriesList');
    if (!list) return;

    const cards = list.querySelectorAll('.entry-card');
    const pinned = list.querySelectorAll('.entry-card[data-pinned="true"]').length;
    const total = cards.length;

    const totalEl = document.getElementById('statTotalEntries');
    if (totalEl) {
      const label = totalEl.querySelector('span[data-i18n]');
      if (label) label.textContent = total + ' ' + (t ? t('historyStatEntries') : 'dictations');
    }

    const pinnedEl = document.getElementById('statPinnedCount');
    if (pinnedEl) {
      const label = pinnedEl.querySelector('span[data-i18n]');
      if (label) label.textContent = pinned + ' ' + (t ? t('historyStatPinned') : 'pinned');
      pinnedEl.style.display = pinned > 0 ? '' : 'none';
    }

    // Toggle external empty state (hidden by default, only shows before first render)
    const emptyState = document.getElementById('historyEmptyState');
    if (emptyState) emptyState.classList.toggle('hidden', total > 0);
  }

  const entriesList = document.getElementById('entriesList');
  if (entriesList) {
    new MutationObserver(updateHistoryStats).observe(entriesList, { childList: true, subtree: true });
  }

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

      // Show section headers if any card in that section is visible
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
  // Shows the "Your Templates" header when custom templates exist.

  function updateCustomTemplatesHeader() {
    const grid = document.getElementById('custom-templates-grid');
    const header = document.getElementById('customTemplatesHeader');
    if (!grid || !header) return;

    const hasCards = grid.querySelectorAll('.preset-card').length > 0;
    header.style.display = hasCards ? '' : 'none';
    grid.style.display = hasCards ? '' : 'none';
  }

  const customGrid = document.getElementById('custom-templates-grid');
  if (customGrid) {
    new MutationObserver(updateCustomTemplatesHeader).observe(customGrid, { childList: true });
  }

})();
