/* ── Configuration Profiles ──────────────────────────── */

async function loadProfileList() {
  const select = document.getElementById('profileSelect');
  const deleteBtn = document.getElementById('profileDeleteBtn');
  if (!select || !window.listProfiles) return;

  const raw = await window.listProfiles();
  const names = JSON.parse(raw || '[]');

  // Remove all options except first (No Profile)
  while (select.options.length > 1) select.remove(1);

  for (const name of names) {
    const opt = document.createElement('option');
    opt.value = name;
    opt.textContent = name;
    select.appendChild(opt);
  }

  // Select active profile
  try {
    const cfgRaw = await window.getConfig();
    const cfg = typeof cfgRaw === 'string' ? JSON.parse(cfgRaw) : cfgRaw;
    if (cfg.active_profile) {
      select.value = cfg.active_profile;
    }
  } catch (e) {}

  if (deleteBtn) {
    deleteBtn.style.display = select.value ? '' : 'none';
  }
}

async function onProfileSelect(name) {
  const deleteBtn = document.getElementById('profileDeleteBtn');

  if (!name) {
    // "No Profile" selected — just clear active
    if (deleteBtn) deleteBtn.style.display = 'none';
    return;
  }

  if (window.loadProfile) {
    const ok = await window.loadProfile(name);
    if (ok) {
      // Reload config into UI
      const raw = await window.getConfig();
      const cfg = typeof raw === 'string' ? JSON.parse(raw) : raw;
      applyConfig(cfg);
      updateModeBadge(cfg);
      updateStatusBar(cfg);
      showToast(t('profile.loaded') + ': ' + name, false);
    }
  }

  if (deleteBtn) deleteBtn.style.display = name ? '' : 'none';
}

async function promptSaveProfile() {
  const select = document.getElementById('profileSelect');
  const currentName = select ? select.value : '';

  const name = await showPromptDialog(
    t('profile.save_title'),
    t('profile.save_msg'),
    { defaultValue: currentName || '', confirmText: t('profile.save') }
  );

  if (!name || !name.trim()) return;

  if (window.saveProfile) {
    await window.saveProfile(name.trim());
    await loadProfileList();
    const sel = document.getElementById('profileSelect');
    if (sel) sel.value = name.trim();
    const deleteBtn = document.getElementById('profileDeleteBtn');
    if (deleteBtn) deleteBtn.style.display = '';
    showToast(t('profile.saved') + ': ' + name.trim(), false);
  }
}

async function deleteCurrentProfile() {
  const select = document.getElementById('profileSelect');
  if (!select || !select.value) return;

  const name = select.value;
  const ok = await showConfirmDialog(
    t('profile.delete_title'),
    t('profile.delete_msg').replace('{name}', name),
    t('profile.delete'),
    t('cancel')
  );

  if (!ok) return;

  if (window.deleteProfile) {
    await window.deleteProfile(name);
    await loadProfileList();
    showToast(t('profile.deleted') + ': ' + name, false);
  }
}
