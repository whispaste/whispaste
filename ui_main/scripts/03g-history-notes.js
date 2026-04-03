// Notes & Attachments panel logic for history entries

// ── Notes ────────────────────────────────────────────

async function loadNoteCount(entryId) {
  const el = document.getElementById('note-count-' + entryId);
  if (!el) return;
  try {
    const count = window.getNoteCount ? await window.getNoteCount(entryId) : 0;
    el.textContent = count > 0 ? '(' + count + ')' : '';
  } catch(e) { /* ignore */ }
}

async function loadAttachmentCount(entryId) {
  const el = document.getElementById('att-count-' + entryId);
  if (!el) return;
  try {
    const count = window.getAttachmentCount ? await window.getAttachmentCount(entryId) : 0;
    el.textContent = count > 0 ? '(' + count + ')' : '';
  } catch(e) { /* ignore */ }
}

function toggleNotesSection(entryId) {
  const body = document.getElementById('notes-body-' + entryId);
  if (!body) return;
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  const toggle = body.previousElementSibling;
  if (toggle) toggle.classList.toggle('open', !isOpen);
  if (!isOpen) loadNotes(entryId);
}

function toggleAttachmentsSection(entryId) {
  const body = document.getElementById('atts-body-' + entryId);
  if (!body) return;
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  const toggle = body.previousElementSibling;
  if (toggle) toggle.classList.toggle('open', !isOpen);
  if (!isOpen) loadAttachments(entryId);
}

async function loadNotes(entryId) {
  const container = document.getElementById('notes-list-' + entryId);
  if (!container || !window.getNotes) return;
  try {
    const json = await window.getNotes(entryId);
    const notes = JSON.parse(json);
    if (notes.length === 0) {
      container.innerHTML = `<div class="notes-empty-state">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 20h9"/><path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.855z"/></svg>
        <span>${t('notebook.notes_empty')}</span>
      </div>`;
    } else {
      container.innerHTML = notes.map(n => renderNote(n, entryId)).join('');
    }
    loadNoteCount(entryId);
    _bindNoteListeners(container, entryId);
  } catch(e) {
    container.innerHTML = '<div class="note-error">' + t('error.generic') + '</div>';
  }
}

function _bindNoteListeners(container, entryId) {
  container.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      if (btn.dataset.action === 'delete-note') {
        deleteNote(btn.dataset.noteId, btn.dataset.id);
      }
    });
  });
  container.querySelectorAll('.note-content').forEach(el => {
    el.addEventListener('blur', () => {
      const noteId = el.dataset.noteId;
      if (window.updateNote && noteId) {
        window.updateNote(noteId, el.textContent.trim()).catch(() => {});
      }
    });
    el.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape') { el.blur(); ev.stopPropagation(); }
    });
  });
}

function renderNote(note, entryId) {
  const date = formatRelativeTime ? formatRelativeTime(note.created_at) : note.created_at;
  const isVoice = note.content && note.content.startsWith('[voice]');
  const content = isVoice ? note.content.replace(/^\[voice\]\s*/, '') : note.content;
  const typeBadge = isVoice
    ? `<span class="note-type-badge voice"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>${t('notebook.voice')}</span>`
    : `<span class="note-type-badge text"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 20h9"/><path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.855z"/></svg>${t('notebook.text')}</span>`;
  return `<div class="note-card">
    <div class="note-card-header">
      <div class="note-meta">
        ${typeBadge}
        <span class="note-date">${esc(date)}</span>
      </div>
      <div class="note-card-actions">
        <button class="btn-icon btn-xs" data-action="delete-note" data-note-id="${note.id}" data-id="${entryId}" title="${t('notebook.delete')}">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
        </button>
      </div>
    </div>
    <div class="note-content" contenteditable="true" spellcheck="true" data-note-id="${note.id}" data-placeholder="${t('notebook.note_placeholder')}">${esc(content)}</div>
  </div>`;
}

async function saveNewNote(entryId) {
  const input = document.getElementById('note-input-' + entryId);
  if (!input || !input.value.trim()) return;
  try {
    if (window.addNote) await window.addNote(entryId, input.value.trim());
    input.value = '';
    await loadNotes(entryId);
  } catch(e) { showToast(t('error.generic'), true); }
}

async function deleteNote(noteId, entryId) {
  if (!noteId) return;
  try {
    if (window.deleteNote) await window.deleteNote(noteId);
    await loadNotes(entryId);
  } catch(e) { showToast(t('error.generic'), true); }
}

// Keyboard shortcut: Ctrl+Enter to save note
document.addEventListener('keydown', function(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    const textarea = e.target.closest('.note-input');
    if (!textarea) return;
    const entryId = textarea.id.replace('note-input-', '');
    if (entryId) { e.preventDefault(); saveNewNote(entryId); }
  }
});

// ── Attachments ──────────────────────────────────────

async function loadAttachments(entryId) {
  const container = document.getElementById('atts-list-' + entryId);
  if (!container || !window.getAttachments) return;
  try {
    const json = await window.getAttachments(entryId);
    const atts = JSON.parse(json);
    if (atts.length === 0) {
      container.innerHTML = `<div class="attachments-empty-state">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>
        <span>${t('notebook.attachments_empty')}</span>
      </div>`;
    } else {
      container.innerHTML = atts.map(a => renderAttachment(a, entryId)).join('');
    }
    loadAttachmentCount(entryId);
    _bindAttachmentListeners(container);
  } catch(e) {
    container.innerHTML = '<div class="note-error">' + t('error.generic') + '</div>';
  }
}

function _bindAttachmentListeners(container) {
  container.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const action = btn.dataset.action;
      if (action === 'open-attachment') openAttachment(btn.dataset.attId);
      else if (action === 'delete-attachment') deleteAttachment(btn.dataset.attId, btn.dataset.id);
    });
  });
  // Click on card to open
  container.querySelectorAll('.attachment-card').forEach(card => {
    card.addEventListener('dblclick', () => {
      const attId = card.dataset.attId;
      if (attId) openAttachment(attId);
    });
  });
}

function renderAttachment(att, entryId) {
  const icon = getFileIcon(att.mime_type, att.filename);
  const size = formatFileSize(att.size_bytes);
  return `<div class="attachment-card" data-att-id="${att.id}">
    <div class="attachment-icon">${icon}</div>
    <div class="attachment-info">
      <span class="attachment-name" title="${esc(att.filename)}">${esc(att.filename)}</span>
      <span class="attachment-size">${size}</span>
    </div>
    <div class="attachment-actions">
      <button class="btn-icon btn-xs" data-action="open-attachment" data-att-id="${att.id}" data-id="${entryId}" title="${t('notebook.open_file')}">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h6"/><path d="m21 3-9 9"/><path d="M15 3h6v6"/></svg>
      </button>
      <button class="btn-icon btn-xs" data-action="delete-attachment" data-att-id="${att.id}" data-id="${entryId}" title="${t('notebook.delete')}">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
      </button>
    </div>
  </div>`;
}

async function triggerAttachmentPicker(entryId) {
  try {
    if (window.addAttachment) {
      await window.addAttachment(entryId);
      await loadAttachments(entryId);
    }
  } catch(e) { showToast(t('error.generic'), true); }
}

async function deleteAttachment(attId, entryId) {
  if (!attId) return;
  try {
    if (window.deleteAttachment) await window.deleteAttachment(attId);
    await loadAttachments(entryId);
  } catch(e) { showToast(t('error.generic'), true); }
}

async function openAttachment(attId) {
  if (!attId) return;
  try {
    if (window.openAttachment) await window.openAttachment(attId);
  } catch(e) { showToast(t('error.generic'), true); }
}

function getFileIcon(mimeType, filename) {
  const ext = (filename || '').split('.').pop().toLowerCase();
  if (mimeType && mimeType.startsWith('image/')) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>';
  }
  if (['pdf'].includes(ext)) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/></svg>';
  }
  if (['mp3', 'wav', 'ogg', 'flac', 'm4a'].includes(ext)) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>';
  }
  if (['doc', 'docx', 'txt', 'md', 'rtf'].includes(ext)) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><line x1="8" y1="13" x2="16" y2="13"/><line x1="8" y1="17" x2="12" y2="17"/></svg>';
  }
  if (['zip', 'rar', '7z', 'tar', 'gz'].includes(ext)) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 12h1v1h-1z"/><path d="M10 15h1v1h-1z"/></svg>';
  }
  return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/></svg>';
}

function formatFileSize(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let size = bytes;
  while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
  return (i === 0 ? size : size.toFixed(1)) + ' ' + units[i];
}
