/* ── Smart Actions on History Items ────────────────────── */

const SMART_PRESETS = [
    { id: 'cleanup' },
    { id: 'concise' },
    { id: 'email' },
    { id: 'formal' },
    { id: 'bullets' },
    { id: 'summary' },
    { id: 'notes' },
    { id: 'meeting' },
    { id: 'social' },
    { id: 'technical' },
    { id: 'casual' },
    { id: 'translate' },
    { id: 'custom' },
];

function showSmartActionMenu(entryId, anchor) {
    const items = [];
    items.push({ header: t('smart.title') });

    for (const p of SMART_PRESETS) {
        if (p.id === 'custom') {
            items.push({ divider: true });
            items.push({
                label: t('smart.custom'),
                action: () => showCustomPromptDialog(entryId),
            });
        } else {
            const presetId = p.id;
            items.push({
                label: t('smart.preset.' + presetId),
                action: () => executeSmartAction(entryId, presetId, ''),
            });
        }
    }

    showPopover(anchor, { items });
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
