package main

import (
	"context"
	_ "embed"
	"fmt"
	"os/exec"
	"sync"

	"github.com/getlantern/systray"
)

//go:embed resources/tray.ico
var embeddedTrayIcon []byte

const supportURL = "https://github.com/sponsors/silvio-l"

// AppTray manages the system tray icon and menu.
type AppTray struct {
	onSettings func(string)
	onQuit     func()
	updater    *Updater
	mUpdate    *systray.MenuItem
	updateInfo *UpdateInfo
	updateMu   sync.Mutex
	history    *History
}

// NewAppTray creates a tray manager. Callbacks are invoked on menu clicks.
func NewAppTray(onSettings func(string), onQuit func(), updater *Updater, history *History) *AppTray {
	return &AppTray{
		onSettings: onSettings,
		onQuit:     onQuit,
		updater:    updater,
		history:    history,
	}
}

// Run starts the system tray. This blocks the calling goroutine.
func (t *AppTray) Run() {
	systray.Run(t.onReady, t.onExit)
}

// Quit terminates the system tray event loop.
func (t *AppTray) Quit() {
	systray.Quit()
}

// ShowUpdateAvailable updates the tray menu to indicate a new version.
func (t *AppTray) ShowUpdateAvailable(info UpdateInfo) {
	t.updateMu.Lock()
	t.updateInfo = &info
	t.updateMu.Unlock()
	if t.mUpdate != nil {
		t.mUpdate.SetTitle(fmt.Sprintf(T("update.available"), info.Version))
		t.mUpdate.Show()
	}
}

func (t *AppTray) onReady() {
	systray.SetIcon(embeddedTrayIcon)
	systray.SetTitle(AppName)
	systray.SetTooltip(T("tray.status_ready"))

	mSettings := systray.AddMenuItem(T("tray.settings"), T("tray.settings"))
	mHistory := systray.AddMenuItem(T("tray.history"), T("tray.history"))
	t.mUpdate = systray.AddMenuItem(T("update.check"), T("update.check"))
	mAbout := systray.AddMenuItem(T("tray.about"), T("tray.about"))
	mSupport := systray.AddMenuItem(T("tray.support"), T("tray.support"))
	systray.AddSeparator()
	mQuit := systray.AddMenuItem(T("tray.quit"), T("tray.quit"))

	// Wire updater callback
	if t.updater != nil {
		t.updater.OnUpdateAvailable(func(info UpdateInfo) {
			t.ShowUpdateAvailable(info)
		})
		t.updater.Start(context.Background())
	}

	go func() {
		for {
			select {
			case <-mSettings.ClickedCh:
				if t.onSettings != nil {
					t.onSettings("general")
				}
			case <-mHistory.ClickedCh:
				t.showHistoryPopup()
			case <-t.mUpdate.ClickedCh:
				t.handleUpdateClick()
			case <-mAbout.ClickedCh:
				if t.onSettings != nil {
					t.onSettings("about")
				}
			case <-mSupport.ClickedCh:
				_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", supportURL).Start()
			case <-mQuit.ClickedCh:
				systray.Quit()
				return
			}
		}
	}()
}

func (t *AppTray) handleUpdateClick() {
	t.updateMu.Lock()
	info := t.updateInfo
	t.updateMu.Unlock()

	if info == nil || !info.Available {
		// No update stored yet — trigger a manual check
		if t.updater != nil {
			t.mUpdate.SetTitle(T("update.check"))
			go func() {
				result, err := t.updater.CheckNow(context.Background(), true)
				if err != nil {
					logWarn("Manual update check failed: %v", err)
					return
				}
				if result.Available {
					t.ShowUpdateAvailable(*result)
				} else {
					t.mUpdate.SetTitle(T("update.up_to_date"))
				}
			}()
		}
		return
	}

	t.mUpdate.SetTitle(T("update.downloading"))
	go func() {
		if err := t.updater.Apply(info); err != nil {
			logError("Update apply failed: %v", err)
			t.mUpdate.SetTitle(fmt.Sprintf(T("update.failed"), err))
			return
		}
		t.updateMu.Lock()
		t.updateInfo = nil
		t.updateMu.Unlock()
		t.mUpdate.SetTitle(T("update.ready"))
	}()
}

// SetTooltipState updates the tray tooltip to reflect current state.
func (t *AppTray) SetTooltipState(state AppState) {
	switch state {
	case StateRecording:
		systray.SetTooltip(T("tray.status_recording"))
	case StateTranscribing, StateProcessing:
		systray.SetTooltip(T("tray.status_working"))
	default:
		systray.SetTooltip(T("tray.status_ready"))
	}
}

func (t *AppTray) showHistoryPopup() {
	if t.history == nil {
		return
	}
	entries := t.history.Recent(1)
	if len(entries) == 0 {
		return
	}
	// Copy the most recent transcription to clipboard
	if err := writeClipboard(entries[0].Text); err != nil {
		logWarn("History copy failed: %v", err)
	} else {
		logInfo("Copied recent transcription to clipboard")
	}
}

func (t *AppTray) onExit() {
	logInfo("System tray exiting")
	if t.updater != nil {
		t.updater.Stop()
	}
	if t.onQuit != nil {
		t.onQuit()
	}
}
