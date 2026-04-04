/* ── Smart Actions on History Items ────────────────────── */

const SMART_PRESETS = [
    { id: 'cleanup' },
    { id: 'concise' },
    { id: 'translate' },
];

function _presetIcon(id) {
    const map = {
        cleanup: icons.sparkles, concise: icons.minimize,
        translate: icons.globe,
    };
    return map[id] || icons.sparkles;
}

function _smartActionTargetLang(preset) {
    if (preset !== 'translate') return '';
    return document.getElementById('select-smarttarget')?.value || 'en';
}

async function showSmartActionMenu(entryId, anchor) {
    const items = [];
    items.push({ header: t('smart.title') });

    for (const p of SMART_PRESETS) {
        items.push({
            icon: _presetIcon(p.id),
            label: t('smart.preset.' + p.id) || p.id,
            action: () => executeSmartAction(entryId, p.id, ''),
        });
    }

    showPopover(anchor, { items });
}

// Pending smart action contexts for async Go→JS callbacks
const _smartPending = new Map();

async function executeSmartAction(entryId, preset, customPrompt) {
    const processingToast = showToast(t('smart.processing'), false, 0);
    const targetLang = _smartActionTargetLang(preset);

    const entryEl = document.querySelector(`.entry[data-id="${entryId}"]`);
    if (entryEl) entryEl.classList.add('processing');

    _smartPending.set(entryId, { preset, processingToast, entryEl });

    try {
        const raw = await window.applySmartAction(entryId, preset, customPrompt || '', targetLang);
        const result = JSON.parse(raw);
        if (result.error) {
            _smartPending.delete(entryId);
            if (processingToast) processingToast.classList.remove('show');
            if (entryEl) entryEl.classList.remove('processing');
            showToast(result.error, true);
        }
    } catch (e) {
        _smartPending.delete(entryId);
        if (processingToast) processingToast.classList.remove('show');
        if (entryEl) entryEl.classList.remove('processing');
        showToast(t('smart.error'), true);
    }
}

// Called from Go via mainWebview.Dispatch when async smart action completes
window.onSmartActionComplete = async function(entryId, resultJSON, error) {
    const ctx = _smartPending.get(entryId);
    _smartPending.delete(entryId);

    if (ctx?.processingToast) ctx.processingToast.classList.remove('show');
    if (ctx?.entryEl) ctx.entryEl.classList.remove('processing');

    if (error) {
        showToast(error, true);
        return;
    }

    try {
        const result = JSON.parse(resultJSON);
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
                await window.updateEntryText(entryId, result.text, result.language || '');
                showToast(t('smart.replaced'), false);
            }
        } else {
            if (window.addSmartEntry) {
                await window.addSmartEntry(entryId, result.text, ctx?.preset || '', result.language || '');
                showToast(t('smart.created'), false);
            }
        }

        loadEntries();
    } catch (e) {
        showToast(t('smart.error'), true);
    }
};

/* ── Bulk Smart Actions (multi-select) ─────────────────── */

async function showBulkSmartActionMenu(anchor) {
    if (_selectedIds.size < 2) {
        showToast(t('smart.bulkTooFew'), false);
        return;
    }
    const items = [];
    items.push({ header: t('smart.bulkTitle') });

    for (const p of SMART_PRESETS) {
        items.push({
            icon: _presetIcon(p.id),
            label: t('smart.preset.' + p.id) || p.id,
            action: () => executeBulkSmartAction(p.id, ''),
        });
    }

    showPopover(anchor, { items });
}

let _bulkProcessingToast = null;

async function executeBulkSmartAction(preset, customPrompt) {
    const ids = [..._selectedIds];
    _bulkProcessingToast = showToast(t('smart.bulkProcessing'), false, 0);
    const targetLang = _smartActionTargetLang(preset);

    try {
        const raw = await window.applyBulkSmartAction(JSON.stringify(ids), preset, customPrompt, targetLang);
        const result = JSON.parse(raw);
        if (result.error) {
            if (_bulkProcessingToast) _bulkProcessingToast.classList.remove('show');
            _bulkProcessingToast = null;
            showToast(result.error, true);
        }
        // If status === "processing", result comes via onBulkSmartActionComplete
    } catch (e) {
        if (_bulkProcessingToast) _bulkProcessingToast.classList.remove('show');
        _bulkProcessingToast = null;
        showToast(t('smart.error'), true);
    }
}

// Called from Go via mainWebview.Dispatch when async bulk action completes
window.onBulkSmartActionComplete = async function(resultJSON, error) {
    if (_bulkProcessingToast) _bulkProcessingToast.classList.remove('show');
    _bulkProcessingToast = null;

    if (error) {
        showToast(error, true);
        return;
    }

    try {
        const result = JSON.parse(resultJSON);
        if (result.error) {
            showToast(result.error, true);
            return;
        }

        if (window.addBulkSmartEntry) {
            await window.addBulkSmartEntry(result.text, result.model || 'custom', result.language || '');
            showToast(t('smart.bulkCreated'), false);
        }

        clearSelection();
        loadEntries();
    } catch (e) {
        showToast(t('smart.error'), true);
    }
};
