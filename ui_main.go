//go:build windows

package main

import (
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/whispaste/whispaste/internal/export"
	"github.com/whispaste/whispaste/internal/stats"

	"golang.org/x/sys/windows"

	webview "github.com/webview/webview_go"
)

var (
	mainWindowMu        sync.Mutex
	mainWindowOpen      bool
	mainWindowHwnd      uintptr
	mainWebview         webview.WebView
	lastRecordingState  AppState // last state pushed via NotifyRecordingState
	forceOnboardingFlag bool     // set via --onboarding CLI flag
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

// jsStr JSON-encodes a string for safe embedding in JavaScript code.
func jsStr(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// base64Encode encodes binary data to standard base64.
func base64Encode(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// checkConnectivity tests internet connectivity by pinging model download endpoints.
func checkConnectivity() bool {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Head("https://huggingface.co")
	if err != nil {
		logDebug("Connectivity check failed: %v", err)
		return false
	}
	resp.Body.Close()
	return resp.StatusCode < 500
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
	pages := collectEmbeddedFiles(uiMainFS, "ui_main/pages", ".html")

	html := string(tmpl)
	html = strings.Replace(html, "/* {{STYLES}} */", css, 1)
	html = strings.Replace(html, "/* {{SCRIPTS}} */", js, 1)
	html = strings.Replace(html, "<!-- {{PAGES}} -->", pages, 1)
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
		if ext == ".html" {
			buf.WriteString("<!-- --- " + name + " --- -->\n")
		} else {
			buf.WriteString("/* --- " + name + " --- */\n")
		}
		buf.Write(data)
		buf.WriteByte('\n')
	}
	return buf.String()
}

// CloseMainWindow terminates the main window if it's open.
func CloseMainWindow() {
	mainWindowMu.Lock()
	wv := mainWebview
	mainWindowMu.Unlock()
	if wv != nil {
		logDebug("CloseMainWindow: terminating main window")
		wv.Terminate()
	}
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
func ShowMainWindow(cfg *Config, recorder *Recorder, history *History, usageStats *stats.UsageStats, onSaved func(), onClose func(), onCapture func(), initialPage string) {
	mainWindowMu.Lock()
	if mainWindowOpen {
		wv := mainWebview
		hwnd := mainWindowHwnd
		mainWindowMu.Unlock()

		// Navigate to the requested page if specified
		if initialPage != "" && wv != nil {
			page := initialPage
			if page == "smart-mode" {
				page = "smartmode"
			}
			wv.Dispatch(func() {
				wv.Eval(fmt.Sprintf(`if(typeof switchPage==='function')switchPage('%s')`, page))
			})
		}

		if hwnd != 0 {
			user32 := windows.NewLazySystemDLL("user32.dll")
			kernel32 := windows.NewLazySystemDLL("kernel32.dll")
			setForeground := user32.NewProc("SetForegroundWindow")
			showWin := user32.NewProc("ShowWindow")
			bringToTop := user32.NewProc("BringWindowToTop")
			getForeground := user32.NewProc("GetForegroundWindow")
			getWindowThreadProcessId := user32.NewProc("GetWindowThreadProcessId")
			attachThreadInput := user32.NewProc("AttachThreadInput")
			getCurrentThreadId := kernel32.NewProc("GetCurrentThreadId")
			showWin.Call(hwnd, 9) // SW_RESTORE
			// AttachThreadInput trick for reliable foreground
			fgHwnd, _, _ := getForeground.Call()
			if fgHwnd != 0 {
				fgThread, _, _ := getWindowThreadProcessId.Call(fgHwnd, 0)
				curThread, _, _ := getCurrentThreadId.Call()
				if fgThread != curThread {
					attachThreadInput.Call(curThread, fgThread, 1) // attach
					setForeground.Call(hwnd)
					bringToTop.Call(hwnd)
					attachThreadInput.Call(curThread, fgThread, 0) // detach
				} else {
					setForeground.Call(hwnd)
					bringToTop.Call(hwnd)
				}
			} else {
				setForeground.Call(hwnd)
			}
		}
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

		w.SetTitle("WhisPaste — " + T("app.notebook"))
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

		// Bind: _logJS → allows JS to log messages to the Go logger
		w.Bind("_logJS", func(level, msg string) {
			switch level {
			case "error":
				logError("JS: %s", msg)
			case "warn":
				logWarn("JS: %s", msg)
			default:
				logDebug("JS: %s", msg)
			}
		})

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
		logDebug("Theme: injecting '%s' from config", cfg.GetTheme())
		// Set data-theme attribute immediately so CSS variables apply before first paint (prevents white flash)
		// Guard against document.documentElement being null on about:blank
		initJS := fmt.Sprintf(`(function(){var d=document.documentElement;if(!d)return;var t=%s;if(t==='system')t=window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light';if(t==='dark')d.setAttribute('data-theme','dark');})();`, themeJSON)
		initJS += fmt.Sprintf(`window._lang = %s; window._theme = %s; window._initialPage = "%s";`, langJSON, themeJSON, effectivePage)
		if !cfg.GetOnboardingDone() || forceOnboardingFlag {
			initJS += ` window._showOnboarding = true;`
			forceOnboardingFlag = false // reset so re-opens don't re-trigger
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

		// Register domain-specific bindings
		bindSettingsHandlers(w, cfg, recorder, onSaved)
		bindHistoryHandlers(w, cfg, history, usageStats, onCapture)
		bindSmartHandlers(w, cfg, history)
		bindUIHandlers(w, cfg, recorder, history, usageStats)
		w.SetHtml(mainWindowHTML)
		w.Run()
		logDebug("Main window closed — invoking cleanup")
		// Window closed — stop any running audio monitor
		if recorder != nil {
			recorder.StopMonitor()
		}
		// Close log viewer if open
		CloseLogViewer()
		// Notify caller
		if onClose != nil {
			logDebug("Main window: calling onClose callback")
			onClose()
		}
	}()
}

func toExportEntry(e *HistoryEntry) *export.Entry {
	return &export.Entry{
		ID:          e.ID,
		Text:        e.Text,
		Title:       e.Title,
		Timestamp:   e.Timestamp,
		Duration:    e.Duration,
		Language:    e.Language,
		Tags:        e.Tags,
		Pinned:      e.Pinned,
		Model:       e.Model,
		IsLocal:     e.IsLocal,
		CostUSD:     e.CostUSD,
		ProjectName: e.ProjectName,
	}
}
