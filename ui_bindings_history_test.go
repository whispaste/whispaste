package main

import (
	"strings"
	"testing"
)

func TestMergedEntryAutoTitleContextUsesMergedTextAndUILanguage(t *testing.T) {
	h := newTestHistory(t)
	h.AddWithModelHint("first text", 10.0, 0.5, "en", "whisper-base", true, "", "de")
	h.AddWithModelHint("second text", 5.0, 0.5, "en", "whisper-base", true, "", "de")
	ids := h.All()

	mergedID := h.Merge([]string{ids[0].ID, ids[1].ID})
	if mergedID == "" {
		t.Fatal("merge returned empty ID")
	}

	text, uiLang, ok := mergedEntryAutoTitleContext(&Config{UILanguage: "de"}, h, mergedID)
	if !ok {
		t.Fatal("expected merged entry auto-title context to be available")
	}
	if uiLang != "de" {
		t.Fatalf("uiLang = %q, want de", uiLang)
	}
	if !strings.Contains(text, "first text") || !strings.Contains(text, "second text") {
		t.Fatalf("merged text %q does not contain both original texts", text)
	}
}

func TestMergedEntryAutoTitleContextRejectsMissingEntry(t *testing.T) {
	h := newTestHistory(t)

	if _, _, ok := mergedEntryAutoTitleContext(&Config{UILanguage: "de"}, h, "missing"); ok {
		t.Fatal("expected missing entry to return no auto-title context")
	}
}
