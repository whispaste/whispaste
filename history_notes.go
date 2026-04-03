package main

import (
	"errors"
	"fmt"
	"time"
)

// EntryNote represents a user note attached to a history entry.
type EntryNote struct {
	ID        string `json:"id"`
	EntryID   string `json:"entry_id"`
	Content   string `json:"content"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

var errNoDatabase = errors.New("database not initialized")

// GetNotes returns all notes for a history entry, ordered by creation time.
func (h *History) GetNotes(entryID string) []EntryNote {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(
		`SELECT id, entry_id, content, created_at, updated_at FROM entry_notes WHERE entry_id = ? ORDER BY created_at ASC`,
		entryID,
	)
	if err != nil {
		logError("GetNotes: %v", err)
		return nil
	}
	defer rows.Close()

	var notes []EntryNote
	for rows.Next() {
		var n EntryNote
		if err := rows.Scan(&n.ID, &n.EntryID, &n.Content, &n.CreatedAt, &n.UpdatedAt); err != nil {
			logError("GetNotes scan: %v", err)
			continue
		}
		notes = append(notes, n)
	}
	return notes
}

// AddNote creates a new note for a history entry.
func (h *History) AddNote(entryID, content string) (EntryNote, error) {
	if h.db == nil {
		return EntryNote{}, errNoDatabase
	}
	now := time.Now().UTC().Format(time.RFC3339)
	note := EntryNote{
		ID:        generateID(),
		EntryID:   entryID,
		Content:   content,
		CreatedAt: now,
		UpdatedAt: now,
	}
	_, err := h.db.Exec(
		`INSERT INTO entry_notes (id, entry_id, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`,
		note.ID, note.EntryID, note.Content, note.CreatedAt, note.UpdatedAt,
	)
	if err != nil {
		return EntryNote{}, fmt.Errorf("AddNote: %w", err)
	}
	return note, nil
}

// UpdateNote updates the content of an existing note.
func (h *History) UpdateNote(noteID, content string) error {
	if h.db == nil {
		return errNoDatabase
	}
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := h.db.Exec(
		`UPDATE entry_notes SET content = ?, updated_at = ? WHERE id = ?`,
		content, now, noteID,
	)
	if err != nil {
		return fmt.Errorf("UpdateNote: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("UpdateNote: note %s not found", noteID)
	}
	return nil
}

// DeleteNote removes a note by ID.
func (h *History) DeleteNote(noteID string) error {
	if h.db == nil {
		return errNoDatabase
	}
	_, err := h.db.Exec(`DELETE FROM entry_notes WHERE id = ?`, noteID)
	if err != nil {
		return fmt.Errorf("DeleteNote: %w", err)
	}
	return nil
}

// DeleteNotesForEntry removes all notes for a history entry (cascade).
func (h *History) DeleteNotesForEntry(entryID string) {
	if h.db == nil {
		return
	}
	if _, err := h.db.Exec(`DELETE FROM entry_notes WHERE entry_id = ?`, entryID); err != nil {
		logError("DeleteNotesForEntry: %v", err)
	}
}

// NoteCount returns the number of notes for a history entry.
func (h *History) NoteCount(entryID string) int {
	if h.db == nil {
		return 0
	}
	var count int
	if err := h.db.QueryRow(`SELECT COUNT(*) FROM entry_notes WHERE entry_id = ?`, entryID).Scan(&count); err != nil {
		return 0
	}
	return count
}
