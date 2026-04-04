package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/whispaste/whispaste/internal/audiocache"
	"github.com/whispaste/whispaste/internal/export"
	"github.com/whispaste/whispaste/internal/stats"
	"github.com/whispaste/whispaste/internal/wav"

	webview "github.com/webview/webview_go"
)

// bindHistoryHandlers registers history, entry CRUD, tag, project, export, and analytics JS bindings.
func bindHistoryHandlers(w webview.WebView, cfg *Config, history *History, usageStats *stats.UsageStats, recorder *Recorder, onCapture func()) {

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
			return map[string]interface{}{"ok": false, "error": T("error.entry_not_found")}
		}
		wavData, err := audiocache.Load(id)
		if err != nil {
			return map[string]interface{}{"ok": false, "error": T("error.no_cached_audio")}
		}

		// Run transcription async to avoid blocking UI
		go func() {
			safeEval := func(js string) {
				mainWindowMu.Lock()
				open := mainWindowOpen
				mainWindowMu.Unlock()
				if open {
					w.Dispatch(func() { w.Eval(js) })
				}
			}

			apiKey := cfg.GetAPIKey()
			endpoint := cfg.GetAPIEndpoint()
			lang := cfg.GetTranscriptionLanguage()
			useLocal := cfg.GetActiveModelLocal()
			metadataLang := lang
			languageHint := lang

			cfg.mu.RLock()
			model := cfg.Model
			cfg.mu.RUnlock()

			var text string
			var txErr error
			if useLocal {
				if len(wavData) <= 44 {
					safeEval(`onReTranscribeResult(` + jsStr(id) + `, false, "Invalid audio file")`)
					return
				}
				pcmData := wavData[44:]
				localLang := cfg.GetEffectiveLocalTranscriptionLanguage()
				metadataLang = cfg.GetLocalTranscriptionMetadataLanguage()
				languageHint = localLang
				text, txErr = TranscribeLocal(pcmData, 16000, localLang, cfg.GetLocalModelID())
			} else {
				if apiKey == "" {
					safeEval(`onReTranscribeResult(` + jsStr(id) + `, false, "No API key configured")`)
					return
				}
				text, txErr = Transcribe(context.Background(), wavData, lang, apiKey, model, endpoint, "")
			}
			if txErr != nil {
				safeEval(`onReTranscribeResult(` + jsStr(id) + `, false, ` + jsStr(txErr.Error()) + `)`)
				return
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
				if !history.CompletePendingEntryHint(id, text, processingDur, metadataLang, modelName, useLocal, languageHint) {
					safeEval(`onReTranscribeResult(` + jsStr(id) + `, false, "Failed to complete pending entry")`)
					return
				}
			} else {
				if !history.UpdateTranscriptionResultHint(id, text, metadataLang, modelName, useLocal, languageHint) {
					safeEval(`onReTranscribeResult(` + jsStr(id) + `, false, "Failed to update entry")`)
					return
				}
			}
			safeEval(`onReTranscribeResult(` + jsStr(id) + `, true, "")`)
		}()

		// Return immediately — result will come via onReTranscribeResult callback
		return map[string]interface{}{"ok": true, "async": true}
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

	w.Bind("updateEntryText", func(id, newText, newLang string) bool {
		if newLang != "" {
			return history.UpdateTextLanguage(id, newText, newLang)
		}
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

	w.Bind("setActiveProject", func(id string) {
		setSelectedProjectID(id)
		logDebug("Active project set to: %s", id)
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

	w.Bind("copyEntryMarkdown", func(id string) string {
		entries := history.All()
		for _, e := range entries {
			if e.ID == id {
				md := formatEntryMarkdown(e)
				writeClipboard(md)
				return md
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

	// --- Notes bindings ---

	w.Bind("getNotes", func(entryID string) (string, error) {
		notes := history.GetNotes(entryID)
		if notes == nil {
			notes = []EntryNote{}
		}
		data, err := json.Marshal(notes)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("addNote", func(entryID, content string) (string, error) {
		note, err := history.AddNote(entryID, content)
		if err != nil {
			return "", err
		}
		data, err := json.Marshal(note)
		if err != nil {
			return "", err
		}
		return string(data), nil
	})

	w.Bind("updateNote", func(noteID, content string) error {
		return history.UpdateNote(noteID, content)
	})

	w.Bind("deleteNote", func(noteID string) error {
		return history.DeleteNote(noteID)
	})

	w.Bind("getNoteCount", func(entryID string) int {
		return history.NoteCount(entryID)
	})

	// --- Attachments bindings ---

	w.Bind("getAttachments", func(entryID string) (string, error) {
		atts := history.GetAttachments(entryID)
		if atts == nil {
			atts = []EntryAttachment{}
		}
		data, err := json.Marshal(atts)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("addAttachment", func(entryID string) (string, error) {
		paths := export.ShowOpenDialog(T("notebook.add_file"))
		if len(paths) == 0 {
			return "[]", nil // cancelled
		}
		var added []EntryAttachment
		for _, srcPath := range paths {
			att, err := history.AddAttachment(entryID, srcPath)
			if err != nil {
				logError("addAttachment: %v", err)
				continue
			}
			added = append(added, att)
		}
		data, err := json.Marshal(added)
		if err != nil {
			return "[]", err
		}
		return string(data), nil
	})

	w.Bind("deleteAttachment", func(attachmentID string) error {
		return history.DeleteAttachment(attachmentID)
	})

	w.Bind("openAttachment", func(attachmentID string) error {
		return history.OpenAttachment(attachmentID)
	})

	w.Bind("getAttachmentCount", func(entryID string) int {
		return history.AttachmentCount(entryID)
	})

	// --- Voice note recording ---
	var vnMu sync.Mutex
	var vnEntryID string
	var vnRecording bool

	w.Bind("startVoiceNote", func(entryID string) map[string]interface{} {
		vnMu.Lock()
		defer vnMu.Unlock()

		if vnRecording {
			return map[string]interface{}{"ok": false, "error": T("voice_note.already_recording")}
		}
		if recorder == nil {
			return map[string]interface{}{"ok": false, "error": T("error.no_recorder")}
		}
		if recorder.IsRecording() {
			return map[string]interface{}{"ok": false, "error": T("voice_note.main_recording_active")}
		}

		if err := recorder.Start(); err != nil {
			return map[string]interface{}{"ok": false, "error": fmt.Sprintf("Recorder start: %v", err)}
		}
		vnEntryID = entryID
		vnRecording = true
		return map[string]interface{}{"ok": true}
	})

	w.Bind("stopVoiceNote", func() map[string]interface{} {
		vnMu.Lock()
		if !vnRecording {
			vnMu.Unlock()
			return map[string]interface{}{"ok": false, "error": T("error.not_recording")}
		}
		entryID := vnEntryID
		vnRecording = false
		vnEntryID = ""
		vnMu.Unlock()

		pcm, err := recorder.Stop()
		if err != nil {
			return map[string]interface{}{"ok": false, "error": fmt.Sprintf("Recorder stop: %v", err)}
		}
		if len(pcm) == 0 {
			return map[string]interface{}{"ok": false, "error": T("voice_note.no_audio")}
		}

		pcm = TrimSilence(pcm, 0.02, 250)
		wavData := wav.Encode(pcm, 16000, 1, 16)

		// Save WAV as attachment
		att, err := history.AddAttachmentFromBytes(entryID, wavData, "voice-note.wav", "audio/wav")
		if err != nil {
			logWarn("Voice note attachment save: %v", err)
		}

		// Transcribe async
		go func() {
			safeEval := func(js string) {
				mainWindowMu.Lock()
				open := mainWindowOpen
				mainWindowMu.Unlock()
				if open {
					w.Dispatch(func() { w.Eval(js) })
				}
			}

			apiKey := cfg.GetAPIKey()
			endpoint := cfg.GetAPIEndpoint()
			lang := cfg.GetTranscriptionLanguage()
			useLocal := cfg.GetActiveModelLocal()

			cfg.mu.RLock()
			model := cfg.Model
			cfg.mu.RUnlock()

			var text string
			var txErr error
			if useLocal {
				localLang := cfg.GetEffectiveLocalTranscriptionLanguage()
				text, txErr = TranscribeLocal(pcm, 16000, localLang, cfg.GetLocalModelID())
			} else {
				if apiKey != "" {
					text, txErr = Transcribe(context.Background(), wavData, lang, apiKey, model, endpoint, "")
				} else {
					txErr = fmt.Errorf("no API key configured")
				}
			}

			noteContent := "[voice]"
			if txErr == nil && strings.TrimSpace(text) != "" {
				text = cfg.ApplyTextReplacements(text)
				noteContent = "[voice] " + strings.TrimSpace(text)
			} else if txErr != nil {
				logWarn("Voice note transcription: %v", txErr)
			}

			_, addErr := history.AddNote(entryID, noteContent)
			if addErr != nil {
				logWarn("Voice note add note: %v", addErr)
				safeEval(`onVoiceNoteResult(` + jsStr(entryID) + `, false, ` + jsStr(addErr.Error()) + `)`)
				return
			}

			_ = att // attachment already saved
			safeEval(`onVoiceNoteResult(` + jsStr(entryID) + `, true, "")`)
		}()

		return map[string]interface{}{"ok": true, "async": true}
	})

	w.Bind("isVoiceNoteRecording", func() bool {
		vnMu.Lock()
		defer vnMu.Unlock()
		return vnRecording
	})
}

// formatEntryMarkdown formats a history entry as a rich Markdown string
// suitable for pasting into notes apps, docs, or chat.
func formatEntryMarkdown(e HistoryEntry) string {
	var b strings.Builder
	title := e.Title
	if title == "" {
		title = truncate(e.Text, 60)
	}
	b.WriteString("# ")
	b.WriteString(title)
	b.WriteString("\n\n")
	b.WriteString(e.Text)
	b.WriteString("\n")

	// Metadata footer
	var meta []string
	if t, err := time.Parse(time.RFC3339, e.Timestamp); err == nil {
		meta = append(meta, fmt.Sprintf("**%s:** %s", T("notebook.date"), t.Format("2006-01-02 15:04")))
	}
	if len(e.Tags) > 0 {
		meta = append(meta, fmt.Sprintf("**Tags:** %s", strings.Join(e.Tags, ", ")))
	}
	if e.Language != "" {
		meta = append(meta, fmt.Sprintf("**%s:** %s", T("notebook.language"), strings.ToUpper(e.Language)))
	}
	if len(meta) > 0 {
		b.WriteString("\n---\n")
		b.WriteString(strings.Join(meta, " · "))
		b.WriteString("\n")
	}
	return b.String()
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "…"
}
