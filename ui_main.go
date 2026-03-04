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
	"unsafe"

	"golang.org/x/sys/windows"

	webview "github.com/webview/webview_go"
)

var (
	mainWindowMu   sync.Mutex
	mainWindowOpen bool
	mainWindowHwnd uintptr
	mainWebview    webview.WebView
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
			cfg.InputDevice = newCfg.InputDevice
			cfg.InputGain = newCfg.InputGain
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
				text, err2 = GetLocalRecognizer().Transcribe(pcm, 16000, cfg.Language, modelDir)
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
				err := DownloadModel(modelID, func(downloaded, total int64, fileIdx, fileCount int) {
					if total > 0 {
						pct := int(float64(downloaded) / float64(total) * 100)
						if pct > 100 {
							pct = 100
						}
						safeDispatch(fmt.Sprintf("window.updateModelProgress('%s', %d, %d, %d)", escapeJS(modelID), pct, fileIdx+1, fileCount))
					}
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

		// Bind: getCategories → returns list of used categories
		w.Bind("getCategories", func() (string, error) {
			cats := history.Categories()
			data, err := json.Marshal(cats)
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

		// Bind: updateEntry → update title/category
		w.Bind("updateEntry", func(id, title, category string) bool {
			return history.UpdateEntry(id, title, category)
		})

		// Bind: updateEntryText → update transcription text content
		w.Bind("updateEntryText", func(id, newText string) bool {
			return history.UpdateText(id, newText)
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

		// Bind: openLogFile → opens the log file in default editor
		w.Bind("openLogFile", func() {
			logDir, err := configDir()
			if err != nil {
				logWarn("Could not determine config dir: %v", err)
				return
			}
			logPath := filepath.Join(logDir, "whispaste.log")
			pathPtr, _ := windows.UTF16PtrFromString(logPath)
			openPtr, _ := windows.UTF16PtrFromString("open")
			shell32 := windows.NewLazySystemDLL("shell32.dll")
			shellExec := shell32.NewProc("ShellExecuteW")
			ret, _, _ := shellExec.Call(0, uintptr(unsafe.Pointer(openPtr)), uintptr(unsafe.Pointer(pathPtr)), 0, 0, 1) // SW_SHOWNORMAL=1
			if ret <= 32 {
				logWarn("ShellExecuteW failed for log file (ret=%d)", ret)
			}
		})

		// Bind: startCapture → triggers recording from dashboard
		w.Bind("startCapture", func() {
			if onCapture != nil {
				go onCapture()
			}
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


