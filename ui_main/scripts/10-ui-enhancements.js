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

    // Default: expanded (collapsed only if user explicitly collapsed)
    toggleSpecialized(safeStorageGet(KEY) !== '0');
    specHeader.addEventListener('click', () => toggleSpecialized(!isExpanded()));
  }

  // ── Contextual Feature Discovery ───────────────────────
  // Legacy tip system removed — replaced by 13-discovery.js
  // which uses proper deduplication and single-instance tooltips.

})();
