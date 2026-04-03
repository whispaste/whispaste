package main

import (
	"fmt"
	"io"
	"mime"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

// EntryAttachment represents a file attached to a history entry.
type EntryAttachment struct {
	ID        string `json:"id"`
	EntryID   string `json:"entry_id"`
	Filename  string `json:"filename"`
	Filepath  string `json:"filepath"`
	MimeType  string `json:"mime_type"`
	SizeBytes int64  `json:"size_bytes"`
	CreatedAt string `json:"created_at"`
}

// attachmentsDir returns the base directory for storing attachment files.
func attachmentsDir() (string, error) {
	dir, err := configDir()
	if err != nil {
		return "", err
	}
	aDir := filepath.Join(dir, "attachments")
	return aDir, os.MkdirAll(aDir, 0700)
}

// GetAttachments returns all attachments for a history entry.
func (h *History) GetAttachments(entryID string) []EntryAttachment {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(
		`SELECT id, entry_id, filename, filepath, mime_type, size_bytes, created_at FROM entry_attachments WHERE entry_id = ? ORDER BY created_at ASC`,
		entryID,
	)
	if err != nil {
		logError("GetAttachments: %v", err)
		return nil
	}
	defer rows.Close()

	var atts []EntryAttachment
	for rows.Next() {
		var a EntryAttachment
		if err := rows.Scan(&a.ID, &a.EntryID, &a.Filename, &a.Filepath, &a.MimeType, &a.SizeBytes, &a.CreatedAt); err != nil {
			logError("GetAttachments scan: %v", err)
			continue
		}
		atts = append(atts, a)
	}
	return atts
}

// AddAttachment copies a file into the attachments directory and records it in the database.
func (h *History) AddAttachment(entryID, srcPath string) (EntryAttachment, error) {
	if h.db == nil {
		return EntryAttachment{}, errNoDatabase
	}

	// Verify source exists
	srcInfo, err := os.Stat(srcPath)
	if err != nil {
		return EntryAttachment{}, fmt.Errorf("AddAttachment stat: %w", err)
	}

	aDir, err := attachmentsDir()
	if err != nil {
		return EntryAttachment{}, fmt.Errorf("AddAttachment dir: %w", err)
	}

	entryDir := filepath.Join(aDir, entryID)
	if err := os.MkdirAll(entryDir, 0700); err != nil {
		return EntryAttachment{}, fmt.Errorf("AddAttachment mkdir: %w", err)
	}

	id := generateID()
	origName := filepath.Base(srcPath)
	ext := filepath.Ext(origName)
	storedName := id + ext
	destPath := filepath.Join(entryDir, storedName)

	// Copy file
	if err := copyAttachmentFile(srcPath, destPath); err != nil {
		return EntryAttachment{}, fmt.Errorf("AddAttachment copy: %w", err)
	}

	mimeType := mime.TypeByExtension(ext)
	now := time.Now().UTC().Format(time.RFC3339)

	att := EntryAttachment{
		ID:        id,
		EntryID:   entryID,
		Filename:  origName,
		Filepath:  destPath,
		MimeType:  mimeType,
		SizeBytes: srcInfo.Size(),
		CreatedAt: now,
	}

	_, err = h.db.Exec(
		`INSERT INTO entry_attachments (id, entry_id, filename, filepath, mime_type, size_bytes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		att.ID, att.EntryID, att.Filename, att.Filepath, att.MimeType, att.SizeBytes, att.CreatedAt,
	)
	if err != nil {
		os.Remove(destPath) // clean up on DB failure
		return EntryAttachment{}, fmt.Errorf("AddAttachment insert: %w", err)
	}
	return att, nil
}

// DeleteAttachment removes an attachment record and its file.
func (h *History) DeleteAttachment(attachmentID string) error {
	if h.db == nil {
		return errNoDatabase
	}

	// Get filepath before deleting record
	var fp string
	if err := h.db.QueryRow(`SELECT filepath FROM entry_attachments WHERE id = ?`, attachmentID).Scan(&fp); err != nil {
		return fmt.Errorf("DeleteAttachment lookup: %w", err)
	}

	if _, err := h.db.Exec(`DELETE FROM entry_attachments WHERE id = ?`, attachmentID); err != nil {
		return fmt.Errorf("DeleteAttachment: %w", err)
	}

	// Remove file (ignore errors — DB record is authoritative)
	os.Remove(fp)
	return nil
}

// DeleteAttachmentsForEntry removes all attachments for a history entry (cascade).
func (h *History) DeleteAttachmentsForEntry(entryID string) {
	if h.db == nil {
		return
	}

	// Collect filepaths first
	rows, err := h.db.Query(`SELECT filepath FROM entry_attachments WHERE entry_id = ?`, entryID)
	if err != nil {
		logError("DeleteAttachmentsForEntry query: %v", err)
		return
	}
	var paths []string
	for rows.Next() {
		var fp string
		if err := rows.Scan(&fp); err == nil {
			paths = append(paths, fp)
		}
	}
	rows.Close()

	if _, err := h.db.Exec(`DELETE FROM entry_attachments WHERE entry_id = ?`, entryID); err != nil {
		logError("DeleteAttachmentsForEntry delete: %v", err)
	}

	// Remove files
	for _, fp := range paths {
		os.Remove(fp)
	}

	// Try to remove the entry's attachment directory (only succeeds if empty)
	aDir, err := attachmentsDir()
	if err == nil {
		os.Remove(filepath.Join(aDir, entryID))
	}
}

// OpenAttachment opens an attachment file with the OS default application.
func (h *History) OpenAttachment(attachmentID string) error {
	if h.db == nil {
		return errNoDatabase
	}

	var fp string
	if err := h.db.QueryRow(`SELECT filepath FROM entry_attachments WHERE id = ?`, attachmentID).Scan(&fp); err != nil {
		return fmt.Errorf("OpenAttachment lookup: %w", err)
	}

	if _, err := os.Stat(fp); err != nil {
		return fmt.Errorf("OpenAttachment: file not found: %w", err)
	}

	return openWithOS(fp)
}

// AttachmentCount returns the number of attachments for a history entry.
func (h *History) AttachmentCount(entryID string) int {
	if h.db == nil {
		return 0
	}
	var count int
	if err := h.db.QueryRow(`SELECT COUNT(*) FROM entry_attachments WHERE entry_id = ?`, entryID).Scan(&count); err != nil {
		return 0
	}
	return count
}

// copyAttachmentFile copies a file from src to dst.
func copyAttachmentFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Close()
}

// openWithOS opens a file with the OS default application.
func openWithOS(path string) error {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", path).Start()
	case "darwin":
		return exec.Command("open", path).Start()
	default:
		return exec.Command("xdg-open", path).Start()
	}
}
