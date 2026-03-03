package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const maxHistoryEntries = 50

// HistoryEntry represents a single transcription.
type HistoryEntry struct {
	Text      string  `json:"text"`
	Timestamp string  `json:"timestamp"`
	Duration  float64 `json:"duration_sec"`
	Language  string  `json:"language"`
}

// History manages transcription history.
type History struct {
	Entries []HistoryEntry `json:"entries"`
	mu      sync.Mutex
}

// LoadHistory reads history from disk or returns empty.
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
	return h
}

// Add appends a new entry and prunes to maxHistoryEntries.
func (h *History) Add(text string, durationSec float64, language string) {
	h.mu.Lock()
	h.Entries = append(h.Entries, HistoryEntry{
		Text:      text,
		Timestamp: time.Now().Format(time.RFC3339),
		Duration:  durationSec,
		Language:  language,
	})
	if len(h.Entries) > maxHistoryEntries {
		h.Entries = h.Entries[len(h.Entries)-maxHistoryEntries:]
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

func (h *History) save() {
	dir, err := configDir()
	if err != nil {
		return
	}
	h.mu.Lock()
	data, err := json.MarshalIndent(h, "", "  ")
	h.mu.Unlock()
	if err != nil {
		return
	}
	os.WriteFile(filepath.Join(dir, "history.json"), data, 0600)
}
