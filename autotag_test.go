package main

import (
	"testing"
)

func TestParseTagResponse(t *testing.T) {
	available := []string{"Work", "Personal", "Meeting", "Urgent", "Ideas"}

	tests := []struct {
		name      string
		content   string
		wantTags  []string
		wantEmpty bool
	}{
		{
			name:     "valid JSON array",
			content:  `["Work", "Meeting"]`,
			wantTags: []string{"Work", "Meeting"},
		},
		{
			name:     "case insensitive match",
			content:  `["work", "MEETING"]`,
			wantTags: []string{"Work", "Meeting"},
		},
		{
			name:      "empty array",
			content:   `[]`,
			wantEmpty: true,
		},
		{
			name:     "comma-separated fallback",
			content:  `Work, Meeting`,
			wantTags: []string{"Work", "Meeting"},
		},
		{
			name:      "invalid tag filtered out",
			content:   `["Work", "NonExistent"]`,
			wantTags:  []string{"Work"},
			wantEmpty: false,
		},
		{
			name:     "caps at 3 tags",
			content:  `["Work", "Personal", "Meeting", "Urgent", "Ideas"]`,
			wantTags: []string{"Work", "Personal", "Meeting"},
		},
		{
			name:     "deduplicates",
			content:  `["Work", "work", "WORK"]`,
			wantTags: []string{"Work"},
		},
		{
			name:      "empty string",
			content:   ``,
			wantEmpty: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseTagResponse(tt.content, available)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.wantEmpty {
				if len(got) != 0 {
					t.Errorf("expected empty, got %v", got)
				}
				return
			}
			if len(got) != len(tt.wantTags) {
				t.Errorf("expected %d tags, got %d: %v", len(tt.wantTags), len(got), got)
				return
			}
			for i, want := range tt.wantTags {
				if got[i] != want {
					t.Errorf("tag[%d]: expected %q, got %q", i, want, got[i])
				}
			}
		})
	}
}
