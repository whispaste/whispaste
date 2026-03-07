package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// UsageStats tracks dictation usage for the stats dashboard.
type UsageStats struct {
	TotalWords      int     `json:"total_words"`
	TotalDictations int     `json:"total_dictations"`
	TotalSeconds    float64 `json:"total_seconds"`
	LocalDictations int     `json:"local_dictations"`
	LocalWords      int     `json:"local_words"`
	LocalSeconds    float64 `json:"local_seconds"`
	MonthWords      int     `json:"month_words"`
	MonthDictations int     `json:"month_dictations"`
	MonthSeconds    float64 `json:"month_seconds"`
	MonthLocalDictations int     `json:"month_local_dictations"`
	MonthLocalWords      int     `json:"month_local_words"`
	MonthLocalSeconds    float64 `json:"month_local_seconds"`
	MonthKey        string  `json:"month_key"` // "2026-03" format
	mu              sync.Mutex
}

// LoadStats reads stats from disk or returns fresh defaults.
func LoadStats() *UsageStats {
	s := &UsageStats{}
	dir, err := configDir()
	if err != nil {
		return s
	}
	data, err := os.ReadFile(filepath.Join(dir, "stats.json"))
	if err != nil {
		return s
	}
	json.Unmarshal(data, s)
	// Reset month counters if month changed
	current := time.Now().Format("2006-01")
	if s.MonthKey != current {
		s.MonthWords = 0
		s.MonthDictations = 0
		s.MonthSeconds = 0
		s.MonthLocalDictations = 0
		s.MonthLocalWords = 0
		s.MonthLocalSeconds = 0
		s.MonthKey = current
	}
	return s
}

// RecordDictation records a completed dictation and returns the new total count.
func (s *UsageStats) RecordDictation(text string, durationSec float64, isLocal bool) int {
	words := len(strings.Fields(text))
	s.mu.Lock()
	// Check month rollover
	current := time.Now().Format("2006-01")
	if s.MonthKey != current {
		s.MonthWords = 0
		s.MonthDictations = 0
		s.MonthSeconds = 0
		s.MonthLocalDictations = 0
		s.MonthLocalWords = 0
		s.MonthLocalSeconds = 0
		s.MonthKey = current
	}
	s.TotalWords += words
	s.TotalDictations++
	s.TotalSeconds += durationSec
	s.MonthWords += words
	s.MonthDictations++
	s.MonthSeconds += durationSec
	if isLocal {
		s.LocalDictations++
		s.LocalWords += words
		s.LocalSeconds += durationSec
		s.MonthLocalDictations++
		s.MonthLocalWords += words
		s.MonthLocalSeconds += durationSec
	}
	total := s.TotalDictations
	s.mu.Unlock()
	s.save()
	return total
}

// TimeSavedMinutes returns estimated minutes saved vs typing at 40 WPM.
func (s *UsageStats) TimeSavedMinutes() float64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	typingMin := float64(s.MonthWords) / 40.0
	dictationMin := s.MonthSeconds / 60.0
	saved := typingMin - dictationMin
	if saved < 0 {
		return 0
	}
	return saved
}

// EstimatedCost returns the estimated API cost for the current month in USD.
func (s *UsageStats) EstimatedCost() float64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	apiSeconds := s.MonthSeconds - s.MonthLocalSeconds
	if apiSeconds < 0 {
		apiSeconds = 0
	}
	return apiSeconds / 60.0 * 0.006
}

// Snapshot returns a copy of stats for UI display (thread-safe).
func (s *UsageStats) Snapshot() map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	return map[string]interface{}{
		"total_words":          s.TotalWords,
		"total_dictations":     s.TotalDictations,
		"local_dictations":     s.LocalDictations,
		"month_local_dictations": s.MonthLocalDictations,
		"local_seconds":        s.LocalSeconds,
		"month_local_seconds":  s.MonthLocalSeconds,
		"month_words":          s.MonthWords,
		"month_dictations":     s.MonthDictations,
		"month_seconds":        s.MonthSeconds,
		"time_saved_min":       s.TimeSavedMinutesLocked(),
		"estimated_cost":       s.EstimatedCostLocked(),
	}
}

// TimeSavedMinutesLocked is the internal version (caller holds lock).
func (s *UsageStats) TimeSavedMinutesLocked() float64 {
	typingMin := float64(s.MonthWords) / 40.0
	dictationMin := s.MonthSeconds / 60.0
	saved := typingMin - dictationMin
	if saved < 0 {
		return 0
	}
	return saved
}

// EstimatedCostLocked is the internal version (caller holds lock).
func (s *UsageStats) EstimatedCostLocked() float64 {
	apiSeconds := s.MonthSeconds - s.MonthLocalSeconds
	if apiSeconds < 0 {
		apiSeconds = 0
	}
	return apiSeconds / 60.0 * 0.006
}

// Reset clears all usage statistics and saves.
func (s *UsageStats) Reset() {
	s.mu.Lock()
	s.TotalWords = 0
	s.TotalDictations = 0
	s.TotalSeconds = 0
	s.LocalDictations = 0
	s.LocalWords = 0
	s.LocalSeconds = 0
	s.MonthWords = 0
	s.MonthDictations = 0
	s.MonthSeconds = 0
	s.MonthLocalDictations = 0
	s.MonthLocalWords = 0
	s.MonthLocalSeconds = 0
	s.MonthKey = time.Now().Format("2006-01")
	s.mu.Unlock()
	s.save()
}

func (s *UsageStats) save() {
	dir, err := configDir()
	if err != nil {
		return
	}
	s.mu.Lock()
	data, err := json.MarshalIndent(s, "", "  ")
	s.mu.Unlock()
	if err != nil {
		return
	}
	os.WriteFile(filepath.Join(dir, "stats.json"), data, 0600)
}
