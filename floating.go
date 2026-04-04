//go:build windows

package main

import (
	_ "embed"
	"fmt"
	"math"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

//go:embed "resources/app-icon ohne bg for light.png"
var appLogoForLight []byte

//go:embed "resources/app-icon ohne bg for dark.png"
var appLogoForDark []byte

// ───────────────────── Floating Button Constants ─────────────────────

const (
	_FLOAT_SIZE = 56 // diameter in pixels

	// Custom window messages (offset from overlay to avoid collision)
	_WM_FLOAT_SHOW     = _WM_USER + 20
	_WM_FLOAT_HIDE     = _WM_USER + 21
	_WM_FLOAT_RERENDER = _WM_USER + 22
	_WM_FLOAT_RESIZE   = _WM_USER + 23
	_WM_FLOAT_OPACITY  = _WM_USER + 24

	// Edge snapping threshold
	_FLOAT_SNAP_PX = 10

	// Icon color
	_FLOAT_CLR_ICON = 0xFFFFFFFF // white mic icon

	// Context menu IDs
	_FLOAT_MENU_SMART_MODE = 1
	_FLOAT_MENU_DASHBOARD  = 2
	_FLOAT_MENU_SETTINGS   = 3
	_FLOAT_MENU_HIDE       = 4
	_FLOAT_MENU_QUIT       = 5
	_FLOAT_MENU_RECORD     = 6
	_FLOAT_MENU_PREVIEW    = 7
	_FLOAT_MENU_LOCK       = 8
	_FLOAT_MENU_AUTO_PASTE = 9

	// Win32 menu constants
	_MF_STRING       = 0x0000
	_MF_SEPARATOR    = 0x0800
	_MF_CHECKED      = 0x0008
	_MF_GRAYED       = 0x0001
	_TPM_RIGHTBUTTON = 0x0002

	// Non-client messages (needed because HTCAPTION consumes LBUTTONxx/RBUTTONxx)
	_WM_NCLBUTTONDOWN = 0x00A1
	_WM_NCLBUTTONUP   = 0x00A2
	_WM_NCRBUTTONUP   = 0x00A5
	_WM_NCMOUSEMOVE   = 0x00A0
	_WM_NCMOUSELEAVE  = 0x02A2

	// Mouse tracking
	_TME_LEAVE      = 0x00000002
	_TME_NONCLIENT  = 0x00000010
	_WM_MOUSEMOVE   = 0x0200
	_WM_MOUSELEAVE  = 0x02A3
	_WM_MOVE        = 0x0003
	_WM_COMMAND     = 0x0111

	// Monitor info
	_MONITOR_DEFAULTTONEAREST = 0x00000002

	// DPI change
	_WM_DPICHANGED = 0x02E0

	// Timer for periodic topmost re-assertion
	_FLOAT_TIMER_ID = 2    // distinct from overlay's _TIMER_ID=1
	_FLOAT_TIMER_MS = 2000 // re-assert topmost every 2 seconds

	// Timer for double-click detection (delays single-click action)
	_FLOAT_DBLCLK_TIMER_ID = 3

	// Timer for re-rendering (countdown arc updates during recording)
	_FLOAT_ANIM_TIMER_ID = 4
	_FLOAT_ANIM_TIMER_MS = 500 // ~2 FPS for countdown arc during recording

	// Timer for idle animation effects (pulse, breathe, glow)
	_FLOAT_IDLE_ANIM_TIMER_ID = 5
	_FLOAT_IDLE_ANIM_TIMER_MS = 100 // 10 FPS for smooth idle animations

	// Tooltip constants
	_TTS_ALWAYSTIP      = 0x01
	_TTS_NOPREFIX       = 0x02
	_TTM_ADDTOOLW       = 0x0432
	_TTM_UPDATETIPTEXTW = 0x0439
	_TTF_IDISHWND       = 0x0001
	_TTF_SUBCLASS       = 0x0010

	// Double-click class style
	_CS_DBLCLKS = 0x0008

	// Non-client double-click
	_WM_NCLBUTTONDBLCLK = 0x00A6
	_WM_LBUTTONDBLCLK   = 0x0203

	// Recording countdown arc color (cyan, 80% opacity)
	_FLOAT_ARC_COLOR = 0xCC00E5FF
)

// Win32 structs for floating button
type monitorInfo struct {
	CbSize    uint32
	RcMonitor rectT
	RcWork    rectT
	DwFlags   uint32
}

// Win32 procs (reuse overlay DLL handles)
var (
	procCreatePopupMenu     = ovlUser32.NewProc("CreatePopupMenu")
	procAppendMenuW         = ovlUser32.NewProc("AppendMenuW")
	procTrackPopupMenu      = ovlUser32.NewProc("TrackPopupMenu")
	procDestroyMenu         = ovlUser32.NewProc("DestroyMenu")
	procSetForegroundWindow = ovlUser32.NewProc("SetForegroundWindow")
	procMonitorFromWindow   = ovlUser32.NewProc("MonitorFromWindow")
	procGetMonitorInfoW     = ovlUser32.NewProc("GetMonitorInfoW")
	procDestroyWindow       = ovlUser32.NewProc("DestroyWindow")
	procGetWindowRect       = ovlUser32.NewProc("GetWindowRect")
	procMoveWindow          = ovlUser32.NewProc("MoveWindow")
	procGetDpiForWindow     = ovlUser32.NewProc("GetDpiForWindow")
	procSendMessageW        = ovlUser32.NewProc("SendMessageW")
	procGetDoubleClickTime  = ovlUser32.NewProc("GetDoubleClickTime")

	// GDI+ string alignment (used in drawMicIcon)
	procGdipSetStringFormatAlign     = ovlGdiplus.NewProc("GdipSetStringFormatAlign")
	procGdipSetStringFormatLineAlign = ovlGdiplus.NewProc("GdipSetStringFormatLineAlign")
	procGdipSetStringFormatTrimming  = ovlGdiplus.NewProc("GdipSetStringFormatTrimming")

	// GDI+ world transform (used for scaling the mic icon)
	procGdipScaleWorldTransform     = ovlGdiplus.NewProc("GdipScaleWorldTransform")
	procGdipTranslateWorldTransform = ovlGdiplus.NewProc("GdipTranslateWorldTransform")
	procGdipResetWorldTransform     = ovlGdiplus.NewProc("GdipResetWorldTransform")

	// GDI+ arc drawing (used for recording countdown ring)
	procGdipDrawArc = ovlGdiplus.NewProc("GdipDrawArc")

	// GDI+ path flattening (used for shape-aware countdown arc)
	procGdipFlattenPath   = ovlGdiplus.NewProc("GdipFlattenPath")
	procGdipGetPointCount = ovlGdiplus.NewProc("GdipGetPointCount")
	procGdipGetPathPoints = ovlGdiplus.NewProc("GdipGetPathPoints")

	// GDI+ gradient from two points (arbitrary angle)
	procGdipCreateLineBrush = ovlGdiplus.NewProc("GdipCreateLineBrush")

	// GDI+ float-based ellipse fill (used for processing icon dots)
	procGdipFillEllipse = ovlGdiplus.NewProc("GdipFillEllipse")

	// GDI+ clipping (used to clip gradient to shape path)
	procGdipSetClipPath    = ovlGdiplus.NewProc("GdipSetClipPath")
	procGdipResetClip      = ovlGdiplus.NewProc("GdipResetClip")

	// GDI+ path figure start (used for polygon shapes)
	procGdipStartPathFigure = ovlGdiplus.NewProc("GdipStartPathFigure")

	// GDI+ image loading (used for custom button icon)
	procGdipLoadImageFromFile    = ovlGdiplus.NewProc("GdipLoadImageFromFile")
	procGdipGetImageWidth        = ovlGdiplus.NewProc("GdipGetImageWidth")
	procGdipGetImageHeight       = ovlGdiplus.NewProc("GdipGetImageHeight")
	procGdipCreateBitmapFromStream = ovlGdiplus.NewProc("GdipCreateBitmapFromStream")

	// GDI+ ImageAttributes for alpha-blended PNG drawing
	procGdipCreateImageAttributes          = ovlGdiplus.NewProc("GdipCreateImageAttributes")
	procGdipSetImageAttributesColorMatrix  = ovlGdiplus.NewProc("GdipSetImageAttributesColorMatrix")
	procGdipDisposeImageAttributes         = ovlGdiplus.NewProc("GdipDisposeImageAttributes")
	procGdipDrawImageRectRectI             = ovlGdiplus.NewProc("GdipDrawImageRectRectI")

	// shlwapi (IStream from memory)
	ovlShlwapi           = windows.NewLazySystemDLL("shlwapi.dll")
	procSHCreateMemStream = ovlShlwapi.NewProc("SHCreateMemStream")
)

// floatColorPreset defines a gradient color theme for the floating button.
type floatColorPreset struct {
	Top      uint32 // ARGB – gradient start (top-left)
	Bottom   uint32 // ARGB – gradient end (bottom-right)
	HoverTop uint32 // ARGB – gradient start on hover
	HoverBot uint32 // ARGB – gradient end on hover
}

// floatColorPresets maps preset names to their gradient colors.
// Each gradient runs 135° (top-left → bottom-right) matching the app's FAB.
var floatColorPresets = map[string]floatColorPreset{
	"cyan": {
		Top: 0xFF22D3EE, Bottom: 0xFF0891B2, // Cyan-400 → Cyan-600
		HoverTop: 0xFF67E8F9, HoverBot: 0xFF06B6D4, // Cyan-300 → Cyan-500
	},
	"purple": {
		Top: 0xFFC084FC, Bottom: 0xFF9333EA, // Purple-400 → Purple-600
		HoverTop: 0xFFD8B4FE, HoverBot: 0xFFA855F7, // Purple-300 → Purple-500
	},
	"rose": {
		Top: 0xFFFB7185, Bottom: 0xFFE11D48, // Rose-400 → Rose-600
		HoverTop: 0xFFFDA4AF, HoverBot: 0xFFF43F5E, // Rose-300 → Rose-500
	},
	"emerald": {
		Top: 0xFF34D399, Bottom: 0xFF059669, // Emerald-400 → Emerald-600
		HoverTop: 0xFF6EE7B7, HoverBot: 0xFF10B981, // Emerald-300 → Emerald-500
	},
	"amber": {
		Top: 0xFFFBBF24, Bottom: 0xFFD97706, // Amber-400 → Amber-600
		HoverTop: 0xFFFCD34D, HoverBot: 0xFFF59E0B, // Amber-300 → Amber-500
	},
	"slate": {
		Top: 0xFF94A3B8, Bottom: 0xFF475569, // Slate-400 → Slate-600
		HoverTop: 0xFFCBD5E1, HoverBot: 0xFF64748B, // Slate-300 → Slate-500
	},
	"blue": {
		Top: 0xFF60A5FA, Bottom: 0xFF2563EB, // Blue-400 → Blue-600
		HoverTop: 0xFF93C5FD, HoverBot: 0xFF3B82F6, // Blue-300 → Blue-500
	},
	"orange": {
		Top: 0xFFFB923C, Bottom: 0xFFEA580C, // Orange-400 → Orange-600
		HoverTop: 0xFFFDBA74, HoverBot: 0xFFF97316, // Orange-300 → Orange-500
	},
}

// getFloatPreset returns the color preset for the given name, defaulting to cyan.
func getFloatPreset(name string) floatColorPreset {
	if p, ok := floatColorPresets[name]; ok {
		return p
	}
	return floatColorPresets["cyan"]
}

// parseHexToARGB converts a "#RRGGBB" hex string to a 0xAARRGGBB uint32 (fully opaque).
func parseHexToARGB(hex string) uint32 {
	hex = strings.TrimPrefix(hex, "#")
	if len(hex) == 6 {
		r, _ := strconv.ParseUint(hex[0:2], 16, 8)
		g, _ := strconv.ParseUint(hex[2:4], 16, 8)
		b, _ := strconv.ParseUint(hex[4:6], 16, 8)
		return 0xFF000000 | (uint32(r) << 16) | (uint32(g) << 8) | uint32(b)
	}
	return 0xFF22D3EE // fallback cyan
}

// darkenColor multiplies RGB channels by factor, preserving alpha.
func darkenColor(argb uint32, factor float64) uint32 {
	a := argb & 0xFF000000
	r := uint32(float64((argb>>16)&0xFF) * factor)
	g := uint32(float64((argb>>8)&0xFF) * factor)
	b := uint32(float64(argb&0xFF) * factor)
	if r > 0xFF {
		r = 0xFF
	}
	if g > 0xFF {
		g = 0xFF
	}
	if b > 0xFF {
		b = 0xFF
	}
	return a | (r << 16) | (g << 8) | b
}

// ───────────────────── FloatingButton ─────────────────────

var globalFloating *FloatingButton

// toolInfoW is the Win32 TOOLINFOW struct for tooltip management.
type toolInfoW struct {
	CbSize   uint32
	UFlags   uint32
	Hwnd     uintptr
	UID      uintptr
	Rect     rectT
	HInst    uintptr
	LpszText *uint16
	LParam   uintptr
	LpReserved uintptr
}

// FloatingButton is a small always-on-top circle that starts recording on click.
type FloatingButton struct {
	hwnd       uintptr
	dibDC      uintptr
	dibBmp     uintptr
	tooltipHwnd uintptr
	ready      chan error
	done       chan struct{}
	cfg        *Config

	onStartRecording func()
	onOpenWindow     func(string)
	onQuit           func()
	onSmartToggled   func(bool)
	onHide           func()           // called when user hides via context menu
	onToggle         func()           // start/stop recording toggle
	onConfigChanged  func()           // called after any config change from context menu

	// Menu state providers (called at menu-open time)
	getState      func() AppState
	getHotkeyStr  func() string
	getLatestText func() string

	opacity    byte
	dragStartX int32 // window X at start of potential drag
	dragStartY int32 // window Y at start of potential drag
	size       int   // current diameter in pixels (cached from config)
	content    string // icon content type (cached from config)
	customImage     uintptr // cached GDI+ image for custom icon
	customImagePath string  // path of the cached image
	appLogoLight    uintptr // cached GDI+ image for app logo (light bg variant)
	appLogoDark     uintptr // cached GDI+ image for app logo (dark bg variant)

	// Double-click detection: defers single-click to distinguish from double-click
	dblClickPending bool

	// Recording countdown: tracks when recording started for progress arc
	recordingStart time.Time

	// Position save debouncing
	lastMoveSave time.Time

	// Auto-hide: tracks when mouse was last near the button
	lastActivityTime time.Time
	autoHidden       bool

	mu sync.Mutex
}

var floatingWndProcCB = syscall.NewCallback(floatingWndProc)

// dpiScale returns the DPI scale factor for the floating button's monitor.
// Returns 1.0 at 96 DPI (100%), 1.5 at 144 DPI (150%), 2.0 at 192 DPI (200%).
func (fb *FloatingButton) dpiScale() float64 {
	if fb.hwnd == 0 {
		return 1.0
	}
	dpi, _, _ := procGetDpiForWindow.Call(fb.hwnd)
	if dpi == 0 {
		return 1.0
	}
	return float64(dpi) / 96.0
}

// getSize returns the cached button diameter (thread-safe), scaled for DPI.
func (fb *FloatingButton) getSize() int {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	s := fb.size
	if s <= 0 {
		s = _FLOAT_SIZE
	}
	return int(float64(s) * fb.dpiScale())
}

// idleOpacity returns the configured idle opacity as a byte (0–255).
func (fb *FloatingButton) idleOpacity() byte {
	pct := fb.cfg.GetFloatingButtonOpacity() // 30–100
	return byte(pct * 255 / 100)
}

func floatingWndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	fb := globalFloating
	if fb == nil {
		ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		return ret
	}

	switch uint32(msg) {
	case _WM_PAINT:
		var ps paintStructT
		procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		return 0

	case _WM_ERASEBKGND:
		return 1

	case _WM_NCHITTEST:
		if fb.cfg.GetFloatingButtonLocked() {
			return 1 // HTCLIENT — prevents drag, allows click
		}
		return _HTCAPTION

	case _WM_NCLBUTTONDOWN:
		// Record window position before the system's modal move loop starts
		var rc rectT
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		func() {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.dragStartX = rc.Left
			fb.dragStartY = rc.Top
		}()
		// DefWindowProc enters a modal move loop and blocks until the
		// mouse button is released. After it returns we check whether
		// the window actually moved — if not, treat it as a click.
		ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		var rc2 rectT
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc2)))
		wasDrag := func() bool {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			return rc2.Left != fb.dragStartX || rc2.Top != fb.dragStartY
		}()
		if !wasDrag {
			// Defer click action to allow double-click detection
			func() {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				fb.dblClickPending = true
			}()
			dblClickMs, _, _ := procGetDoubleClickTime.Call()
			if dblClickMs == 0 {
				dblClickMs = 250
			}
			procSetTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID, dblClickMs, 0)
		}
		return ret

	case _WM_NCLBUTTONUP:
		// May still arrive after the modal loop — handle for completeness.
		// The primary click detection is in NCLBUTTONDOWN above.
		return 0

	case _WM_NCLBUTTONDBLCLK:
		// Cancel the pending single-click timer and open main window
		procKillTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID)
		cb := func() func(string) {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.dblClickPending = false
			return fb.onOpenWindow
		}()
		if cb != nil {
			go cb("")
		}
		return 0

	case 0x0201: // WM_LBUTTONDOWN — when position is locked, NCHITTEST returns HTCLIENT
		// Defer click to allow double-click detection
		func() {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.dblClickPending = true
		}()
		dblClickMs, _, _ := procGetDoubleClickTime.Call()
		if dblClickMs == 0 {
			dblClickMs = 250
		}
		procSetTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID, dblClickMs, 0)
		return 0

	case _WM_LBUTTONDBLCLK:
		// Cancel pending single-click and open main window (locked mode)
		procKillTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID)
		cb := func() func(string) {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.dblClickPending = false
			return fb.onOpenWindow
		}()
		if cb != nil {
			go cb("")
		}
		return 0

	case _WM_NCRBUTTONUP:
		fb.showContextMenu(hwnd)
		return 0

	case 0x0205: // WM_RBUTTONUP — context menu when position is locked
		fb.showContextMenu(hwnd)
		return 0

	case _WM_MOVE:
		fb.onWindowMoved()
		return 0

	case _WM_NCMOUSEMOVE:
		fb.touchActivity()
		r, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		return r

	case _WM_COMMAND:
		switch int(wParam & 0xFFFF) {
		case _FLOAT_MENU_SMART_MODE:
			go func() {
				fb.cfg.mu.Lock()
				fb.cfg.SmartMode = !fb.cfg.SmartMode
				newState := fb.cfg.SmartMode
				fb.cfg.mu.Unlock()
				fb.cfg.Save()
				logInfo("Floating menu toggled Smart Mode: %v", newState)
				cb := func() func(bool) {
					fb.mu.Lock()
					defer fb.mu.Unlock()
					return fb.onSmartToggled
				}()
				if cb != nil {
					cb(newState)
				}
			}()
		case _FLOAT_MENU_DASHBOARD:
			cb := func() func(string) {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.onOpenWindow
			}()
			if cb != nil {
				go cb("history")
			}
		case _FLOAT_MENU_SETTINGS:
			cb := func() func(string) {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.onOpenWindow
			}()
			if cb != nil {
				go cb("settings")
			}
		case _FLOAT_MENU_HIDE:
			procPostMessageW.Call(hwnd, _WM_FLOAT_HIDE, 0, 0)
			go func() {
				fb.cfg.mu.Lock()
				fb.cfg.FloatingButtonEnabled = false
				fb.cfg.mu.Unlock()
				fb.cfg.Save()
				cb := func() func() {
					fb.mu.Lock()
					defer fb.mu.Unlock()
					return fb.onHide
				}()
				if cb != nil {
					cb()
				}
			}()
		case _FLOAT_MENU_QUIT:
			cb := func() func() {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.onQuit
			}()
			if cb != nil {
				go cb()
			}
		case _FLOAT_MENU_RECORD:
			cb := func() func() {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.onToggle
			}()
			if cb != nil {
				go cb()
			}
		case _FLOAT_MENU_PREVIEW:
			// Copy latest transcription to clipboard
			cb := func() func() string {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.getLatestText
			}()
			if cb != nil {
				go func() {
					if text := cb(); text != "" {
						if err := writeClipboard(text); err != nil {
							logWarn("Menu preview copy failed: %v", err)
						} else {
							logInfo("Copied last transcription from menu (%d chars)", len(text))
						}
					}
				}()
			}
		case _FLOAT_MENU_LOCK:
			go func() {
				fb.cfg.mu.Lock()
				fb.cfg.FloatingButtonLocked = !fb.cfg.FloatingButtonLocked
				locked := fb.cfg.FloatingButtonLocked
				fb.cfg.mu.Unlock()
				fb.cfg.Save()
				logInfo("Floating button position lock: %v", locked)
				cb := func() func() {
					fb.mu.Lock()
					defer fb.mu.Unlock()
					return fb.onConfigChanged
				}()
				if cb != nil {
					cb()
				}
			}()
		case _FLOAT_MENU_AUTO_PASTE:
			go func() {
				fb.cfg.mu.Lock()
				fb.cfg.AutoPaste = !fb.cfg.AutoPaste
				newState := fb.cfg.AutoPaste
				fb.cfg.mu.Unlock()
				fb.cfg.Save()
				logInfo("Floating menu toggled Auto-Paste: %v", newState)
				cb := func() func() {
					fb.mu.Lock()
					defer fb.mu.Unlock()
					return fb.onConfigChanged
				}()
				if cb != nil {
					cb()
				}
			}()
		}
		return 0

	case _WM_FLOAT_SHOW:
		// Restore position from config, snap to edges, show
		fb.restorePosition()
		procShowWindow.Call(hwnd, uintptr(_SW_SHOWNA))
		// Re-assert topmost
		const _SWP_NOSIZE = 0x0001
		const _SWP_NOMOVE = 0x0002
		const _SWP_NOACTIVATE = 0x0010
		const _SWP_SHOWWINDOW = 0x0040
		const _HWND_TOPMOST = ^uintptr(0)
		procSetWindowPos.Call(hwnd, _HWND_TOPMOST, 0, 0, 0, 0,
			_SWP_NOMOVE|_SWP_NOSIZE|_SWP_NOACTIVATE|_SWP_SHOWWINDOW)
		// Start periodic topmost re-assertion timer
		procSetTimer.Call(hwnd, _FLOAT_TIMER_ID, _FLOAT_TIMER_MS, 0)
		// Start animation timer for gradient rotation and state icons
		procSetTimer.Call(hwnd, _FLOAT_ANIM_TIMER_ID, _FLOAT_ANIM_TIMER_MS, 0)
		// Start idle timer for auto-hide if configured
		if fb.cfg.GetFloatingButtonAutoHide() != "never" {
			procSetTimer.Call(hwnd, _FLOAT_IDLE_ANIM_TIMER_ID, _FLOAT_IDLE_ANIM_TIMER_MS, 0)
		}
		fb.render()
		return 0

	case _WM_FLOAT_HIDE:
		procKillTimer.Call(hwnd, _FLOAT_TIMER_ID)
		procKillTimer.Call(hwnd, _FLOAT_ANIM_TIMER_ID)
		procKillTimer.Call(hwnd, _FLOAT_IDLE_ANIM_TIMER_ID)
		procShowWindow.Call(hwnd, uintptr(_SW_HIDE))
		func() {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.opacity = fb.idleOpacity()
		}()
		return 0

	case _WM_FLOAT_RERENDER:
		fb.render()
		return 0

	case _WM_FLOAT_RESIZE:
		fb.handleResize()
		return 0

	case _WM_FLOAT_OPACITY:
		func() {
			fb.mu.Lock()
			defer fb.mu.Unlock()
			fb.opacity = fb.idleOpacity()
		}()
		fb.render()
		return 0

	case _WM_TIMER:
		timerID := wParam
		if timerID == _FLOAT_DBLCLK_TIMER_ID {
			// Double-click timer expired — treat as single click (record toggle)
			procKillTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID)
			pending, cb := func() (bool, func()) {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				p := fb.dblClickPending
				fb.dblClickPending = false
				return p, fb.onStartRecording
			}()
			if pending && cb != nil {
				// Play configured button click sound
				go fb.playButtonSound()
				procPostMessageW.Call(hwnd, _WM_FLOAT_HIDE, 0, 0)
				go cb()
			}
			return 0
		}
		if timerID == _FLOAT_ANIM_TIMER_ID {
			fb.render()
			return 0
		}
		if timerID == _FLOAT_IDLE_ANIM_TIMER_ID {
			fb.checkAutoHide()
			fb.render()
			return 0
		}
		// Periodic topmost re-assertion to prevent z-order loss
		const _HWND_TOPMOST3 = ^uintptr(0)
		const _SWP_NOMOVE3 = 0x0002
		const _SWP_NOSIZE3 = 0x0001
		const _SWP_NOACTIVATE3 = 0x0010
		procSetWindowPos.Call(hwnd, _HWND_TOPMOST3, 0, 0, 0, 0,
			_SWP_NOMOVE3|_SWP_NOSIZE3|_SWP_NOACTIVATE3)
		return 0

	case _WM_DPICHANGED:
		fb.handleResize()
		return 0

	case _WM_DESTROY:
		procKillTimer.Call(hwnd, _FLOAT_TIMER_ID)
		procKillTimer.Call(hwnd, _FLOAT_DBLCLK_TIMER_ID)
		procKillTimer.Call(hwnd, _FLOAT_ANIM_TIMER_ID)
		procKillTimer.Call(hwnd, _FLOAT_IDLE_ANIM_TIMER_ID)
		if fb.tooltipHwnd != 0 {
			procDestroyWindow.Call(fb.tooltipHwnd)
		}
		if fb.dibDC != 0 {
			procDeleteDC.Call(fb.dibDC)
		}
		if fb.dibBmp != 0 {
			procDeleteObject.Call(fb.dibBmp)
		}
		fb.mu.Lock()
		if fb.customImage != 0 {
			procGdipDisposeImage.Call(fb.customImage)
			fb.customImage = 0
		}
		fb.mu.Unlock()
		procPostQuitMessage.Call(0)
		return 0
	}

	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret
}

// ───────────────────── Public API ─────────────────────

// NewFloatingButton creates the floating record button on a dedicated OS thread.
func NewFloatingButton(c *Config) (*FloatingButton, error) {
	fb := &FloatingButton{
		ready:            make(chan error, 1),
		done:             make(chan struct{}),
		cfg:              c,
		opacity:          byte(c.GetFloatingButtonOpacity() * 255 / 100),
		size:             c.GetFloatingButtonSize(),
		content:          c.GetFloatingButtonContent(),
		lastActivityTime: time.Now(),
	}
	globalFloating = fb

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		if err := fb.initWindow(); err != nil {
			fb.ready <- err
			return
		}
		fb.loadAppLogos()
		fb.ready <- nil

		var msg msgT
		for {
			ret, _, _ := procGetMessageW.Call(
				uintptr(unsafe.Pointer(&msg)), 0, 0, 0,
			)
			if ret == 0 || ret == ^uintptr(0) {
				break
			}
			procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
		}
		close(fb.done)
	}()

	if err := <-fb.ready; err != nil {
		return nil, err
	}
	return fb, nil
}

// SetCallbacks sets the floating button callbacks (thread-safe).
func (fb *FloatingButton) SetCallbacks(onStart func(), onOpenWindow func(string), onQuit func(), onSmartToggled func(bool), onHide func(), onConfigChanged func()) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	fb.onStartRecording = onStart
	fb.onOpenWindow = onOpenWindow
	fb.onQuit = onQuit
	fb.onSmartToggled = onSmartToggled
	fb.onHide = onHide
	fb.onConfigChanged = onConfigChanged
}

// SetMenuCallbacks sets the state-provider callbacks for the context menu.
func (fb *FloatingButton) SetMenuCallbacks(onToggle func(), getState func() AppState, getHotkeyStr func() string, getLatestText func() string) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	fb.onToggle = onToggle
	fb.getState = getState
	fb.getHotkeyStr = getHotkeyStr
	fb.getLatestText = getLatestText
}

// Show displays the floating button.
func (fb *FloatingButton) Show() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_SHOW, 0, 0)
	}
}

// Hide hides the floating button.
func (fb *FloatingButton) Hide() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_HIDE, 0, 0)
	}
}

// Close destroys the floating button window and waits for cleanup.
func (fb *FloatingButton) Close() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, uintptr(_WM_CLOSE), 0, 0)
		<-fb.done
	}
}

// UpdateColor triggers a re-render to pick up the current config color.
func (fb *FloatingButton) UpdateColor() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_RERENDER, 0, 0)
	}
}

// UpdateContent updates the cached icon content and triggers a re-render.
func (fb *FloatingButton) UpdateContent() {
	newContent := fb.cfg.GetFloatingButtonContent()
	newImagePath := fb.cfg.GetFloatingButtonCustomImage()
	fb.mu.Lock()
	fb.content = newContent
	// Reload custom image if path changed
	if newContent == "custom" && newImagePath != fb.customImagePath {
		if fb.customImage != 0 {
			procGdipDisposeImage.Call(fb.customImage)
			fb.customImage = 0
		}
		fb.customImagePath = newImagePath
		fb.loadCustomImageLocked()
	}
	fb.mu.Unlock()
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_RERENDER, 0, 0)
	}
}

// playButtonSound is a no-op; button click sounds have been removed.
func (fb *FloatingButton) playButtonSound() {}

// touchActivity resets the auto-hide inactivity timer and restores
// the button to full opacity if it was auto-hidden.
func (fb *FloatingButton) touchActivity() {
	fb.mu.Lock()
	fb.lastActivityTime = time.Now()
	wasHidden := fb.autoHidden
	fb.autoHidden = false
	fb.mu.Unlock()
	if wasHidden {
		fb.render()
	}
}

// checkAutoHide fades the button when the auto-hide timeout expires.
func (fb *FloatingButton) checkAutoHide() {
	mode := fb.cfg.GetFloatingButtonAutoHide()
	if mode != "timeout" {
		return
	}
	timeout := fb.cfg.GetFloatingButtonAutoHideTimeout()
	if timeout <= 0 {
		return
	}
	fb.mu.Lock()
	if fb.autoHidden {
		fb.mu.Unlock()
		return
	}
	if fb.lastActivityTime.IsZero() || time.Since(fb.lastActivityTime) < time.Duration(timeout)*time.Second {
		fb.mu.Unlock()
		return
	}
	fb.autoHidden = true
	fb.mu.Unlock()
	fb.render()
}

// UpdateOpacity applies the current config opacity immediately.
func (fb *FloatingButton) UpdateOpacity() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_OPACITY, 0, 0)
	}
}

// UpdateSize resizes the floating button to match the current config size.
// Must be called from any thread — the actual resize happens on the window thread.
func (fb *FloatingButton) UpdateSize() {
	if fb.hwnd == 0 {
		return
	}
	newSize := fb.cfg.GetFloatingButtonSize()
	changed := func() bool {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		c := fb.size != newSize
		fb.size = newSize
		return c
	}()
	if changed {
		// Post a custom message to rebuild DIB and resize on the window thread
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_RESIZE, 0, 0)
	}
}

// handleResize recreates the DIB and resizes the window to match the current size.
// Must run on the window thread (called from wndProc).
func (fb *FloatingButton) handleResize() {
	sz := fb.getSize()

	// Destroy old DIB
	if fb.dibDC != 0 {
		procDeleteDC.Call(fb.dibDC)
		fb.dibDC = 0
	}
	if fb.dibBmp != 0 {
		procDeleteObject.Call(fb.dibBmp)
		fb.dibBmp = 0
	}

	// Create new DIB at current size
	fb.createDIB()

	// Resize window in-place
	var r rectT
	procGetWindowRect.Call(fb.hwnd, uintptr(unsafe.Pointer(&r)))
	x, y := int(r.Left), int(r.Top)
	x, y = fb.clampToMonitor(x, y)
	procMoveWindow.Call(fb.hwnd, uintptr(x), uintptr(y), uintptr(sz), uintptr(sz), 1)

	fb.render()
}

// ───────────────────── Window Init ─────────────────────

func (fb *FloatingButton) initWindow() error {
	hInst, _, _ := procGetModuleHandleW.Call(0)
	className, _ := windows.UTF16PtrFromString("WhispasteFloating")

	var wc wndClassExW
	wc.CbSize = uint32(unsafe.Sizeof(wc))
	wc.Style = _CS_HREDRAW | _CS_VREDRAW | _CS_DBLCLKS
	wc.LpfnWndProc = floatingWndProcCB
	wc.HInstance = hInst
	// Hand cursor for the button
	handCursor, _, _ := procLoadCursorW.Call(0, 32649) // IDC_HAND
	wc.HCursor = handCursor
	wc.LpszClassName = className

	atom, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
	if atom == 0 {
		return fmt.Errorf("RegisterClassExW failed for floating button")
	}

	// Default position: bottom-right of primary screen
	screenW, _, _ := procGetSystemMetrics.Call(_SM_CXSCREEN)
	screenH, _, _ := procGetSystemMetrics.Call(_SM_CYSCREEN)
	sz := fb.getSize()
	x := int(screenW) - sz - 40
	y := int(screenH) - sz - 120

	// Restore saved position if available
	savedX, savedY := fb.cfg.GetFloatingButtonPos()
	if savedX > 0 || savedY > 0 {
		x, y = savedX, savedY
	}

	exStyle := uintptr(_WS_EX_TOPMOST | _WS_EX_LAYERED | _WS_EX_TOOLWINDOW | _WS_EX_NOACTIVATE)
	hwnd, _, _ := procCreateWindowExW.Call(
		exStyle,
		uintptr(unsafe.Pointer(className)),
		0,
		uintptr(_WS_POPUP),
		uintptr(x), uintptr(y), uintptr(sz), uintptr(sz),
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowExW failed for floating button")
	}
	fb.hwnd = hwnd

	// Create tooltip control
	fb.createTooltip(hInst)

	// Create DIB section for per-pixel alpha rendering
	fb.createDIB()
	fb.render()

	return nil
}

// ───────────────────── DIB + Rendering ─────────────────────

// buildShapePath creates a GDI+ path for the configured shape (rounded/squircle).
// Returns 0 for "circle" (caller should use ellipse calls instead).
// Caller MUST call procGdipDeletePath when done with a non-zero result.
func (fb *FloatingButton) buildShapePath(x, y, w, h int) uintptr {
	shape := fb.cfg.GetFloatingButtonShape()
	switch shape {
	case "rounded":
		return fb.buildRoundedPath(x, y, w, h, float32(w)/4.0)
	case "squircle":
		return fb.buildRoundedPath(x, y, w, h, float32(w)/3.0)
	case "hexagon":
		return fb.buildHexPath(x, y, w, h)
	case "diamond":
		return fb.buildDiamondPath(x, y, w, h)
	default:
		return 0
	}
}

// buildRoundedPath creates a rounded rectangle path with the given corner radius.
func (fb *FloatingButton) buildRoundedPath(x, y, w, h int, r float32) uintptr {
	var path uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
	if path == 0 {
		return 0
	}
	procGdipAddPathArc.Call(path, f32(float32(x)), f32(float32(y)), f32(r*2), f32(r*2), f32(180), f32(90))
	procGdipAddPathArc.Call(path, f32(float32(x+w)-r*2), f32(float32(y)), f32(r*2), f32(r*2), f32(270), f32(90))
	procGdipAddPathArc.Call(path, f32(float32(x+w)-r*2), f32(float32(y+h)-r*2), f32(r*2), f32(r*2), f32(0), f32(90))
	procGdipAddPathArc.Call(path, f32(float32(x)), f32(float32(y+h)-r*2), f32(r*2), f32(r*2), f32(90), f32(90))
	procGdipClosePathFigure.Call(path)
	return path
}

// buildHexPath creates a flat-top hexagonal path.
func (fb *FloatingButton) buildHexPath(x, y, w, h int) uintptr {
	var path uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
	if path == 0 {
		return 0
	}
	cx, cy := float32(x)+float32(w)/2, float32(y)+float32(h)/2
	r := float32(w) / 2
	for i := 0; i < 6; i++ {
		angle := float64(-30+60*i) * math.Pi / 180
		px := cx + r*float32(math.Cos(angle))
		py := cy + r*float32(math.Sin(angle))
		if i > 0 {
			prevAngle := float64(-30+60*(i-1)) * math.Pi / 180
			prevX := cx + r*float32(math.Cos(prevAngle))
			prevY := cy + r*float32(math.Sin(prevAngle))
			procGdipAddPathLine.Call(path, uintptr(int32(prevX)), uintptr(int32(prevY)), uintptr(int32(px)), uintptr(int32(py)))
		}
	}
	procGdipClosePathFigure.Call(path)
	return path
}

// buildDiamondPath creates a diamond (rotated square) path.
func (fb *FloatingButton) buildDiamondPath(x, y, w, h int) uintptr {
	var path uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
	if path == 0 {
		return 0
	}
	cx, cy := float32(x)+float32(w)/2, float32(y)+float32(h)/2
	rx, ry := float32(w)/2, float32(h)/2
	procGdipAddPathLine.Call(path, uintptr(int32(cx)), uintptr(int32(cy-ry)), uintptr(int32(cx+rx)), uintptr(int32(cy)))
	procGdipAddPathLine.Call(path, uintptr(int32(cx+rx)), uintptr(int32(cy)), uintptr(int32(cx)), uintptr(int32(cy+ry)))
	procGdipAddPathLine.Call(path, uintptr(int32(cx)), uintptr(int32(cy+ry)), uintptr(int32(cx-rx)), uintptr(int32(cy)))
	procGdipClosePathFigure.Call(path)
	return path
}

// fillShape fills the configured shape (circle, rounded, squircle) with the given brush.
func (fb *FloatingButton) fillShape(g, brush uintptr, x, y, w, h int) {
	path := fb.buildShapePath(x, y, w, h)
	if path == 0 {
		procGdipFillEllipseI.Call(g, brush, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
		return
	}
	defer procGdipDeletePath.Call(path)
	procGdipFillPath.Call(g, brush, path)
}

// setShapeClip sets a GDI+ clipping region to the button shape so all
// subsequent drawing is confined to the shape bounds (no gradient bleed).
func (fb *FloatingButton) setShapeClip(g uintptr, x, y, w, h int) {
	path := fb.buildShapePath(x, y, w, h)
	if path == 0 {
		// Circle: clip to ellipse via a temporary path
		var epath uintptr
		procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&epath)))
		if epath == 0 {
			return
		}
		procGdipAddPathEllipseI.Call(epath, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
		procGdipSetClipPath.Call(g, epath, 0) // CombineModeReplace
		procGdipDeletePath.Call(epath)
		return
	}
	procGdipSetClipPath.Call(g, path, 0) // CombineModeReplace
	procGdipDeletePath.Call(path)
}

// drawShapeOutline strokes the configured shape with the given pen.
func (fb *FloatingButton) drawShapeOutline(g, pen uintptr, x, y, w, h int) {
	path := fb.buildShapePath(x, y, w, h)
	if path == 0 {
		procGdipDrawEllipseI.Call(g, pen, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
		return
	}
	defer procGdipDeletePath.Call(path)
	procGdipDrawPath.Call(g, pen, path)
}

// drawShapeProgress draws a progress stroke along the button shape outline.
// For circles, it uses GdipDrawArc. For other shapes, it traces the flattened outline.
func (fb *FloatingButton) drawShapeProgress(g, pen uintptr, x, y, w, h int, progress float32) {
	shape := fb.cfg.GetFloatingButtonShape()
	if shape == "" || shape == "circle" {
		sweepAngle := progress * 360.0
		procGdipDrawArc.Call(g, pen,
			f32(float32(x)), f32(float32(y)), f32(float32(w)), f32(float32(h)),
			f32(-90), f32(sweepAngle))
		return
	}

	path := fb.buildShapePath(x, y, w, h)
	if path == 0 {
		sweepAngle := progress * 360.0
		procGdipDrawArc.Call(g, pen,
			f32(float32(x)), f32(float32(y)), f32(float32(w)), f32(float32(h)),
			f32(-90), f32(sweepAngle))
		return
	}
	defer procGdipDeletePath.Call(path)

	// Flatten curves to line segments
	procGdipFlattenPath.Call(path, 0, f32(1.0))

	var count int32
	procGdipGetPointCount.Call(path, uintptr(unsafe.Pointer(&count)))
	if count < 2 {
		return
	}

	type pointF struct{ X, Y float32 }
	points := make([]pointF, count)
	procGdipGetPathPoints.Call(path, uintptr(unsafe.Pointer(&points[0])), uintptr(count))

	// Compute total closed-path length
	n := int(count)
	totalLen := float32(0)
	for i := 1; i <= n; i++ {
		prev := points[i-1]
		curr := points[i%n]
		dx := curr.X - prev.X
		dy := curr.Y - prev.Y
		totalLen += float32(math.Sqrt(float64(dx*dx + dy*dy)))
	}

	// Find the topmost point as the starting vertex (closest to -90°, matching GdipDrawArc)
	startIdx := 0
	minY := points[0].Y
	for i := 1; i < n; i++ {
		if points[i].Y < minY || (points[i].Y == minY && math.Abs(float64(points[i].X-float32(x+w/2))) < math.Abs(float64(points[startIdx].X-float32(x+w/2)))) {
			minY = points[i].Y
			startIdx = i
		}
	}

	// Draw segments starting from the top vertex up to progress fraction
	targetLen := progress * totalLen
	drawn := float32(0)
	for step := 0; step < n; step++ {
		i := (startIdx + step) % n
		j := (startIdx + step + 1) % n
		prev := points[i]
		curr := points[j]
		dx := curr.X - prev.X
		dy := curr.Y - prev.Y
		segLen := float32(math.Sqrt(float64(dx*dx + dy*dy)))

		if drawn+segLen <= targetLen {
			procGdipDrawLine.Call(g, pen,
				f32(prev.X), f32(prev.Y), f32(curr.X), f32(curr.Y))
			drawn += segLen
		} else {
			remain := targetLen - drawn
			frac := remain / segLen
			endX := prev.X + dx*frac
			endY := prev.Y + dy*frac
			procGdipDrawLine.Call(g, pen,
				f32(prev.X), f32(prev.Y), f32(endX), f32(endY))
			break
		}
	}
}

func (fb *FloatingButton) createDIB() {
	sz := int32(fb.getSize())
	var bmi bitmapInfoHeader
	bmi.BiSize = uint32(unsafe.Sizeof(bmi))
	bmi.BiWidth = sz
	bmi.BiHeight = -sz // top-down
	bmi.BiPlanes = 1
	bmi.BiBitCount = 32

	screenDC, _, _ := procGetDC.Call(0)
	var bits uintptr
	fb.dibBmp, _, _ = procCreateDIBSection.Call(
		screenDC,
		uintptr(unsafe.Pointer(&bmi)),
		0, // DIB_RGB_COLORS
		uintptr(unsafe.Pointer(&bits)),
		0, 0,
	)
	procReleaseDC.Call(0, screenDC)

	fb.dibDC, _, _ = procCreateCompatibleDC.Call(0)
	procSelectObject.Call(fb.dibDC, fb.dibBmp)
}

func (fb *FloatingButton) render() {
	if fb.dibDC == 0 {
		return
	}
	sz := fb.getSize()

	var g uintptr
	procGdipCreateFromHDC.Call(fb.dibDC, uintptr(unsafe.Pointer(&g)))
	if g == 0 {
		return
	}
	defer procGdipDeleteGraphics.Call(g)

	procGdipSetSmoothingMode.Call(g, _SmoothingModeAntiAlias)
	procGdipSetTextRenderingHint.Call(g, _TextRenderingHintAntiAliasGridFit)

	// Clear to transparent
	procGdipGraphicsClear.Call(g, 0x00000000)

	// Clip all drawing to the button shape so gradients don't bleed at corners
	fb.setShapeClip(g, 0, 0, sz, sz)

	alpha := func() byte {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		return fb.opacity
	}()

	preset := getFloatPreset(fb.cfg.GetFloatingButtonColor())
	if fb.cfg.GetFloatingButtonColor() == "custom" {
		base := parseHexToARGB(fb.cfg.GetFloatingButtonCustomColor())
		darker := darkenColor(base, 0.7)
		lighter := darkenColor(base, 1.15) // slightly brighter for hover
		preset = floatColorPreset{Top: base, Bottom: darker, HoverTop: lighter, HoverBot: base}
	}

	// State-based glow color for the outer ring
	var glowColor uint32
	appState := StateIdle
	if fn := func() func() AppState {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		return fb.getState
	}(); fn != nil {
		appState = fn()
	}
	switch appState {
	case StateRecording, StatePaused:
		glowColor = (uint32(100) << 24) | 0xFF3333
	case StateTranscribing, StateProcessing:
		glowColor = 0x60FFAB00 // amber
	default:
		// Default: subtle accent glow
		glowColor = (uint32(40) << 24) | (preset.Top & 0x00FFFFFF)
	}
	var glowBrush uintptr
	procGdipCreateSolidFill.Call(uintptr(glowColor), uintptr(unsafe.Pointer(&glowBrush)))
	if glowBrush != 0 {
		fb.fillShape(g, glowBrush, 0, 0, sz, sz)
		procGdipDeleteBrush.Call(glowBrush)
	}

	// Shadow (offset 2px down-right, drawn within glow area)
	// Design alpha: 48/255 ≈ 19%
	shadowColor := uint32(48) << 24
	var shadowBrush uintptr
	procGdipCreateSolidFill.Call(uintptr(shadowColor), uintptr(unsafe.Pointer(&shadowBrush)))
	if shadowBrush != 0 {
		fb.fillShape(g, shadowBrush, 4, 4, sz-4, sz-4)
		procGdipDeleteBrush.Call(shadowBrush)
	}

	// Main shape with animated gradient (slow rotating color shift)
	topClr, botClr := preset.Top, preset.Bottom

	// Static diagonal gradient — extend to sqrt(2) × halfSz to cover all corners
	angle := float32(135.0)
	cxf, cyf := float32(sz)/2.0, float32(sz)/2.0
	rad := float64(angle) * math.Pi / 180.0
	gdx, gdy := float32(math.Cos(rad)), float32(math.Sin(rad))
	halfDiag := float32(sz) / 2.0 * float32(math.Sqrt2)
	pt1 := [2]float32{cxf - gdx*halfDiag, cyf - gdy*halfDiag}
	pt2 := [2]float32{cxf + gdx*halfDiag, cyf + gdy*halfDiag}

	var gradBrush uintptr
	procGdipCreateLineBrush.Call(
		uintptr(unsafe.Pointer(&pt1)),
		uintptr(unsafe.Pointer(&pt2)),
		uintptr(topClr),
		uintptr(botClr),
		0, // WrapModeTile
		uintptr(unsafe.Pointer(&gradBrush)),
	)
	if gradBrush != 0 {
		fb.fillShape(g, gradBrush, 2, 2, sz-4, sz-4)
		procGdipDeleteBrush.Call(gradBrush)
	}

	// Optional accent border ring
	if fb.cfg.GetFloatingButtonBorder() {
		borderColor := (uint32(200) << 24) | 0x00FFFFFF // white ring, design alpha 200/255
		var borderPen uintptr
		procGdipCreatePen1.Call(uintptr(borderColor), f32(2.0), 2, uintptr(unsafe.Pointer(&borderPen)))
		if borderPen != 0 {
			fb.drawShapeOutline(g, borderPen, 3, 3, sz-6, sz-6)
			procGdipDeletePen.Call(borderPen)
		}
	}

	// Recording countdown arc — shows progress toward max recording duration
	if appState == StateRecording || appState == StatePaused {
		maxDur := fb.cfg.GetMaxRecordSec()
		if maxDur > 0 {
			recStart := func() time.Time {
				fb.mu.Lock()
				defer fb.mu.Unlock()
				return fb.recordingStart
			}()
			if !recStart.IsZero() {
				elapsed := time.Since(recStart).Seconds()
				progress := float32(elapsed) / float32(maxDur)
				if progress > 1 {
					progress = 1
				}
				var arcPen uintptr
				procGdipCreatePen1.Call(uintptr(_FLOAT_ARC_COLOR), f32(2.5), 2, uintptr(unsafe.Pointer(&arcPen)))
				if arcPen != 0 {
					inset := 2
					arcSize := sz - 2*inset
					fb.drawShapeProgress(g, arcPen, inset, inset, arcSize, arcSize, progress)
					procGdipDeletePen.Call(arcPen)
				}
			}
		}
	}

	// Draw the configured icon — button is hidden during recording/transcribing/processing
	fb.drawButtonIcon(g, 255)

	// Auto-hide: reduce alpha to near-invisible when idle too long
	isHidden := func() bool {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		return fb.autoHidden
	}()
	if isHidden {
		alpha = 15 // ~6% — barely visible, still hoverable
	}

	// UpdateLayeredWindow — SourceConstantAlpha controls the user's opacity setting.
	// Per-pixel alpha (AC_SRC_ALPHA) handles the circle shape / glow / shadow design.
	// Both combine: effective alpha = pixel_alpha × SourceConstantAlpha / 255.
	blend := blendFunction{
		BlendOp:             0,     // AC_SRC_OVER
		SourceConstantAlpha: alpha, // user's configured opacity (0–255)
		AlphaFormat:         1,     // AC_SRC_ALPHA
	}
	ptSrc := pointT{0, 0}
	ulsz := sizeT{int32(sz), int32(sz)}

	procUpdateLayeredWindow.Call(
		fb.hwnd,
		0,
		0, // keep position
		uintptr(unsafe.Pointer(&ulsz)),
		fb.dibDC,
		uintptr(unsafe.Pointer(&ptSrc)),
		0,
		uintptr(unsafe.Pointer(&blend)),
		2, // ULW_ALPHA
	)

	// Update tooltip to reflect current state
	fb.updateTooltip()
}

// drawButtonIcon dispatches to the correct icon drawing function based on config.
func (fb *FloatingButton) drawButtonIcon(g uintptr, alpha uint32) {
	content := func() string {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		return fb.content
	}()
	switch content {
	case "applogo":
		fb.drawAppLogoIcon(g, alpha)
	case "waveform":
		fb.drawWaveformIcon(g, alpha)
	case "custom":
		fb.drawCustomImageIcon(g, alpha)
	default:
		fb.drawMicIcon(g, alpha)
	}
}

func (fb *FloatingButton) drawMicIcon(g uintptr, alpha uint32) {
	// Draw Lucide microphone SVG paths using GDI+ to match the app's FAB icon.
	// Paths are designed for 56px (offset 16, 24px icon). Scale for other sizes.
	sz := fb.getSize()
	scale := float32(sz) / 56.0

	// Apply world transform to scale all coordinates uniformly
	procGdipScaleWorldTransform.Call(g, f32(scale), f32(scale), 0) // MatrixOrderPrepend
	defer procGdipResetWorldTransform.Call(g)

	penColor := (alpha << 24) | (_FLOAT_CLR_ICON & 0x00FFFFFF)
	var pen uintptr
	procGdipCreatePen1.Call(uintptr(penColor), f32(2.0), 2, uintptr(unsafe.Pointer(&pen)))
	if pen == 0 {
		return
	}
	defer procGdipDeletePen.Call(pen)
	procGdipSetPenLineCap197819.Call(pen, 2, 2, 0) // LineCapRound
	procGdipSetPenLineJoin.Call(pen, 2)            // LineJoinRound

	const o = 16 // offset to center 24px icon in 56px button

	// ── Mic body capsule ──
	// Top semicircle + right side + bottom semicircle + close (left side)
	var capsule uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&capsule)))
	if capsule == 0 {
		return
	}
	defer procGdipDeletePath.Call(capsule)
	procGdipAddPathArc.Call(capsule, f32(9+o), f32(2+o), f32(6), f32(6), f32(180), f32(180))
	procGdipAddPathLine.Call(capsule, uintptr(15+o), uintptr(5+o), uintptr(15+o), uintptr(12+o))
	procGdipAddPathArc.Call(capsule, f32(9+o), f32(9+o), f32(6), f32(6), f32(0), f32(180))
	procGdipClosePathFigure.Call(capsule)
	procGdipDrawPath.Call(g, pen, capsule)

	// ── U-shaped arc ──
	var uarc uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&uarc)))
	if uarc == 0 {
		return
	}
	defer procGdipDeletePath.Call(uarc)
	procGdipAddPathLine.Call(uarc, uintptr(19+o), uintptr(10+o), uintptr(19+o), uintptr(12+o))
	procGdipAddPathArc.Call(uarc, f32(5+o), f32(5+o), f32(14), f32(14), f32(0), f32(180))
	procGdipAddPathLine.Call(uarc, uintptr(5+o), uintptr(12+o), uintptr(5+o), uintptr(10+o))
	procGdipDrawPath.Call(g, pen, uarc)

	// ── Stem ──
	procGdipDrawLineI.Call(g, pen, uintptr(12+o), uintptr(19+o), uintptr(12+o), uintptr(22+o))
}

// iconPenSetup creates a scaled GDI+ pen for icon drawing at the current button size.
// Returns the pen handle and a cleanup function. Caller must call cleanup().
func (fb *FloatingButton) iconPenSetup(g uintptr, alpha uint32) (uintptr, func()) {
	sz := fb.getSize()
	scale := float32(sz) / 56.0
	procGdipScaleWorldTransform.Call(g, f32(scale), f32(scale), 0)
	penColor := (alpha << 24) | (_FLOAT_CLR_ICON & 0x00FFFFFF)
	var pen uintptr
	procGdipCreatePen1.Call(uintptr(penColor), f32(2.0), 2, uintptr(unsafe.Pointer(&pen)))
	if pen != 0 {
		procGdipSetPenLineCap197819.Call(pen, 2, 2, 0)
		procGdipSetPenLineJoin.Call(pen, 2)
	}
	return pen, func() {
		if pen != 0 {
			procGdipDeletePen.Call(pen)
		}
		procGdipResetWorldTransform.Call(g)
	}
}

// drawAppLogoIcon draws the embedded WhisPaste app icon PNG, choosing
// the light- or dark-background variant based on button color luminance.
func (fb *FloatingButton) drawAppLogoIcon(g uintptr, alpha uint32) {
	// Determine button top color luminance to pick the right logo variant
	preset := getFloatPreset(fb.cfg.GetFloatingButtonColor())
	if fb.cfg.GetFloatingButtonColor() == "custom" {
		base := parseHexToARGB(fb.cfg.GetFloatingButtonCustomColor())
		preset = floatColorPreset{Top: base}
	}
	top := preset.Top
	r := float64((top >> 16) & 0xFF)
	gv := float64((top >> 8) & 0xFF)
	b := float64(top & 0xFF)
	lum := 0.299*r + 0.587*gv + 0.114*b // perceived brightness 0–255

	fb.mu.Lock()
	var img uintptr
	if lum < 140 {
		img = fb.appLogoForDark() // dark button → use light/white icon
	} else {
		img = fb.appLogoForLight() // light button → use dark icon
	}
	fb.mu.Unlock()

	if img == 0 {
		// Fallback to mic icon if PNG failed to load
		fb.drawMicIcon(g, alpha)
		return
	}

	sz := fb.getSize()
	margin := sz / 4
	x := margin
	y := margin
	w := sz - 2*margin
	h := sz - 2*margin

	procGdipSetInterpolationMode.Call(g, 7) // HighQualityBicubic
	drawImageWithAlpha(g, img, x, y, w, h, alpha)
}

// appLogoForDark returns the GDI+ image for dark backgrounds. Caller must hold fb.mu.
func (fb *FloatingButton) appLogoForDark() uintptr { return fb.appLogoDark }

// appLogoForLight returns the GDI+ image for light backgrounds. Caller must hold fb.mu.
func (fb *FloatingButton) appLogoForLight() uintptr { return fb.appLogoLight }

// colorMatrix5x5 represents a GDI+ ColorMatrix (5×5 float32 array, row-major).
type colorMatrix5x5 [5][5]float32

// drawImageWithAlpha draws a GDI+ image at the given rect with alpha scaling.
// Uses ImageAttributes ColorMatrix to apply the alpha value to PNG images.
func drawImageWithAlpha(g, img uintptr, x, y, w, h int, alpha uint32) {
	procGdipSetInterpolationMode.Call(g, 7) // HighQualityBicubic

	if alpha >= 255 {
		// Full opacity — no need for ImageAttributes overhead
		procGdipDrawImageRectI.Call(g, img, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
		return
	}

	a := float32(alpha) / 255.0
	// Identity matrix with alpha scaling in [3][3]
	cm := colorMatrix5x5{
		{1, 0, 0, 0, 0},
		{0, 1, 0, 0, 0},
		{0, 0, 1, 0, 0},
		{0, 0, 0, a, 0},
		{0, 0, 0, 0, 1},
	}

	var imgAttr uintptr
	procGdipCreateImageAttributes.Call(uintptr(unsafe.Pointer(&imgAttr)))
	if imgAttr == 0 {
		// Fallback to non-alpha draw
		procGdipDrawImageRectI.Call(g, img, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
		return
	}
	defer procGdipDisposeImageAttributes.Call(imgAttr)

	// ColorAdjustTypeBitmap = 1, ColorMatrixFlagsDefault = 0
	procGdipSetImageAttributesColorMatrix.Call(
		imgAttr,
		1,     // ColorAdjustTypeBitmap
		1,     // enableFlag = TRUE
		uintptr(unsafe.Pointer(&cm)),
		0,     // grayMatrix = NULL
		0,     // flags = ColorMatrixFlagsDefault
	)

	// Get source image dimensions for src rect
	var srcW, srcH uint32
	procGdipGetImageWidth.Call(img, uintptr(unsafe.Pointer(&srcW)))
	procGdipGetImageHeight.Call(img, uintptr(unsafe.Pointer(&srcH)))

	// GdipDrawImageRectRectI(graphics, image, dstX, dstY, dstW, dstH, srcX, srcY, srcW, srcH, unit, imageAttributes)
	procGdipDrawImageRectRectI.Call(
		g, img,
		uintptr(x), uintptr(y), uintptr(w), uintptr(h),
		0, 0, uintptr(srcW), uintptr(srcH),
		2, // UnitPixel
		imgAttr,
		0, 0, // callback, callbackData
	)
}

// drawWaveformIcon draws an audio waveform (5 vertical bars).
func (fb *FloatingButton) drawWaveformIcon(g uintptr, alpha uint32) {
	pen, cleanup := fb.iconPenSetup(g, alpha)
	if pen == 0 {
		cleanup()
		return
	}
	defer cleanup()
	const o = 16
	procGdipDrawLineI.Call(g, pen, uintptr(4+o), uintptr(8+o), uintptr(4+o), uintptr(16+o))
	procGdipDrawLineI.Call(g, pen, uintptr(8+o), uintptr(5+o), uintptr(8+o), uintptr(19+o))
	procGdipDrawLineI.Call(g, pen, uintptr(12+o), uintptr(2+o), uintptr(12+o), uintptr(22+o))
	procGdipDrawLineI.Call(g, pen, uintptr(16+o), uintptr(6+o), uintptr(16+o), uintptr(18+o))
	procGdipDrawLineI.Call(g, pen, uintptr(20+o), uintptr(9+o), uintptr(20+o), uintptr(15+o))
}

// loadCustomImageLocked loads the custom button image via GDI+. Caller must hold fb.mu.
func (fb *FloatingButton) loadCustomImageLocked() {
	if fb.customImagePath == "" {
		return
	}
	pathUTF16, err := windows.UTF16PtrFromString(fb.customImagePath)
	if err != nil {
		logWarn("loadCustomImage: invalid path: %v", err)
		return
	}
	var img uintptr
	ret, _, _ := procGdipLoadImageFromFile.Call(uintptr(unsafe.Pointer(pathUTF16)), uintptr(unsafe.Pointer(&img)))
	if ret != 0 || img == 0 {
		logWarn("loadCustomImage: GdipLoadImageFromFile failed (status %d)", ret)
		return
	}
	fb.customImage = img
}

// loadImageFromMemory creates a GDI+ image from an in-memory byte slice using
// SHCreateMemStream → GdipCreateBitmapFromStream. The IStream is intentionally
// not released because GDI+ keeps a reference to it for the image's lifetime.
func loadImageFromMemory(data []byte) uintptr {
	if len(data) == 0 {
		return 0
	}
	stream, _, _ := procSHCreateMemStream.Call(uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)))
	if stream == 0 {
		return 0
	}
	var img uintptr
	ret, _, _ := procGdipCreateBitmapFromStream.Call(stream, uintptr(unsafe.Pointer(&img)))
	if ret != 0 || img == 0 {
		return 0
	}
	return img
}

// loadAppLogos loads the embedded app icon PNGs into GDI+ images. Called once during init.
func (fb *FloatingButton) loadAppLogos() {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	if fb.appLogoLight == 0 {
		fb.appLogoLight = loadImageFromMemory(appLogoForLight)
	}
	if fb.appLogoDark == 0 {
		fb.appLogoDark = loadImageFromMemory(appLogoForDark)
	}
}

// drawCustomImageIcon draws the user's custom image scaled to fit inside the button.
func (fb *FloatingButton) drawCustomImageIcon(g uintptr, alpha uint32) {
	fb.mu.Lock()
	img := fb.customImage
	fb.mu.Unlock()

	if img == 0 {
		// Fallback to microphone if image not loaded
		fb.drawMicIcon(g, alpha)
		return
	}

	sz := fb.getSize()
	// Inset the image by ~25% on each side so it fits inside the button shape
	margin := sz / 4
	x := margin
	y := margin
	w := sz - 2*margin
	h := sz - 2*margin

	// Set interpolation mode to high quality bicubic (7)
	procGdipSetInterpolationMode.Call(g, 7)
	drawImageWithAlpha(g, img, x, y, w, h, alpha)
}

// ───────────────────── Tooltip ─────────────────────

// createTooltip creates a Win32 tooltip control attached to the floating button window.
func (fb *FloatingButton) createTooltip(hInst uintptr) {
	ttClass, _ := windows.UTF16PtrFromString("tooltips_class32")
	hwndTip, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(ttClass)),
		0,
		uintptr(_TTS_ALWAYSTIP|_TTS_NOPREFIX),
		0, 0, 0, 0,
		fb.hwnd, 0, hInst, 0,
	)
	if hwndTip == 0 {
		logWarn("Failed to create floating button tooltip")
		return
	}
	fb.tooltipHwnd = hwndTip

	tipText, _ := windows.UTF16PtrFromString("WhisPaste — " + T("floating.status_ready"))
	var ti toolInfoW
	ti.CbSize = uint32(unsafe.Sizeof(ti))
	ti.UFlags = _TTF_IDISHWND | _TTF_SUBCLASS
	ti.Hwnd = fb.hwnd
	ti.UID = fb.hwnd
	ti.LpszText = tipText
	procSendMessageW.Call(hwndTip, _TTM_ADDTOOLW, 0, uintptr(unsafe.Pointer(&ti)))
}

// updateTooltip updates the tooltip text based on the current app state.
// Must be called on the window thread (via PostMessage).
func (fb *FloatingButton) updateTooltip() {
	if fb.tooltipHwnd == 0 {
		return
	}
	appState := StateIdle
	if fn := func() func() AppState {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		return fb.getState
	}(); fn != nil {
		appState = fn()
	}

	var statusKey string
	switch appState {
	case StateRecording:
		statusKey = "floating.tip_recording"
	case StatePaused:
		statusKey = "floating.tip_paused"
	case StateTranscribing:
		statusKey = "floating.tip_transcribing"
	case StateProcessing:
		statusKey = "floating.tip_processing"
	default:
		statusKey = "floating.tip_ready"
	}

	tipText, _ := windows.UTF16PtrFromString(T(statusKey))
	var ti toolInfoW
	ti.CbSize = uint32(unsafe.Sizeof(ti))
	ti.UFlags = _TTF_IDISHWND | _TTF_SUBCLASS
	ti.Hwnd = fb.hwnd
	ti.UID = fb.hwnd
	ti.LpszText = tipText
	procSendMessageW.Call(fb.tooltipHwnd, _TTM_UPDATETIPTEXTW, 0, uintptr(unsafe.Pointer(&ti)))
}

// ───────────────────── Recording State ─────────────────────

// SetRecordingStart records when a recording session began (for countdown arc).
func (fb *FloatingButton) SetRecordingStart(t time.Time) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	fb.recordingStart = t
}

// NotifyStateChanged triggers a re-render and tooltip update to reflect the current state.
func (fb *FloatingButton) NotifyStateChanged() {
	if fb.hwnd != 0 {
		procPostMessageW.Call(fb.hwnd, _WM_FLOAT_RERENDER, 0, 0)
	}
}

// ───────────────────── Position Management ─────────────────────

func (fb *FloatingButton) onWindowMoved() {
	// Debounce: save at most every 500ms
	now := time.Now()
	shouldSave := func() bool {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		if now.Sub(fb.lastMoveSave) < 500*time.Millisecond {
			return false
		}
		fb.lastMoveSave = now
		return true
	}()
	if !shouldSave {
		return
	}

	var rc rectT
	procGetWindowRect.Call(fb.hwnd, uintptr(unsafe.Pointer(&rc)))
	x, y := int(rc.Left), int(rc.Top)

	go func() {
		fb.cfg.mu.Lock()
		fb.cfg.FloatingButtonX = x
		fb.cfg.FloatingButtonY = y
		fb.cfg.mu.Unlock()
		fb.cfg.Save()
	}()
}

func (fb *FloatingButton) restorePosition() {
	x, y := fb.cfg.GetFloatingButtonPos()
	if x == 0 && y == 0 {
		return // use window's current position
	}

	sz := fb.getSize()
	// Clamp to nearest monitor work area
	x, y = fb.clampToMonitor(x, y)

	procMoveWindow.Call(fb.hwnd, uintptr(x), uintptr(y), uintptr(sz), uintptr(sz), 1)
}

func (fb *FloatingButton) clampToMonitor(x, y int) (int, int) {
	sz := fb.getSize()
	// Temporarily move to get the right monitor
	procMoveWindow.Call(fb.hwnd, uintptr(x), uintptr(y), uintptr(sz), uintptr(sz), 0)
	hMon, _, _ := procMonitorFromWindow.Call(fb.hwnd, _MONITOR_DEFAULTTONEAREST)
	if hMon == 0 {
		return x, y
	}

	var mi monitorInfo
	mi.CbSize = uint32(unsafe.Sizeof(mi))
	ret, _, _ := procGetMonitorInfoW.Call(hMon, uintptr(unsafe.Pointer(&mi)))
	if ret == 0 {
		return x, y
	}

	work := mi.RcWork
	if x < int(work.Left) {
		x = int(work.Left)
	}
	if y < int(work.Top) {
		y = int(work.Top)
	}
	if x+sz > int(work.Right) {
		x = int(work.Right) - sz
	}
	if y+sz > int(work.Bottom) {
		y = int(work.Bottom) - sz
	}

	// Edge snapping (scaled for DPI)
	snap := int(float64(_FLOAT_SNAP_PX) * fb.dpiScale())
	if x-int(work.Left) < snap {
		x = int(work.Left)
	}
	if int(work.Right)-x-sz < snap {
		x = int(work.Right) - sz
	}
	if y-int(work.Top) < snap {
		y = int(work.Top)
	}
	if int(work.Bottom)-y-sz < snap {
		y = int(work.Bottom) - sz
	}

	return x, y
}

// ───────────────────── Context Menu ─────────────────────

func (fb *FloatingButton) showContextMenu(hwnd uintptr) {
	hMenu, _, _ := procCreatePopupMenu.Call()
	if hMenu == 0 {
		return
	}

	// Snapshot state providers under lock
	var getState func() AppState
	var getHotkeyStr func() string
	var getLatestText func() string
	func() {
		fb.mu.Lock()
		defer fb.mu.Unlock()
		getState = fb.getState
		getHotkeyStr = fb.getHotkeyStr
		getLatestText = fb.getLatestText
	}()

	// --- Status line (disabled/grayed, informational) ---
	statusKey := "floating.status_ready"
	appState := StateIdle
	if getState != nil {
		appState = getState()
	}
	switch appState {
	case StateRecording, StatePaused:
		statusKey = "floating.status_record"
	case StateTranscribing, StateProcessing:
		statusKey = "floating.status_working"
	}
	statusText, _ := windows.UTF16PtrFromString("● " + T(statusKey))
	procAppendMenuW.Call(hMenu, _MF_STRING|_MF_GRAYED, 0, uintptr(unsafe.Pointer(statusText)))

	// --- Last transcription preview (click to copy) ---
	var previewFull string
	if getLatestText != nil {
		previewFull = getLatestText()
	}
	if previewFull != "" {
		preview := truncateRunes(previewFull, 35)
		previewLabel := fmt.Sprintf(T("floating.last_text"), preview)
		previewPtr, _ := windows.UTF16PtrFromString(previewLabel)
		procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_PREVIEW, uintptr(unsafe.Pointer(previewPtr)))
	}

	procAppendMenuW.Call(hMenu, _MF_SEPARATOR, 0, 0)

	// --- Start/Stop Recording + hotkey shortcut ---
	isRecording := appState == StateRecording || appState == StatePaused
	recordKey := "tray.start_record"
	if isRecording {
		recordKey = "tray.stop_record"
	}
	recordLabel := T(recordKey)
	if getHotkeyStr != nil {
		if hk := getHotkeyStr(); hk != "" {
			recordLabel += "\t" + hk
		}
	}
	recordPtr, _ := windows.UTF16PtrFromString(recordLabel)
	recordFlags := uintptr(_MF_STRING)
	if appState == StateTranscribing || appState == StateProcessing {
		recordFlags |= _MF_GRAYED
	}
	procAppendMenuW.Call(hMenu, recordFlags, _FLOAT_MENU_RECORD, uintptr(unsafe.Pointer(recordPtr)))

	// --- Smart Mode toggle ---
	smartText, _ := windows.UTF16PtrFromString(T("tray.smart_mode"))
	smartFlags := uintptr(_MF_STRING)
	if fb.cfg.GetSmartMode() {
		smartFlags |= _MF_CHECKED
	}
	procAppendMenuW.Call(hMenu, smartFlags, _FLOAT_MENU_SMART_MODE, uintptr(unsafe.Pointer(smartText)))

	// --- Auto-Paste toggle ---
	autoPasteText, _ := windows.UTF16PtrFromString(T("floating.auto_paste"))
	autoPasteFlags := uintptr(_MF_STRING)
	if fb.cfg.GetAutoPaste() {
		autoPasteFlags |= _MF_CHECKED
	}
	procAppendMenuW.Call(hMenu, autoPasteFlags, _FLOAT_MENU_AUTO_PASTE, uintptr(unsafe.Pointer(autoPasteText)))

	procAppendMenuW.Call(hMenu, _MF_SEPARATOR, 0, 0)

	// --- Dashboard ---
	dashText, _ := windows.UTF16PtrFromString(T("tray.notebook"))
	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_DASHBOARD, uintptr(unsafe.Pointer(dashText)))

	// --- Settings ---
	settingsText, _ := windows.UTF16PtrFromString(T("tray.settings"))
	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_SETTINGS, uintptr(unsafe.Pointer(settingsText)))

	procAppendMenuW.Call(hMenu, _MF_SEPARATOR, 0, 0)

	// --- Lock position toggle ---
	lockText, _ := windows.UTF16PtrFromString(T("floating.lock"))
	lockFlags := uintptr(_MF_STRING)
	if fb.cfg.GetFloatingButtonLocked() {
		lockFlags |= _MF_CHECKED
	}
	procAppendMenuW.Call(hMenu, lockFlags, _FLOAT_MENU_LOCK, uintptr(unsafe.Pointer(lockText)))

	// --- Hide button ---
	hideText, _ := windows.UTF16PtrFromString(T("floating.hide"))
	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_HIDE, uintptr(unsafe.Pointer(hideText)))

	// --- Quit ---
	quitText, _ := windows.UTF16PtrFromString(T("tray.quit"))
	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_QUIT, uintptr(unsafe.Pointer(quitText)))

	var pt pointT
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))

	procSetForegroundWindow.Call(hwnd)
	procTrackPopupMenu.Call(hMenu, _TPM_RIGHTBUTTON, uintptr(pt.X), uintptr(pt.Y), 0, hwnd, 0)
	procDestroyMenu.Call(hMenu)

	procPostMessageW.Call(hwnd, _WM_USER, 0, 0)
}
