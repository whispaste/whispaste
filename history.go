package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const defaultMaxHistory = 500

// HistoryEntry represents a single transcription or note.
type HistoryEntry struct {
	ID        string  `json:"id"`
	Text      string  `json:"text"`
	Title     string  `json:"title,omitempty"`
	Timestamp string  `json:"timestamp"`
	Duration  float64 `json:"duration_sec"`
	Language  string  `json:"language"`
	Category  string  `json:"category,omitempty"`
	Pinned    bool    `json:"pinned,omitempty"`
	Source    string  `json:"source,omitempty"`
	Model     string  `json:"model,omitempty"`
	IsLocal   bool    `json:"is_local,omitempty"`
	CostUSD   float64 `json:"cost_usd,omitempty"`
}

// History manages transcription history.
type History struct {
	Entries []HistoryEntry `json:"entries"`
	mu      sync.Mutex
}

func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		// Fallback to timestamp-based ID
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

// LoadHistory reads history from disk or returns empty.
// Backward-compatible: entries without ID get one generated.
func LoadHistory() *History {
	h := &History{}
	dir, err := configDir()
	if err != nil {
		return h
	}
	data, err := os.ReadFile(filepath.Join(dir, "history.json"))
	if err != nil {
		return h
	}
	json.Unmarshal(data, h)
	// Migration: ensure all entries have IDs and titles
	migrated := false
	for i := range h.Entries {
		if h.Entries[i].ID == "" {
			h.Entries[i].ID = generateID()
			migrated = true
		}
		if h.Entries[i].Title == "" && h.Entries[i].Text != "" {
			h.Entries[i].Title = autoTitle(h.Entries[i].Text)
			migrated = true
		}
		if h.Entries[i].Source == "" {
			h.Entries[i].Source = "dictation"
			migrated = true
		}
	}
	if migrated {
		h.save()
	}
	return h
}

// WhisperCostPerMinute is the current cost of OpenAI Whisper API per audio minute (USD).
const WhisperCostPerMinute = 0.006

// Add appends a new entry and prunes to the limit.
func (h *History) Add(text string, durationSec float64, language string) {
	h.AddWithModel(text, durationSec, language, "", false)
}

// AddWithModel appends a new entry with model tracking and prunes to the limit.
func (h *History) AddWithModel(text string, durationSec float64, language, model string, isLocal bool) {
	var cost float64
	if !isLocal && durationSec > 0 {
		cost = (durationSec / 60.0) * WhisperCostPerMinute
	}
	h.mu.Lock()
	h.Entries = append(h.Entries, HistoryEntry{
		ID:        generateID(),
		Text:      text,
		Title:     autoTitle(text),
		Timestamp: time.Now().Format(time.RFC3339),
		Duration:  durationSec,
		Language:  language,
		Source:    "dictation",
		Model:     model,
		IsLocal:   isLocal,
		CostUSD:   cost,
	})
	if len(h.Entries) > defaultMaxHistory {
		h.Entries = h.Entries[len(h.Entries)-defaultMaxHistory:]
	}
	h.mu.Unlock()
	h.save()
}

// Recent returns the last n entries (newest first).
func (h *History) Recent(n int) []HistoryEntry {
	h.mu.Lock()
	defer h.mu.Unlock()
	if n > len(h.Entries) {
		n = len(h.Entries)
	}
	result := make([]HistoryEntry, n)
	for i := 0; i < n; i++ {
		result[i] = h.Entries[len(h.Entries)-1-i]
	}
	return result
}

// All returns all entries (newest first).
func (h *History) All() []HistoryEntry {
	h.mu.Lock()
	defer h.mu.Unlock()
	result := make([]HistoryEntry, len(h.Entries))
	for i := 0; i < len(h.Entries); i++ {
		result[i] = h.Entries[len(h.Entries)-1-i]
	}
	return result
}

// Delete removes an entry by ID.
func (h *History) Delete(id string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, e := range h.Entries {
		if e.ID == id {
			h.Entries = append(h.Entries[:i], h.Entries[i+1:]...)
			h.saveLocked()
			return true
		}
	}
	return false
}

// TogglePin toggles the pinned state of an entry by ID.
func (h *History) TogglePin(id string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, e := range h.Entries {
		if e.ID == id {
			h.Entries[i].Pinned = !e.Pinned
			h.saveLocked()
			return true
		}
	}
	return false
}

// UpdateEntry updates title and/or category for an entry by ID.
func (h *History) UpdateEntry(id, title, category string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, e := range h.Entries {
		if e.ID == id {
			if title != "" {
				h.Entries[i].Title = title
			}
			h.Entries[i].Category = category
			h.saveLocked()
			return true
		}
	}
	return false
}

// UpdateText updates the text content (and auto-title) for an entry by ID.
func (h *History) UpdateText(id, newText string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, e := range h.Entries {
		if e.ID == id {
			h.Entries[i].Text = newText
			h.Entries[i].Title = autoTitle(newText)
			h.saveLocked()
			return true
		}
	}
	return false
}

// GetAnalytics computes usage statistics for a given time period.
func (h *History) GetAnalytics(periodDays int) map[string]interface{} {
	h.mu.Lock()
	defer h.mu.Unlock()

	now := time.Now()
	var cutoff time.Time
	if periodDays > 0 {
		cutoff = now.AddDate(0, 0, -periodDays)
	}

	var totalEntries, localEntries, apiEntries int
	var totalDuration, totalCost, localDuration float64
	var minDuration, maxDuration float64
	first := true
	dailyCounts := map[string]int{}
	modelCounts := map[string]int{}
	durationBuckets := map[string]int{"<15s": 0, "15-30s": 0, "30-60s": 0, "1-3m": 0, ">3m": 0}

	for _, e := range h.Entries {
		ts, err := time.Parse(time.RFC3339, e.Timestamp)
		if err != nil {
			continue
		}
		if periodDays > 0 && ts.Before(cutoff) {
			continue
		}

		totalEntries++
		totalDuration += e.Duration
		totalCost += e.CostUSD

		if first || e.Duration < minDuration {
			minDuration = e.Duration
		}
		if first || e.Duration > maxDuration {
			maxDuration = e.Duration
		}
		first = false

		if e.IsLocal {
			localEntries++
			localDuration += e.Duration
		} else {
			apiEntries++
		}

		day := ts.Format("2006-01-02")
		dailyCounts[day]++

		m := e.Model
		if m == "" {
			m = "unknown"
		}
		modelCounts[m]++

		switch {
		case e.Duration < 15:
			durationBuckets["<15s"]++
		case e.Duration < 30:
			durationBuckets["15-30s"]++
		case e.Duration < 60:
			durationBuckets["30-60s"]++
		case e.Duration < 180:
			durationBuckets["1-3m"]++
		default:
			durationBuckets[">3m"]++
		}
	}

	// Calculate savings: what local transcriptions would have cost via API
	savings := (localDuration / 60.0) * WhisperCostPerMinute

	return map[string]interface{}{
		"totalEntries":    totalEntries,
		"localEntries":    localEntries,
		"apiEntries":      apiEntries,
		"totalDuration":   totalDuration,
		"totalCost":       totalCost,
		"savings":         savings,
		"dailyCounts":     dailyCounts,
		"modelCounts":     modelCounts,
		"durationBuckets": durationBuckets,
		"avgDuration":     safeDiv(totalDuration, float64(totalEntries)),
		"minDuration":     minDuration,
		"maxDuration":     maxDuration,
	}
}

func safeDiv(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}

// Categories returns all unique category names used across entries.
func (h *History) Categories() []string {
	h.mu.Lock()
	defer h.mu.Unlock()
	seen := map[string]bool{}
	var cats []string
	for _, e := range h.Entries {
		if e.Category != "" && !seen[e.Category] {
			seen[e.Category] = true
			cats = append(cats, e.Category)
		}
	}
	return cats
}

// Merge combines multiple entries into one. The newest entry's metadata is used as the base.
// Texts are concatenated with double newline separators. Duration is summed.
// Returns the ID of the merged entry, or empty string on error.
func (h *History) Merge(ids []string) string {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Find matching entries (preserve order by timestamp)
	var matches []HistoryEntry
	idSet := make(map[string]bool)
	for _, id := range ids {
		idSet[id] = true
	}
	for _, e := range h.Entries {
		if idSet[e.ID] {
			matches = append(matches, e)
		}
	}
	if len(matches) < 2 {
		return ""
	}

	// Build merged entry: concatenate texts, sum durations, use newest timestamp
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
	merged := HistoryEntry{
		ID:        generateID(),
		Text:      mergedText,
		Title:     autoTitle(mergedText),
		Timestamp: newestTime,
		Duration:  totalDuration,
		Language:  matches[0].Language,
		Source:    "merged",
		Category:  "merged",
	}

	// Remove originals
	var remaining []HistoryEntry
	for _, e := range h.Entries {
		if !idSet[e.ID] {
			remaining = append(remaining, e)
		}
	}
	remaining = append(remaining, merged)
	h.Entries = remaining
	h.saveLocked()
	return merged.ID
}

func (h *History) save() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.saveLocked()
}

// saveLocked writes history to disk. Caller must hold h.mu.
func (h *History) saveLocked() {
	dir, err := configDir()
	if err != nil {
		return
	}
	data, err := json.MarshalIndent(h, "", "  ")
	if err != nil {
		return
	}
	os.WriteFile(filepath.Join(dir, "history.json"), data, 0600)
}
