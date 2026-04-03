/* ── Smart Actions on History Items ────────────────────── */

const SMART_PRESETS = [
    { id: 'cleanup' },
    { id: 'concise' },
    { id: 'email' },
    { id: 'formal' },
    { id: 'bullets' },
    { id: 'aiprompt' },
    { id: 'summary' },
    { id: 'notes' },
    { id: 'meeting' },
    { id: 'social' },
    { id: 'technical' },
    { id: 'casual' },
    { id: 'translate' },
];

function _presetIcon(id) {
    const map = {
        cleanup: icons.sparkles, concise: icons.minimize, email: icons.mail,
        formal: icons.fileText, bullets: icons.list, aiprompt: icons.bot,
        summary: icons.fileText, notes: icons.clipboard, meeting: icons.users,
        social: icons.share, technical: icons.code, casual: icons.messageCircle,
        translate: icons.globe,
    };
    return map[id] || icons.sparkles;
}

function _smartActionTargetLang(preset) {
    if (preset !== 'translate') return '';
    return document.getElementById('select-smarttarget')?.value || 'en';
}

async function showSmartActionMenu(entryId, anchor) {
    const templates = await getAllSmartTemplates();
    const items = [];
    items.push({ header: t('smart.title') });

    // Built-in presets
    const builtIn = templates.filter(tpl => !tpl.isCustom);
    for (const tpl of builtIn) {
        items.push({
            icon: _presetIcon(tpl.id),
            label: tpl.label,
            action: () => executeSmartAction(entryId, tpl.id, ''),
        });
    }

    // Custom templates
    const custom = templates.filter(tpl => tpl.isCustom);
    if (custom.length > 0) {
        items.push({ divider: true });
        items.push({ header: t('smart.customSection') });
        for (const tpl of custom) {
            items.push({
                icon: icons.fileText,
                label: esc(tpl.label),
                action: () => executeSmartAction(entryId, tpl.id, ''),
            });
        }
    }

    // Custom prompt option
    items.push({ divider: true });
    items.push({
        icon: icons.pencil,
        label: t('smart.custom'),
        action: () => showCustomPromptDialog(entryId),
    });

    showPopover(anchor, { items });
}

async function showCustomPromptDialog(entryId) {
    const result = await showDialog({
        title: t('smart.customTitle'),
        message: '<textarea id="smartCustomPrompt" class="smart-custom-textarea" rows="4" placeholder="' + esc(t('smart.customPlaceholder')) + '"></textarea>',
        htmlMessage: true,
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

// Pending smart action contexts for async Go→JS callbacks
const _smartPending = new Map();

async function executeSmartAction(entryId, preset, customPrompt) {
    const processingToast = showToast(t('smart.processing'), false, 0);
    const targetLang = _smartActionTargetLang(preset);

    const entryEl = document.querySelector(`.entry[data-id="${entryId}"]`);
    if (entryEl) entryEl.classList.add('processing');

    _smartPending.set(entryId, { preset, processingToast, entryEl });

    try {
        const raw = await window.applySmartAction(entryId, preset, customPrompt, targetLang);
        const result = JSON.parse(raw);
        // Immediate validation error — clean up now
        if (result.error) {
            _smartPending.delete(entryId);
            if (processingToast) processingToast.classList.remove('show');
            if (entryEl) entryEl.classList.remove('processing');
            showToast(result.error, true);
        }
        // If status === "processing", result comes via onSmartActionComplete
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
    const templates = await getAllSmartTemplates();
    const items = [];
    items.push({ header: t('smart.bulkTitle') });

    for (const tpl of templates.filter(x => !x.isCustom)) {
        items.push({
            icon: _presetIcon(tpl.id),
            label: tpl.label,
            action: () => executeBulkSmartAction(tpl.id, ''),
        });
    }

    const custom = templates.filter(x => x.isCustom);
    if (custom.length > 0) {
        items.push({ divider: true });
        items.push({ header: t('smart.customSection') });
        for (const tpl of custom) {
            items.push({
                icon: icons.fileText,
                label: esc(tpl.label),
                action: () => executeBulkSmartAction(tpl.id, ''),
            });
        }
    }

    items.push({ divider: true });
    items.push({
        icon: icons.pencil,
        label: t('smart.custom'),
        action: () => showBulkCustomPromptDialog(),
    });

    showPopover(anchor, { items });
}

async function showBulkCustomPromptDialog() {
    const result = await showDialog({
        title: t('smart.customTitle'),
        message: '<textarea id="smartBulkPrompt" class="smart-custom-textarea" rows="4" placeholder="' + esc(t('smart.customPlaceholder')) + '"></textarea>',
        htmlMessage: true,
        confirmText: t('smart.apply'),
        cancelText: t('cancel'),
    });

    if (result) {
        const textarea = document.getElementById('smartBulkPrompt');
        const prompt = textarea ? textarea.value.trim() : '';
        if (prompt) {
            await executeBulkSmartAction('custom', prompt);
        }
    }
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
