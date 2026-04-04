package main

import (
	"strings"
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
		{
			name:     "labeled json array",
			content:  `Tags: ["Work", "Meeting"]`,
			wantTags: []string{"Work", "Meeting"},
		},
		{
			name:     "takes last valid json array",
			content:  `Example: ["Personal"] Answer: ["Work", "Meeting"]`,
			wantTags: []string{"Work", "Meeting"},
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
		{
			name:     "labeled json array",
			content:  `Suggested tags: ["work", "email"]`,
			wantTags: []string{"Work", "Email"},
		},
		{
			name:     "takes last valid json array",
			content:  `Example: ["personal"] Answer: ["work", "email"]`,
			wantTags: []string{"Work", "Email"},
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
		name    string
		content string
		want    string
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
		{
			name:    "greeting line skipped",
			content: "Hello!\nWeekly Project Planning Update",
			want:    "Weekly Project Planning Update",
		},
		{
			name:    "title label stripped",
			content: "Title: Weekly Project Planning Update",
			want:    "Weekly Project Planning Update",
		},
		{
			name:    "meta preface line skipped",
			content: "Suggested title:\nWeekly Project Planning Update",
			want:    "Weekly Project Planning Update",
		},
		{
			name:    "bullet prefix stripped",
			content: "- Weekly Project Planning Update",
			want:    "Weekly Project Planning Update",
		},
		{
			name:    "year-like title preserved",
			content: "2025. Product Roadmap Review",
			want:    "2025. Product Roadmap Review",
		},
		{
			name:    "numbered title preserved",
			content: "12. Angry Men Notes",
			want:    "12. Angry Men Notes",
		},
		{
			name:    "title preface with sentence reduced to payload",
			content: "Fragen: Release coordination for Friday launch",
			want:    "Fragen: Release coordination for Friday launch",
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

func TestBuildTitleSystemPrompt(t *testing.T) {
	prevLang := GetLanguage()
	SetLanguage("en")
	defer SetLanguage(prevLang)

	prompt := buildTitleSystemPrompt("de")
	if !strings.HasPrefix(prompt, "Task: Create a short, descriptive title") {
		t.Fatalf("title prompt should start with the direct task, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Write the title in German.") {
		t.Errorf("title prompt should enforce German for langHint=de, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Use 3-7 words.") {
		t.Errorf("title prompt should enforce a shorter title length, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Return only the title text. No quotes, labels, or commentary.") {
		t.Errorf("title prompt should require title-only output, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Do not start with greetings, filler, or meta-commentary.") {
		t.Errorf("title prompt should forbid greetings and meta-commentary, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Do not format the answer as a list item or add labels like \"Title:\".") {
		t.Errorf("title prompt should forbid list-style titles and labels, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Do not invent people, dates, places, or facts that are not stated in the note.") {
		t.Errorf("title prompt should forbid invented specifics, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Do not write a full sentence, question, or request.") {
		t.Errorf("title prompt should forbid sentence-like titles, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Do not copy imperative wording from the note.") {
		t.Errorf("title prompt should forbid imperative note wording, got: %q", prompt)
	}
}

func TestBuildTitleSystemPromptFallsBackToCurrentUILanguage(t *testing.T) {
	prevLang := GetLanguage()
	SetLanguage("de")
	defer SetLanguage(prevLang)

	prompt := buildTitleSystemPrompt("")
	if !strings.Contains(prompt, "Write the title in German.") {
		t.Errorf("title prompt should fall back to the current UI language when no explicit UI hint is provided, got: %q", prompt)
	}
}

func TestTitleNeedsRetry(t *testing.T) {
	tests := []struct {
		name  string
		title string
		want  bool
	}{
		{name: "good short title", title: "Release Coordination Friday", want: false},
		{name: "greeting style", title: "Hallo Frau Becker", want: true},
		{name: "imperative sentence", title: "Bitte senden Sie mir die Agenda", want: true},
		{name: "question style", title: "Fragen: Für den Release am Freitag müssen wir heute noch koordinieren", want: true},
		{name: "time only title", title: "Mittwoch um 14 Uhr", want: true},
		{name: "weekday led action title", title: "Freitag: Release-Plan koordinieren", want: true},
		{name: "german am not false positive", title: "Fehler am 5. Tag", want: false},
		{name: "english am time", title: "Meeting 10 am", want: true},
		{name: "too many words", title: "This is far too long to be a good generated note title", want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := titleNeedsRetry(tt.title); got != tt.want {
				t.Fatalf("titleNeedsRetry(%q) = %v, want %v", tt.title, got, tt.want)
			}
		})
	}
}

func TestFallbackTitleFromTags(t *testing.T) {
	if got := fallbackTitleFromTags(nil); got != "" {
		t.Fatalf("fallbackTitleFromTags(nil) = %q, want empty", got)
	}
	if got := fallbackTitleFromTags([]string{"Release"}); got != "Release" {
		t.Fatalf("fallbackTitleFromTags(single) = %q", got)
	}
	if got := fallbackTitleFromTags([]string{"Release", "Changelog", "Ui-texte"}); got != "Release & Changelog" {
		t.Fatalf("fallbackTitleFromTags(multi) = %q", got)
	}
}

func TestBuildNewTagsSystemPromptUsesUILanguage(t *testing.T) {
	prevLang := GetLanguage()
	SetLanguage("en")
	defer SetLanguage(prevLang)

	prompt := buildNewTagsSystemPrompt("de")
	if !strings.Contains(prompt, "Write all tags in German") {
		t.Errorf("new-tag prompt should enforce the UI language, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Keep every tag in that UI language, even if the source text mixes languages") {
		t.Errorf("new-tag prompt should keep all tags in the UI language, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Prefer 2-3 complementary topical tags") {
		t.Errorf("new-tag prompt should prefer complementary topical tags, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Favor reusable grouping tags") {
		t.Errorf("new-tag prompt should encourage reusable grouping tags, got: %q", prompt)
	}
}

func TestBuildTagClassifierSystemPromptUsesUILanguagePreference(t *testing.T) {
	prevLang := GetLanguage()
	SetLanguage("en")
	defer SetLanguage(prevLang)

	prompt := buildTagClassifierSystemPrompt([]string{"Meeting", "Email"}, "de")
	if !strings.Contains(prompt, "Prefer tags written in German") {
		t.Errorf("tag-classifier prompt should prefer tags in the UI language, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Never translate, rewrite, or explain tags; use the exact tag text from the list") {
		t.Errorf("tag-classifier prompt should preserve stable tag text from the available list, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Prefer 2-3 complementary tags") {
		t.Errorf("tag-classifier prompt should prefer complementary tags when warranted, got: %q", prompt)
	}
	if !strings.Contains(prompt, "Prefer reusable grouping tags over one-off details") {
		t.Errorf("tag-classifier prompt should encourage reusable grouping tags, got: %q", prompt)
	}
}
