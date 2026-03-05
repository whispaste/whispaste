package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// newTestHistory creates a History backed by an in-memory SQLite database.
func newTestHistory(t *testing.T) *History {
	t.Helper()
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	if err := createHistoryTables(db); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return &History{db: db}
}

func TestHistoryAddAndAll(t *testing.T) {
	h := newTestHistory(t)
	h.AddWithModel("hello world", 10.5, 1.2, "en", "whisper-1", false)
	h.AddWithModel("zweiter eintrag", 5.0, 0.8, "de", "whisper-base", true)

	all := h.All()
	if len(all) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(all))
	}
	// Newest first
	if all[0].Language != "de" {
		t.Errorf("expected newest entry (de) first, got %s", all[0].Language)
	}
	if all[1].CostUSD == 0 {
		t.Error("expected non-zero cost for API entry")
	}
	if all[0].CostUSD != 0 {
		t.Error("expected zero cost for local entry")
	}
}

func TestHistoryRecent(t *testing.T) {
	h := newTestHistory(t)
	for i := 0; i < 5; i++ {
		h.Add("entry", float64(i), "en")
	}
	recent := h.Recent(3)
	if len(recent) != 3 {
		t.Fatalf("expected 3 recent, got %d", len(recent))
	}
}

func TestHistoryDelete(t *testing.T) {
	h := newTestHistory(t)
	h.Add("test", 1.0, "en")
	entries := h.All()
	if len(entries) != 1 {
		t.Fatal("expected 1 entry")
	}
	if !h.Delete(entries[0].ID) {
		t.Error("delete returned false")
	}
	if len(h.All()) != 0 {
		t.Error("expected 0 entries after delete")
	}
	if h.Delete("nonexistent") {
		t.Error("delete of nonexistent should return false")
	}
}

func TestHistoryTogglePin(t *testing.T) {
	h := newTestHistory(t)
	h.Add("test", 1.0, "en")
	id := h.All()[0].ID

	h.TogglePin(id)
	if !h.GetByID(id).Pinned {
		t.Error("expected pinned=true")
	}
	h.TogglePin(id)
	if h.GetByID(id).Pinned {
		t.Error("expected pinned=false")
	}
}

func TestHistoryUpdateEntry(t *testing.T) {
	h := newTestHistory(t)
	h.Add("test", 1.0, "en")
	id := h.All()[0].ID

	h.UpdateEntry(id, "new title", []string{"tag1", "tag2"})
	e := h.GetByID(id)
	if e.Title != "new title" {
		t.Errorf("expected title 'new title', got %q", e.Title)
	}
	if len(e.Tags) != 2 || e.Tags[0] != "tag1" {
		t.Errorf("expected tags [tag1,tag2], got %v", e.Tags)
	}
}

func TestHistoryUpdateText(t *testing.T) {
	h := newTestHistory(t)
	h.Add("old text", 1.0, "en")
	id := h.All()[0].ID

	h.UpdateText(id, "new text content")
	e := h.GetByID(id)
	if e.Text != "new text content" {
		t.Errorf("expected 'new text content', got %q", e.Text)
	}
	if e.Title != "new text content" {
		t.Errorf("expected auto-title from new text, got %q", e.Title)
	}
}

func TestHistoryTags(t *testing.T) {
	h := newTestHistory(t)
	h.Add("a", 1.0, "en")
	h.Add("b", 1.0, "en")
	ids := h.All()
	h.UpdateEntry(ids[0].ID, "", []string{"work", "meeting"})
	h.UpdateEntry(ids[1].ID, "", []string{"meeting", "personal"})

	tags := h.Tags()
	if len(tags) != 3 {
		t.Errorf("expected 3 unique tags, got %d: %v", len(tags), tags)
	}
}

func TestHistoryRenameTag(t *testing.T) {
	h := newTestHistory(t)
	h.Add("a", 1.0, "en")
	h.Add("b", 1.0, "en")
	ids := h.All()
	h.UpdateEntry(ids[0].ID, "", []string{"old"})
	h.UpdateEntry(ids[1].ID, "", []string{"old", "other"})

	count := h.RenameTag("old", "new")
	if count != 2 {
		t.Errorf("expected 2 renames, got %d", count)
	}
	tags := h.Tags()
	for _, tag := range tags {
		if tag == "old" {
			t.Error("old tag still exists after rename")
		}
	}
}

func TestHistoryMerge(t *testing.T) {
	h := newTestHistory(t)
	h.Add("first text", 10.0, "en")
	h.Add("second text", 5.0, "en")
	ids := h.All()

	mergedID := h.Merge([]string{ids[0].ID, ids[1].ID})
	if mergedID == "" {
		t.Fatal("merge returned empty ID")
	}

	all := h.All()
	if len(all) != 1 {
		t.Fatalf("expected 1 entry after merge, got %d", len(all))
	}
	if all[0].Duration != 15.0 {
		t.Errorf("expected merged duration 15.0, got %f", all[0].Duration)
	}
	if all[0].Source != "merged" {
		t.Errorf("expected source 'merged', got %q", all[0].Source)
	}
}

func TestHistoryDuplicate(t *testing.T) {
	h := newTestHistory(t)
	h.Add("original", 1.0, "en")
	id := h.All()[0].ID
	h.UpdateEntry(id, "", []string{"important"})

	if !h.DuplicateEntry(id) {
		t.Error("duplicate returned false")
	}
	all := h.All()
	if len(all) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(all))
	}

	// Find the duplicate (the newer one)
	dup := all[0]
	if dup.ID == id {
		t.Error("duplicate should have new ID")
	}
	found := false
	for _, tag := range dup.Tags {
		if tag == "duplicated" {
			found = true
		}
	}
	if !found {
		t.Error("duplicate should have 'duplicated' tag")
	}
}

func TestHistoryAddSmart(t *testing.T) {
	h := newTestHistory(t)
	h.AddSmart("smart result", "en", []string{"auto"})
	all := h.All()
	if len(all) != 1 {
		t.Fatal("expected 1 entry")
	}
	if all[0].Source != "smart" {
		t.Errorf("expected source 'smart', got %q", all[0].Source)
	}
}

func TestHistoryCleanup(t *testing.T) {
	h := newTestHistory(t)
	for i := 0; i < 10; i++ {
		h.Add("entry", 1.0, "en")
	}
	// Pin one
	h.TogglePin(h.All()[0].ID)

	removed := h.Cleanup(5, 0, false)
	if removed != 5 {
		t.Errorf("expected 5 removed, got %d", removed)
	}
	remaining := h.All()
	if len(remaining) != 5 {
		t.Errorf("expected 5 remaining, got %d", len(remaining))
	}
	// Check pinned is still there
	pinnedFound := false
	for _, e := range remaining {
		if e.Pinned {
			pinnedFound = true
		}
	}
	if !pinnedFound {
		t.Error("pinned entry should survive cleanup")
	}
}

func TestHistoryGetAnalytics(t *testing.T) {
	h := newTestHistory(t)
	h.AddWithModel("test1", 30.0, 2.0, "en", "whisper-1", false)
	h.RecordDailyStats(30.0, 2.0, "test1", "whisper-1", false)
	h.AddWithModel("test2", 60.0, 1.5, "de", "whisper-base", true)
	h.RecordDailyStats(60.0, 1.5, "test2", "whisper-base", true)

	analytics := h.GetAnalytics(0)
	if analytics["totalEntries"].(int) != 2 {
		t.Errorf("expected 2 total entries, got %v", analytics["totalEntries"])
	}
	if analytics["localEntries"].(int) != 1 {
		t.Errorf("expected 1 local entry, got %v", analytics["localEntries"])
	}
	if analytics["apiEntries"].(int) != 1 {
		t.Errorf("expected 1 API entry, got %v", analytics["apiEntries"])
	}
}

func TestHistoryNilDB(t *testing.T) {
	h := &History{}
	// All methods should be safe with nil db
	h.Add("test", 1.0, "en")
	if h.All() != nil {
		t.Error("expected nil from All with nil db")
	}
	if h.Delete("x") {
		t.Error("expected false from Delete with nil db")
	}
	if h.TogglePin("x") {
		t.Error("expected false from TogglePin with nil db")
	}
	h.Close() // should not panic
}

func TestMigrateFromJSON(t *testing.T) {
	dir := t.TempDir()
	jsonData := `{"entries":[
		{"id":"abc123","text":"hello","title":"hello","timestamp":"2024-01-01T00:00:00Z","duration_sec":5,"language":"en","source":"dictation"},
		{"text":"no id","timestamp":"2024-01-02T00:00:00Z","duration_sec":3,"language":"de","category":"meeting"}
	]}`
	os.WriteFile(filepath.Join(dir, "history.json"), []byte(jsonData), 0600)

	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	createHistoryTables(db)

	err = migrateFromJSON(db, dir)
	if err != nil {
		t.Fatalf("migration failed: %v", err)
	}

	var count int
	db.QueryRow("SELECT COUNT(*) FROM history_entries").Scan(&count)
	if count != 2 {
		t.Fatalf("expected 2 migrated entries, got %d", count)
	}

	// Check that second entry got an ID and category was migrated to tags
	var id, tags, source string
	db.QueryRow("SELECT id, tags, source FROM history_entries WHERE text = 'no id'").Scan(&id, &tags, &source)
	if id == "" {
		t.Error("expected generated ID for entry without one")
	}
	if tags == "[]" || tags == "" {
		t.Error("expected category to be migrated to tags")
	}
	if source != "dictation" {
		t.Errorf("expected source 'dictation', got %q", source)
	}
}

func TestHistorySearch(t *testing.T) {
	h := newTestHistory(t)
	h.AddWithModel("The quick brown fox jumps over the lazy dog", 10.0, 1.0, "en", "whisper-1", false)
	h.AddWithModel("Die Katze sitzt auf der Matte", 5.0, 0.5, "de", "whisper-base", true)
	h.AddWithModel("Testing microphone input levels", 3.0, 0.3, "en", "whisper-1", false)

	// Basic search
	results := h.Search("fox")
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'fox', got %d", len(results))
	}
	if results[0].Language != "en" {
		t.Errorf("expected English entry, got %s", results[0].Language)
	}

	// Search matches title too (autoTitle derives from text)
	results = h.Search("Katze")
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'Katze', got %d", len(results))
	}

	// Search with no matches
	results = h.Search("nonexistent")
	if len(results) != 0 {
		t.Errorf("expected 0 results for 'nonexistent', got %d", len(results))
	}

	// Empty search returns nil
	results = h.Search("")
	if results != nil {
		t.Error("expected nil for empty search")
	}

	// Nil DB safety
	nilH := &History{}
	results = nilH.Search("test")
	if results != nil {
		t.Error("expected nil from Search with nil db")
	}

	// FTS5 OR query
	results = h.Search("fox OR Katze")
	if len(results) != 2 {
		t.Fatalf("expected 2 results for 'fox OR Katze', got %d", len(results))
	}

	// Search after text update — FTS stays in sync
	entry := h.All()[0] // newest
	h.UpdateText(entry.ID, "Updated content about elephants")
	results = h.Search("elephants")
	if len(results) != 1 {
		t.Fatalf("expected 1 result after update, got %d", len(results))
	}

	// Search after delete — FTS stays in sync
	h.Delete(entry.ID)
	results = h.Search("elephants")
	if len(results) != 0 {
		t.Errorf("expected 0 results after delete, got %d", len(results))
	}
}
