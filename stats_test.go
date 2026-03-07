package main

import (
	"testing"
)

func TestRecordDictation(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())

	s := &UsageStats{}
	total := s.RecordDictation("hello world foo bar", 5.0, false)
	if total != 1 {
		t.Errorf("total dictations = %d, want 1", total)
	}
	if s.TotalWords != 4 {
		t.Errorf("total words = %d, want 4", s.TotalWords)
	}
	if s.TotalSeconds != 5.0 {
		t.Errorf("total seconds = %f, want 5.0", s.TotalSeconds)
	}
	if s.MonthWords != 4 {
		t.Errorf("month words = %d, want 4", s.MonthWords)
	}

	// Local dictation
	s.RecordDictation("local text here", 3.0, true)
	if s.LocalDictations != 1 {
		t.Errorf("local dictations = %d, want 1", s.LocalDictations)
	}
	if s.LocalWords != 3 {
		t.Errorf("local words = %d, want 3", s.LocalWords)
	}
	if s.TotalDictations != 2 {
		t.Errorf("total dictations = %d, want 2", s.TotalDictations)
	}
}

func TestRecordDictationMonthRollover(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())

	s := &UsageStats{
		MonthKey:        "2025-01", // old month
		MonthWords:      100,
		MonthDictations: 10,
		MonthSeconds:    60.0,
		TotalWords:      200,
		TotalDictations: 20,
	}
	s.RecordDictation("new month", 2.0, false)
	if s.MonthWords != 2 {
		t.Errorf("after rollover month words = %d, want 2", s.MonthWords)
	}
	if s.MonthDictations != 1 {
		t.Errorf("after rollover month dictations = %d, want 1", s.MonthDictations)
	}
	// Totals should still accumulate
	if s.TotalWords != 202 {
		t.Errorf("total words = %d, want 202", s.TotalWords)
	}
}

func TestTimeSavedMinutes(t *testing.T) {
	tests := []struct {
		name         string
		monthWords   int
		monthSeconds float64
		wantMin      float64
	}{
		{"positive savings", 400, 120, 400.0/40.0 - 120.0/60.0},
		{"zero savings", 0, 0, 0},
		{"negative clamped", 10, 600, 0}, // typing faster than dictating
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := &UsageStats{MonthWords: tt.monthWords, MonthSeconds: tt.monthSeconds}
			got := s.TimeSavedMinutes()
			if got != tt.wantMin {
				t.Errorf("TimeSavedMinutes() = %f, want %f", got, tt.wantMin)
			}
		})
	}
}

func TestEstimatedCost(t *testing.T) {
	tests := []struct {
		name              string
		monthSeconds      float64
		monthLocalSeconds float64
		wantCost          float64
	}{
		{"all API", 600, 0, 600.0 / 60.0 * 0.006},         // 10 min * $0.006/min
		{"mixed", 600, 300, 300.0 / 60.0 * 0.006},          // 5 min API
		{"all local", 600, 600, 0},                          // no API cost
		{"more local than total", 100, 200, 0},              // clamped to 0
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := &UsageStats{MonthSeconds: tt.monthSeconds, MonthLocalSeconds: tt.monthLocalSeconds}
			got := s.EstimatedCost()
			if got != tt.wantCost {
				t.Errorf("EstimatedCost() = %f, want %f", got, tt.wantCost)
			}
		})
	}
}

func TestSnapshot(t *testing.T) {
	s := &UsageStats{
		TotalWords:      100,
		TotalDictations: 5,
		MonthWords:      50,
		MonthDictations: 3,
	}
	snap := s.Snapshot()
	if snap["total_words"] != 100 {
		t.Errorf("snapshot total_words = %v, want 100", snap["total_words"])
	}
	if snap["month_dictations"] != 3 {
		t.Errorf("snapshot month_dictations = %v, want 3", snap["month_dictations"])
	}
}
