package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func testEntry() *HistoryEntry {
	return &HistoryEntry{
		ID:        "test-1",
		Title:     "Test Entry",
		Text:      "Hello world",
		Timestamp: "2026-01-01 12:00",
		Duration:  3.5,
		Language:  "en",
		Tags:      []string{"tag1", "tag2"},
		Pinned:    false,
		Model:     "whisper-1",
		IsLocal:   false,
		CostUSD:   0.006,
	}
}

// P0 — CSV formula injection prevention
func TestCSVSafe(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"equals", "=cmd|'/C calc'!A0", "\t=cmd|'/C calc'!A0"},
		{"plus", "+1+1", "\t+1+1"},
		{"minus", "-1-1", "\t-1-1"},
		{"at", "@SUM(A1:A2)", "\t@SUM(A1:A2)"},
		{"normal", "Hello world", "Hello world"},
		{"empty", "", ""},
		{"safe number", "42", "42"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := csvSafe(tt.in)
			if got != tt.want {
				t.Errorf("csvSafe(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestXMLEscape(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"special chars", `<script>&"end"`, "&lt;script&gt;&amp;&#34;end&#34;"},
		{"plain text", "hello", "hello"},
		{"empty", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := xmlEscape(tt.in)
			if got != tt.want {
				t.Errorf("xmlEscape(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestSanitizeFilename(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"invalid chars", `file<>:"/\|?*name`, "filename"},
		{"long name", strings.Repeat("a", 80), strings.Repeat("a", 50)},
		{"whitespace", "  hello  ", "hello"},
		{"newlines", "line1\nline2\r\n", "line1 line2"},
		{"empty", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sanitizeFilename(tt.in)
			if got != tt.want {
				t.Errorf("sanitizeFilename(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestFormatEntriesJSON(t *testing.T) {
	t.Run("single entry", func(t *testing.T) {
		e := testEntry()
		data, err := formatEntriesJSON([]*HistoryEntry{e})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		var result []map[string]interface{}
		if err := json.Unmarshal(data, &result); err != nil {
			t.Fatalf("invalid JSON: %v", err)
		}
		if len(result) != 1 {
			t.Fatalf("expected 1 entry, got %d", len(result))
		}
		if result[0]["id"] != "test-1" {
			t.Errorf("id = %v, want test-1", result[0]["id"])
		}
		if result[0]["text"] != "Hello world" {
			t.Errorf("text = %v, want Hello world", result[0]["text"])
		}
	})

	t.Run("empty slice", func(t *testing.T) {
		data, err := formatEntriesJSON([]*HistoryEntry{})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		var result []interface{}
		if err := json.Unmarshal(data, &result); err != nil {
			t.Fatalf("invalid JSON: %v", err)
		}
		if len(result) != 0 {
			t.Errorf("expected empty array, got %d items", len(result))
		}
	})
}

func TestFormatEntriesCSV(t *testing.T) {
	t.Run("normal entry", func(t *testing.T) {
		e := testEntry()
		data, err := formatEntriesCSV([]*HistoryEntry{e})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		lines := strings.Split(strings.TrimSpace(string(data)), "\n")
		if len(lines) < 2 {
			t.Fatalf("expected header + data row, got %d lines", len(lines))
		}
		header := lines[0]
		for _, col := range []string{"ID", "Title", "Text", "Timestamp", "Language", "Tags"} {
			if !strings.Contains(header, col) {
				t.Errorf("header missing column %q", col)
			}
		}
	})

	t.Run("formula injection sanitized", func(t *testing.T) {
		e := testEntry()
		e.Text = "=HYPERLINK(\"http://evil\")"
		data, err := formatEntriesCSV([]*HistoryEntry{e})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		csv := string(data)
		if !strings.Contains(csv, "\t=HYPERLINK") {
			t.Errorf("expected tab-prefixed formula, got: %s", csv)
		}
	})
}

func TestGenerateDOCX(t *testing.T) {
	t.Run("valid zip structure", func(t *testing.T) {
		e := testEntry()
		data, err := generateDOCX([]*HistoryEntry{e})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
		if err != nil {
			t.Fatalf("invalid ZIP: %v", err)
		}

		expected := map[string]bool{
			"[Content_Types].xml":          false,
			"_rels/.rels":                  false,
			"word/_rels/document.xml.rels": false,
			"word/styles.xml":              false,
			"word/document.xml":            false,
		}
		for _, f := range zr.File {
			if _, ok := expected[f.Name]; ok {
				expected[f.Name] = true
			}
		}
		for name, found := range expected {
			if !found {
				t.Errorf("missing DOCX entry: %s", name)
			}
		}
	})

	t.Run("xml entities escaped", func(t *testing.T) {
		e := testEntry()
		e.Title = "Test <&> Title"
		e.Text = "Body with \"quotes\" & <tags>"
		data, err := generateDOCX([]*HistoryEntry{e})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
		if err != nil {
			t.Fatalf("invalid ZIP: %v", err)
		}
		for _, f := range zr.File {
			if f.Name == "word/document.xml" {
				rc, err := f.Open()
				if err != nil {
					t.Fatalf("open document.xml: %v", err)
				}
				var buf bytes.Buffer
				buf.ReadFrom(rc)
				rc.Close()
				content := buf.String()
				if strings.Contains(content, "<&>") {
					t.Error("unescaped XML entities in document.xml")
				}
				if !strings.Contains(content, "&lt;&amp;&gt;") {
					t.Error("expected escaped entities in title")
				}
				return
			}
		}
		t.Error("word/document.xml not found in ZIP")
	})
}

func TestFormatEntryTXT(t *testing.T) {
	e := testEntry()
	got := formatEntryTXT(e)

	checks := []string{
		"Test Entry\n",
		"Date: 2026-01-01 12:00",
		"Language: en",
		"Tags: tag1, tag2",
		"Hello world",
	}
	for _, want := range checks {
		if !strings.Contains(got, want) {
			t.Errorf("formatEntryTXT missing %q\ngot:\n%s", want, got)
		}
	}
}

func TestFormatEntryMD(t *testing.T) {
	e := testEntry()
	got := formatEntryMD(e)

	checks := []string{
		"# Test Entry",
		"- **Date:** 2026-01-01 12:00",
		"- **Language:** EN",
		"- **Duration:** 3.5s",
		"`tag1`",
		"`tag2`",
		"Hello world",
	}
	for _, want := range checks {
		if !strings.Contains(got, want) {
			t.Errorf("formatEntryMD missing %q\ngot:\n%s", want, got)
		}
	}
}
