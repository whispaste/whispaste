/* ── Smart Actions on History Items ────────────────────── */

const SMART_PRESETS = [
    { id: 'cleanup' },
    { id: 'concise' },
    { id: 'email' },
    { id: 'formal' },
    { id: 'bullets' },
    { id: 'summary' },
    { id: 'notes' },
    { id: 'translate' },
    { id: 'custom' },
];

function showSmartActionMenu(entryId, anchor) {
    document.querySelector('.smart-action-popover')?.remove();

    const popover = document.createElement('div');
    popover.className = 'smart-action-popover';

    let html = '<div class="smart-action-header">' + t('smart.title') + '</div>';
    html += '<div class="smart-action-list">';

    for (const p of SMART_PRESETS) {
        if (p.id === 'custom') {
            html += '<div class="smart-action-divider"></div>';
            html += `<div class="smart-action-item" data-preset="custom">
                <span class="smart-action-label">${t('smart.custom')}</span>
            </div>`;
        } else {
            html += `<div class="smart-action-item" data-preset="${p.id}">
                <span class="smart-action-label">${t('smart.preset.' + p.id)}</span>
            </div>`;
        }
    }
    html += '</div>';
    popover.innerHTML = html;
    document.body.appendChild(popover);

    // Position near anchor
    const rect = anchor.getBoundingClientRect();
    const popRect = popover.getBoundingClientRect();
    let top = rect.bottom + 4;
    if (top + popRect.height > window.innerHeight) {
        top = rect.top - popRect.height - 4;
    }
    popover.style.top = top + 'px';
    popover.style.left = Math.min(rect.left, window.innerWidth - popRect.width - 8) + 'px';

    // Click handler
    popover.addEventListener('click', async (e) => {
        const item = e.target.closest('.smart-action-item');
        if (!item) return;

        const preset = item.dataset.preset;
        popover.remove();

        if (preset === 'custom') {
            showCustomPromptDialog(entryId);
            return;
        }

        await executeSmartAction(entryId, preset, '');
    });

    // Close on outside click
    setTimeout(() => {
        const close = (e) => {
            if (!popover.contains(e.target)) {
                popover.remove();
                document.removeEventListener('click', close);
            }
        };
        document.addEventListener('click', close);
    }, 10);
}

async function showCustomPromptDialog(entryId) {
    const result = await showDialog({
        title: t('smart.customTitle'),
        message: '<textarea id="smartCustomPrompt" class="smart-custom-textarea" rows="4" placeholder="' + esc(t('smart.customPlaceholder')) + '"></textarea>',
        confirmText: t('smart.apply'),
        cancelText: t('cancel'),
    });

    if (result) {
        const textarea = document.getElementById('smartCustomPrompt');
        const prompt = textarea ? textarea.value.trim() : '';
        if (prompt) {
            await executeSmartAction(entryId, 'custom', prompt);
        }
    }
}

async function executeSmartAction(entryId, preset, customPrompt) {
    showToast(t('smart.processing'), false);

    try {
        const raw = await window.applySmartAction(entryId, preset, customPrompt);
        const result = JSON.parse(raw);

        if (result.error) {
            showToast(result.error, true);
            return;
        }

        const replace = await showDialog({
            title: t('smart.resultTitle'),
            message: t('smart.resultMessage'),
            confirmText: t('smart.replace'),
            cancelText: t('smart.createNew'),
        });

        if (replace) {
            if (window.updateEntryText) {
                await window.updateEntryText(entryId, result.text);
                showToast(t('smart.replaced'), false);
            }
        } else {
            if (window.addSmartEntry) {
                await window.addSmartEntry(entryId, result.text, preset);
                showToast(t('smart.created'), false);
            }
        }

        loadEntries();
    } catch (e) {
        showToast(t('smart.error'), true);
    }
}
