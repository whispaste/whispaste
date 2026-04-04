package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/audiocache"
)

// CreateProject creates a new project and returns it.
func (h *History) CreateProject(name string) (Project, error) {
	if h.db == nil {
		return Project{}, fmt.Errorf("database not initialized")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return Project{}, fmt.Errorf("project name cannot be empty")
	}
	p := Project{
		ID:        generateID(),
		Name:      name,
		CreatedAt: time.Now().Format(time.RFC3339),
	}
	_, err := h.db.Exec("INSERT INTO projects (id, name, created_at) VALUES (?, ?, ?)",
		p.ID, p.Name, p.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint") {
			return Project{}, fmt.Errorf("project '%s' already exists", name)
		}
		return Project{}, fmt.Errorf("create project: %w", err)
	}
	logInfo("Project created: %s (%s)", p.Name, p.ID)
	return p, nil
}

// RenameProject renames a project.
func (h *History) RenameProject(id, newName string) error {
	if h.db == nil {
		return fmt.Errorf("database not initialized")
	}
	newName = strings.TrimSpace(newName)
	if newName == "" {
		return fmt.Errorf("project name cannot be empty")
	}
	res, err := h.db.Exec("UPDATE projects SET name = ? WHERE id = ?", newName, id)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint") {
			return fmt.Errorf("project '%s' already exists", newName)
		}
		return fmt.Errorf("rename project: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("project not found")
	}
	logInfo("Project renamed to '%s' (%s)", newName, id)
	return nil
}

// DeleteProject removes a project. If deleteEntries is true, all entries
// in the project are deleted; otherwise they are unassigned.
func (h *History) DeleteProject(id string, deleteEntries bool) error {
	if h.db == nil {
		return fmt.Errorf("database not initialized")
	}
	tx, err := h.db.Begin()
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	if deleteEntries {
		// Delete cached audio for entries in this project
		rows, err := tx.Query("SELECT id FROM history_entries WHERE project_id = ?", id)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var entryID string
				if err := rows.Scan(&entryID); err == nil {
					audiocache.Delete(entryID)
				}
			}
		}
		if _, err := tx.Exec("DELETE FROM history_entries WHERE project_id = ?", id); err != nil {
			return fmt.Errorf("delete project entries: %w", err)
		}
	} else {
		if _, err := tx.Exec("UPDATE history_entries SET project_id = '' WHERE project_id = ?", id); err != nil {
			return fmt.Errorf("unassign project entries: %w", err)
		}
	}

	res, err := tx.Exec("DELETE FROM projects WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete project: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("project not found")
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	logInfo("Project deleted: %s (deleteEntries=%v)", id, deleteEntries)
	return nil
}

// ListProjects returns all projects with their entry counts.
func (h *History) ListProjects() []Project {
	if h.db == nil {
		return nil
	}
	rows, err := h.db.Query(`
		SELECT p.id, p.name, p.created_at, COUNT(e.id) as entry_count
		FROM projects p
		LEFT JOIN history_entries e ON e.project_id = p.id AND e.deleted_at IS NULL
		GROUP BY p.id, p.name, p.created_at
		ORDER BY p.name COLLATE NOCASE`)
	if err != nil {
		logError("ListProjects: %v", err)
		return nil
	}
	defer rows.Close()

	var projects []Project
	for rows.Next() {
		var p Project
		if err := rows.Scan(&p.ID, &p.Name, &p.CreatedAt, &p.Count); err != nil {
			logError("ListProjects scan: %v", err)
			continue
		}
		projects = append(projects, p)
	}
	return projects
}

// SetEntryProject assigns an entry to a project (or unassigns with projectID="").
func (h *History) SetEntryProject(entryID, projectID string) error {
	if h.db == nil {
		return fmt.Errorf("database not initialized")
	}
	// Validate project exists if assigning
	if projectID != "" {
		var exists int
		err := h.db.QueryRow("SELECT COUNT(*) FROM projects WHERE id = ?", projectID).Scan(&exists)
		if err != nil || exists == 0 {
			return fmt.Errorf("project not found")
		}
	}
	_, err := execWithFTSRepair(h.db, "UPDATE history_entries SET project_id = ? WHERE id = ?", projectID, entryID)
	if err != nil {
		return fmt.Errorf("set entry project: %w", err)
	}
	return nil
}

// SetEntriesProject assigns multiple entries to a project (bulk operation).
func (h *History) SetEntriesProject(entryIDs []string, projectID string) error {
	if h.db == nil {
		return fmt.Errorf("database not initialized")
	}
	if len(entryIDs) == 0 {
		return nil
	}
	// Validate project exists if assigning
	if projectID != "" {
		var exists int
		err := h.db.QueryRow("SELECT COUNT(*) FROM projects WHERE id = ?", projectID).Scan(&exists)
		if err != nil || exists == 0 {
			return fmt.Errorf("project not found")
		}
	}
	tx, err := h.db.Begin()
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()
	for _, id := range entryIDs {
		if _, err := tx.Exec("UPDATE history_entries SET project_id = ? WHERE id = ?", projectID, id); err != nil {
			return fmt.Errorf("set entry project: %w", err)
		}
	}
	return tx.Commit()
}

// fillProjectNames populates the ProjectName field for entries that have a ProjectID.
func (h *History) fillProjectNames(entries []HistoryEntry) {
	if h.db == nil || len(entries) == 0 {
		return
	}
	names := make(map[string]string)
	rows, err := h.db.Query("SELECT id, name FROM projects")
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err == nil {
			names[id] = name
		}
	}
	for i := range entries {
		if entries[i].ProjectID != "" {
			entries[i].ProjectName = names[entries[i].ProjectID]
		}
	}
}
