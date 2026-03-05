package main

import (
	"fmt"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ───────────────────── Floating Button Constants ─────────────────────

const (
	_FLOAT_SIZE = 56 // diameter in pixels

	// Custom window messages (offset from overlay to avoid collision)
	_WM_FLOAT_SHOW   = _WM_USER + 20
	_WM_FLOAT_HIDE   = _WM_USER + 21
	_WM_FLOAT_RERENDER = _WM_USER + 22

	// Timer for hover/opacity animation
	_FLOAT_TIMER_ID = 2
	_FLOAT_TIMER_MS = 16 // ~60 FPS

	// Opacity
	_FLOAT_OPACITY_IDLE  = 178 // ~70%
	_FLOAT_OPACITY_HOVER = 255 // 100%
	_FLOAT_OPACITY_STEP  = 20  // per-frame change

	// Edge snapping threshold
	_FLOAT_SNAP_PX = 10

	// Icon color
	_FLOAT_CLR_ICON = 0xFFFFFFFF // white mic icon

	// Context menu IDs
	_FLOAT_MENU_SETTINGS = 1
	_FLOAT_MENU_HIDE     = 2

	// Win32 menu constants
	_MF_STRING    = 0x0000
	_MF_SEPARATOR = 0x0800
	_TPM_RIGHTBUTTON = 0x0002

	// Non-client messages (needed because HTCAPTION consumes LBUTTONxx/RBUTTONxx)
	_WM_NCLBUTTONDOWN = 0x00A1
	_WM_NCLBUTTONUP   = 0x00A2
	_WM_NCRBUTTONUP   = 0x00A5

	// Mouse tracking
	_TME_LEAVE    = 0x00000002
	_WM_MOUSEMOVE  = 0x0200
	_WM_MOUSELEAVE = 0x02A3
	_WM_MOVE       = 0x0003
	_WM_COMMAND    = 0x0111

	// Monitor info
	_MONITOR_DEFAULTTONEAREST = 0x00000002
)

// Win32 structs for floating button
type trackMouseEventT struct {
	CbSize      uint32
	DwFlags     uint32
	HwndTrack   uintptr
	DwHoverTime uint32
}

type monitorInfo struct {
	CbSize    uint32
	RcMonitor rectT
	RcWork    rectT
	DwFlags   uint32
}

// Win32 procs (reuse overlay DLL handles)
var (
	procCreatePopupMenu  = ovlUser32.NewProc("CreatePopupMenu")
	procAppendMenuW      = ovlUser32.NewProc("AppendMenuW")
	procTrackPopupMenu   = ovlUser32.NewProc("TrackPopupMenu")
	procDestroyMenu      = ovlUser32.NewProc("DestroyMenu")
	procSetForegroundWindow = ovlUser32.NewProc("SetForegroundWindow")
	procMonitorFromWindow = ovlUser32.NewProc("MonitorFromWindow")
	procGetMonitorInfoW  = ovlUser32.NewProc("GetMonitorInfoW")
	procDestroyWindow    = ovlUser32.NewProc("DestroyWindow")
	procGetWindowRect    = ovlUser32.NewProc("GetWindowRect")
	procMoveWindow       = ovlUser32.NewProc("MoveWindow")

	// GDI+ string alignment (used in drawMicIcon)
	procGdipSetStringFormatAlign     = ovlGdiplus.NewProc("GdipSetStringFormatAlign")
	procGdipSetStringFormatLineAlign = ovlGdiplus.NewProc("GdipSetStringFormatLineAlign")
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

// ───────────────────── FloatingButton ─────────────────────

var globalFloating *FloatingButton

// FloatingButton is a small always-on-top circle that starts recording on click.
type FloatingButton struct {
	hwnd    uintptr
	dibDC   uintptr
	dibBmp  uintptr
	ready   chan error
	done    chan struct{}
	cfg     *Config

	onStartRecording func()
	onShowSettings   func()

	hovered       bool
	tracking      bool
	opacity       byte
	targetOpacity byte
	dragStartX    int32 // window X at start of potential drag
	dragStartY    int32 // window Y at start of potential drag

	// Position save debouncing
	lastMoveSave time.Time

	mu sync.Mutex
}

var floatingWndProcCB = syscall.NewCallback(floatingWndProc)

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
		// Entire window is draggable
		return _HTCAPTION

	case _WM_NCLBUTTONDOWN:
		// Record window position before the system's modal move loop starts
		var rc rectT
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		fb.mu.Lock()
		fb.dragStartX = rc.Left
		fb.dragStartY = rc.Top
		fb.mu.Unlock()
		// Let DefWindowProc handle the move
		ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		return ret

	case _WM_NCLBUTTONUP:
		// After the modal move loop ends, check if the window actually moved.
		// If it didn't move, treat it as a click → start recording.
		var rc rectT
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		fb.mu.Lock()
		wasDrag := rc.Left != fb.dragStartX || rc.Top != fb.dragStartY
		cb := fb.onStartRecording
		fb.mu.Unlock()
		if !wasDrag && cb != nil {
			procPostMessageW.Call(hwnd, _WM_FLOAT_HIDE, 0, 0)
			go cb()
		}
		return 0

	case _WM_NCRBUTTONUP:
		fb.showContextMenu(hwnd)
		return 0

	case _WM_MOUSEMOVE:
		fb.mu.Lock()
		wasHovered := fb.hovered
		fb.hovered = true
		fb.targetOpacity = _FLOAT_OPACITY_HOVER
		if !fb.tracking {
			fb.tracking = true
			tme := trackMouseEventT{
				CbSize:    uint32(unsafe.Sizeof(trackMouseEventT{})),
				DwFlags:   _TME_LEAVE,
				HwndTrack: hwnd,
			}
			procTrackMouseEvent.Call(uintptr(unsafe.Pointer(&tme)))
		}
		fb.mu.Unlock()
		if !wasHovered {
			procSetTimer.Call(hwnd, _FLOAT_TIMER_ID, _FLOAT_TIMER_MS, 0)
		}
		return 0

	case _WM_MOUSELEAVE:
		fb.mu.Lock()
		fb.hovered = false
		fb.tracking = false
		fb.targetOpacity = _FLOAT_OPACITY_IDLE
		fb.mu.Unlock()
		return 0

	case _WM_MOVE:
		fb.onWindowMoved()
		return 0

	case _WM_TIMER:
		if wParam == _FLOAT_TIMER_ID {
			fb.mu.Lock()
			target := fb.targetOpacity
			current := fb.opacity
			fb.mu.Unlock()

			if current != target {
				if current < target {
					current += _FLOAT_OPACITY_STEP
					if current > target {
						current = target
					}
				} else {
					if current < _FLOAT_OPACITY_STEP {
						current = target
					} else {
						current -= _FLOAT_OPACITY_STEP
						if current < target {
							current = target
						}
					}
				}
				fb.mu.Lock()
				fb.opacity = current
				fb.mu.Unlock()
				fb.render()
			} else {
				// Stop timer when target reached and not hovered
				fb.mu.Lock()
				h := fb.hovered
				fb.mu.Unlock()
				if !h {
					procKillTimer.Call(hwnd, _FLOAT_TIMER_ID)
				}
			}
		}
		return 0

	case _WM_COMMAND:
		switch int(wParam & 0xFFFF) {
		case _FLOAT_MENU_SETTINGS:
			fb.mu.Lock()
			cb := fb.onShowSettings
			fb.mu.Unlock()
			if cb != nil {
				go cb()
			}
		case _FLOAT_MENU_HIDE:
			procPostMessageW.Call(hwnd, _WM_FLOAT_HIDE, 0, 0)
			go func() {
				fb.cfg.mu.Lock()
				fb.cfg.FloatingButtonEnabled = false
				fb.cfg.mu.Unlock()
				fb.cfg.Save()
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
		fb.render()
		return 0

	case _WM_FLOAT_HIDE:
		procShowWindow.Call(hwnd, uintptr(_SW_HIDE))
		procKillTimer.Call(hwnd, _FLOAT_TIMER_ID)
		return 0

	case _WM_FLOAT_RERENDER:
		fb.render()
		return 0

	case _WM_DESTROY:
		procKillTimer.Call(hwnd, _FLOAT_TIMER_ID)
		if fb.dibDC != 0 {
			procDeleteDC.Call(fb.dibDC)
		}
		if fb.dibBmp != 0 {
			procDeleteObject.Call(fb.dibBmp)
		}
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
		ready:         make(chan error, 1),
		done:          make(chan struct{}),
		cfg:           c,
		opacity:       _FLOAT_OPACITY_IDLE,
		targetOpacity: _FLOAT_OPACITY_IDLE,
	}
	globalFloating = fb

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		if err := fb.initWindow(); err != nil {
			fb.ready <- err
			return
		}
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
func (fb *FloatingButton) SetCallbacks(onStart func(), onSettings func()) {
	fb.mu.Lock()
	fb.onStartRecording = onStart
	fb.onShowSettings = onSettings
	fb.mu.Unlock()
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

// ───────────────────── Window Init ─────────────────────

func (fb *FloatingButton) initWindow() error {
	hInst, _, _ := procGetModuleHandleW.Call(0)
	className, _ := windows.UTF16PtrFromString("WhispasteFloating")

	var wc wndClassExW
	wc.CbSize = uint32(unsafe.Sizeof(wc))
	wc.Style = _CS_HREDRAW | _CS_VREDRAW
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
	x := int(screenW) - _FLOAT_SIZE - 40
	y := int(screenH) - _FLOAT_SIZE - 120

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
		uintptr(x), uintptr(y), _FLOAT_SIZE, _FLOAT_SIZE,
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowExW failed for floating button")
	}
	fb.hwnd = hwnd

	// Create DIB section for per-pixel alpha rendering
	fb.createDIB()
	fb.render()

	return nil
}

// ───────────────────── DIB + Rendering ─────────────────────

func (fb *FloatingButton) createDIB() {
	var bmi bitmapInfoHeader
	bmi.BiSize = uint32(unsafe.Sizeof(bmi))
	bmi.BiWidth = _FLOAT_SIZE
	bmi.BiHeight = -_FLOAT_SIZE // top-down
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

	fb.mu.Lock()
	hovered := fb.hovered
	alpha := fb.opacity
	fb.mu.Unlock()

	a := uint32(alpha)
	preset := getFloatPreset(fb.cfg.GetFloatingButtonColor())

	// Outer glow (semi-transparent accent ring behind the circle)
	glowAlpha := a * 40 / 255 // subtle glow
	glowColor := (glowAlpha << 24) | (preset.Top & 0x00FFFFFF)
	var glowBrush uintptr
	procGdipCreateSolidFill.Call(uintptr(glowColor), uintptr(unsafe.Pointer(&glowBrush)))
	if glowBrush != 0 {
		procGdipFillEllipseI.Call(g, glowBrush, 0, 0, _FLOAT_SIZE, _FLOAT_SIZE)
		procGdipDeleteBrush.Call(glowBrush)
	}

	// Shadow (offset 2px down-right, drawn within glow area)
	shadowAlpha := a * 48 / 255
	shadowColor := shadowAlpha << 24
	var shadowBrush uintptr
	procGdipCreateSolidFill.Call(uintptr(shadowColor), uintptr(unsafe.Pointer(&shadowBrush)))
	if shadowBrush != 0 {
		procGdipFillEllipseI.Call(g, shadowBrush, 4, 4, _FLOAT_SIZE-4, _FLOAT_SIZE-4)
		procGdipDeleteBrush.Call(shadowBrush)
	}

	// Main circle with 135° gradient (top-left → bottom-right)
	topClr, botClr := preset.Top, preset.Bottom
	if hovered {
		topClr, botClr = preset.HoverTop, preset.HoverBot
	}
	topClr = (a << 24) | (topClr & 0x00FFFFFF)
	botClr = (a << 24) | (botClr & 0x00FFFFFF)

	// GdipCreateLineBrushFromRectI uses a rect + LinearGradientMode
	// For 135° we use ForwardDiagonal (mode=2)
	type gpRectI struct{ X, Y, W, H int32 }
	circleRect := gpRectI{2, 2, int32(_FLOAT_SIZE - 4), int32(_FLOAT_SIZE - 4)}
	var gradBrush uintptr
	procGdipCreateLineBrushFromRectI.Call(
		uintptr(unsafe.Pointer(&circleRect)),
		uintptr(topClr),
		uintptr(botClr),
		2, // LinearGradientModeForwardDiagonal (135°)
		0, // WrapModeTile
		uintptr(unsafe.Pointer(&gradBrush)),
	)
	if gradBrush != 0 {
		procGdipFillEllipseI.Call(g, gradBrush, 2, 2, _FLOAT_SIZE-4, _FLOAT_SIZE-4)
		procGdipDeleteBrush.Call(gradBrush)
	}

	// Mic icon
	fb.drawMicIcon(g, a)

	// UpdateLayeredWindow
	blend := blendFunction{
		BlendOp:             0, // AC_SRC_OVER
		SourceConstantAlpha: 255,
		AlphaFormat:         1, // AC_SRC_ALPHA
	}
	ptSrc := pointT{0, 0}
	sz := sizeT{_FLOAT_SIZE, _FLOAT_SIZE}

	procUpdateLayeredWindow.Call(
		fb.hwnd,
		0,
		0, // keep position
		uintptr(unsafe.Pointer(&sz)),
		fb.dibDC,
		uintptr(unsafe.Pointer(&ptSrc)),
		0,
		uintptr(unsafe.Pointer(&blend)),
		2, // ULW_ALPHA
	)
}

func (fb *FloatingButton) drawMicIcon(g uintptr, alpha uint32) {
	// Use Segoe MDL2 Assets for the microphone glyph
	fontName, _ := windows.UTF16PtrFromString("Segoe MDL2 Assets")
	var fontFamily uintptr
	procGdipCreateFontFamilyFromName.Call(
		uintptr(unsafe.Pointer(fontName)),
		0,
		uintptr(unsafe.Pointer(&fontFamily)),
	)
	if fontFamily == 0 {
		return
	}
	defer procGdipDeleteFontFamily.Call(fontFamily)

	var font uintptr
	procGdipCreateFont.Call(fontFamily, f32(22), _FontStyleRegular, _UnitPixel,
		uintptr(unsafe.Pointer(&font)))
	if font == 0 {
		return
	}
	defer procGdipDeleteFont.Call(font)

	var strFmt uintptr
	procGdipCreateStringFormat.Call(0, 0, uintptr(unsafe.Pointer(&strFmt)))
	if strFmt == 0 {
		return
	}
	defer procGdipDeleteStringFormat.Call(strFmt)

	// Center alignment
	const _StringAlignmentCenter = 1
	procGdipSetStringFormatAlign.Call(strFmt, _StringAlignmentCenter)
	procGdipSetStringFormatLineAlign.Call(strFmt, _StringAlignmentCenter)

	// Icon color with alpha
	iconColor := (alpha << 24) | (_FLOAT_CLR_ICON & 0x00FFFFFF)
	var brush uintptr
	procGdipCreateSolidFill.Call(uintptr(iconColor), uintptr(unsafe.Pointer(&brush)))
	if brush == 0 {
		return
	}
	defer procGdipDeleteBrush.Call(brush)

	// Microphone glyph: U+E720
	micStr, _ := windows.UTF16PtrFromString("\uE720")
	rect := gdipRectF{
		X: 2, Y: 2,
		Width:  float32(_FLOAT_SIZE - 4),
		Height: float32(_FLOAT_SIZE - 4),
	}
	procGdipDrawString.Call(g, uintptr(unsafe.Pointer(micStr)), 1,
		font, uintptr(unsafe.Pointer(&rect)), strFmt, brush)
}

// ───────────────────── Position Management ─────────────────────

func (fb *FloatingButton) onWindowMoved() {
	// Debounce: save at most every 500ms
	now := time.Now()
	fb.mu.Lock()
	if now.Sub(fb.lastMoveSave) < 500*time.Millisecond {
		fb.mu.Unlock()
		return
	}
	fb.lastMoveSave = now
	fb.mu.Unlock()

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

	// Clamp to nearest monitor work area
	x, y = fb.clampToMonitor(x, y)

	procMoveWindow.Call(fb.hwnd, uintptr(x), uintptr(y), _FLOAT_SIZE, _FLOAT_SIZE, 1)
}

func (fb *FloatingButton) clampToMonitor(x, y int) (int, int) {
	// Temporarily move to get the right monitor
	procMoveWindow.Call(fb.hwnd, uintptr(x), uintptr(y), _FLOAT_SIZE, _FLOAT_SIZE, 0)
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
	if x+_FLOAT_SIZE > int(work.Right) {
		x = int(work.Right) - _FLOAT_SIZE
	}
	if y+_FLOAT_SIZE > int(work.Bottom) {
		y = int(work.Bottom) - _FLOAT_SIZE
	}

	// Edge snapping
	if x-int(work.Left) < _FLOAT_SNAP_PX {
		x = int(work.Left)
	}
	if int(work.Right)-x-_FLOAT_SIZE < _FLOAT_SNAP_PX {
		x = int(work.Right) - _FLOAT_SIZE
	}
	if y-int(work.Top) < _FLOAT_SNAP_PX {
		y = int(work.Top)
	}
	if int(work.Bottom)-y-_FLOAT_SIZE < _FLOAT_SNAP_PX {
		y = int(work.Bottom) - _FLOAT_SIZE
	}

	return x, y
}

// ───────────────────── Context Menu ─────────────────────

func (fb *FloatingButton) showContextMenu(hwnd uintptr) {
	hMenu, _, _ := procCreatePopupMenu.Call()
	if hMenu == 0 {
		return
	}

	settingsText, _ := windows.UTF16PtrFromString(T("tray.settings"))
	hideText, _ := windows.UTF16PtrFromString(T("floating.hide"))

	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_SETTINGS, uintptr(unsafe.Pointer(settingsText)))
	procAppendMenuW.Call(hMenu, _MF_SEPARATOR, 0, 0)
	procAppendMenuW.Call(hMenu, _MF_STRING, _FLOAT_MENU_HIDE, uintptr(unsafe.Pointer(hideText)))

	var pt pointT
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))

	// Required for popup menu to work on a tool window
	procSetForegroundWindow.Call(hwnd)
	procTrackPopupMenu.Call(hMenu, _TPM_RIGHTBUTTON, uintptr(pt.X), uintptr(pt.Y), 0, hwnd, 0)
	procDestroyMenu.Call(hMenu)

	// Post a dummy message to dismiss the menu properly
	procPostMessageW.Call(hwnd, _WM_USER, 0, 0)
}
