package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"

	"golang.org/x/sys/windows"

	webview "github.com/webview/webview_go"
)

var (
	notebookMu   sync.Mutex
	notebookOpen bool
	notebookHwnd uintptr

	nbUser32 = windows.NewLazySystemDLL("user32.dll")
)

//go:embed ui_notebook.html
var notebookHTML string

// ShowNotebook opens the notebook window with WebView2.
func ShowNotebook(history *History, openSettings func()) {
	notebookMu.Lock()
	if notebookOpen {
		if notebookHwnd != 0 {
			setForeground := nbUser32.NewProc("SetForegroundWindow")
			showWin := nbUser32.NewProc("ShowWindow")
			showWin.Call(notebookHwnd, 9) // SW_RESTORE
			setForeground.Call(notebookHwnd)
		}
		notebookMu.Unlock()
		return
	}
	notebookOpen = true
	notebookMu.Unlock()

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		defer func() {
			notebookMu.Lock()
			notebookOpen = false
			notebookHwnd = 0
			notebookMu.Unlock()
		}()

		w := webview.New(true)
		if w == nil {
			return
		}
		defer w.Destroy()

		w.SetTitle("WhisPaste")
		w.SetSize(1000, 650, webview.HintNone)
		w.SetSize(700, 450, webview.HintMin)

		hwndPtr := w.Window()
		hwnd := uintptr(hwndPtr)

		notebookMu.Lock()
		notebookHwnd = hwnd
		notebookMu.Unlock()

		showWindow := nbUser32.NewProc("ShowWindow")
		const swHide = 0
		const swShow = 5
		showWindow.Call(hwnd, swHide)

		setWindowIcon(hwndPtr)

		w.Bind("windowReady", func() {
			showWindow.Call(hwnd, swShow)
		})

		w.Init(fmt.Sprintf(`window._lang = "%s";`, currentLang))

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

		// Bind: closeNotebook
		w.Bind("closeNotebook", func() {
			w.Terminate()
		})

		// Bind: openLogFile → opens the log file in default editor
		w.Bind("openLogFile", func() {
			logDir, err := configDir()
			if err != nil {
				logWarn("Could not determine config dir: %v", err)
				return
			}
			logPath := filepath.Join(logDir, "whispaste.log")
			exec.Command("cmd", "/c", "start", "", logPath).Start()
		})

		// Bind: startCapture → placeholder for dashboard recording
		w.Bind("startCapture", func() {
			logInfo("Capture from dashboard not yet implemented")
		})

		// Bind: openSettingsBinding → opens settings window
		w.Bind("openSettingsBinding", func() {
			if openSettings != nil {
				go openSettings()
			}
		})

		// Bind: getTranslations → returns notebook l10n strings
		w.Bind("getTranslations", func() (string, error) {
			keys := []string{
				"notebook.title", "notebook.search", "notebook.all",
				"notebook.pinned", "notebook.today", "notebook.this_week",
				"notebook.older", "notebook.empty", "notebook.no_results",
				"notebook.copy", "notebook.delete", "notebook.pin",
				"notebook.unpin", "notebook.copied", "notebook.confirm_delete",
				"notebook.uncategorized",
				"notebook.sort_newest", "notebook.sort_oldest",
				"notebook.sort_alpha", "notebook.sort_duration",
				"notebook.add_tag", "notebook.tag_updated",
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

		w.SetHtml(notebookHTML)
		w.Run()
	}()
}
