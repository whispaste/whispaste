package main

import (
	_ "embed"
	"os/exec"

	"github.com/getlantern/systray"
)

//go:embed resources/tray.ico
var embeddedTrayIcon []byte

const supportURL = "https://github.com/sponsors/silvio-l"

// AppTray manages the system tray icon and menu.
type AppTray struct {
	onSettings func()
	onQuit     func()
}

// NewAppTray creates a tray manager. Callbacks are invoked on menu clicks.
func NewAppTray(onSettings func(), onQuit func()) *AppTray {
	return &AppTray{
		onSettings: onSettings,
		onQuit:     onQuit,
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

func (t *AppTray) onReady() {
	systray.SetIcon(embeddedTrayIcon)
	systray.SetTitle(AppName)
	systray.SetTooltip(T("tray.tooltip"))

	mSettings := systray.AddMenuItem(T("tray.settings"), T("tray.settings"))
	mAbout := systray.AddMenuItem(T("tray.about"), T("tray.about"))
	mSupport := systray.AddMenuItem(T("tray.support"), T("tray.support"))
	systray.AddSeparator()
	mQuit := systray.AddMenuItem(T("tray.quit"), T("tray.quit"))

	go func() {
		for {
			select {
			case <-mSettings.ClickedCh:
				if t.onSettings != nil {
					t.onSettings()
				}
			case <-mAbout.ClickedCh:
				if t.onSettings != nil {
					t.onSettings()
				}
			case <-mSupport.ClickedCh:
				exec.Command("rundll32", "url.dll,FileProtocolHandler", supportURL).Start()
			case <-mQuit.ClickedCh:
				if t.onQuit != nil {
					t.onQuit()
				}
				return
			}
		}
	}()
}

func (t *AppTray) onExit() {}
