package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows"

	webview "github.com/webview/webview_go"
)

var (
	mainWindowMu       sync.Mutex
	mainWindowOpen     bool
	mainWindowHwnd     uintptr
	mainWebview        webview.WebView
	lastRecordingState AppState // last state pushed via NotifyRecordingState
)

//go:embed ui_main
var uiMainFS embed.FS

// mainWindowHTML is assembled once at init from modular files.
var mainWindowHTML string

func init() {
	mainWindowHTML = assembleMainHTML()
}

// escapeJS escapes a string for safe embedding in a JavaScript string literal.
func escapeJS(s string) string {
	r := strings.NewReplacer("\\", "\\\\", "'", "\\'", "\"", "\\\"", "\n", "\\n", "\r", "\\r")
	return r.Replace(s)
}

// assembleMainHTML reads template.html and injects concatenated CSS/JS from ui_main/ subdirectories.
func assembleMainHTML() string {
	tmpl, err := fs.ReadFile(uiMainFS, "ui_main/template.html")
	if err != nil {
		logError("Failed to read UI template: %v", err)
		return "<html><body><p>UI load error</p></body></html>"
	}

	css := collectEmbeddedFiles(uiMainFS, "ui_main/styles", ".css")
	js := collectEmbeddedFiles(uiMainFS, "ui_main/scripts", ".js")

	html := string(tmpl)
	html = strings.Replace(html, "/* {{STYLES}} */", css, 1)
	html = strings.Replace(html, "/* {{SCRIPTS}} */", js, 1)
	return html
}

// collectEmbeddedFiles reads all files with the given extension from a directory, sorted by name.
func collectEmbeddedFiles(fsys embed.FS, dir, ext string) string {
	entries, err := fs.ReadDir(fsys, dir)
	if err != nil {
		logWarn("Failed to read UI dir %s: %v", dir, err)
		return ""
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ext) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	var buf strings.Builder
	for _, name := range names {
		data, err := fs.ReadFile(fsys, dir+"/"+name)
		if err != nil {
			logWarn("Failed to read UI file %s/%s: %v", dir, name, err)
			continue
		}
		buf.WriteString("/* --- " + name + " --- */\n")
		buf.Write(data)
		buf.WriteByte('\n')
	}
	return buf.String()
}

// NotifyRecordingState pushes the current recording state to the dashboard FAB.
func NotifyRecordingState(s AppState) {
	mainWindowMu.Lock()
	lastRecordingState = s
	w := mainWebview
	open := mainWindowOpen
	mainWindowMu.Unlock()
	if open && w != nil {
		stateStr := "idle"
		switch s {
		case StateRecording:
			stateStr = "recording"
		case StatePaused:
			stateStr = "paused"
		case StateTranscribing:
			stateStr = "transcribing"
		case StateProcessing:
			stateStr = "processing"
		}
		w.Dispatch(func() {
			w.Eval(fmt.Sprintf("if(typeof onRecordingStateChanged==='function')onRecordingStateChanged('%s')", stateStr))
		})
	}
}

// NotifyHistoryChanged tells the open dashboard to reload entries.
func NotifyHistoryChanged() {
	mainWindowMu.Lock()
	w := mainWebview
	open := mainWindowOpen
	mainWindowMu.Unlock()
	if open && w != nil {
		w.Dispatch(func() {
			w.Eval("if(typeof loadEntries==='function')loadEntries()")
		})
	}
}

// ShowMainWindow opens the unified main window with WebView2.
func ShowMainWindow(cfg *Config, recorder *Recorder, history *History, onSaved func(), onClose func(), onCapture func(), initialPage string) {
	mainWindowMu.Lock()
	if mainWindowOpen {
		if mainWindowHwnd != 0 {
			user32 := windows.NewLazySystemDLL("user32.dll")
			kernel32 := windows.NewLazySystemDLL("kernel32.dll")
			setForeground := user32.NewProc("SetForegroundWindow")
			showWin := user32.NewProc("ShowWindow")
			bringToTop := user32.NewProc("BringWindowToTop")
			getForeground := user32.NewProc("GetForegroundWindow")
			getWindowThreadProcessId := user32.NewProc("GetWindowThreadProcessId")
			attachThreadInput := user32.NewProc("AttachThreadInput")
			getCurrentThreadId := kernel32.NewProc("GetCurrentThreadId")
			showWin.Call(mainWindowHwnd, 9) // SW_RESTORE
			// AttachThreadInput trick for reliable foreground
			fgHwnd, _, _ := getForeground.Call()
			if fgHwnd != 0 {
				fgThread, _, _ := getWindowThreadProcessId.Call(fgHwnd, 0)
				curThread, _, _ := getCurrentThreadId.Call()
				if fgThread != curThread {
					attachThreadInput.Call(curThread, fgThread, 1) // attach
					setForeground.Call(mainWindowHwnd)
					bringToTop.Call(mainWindowHwnd)
					attachThreadInput.Call(curThread, fgThread, 0) // detach
				} else {
					setForeground.Call(mainWindowHwnd)
					bringToTop.Call(mainWindowHwnd)
				}
			} else {
				setForeground.Call(mainWindowHwnd)
			}
		}
		mainWindowMu.Unlock()
		return
	}
	mainWindowOpen = true
	mainWindowMu.Unlock()

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		defer func() {
			mainWindowMu.Lock()
			mainWindowOpen = false
			mainWindowHwnd = 0
			mainWebview = nil
			mainWindowMu.Unlock()
		}()

		// Always create with DevTools enabled (accessible only via Ctrl+F12, right-click is blocked)
		w := webview.New(true)
		if w == nil {
			return
		}
		defer w.Destroy()

		mainWindowMu.Lock()
		mainWebview = w
		mainWindowMu.Unlock()

		w.SetTitle("WhisPaste")
		w.SetSize(1000, 700, webview.HintNone)
		w.SetSize(800, 550, webview.HintMin)

		// Hide window initially to prevent white flash before content loads
		hwndPtr := w.Window()
		hwnd := uintptr(hwndPtr)

		mainWindowMu.Lock()
		mainWindowHwnd = hwnd
		mainWindowMu.Unlock()
		user32 := windows.NewLazySystemDLL("user32.dll")
		showWindow := user32.NewProc("ShowWindow")
		const swHide = 0
		const swShow = 5
		showWindow.Call(hwnd, swHide)

		// Set window icon from embedded .ico
		setWindowIcon(hwndPtr)

		// Bind: windowReady → shows the window and focuses it after HTML is fully loaded
		w.Bind("windowReady", func() {
			showWindow.Call(hwnd, swShow)
			setFgProc := user32.NewProc("SetForegroundWindow")
			setFgProc.Call(hwnd)
			// Sync recording state in case a recording is already in progress
			mainWindowMu.Lock()
			s := lastRecordingState
			mainWindowMu.Unlock()
			NotifyRecordingState(s)
		})

		// Inject the current language, theme, and initial page before page loads
		langJSON, _ := json.Marshal(cfg.GetUILanguage())
		themeJSON, _ := json.Marshal(cfg.GetTheme())
		effectivePage := initialPage
		if initialPage == "smart-mode" {
			effectivePage = "settings"
		}
		// Set data-theme attribute immediately so CSS variables apply before first paint (prevents white flash)
		// Guard against document.documentElement being null on about:blank
		initJS := fmt.Sprintf(`(function(){var d=document.documentElement;if(!d)return;var t=%s;if(t==='system')t=window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light';if(t==='dark')d.setAttribute('data-theme','dark');})();`, themeJSON)
		initJS += fmt.Sprintf(`window._lang = %s; window._theme = %s; window._initialPage = "%s";`, langJSON, themeJSON, effectivePage)
		if !cfg.GetOnboardingDone() {
			initJS += ` window._showOnboarding = true;`
		}
		if initialPage == "smart-mode" {
			initJS += ` window._initialSection = "smart-mode";`
		}
		// Disable browser context menu (right-click) — app provides its own UX
		initJS += ` document.addEventListener('contextmenu', function(e){ e.preventDefault(); });`
		// Disable Ctrl+/- zoom and Ctrl+mousewheel zoom
		initJS += ` document.addEventListener('keydown', function(e){ if(e.ctrlKey && (e.key==='+' || e.key==='-' || e.key==='=' || e.key==='0')) e.preventDefault(); });`
		initJS += ` document.addEventListener('wheel', function(e){ if(e.ctrlKey) e.preventDefault(); }, {passive:false});`
		w.Init(initJS)

		// --- Settings bindings ---

		// Bind: getConfig → returns JSON config
		w.Bind("getConfig", func() (string, error) {
			cfg.mu.RLock()
			defer cfg.mu.RUnlock()
			data, err := json.Marshal(cfg)
			if err != nil {
				return "", err
			}
			return string(data), nil
		})

		// Bind: saveConfig → saves config from JSON
		w.Bind("saveConfig", func(configJSON string) map[string]interface{} {
			var newCfg Config
			if err := json.Unmarshal([]byte(configJSON), &newCfg); err != nil {
				return map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("Invalid config: %v", err),
				}
			}
			cfg.mu.Lock()
			cfg.APIKey = newCfg.APIKey
			cfg.APIEndpoint = newCfg.APIEndpoint
			cfg.HotkeyMods = newCfg.HotkeyMods
			cfg.HotkeyKey = newCfg.HotkeyKey
			cfg.Mode = newCfg.Mode
			cfg.Language = newCfg.Language
			cfg.Model = newCfg.Model
			cfg.Prompt = newCfg.Prompt
			cfg.OverlayPos = newCfg.OverlayPos
			cfg.AutoPaste = newCfg.AutoPaste
			cfg.PlaySounds = newCfg.PlaySounds
			cfg.CheckUpdates = newCfg.CheckUpdates
			cfg.UILanguage = newCfg.UILanguage
			cfg.Theme = newCfg.Theme
			cfg.Autostart = newCfg.Autostart
			cfg.CloseToTray = newCfg.CloseToTray
			cfg.SoundVolume = newCfg.SoundVolume
			cfg.MaxRecordSec = newCfg.MaxRecordSec
			cfg.SmartMode = newCfg.SmartMode
			cfg.SmartModePreset = newCfg.SmartModePreset
			cfg.SmartModePrompt = newCfg.SmartModePrompt
			cfg.SmartModeTarget = newCfg.SmartModeTarget
			cfg.UseLocalSTT = newCfg.UseLocalSTT
			cfg.LocalModelID = newCfg.LocalModelID
			cfg.TranscriptionLanguage = newCfg.TranscriptionLanguage
			cfg.InputDevice = newCfg.InputDevice
			cfg.InputGain = newCfg.InputGain
			cfg.CleanupEnabled = newCfg.CleanupEnabled
			cfg.CleanupMaxEntries = newCfg.CleanupMaxEntries
			cfg.CleanupMaxAgeDays = newCfg.CleanupMaxAgeDays
			cfg.TrimSilence = newCfg.TrimSilence
			cfg.mu.Unlock()

			// Apply autostart setting
			if err := SetAutostart(newCfg.Autostart); err != nil {
				logWarn("Failed to set autostart: %v", err)
			}

			SetLanguage(newCfg.UILanguage)

			if err := cfg.Save(); err != nil {
				return map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("Save failed: %v", err),
				}
			}
			if onSaved != nil {
				onSaved()
			}
			return map[string]interface{}{"success": true, "error": ""}
		})

		// Bind: testRecording → record 3s, transcribe, return result
		w.Bind("_doTestRecording", func() map[string]interface{} {
			logInfo("Test recording started")
			if !cfg.GetUseLocalSTT() && !cfg.HasAPIKey() {
				logWarn("Test recording: no API key and local STT disabled")
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   T("error.no_api_key"),
				}
			}
			if recorder == nil {
				logError("Test recording: recorder not available")
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   "Recorder not available",
				}
			}

			// Stop monitor if running (exclusive capture devices conflict)
			recorder.StopMonitor()
			recorder.SetGain(cfg.GetInputGain())
			if err := recorder.Start(); err != nil {
				logError("Test recording start failed: %v", err)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   fmt.Sprintf(T("error.recording"), err),
				}
			}

			// Record for 3 seconds
			time.Sleep(3 * time.Second)
			pcm, err := recorder.Stop()
			if err != nil || len(pcm) == 0 {
				errMsg := "no audio captured"
				if err != nil {
					errMsg = err.Error()
				}
				logError("Test recording capture failed: %s", errMsg)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   errMsg,
				}
			}

			logInfo("Test recording captured %d bytes, transcribing...", len(pcm))
			model := cfg.Model
			if model == "" {
				model = "whisper-1"
			}
			var text string
			var err2 error
			if cfg.GetUseLocalSTT() {
				modelDir, mdErr := GetModelDir(cfg.GetLocalModelID())
				if mdErr != nil {
					return map[string]interface{}{"success": false, "text": "", "error": mdErr.Error()}
				}
				text, err2 = GetLocalRecognizer().Transcribe(pcm, 16000, cfg.GetTranscriptionLanguage(), modelDir)
			} else {
				wav := EncodeWAV(pcm, 16000, 1, 16)
				text, err2 = Transcribe(wav, cfg.Language, cfg.GetAPIKey(), model, cfg.GetAPIEndpoint(), cfg.GetPrompt())
			}
			if err2 != nil {
				logError("Test transcription failed: %v", err2)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   err2.Error(),
				}
			}
			logInfo("Test transcription succeeded: %q", strings.TrimSpace(text))
			return map[string]interface{}{
				"success": true,
				"text":    strings.TrimSpace(text),
				"error":   "",
			}
		})

		// Bind: testSound → plays a success chime for preview
		w.Bind("_testSound", func() {
			PlayFeedback(SoundSuccess)
		})

		// Bind: _getModels → returns available models with download status
		w.Bind("_getModels", func() []map[string]interface{} {
			var result []map[string]interface{}
			for _, m := range AvailableModels {
				result = append(result, map[string]interface{}{
					"id":         m.ID,
					"name":       m.Name,
					"size":       m.Size,
					"downloaded": IsModelDownloaded(m.ID),
				})
			}
			return result
		})

		// Bind: _downloadModel → download a model by ID (async, non-blocking)
		w.Bind("_downloadModel", func(modelID string) map[string]interface{} {
			logInfo("Starting model download: %s", modelID)
			go func() {
				safeDispatch := func(js string) {
					mainWindowMu.Lock()
					open := mainWindowOpen
					mainWindowMu.Unlock()
					if open {
						w.Dispatch(func() { w.Eval(js) })
					}
				}
				err := DownloadModel(modelID, func(fileDownloaded, fileTotal int64, fileIdx, fileCount int, fileName string) {
					var pct int
					if fileTotal > 0 {
						pct = int(float64(fileDownloaded) / float64(fileTotal) * 100)
						if pct > 100 {
							pct = 100
						}
					}
					safeDispatch(fmt.Sprintf("window.updateModelProgress('%s', %d, %d, %d, '%s')", escapeJS(modelID), pct, fileIdx+1, fileCount, escapeJS(fileName)))
				})
				if err != nil {
					logError("Model download failed: %v", err)
					safeDispatch(fmt.Sprintf("window.downloadComplete('%s', false, '%s')", escapeJS(modelID), escapeJS(err.Error())))
					return
				}
				logInfo("Model downloaded: %s", modelID)
				safeDispatch(fmt.Sprintf("window.downloadComplete('%s', true, '')", escapeJS(modelID)))
			}()
			return map[string]interface{}{"started": true}
		})

		// Bind: _deleteModel → delete a downloaded model
		w.Bind("_deleteModel", func(modelID string) map[string]interface{} {
			if err := DeleteModel(modelID); err != nil {
				logError("Model delete failed: %v", err)
				return map[string]interface{}{"success": false, "error": err.Error()}
			}
			return map[string]interface{}{"success": true, "error": ""}
		})

		// Bind: _getAudioDevices → returns available audio capture devices
		w.Bind("_getAudioDevices", func() string {
			devices, err := ListAudioDevices()
			if err != nil {
				logWarn("Failed to list audio devices: %v", err)
				return "[]"
			}
			data, _ := json.Marshal(devices)
			return string(data)
		})

		// Bind: _getAudioLevel → returns current mic input level (0.0–1.0)
		w.Bind("_getAudioLevel", func() string {
			if recorder == nil {
				return "0"
			}
			level := recorder.GetLevel()
			return fmt.Sprintf("%.4f", level)
		})

		// Bind: _startAudioMonitor → starts mic monitoring for VU meter
		w.Bind("_startAudioMonitor", func() string {
			if recorder == nil {
				return `{"success":false,"error":"no recorder"}`
			}
			recorder.SetGain(cfg.GetInputGain())
			if err := recorder.StartMonitor(); err != nil {
				logWarn("StartMonitor failed: %v", err)
				return fmt.Sprintf(`{"success":false,"error":"%s"}`, err.Error())
			}
			return `{"success":true}`
		})

		// Bind: _stopAudioMonitor → stops mic monitoring
		w.Bind("_stopAudioMonitor", func() {
			if recorder != nil {
				recorder.StopMonitor()
			}
		})

		// Bind: openURL → opens URL in default browser (https only)
		w.Bind("openURL", func(url string) {
			if !strings.HasPrefix(url, "https://") {
				logWarn("openURL: blocked non-https URL: %s", url)
				return
			}
			exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
		})

		// --- History/notebook bindings ---

		// Bind: getEntries → returns all history entries as JSON
		w.Bind("getEntries", func() (string, error) {
			entries := history.All()
			data, err := json.Marshal(entries)
			if err != nil {
				return "[]", err
			}
			return string(data), nil
		})

		// Bind: searchEntries → FTS5 full-text search across transcriptions
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

		// Bind: getCategories → returns list of used categories
		w.Bind("getCategories", func() (string, error) {
			tags := history.Tags()
			data, err := json.Marshal(tags)
			if err != nil {
				return "[]", err
			}
			return string(data), nil
		})

		// Bind: deleteEntry → removes entry by ID
		w.Bind("deleteEntry", func(id string) bool {
			return history.Delete(id)
		})

		// Bind: pinEntry → toggles pin state
		w.Bind("pinEntry", func(id string) bool {
			return history.TogglePin(id)
		})

		// Bind: duplicateEntry → creates a copy of an entry
		w.Bind("duplicateEntry", func(id string) bool {
			return history.DuplicateEntry(id)
		})

		// Bind: updateEntry → update title/tags (tags as JSON array string)
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

		// Bind: updateEntryText → update transcription text content
		w.Bind("updateEntryText", func(id, newText string) bool {
			return history.UpdateText(id, newText)
		})

		// Bind: applySmartAction → apply a smart mode preset to an existing entry
		w.Bind("applySmartAction", func(entryID, preset, customPrompt string) string {
			entry := history.GetByID(entryID)
			if entry == nil {
				resp, _ := json.Marshal(map[string]string{"error": "Entry not found"})
				return string(resp)
			}

			apiKey := cfg.GetAPIKey()
			endpoint := cfg.GetAPIEndpoint()
			appLang := cfg.GetUILanguage()
			if appLang == "" {
				appLang = "en"
			}

			result, err := ApplySmartAction(entry.Text, preset, customPrompt, apiKey, endpoint, appLang, cfg.GetCustomTemplates())
			if err != nil {
				resp, _ := json.Marshal(map[string]string{"error": err.Error()})
				return string(resp)
			}

			resp, _ := json.Marshal(map[string]string{"text": result})
			return string(resp)
		})

		// Bind: addSmartEntry → creates a new entry from smart action result
		w.Bind("addSmartEntry", func(sourceID, text, preset string) {
			entry := history.GetByID(sourceID)
			if entry == nil {
				return
			}
			history.AddSmart(text, entry.Language, []string{"smart:" + preset})
			logInfo("New smart entry created from %s using preset %s", sourceID, preset)
		})

		// Bind: getTagColors → returns custom tag color mappings as JSON
		w.Bind("getTagColors", func() string {
			colors := cfg.GetTagColors()
			b, _ := json.Marshal(colors)
			return string(b)
		})

		// Bind: saveTagColor → saves or removes a custom tag color
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

		// Bind: renameTag → renames a tag across all entries
		w.Bind("renameTag", func(oldName, newName string) bool {
			count := history.RenameTag(oldName, newName)
			if count > 0 {
				// Also rename in TagColors config
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

		// Bind: getAnalytics → returns usage analytics for a time period
		w.Bind("getAnalytics", func(periodDays int) string {
			data := history.GetAnalytics(periodDays)
			b, err := json.Marshal(data)
			if err != nil {
				return "{}"
			}
			return string(b)
		})

		// Bind: _mergeEntries → merges multiple entries into one
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

		// Bind: copyEntry → copies text to clipboard
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

		// Bind: openLogFile → opens the log viewer window
		w.Bind("openLogFile", func() {
			ShowLogViewer()
		})

		// Bind: startCapture → triggers recording from dashboard
		w.Bind("startCapture", func() {
			if onCapture != nil {
				go onCapture()
			}
		})

		// Bind: manualCleanup → runs cleanup and returns deleted count
		w.Bind("manualCleanup", func() int {
			maxEntries := cfg.GetCleanupMaxEntries()
			maxAgeDays := cfg.GetCleanupMaxAgeDays()
			logInfo("Manual cleanup triggered (maxEntries=%d, maxAgeDays=%d)", maxEntries, maxAgeDays)
			removed := history.Cleanup(maxEntries, maxAgeDays)
			logInfo("Manual cleanup removed %d entries", removed)
			if removed > 0 {
				NotifyHistoryChanged()
			}
			return removed
		})

		// Bind: exportEntry → export a single entry to file (txt or md)
		w.Bind("exportEntry", func(id, format string) string {
			e := history.GetByID(id)
			if e == nil {
				return ""
			}
			return exportEntries([]*HistoryEntry{e}, format)
		})

		// Bind: exportSelected → export multiple entries by IDs
		w.Bind("exportSelected", func(idsJSON, format string) string {
			var ids []string
			if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
				logError("Export parse IDs: %v", err)
				return ""
			}
			var entries []*HistoryEntry
			for _, id := range ids {
				if e := history.GetByID(id); e != nil {
					entries = append(entries, e)
				}
			}
			return exportEntries(entries, format)
		})

		// --- Onboarding bindings ---

		// Bind: completeOnboarding → marks onboarding as done
		w.Bind("completeOnboarding", func() {
			cfg.SetOnboardingDone(true)
			if err := cfg.Save(); err != nil {
				logError("Save config after onboarding: %v", err)
			}
			logInfo("Onboarding completed")
		})

		// --- Quick Mode Switching bindings ---

		// Bind: setSmartPreset → quickly switch smart mode preset from status bar
		w.Bind("setSmartPreset", func(preset string) {
			cfg.SetSmartModePreset(preset)
			if err := cfg.Save(); err != nil {
				logError("Save config after smart preset switch: %v", err)
			}
			logInfo("Smart mode preset switched to: %s (enabled=%v)", preset, cfg.GetSmartMode())
		})

		// --- Profile bindings ---

		// Bind: saveProfile → save current settings as a named profile
		w.Bind("saveProfile", func(name string) {
			cfg.SaveProfile(name)
			if err := cfg.Save(); err != nil {
				logError("Save profile %q: %v", name, err)
			}
			logInfo("Profile saved: %s", name)
		})

		// Bind: loadProfile → apply a named profile
		w.Bind("loadProfile", func(name string) bool {
			ok := cfg.LoadProfile(name)
			if ok {
				if err := cfg.Save(); err != nil {
					logError("Save config after loading profile %q: %v", name, err)
				}
				logInfo("Profile loaded: %s", name)
			}
			return ok
		})

		// Bind: deleteProfile → remove a named profile
		w.Bind("deleteProfile", func(name string) {
			cfg.DeleteProfile(name)
			if err := cfg.Save(); err != nil {
				logError("Delete profile %q: %v", name, err)
			}
			logInfo("Profile deleted: %s", name)
		})

		// Bind: listProfiles → returns JSON array of profile names
		w.Bind("listProfiles", func() string {
			names := cfg.ListProfiles()
			data, _ := json.Marshal(names)
			return string(data)
		})

		// Bind: saveCustomTemplate → save a user-defined smart mode template
		w.Bind("saveCustomTemplate", func(name, prompt string) {
			cfg.SaveCustomTemplate(name, prompt)
			if err := cfg.Save(); err != nil {
				logError("Save custom template %q: %v", name, err)
			}
			logInfo("Custom template saved: %s", name)
		})

		// Bind: deleteCustomTemplate → delete a user-defined template
		w.Bind("deleteCustomTemplate", func(name string) {
			cfg.DeleteCustomTemplate(name)
			if err := cfg.Save(); err != nil {
				logError("Delete custom template %q: %v", name, err)
			}
			logInfo("Custom template deleted: %s", name)
		})

		// Bind: getCustomTemplates → returns JSON map of user templates
		w.Bind("getCustomTemplates", func() string {
			templates := cfg.GetCustomTemplates()
			data, _ := json.Marshal(templates)
			return string(data)
		})

		// Bind: getBuiltinPresets → returns JSON map of built-in preset names→prompts
		w.Bind("getBuiltinPresets", func() string {
			presets := GetBuiltinPresets()
			data, _ := json.Marshal(presets)
			return string(data)
		})

		// Bind: getTextReplacements → returns JSON array of replacements
		w.Bind("getTextReplacements", func() string {
			items := cfg.GetTextReplacements()
			data, _ := json.Marshal(items)
			return string(data)
		})

		// Bind: setTextReplacements → saves full replacement list
		w.Bind("setTextReplacements", func(jsonStr string) {
			var items []TextReplacement
			if err := json.Unmarshal([]byte(jsonStr), &items); err != nil {
				logError("Parse text replacements: %v", err)
				return
			}
			cfg.SetTextReplacements(items)
			if err := cfg.Save(); err != nil {
				logError("Save text replacements: %v", err)
			}
		})

		// Bind: setTextReplacementsEnabled → toggle the feature
		w.Bind("setTextReplacementsEnabled", func(enabled bool) {
			cfg.SetTextReplacementsEnabled(enabled)
			if err := cfg.Save(); err != nil {
				logError("Save text replacements enabled: %v", err)
			}
		})

		// Bind: getTextReplacementsEnabled → returns enabled state
		w.Bind("getTextReplacementsEnabled", func() bool {
			return cfg.GetTextReplacementsEnabled()
		})

		// Bind: getAppPresets → returns JSON map of app→preset mappings
		w.Bind("getAppPresets", func() string {
			m := cfg.GetAppPresets()
			data, _ := json.Marshal(m)
			return string(data)
		})

		// Bind: setAppPresets → saves app→preset mappings
		w.Bind("setAppPresets", func(jsonStr string) {
			var m map[string]string
			if err := json.Unmarshal([]byte(jsonStr), &m); err != nil {
				logError("Parse app presets: %v", err)
				return
			}
			cfg.SetAppPresets(m)
			if err := cfg.Save(); err != nil {
				logError("Save app presets: %v", err)
			}
		})

		// Bind: setAppDetectionEnabled → toggle app detection
		w.Bind("setAppDetectionEnabled", func(enabled bool) {
			cfg.mu.Lock()
			cfg.AppDetection = enabled
			cfg.mu.Unlock()
			if err := cfg.Save(); err != nil {
				logError("Save app detection: %v", err)
			}
		})

		// Bind: getAppDetectionEnabled → returns enabled state
		w.Bind("getAppDetectionEnabled", func() bool {
			return cfg.GetAppDetectionEnabled()
		})

		// Bind: getActiveAppName → returns current foreground app exe name
		w.Bind("getActiveAppName", func() string {
			return GetActiveAppName()
		})

		// --- Theme & language bindings ---

		// Bind: getTheme → returns current theme from config
		w.Bind("getTheme", func() string {
			cfg.mu.RLock()
			defer cfg.mu.RUnlock()
			return cfg.Theme
		})

		// Bind: setTheme → saves theme to config
		w.Bind("setTheme", func(theme string) {
			if theme != "system" && theme != "light" && theme != "dark" {
				return
			}
			cfg.mu.Lock()
			cfg.Theme = theme
			cfg.mu.Unlock()
			if err := cfg.Save(); err != nil {
				logWarn("Failed to save theme: %v", err)
			}
		})

		// Bind: getUILanguage → returns current UI language
		w.Bind("getUILanguage", func() string {
			return cfg.GetUILanguage()
		})

		// Bind: setUILanguage → saves UI language and re-applies
		w.Bind("setUILanguage", func(lang string) {
			if lang != "en" && lang != "de" {
				return
			}
			cfg.mu.Lock()
			cfg.UILanguage = lang
			cfg.mu.Unlock()
			SetLanguage(lang)
			if err := cfg.Save(); err != nil {
				logWarn("Failed to save language: %v", err)
			}
		})

		// Bind: getTranslations → returns all l10n strings (notebook + settings)
		w.Bind("getTranslations", func() (string, error) {
			keys := []string{
				// Notebook keys
				"notebook.title", "notebook.search", "notebook.all",
				"notebook.pinned", "notebook.today", "notebook.this_week",
				"notebook.older", "notebook.empty", "notebook.no_results",
				"notebook.copy", "notebook.delete", "notebook.pin",
				"notebook.unpin", "notebook.copied", "notebook.confirm_delete",
				"notebook.uncategorized",
				"notebook.sort", "notebook.sort_newest", "notebook.sort_oldest",
				"notebook.sort_alpha", "notebook.sort_duration",
				"notebook.add_tag", "notebook.tag_updated",
				"notebook.export", "notebook.export_txt", "notebook.export_md",
				"notebook.exported", "notebook.export_selected",
				// Settings keys
				"settings.title", "settings.api_key", "settings.api_key_hint",
				"settings.hotkey", "settings.mode", "settings.mode_ptt", "settings.mode_toggle",
				"settings.language", "settings.language_auto", "settings.ui_language",
				"settings.overlay", "settings.overlay_top", "settings.overlay_cursor",
				"settings.auto_paste", "settings.play_sounds", "settings.check_updates",
				"settings.save", "settings.cancel", "settings.test",
				"settings.test_recording", "settings.test_success", "settings.test_error",
				"settings.saved", "settings.about", "settings.general",
				"settings.audio", "settings.appearance",
				"settings.show_key", "settings.hide_key",
				"settings.theme", "settings.theme_light", "settings.theme_dark", "settings.theme_system",
				"settings.smart_mode", "settings.smart_preset",
				"settings.smart_preset_off", "settings.smart_preset_cleanup",
				"settings.smart_preset_email", "settings.smart_preset_bullets",
				"settings.smart_preset_formal", "settings.smart_preset_translate",
				"settings.smart_preset_custom",
				"settings.smart_prompt", "settings.smart_prompt_hint",
				"settings.smart_target", "settings.smart_cost_note",
				"settings.api_endpoint", "settings.api_endpoint_hint",
				"settings.whisper_prompt", "settings.whisper_prompt_hint",
				"settings.max_duration", "settings.max_duration_fmt", "settings.unlimited",
				// Stats keys
				"stats.title", "stats.dictations", "stats.words",
				"stats.time_saved", "stats.minutes", "stats.cost",
				// App keys
				"app.name", "app.description", "app.version",
				// Update keys
				"update.check", "update.up_to_date", "update.available",
			}
			tr := map[string]string{}
			for _, k := range keys {
				tr[k] = T(k)
			}
			data, err := json.Marshal(tr)
			if err != nil {
				return "{}", err
			}
			return string(data), nil
		})

		// Bind: closeWindow → closes the webview window
		w.Bind("closeWindow", func() {
			// Stop any running audio monitor before closing
			if recorder != nil {
				recorder.StopMonitor()
			}
			w.Terminate()
		})

		// Bind: getAvailableModels → returns JSON array of available models for quick switching
		w.Bind("getAvailableModels", func() string {
			type modelInfo struct {
				ID      string `json:"id"`
				Name    string `json:"name"`
				Meta    string `json:"meta"`
				IsLocal bool   `json:"isLocal"`
			}
			var models []modelInfo

			// API model (always available if API key is set)
			if cfg.GetAPIKey() != "" {
				cfg.mu.RLock()
				apiModel := cfg.Model
				cfg.mu.RUnlock()
				if apiModel == "" {
					apiModel = "whisper-1"
				}
				models = append(models, modelInfo{
					ID:      apiModel,
					Name:    "Whisper API (" + apiModel + ")",
					Meta:    "Cloud",
					IsLocal: false,
				})
			}

			// Local models (only if downloaded)
			for _, m := range ListDownloadedModels() {
				models = append(models, modelInfo{
					ID:      m.ID,
					Name:    m.Name,
					Meta:    "Local · " + m.Size,
					IsLocal: true,
				})
			}

			data, _ := json.Marshal(models)
			return string(data)
		})

		// Bind: switchModel → switches the active model
		w.Bind("switchModel", func(modelID string, isLocal bool) {
			cfg.mu.Lock()
			if isLocal {
				cfg.UseLocalSTT = true
				cfg.LocalModelID = modelID
			} else {
				cfg.UseLocalSTT = false
				cfg.Model = modelID
			}
			cfg.mu.Unlock()
			cfg.Save()
			logInfo("Model switched to %s (local=%v)", modelID, isLocal)
		})

		// Bind: getSystemInfo → returns system/build info for the About page
		w.Bind("getSystemInfo", func() string {
			cfgPath, _ := configPath()
			dir, _ := configDir()
			logPath := filepath.Join(dir, logFile)

			info := map[string]string{
				"appVersion":  AppVersion,
				"goVersion":   runtime.Version(),
				"os":          runtime.GOOS,
				"arch":        runtime.GOARCH,
				"configPath":  cfgPath,
				"logPath":     logPath,
				"buildCommit": BuildCommit,
				"buildDate":   BuildDate,
			}
			data, _ := json.Marshal(info)
			return string(data)
		})

		w.SetHtml(mainWindowHTML)
		w.Run()
		logDebug("Main window closed — invoking cleanup")
		// Window closed — stop any running audio monitor
		if recorder != nil {
			recorder.StopMonitor()
		}
		// Notify caller
		if onClose != nil {
			logDebug("Main window: calling onClose callback")
			onClose()
		}
	}()
}


