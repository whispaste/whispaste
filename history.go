package main

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/whispaste/whispaste/internal/audiocache"
)

const defaultMaxHistory = 500

// HistoryEntry represents a single transcription or note.
type HistoryEntry struct {
	ID                 string   `json:"id"`
	Text               string   `json:"text"`
	Title              string   `json:"title,omitempty"`
	Timestamp          string   `json:"timestamp"`
	Duration           float64  `json:"duration_sec"`
	ProcessingDuration float64  `json:"processing_duration_sec,omitempty"`
	Language           string   `json:"language"`
	Category           string   `json:"category,omitempty"` // deprecated: kept for backward compat with old JSON
	Tags               []string `json:"tags,omitempty"`
	Pinned             bool     `json:"pinned,omitempty"`
	Source             string   `json:"source,omitempty"`
	Model              string   `json:"model,omitempty"`
	IsLocal            bool     `json:"is_local,omitempty"`
	CostUSD            float64  `json:"cost_usd,omitempty"`
	ProjectID          string   `json:"project_id"`
	ProjectName        string   `json:"project_name,omitempty"` // computed, not stored
	Archived           bool     `json:"archived,omitempty"`
}

// Project represents a named project that groups transcriptions.
type Project struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
	Count     int    `json:"count"` // number of entries in this project (computed)
}

// analyticsCache stores a computed analytics result with an expiry.
type analyticsCache struct {
	data       map[string]interface{}
	validUntil time.Time
}

// History manages transcription history backed by SQLite.
type History struct {
	db            *sql.DB
	realDb        *sql.DB                // saved real DB when demo mode is active
	demoMode      bool                   // true when demo mode is active
	mu            sync.Mutex
	cache         map[int]*analyticsCache // keyed by periodDays
	lastAuditTime time.Time
}

// invalidateCache clears the analytics cache under lock.
func (h *History) invalidateCache() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.cache = nil
}

func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%x", time.Now().UnixNano())
	}
	return fmt.Sprintf("%x", b)
}

func autoTitle(text string) string {
	t := strings.ReplaceAll(text, "\n", " ")
	t = strings.TrimSpace(t)
	if len([]rune(t)) > 60 {
		return string([]rune(t)[:60]) + "…"
	}
	return t
}

// LoadHistory initialises the SQLite-backed history store.
// On first run, migrates data from history.json if present.
func LoadHistory() *History {
	h := &History{}
	db, err := initHistoryDB()
	if err != nil {
		logError("Failed to open history DB: %v", err)
		return h
	}
	h.db = db
	return h
}

// WhisperCostPerMinute is the current cost of OpenAI Whisper API per audio minute (USD).
const WhisperCostPerMinute = 0.006

// Add appends a new entry and prunes to the limit.
func (h *History) Add(text string, durationSec float64, language string) {
	h.AddWithModel(text, durationSec, 0, language, "", false, "")
}

// AddWithModel appends a new entry with model tracking and prunes to the limit.
// If projectID is non-empty, the entry is assigned to that project.
func (h *History) AddWithModel(text string, durationSec float64, processingDurationSec float64, language, model string, isLocal bool, projectID string) string {
	var cost float64
	if !isLocal && durationSec > 0 {
		cost = (durationSec / 60.0) * WhisperCostPerMinute
	}
	entry := HistoryEntry{
		ID:                 generateID(),
		Text:               text,
		Title:              autoTitle(text),
		Timestamp:          time.Now().Format(time.RFC3339),
		Duration:           durationSec,
		ProcessingDuration: processingDurationSec,
		Language:           language,
		Source:             "dictation",
		Model:              model,
		IsLocal:            isLocal,
		CostUSD:            cost,
		ProjectID:          projectID,
	}

	h.invalidateCache()

	if h.db == nil {
		return entry.ID
	}
	h.insertEntry(entry)
	h.pruneToLimit(defaultMaxHistory)
	return entry.ID
}

// AddPendingEntry creates a history entry for audio that hasn't been
// transcribed yet (cancelled or failed). Tagged with system tag "pending".
// Returns the entry ID for audio caching.
func (h *History) AddPendingEntry(durationSec float64, language, model string, isLocal bool, reason string) string {
	title := "⏳ " + reason
	entry := HistoryEntry{
		ID:        generateID(),
		Text:      "",
		Title:     title,
		Timestamp: time.Now().Format(time.RFC3339),
		Duration:  durationSec,
		Language:  language,
		Source:    "dictation",
		Model:     model,
		IsLocal:   isLocal,
		Tags:      []string{"pending"},
	}

	h.invalidateCache()

	if h.db == nil {
		return entry.ID
	}
	h.insertEntry(entry)
	h.pruneToLimit(defaultMaxHistory)
	return entry.ID
}

// insertEntry inserts a single entry into the database.
func (h *History) insertEntry(e HistoryEntry) {
	pinned := 0
	if e.Pinned {
		pinned = 1
	}
	isLocal := 0
	if e.IsLocal {
		isLocal = 1
	}
	_, err := execWithFTSRepair(h.db, `INSERT INTO history_entries
		(id, text, title, timestamp, duration_sec, processing_duration_sec,
		 language, tags, pinned, source, model, is_local, cost_usd, project_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.Text, e.Title, e.Timestamp, e.Duration, e.ProcessingDuration,
		e.Language, marshalTags(e.Tags), pinned, e.Source, e.Model, isLocal, e.CostUSD, e.ProjectID)
	if err != nil {
		logError("Insert history entry: %v", err)
	}
}

// pruneToLimit removes oldest non-pinned entries if total count exceeds limit.
func (h *History) pruneToLimit(limit int) {
	if h.db == nil {
		return
	}
	// Delete oldest non-pinned, non-archived entries beyond the limit
	// Count only non-archived entries (pinned still count against limit but aren't deletable)
	_, err := execWithFTSRepair(h.db, `DELETE FROM history_entries WHERE id IN (
		SELECT id FROM history_entries WHERE pinned = 0 AND archived = 0
		ORDER BY timestamp ASC
		LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries WHERE archived = 0) - ?)
	)`, limit)
	if err != nil {
		logError("Prune history: %v", err)
	}
}

// Recent returns the last n entries (newest first).
func (h *History) Recent(n int) []HistoryEntry {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(`SELECT `+allColumns+` FROM history_entries
		WHERE archived = 0
		ORDER BY timestamp DESC, rowid DESC LIMIT ?`, n)
	if err != nil {
		logError("Recent query: %v", err)
		return nil
	}
	defer rows.Close()
	entries := scanEntries(rows)
	h.fillProjectNames(entries)
	return entries
}

// All returns all non-archived entries (newest first).
func (h *History) All() []HistoryEntry {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(`SELECT ` + allColumns + ` FROM history_entries WHERE archived = 0 ORDER BY timestamp DESC, rowid DESC`)
	if err != nil {
		logError("All query: %v", err)
		return nil
	}
	defer rows.Close()
	entries := scanEntries(rows)
	h.fillProjectNames(entries)
	return entries
}

// AllArchived returns only archived entries (newest first).
func (h *History) AllArchived() []HistoryEntry {
	if h.db == nil {
		return []HistoryEntry{}
	}
	rows, err := h.db.Query(`SELECT ` + allColumns + ` FROM history_entries WHERE archived = 1 ORDER BY timestamp DESC, rowid DESC`)
	if err != nil {
		logError("AllArchived query: %v", err)
		return []HistoryEntry{}
	}
	defer rows.Close()
	entries := scanEntries(rows)
	if entries == nil {
		return []HistoryEntry{}
	}
	h.fillProjectNames(entries)
	return entries
}

// ArchivedCount returns the number of archived entries.
func (h *History) ArchivedCount() int {
	if h.db == nil {
		return 0
	}
	var count int
	err := h.db.QueryRow("SELECT COUNT(*) FROM history_entries WHERE archived = 1").Scan(&count)
	if err != nil {
		logError("ArchivedCount: %v", err)
		return 0
	}
	return count
}

// scanEntries reads all rows into a slice.
func scanEntries(rows *sql.Rows) []HistoryEntry {
	var entries []HistoryEntry
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			logError("Scan entry: %v", err)
			continue
		}
		entries = append(entries, e)
	}
	return entries
}

// Delete removes an entry by ID and its cached audio file.
func (h *History) Delete(id string) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	res, err := execWithFTSRepair(h.db, "DELETE FROM history_entries WHERE id = ?", id)
	if err != nil {
		logError("Delete entry: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	if n > 0 {
		audiocache.Delete(id)
	}
	return n > 0
}

// TogglePin toggles the pinned state of an entry by ID.
func (h *History) TogglePin(id string) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	res, err := execWithFTSRepair(h.db, `UPDATE history_entries SET pinned = CASE WHEN pinned = 0 THEN 1 ELSE 0 END WHERE id = ?`, id)
	if err != nil {
		logError("Toggle pin: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// ToggleArchive toggles the archived state of an entry by ID.
func (h *History) ToggleArchive(id string) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	res, err := execWithFTSRepair(h.db, `UPDATE history_entries SET archived = CASE WHEN archived = 0 THEN 1 ELSE 0 END WHERE id = ?`, id)
	if err != nil {
		logError("Toggle archive: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

func (h *History) UpdateEntry(id, title string, tags []string) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	var res sql.Result
	var err error
	tagsJSON := marshalTags(tags)
	logDebug("UpdateEntry id=%s title=%q tagCount=%d tags=%s", id, title, len(tags), tagsJSON)
	if title != "" {
		res, err = execWithFTSRepair(h.db, "UPDATE history_entries SET title = ?, tags = ? WHERE id = ?", title, tagsJSON, id)
	} else {
		res, err = execWithFTSRepair(h.db, "UPDATE history_entries SET tags = ? WHERE id = ?", tagsJSON, id)
	}
	if err != nil {
		logError("Update entry id=%s: %v", id, err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// UpdateText updates the text content (and auto-title) for an entry by ID.
func (h *History) UpdateText(id, newText string) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	newTitle := autoTitle(newText)
	res, err := execWithFTSRepair(h.db, "UPDATE history_entries SET text = ?, title = ? WHERE id = ?", newText, newTitle, id)
	if err != nil {
		logError("Update text: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// CompletePendingEntry updates a pending entry with transcription text,
// auto-generated title, processing duration, cost, and removes the "pending" tag.
func (h *History) CompletePendingEntry(id, text string, processingDurationSec float64, model string, isLocal bool) bool {
	if h.db == nil {
		return false
	}
	h.invalidateCache()

	title := autoTitle(text)
	var cost float64
	// look up duration for cost calc
	var durationSec float64
	var tagsJSON string
	err := h.db.QueryRow("SELECT duration_sec, tags FROM history_entries WHERE id = ?", id).Scan(&durationSec, &tagsJSON)
	if err != nil {
		logError("CompletePendingEntry lookup: %v", err)
		return false
	}
	if !isLocal && durationSec > 0 {
		cost = (durationSec / 60.0) * WhisperCostPerMinute
	}
	// remove "pending" tag
	tags := unmarshalTags(tagsJSON)
	filtered := make([]string, 0, len(tags))
	for _, t := range tags {
		if t != "pending" {
			filtered = append(filtered, t)
		}
	}
	res, err := execWithFTSRepair(h.db,
		`UPDATE history_entries SET text = ?, title = ?, processing_duration_sec = ?,
		 model = ?, is_local = ?, cost_usd = ?, tags = ? WHERE id = ?`,
		text, title, processingDurationSec, model, boolToInt(isLocal), cost,
		marshalTags(filtered), id)
	if err != nil {
		logError("CompletePendingEntry update: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// UpdatePendingReason updates the title/reason of a pending entry (e.g. from
// "transcribing" to "transcription_failed" when transcription fails).
func (h *History) UpdatePendingReason(id, reason string) {
	if h.db == nil || id == "" {
		return
	}
	title := "⏳ " + reason
	_, err := execWithFTSRepair(h.db,
		`UPDATE history_entries SET title = ? WHERE id = ?`, title, id)
	if err != nil {
		logWarn("UpdatePendingReason: %v", err)
	}
}

// CleanupStalePending removes pending entries older than maxAge that have no
// cached audio (true crash orphans). Entries with audio are kept for retry.
func (h *History) CleanupStalePending(maxAge time.Duration) int {
	if h.db == nil {
		return 0
	}
	cutoff := time.Now().Add(-maxAge).Format(time.RFC3339)
	rows, err := h.db.Query(
		`SELECT id FROM history_entries WHERE tags LIKE '%"pending"%' AND text = '' AND timestamp < ?`, cutoff)
	if err != nil {
		logWarn("CleanupStalePending query: %v", err)
		return 0
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err == nil {
			if !audiocache.Has(id) {
				ids = append(ids, id)
			}
		}
	}
	if len(ids) == 0 {
		return 0
	}

	h.invalidateCache()
	for _, id := range ids {
		h.Delete(id)
	}
	logInfo("Cleaned up %d stale pending entries (older than %v, no audio)", len(ids), maxAge)
	return len(ids)
}

// Merge combines multiple entries into one. The newest entry's metadata is used as the base.
// Returns the ID of the merged entry, or empty string on error.
func (h *History) Merge(ids []string) string {
	if h.db == nil || len(ids) < 2 {
		return ""
	}

	h.invalidateCache()

	// Build placeholder query
	placeholders := make([]string, len(ids))
	args := make([]interface{}, len(ids))
	for i, id := range ids {
		placeholders[i] = "?"
		args[i] = id
	}

	tx, err := h.db.Begin()
	if err != nil {
		logError("Merge transaction: %v", err)
		return ""
	}
	defer tx.Rollback()

	query := `SELECT ` + allColumns + ` FROM history_entries WHERE id IN (` + strings.Join(placeholders, ",") + `) ORDER BY timestamp`
	rows, err := tx.Query(query, args...)
	if err != nil {
		logError("Merge query: %v", err)
		return ""
	}
	defer rows.Close()
	matches := scanEntries(rows)
	rows.Close() // close before using tx for writes

	if len(matches) < 2 {
		return ""
	}

	var texts []string
	var totalDuration float64
	newestTime := ""
	for _, m := range matches {
		texts = append(texts, strings.TrimSpace(m.Text))
		totalDuration += m.Duration
		if m.Timestamp > newestTime {
			newestTime = m.Timestamp
		}
	}

	mergedText := strings.Join(texts, "\n\n")

	tagSet := map[string]struct{}{"merged": {}}
	for _, m := range matches {
		for _, t := range m.Tags {
			tagSet[t] = struct{}{}
		}
	}
	var mergedTags []string
	for t := range tagSet {
		mergedTags = append(mergedTags, t)
	}

	merged := HistoryEntry{
		ID:        generateID(),
		Text:      mergedText,
		Title:     autoTitle(mergedText),
		Timestamp: newestTime,
		Duration:  totalDuration,
		Language:  matches[0].Language,
		Source:    "merged",
		Tags:      mergedTags,
		ProjectID: matches[0].ProjectID,
	}

	// Delete originals, insert merged
	delQuery := "DELETE FROM history_entries WHERE id IN (" + strings.Join(placeholders, ",") + ")"
	if _, err := tx.Exec(delQuery, args...); err != nil {
		logError("Merge delete: %v", err)
		return ""
	}

	pinned := 0
	isLocal := 0
	if _, err := tx.Exec(`INSERT INTO history_entries
		(id, text, title, timestamp, duration_sec, processing_duration_sec,
		 language, tags, pinned, source, model, is_local, cost_usd, project_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		merged.ID, merged.Text, merged.Title, merged.Timestamp,
		merged.Duration, merged.ProcessingDuration, merged.Language,
		marshalTags(merged.Tags), pinned, merged.Source, merged.Model,
		isLocal, merged.CostUSD, merged.ProjectID); err != nil {
		logError("Merge insert: %v", err)
		return ""
	}

	if err := tx.Commit(); err != nil {
		logError("Merge commit: %v", err)
		return ""
	}

	// Copy audio in same order as merged text (timestamp-sorted matches)
	orderedIDs := make([]string, len(matches))
	for i, m := range matches {
		orderedIDs[i] = m.ID
	}
	copied := audiocache.CopyForMerge(orderedIDs, merged.ID)
	if copied > 0 {
		logInfo("Merged %d audio files for entry %s", copied, merged.ID)
	}
	// Only delete originals if all audio was successfully copied (prevent data loss)
	expected := 0
	for _, id := range orderedIDs {
		expected += audiocache.AudioCount(id)
	}
	if copied >= expected {
		for _, id := range orderedIDs {
			audiocache.Delete(id)
		}
	} else {
		logWarn("Merge audio: copied %d of %d files, keeping originals", copied, expected)
	}

	return merged.ID
}

// AllEntryIDs returns a set of all entry IDs in the database.
func (h *History) AllEntryIDs() map[string]bool {
	ids := make(map[string]bool)
	if h.db == nil {
		return ids
	}
	rows, err := h.db.Query("SELECT id FROM history_entries")
	if err != nil {
		logError("AllEntryIDs: %v", err)
		return ids
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids[id] = true
		}
	}
	return ids
}

// GetByID returns a copy of the entry with the given ID, or nil if not found.
func (h *History) GetByID(id string) *HistoryEntry {
	if h.db == nil {
		return nil
	}
	row := h.db.QueryRow(`SELECT `+allColumns+` FROM history_entries WHERE id = ?`, id)
	e, err := scanEntry(row)
	if err != nil {
		return nil
	}
	if e.ProjectID != "" {
		entries := []HistoryEntry{e}
		h.fillProjectNames(entries)
		e = entries[0]
	}
	return &e
}

// AddSmart creates a new entry with the given text, language, and tags.
func (h *History) AddSmart(text, language string, tags []string) {
	h.invalidateCache()

	if h.db == nil {
		return
	}
	entry := HistoryEntry{
		ID:        generateID(),
		Text:      text,
		Title:     autoTitle(text),
		Timestamp: time.Now().Format(time.RFC3339),
		Language:  language,
		Source:    "smart",
		Tags:      tags,
	}
	h.insertEntry(entry)
	h.pruneToLimit(defaultMaxHistory)
}

// Cleanup removes old entries based on config settings.
// When includePinned is false, pinned entries are preserved.
// Archived entries are always preserved regardless of settings.
// Returns the number of entries removed. Also cleans up orphaned audio files.
func (h *History) Cleanup(maxEntries, maxAgeDays int, includePinned bool) int {
	if h.db == nil {
		return 0
	}

	// Collect IDs that will be deleted (for audio cleanup)
	var deletedIDs []string

	h.invalidateCache()

	// Archived entries are always excluded from cleanup
	protectFilter := " AND archived = 0"
	if !includePinned {
		protectFilter += " AND pinned = 0"
	}

	var totalRemoved int64

	// Remove by age
	if maxAgeDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -maxAgeDays).Format(time.RFC3339)
		// Collect IDs before deletion
		rows, err := h.db.Query("SELECT id FROM history_entries WHERE timestamp < ?"+protectFilter, cutoff)
		if err == nil {
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					deletedIDs = append(deletedIDs, id)
				}
			}
			rows.Close()
		}
		res, err := execWithFTSRepair(h.db, "DELETE FROM history_entries WHERE timestamp < ?"+protectFilter, cutoff)
		if err != nil {
			logError("Cleanup by age: %v", err)
		} else {
			n, _ := res.RowsAffected()
			totalRemoved += n
		}
	}

	// Remove by count (keep newest)
	if maxEntries > 0 {
		whereClause := "archived = 0"
		if !includePinned {
			whereClause += " AND pinned = 0"
		}
		// Collect IDs before deletion
		rows, err := h.db.Query(`SELECT id FROM history_entries WHERE id IN (
			SELECT id FROM history_entries WHERE `+whereClause+`
			ORDER BY timestamp ASC
			LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries WHERE archived = 0) - ?)
		)`, maxEntries)
		if err == nil {
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					deletedIDs = append(deletedIDs, id)
				}
			}
			rows.Close()
		}
		res, err := execWithFTSRepair(h.db, `DELETE FROM history_entries WHERE id IN (
			SELECT id FROM history_entries WHERE `+whereClause+`
			ORDER BY timestamp ASC
			LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries WHERE archived = 0) - ?)
		)`, maxEntries)
		if err != nil {
			logError("Cleanup by count: %v", err)
		} else {
			n, _ := res.RowsAffected()
			totalRemoved += n
		}
	}

	// Delete audio files for removed entries
	for _, id := range deletedIDs {
		audiocache.Delete(id)
	}

	// Clean up orphaned audio files (from crashes, manual DB edits, etc.)
	validIDs := h.AllEntryIDs()
	audiocache.CleanupOrphaned(validIDs)

	return int(totalRemoved)
}

// DuplicateEntry creates a copy of an entry by ID.
func (h *History) DuplicateEntry(id string) bool {
	e := h.GetByID(id)
	if e == nil {
		return false
	}

	h.invalidateCache()

	dup := *e
	dup.ID = generateID()
	dup.Timestamp = time.Now().Format(time.RFC3339)
	dup.Title = e.Title + " (Copy)"
	dup.Pinned = false
	if len(e.Tags) > 0 {
		dup.Tags = make([]string, len(e.Tags))
		copy(dup.Tags, e.Tags)
	}
	dup.Tags = append(dup.Tags, "duplicated")
	h.insertEntry(dup)
	return true
}

// Close closes the underlying database connection.
func (h *History) Close() {
	if h.demoMode && h.realDb != nil {
		h.db.Close()
		h.db = h.realDb
		h.realDb = nil
		h.demoMode = false
	}
	if h.db != nil {
		h.db.Close()
	}
}
