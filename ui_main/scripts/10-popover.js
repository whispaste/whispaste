/* ── Popover / Context Menu ────────────────────────────── */

/** @type {HTMLElement|null} */
let _activePopover = null;

/**
 * Build the popover DOM from an options object.
 * @param {{
 *   items?: Array<{icon?: string, label: string, action?: function, danger?: boolean, disabled?: boolean, divider?: boolean, header?: string}>,
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
        el.appendChild(hdr);
        continue;
      }
      const row = document.createElement('div');
      row.className = 'wp-popover-item';
      if (item.danger) row.classList.add('danger');
      if (item.disabled) row.classList.add('disabled');

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
      row.appendChild(label);

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
 * @param {HTMLElement} popover
 * @param {number} x  desired left
 * @param {number} y  desired top
 */
function _positionPopover(popover, x, y) {
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

  // Flip vertically if needed
  let top = y;
  if (top + rect.height > vh - pad) {
    top = Math.max(pad, y - rect.height);
  }

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
  // Default: below-left aligned to the anchor
  _positionPopover(popover, r.left, r.bottom + 4);

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
