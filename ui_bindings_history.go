package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/whispaste/whispaste/internal/audiocache"
	"github.com/whispaste/whispaste/internal/export"
	"github.com/whispaste/whispaste/internal/models"
	"github.com/whispaste/whispaste/internal/stats"

	webview "github.com/webview/webview_go"
)

// bindHistoryHandlers registers history, entry CRUD, tag, project, export, and analytics JS bindings.
func bindHistoryHandlers(w webview.WebView, cfg *Config, history *History, usageStats *stats.UsageStats, onCapture func()) {

	w.Bind("getEntries", func() (string, error) {
		entries := history.All()
		data, err := json.Marshal(entries)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("searchEntries", func(query string) (string, error) {
		entries := history.Search(query)
		if entries == nil {
			return "[]", nil
		}
		data, err := json.Marshal(entries)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("getCategories", func() (string, error) {
		tags := history.Tags()
		data, err := json.Marshal(tags)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("deleteEntry", func(id string) bool {
		return history.Delete(id)
	})

	w.Bind("hasAudio", func(id string) bool {
		return audiocache.Has(id)
	})

	w.Bind("getAudioBase64", func(id string) string {
		data, err := audiocache.Load(id)
		if err != nil {
			logWarn("Load audio for playback: %v", err)
			return ""
		}
		const maxPlaybackSize = 50 * 1024 * 1024
		if len(data) > maxPlaybackSize {
			logWarn("Audio file too large for playback: %d bytes", len(data))
			return ""
		}
		encoded := base64Encode(data)
		return "data:audio/wav;base64," + encoded
	})

	w.Bind("getAudioCount", func(id string) int {
		return audiocache.AudioCount(id)
	})

	w.Bind("getAudioBase64ByIndex", func(id string, idx int) string {
		data, err := audiocache.LoadByIndex(id, idx)
		if err != nil {
			logWarn("Load audio index %d for %s: %v", idx, id, err)
			return ""
		}
		const maxPlaybackSize = 50 * 1024 * 1024
		if len(data) > maxPlaybackSize {
			logWarn("Audio file too large for playback: %d bytes", len(data))
			return ""
		}
		encoded := base64Encode(data)
		return "data:audio/wav;base64," + encoded
	})

	w.Bind("reTranscribe", func(id string) map[string]interface{} {
		entry := history.GetByID(id)
		if entry == nil {
			return map[string]interface{}{"ok": false, "error": "Entry not found"}
		}
		wavData, err := audiocache.Load(id)
		if err != nil {
			return map[string]interface{}{"ok": false, "error": "No cached audio"}
		}

		apiKey := cfg.GetAPIKey()
		endpoint := cfg.GetAPIEndpoint()
		lang := cfg.GetTranscriptionLanguage()
		useLocal := cfg.GetActiveModelLocal()

		cfg.mu.RLock()
		model := cfg.Model
		cfg.mu.RUnlock()

		var text string
		if useLocal {
			if len(wavData) <= 44 {
				return map[string]interface{}{"ok": false, "error": "Invalid audio file"}
			}
			pcmData := wavData[44:]
			modelDir, mdErr := models.GetDir(cfg.GetLocalModelID())
			if mdErr != nil {
				return map[string]interface{}{"ok": false, "error": mdErr.Error()}
			}
			localLang := cfg.GetTranscriptionLanguage()
			text, err = GetLocalRecognizer().Transcribe(pcmData, 16000, localLang, modelDir)
		} else {
			if apiKey == "" {
				return map[string]interface{}{"ok": false, "error": "No API key configured"}
			}
			text, err = Transcribe(context.Background(), wavData, lang, apiKey, model, endpoint, "")
		}
		if err != nil {
			return map[string]interface{}{"ok": false, "error": err.Error()}
		}

		text = cfg.ApplyTextReplacements(text)

		modelName := model
		if useLocal {
			modelName = cfg.GetLocalModelID()
		}
		processingDur := 0.0

		isPending := false
		for _, tag := range entry.Tags {
			if tag == "pending" {
				isPending = true
				break
			}
		}
		if isPending {
			if !history.CompletePendingEntry(id, text, processingDur, modelName, useLocal) {
				return map[string]interface{}{"ok": false, "error": "Failed to complete pending entry"}
			}
		} else {
			if !history.UpdateText(id, text) {
				return map[string]interface{}{"ok": false, "error": "Failed to update entry"}
			}
		}
		return map[string]interface{}{"ok": true, "text": text}
	})

	w.Bind("pinEntry", func(id string) bool { return history.TogglePin(id) })
	w.Bind("duplicateEntry", func(id string) bool { return history.DuplicateEntry(id) })
	w.Bind("archiveEntry", func(id string) bool { return history.ToggleArchive(id) })

	w.Bind("getArchivedEntries", func() (string, error) {
		entries := history.AllArchived()
		data, err := json.Marshal(entries)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("getArchivedCount", func() int { return history.ArchivedCount() })

	w.Bind("updateEntry", func(id, title, tagsJSON string) bool {
		var tags []string
		if tagsJSON != "" {
			if err := json.Unmarshal([]byte(tagsJSON), &tags); err != nil {
				logWarn("updateEntry: invalid tags JSON: %v", err)
				return false
			}
		}
		return history.UpdateEntry(id, title, tags)
	})

	w.Bind("updateEntryText", func(id, newText string) bool {
		return history.UpdateText(id, newText)
	})

	w.Bind("getTagColors", func() string {
		colors := cfg.GetTagColors()
		b, _ := json.Marshal(colors)
		return string(b)
	})

	w.Bind("saveTagColor", func(tagName string, colorIndex int) bool {
		cfg.mu.Lock()
		if cfg.TagColors == nil {
			cfg.TagColors = make(map[string]int)
		}
		if colorIndex < 0 {
			delete(cfg.TagColors, tagName)
		} else {
			cfg.TagColors[tagName] = colorIndex
		}
		cfg.mu.Unlock()
		go cfg.Save()
		return true
	})

	w.Bind("getCustomTags", func() string {
		tags := cfg.GetCustomTags()
		data, _ := json.Marshal(tags)
		return string(data)
	})

	w.Bind("saveCustomTags", func(jsonStr string) {
		var tags []string
		if err := json.Unmarshal([]byte(jsonStr), &tags); err != nil {
			logError("Parse custom tags: %v", err)
			return
		}
		cfg.SetCustomTags(tags)
		if err := cfg.Save(); err != nil {
			logError("Save custom tags: %v", err)
		}
	})

	w.Bind("renameTag", func(oldName, newName string) bool {
		count := history.RenameTag(oldName, newName)
		if count > 0 {
			cfg.mu.Lock()
			if cfg.TagColors != nil {
				if idx, ok := cfg.TagColors[oldName]; ok {
					delete(cfg.TagColors, oldName)
					cfg.TagColors[newName] = idx
				}
			}
			cfg.mu.Unlock()
			go cfg.Save()
		}
		return count > 0
	})

	w.Bind("deleteTag", func(tagName string) bool {
		history.DeleteTag(tagName)
		cfg.mu.Lock()
		if cfg.TagColors != nil {
			delete(cfg.TagColors, tagName)
		}
		cfg.mu.Unlock()
		tags := cfg.GetCustomTags()
		filtered := make([]string, 0, len(tags))
		for _, t := range tags {
			if t != tagName {
				filtered = append(filtered, t)
			}
		}
		cfg.SetCustomTags(filtered)
		go cfg.Save()
		return true
	})

	// --- Project management ---

	w.Bind("getProjects", func() (string, error) {
		projects := history.ListProjects()
		if projects == nil {
			projects = []Project{}
		}
		data, err := json.Marshal(projects)
		return string(data), err
	})

	w.Bind("createProject", func(name string) (string, error) {
		p, err := history.CreateProject(name)
		if err != nil {
			return "", err
		}
		data, err := json.Marshal(p)
		return string(data), err
	})

	w.Bind("renameProject", func(id, newName string) (bool, error) {
		if err := history.RenameProject(id, newName); err != nil {
			return false, fmt.Errorf("renameProject: %w", err)
		}
		return true, nil
	})

	w.Bind("deleteProject", func(id string, deleteEntries bool) (bool, error) {
		if err := history.DeleteProject(id, deleteEntries); err != nil {
			return false, fmt.Errorf("deleteProject: %w", err)
		}
		NotifyHistoryChanged()
		return true, nil
	})

	w.Bind("setEntryProject", func(entryID, projectID string) (bool, error) {
		if err := history.SetEntryProject(entryID, projectID); err != nil {
			return false, fmt.Errorf("setEntryProject: %w", err)
		}
		return true, nil
	})

	w.Bind("setEntriesProject", func(idsJSON, projectID string) (bool, error) {
		var ids []string
		if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
			return false, fmt.Errorf("setEntriesProject: unmarshal IDs: %w", err)
		}
		if err := history.SetEntriesProject(ids, projectID); err != nil {
			return false, fmt.Errorf("setEntriesProject: %w", err)
		}
		return true, nil
	})

	w.Bind("getLastProjectID", func() string { return cfg.GetLastProjectID() })

	w.Bind("setLastProjectID", func(id string) {
		cfg.SetLastProjectID(id)
		go cfg.Save()
	})

	w.Bind("getSidebarWidth", func() int { return cfg.GetSidebarWidth() })

	w.Bind("setSidebarWidth", func(w int) {
		cfg.SetSidebarWidth(w)
		go cfg.Save()
	})

	w.Bind("getAnalytics", func(periodDays int) string {
		data := history.GetAnalytics(periodDays)
		b, err := json.Marshal(data)
		if err != nil {
			return "{}"
		}
		return string(b)
	})

	w.Bind("resetStatistics", func() map[string]interface{} {
		if err := history.ResetStatistics(); err != nil {
			return map[string]interface{}{"ok": false, "error": err.Error()}
		}
		usageStats.Reset()
		return map[string]interface{}{"ok": true}
	})

	w.Bind("_mergeEntries", func(idsJSON string) string {
		var ids []string
		if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
			return `{"success":false,"error":"invalid input"}`
		}
		newID := history.Merge(ids)
		if newID == "" {
			return `{"success":false,"error":"need at least 2 entries"}`
		}
		return fmt.Sprintf(`{"success":true,"id":"%s"}`, newID)
	})

	w.Bind("copyEntry", func(id string) string {
		entries := history.All()
		for _, e := range entries {
			if e.ID == id {
				writeClipboard(e.Text)
				return e.Text
			}
		}
		return ""
	})

	w.Bind("openLogFile", func() { ShowLogViewer() })

	w.Bind("startCapture", func() {
		if onCapture != nil {
			go onCapture()
		}
	})

	w.Bind("manualCleanup", func() int {
		maxEntries := cfg.GetCleanupMaxEntries()
		maxAgeDays := cfg.GetCleanupMaxAgeDays()
		logInfo("Manual cleanup triggered (maxEntries=%d, maxAgeDays=%d)", maxEntries, maxAgeDays)
		includePinned := cfg.GetCleanupIncludePinned()
		removed := history.Cleanup(maxEntries, maxAgeDays, includePinned)
		logInfo("Manual cleanup removed %d entries", removed)
		if removed > 0 {
			NotifyHistoryChanged()
		}
		return removed
	})

	w.Bind("exportEntry", func(id, format string) string {
		e := history.GetByID(id)
		if e == nil {
			return ""
		}
		path, err := export.Entries([]*export.Entry{toExportEntry(e)}, format)
		if err != nil {
			logError("Export failed: %v", err)
			return ""
		}
		return path
	})

	w.Bind("exportSelected", func(idsJSON, format string) string {
		var ids []string
		if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
			logError("Export parse IDs: %v", err)
			return ""
		}
		var expEntries []*export.Entry
		for _, id := range ids {
			if e := history.GetByID(id); e != nil {
				expEntries = append(expEntries, toExportEntry(e))
			}
		}
		path, err := export.Entries(expEntries, format)
		if err != nil {
			logError("Export failed: %v", err)
			return ""
		}
		return path
	})
}
