package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

const historyDBFile = "history.db"

// initHistoryDB opens (or creates) the SQLite database and ensures tables exist.
func initHistoryDB() (*sql.DB, error) {
	dir, err := configDir()
	if err != nil {
		return nil, fmt.Errorf("config dir: %w", err)
	}

	dbPath := filepath.Join(dir, historyDBFile)
	db, err := sql.Open("sqlite", dbPath+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}

	if err := createHistoryTables(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("create tables: %w", err)
	}

	// Check DB integrity and repair FTS if needed
	repairDBIfNeeded(db)

	// Migrate from JSON if the DB is empty and JSON file exists
	if err := migrateFromJSON(db, dir); err != nil {
		logWarn("JSON migration failed: %v", err)
		// Non-fatal — continue with whatever data we have
	}

	return db, nil
}

// repairDBIfNeeded checks FTS5 index integrity and rebuilds if corrupted.
func repairDBIfNeeded(db *sql.DB) {
	// FTS5-specific integrity check (PRAGMA integrity_check does NOT cover FTS5 virtual tables)
	_, err := db.Exec("INSERT INTO history_fts(history_fts) VALUES('integrity-check')")
	if err != nil {
		logWarn("FTS5 integrity check failed: %v — rebuilding FTS index", err)
		rebuildFTS(db)
		return
	}
	logDebug("FTS5 integrity check passed")
}

// rebuildFTS drops and recreates the FTS5 virtual table and triggers.
func rebuildFTS(db *sql.DB) {
	logInfo("Rebuilding FTS index...")
	// Drop triggers first, then the FTS table
	for _, stmt := range []string{
		"DROP TRIGGER IF EXISTS history_fts_ai",
		"DROP TRIGGER IF EXISTS history_fts_ad",
		"DROP TRIGGER IF EXISTS history_fts_au",
		"DROP TABLE IF EXISTS history_fts",
	} {
		if _, err := db.Exec(stmt); err != nil {
			logWarn("FTS cleanup (%s): %v", stmt, err)
		}
	}
	// Recreate FTS tables (this also repopulates from history_entries)
	if err := createFTSTables(db); err != nil {
		logError("FTS rebuild failed: %v", err)
	} else {
		logInfo("FTS index rebuilt successfully")
	}
}

func createHistoryTables(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS history_entries (
			id            TEXT PRIMARY KEY,
			text          TEXT NOT NULL DEFAULT '',
			title         TEXT NOT NULL DEFAULT '',
			timestamp     TEXT NOT NULL,
			duration_sec  REAL NOT NULL DEFAULT 0,
			processing_duration_sec REAL NOT NULL DEFAULT 0,
			language      TEXT NOT NULL DEFAULT '',
			tags          TEXT NOT NULL DEFAULT '[]',
			pinned        INTEGER NOT NULL DEFAULT 0,
			source        TEXT NOT NULL DEFAULT 'dictation',
			model         TEXT NOT NULL DEFAULT '',
			is_local      INTEGER NOT NULL DEFAULT 0,
			cost_usd      REAL NOT NULL DEFAULT 0
		);

		CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history_entries(timestamp);
		CREATE INDEX IF NOT EXISTS idx_history_pinned ON history_entries(pinned);
	`)
	if err != nil {
		return err
	}
	return createFTSTables(db)
}

// createFTSTables creates the FTS5 virtual table and sync triggers.
// Uses external-content FTS5 so data lives only in history_entries.
func createFTSTables(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
			title, text, tags,
			content='history_entries',
			content_rowid='rowid'
		);

		-- Triggers keep FTS in sync with the content table
		CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries BEGIN
			INSERT INTO history_fts(rowid, title, text, tags)
			VALUES (new.rowid, new.title, new.text, new.tags);
		END;

		CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries BEGIN
			INSERT INTO history_fts(history_fts, rowid, title, text, tags)
			VALUES ('delete', old.rowid, old.title, old.text, old.tags);
		END;

		CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries BEGIN
			INSERT INTO history_fts(history_fts, rowid, title, text, tags)
			VALUES ('delete', old.rowid, old.title, old.text, old.tags);
			INSERT INTO history_fts(rowid, title, text, tags)
			VALUES (new.rowid, new.title, new.text, new.tags);
		END;
	`)
	if err != nil {
		return fmt.Errorf("create FTS tables: %w", err)
	}

	// Populate FTS from existing data if FTS is empty but entries exist
	var ftsCount, entryCount int
	db.QueryRow("SELECT COUNT(*) FROM history_fts").Scan(&ftsCount)
	db.QueryRow("SELECT COUNT(*) FROM history_entries").Scan(&entryCount)
	if ftsCount == 0 && entryCount > 0 {
		if _, err := db.Exec(`INSERT INTO history_fts(rowid, title, text, tags)
			SELECT rowid, title, text, tags FROM history_entries`); err != nil {
			logWarn("FTS initial population failed: %v", err)
		} else {
			logInfo("Populated FTS index with %d entries", entryCount)
		}
	}

	return nil
}

// migrateFromJSON imports entries from history.json into SQLite if the DB is empty.
func migrateFromJSON(db *sql.DB, dir string) error {
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM history_entries").Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil // already have data
	}

	jsonPath := filepath.Join(dir, "history.json")
	data, err := os.ReadFile(jsonPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // no JSON file — fresh install
		}
		return fmt.Errorf("read history.json: %w", err)
	}

	var legacy struct {
		Entries []HistoryEntry `json:"entries"`
	}
	if err := json.Unmarshal(data, &legacy); err != nil {
		return fmt.Errorf("parse JSON: %w", err)
	}
	if len(legacy.Entries) == 0 {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`INSERT OR IGNORE INTO history_entries
		(id, text, title, timestamp, duration_sec, processing_duration_sec,
		 language, tags, pinned, source, model, is_local, cost_usd)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for i := range legacy.Entries {
		e := &legacy.Entries[i]
		// Apply same migrations as old LoadHistory
		if e.ID == "" {
			e.ID = generateID()
		}
		if e.Title == "" && e.Text != "" {
			e.Title = autoTitle(e.Text)
		}
		if e.Source == "" {
			e.Source = "dictation"
		}
		if len(e.Tags) == 0 && e.Category != "" {
			e.Tags = []string{e.Category}
		}

		tagsJSON := marshalTags(e.Tags)
		pinned := 0
		if e.Pinned {
			pinned = 1
		}
		isLocal := 0
		if e.IsLocal {
			isLocal = 1
		}

		if _, err := stmt.Exec(e.ID, e.Text, e.Title, e.Timestamp,
			e.Duration, e.ProcessingDuration, e.Language, tagsJSON,
			pinned, e.Source, e.Model, isLocal, e.CostUSD); err != nil {
			return fmt.Errorf("insert entry %s: %w", e.ID, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	logInfo("Migrated %d entries from history.json to SQLite", len(legacy.Entries))

	// Rename old file as backup
	backupPath := jsonPath + ".bak"
	if err := os.Rename(jsonPath, backupPath); err != nil {
		logWarn("Could not rename history.json to .bak: %v", err)
	}

	return nil
}

// marshalTags converts a string slice to JSON array string.
func marshalTags(tags []string) string {
	if len(tags) == 0 {
		return "[]"
	}
	data, err := json.Marshal(tags)
	if err != nil {
		return "[]"
	}
	return string(data)
}

// unmarshalTags converts a JSON array string to string slice.
func unmarshalTags(s string) []string {
	if s == "" || s == "[]" {
		return nil
	}
	var tags []string
	if err := json.Unmarshal([]byte(s), &tags); err != nil {
		// Fallback: try comma-separated
		return strings.Split(s, ",")
	}
	return tags
}

// scanEntry scans a row into a HistoryEntry.
func scanEntry(row interface{ Scan(...interface{}) error }) (HistoryEntry, error) {
	var e HistoryEntry
	var tagsJSON string
	var pinned, isLocal int
	err := row.Scan(&e.ID, &e.Text, &e.Title, &e.Timestamp,
		&e.Duration, &e.ProcessingDuration, &e.Language, &tagsJSON,
		&pinned, &e.Source, &e.Model, &isLocal, &e.CostUSD)
	if err != nil {
		return e, err
	}
	e.Tags = unmarshalTags(tagsJSON)
	e.Pinned = pinned != 0
	e.IsLocal = isLocal != 0
	return e, nil
}

// allColumns is the column list for SELECT queries on history_entries.
const allColumns = `id, text, title, timestamp, duration_sec, processing_duration_sec,
	language, tags, pinned, source, model, is_local, cost_usd`
