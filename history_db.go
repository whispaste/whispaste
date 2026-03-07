package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// isFTSCorruptionError returns true if the error indicates FTS5 or DB-level corruption
// that may be resolved by rebuilding the FTS index.
func isFTSCorruptionError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "malformed") || strings.Contains(msg, "corrupt")
}

// execWithFTSRepair runs a write query. If it fails with FTS corruption,
// rebuilds the FTS index and retries once.
func execWithFTSRepair(db *sql.DB, query string, args ...interface{}) (sql.Result, error) {
	res, err := db.Exec(query, args...)
	if err != nil && isFTSCorruptionError(err) {
		logWarn("FTS5 corruption detected on write, rebuilding index: %v", err)
		rebuildFTS(db)
		// Retry once after rebuild
		res, err = db.Exec(query, args...)
	}
	return res, err
}

const historyDBFile = "history.db"

// currentSchemaVersion tracks the DB schema. Version history:
// 1 = external-content FTS5 (value-matching delete triggers — broken with modernc.org/sqlite)
// 2 = regular FTS5 (rowid-based triggers)
// 3 = daily_stats aggregation table
const currentSchemaVersion = 4

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

	// For existing DBs, run migration FIRST so new columns (e.g. project_id)
	// exist before createHistoryTables tries to create indexes on them.
	// For fresh DBs, create tables first so migrations can reference them.
	var tableExists int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='history_entries'`).Scan(&tableExists); err != nil {
		db.Close()
		return nil, fmt.Errorf("check history_entries existence: %w", err)
	}

	if tableExists > 0 {
		if err := ensureSchemaVersion(db); err != nil {
			logWarn("Schema migration: %v", err)
		}
		if err := createHistoryTables(db); err != nil {
			db.Close()
			return nil, fmt.Errorf("create tables: %w", err)
		}
	} else {
		if err := createHistoryTables(db); err != nil {
			db.Close()
			return nil, fmt.Errorf("create tables: %w", err)
		}
		if err := ensureSchemaVersion(db); err != nil {
			logWarn("Schema migration: %v", err)
		}
	}

	// Check DB integrity and repair FTS if needed
	repairDBIfNeeded(db)

	// Post-repair verification: if DB is still corrupted, rename and start fresh
	var result string
	if err := db.QueryRow("PRAGMA integrity_check(1)").Scan(&result); err != nil || result != "ok" {
		logError("Database still corrupted after repair — renaming and starting fresh")
		db.Close()
		backupPath := dbPath + ".corrupt"
		if err := os.Rename(dbPath, backupPath); err != nil {
			logWarn("Cannot rename corrupted DB: %v", err)
		} else {
			logInfo("Corrupted DB saved as %s", backupPath)
		}
		// Reopen fresh DB
		db, err = sql.Open("sqlite", dbPath+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
		if err != nil {
			return nil, fmt.Errorf("reopen fresh db: %w", err)
		}
		if err := createHistoryTables(db); err != nil {
			db.Close()
			return nil, fmt.Errorf("create tables on fresh db: %w", err)
		}
		db.Exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER)")
		db.Exec("INSERT INTO schema_version (version) VALUES (?)", currentSchemaVersion)
	}

	// Migrate from JSON if the DB is empty and JSON file exists
	if err := migrateFromJSON(db, dir); err != nil {
		logWarn("JSON migration failed: %v", err)
		// Non-fatal — continue with whatever data we have
	}

	return db, nil
}

// repairDBIfNeeded checks main database and FTS5 index integrity,
// attempting recovery if corruption is detected.
func repairDBIfNeeded(db *sql.DB) {
	// 1. Main database integrity check
	var result string
	if err := db.QueryRow("PRAGMA integrity_check(1)").Scan(&result); err != nil {
		logError("PRAGMA integrity_check failed: %v", err)
		repairMainDB(db)
		return
	}
	if result != "ok" {
		logError("Database integrity check: %s", result)
		repairMainDB(db)
		return
	}

	// 2. FTS5-specific integrity check (PRAGMA integrity_check does NOT cover FTS5 virtual tables)
	_, err := db.Exec("INSERT INTO history_fts(history_fts) VALUES('integrity-check')")
	if err != nil {
		logWarn("FTS5 integrity check failed: %v — rebuilding FTS index", err)
		rebuildFTS(db)
		return
	}
	logDebug("FTS5 integrity check passed")
}

// repairMainDB attempts to salvage data from a corrupted database by exporting
// readable rows and rebuilding the schema.
func repairMainDB(db *sql.DB) {
	logInfo("Attempting database repair...")

	// Try to read whatever entries we can from the corrupted DB
	rows, err := db.Query("SELECT " + allColumns + " FROM history_entries")
	if err != nil {
		logError("Cannot read entries from corrupted DB: %v — database will be recreated empty", err)
		recreateDB(db)
		return
	}
	defer rows.Close()

	var salvaged []HistoryEntry
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			logWarn("Skipping corrupted row: %v", err)
			continue
		}
		salvaged = append(salvaged, e)
	}
	if err := rows.Err(); err != nil {
		logWarn("Row iteration error during salvage: %v", err)
	}
	logInfo("Salvaged %d entries from corrupted database", len(salvaged))

	recreateDB(db)

	// Re-insert salvaged entries
	if len(salvaged) > 0 {
		reimportEntries(db, salvaged)
	}
}

// recreateDB drops and recreates all tables (main + FTS5).
func recreateDB(db *sql.DB) {
	for _, stmt := range []string{
		"DROP TRIGGER IF EXISTS history_fts_ai",
		"DROP TRIGGER IF EXISTS history_fts_ad",
		"DROP TRIGGER IF EXISTS history_fts_au",
		"DROP TABLE IF EXISTS history_fts",
		"DROP TABLE IF EXISTS history_entries",
		"DROP TABLE IF EXISTS daily_stats",
		"DROP TABLE IF EXISTS schema_version",
	} {
		if _, err := db.Exec(stmt); err != nil {
			logWarn("DB cleanup (%s): %v", stmt, err)
		}
	}
	if err := createHistoryTables(db); err != nil {
		logError("Failed to recreate tables: %v", err)
		return
	}
	// Recreate daily_stats
	db.Exec(`CREATE TABLE IF NOT EXISTS daily_stats (
		date TEXT NOT NULL, model TEXT NOT NULL, is_local INTEGER NOT NULL,
		count INTEGER NOT NULL DEFAULT 0, total_duration_sec REAL NOT NULL DEFAULT 0,
		total_processing_sec REAL NOT NULL DEFAULT 0, total_words INTEGER NOT NULL DEFAULT 0,
		total_cost_usd REAL NOT NULL DEFAULT 0, dur_under_15s INTEGER NOT NULL DEFAULT 0,
		dur_15_30s INTEGER NOT NULL DEFAULT 0, dur_30_60s INTEGER NOT NULL DEFAULT 0,
		dur_1_3m INTEGER NOT NULL DEFAULT 0, dur_over_3m INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (date, model, is_local))`)
	// Set schema version
	db.Exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER)")
	db.Exec("DELETE FROM schema_version")
	db.Exec("INSERT INTO schema_version (version) VALUES (?)", currentSchemaVersion)
	logInfo("Database tables recreated successfully")
}

// reimportEntries inserts salvaged entries into a fresh database.
func reimportEntries(db *sql.DB, entries []HistoryEntry) {
	tx, err := db.Begin()
	if err != nil {
		logError("reimport begin tx: %v", err)
		return
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`INSERT OR IGNORE INTO history_entries
		(id, text, title, timestamp, duration_sec, processing_duration_sec,
		 language, tags, pinned, source, model, is_local, cost_usd)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
	if err != nil {
		logError("reimport prepare: %v", err)
		return
	}
	defer stmt.Close()

	imported := 0
	for i := range entries {
		e := &entries[i]
		pinned, isLocal := 0, 0
		if e.Pinned {
			pinned = 1
		}
		if e.IsLocal {
			isLocal = 1
		}
		if _, err := stmt.Exec(e.ID, e.Text, e.Title, e.Timestamp,
			e.Duration, e.ProcessingDuration, e.Language, marshalTags(e.Tags),
			pinned, e.Source, e.Model, isLocal, e.CostUSD); err != nil {
			logWarn("reimport entry %s: %v", e.ID, err)
			continue
		}
		imported++
	}
	if err := tx.Commit(); err != nil {
		logError("reimport commit: %v", err)
		return
	}
	logInfo("Re-imported %d/%d entries after repair", imported, len(entries))
}

// rebuildFTS rebuilds the FTS5 index. For regular FTS5, tries the fast 'rebuild'
// command first, falling back to full drop+recreate if that fails.
func rebuildFTS(db *sql.DB) {
	logInfo("Rebuilding FTS index...")

	// Fast path: regular FTS5 supports 'rebuild' natively
	_, err := db.Exec("INSERT INTO history_fts(history_fts) VALUES('rebuild')")
	if err == nil {
		logInfo("FTS index rebuilt successfully (fast rebuild)")
		return
	}
	logWarn("FTS fast rebuild failed: %v — doing full drop+recreate", err)

	// Slow path: drop triggers + table, then recreate
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

// ensureSchemaVersion checks the DB schema version and runs migrations if needed.
func ensureSchemaVersion(db *sql.DB) error {
	_, err := db.Exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER)")
	if err != nil {
		return fmt.Errorf("create schema_version table: %w", err)
	}

	var version int
	err = db.QueryRow("SELECT version FROM schema_version LIMIT 1").Scan(&version)
	if err != nil {
		if err == sql.ErrNoRows {
			// No row yet — treat as version 0 (pre-versioning / external-content FTS5)
			version = 0
		} else {
			return fmt.Errorf("check schema version: %w", err)
		}
	}

	if version >= currentSchemaVersion {
		return nil
	}

	logInfo("Migrating schema from version %d to %d", version, currentSchemaVersion)

	for version < currentSchemaVersion {
		switch version {
		case 0, 1:
			// Migration to v2: switch from external-content FTS5 to regular FTS5
			for _, stmt := range []string{
				"DROP TRIGGER IF EXISTS history_fts_ai",
				"DROP TRIGGER IF EXISTS history_fts_ad",
				"DROP TRIGGER IF EXISTS history_fts_au",
				"DROP TABLE IF EXISTS history_fts",
			} {
				if _, err := db.Exec(stmt); err != nil {
					logWarn("Schema migration cleanup (%s): %v", stmt, err)
				}
			}
			if err := createFTSTables(db); err != nil {
				return fmt.Errorf("recreate FTS tables: %w", err)
			}
			version = 2

		case 2:
			// Migration to v3: add daily_stats aggregation table (falls through from above)
			if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS daily_stats (
				date                  TEXT NOT NULL,
				model                 TEXT NOT NULL,
				is_local              INTEGER NOT NULL,
				count                 INTEGER NOT NULL DEFAULT 0,
				total_duration_sec    REAL NOT NULL DEFAULT 0,
				total_processing_sec  REAL NOT NULL DEFAULT 0,
				total_words           INTEGER NOT NULL DEFAULT 0,
				total_cost_usd        REAL NOT NULL DEFAULT 0,
				dur_under_15s         INTEGER NOT NULL DEFAULT 0,
				dur_15_30s            INTEGER NOT NULL DEFAULT 0,
				dur_30_60s            INTEGER NOT NULL DEFAULT 0,
				dur_1_3m              INTEGER NOT NULL DEFAULT 0,
				dur_over_3m           INTEGER NOT NULL DEFAULT 0,
				PRIMARY KEY (date, model, is_local)
			)`); err != nil {
				return fmt.Errorf("create daily_stats table: %w", err)
			}

			// Backfill from existing history_entries
			if _, err := db.Exec(`INSERT OR IGNORE INTO daily_stats
				(date, model, is_local, count, total_duration_sec, total_processing_sec,
				 total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m)
				SELECT
					substr(timestamp, 1, 10) as date,
					COALESCE(NULLIF(model, ''), 'whisper-1') as model,
					COALESCE(is_local, 0) as is_local,
					COUNT(*) as count,
					COALESCE(SUM(duration_sec), 0) as total_duration_sec,
					COALESCE(SUM(processing_duration_sec), 0) as total_processing_sec,
					COALESCE(SUM(LENGTH(text) - LENGTH(REPLACE(text, ' ', '')) + 1), 0) as total_words,
					COALESCE(SUM(cost_usd), 0) as total_cost_usd,
					SUM(CASE WHEN duration_sec < 15 THEN 1 ELSE 0 END),
					SUM(CASE WHEN duration_sec >= 15 AND duration_sec < 30 THEN 1 ELSE 0 END),
					SUM(CASE WHEN duration_sec >= 30 AND duration_sec < 60 THEN 1 ELSE 0 END),
					SUM(CASE WHEN duration_sec >= 60 AND duration_sec < 180 THEN 1 ELSE 0 END),
					SUM(CASE WHEN duration_sec >= 180 THEN 1 ELSE 0 END)
				FROM history_entries
				GROUP BY substr(timestamp, 1, 10), COALESCE(NULLIF(model, ''), 'whisper-1'), COALESCE(is_local, 0)`); err != nil {
				logWarn("daily_stats backfill: %v", err)
			}
			version = 3

		case 3:
			// Migration to v4: add projects table and project_id column
			if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS projects (
				id         TEXT PRIMARY KEY,
				name       TEXT NOT NULL UNIQUE,
				created_at TEXT NOT NULL
			)`); err != nil {
				return fmt.Errorf("create projects table: %w", err)
			}
			// SQLite: ALTER TABLE can only add one column at a time
			if _, err := db.Exec(`ALTER TABLE history_entries ADD COLUMN project_id TEXT NOT NULL DEFAULT ''`); err != nil {
				// Column may already exist from a partial migration
				if !strings.Contains(err.Error(), "duplicate column") {
					return fmt.Errorf("add project_id column: %w", err)
				}
			}
			if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_history_project ON history_entries(project_id)`); err != nil {
				logWarn("create project_id index: %v", err)
			}
			version = 4

		default:
			return fmt.Errorf("unexpected schema version %d, cannot migrate", version)
		}
	}

	// Upsert schema version
	if _, err := db.Exec("DELETE FROM schema_version"); err != nil {
		return fmt.Errorf("update schema version: %w", err)
	}
	if _, err := db.Exec("INSERT INTO schema_version (version) VALUES (?)", currentSchemaVersion); err != nil {
		return fmt.Errorf("update schema version: %w", err)
	}
	logInfo("Schema migration to version %d complete", currentSchemaVersion)
	return nil
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
			cost_usd      REAL NOT NULL DEFAULT 0,
			project_id    TEXT NOT NULL DEFAULT ''
		);

		CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history_entries(timestamp);
		CREATE INDEX IF NOT EXISTS idx_history_pinned ON history_entries(pinned);
		CREATE INDEX IF NOT EXISTS idx_history_project ON history_entries(project_id);

		CREATE TABLE IF NOT EXISTS projects (
			id         TEXT PRIMARY KEY,
			name       TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL
		);

		CREATE TABLE IF NOT EXISTS daily_stats (
			date TEXT NOT NULL, model TEXT NOT NULL, is_local INTEGER NOT NULL,
			count INTEGER NOT NULL DEFAULT 0, total_duration_sec REAL NOT NULL DEFAULT 0,
			total_processing_sec REAL NOT NULL DEFAULT 0, total_words INTEGER NOT NULL DEFAULT 0,
			total_cost_usd REAL NOT NULL DEFAULT 0, dur_under_15s INTEGER NOT NULL DEFAULT 0,
			dur_15_30s INTEGER NOT NULL DEFAULT 0, dur_30_60s INTEGER NOT NULL DEFAULT 0,
			dur_1_3m INTEGER NOT NULL DEFAULT 0, dur_over_3m INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (date, model, is_local));
	`)
	if err != nil {
		return err
	}
	return createFTSTables(db)
}

// createFTSTables creates the FTS5 virtual table and sync triggers.
// Uses regular (not external-content) FTS5 for reliable rowid-based operations.
func createFTSTables(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
			title, text, tags
		);

		-- Triggers keep FTS in sync with the content table
		CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries BEGIN
			INSERT INTO history_fts(rowid, title, text, tags)
			VALUES (new.rowid, new.title, new.text, new.tags);
		END;

		CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries BEGIN
			DELETE FROM history_fts WHERE rowid = old.rowid;
		END;

		CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries BEGIN
			DELETE FROM history_fts WHERE rowid = old.rowid;
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
		&pinned, &e.Source, &e.Model, &isLocal, &e.CostUSD, &e.ProjectID)
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
	language, tags, pinned, source, model, is_local, cost_usd, project_id`

// RecordDailyStats upserts a row in daily_stats for the current transcription.
func (h *History) RecordDailyStats(durationSec, processingSec float64, text string, model string, isLocal bool) {
	if h.db == nil {
		return
	}
	date := time.Now().Format("2006-01-02")
	words := len(strings.Fields(text))

	cost := 0.0
	if !isLocal {
		cost = durationSec / 60.0 * 0.006
	}

	isLocalInt := 0
	if isLocal {
		isLocalInt = 1
	}

	if model == "" {
		model = "whisper-1"
	}

	_, err := h.db.Exec(`
		INSERT INTO daily_stats (date, model, is_local, count, total_duration_sec, total_processing_sec, total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m)
		VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(date, model, is_local) DO UPDATE SET
			count = count + 1,
			total_duration_sec = total_duration_sec + excluded.total_duration_sec,
			total_processing_sec = total_processing_sec + excluded.total_processing_sec,
			total_words = total_words + excluded.total_words,
			total_cost_usd = total_cost_usd + excluded.total_cost_usd,
			dur_under_15s = dur_under_15s + excluded.dur_under_15s,
			dur_15_30s = dur_15_30s + excluded.dur_15_30s,
			dur_30_60s = dur_30_60s + excluded.dur_30_60s,
			dur_1_3m = dur_1_3m + excluded.dur_1_3m,
			dur_over_3m = dur_over_3m + excluded.dur_over_3m`,
		date, model, isLocalInt, durationSec, processingSec, words, cost,
		boolToInt(durationSec < 15),
		boolToInt(durationSec >= 15 && durationSec < 30),
		boolToInt(durationSec >= 30 && durationSec < 60),
		boolToInt(durationSec >= 60 && durationSec < 180),
		boolToInt(durationSec >= 180),
	)
	if err != nil {
		logWarn("RecordDailyStats error: %v", err)
	}
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
