package main

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"strings"
	"sync"
	"time"
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
}

// analyticsCache stores a computed analytics result with an expiry.
type analyticsCache struct {
	data       map[string]interface{}
	validUntil time.Time
}

// History manages transcription history backed by SQLite.
type History struct {
	db    *sql.DB
	mu    sync.Mutex
	cache map[int]*analyticsCache // keyed by periodDays
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
	h.AddWithModel(text, durationSec, 0, language, "", false)
}

// AddWithModel appends a new entry with model tracking and prunes to the limit.
func (h *History) AddWithModel(text string, durationSec float64, processingDurationSec float64, language, model string, isLocal bool) string {
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
	}

	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

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
		 language, tags, pinned, source, model, is_local, cost_usd)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.Text, e.Title, e.Timestamp, e.Duration, e.ProcessingDuration,
		e.Language, marshalTags(e.Tags), pinned, e.Source, e.Model, isLocal, e.CostUSD)
	if err != nil {
		logError("Insert history entry: %v", err)
	}
}

// pruneToLimit removes oldest non-pinned entries if total count exceeds limit.
func (h *History) pruneToLimit(limit int) {
	if h.db == nil {
		return
	}
	// Delete oldest non-pinned entries beyond the limit
	_, err := execWithFTSRepair(h.db, `DELETE FROM history_entries WHERE id IN (
		SELECT id FROM history_entries WHERE pinned = 0
		ORDER BY timestamp ASC
		LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries) - ?)
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
		ORDER BY timestamp DESC LIMIT ?`, n)
	if err != nil {
		logError("Recent query: %v", err)
		return nil
	}
	defer rows.Close()
	return scanEntries(rows)
}

// All returns all entries (newest first).
func (h *History) All() []HistoryEntry {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(`SELECT ` + allColumns + ` FROM history_entries ORDER BY timestamp DESC`)
	if err != nil {
		logError("All query: %v", err)
		return nil
	}
	defer rows.Close()
	return scanEntries(rows)
}

// Search returns entries matching the FTS5 query, ordered by newest first.
// The query uses FTS5 syntax (e.g. "hello world", hello OR world, hello NOT world).
// Returns nil on empty query or error.
func (h *History) Search(query string) []HistoryEntry {
	if h.db == nil {
		return nil
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil
	}
	rows, err := h.db.Query(`SELECT `+allColumns+` FROM history_entries
		WHERE rowid IN (
			SELECT rowid FROM history_fts WHERE history_fts MATCH ?
			ORDER BY rank
		) ORDER BY timestamp DESC`, query)
	if err != nil {
		logError("FTS search query: %v", err)
		return nil
	}
	defer rows.Close()
	return scanEntries(rows)
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
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	res, err := execWithFTSRepair(h.db, "DELETE FROM history_entries WHERE id = ?", id)
	if err != nil {
		logError("Delete entry: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	if n > 0 {
		DeleteAudio(id)
	}
	return n > 0
}

// TogglePin toggles the pinned state of an entry by ID.
func (h *History) TogglePin(id string) bool {
	if h.db == nil {
		return false
	}
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	res, err := execWithFTSRepair(h.db, `UPDATE history_entries SET pinned = CASE WHEN pinned = 0 THEN 1 ELSE 0 END WHERE id = ?`, id)
	if err != nil {
		logError("Toggle pin: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// UpdateEntry updates title and/or tags for an entry by ID.
func (h *History) UpdateEntry(id, title string, tags []string) bool {
	if h.db == nil {
		return false
	}
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

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
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	newTitle := autoTitle(newText)
	res, err := execWithFTSRepair(h.db, "UPDATE history_entries SET text = ?, title = ? WHERE id = ?", newText, newTitle, id)
	if err != nil {
		logError("Update text: %v", err)
		return false
	}
	n, _ := res.RowsAffected()
	return n > 0
}

// GetAnalytics computes usage statistics for a given time period.
// Results are cached for 2 seconds to avoid recomputation on rapid refreshes.
// Reads from the daily_stats aggregation table instead of scanning history_entries.
func (h *History) GetAnalytics(periodDays int) map[string]interface{} {
	if h.db == nil {
		return map[string]interface{}{}
	}

	h.mu.Lock()
	if h.cache != nil {
		if c, ok := h.cache[periodDays]; ok && time.Now().Before(c.validUntil) {
			h.mu.Unlock()
			return c.data
		}
	}
	h.mu.Unlock()

	var rows *sql.Rows
	var err error
	if periodDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -periodDays).Format("2006-01-02")
		rows, err = h.db.Query(`SELECT date, model, is_local, count, total_duration_sec, total_processing_sec, total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m FROM daily_stats WHERE date >= ?`, cutoff)
	} else {
		rows, err = h.db.Query(`SELECT date, model, is_local, count, total_duration_sec, total_processing_sec, total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m FROM daily_stats`)
	}
	if err != nil {
		logError("Analytics query: %v", err)
		return map[string]interface{}{}
	}
	defer rows.Close()

	var totalEntries, localEntries, apiEntries int
	var totalDuration, totalCost, localDuration float64
	var totalProcessingDuration float64
	dailyCounts := map[string]int{}
	modelCounts := map[string]int{}
	durationBuckets := map[string]int{"<15s": 0, "15-30s": 0, "30-60s": 0, "1-3m": 0, ">3m": 0}

	for rows.Next() {
		var date, model string
		var isLocal, count, durU15, dur1530, dur3060, dur13m, durO3m int
		var durSec, procSec, words float64
		var costUSD float64
		if err := rows.Scan(&date, &model, &isLocal, &count, &durSec, &procSec, &words, &costUSD, &durU15, &dur1530, &dur3060, &dur13m, &durO3m); err != nil {
			logWarn("Analytics row scan: %v", err)
			continue
		}

		totalEntries += count
		totalDuration += durSec
		totalCost += costUSD
		totalProcessingDuration += procSec

		if isLocal == 1 {
			localEntries += count
			localDuration += durSec
		} else {
			apiEntries += count
		}

		dailyCounts[date] += count

		if model == "" {
			model = "unknown"
		}
		modelCounts[model] += count

		durationBuckets["<15s"] += durU15
		durationBuckets["15-30s"] += dur1530
		durationBuckets["30-60s"] += dur3060
		durationBuckets["1-3m"] += dur13m
		durationBuckets[">3m"] += durO3m
	}
	if err := rows.Err(); err != nil {
		logWarn("Analytics rows iteration: %v", err)
	}

	savings := (localDuration / 60.0) * WhisperCostPerMinute
	avgDuration := safeDiv(totalDuration, float64(totalEntries))

	result := map[string]interface{}{
		"totalEntries":          totalEntries,
		"localEntries":          localEntries,
		"apiEntries":            apiEntries,
		"totalDuration":         totalDuration,
		"totalCost":             totalCost,
		"savings":               savings,
		"dailyCounts":           dailyCounts,
		"modelCounts":           modelCounts,
		"durationBuckets":       durationBuckets,
		"avgDuration":           avgDuration,
		"minDuration":           avgDuration, // approximation from aggregates
		"maxDuration":           avgDuration, // approximation from aggregates
		"avgProcessingDuration": safeDiv(totalProcessingDuration, float64(totalEntries)),
		"totalProcessingTime":   totalProcessingDuration,
	}

	h.mu.Lock()
	if h.cache == nil {
		h.cache = make(map[int]*analyticsCache)
	}
	h.cache[periodDays] = &analyticsCache{data: result, validUntil: time.Now().Add(2 * time.Second)}
	h.mu.Unlock()

	return result
}

func safeDiv(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}

// Tags returns all unique tag names used across entries.
func (h *History) Tags() []string {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query("SELECT tags FROM history_entries WHERE tags != '[]' AND tags != ''")
	if err != nil {
		logError("Tags query: %v", err)
		return nil
	}
	defer rows.Close()

	seen := map[string]bool{}
	var result []string
	for rows.Next() {
		var tagsJSON string
		if err := rows.Scan(&tagsJSON); err != nil {
			continue
		}
		for _, tag := range unmarshalTags(tagsJSON) {
			if tag != "" && !seen[tag] {
				seen[tag] = true
				result = append(result, tag)
			}
		}
	}
	return result
}

// RenameTag renames a tag across all entries that have it.
func (h *History) RenameTag(oldName, newName string) int {
	if h.db == nil {
		return 0
	}
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	// Escape LIKE wildcards in tag name
	escaped := strings.NewReplacer("%", "\\%", "_", "\\_").Replace(oldName)
	pattern := `%"` + escaped + `"%`

	tx, err := h.db.Begin()
	if err != nil {
		logError("RenameTag begin tx: %v", err)
		return 0
	}
	defer tx.Rollback()

	rows, err := tx.Query("SELECT id, tags FROM history_entries WHERE tags LIKE ? ESCAPE '\\'", pattern)
	if err != nil {
		logError("RenameTag query: %v", err)
		return 0
	}

	type idTags struct {
		id   string
		tags []string
	}
	var updates []idTags
	for rows.Next() {
		var id, tagsJSON string
		if err := rows.Scan(&id, &tagsJSON); err != nil {
			continue
		}
		tags := unmarshalTags(tagsJSON)
		changed := false
		for j, tag := range tags {
			if tag == oldName {
				tags[j] = newName
				changed = true
				break
			}
		}
		if changed {
			updates = append(updates, idTags{id, tags})
		}
	}
	rows.Close()

	count := 0
	for _, u := range updates {
		if _, err := tx.Exec("UPDATE history_entries SET tags = ? WHERE id = ?", marshalTags(u.tags), u.id); err != nil {
			logError("RenameTag update %s: %v", u.id, err)
			return 0
		}
		count++
	}

	if err := tx.Commit(); err != nil {
		logError("RenameTag commit: %v", err)
		return 0
	}
	return count
}

// DeleteTag removes a tag from all entries that have it.
func (h *History) DeleteTag(tagName string) int {
	if h.db == nil {
		return 0
	}
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	escaped := strings.NewReplacer("%", "\\%", "_", "\\_").Replace(tagName)
	pattern := `%"` + escaped + `"%`

	tx, err := h.db.Begin()
	if err != nil {
		logError("DeleteTag begin tx: %v", err)
		return 0
	}
	defer tx.Rollback()

	rows, err := tx.Query("SELECT id, tags FROM history_entries WHERE tags LIKE ? ESCAPE '\\'", pattern)
	if err != nil {
		logError("DeleteTag query: %v", err)
		return 0
	}

	type idTags struct {
		id   string
		tags []string
	}
	var updates []idTags
	for rows.Next() {
		var id, tagsJSON string
		if err := rows.Scan(&id, &tagsJSON); err != nil {
			continue
		}
		tags := unmarshalTags(tagsJSON)
		filtered := make([]string, 0, len(tags))
		for _, tag := range tags {
			if tag != tagName {
				filtered = append(filtered, tag)
			}
		}
		if len(filtered) < len(tags) {
			updates = append(updates, idTags{id, filtered})
		}
	}
	rows.Close()

	count := 0
	for _, u := range updates {
		if _, err := tx.Exec("UPDATE history_entries SET tags = ? WHERE id = ?", marshalTags(u.tags), u.id); err != nil {
			logError("DeleteTag update %s: %v", u.id, err)
			return 0
		}
		count++
	}

	if err := tx.Commit(); err != nil {
		logError("DeleteTag commit: %v", err)
		return 0
	}
	return count
}

// Merge combines multiple entries into one. The newest entry's metadata is used as the base.
// Returns the ID of the merged entry, or empty string on error.
func (h *History) Merge(ids []string) string {
	if h.db == nil || len(ids) < 2 {
		return ""
	}

	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

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
		 language, tags, pinned, source, model, is_local, cost_usd)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		merged.ID, merged.Text, merged.Title, merged.Timestamp,
		merged.Duration, merged.ProcessingDuration, merged.Language,
		marshalTags(merged.Tags), pinned, merged.Source, merged.Model,
		isLocal, merged.CostUSD); err != nil {
		logError("Merge insert: %v", err)
		return ""
	}

	if err := tx.Commit(); err != nil {
		logError("Merge commit: %v", err)
		return ""
	}
	return merged.ID
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
	return &e
}

// AddSmart creates a new entry with the given text, language, and tags.
func (h *History) AddSmart(text, language string, tags []string) {
	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

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
// Returns the number of entries removed. Also cleans up orphaned audio files.
func (h *History) Cleanup(maxEntries, maxAgeDays int, includePinned bool) int {
	if h.db == nil {
		return 0
	}

	// Collect IDs that will be deleted (for audio cleanup)
	var deletedIDs []string

	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

	pinnedFilter := " AND pinned = 0"
	if includePinned {
		pinnedFilter = ""
	}

	var totalRemoved int64

	// Remove by age
	if maxAgeDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -maxAgeDays).Format(time.RFC3339)
		// Collect IDs before deletion
		rows, err := h.db.Query("SELECT id FROM history_entries WHERE timestamp < ?"+pinnedFilter, cutoff)
		if err == nil {
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					deletedIDs = append(deletedIDs, id)
				}
			}
			rows.Close()
		}
		res, err := execWithFTSRepair(h.db, "DELETE FROM history_entries WHERE timestamp < ?"+pinnedFilter, cutoff)
		if err != nil {
			logError("Cleanup by age: %v", err)
		} else {
			n, _ := res.RowsAffected()
			totalRemoved += n
		}
	}

	// Remove by count (keep newest)
	if maxEntries > 0 {
		whereClause := "pinned = 0"
		if includePinned {
			whereClause = "1=1"
		}
		// Collect IDs before deletion
		rows, err := h.db.Query(`SELECT id FROM history_entries WHERE id IN (
			SELECT id FROM history_entries WHERE `+whereClause+`
			ORDER BY timestamp ASC
			LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries) - ?)
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
			LIMIT MAX(0, (SELECT COUNT(*) FROM history_entries) - ?)
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
		DeleteAudio(id)
	}

	return int(totalRemoved)
}

// DuplicateEntry creates a copy of an entry by ID.
func (h *History) DuplicateEntry(id string) bool {
	e := h.GetByID(id)
	if e == nil {
		return false
	}

	h.mu.Lock()
	h.cache = nil
	h.mu.Unlock()

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
	if h.db != nil {
		h.db.Close()
	}
}
