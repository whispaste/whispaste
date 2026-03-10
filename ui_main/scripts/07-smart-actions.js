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

async function showSmartActionMenu(entryId, anchor) {
    const templates = await getAllSmartTemplates();
    const items = [];
    items.push({ header: t('smart.title') });

    // Built-in presets
    const builtIn = templates.filter(tpl => !tpl.isCustom);
    for (const tpl of builtIn) {
        items.push({
            label: tpl.label,
            action: () => executeSmartAction(entryId, tpl.id, ''),
        });
    }

    // Custom templates
    const custom = templates.filter(tpl => tpl.isCustom);
    if (custom.length > 0) {
        items.push({ divider: true });
        for (const tpl of custom) {
            items.push({
                label: esc(tpl.label),
                action: () => executeSmartAction(entryId, tpl.id, ''),
            });
        }
    }

    // Custom prompt option
    items.push({ divider: true });
    items.push({
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
            label: tpl.label,
            action: () => executeBulkSmartAction(tpl.id, ''),
        });
    }

    const custom = templates.filter(x => x.isCustom);
    if (custom.length > 0) {
        items.push({ divider: true });
        for (const tpl of custom) {
            items.push({
                label: esc(tpl.label),
                action: () => executeBulkSmartAction(tpl.id, ''),
            });
        }
    }

    items.push({ divider: true });
    items.push({
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

async function executeBulkSmartAction(preset, customPrompt) {
    const ids = [..._selectedIds];
    showToast(t('smart.bulkProcessing'), false);

    try {
        const raw = await window.applyBulkSmartAction(JSON.stringify(ids), preset, customPrompt);
        const result = JSON.parse(raw);

        if (result.error) {
            showToast(result.error, true);
            return;
        }

        if (window.addBulkSmartEntry) {
            await window.addBulkSmartEntry(result.text, preset || 'custom', result.language || '');
            showToast(t('smart.bulkCreated'), false);
        }

        clearSelection();
        loadEntries();
    } catch (e) {
        showToast(t('smart.error'), true);
    }
}
