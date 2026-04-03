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
		{
			name:     "markdown fenced multiline",
			content:  "```json\n[\"Work\", \"Meeting\"]\n```",
			wantTags: []string{"Work", "Meeting"},
		},
		{
			name:     "markdown fenced inline",
			content:  "```[\"Work\"]```",
			wantTags: []string{"Work"},
		},
		{
			name:     "markdown fenced with extra text",
			content:  "Here are the tags:\n```json\n[\"Personal\"]\n```\n",
			wantTags: []string{"Personal"},
		},
		{
			name:     "markdown multiple fenced blocks",
			content:  "Example:\n```\nfoo\n```\n\nAnswer:\n```json\n[\"Work\"]\n```",
			wantTags: []string{"Work"},
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

func TestParseGeneratedTags(t *testing.T) {
	tests := []struct {
		name      string
		content   string
		wantTags  []string
		wantEmpty bool
	}{
		{
			name:     "valid JSON array normalized to Title Case",
			content:  `["work", "email"]`,
			wantTags: []string{"Work", "Email"},
		},
		{
			name:     "uppercased tags normalized to Title Case",
			content:  `["WORK", "EMAIL"]`,
			wantTags: []string{"Work", "Email"},
		},
		{
			name:     "mixed case normalized to Title Case",
			content:  `["Meeting", "pLANNING"]`,
			wantTags: []string{"Meeting", "Planning"},
		},
		{
			name:      "empty array",
			content:   `[]`,
			wantEmpty: true,
		},
		{
			name:     "comma-separated fallback",
			content:  `work, planning`,
			wantTags: []string{"Work", "Planning"},
		},
		{
			name:      "too short tag filtered",
			content:   `["a", "ok"]`,
			wantTags:  []string{"Ok"},
			wantEmpty: false,
		},
		{
			name:      "tag with spaces rejected",
			content:   `["my tag", "work"]`,
			wantTags:  []string{"Work"},
			wantEmpty: false,
		},
		{
			name:     "caps at 3 tags",
			content:  `["alpha", "beta", "gamma", "delta", "epsilon"]`,
			wantTags: []string{"Alpha", "Beta", "Gamma"},
		},
		{
			name:     "deduplicates case-insensitively",
			content:  `["work", "Work", "WORK"]`,
			wantTags: []string{"Work"},
		},
		{
			name:      "empty string",
			content:   ``,
			wantEmpty: true,
		},
		{
			name:     "markdown fenced",
			content:  "```json\n[\"meeting\", \"notes\"]\n```",
			wantTags: []string{"Meeting", "Notes"},
		},
		{
			name:     "hyphenated tags allowed",
			content:  `["to-do", "follow-up"]`,
			wantTags: []string{"To-do", "Follow-up"},
		},
		{
			name:      "special chars rejected",
			content:   `["tag!", "hello@world", "ok"]`,
			wantTags:  []string{"Ok"},
			wantEmpty: false,
		},
		{
			name:      "too long tag rejected",
			content:   `["thistagiswaytoolongtobevalid", "ok"]`,
			wantTags:  []string{"Ok"},
			wantEmpty: false,
		},
		{
			name:      "system tag pending filtered",
			content:   `["pending", "work", "meeting"]`,
			wantTags:  []string{"Work", "Meeting"},
			wantEmpty: false,
		},
		{
			name:      "system tag duplicated filtered",
			content:   `["duplicated", "email"]`,
			wantTags:  []string{"Email"},
			wantEmpty: false,
		},
		{
			name:      "system tags case-insensitive filter",
			content:   `["PENDING", "Duplicated", "notes"]`,
			wantTags:  []string{"Notes"},
			wantEmpty: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseGeneratedTags(tt.content)
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

func TestCleanTitleResponse(t *testing.T) {
	tests := []struct {
		name string
		content string
		want string
	}{
		{
			name:    "plain title",
			content: "Weekly Project Planning Update",
			want:    "Weekly Project Planning Update",
		},
		{
			name:    "title with surrounding quotes",
			content: `"Weekly Project Planning"`,
			want:    "Weekly Project Planning",
		},
		{
			name:    "title with single quotes",
			content: `'Meeting Notes'`,
			want:    "Meeting Notes",
		},
		{
			name:    "title with markdown code fence",
			content: "```\nProject Update\n```",
			want:    "Project Update",
		},
		{
			name:    "title with markdown json fence",
			content: "```json\nProject Update\n```",
			want:    "Project Update",
		},
		{
			name:    "multiline takes first line only",
			content: "Main Title\nSome extra explanation",
			want:    "Main Title",
		},
		{
			name:    "empty string",
			content: "",
			want:    "",
		},
		{
			name:    "whitespace only",
			content: "   ",
			want:    "",
		},
		{
			name:    "truncated to 100 chars",
			content: "This is a very long title that exceeds the one hundred character limit and should be truncated by the cleaning function here",
			want:    "This is a very long title that exceeds the one hundred character limit and should be truncated by th",
		},
		{
			name:    "title with backtick quotes",
			content: "`Quick Summary`",
			want:    "Quick Summary",
		},
		{
			name:    "title with leading/trailing whitespace",
			content: "  Trimmed Title  ",
			want:    "Trimmed Title",
		},
		{
			name:    "title with /no_think",
			content: "Weekly Update /no_think",
			want:    "Weekly Update",
		},
		{
			name:    "title with /no_feedback",
			content: "Projektplanung /no_feedback",
			want:    "Projektplanung",
		},
		{
			name:    "title with multiple slashes",
			content: "My Title /no_think /no_feedback",
			want:    "My Title /no_think",
		},
		{
			name:    "title with URL-like slash",
			content: "Check http://example.com",
			want:    "Check http://example.com",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := cleanTitleResponse(tt.content)
			if got != tt.want {
				t.Errorf("cleanTitleResponse(%q) = %q, want %q", tt.content, got, tt.want)
			}
		})
	}
}
