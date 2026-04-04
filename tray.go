package main

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
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
	_NIM_MODIFY      = 0x00000001
	_NIM_SETVERSION  = 0x00000004
	_NIF_INFO        = 0x00000010
	_NIIF_INFO       = 0x00000001
	_NIIF_USER       = 0x00000004
	_NIIF_LARGE_ICON = 0x00000020
	_systrayUID      = 100 // UID used by getlantern/systray

	// NOTIFYICON_VERSION_4 enables modern notification behavior on Windows 10/11.
	// Without this, Shell_NotifyIconW NIF_INFO balloons may be silently dropped.
	_NOTIFYICON_VERSION_4 = 4

	// Tray icon left-click notification (lParam event in VERSION_4 callback)
	_NIN_SELECT = 0x0400 // WM_USER + 0
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

// verifySystrayWindow finds the SystrayClass window and verifies it belongs
// to our process. Returns the window handle or 0 if not found/wrong PID.
func verifySystrayWindow(caller string) uintptr {
	className, err := windows.UTF16PtrFromString("SystrayClass")
	if err != nil {
		logWarn("%s: UTF16 class failed: %v", caller, err)
		return 0
	}
	hwnd, _, _ := procFindWindow.Call(uintptr(unsafe.Pointer(className)), 0)
	if hwnd == 0 {
		logWarn("%s: systray window not found", caller)
		return 0
	}
	var windowPID uint32
	procGetWindowThreadProcess.Call(hwnd, uintptr(unsafe.Pointer(&windowPID)))
	ourPID, _, _ := procGetCurrentProcessId.Call()
	if windowPID != uint32(ourPID) {
		logWarn("%s: window PID %d != our PID %d", caller, windowPID, ourPID)
		return 0
	}
	return hwnd
}

// notifyIconDataW matches the Windows NOTIFYICONDATAW (Version 4) struct
// layout with correct SDK field offsets. cbSize = 976 on 64-bit, which is
// the proper size for the struct including hBalloonIcon. The getlantern/
// systray library has a bug (Timeout + Version = 8 bytes instead of a
// 4-byte union) giving cbSize=984, but Windows accepts NIM_MODIFY with
// the correct 976-byte size regardless of what NIM_ADD used.
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
}

// balloonAction describes what happens when the user clicks a balloon notification.
type balloonAction int

const (
	balloonActionNone    balloonAction = iota
	balloonActionSponsor               // open sponsor URL
	balloonActionRestart               // restart app after update
)

// AppTray manages the system tray icon and menu.
type AppTray struct {
	onOpenWindow          func(string) // opens unified window with page name: "history", "settings", "about", "smart-mode"
	onQuit                func()
	onToggle              func()
	updater               *Updater
	mToggle               *systray.MenuItem
	mUpdate               *systray.MenuItem
	updateInfo            *UpdateInfo
	updateMu              sync.Mutex
	history               *History
	balloonShown          bool // tracks whether minimize-to-tray balloon was shown this session
	cfg                   *Config
	smartItem             *systray.MenuItem  // single smart mode toggle
	autoPasteItem         *systray.MenuItem  // auto-paste toggle
	mStatus              *systray.MenuItem  // disabled status line
	mPreview             *systray.MenuItem  // last transcription preview
	onSaved               func()
	balloonIcon           uintptr       // HICON for balloon notifications
	pendingBalloonAction  balloonAction // what the next balloon click should do
	updateDownloaded      bool          // true after update binary has been downloaded
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

// enableDarkModeMenus calls the undocumented uxtheme SetPreferredAppMode +
// FlushMenuThemes APIs so native Win32 context menus follow the system dark
// mode setting. These ordinal-based APIs are used by major apps (VS Code,
// Notepad++, etc.) and have been stable since Windows 10 1903.
func enableDarkModeMenus() {
	dll, err := windows.LoadDLL("uxtheme.dll")
	if err != nil {
		logDebug("Could not load uxtheme.dll: %v", err)
		return
	}
	defer dll.Release()
	// SetPreferredAppMode (ordinal 135): 0=Default, 1=AllowDark, 2=ForceDark
	if proc, err := dll.FindProcByOrdinal(135); err == nil {
		proc.Call(1) // AllowDark
	}
	// FlushMenuThemes (ordinal 136): forces menu theme refresh
	if proc, err := dll.FindProcByOrdinal(136); err == nil {
		proc.Call()
	}
	logDebug("Dark mode menus enabled")
}

// Run starts the system tray. This blocks the calling goroutine.
func (t *AppTray) Run() {
	enableDarkModeMenus()
	systray.Run(t.onReady, t.onExit)
}

// Quit terminates the system tray event loop.
func (t *AppTray) Quit() {
	systray.Quit()
}

// ShowUpdateAvailable updates the tray menu to indicate a new version
// and shows a toast notification. Triggers auto-download in the background.
func (t *AppTray) ShowUpdateAvailable(info UpdateInfo) {
	t.updateMu.Lock()
	t.updateInfo = &info
	t.updateDownloaded = false
	t.updateMu.Unlock()
	if t.mUpdate != nil {
		t.mUpdate.SetTitle(fmt.Sprintf(T("update.available"), info.Version))
		t.mUpdate.Show()
	}
	// Notify user via toast and auto-download
	t.ShowBalloon(AppName, fmt.Sprintf(T("update.notify_downloading"), info.Version))
	go t.autoApplyUpdate(info)
}

// showUpdateCheckFailed updates the tray menu item to indicate that
// the last automatic update check could not reach GitHub.
func (t *AppTray) showUpdateCheckFailed() {
	if t.mUpdate != nil {
		t.mUpdate.SetTitle(T("update.check_failed"))
	}
}

// autoApplyUpdate downloads and installs an update in the background,
// then shows a toast notification prompting the user to restart.
func (t *AppTray) autoApplyUpdate(info UpdateInfo) {
	if t.mUpdate != nil {
		t.mUpdate.SetTitle(T("update.downloading"))
	}
	if err := t.updater.Apply(&info); err != nil {
		if errors.Is(err, ErrUpdateInProgress) {
			logDebug("Auto-update: another apply already running, skipping")
			return
		}
		if strings.Contains(err.Error(), "protected location") {
			logInfo("Auto-update failed (permission): %v", err)
			if t.mUpdate != nil {
				t.mUpdate.SetTitle(T("update.permission_failed"))
			}
			t.ShowBalloon(AppName, T("update.permission_hint"))
			return
		}
		logWarn("Auto-update failed: %v", err)
		if t.mUpdate != nil {
			t.mUpdate.SetTitle(fmt.Sprintf(T("update.failed"), err))
		}
		return
	}
	t.updateMu.Lock()
	t.updateInfo = nil
	t.updateDownloaded = true
	t.updateMu.Unlock()
	if t.mUpdate != nil {
		t.mUpdate.SetTitle(T("update.ready"))
	}
	logInfo("Auto-update downloaded successfully, prompting restart")
	t.showBalloonWithAction(balloonActionRestart, AppName, T("update.notify_ready"))
}

// restartApp starts a new instance of the application and exits the current one.
func restartApp() {
	exe, err := os.Executable()
	if err != nil {
		logError("restartApp: resolve exe: %v", err)
		return
	}
	logInfo("Restarting app: %s", exe)
	cmd := exec.Command(exe)
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: 0x00000008} // DETACHED_PROCESS
	if err := cmd.Start(); err != nil {
		logError("restartApp: start failed: %v", err)
		return
	}
	systray.Quit()
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
// It resets any pending balloon action so stale actions cannot leak to unrelated
// balloon clicks. Use showBalloonWithAction for balloons that should trigger
// an action on click.
func (t *AppTray) ShowBalloon(title, text string) {
	t.updateMu.Lock()
	t.pendingBalloonAction = balloonActionNone
	t.updateMu.Unlock()
	t.showBalloonRaw(title, text)
}

// showBalloonWithAction shows a balloon and atomically sets the pending action
// so the click handler knows what to do. This avoids a race between setting the
// action and showing the balloon.
func (t *AppTray) showBalloonWithAction(action balloonAction, title, text string) {
	t.updateMu.Lock()
	t.pendingBalloonAction = action
	t.updateMu.Unlock()
	// Bypass ShowBalloon (which resets the action) — call the Win32 API directly.
	t.showBalloonRaw(title, text)
}

// showBalloonRaw performs the raw Win32 Shell_NotifyIconW balloon call without
// touching pendingBalloonAction. ShowBalloon and showBalloonWithAction both
// delegate here after setting the action appropriately.
func (t *AppTray) showBalloonRaw(title, text string) {
	hwnd := verifySystrayWindow("ShowBalloon")
	if hwnd == 0 {
		return
	}

	infoFlags := uint32(_NIIF_INFO)
	iconHandle := t.balloonIcon
	if iconHandle != 0 {
		infoFlags = uint32(_NIIF_USER | _NIIF_LARGE_ICON)
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

	logDebug("ShowBalloon: hwnd=%d cbSize=%d flags=0x%X balloonIcon=%d title=%q", hwnd, nid.cbSize, infoFlags, iconHandle, title)
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
	hwnd := verifySystrayWindow("subclassSystrayWindow")
	if hwnd == 0 {
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
	hwnd := verifySystrayWindow("setNotifyIconVersion")
	if hwnd == 0 {
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
	action := t.pendingBalloonAction
	t.pendingBalloonAction = balloonActionNone
	t.updateMu.Unlock()
	switch action {
	case balloonActionSponsor:
		_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", supportURL).Start()
	case balloonActionRestart:
		restartApp()
	}
}

func (t *AppTray) onReady() {
	systray.SetIcon(embeddedTrayIcon)
	systray.SetTitle(AppName)
	systray.SetTooltip(T("tray.status_ready"))
	t.loadBalloonIcon()
	t.subclassSystrayWindow()
	t.setNotifyIconVersion()

	// Status line (disabled, informational)
	t.mStatus = systray.AddMenuItem("● "+T("floating.status_ready"), "")
	t.mStatus.Disable()

	// Last transcription preview (click to copy)
	t.mPreview = systray.AddMenuItem("", "")
	t.mPreview.Hide()

	go func() {
		for range t.mPreview.ClickedCh {
			t.copyLatestTranscription()
		}
	}()

	systray.AddSeparator()

	// Start/Stop Recording with hotkey display
	hotkeyStr := t.formatHotkey()
	toggleLabel := T("tray.start_record")
	if hotkeyStr != "" {
		toggleLabel += "\t" + hotkeyStr
	}
	t.mToggle = systray.AddMenuItem(toggleLabel, T("tray.start_record"))
	systray.AddSeparator()

	// Smart Mode — simple on/off toggle (preset selection in Settings)
	mSmart := systray.AddMenuItem(T("tray.smart_mode"), T("tray.smart_mode"))
	t.smartItem = mSmart
	t.updateSmartCheck()

	go func() {
		for range mSmart.ClickedCh {
			t.cfg.mu.Lock()
			t.cfg.SmartMode = !t.cfg.SmartMode
			t.cfg.mu.Unlock()
			if err := t.cfg.Save(); err != nil {
				logWarn("Failed to save smart mode: %v", err)
			}
			t.updateSmartCheck()
			if t.onSaved != nil {
				t.onSaved()
			}
		}
	}()

	// Auto-Paste — quick toggle for automatic text insertion
	mAutoPaste := systray.AddMenuItem(T("tray.auto_paste"), T("tray.auto_paste"))
	t.autoPasteItem = mAutoPaste
	t.updateAutoPasteCheck()

	go func() {
		for range mAutoPaste.ClickedCh {
			t.cfg.mu.Lock()
			t.cfg.AutoPaste = !t.cfg.AutoPaste
			t.cfg.mu.Unlock()
			if err := t.cfg.Save(); err != nil {
				logWarn("Failed to save auto-paste: %v", err)
			}
			t.updateAutoPasteCheck()
			logInfo("Tray toggled Auto-Paste: %v", t.cfg.GetAutoPaste())
			if t.onSaved != nil {
				t.onSaved()
			}
		}
	}()

	systray.AddSeparator()
	mOpen := systray.AddMenuItem(T("tray.open"), T("tray.open_desc"))

	// History submenu
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
	mFeedback := systray.AddMenuItem(T("tray.feedback"), T("tray.feedback_desc"))
	t.mUpdate = systray.AddMenuItem(T("update.check"), T("update.check"))
	systray.AddSeparator()
	mQuit := systray.AddMenuItem(T("tray.quit"), T("tray.quit"))

	// Wire updater callback
	if t.updater != nil {
		t.updater.OnUpdateAvailable(func(info UpdateInfo) {
			t.ShowUpdateAvailable(info)
		})
		t.updater.OnCheckFailed(func() {
			t.showUpdateCheckFailed()
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
			case <-mOpen.ClickedCh:
				if t.onOpenWindow != nil {
					t.onOpenWindow("")
				}
			case <-mFeedback.ClickedCh:
				if t.onOpenWindow != nil {
					t.onOpenWindow("feedback")
				}
			case <-t.mUpdate.ClickedCh:
				t.handleUpdateClick()
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
	downloaded := t.updateDownloaded
	t.updateMu.Unlock()

	// Update already downloaded — restart to activate
	if downloaded {
		restartApp()
		return
	}

	if info == nil || !info.Available {
		// No update stored yet — trigger a manual check
		if t.updater != nil {
			t.mUpdate.SetTitle(T("update.check"))
			go func() {
				result, err := t.updater.CheckNow(context.Background(), true)
				if err != nil {
					logWarn("Manual update check failed: %v", err)
					t.mUpdate.SetTitle(T("update.check_failed"))
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

	// Update available but auto-download may not have started yet — trigger manually
	t.mUpdate.SetTitle(T("update.downloading"))
	go t.autoApplyUpdate(*info)
}

// SetTooltipState updates the tray tooltip to reflect current state.
func (t *AppTray) SetTooltipState(state AppState) {
	hotkeyStr := t.formatHotkey()
	appendHotkey := func(label string) string {
		if hotkeyStr != "" {
			return label + "\t" + hotkeyStr
		}
		return label
	}

	switch state {
	case StateRecording:
		systray.SetTooltip(T("tray.status_recording"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(appendHotkey(T("tray.stop_record")))
			t.mToggle.SetTooltip(T("tray.stop_record"))
		}
		if t.mStatus != nil {
			t.mStatus.SetTitle("● " + T("floating.status_record"))
		}
	case StatePaused:
		systray.SetTooltip(T("tray.status_paused"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(appendHotkey(T("tray.stop_record")))
			t.mToggle.SetTooltip(T("tray.stop_record"))
		}
		if t.mStatus != nil {
			t.mStatus.SetTitle("● " + T("floating.status_record"))
		}
	case StateTranscribing, StateProcessing:
		systray.SetTooltip(T("tray.status_working"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(appendHotkey(T("tray.start_record")))
			t.mToggle.SetTooltip(T("tray.start_record"))
		}
		if t.mStatus != nil {
			t.mStatus.SetTitle("● " + T("floating.status_working"))
		}
	default:
		systray.SetTooltip(T("tray.status_ready"))
		if t.mToggle != nil {
			t.mToggle.SetTitle(appendHotkey(T("tray.start_record")))
			t.mToggle.SetTooltip(T("tray.start_record"))
		}
		if t.mStatus != nil {
			t.mStatus.SetTitle("● " + T("floating.status_ready"))
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

	// Update last-text preview item
	if t.mPreview != nil {
		if len(entries) > 0 && entries[0].Text != "" {
			preview := truncateRunes(entries[0].Text, 35)
			t.mPreview.SetTitle(fmt.Sprintf(T("floating.last_text"), preview))
			t.mPreview.Show()
		} else {
			t.mPreview.Hide()
		}
	}

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
	t.showBalloonWithAction(balloonActionSponsor, T("balloon.sponsor_title"), T("balloon.sponsor"))
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

// updateSmartCheck updates the tray Smart Mode item check state.
func (t *AppTray) updateSmartCheck() {
	if t.smartItem == nil {
		return
	}
	if t.cfg.GetSmartMode() {
		t.smartItem.Check()
	} else {
		t.smartItem.Uncheck()
	}
}

// updateAutoPasteCheck updates the tray Auto-Paste item check state.
func (t *AppTray) updateAutoPasteCheck() {
	if t.autoPasteItem == nil {
		return
	}
	if t.cfg.GetAutoPaste() {
		t.autoPasteItem.Check()
	} else {
		t.autoPasteItem.Uncheck()
	}
}

// formatHotkey returns the current hotkey as display string (e.g. "Ctrl+Shift+D").
func (t *AppTray) formatHotkey() string {
	if t.cfg == nil {
		return ""
	}
	t.cfg.mu.RLock()
	mods := t.cfg.HotkeyMods
	key := t.cfg.HotkeyKey
	t.cfg.mu.RUnlock()
	if len(mods) == 0 && key == "" {
		return ""
	}
	return strings.Join(mods, "+") + "+" + key
}

// copyLatestTranscription copies the most recent transcription to the clipboard.
func (t *AppTray) copyLatestTranscription() {
	if t.history == nil {
		return
	}
	entries := t.history.Recent(1)
	if len(entries) == 0 || entries[0].Text == "" {
		return
	}
	text := entries[0].Text
	if err := writeClipboard(text); err != nil {
		logWarn("Tray preview copy failed: %v", err)
		return
	}
	logInfo("Copied latest transcription from tray menu (%d chars)", len(text))
	preview := truncateRunes(text, 200)
	t.ShowBalloon(T("balloon.copied"), preview)
}

func (t *AppTray) onExit() {
	logInfo("System tray exiting")
	exitStart := time.Now()
	if t.updater != nil {
		t.updater.Stop()
		logDebug("Shutdown: updater stopped (%dms)", time.Since(exitStart).Milliseconds())
	}
	if t.onQuit != nil {
		t.onQuit()
	}
	if t.balloonIcon != 0 {
		procDestroyIcon := trayUser32.NewProc("DestroyIcon")
		procDestroyIcon.Call(t.balloonIcon)
	}
	logInfo("Cleanup complete (%dms), exiting process", time.Since(exitStart).Milliseconds())
	os.Exit(0)
}
