package main

import "strings"

// Search returns entries matching the FTS5 query, ordered by newest first.
// The query uses FTS5 syntax (e.g. "hello world", hello OR world, hello NOT world).
// Returns nil on empty query or error.
func (h *History) Search(query string) []HistoryEntry {
	if h.db == nil {
		return nil
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil
	}
	rows, err := h.db.Query(`SELECT `+allColumns+` FROM history_entries
		WHERE archived = 0 AND rowid IN (
			SELECT rowid FROM history_fts WHERE history_fts MATCH ?
			ORDER BY rank
		) ORDER BY timestamp DESC, rowid DESC`, query)
	if err != nil {
		logError("FTS search query: %v", err)
		return nil
	}
	defer rows.Close()
	entries := scanEntries(rows)
	h.fillProjectNames(entries)
	return entries
}

// Tags returns all unique tag names used across entries.
func (h *History) Tags() []string {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query("SELECT tags FROM history_entries WHERE tags != '[]' AND tags != ''")
	if err != nil {
		logError("Tags query: %v", err)
		return nil
	}
	defer rows.Close()

	seen := map[string]bool{}
	var result []string
	for rows.Next() {
		var tagsJSON string
		if err := rows.Scan(&tagsJSON); err != nil {
			continue
		}
		for _, tag := range unmarshalTags(tagsJSON) {
			if tag != "" && !seen[tag] {
				seen[tag] = true
				result = append(result, tag)
			}
		}
	}
	return result
}

// updateTagEntries finds entries matching tagName via LIKE pattern and applies
// the modifier function to each entry's tags, updating the database in a transaction.
func (h *History) updateTagEntries(label, tagName string, modifier func(tags []string) []string) int {
	if h.db == nil {
		return 0
	}
	h.invalidateCache()

	escaped := strings.NewReplacer("%", "\\%", "_", "\\_").Replace(tagName)
	pattern := `%"` + escaped + `"%`

	tx, err := h.db.Begin()
	if err != nil {
		logError("%s begin tx: %v", label, err)
		return 0
	}
	defer tx.Rollback()

	rows, err := tx.Query("SELECT id, tags FROM history_entries WHERE tags LIKE ? ESCAPE '\\'", pattern)
	if err != nil {
		logError("%s query: %v", label, err)
		return 0
	}

	type idTags struct {
		id   string
		tags []string
	}
	var updates []idTags
	for rows.Next() {
		var id, tagsJSON string
		if err := rows.Scan(&id, &tagsJSON); err != nil {
			continue
		}
		newTags := modifier(unmarshalTags(tagsJSON))
		if newTags != nil {
			updates = append(updates, idTags{id, newTags})
		}
	}
	rows.Close()

	count := 0
	for _, u := range updates {
		if _, err := tx.Exec("UPDATE history_entries SET tags = ? WHERE id = ?", marshalTags(u.tags), u.id); err != nil {
			logError("%s update %s: %v", label, u.id, err)
			return 0
		}
		count++
	}

	if err := tx.Commit(); err != nil {
		logError("%s commit: %v", label, err)
		return 0
	}
	return count
}

// RenameTag renames a tag across all entries that have it.
func (h *History) RenameTag(oldName, newName string) int {
	return h.updateTagEntries("RenameTag", oldName, func(tags []string) []string {
		for j, tag := range tags {
			if tag == oldName {
				tags[j] = newName
				return tags
			}
		}
		return nil
	})
}

// DeleteTag removes a tag from all entries that have it.
func (h *History) DeleteTag(tagName string) int {
	return h.updateTagEntries("DeleteTag", tagName, func(tags []string) []string {
		filtered := make([]string, 0, len(tags))
		for _, tag := range tags {
			if tag != tagName {
				filtered = append(filtered, tag)
			}
		}
		if len(filtered) < len(tags) {
			return filtered
		}
		return nil
	})
}
