/* ── Popover / Context Menu ────────────────────────────── */

/** @type {HTMLElement|null} */
let _activePopover = null;

/**
 * Build the popover DOM from an options object.
 * @param {{
 *   items?: Array<{icon?: string, label: string, action?: function, danger?: boolean, disabled?: boolean, divider?: boolean, header?: string, checked?: boolean, headerToggle?: {label:string, on:boolean, action:function}, footer?: {label:string, action:function}}>,
 *   className?: string
 * }} options
 * @returns {HTMLElement}
 */
function _buildPopover(options) {
  const el = document.createElement('div');
  el.className = 'wp-popover' + (options.className ? ' ' + options.className : '');

  if (options.items) {
    for (const item of options.items) {
      if (item.divider) {
        const div = document.createElement('div');
        div.className = 'wp-popover-divider';
        el.appendChild(div);
        continue;
      }
      if (item.header) {
        const hdr = document.createElement('div');
        hdr.className = 'wp-popover-header';
        hdr.textContent = item.header;
        // Optional toggle button in header
        if (item.headerToggle) {
          hdr.style.display = 'flex';
          hdr.style.justifyContent = 'space-between';
          hdr.style.alignItems = 'center';
          const btn = document.createElement('button');
          btn.className = 'wp-popover-toggle' + (item.headerToggle.on ? ' on' : '');
          btn.textContent = item.headerToggle.label;
          btn.addEventListener('click', (e) => {
            e.stopPropagation();
            hidePopovers();
            item.headerToggle.action();
          });
          hdr.appendChild(btn);
        }
        el.appendChild(hdr);
        continue;
      }
      if (item.footer) {
        const ftr = document.createElement('div');
        ftr.className = 'wp-popover-footer';
        const link = document.createElement('a');
        link.className = 'wp-popover-footer-link';
        link.textContent = item.footer.label;
        link.addEventListener('click', (e) => {
          e.stopPropagation();
          hidePopovers();
          item.footer.action();
        });
        ftr.appendChild(link);
        el.appendChild(ftr);
        continue;
      }
      const row = document.createElement('div');
      row.className = 'wp-popover-item';
      if (item.danger) row.classList.add('danger');
      if (item.disabled) row.classList.add('disabled');
      if (item.checked) row.classList.add('checked');

      if (item.icon) {
        const iconSpan = document.createElement('span');
        iconSpan.className = 'icon';
        iconSpan.innerHTML = item.icon;
        // unwrap: if the icon HTML itself is an svg with class="icon", use it directly
        const innerSvg = iconSpan.querySelector('svg');
        if (innerSvg) {
          innerSvg.classList.add('icon');
          innerSvg.style.width = '100%';
          innerSvg.style.height = '100%';
        }
        row.appendChild(iconSpan);
      }

      const label = document.createElement('span');
      label.textContent = item.label;
      label.style.flex = '1';
      row.appendChild(label);

      if (item.checked) {
        const chk = document.createElement('span');
        chk.className = 'wp-popover-check';
        chk.innerHTML = icons.check || '✓';
        row.appendChild(chk);
      }

      if (item.action && !item.disabled) {
        row.addEventListener('click', (e) => {
          e.stopPropagation();
          hidePopovers();
          item.action();
        });
      }

      el.appendChild(row);
    }
  }

  return el;
}

/**
 * Position the popover so it stays within the viewport.
 * Automatically flips above the anchor when near the bottom of the viewport.
 * @param {HTMLElement} popover
 * @param {number} x  desired left
 * @param {number} y  desired top
 * @param {HTMLElement} [anchor] optional anchor element for smart flip
 */
function _positionPopover(popover, x, y, anchor) {
  // Place off-screen first to measure
  popover.style.left = '-9999px';
  popover.style.top = '-9999px';
  document.body.appendChild(popover);

  const rect = popover.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const pad = 4;

  // Flip horizontally if needed
  let left = x;
  if (left + rect.width > vw - pad) {
    left = Math.max(pad, vw - rect.width - pad);
  }

  // Flip vertically: if popover would overflow below, position above anchor
  let top = y;
  if (top + rect.height > vh - pad) {
    if (anchor) {
      const ar = anchor.getBoundingClientRect();
      top = ar.top - rect.height - 4;
      // Add upward animation class
      popover.classList.add('wp-popover-flip-up');
    } else {
      top = Math.max(pad, y - rect.height);
    }
  }
  if (top < pad) top = pad;

  popover.style.left = left + 'px';
  popover.style.top = top + 'px';
}

/**
 * Show a popover anchored to an element.
 * @param {HTMLElement} anchor
 * @param {{items?: Array, className?: string}} options
 * @returns {HTMLElement} the popover element
 */
function showPopover(anchor, options) {
  hidePopovers();
  const popover = _buildPopover(options);

  const r = anchor.getBoundingClientRect();
  // Default: below-left aligned to the anchor (auto-flips above if near bottom)
  _positionPopover(popover, r.left, r.bottom + 4, anchor);

  _activePopover = popover;
  return popover;
}

/**
 * Show a popover at explicit coordinates (e.g. right-click).
 * @param {number} x
 * @param {number} y
 * @param {{items?: Array, className?: string}} options
 * @returns {HTMLElement} the popover element
 */
function showPopoverAt(x, y, options) {
  hidePopovers();
  const popover = _buildPopover(options);
  _positionPopover(popover, x, y);
  _activePopover = popover;
  return popover;
}

/** Hide and remove all open popovers. */
function hidePopovers() {
  if (_activePopover) {
    _activePopover.remove();
    _activePopover = null;
  }
}

/* ── Global listeners ─────────────────────────────────── */
document.addEventListener('mousedown', (e) => {
  if (_activePopover && !_activePopover.contains(e.target)) {
    hidePopovers();
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && _activePopover) {
    hidePopovers();
  }
});
