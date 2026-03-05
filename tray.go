package main

import (
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/getlantern/systray"
	"golang.org/x/sys/windows"
)

const _HISTORY_SLOTS = 10

//go:embed resources/tray.ico
var embeddedTrayIcon []byte

const supportURL = "https://github.com/sponsors/silvio-l"

// Win32 balloon notification constants and API
const (
	_NIM_MODIFY     = 0x00000001
	_NIM_SETVERSION = 0x00000004
	_NIF_INFO       = 0x00000010
	_NIIF_INFO      = 0x00000001
	_NIIF_USER      = 0x00000004
	_systrayUID     = 100 // UID used by getlantern/systray

	// NOTIFYICON_VERSION_4 enables modern notification behavior on Windows 10/11.
	// Without this, Shell_NotifyIconW NIF_INFO balloons may be silently dropped.
	_NOTIFYICON_VERSION_4 = 4

	// Tray icon left-click notification (lParam event in VERSION_4 callback)
	_NIN_SELECT           = 0x0400 // WM_USER + 0
	// Balloon click notification (lParam value in systray callback)
	_NIN_BALLOONUSERCLICK = 0x0405 // WM_USER + 5
	// systray callback message (WM_USER + 1, set by getlantern/systray v1.2.2)
	_WM_SYSTRAY_CALLBACK = 0x0401
	_GWLP_WNDPROC        = ^uintptr(3) // -4
)

var (
	trayShell32                = windows.NewLazySystemDLL("shell32.dll")
	trayUser32                 = windows.NewLazySystemDLL("user32.dll")
	trayKernel32               = windows.NewLazySystemDLL("kernel32.dll")
	procShellNotifyIcon        = trayShell32.NewProc("Shell_NotifyIconW")
	procFindWindow             = trayUser32.NewProc("FindWindowW")
	procGetWindowThreadProcess = trayUser32.NewProc("GetWindowThreadProcessId")
	procGetCurrentProcessId    = trayKernel32.NewProc("GetCurrentProcessId")
	procSetWindowLongPtrW      = trayUser32.NewProc("SetWindowLongPtrW")
	procCallWindowProcW        = trayUser32.NewProc("CallWindowProcW")
	procRegisterWindowMessage  = trayUser32.NewProc("RegisterWindowMessageW")
)

// Balloon click subclass: intercepts NIN_BALLOONUSERCLICK on the systray window.
var (
	globalTrayRef          *AppTray
	globalOrigWndProc      uintptr
	globalTaskbarCreatedID uint32 // registered "TaskbarCreated" message for explorer restart
	traySubclassProc       = syscall.NewCallback(traySubclassWndProc)
)

func traySubclassWndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	if uint32(msg) == _WM_SYSTRAY_CALLBACK {
		// Extract event from LOWORD(lParam). This works for both
		// NOTIFYICON_VERSION 0 (lParam = event) and VERSION_4
		// (lParam = MAKELONG(event, iconID)).
		event := uint16(lParam)
		if event == uint16(_NIN_SELECT) {
			// Left-click on tray icon → open dashboard
			if t := globalTrayRef; t != nil && t.onOpenWindow != nil {
				go t.onOpenWindow("")
			}
			return 0
		}
		// In VERSION_4, left-click also sends WM_LBUTTONUP (0x0202).
		// Suppress it so the systray library doesn't show the context menu.
		if event == 0x0202 {
			return 0
		}
		if event == uint16(_NIN_BALLOONUSERCLICK) {
			if t := globalTrayRef; t != nil {
				t.handleBalloonClick()
			}
		}
		// Strip HIWORD (icon ID in v4) so the systray library sees
		// the plain event value it expects from version 0.
		lParam = uintptr(event)
	}
	// Let the original wndProc handle the message first.
	ret, _, _ := procCallWindowProcW.Call(globalOrigWndProc, hwnd, msg, wParam, lParam)
	// After explorer.exe restarts, the systray library re-adds the icon
	// (NIM_ADD) which resets the version to 0. Re-apply VERSION_4.
	if globalTaskbarCreatedID != 0 && uint32(msg) == globalTaskbarCreatedID {
		if t := globalTrayRef; t != nil {
			t.setNotifyIconVersion()
		}
	}
	return ret
}

// notifyIconDataW matches the Windows NOTIFYICONDATAW struct layout.
// The trailing _pad field is required because getlantern/systray v1.2.2
// has a struct bug: it declares Timeout AND Version as separate uint32
// fields (8 bytes) where Windows has a 4-byte union. This makes the
// library's NIM_ADD use cbSize=984 instead of the correct 976. Windows
// may reject NIM_MODIFY calls with a different cbSize than NIM_ADD.
// Our padding keeps all field offsets correct while matching cbSize=984.
type notifyIconDataW struct {
	cbSize           uint32
	hWnd             uintptr
	uID              uint32
	uFlags           uint32
	uCallbackMessage uint32
	hIcon            uintptr
	szTip            [128]uint16
	dwState          uint32
	dwStateMask      uint32
	szInfo           [256]uint16
	uVersion         uint32
	szInfoTitle      [64]uint16
	dwInfoFlags      uint32
	guidItem         [16]byte
	hBalloonIcon     uintptr
	_pad             [8]byte // match systray library cbSize (984 vs 976)
}

// AppTray manages the system tray icon and menu.
type AppTray struct {
	onOpenWindow func(string) // opens unified window with page name: "history", "settings", "about", "smart-mode"
	onQuit       func()
	onToggle     func()
	updater      *Updater
	mToggle      *systray.MenuItem
	mUpdate      *systray.MenuItem
	updateInfo   *UpdateInfo
	updateMu     sync.Mutex
	history      *History
	balloonShown bool // tracks whether minimize-to-tray balloon was shown this session
	cfg          *Config
	smartItems   []*systray.MenuItem
	smartPresets []string
	onSaved      func()
	balloonIcon  uintptr // HICON for balloon notifications
	lastBalloonSponsor bool // true if last balloon was a sponsor notification
	// History submenu
	historyEmpty *systray.MenuItem
	historyItems [_HISTORY_SLOTS]*systray.MenuItem
	historyTexts [_HISTORY_SLOTS]string
	historyCount int
	historyMu    sync.Mutex
}

// NewAppTray creates a tray manager. Callbacks are invoked on menu clicks.
func NewAppTray(onOpenWindow func(string), onQuit func(), updater *Updater, history *History, cfg *Config, onSaved func(), onToggle func()) *AppTray {
	return &AppTray{
		onOpenWindow: onOpenWindow,
		onQuit:       onQuit,
		onToggle:     onToggle,
		updater:      updater,
		history:      history,
		cfg:          cfg,
		onSaved:      onSaved,
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

// ShowMinimizeBalloon shows a one-time notification that the app is still running.
func (t *AppTray) ShowMinimizeBalloon() {
	logDebug("ShowMinimizeBalloon: called (balloonShown=%v, notifyBg=%v)", t.balloonShown, t.cfg.GetNotifyBackground())
	if t.balloonShown {
		logDebug("ShowMinimizeBalloon: skipped — already shown this session")
		return
	}
	if !t.cfg.GetNotifyBackground() {
		logDebug("ShowMinimizeBalloon: skipped — notifications disabled in settings")
		return
	}
	t.balloonShown = true
	t.ShowBalloon(AppName, T("balloon.minimize"))
}

// loadBalloonIcon creates an HICON from embeddedAppIcon for balloon notifications.
// Uses the largest available icon entry for crisp notification display.
func (t *AppTray) loadBalloonIcon() {
	ico := embeddedAppIcon
	if len(ico) < 22 {
		logWarn("loadBalloonIcon: embedded icon too small (%d bytes)", len(ico))
		return
	}
	count := int(ico[4]) | int(ico[5])<<8
	if count < 1 {
		logWarn("loadBalloonIcon: no icon entries found")
		return
	}
	// Pick the largest icon entry (by data size)
	bestOff := 6
	bestSize := uint32(0)
	for i := 0; i < count; i++ {
		off := 6 + i*16
		if off+16 > len(ico) {
			break
		}
		ds := uint32(ico[off+8]) | uint32(ico[off+9])<<8 |
			uint32(ico[off+10])<<16 | uint32(ico[off+11])<<24
		if ds > bestSize {
			bestSize = ds
			bestOff = off
		}
	}
	if bestOff+16 > len(ico) {
		logWarn("loadBalloonIcon: best entry offset out of bounds")
		return
	}
	dataSize := uint32(ico[bestOff+8]) | uint32(ico[bestOff+9])<<8 |
		uint32(ico[bestOff+10])<<16 | uint32(ico[bestOff+11])<<24
	dataOffset := uint32(ico[bestOff+12]) | uint32(ico[bestOff+13])<<8 |
		uint32(ico[bestOff+14])<<16 | uint32(ico[bestOff+15])<<24
	if dataOffset+dataSize > uint32(len(ico)) {
		logWarn("loadBalloonIcon: data range out of bounds")
		return
	}
	iconData := ico[dataOffset : dataOffset+dataSize]
	proc := trayUser32.NewProc("CreateIconFromResourceEx")
	h, _, err := proc.Call(
		uintptr(unsafe.Pointer(&iconData[0])),
		uintptr(dataSize),
		1,          // fIcon = TRUE
		0x00030000, // version
		0, 0,       // use default size
		0, // LR_DEFAULTCOLOR
	)
	if h == 0 {
		logWarn("loadBalloonIcon: CreateIconFromResourceEx failed: %v", err)
	} else {
		logDebug("loadBalloonIcon: icon loaded (handle=%d)", h)
	}
	t.balloonIcon = h
}

// ShowBalloon shows a Windows balloon notification from the system tray icon.
func (t *AppTray) ShowBalloon(title, text string) {
	className, err := windows.UTF16PtrFromString("SystrayClass")
	if err != nil {
		logWarn("ShowBalloon: UTF16 class failed: %v", err)
		return
	}
	hwnd, _, _ := procFindWindow.Call(uintptr(unsafe.Pointer(className)), 0)
	if hwnd == 0 {
		logWarn("ShowBalloon: systray window not found")
		return
	}

	// Verify the found window belongs to our process
	var windowPID uint32
	procGetWindowThreadProcess.Call(hwnd, uintptr(unsafe.Pointer(&windowPID)))
	ourPID, _, _ := procGetCurrentProcessId.Call()
	if windowPID != uint32(ourPID) {
		logWarn("ShowBalloon: window PID %d != our PID %d, wrong SystrayClass window", windowPID, ourPID)
		return
	}

	// Use custom icon if available, otherwise fall back to system info icon
	infoFlags := uint32(_NIIF_USER)
	iconHandle := t.balloonIcon
	if iconHandle == 0 {
		infoFlags = _NIIF_INFO
	}

	nid := notifyIconDataW{
		hWnd:         hwnd,
		uID:          _systrayUID,
		uFlags:       _NIF_INFO,
		dwInfoFlags:  infoFlags,
		hBalloonIcon: iconHandle,
	}
	nid.cbSize = uint32(unsafe.Sizeof(nid))

	if titleUTF16, err := windows.UTF16FromString(title); err == nil {
		copy(nid.szInfoTitle[:63], titleUTF16)
	}
	if textUTF16, err := windows.UTF16FromString(text); err == nil {
		copy(nid.szInfo[:255], textUTF16)
	}

	logDebug("ShowBalloon: hwnd=%d pid=%d cbSize=%d flags=0x%X title=%q", hwnd, windowPID, nid.cbSize, infoFlags, title)
	ret, _, callErr := procShellNotifyIcon.Call(_NIM_MODIFY, uintptr(unsafe.Pointer(&nid)))
	if ret == 0 {
		if errno, ok := callErr.(syscall.Errno); ok {
			logWarn("ShowBalloon: Shell_NotifyIconW failed: errno=%d (%v)", uintptr(errno), callErr)
		} else {
			logWarn("ShowBalloon: Shell_NotifyIconW failed: %v", callErr)
		}
	} else {
		logDebug("ShowBalloon: notification shown successfully")
	}
}

// subclassSystrayWindow replaces the systray window procedure to intercept
// NIN_BALLOONUSERCLICK events (balloon notification clicks).
func (t *AppTray) subclassSystrayWindow() {
	className, err := windows.UTF16PtrFromString("SystrayClass")
	if err != nil {
		return
	}
	hwnd, _, _ := procFindWindow.Call(uintptr(unsafe.Pointer(className)), 0)
	if hwnd == 0 {
		logWarn("subclassSystrayWindow: window not found")
		return
	}
	var windowPID uint32
	procGetWindowThreadProcess.Call(hwnd, uintptr(unsafe.Pointer(&windowPID)))
	ourPID, _, _ := procGetCurrentProcessId.Call()
	if windowPID != uint32(ourPID) {
		return
	}
	globalTrayRef = t
	orig, _, callErr := procSetWindowLongPtrW.Call(hwnd, _GWLP_WNDPROC, traySubclassProc)
	if orig == 0 {
		logWarn("subclassSystrayWindow: SetWindowLongPtrW failed: %v", callErr)
		return
	}
	globalOrigWndProc = orig
	logDebug("subclassSystrayWindow: subclassed successfully")

	// Register "TaskbarCreated" to detect explorer.exe restarts
	if tbcName, err := windows.UTF16PtrFromString("TaskbarCreated"); err == nil {
		id, _, _ := procRegisterWindowMessage.Call(uintptr(unsafe.Pointer(tbcName)))
		if id != 0 {
			globalTaskbarCreatedID = uint32(id)
		}
	}
}

// setNotifyIconVersion sets NOTIFYICON_VERSION_4 on the systray icon so that
// balloon notifications are properly displayed as toast notifications on
// Windows 10/11. Must be called after subclassSystrayWindow (which translates
// version 4 callback messages for the systray library).
func (t *AppTray) setNotifyIconVersion() {
	className, err := windows.UTF16PtrFromString("SystrayClass")
	if err != nil {
		return
	}
	hwnd, _, _ := procFindWindow.Call(uintptr(unsafe.Pointer(className)), 0)
	if hwnd == 0 {
		logWarn("setNotifyIconVersion: window not found")
		return
	}
	var windowPID uint32
	procGetWindowThreadProcess.Call(hwnd, uintptr(unsafe.Pointer(&windowPID)))
	ourPID, _, _ := procGetCurrentProcessId.Call()
	if windowPID != uint32(ourPID) {
		return
	}
	nid := notifyIconDataW{
		hWnd:     hwnd,
		uID:      _systrayUID,
		uVersion: _NOTIFYICON_VERSION_4,
	}
	nid.cbSize = uint32(unsafe.Sizeof(nid))
	ret, _, callErr := procShellNotifyIcon.Call(_NIM_SETVERSION, uintptr(unsafe.Pointer(&nid)))
	if ret == 0 {
		logWarn("setNotifyIconVersion: NIM_SETVERSION failed: %v", callErr)
	} else {
		logDebug("setNotifyIconVersion: set NOTIFYICON_VERSION_4")
	}
}

// handleBalloonClick opens the sponsor URL when a sponsor balloon is clicked.
func (t *AppTray) handleBalloonClick() {
	t.updateMu.Lock()
	isSponsor := t.lastBalloonSponsor
	t.lastBalloonSponsor = false
	t.updateMu.Unlock()
	if isSponsor {
		_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", supportURL).Start()
	}
}

func (t *AppTray) onReady() {
	systray.SetIcon(embeddedTrayIcon)
	systray.SetTitle(AppName)
	systray.SetTooltip(T("tray.status_ready"))
	t.loadBalloonIcon()
	t.subclassSystrayWindow()
	t.setNotifyIconVersion()

	t.mToggle = systray.AddMenuItem(T("tray.start_record"), T("tray.start_record"))
	systray.AddSeparator()
	mDashboard := systray.AddMenuItem(T("tray.notebook"), T("tray.notebook"))

	// Smart Mode submenu
	mSmart := systray.AddMenuItem(T("tray.smart_mode"), T("tray.smart_mode"))
	smartDefs := []struct {
		preset string
		key    string
	}{
		{"off", "settings.smart_preset_off"},
		{"cleanup", "settings.smart_preset_cleanup"},
		{"concise", "settings.smart_preset_concise"},
		{"email", "settings.smart_preset_email"},
		{"bullets", "settings.smart_preset_bullets"},
		{"formal", "settings.smart_preset_formal"},
		{"aiprompt", "settings.smart_preset_aiprompt"},
		{"summary", "settings.smart_preset_summary"},
		{"notes", "settings.smart_preset_notes"},
		{"meeting", "settings.smart_preset_meeting"},
		{"social", "settings.smart_preset_social"},
		{"technical", "settings.smart_preset_technical"},
		{"casual", "settings.smart_preset_casual"},
		{"translate", "settings.smart_preset_translate"},
		{"custom", "settings.smart_preset_custom"},
	}
	subItems := make([]*systray.MenuItem, len(smartDefs))
	for i, d := range smartDefs {
		subItems[i] = mSmart.AddSubMenuItem(T(d.key), T(d.key))
	}
	t.smartItems = subItems
	t.smartPresets = make([]string, len(smartDefs))
	for i, d := range smartDefs {
		t.smartPresets[i] = d.preset
	}
	t.updateSmartCheckmarks()

	for i, item := range subItems {
		go func(idx int, menuItem *systray.MenuItem) {
			for range menuItem.ClickedCh {
				t.cfg.SetSmartModePreset(t.smartPresets[idx])
				if err := t.cfg.Save(); err != nil {
					logWarn("Failed to save smart mode: %v", err)
				}
				t.updateSmartCheckmarks()
				if t.onSaved != nil {
					t.onSaved()
				}
				// If "custom" selected with empty prompt, open settings at smart section
				if t.smartPresets[idx] == "custom" && t.cfg.GetSmartModePrompt() == "" {
					if t.onOpenWindow != nil {
						t.onOpenWindow("smart-mode")
					}
				}
			}
		}(i, item)
	}

	mHistory := systray.AddMenuItem(T("tray.history"), T("tray.history"))
	t.historyEmpty = mHistory.AddSubMenuItem(T("tray.history_empty"), "")
	t.historyEmpty.Disable()
	for i := 0; i < _HISTORY_SLOTS; i++ {
		t.historyItems[i] = mHistory.AddSubMenuItem("", "")
		t.historyItems[i].Hide()
	}
	t.updateHistoryMenu()

	for i := 0; i < _HISTORY_SLOTS; i++ {
		go func(idx int) {
			for range t.historyItems[idx].ClickedCh {
				t.copyHistoryEntry(idx)
			}
		}(i)
	}

	systray.AddSeparator()
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
			case <-t.mToggle.ClickedCh:
				if t.onToggle != nil {
					t.onToggle()
				}
			case <-mDashboard.ClickedCh:
				if t.onOpenWindow != nil {
					t.onOpenWindow("history")
				}
			case <-t.mUpdate.ClickedCh:
				t.handleUpdateClick()
			case <-mAbout.ClickedCh:
				if t.onOpenWindow != nil {
					t.onOpenWindow("about")
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
		if t.mToggle != nil {
			t.mToggle.SetTitle(T("tray.stop_record"))
			t.mToggle.SetTooltip(T("tray.stop_record"))
		}
	case StatePaused:
		systray.SetTooltip(T("tray.status_paused"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(T("tray.stop_record"))
			t.mToggle.SetTooltip(T("tray.stop_record"))
		}
	case StateTranscribing, StateProcessing:
		systray.SetTooltip(T("tray.status_working"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(T("tray.start_record"))
			t.mToggle.SetTooltip(T("tray.start_record"))
		}
	default:
		systray.SetTooltip(T("tray.status_ready"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(T("tray.start_record"))
			t.mToggle.SetTooltip(T("tray.start_record"))
		}
	}
}

func (t *AppTray) updateHistoryMenu() {
	if t.history == nil {
		return
	}
	entries := t.history.Recent(_HISTORY_SLOTS)

	t.historyMu.Lock()
	t.historyCount = len(entries)
	for i := 0; i < _HISTORY_SLOTS; i++ {
		if i < len(entries) {
			t.historyTexts[i] = entries[i].Text
		} else {
			t.historyTexts[i] = ""
		}
	}
	t.historyMu.Unlock()

	if len(entries) == 0 {
		t.historyEmpty.Show()
	} else {
		t.historyEmpty.Hide()
	}

	for i := 0; i < _HISTORY_SLOTS; i++ {
		if i < len(entries) {
			preview := truncateRunes(entries[i].Text, 40)
			ago := relativeTime(entries[i].Timestamp)
			if ago != "" {
				t.historyItems[i].SetTitle(fmt.Sprintf("%s  (%s)", preview, ago))
			} else {
				t.historyItems[i].SetTitle(preview)
			}
			t.historyItems[i].Show()
		} else {
			t.historyItems[i].Hide()
		}
	}
}

func (t *AppTray) copyHistoryEntry(idx int) {
	t.historyMu.Lock()
	if idx >= t.historyCount {
		t.historyMu.Unlock()
		return
	}
	text := t.historyTexts[idx]
	t.historyMu.Unlock()

	if err := writeClipboard(text); err != nil {
		logWarn("History copy failed: %v", err)
		return
	}
	logInfo("Copied history entry %d to clipboard", idx)
	preview := truncateRunes(text, 200)
	t.ShowBalloon(T("balloon.copied"), preview)
}

// MaybeSponsorBalloon shows a sponsor balloon every 50 dictations.
func (t *AppTray) MaybeSponsorBalloon(totalDictations int) {
	if totalDictations < 50 {
		return
	}
	if !t.cfg.GetNotifyDonate() {
		return
	}
	last := t.cfg.GetSponsorLastRemindedAt()
	if totalDictations < last+50 {
		return
	}
	t.cfg.SetSponsorLastRemindedAt(totalDictations)
	if err := t.cfg.Save(); err != nil {
		logWarn("Failed to save sponsor reminder: %v", err)
	}
	t.updateMu.Lock()
	t.lastBalloonSponsor = true
	t.updateMu.Unlock()
	t.ShowBalloon(T("balloon.sponsor_title"), T("balloon.sponsor"))
}

// RefreshHistory rebuilds the history submenu from disk. Call after adding entries.
func (t *AppTray) RefreshHistory() {
	t.updateHistoryMenu()
}

func truncateRunes(s string, max int) string {
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max]) + "…"
}

func relativeTime(ts string) string {
	t, err := time.Parse(time.RFC3339, ts)
	if err != nil {
		return ""
	}
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "<1m"
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

// updateSmartCheckmarks checks the active preset and unchecks others.
func (t *AppTray) updateSmartCheckmarks() {
	if t.cfg == nil || len(t.smartItems) == 0 {
		return
	}
	currentPreset := "off"
	if t.cfg.GetSmartMode() {
		currentPreset = t.cfg.GetSmartModePreset()
		if currentPreset == "" {
			currentPreset = "cleanup"
		}
	}
	for i, item := range t.smartItems {
		if t.smartPresets[i] == currentPreset {
			item.Check()
		} else {
			item.Uncheck()
		}
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
	logInfo("Cleanup complete, exiting process")
	os.Exit(0)
}
