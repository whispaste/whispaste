package main

import (
	"fmt"
	"math"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ───────────────────── Win32 constants ─────────────────────

const (
	// Window styles
	_WS_POPUP   = 0x80000000
	_WS_VISIBLE = 0x10000000

	// Extended window styles
	_WS_EX_TOPMOST     = 0x00000008
	_WS_EX_LAYERED     = 0x00080000
	_WS_EX_TRANSPARENT = 0x00000020
	_WS_EX_TOOLWINDOW  = 0x00000080

	// Class styles
	_CS_HREDRAW = 0x0002
	_CS_VREDRAW = 0x0001

	// Messages
	_WM_CREATE      = 0x0001
	_WM_DESTROY     = 0x0002
	_WM_PAINT       = 0x000F
	_WM_CLOSE       = 0x0010
	_WM_ERASEBKGND  = 0x0014
	_WM_TIMER       = 0x0113
	_WM_USER        = 0x0400

	// Custom messages
	_WM_OVL_SHOW   = _WM_USER + 1
	_WM_OVL_HIDE   = _WM_USER + 2
	_WM_OVL_LEVEL  = _WM_USER + 3

	// ShowWindow
	_SW_HIDE       = 0
	_SW_SHOWNA     = 8

	// System metrics
	_SM_CXSCREEN = 0

	// Layered window
	_LWA_COLORKEY = 0x00000001
	_LWA_ALPHA    = 0x00000002

	// Cursor
	_IDC_ARROW = 32512

	// GDI
	_TRANSPARENT     = 1
	_PS_SOLID        = 0
	_PS_NULL         = 5
	_NULL_PEN        = 8
	_NULL_BRUSH      = 5
	_FW_NORMAL       = 400
	_FW_SEMIBOLD     = 600
	_DEFAULT_CHARSET = 1
	_CLEARTYPE_QUALITY = 5
	_DT_CENTER     = 0x0001
	_DT_VCENTER    = 0x0004
	_DT_SINGLELINE = 0x0020

	// Timer
	_TIMER_ID  = 1
	_TIMER_MS  = 33 // ~30 FPS

	// Window dimensions
	_OVL_WIDTH  = 300
	_OVL_HEIGHT = 60
	_OVL_MARGIN = 20

	// Colors (COLORREF = 0x00BBGGRR)
	_CLR_BACKGROUND = 0x002E1A1A // RGB(26,26,46)
	_CLR_BORDER     = 0x00504030 // subtle border
	_CLR_TEXT       = 0x00FFFFFF // white
	_CLR_RED_DOT    = 0x003C3CFF // RGB(255,60,60)
	_CLR_BAR        = 0x00FFA050 // accent for waveform
	_CLR_COLORKEY   = 0x00FF00FF // magenta – transparent
)

// ───────────────────── Win32 types ─────────────────────

type pointT struct{ X, Y int32 }
type rectT struct{ Left, Top, Right, Bottom int32 }

type wndClassExW struct {
	CbSize        uint32
	Style         uint32
	LpfnWndProc   uintptr
	CbClsExtra    int32
	CbWndExtra    int32
	HInstance     uintptr
	HIcon         uintptr
	HCursor       uintptr
	HbrBackground uintptr
	LpszMenuName  *uint16
	LpszClassName *uint16
	HIconSm       uintptr
}

type msgT struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      pointT
}

type paintStructT struct {
	Hdc         uintptr
	FErase      int32
	RcPaint     rectT
	FRestore    int32
	FIncUpdate  int32
	RgbReserved [32]byte
}

// ───────────────────── Win32 procs ─────────────────────

var (
	ovlUser32   = windows.NewLazySystemDLL("user32.dll")
	ovlGdi32    = windows.NewLazySystemDLL("gdi32.dll")
	ovlKernel32 = windows.NewLazySystemDLL("kernel32.dll")

	procRegisterClassExW        = ovlUser32.NewProc("RegisterClassExW")
	procCreateWindowExW         = ovlUser32.NewProc("CreateWindowExW")
	procShowWindow              = ovlUser32.NewProc("ShowWindow")
	procDestroyWindow           = ovlUser32.NewProc("DestroyWindow")
	procSetTimer                = ovlUser32.NewProc("SetTimer")
	procKillTimer               = ovlUser32.NewProc("KillTimer")
	procGetMessageW             = ovlUser32.NewProc("GetMessageW")
	procTranslateMessage        = ovlUser32.NewProc("TranslateMessage")
	procDispatchMessageW        = ovlUser32.NewProc("DispatchMessageW")
	procDefWindowProcW          = ovlUser32.NewProc("DefWindowProcW")
	procBeginPaint              = ovlUser32.NewProc("BeginPaint")
	procEndPaint                = ovlUser32.NewProc("EndPaint")
	procInvalidateRect          = ovlUser32.NewProc("InvalidateRect")
	procGetSystemMetrics        = ovlUser32.NewProc("GetSystemMetrics")
	procPostMessageW            = ovlUser32.NewProc("PostMessageW")
	procSetWindowPos            = ovlUser32.NewProc("SetWindowPos")
	procSetLayeredWindowAttributes = ovlUser32.NewProc("SetLayeredWindowAttributes")
	procLoadCursorW             = ovlUser32.NewProc("LoadCursorW")
	procPostQuitMessage         = ovlUser32.NewProc("PostQuitMessage")
	procFillRect                = ovlUser32.NewProc("FillRect")
	procDrawTextW               = ovlUser32.NewProc("DrawTextW")

	procCreateSolidBrush = ovlGdi32.NewProc("CreateSolidBrush")
	procCreatePen        = ovlGdi32.NewProc("CreatePen")
	procCreateFontW      = ovlGdi32.NewProc("CreateFontW")
	procDeleteObject     = ovlGdi32.NewProc("DeleteObject")
	procSelectObject     = ovlGdi32.NewProc("SelectObject")
	procSetBkMode        = ovlGdi32.NewProc("SetBkMode")
	procSetTextColor     = ovlGdi32.NewProc("SetTextColor")
	procRoundRect        = ovlGdi32.NewProc("RoundRect")
	procRectangle        = ovlGdi32.NewProc("Rectangle")
	procEllipse          = ovlGdi32.NewProc("Ellipse")
	procGetStockObject   = ovlGdi32.NewProc("GetStockObject")

	procGetModuleHandleW = ovlKernel32.NewProc("GetModuleHandleW")
)

// ───────────────────── Overlay ─────────────────────

var globalOverlay *Overlay

// Overlay displays a recording/transcribing indicator.
type Overlay struct {
	hwnd      uintptr
	font      uintptr
	state     AppState
	level     float32
	levels    [30]float32 // ring buffer for scrolling waveform
	levelIdx  int
	startTime time.Time
	frame     int
	visible   bool
	ready     chan error
	done      chan struct{}
	mu        sync.Mutex
}

var overlayWndProcCB = syscall.NewCallback(overlayWndProc)

func overlayWndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	o := globalOverlay
	if o == nil {
		ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		return ret
	}

	switch uint32(msg) {
	case _WM_PAINT:
		o.paint(hwnd)
		return 0

	case _WM_ERASEBKGND:
		return 1

	case _WM_TIMER:
		o.mu.Lock()
		o.frame++
		o.mu.Unlock()
		procInvalidateRect.Call(hwnd, 0, 1)
		return 0

	case _WM_OVL_SHOW:
		o.mu.Lock()
		o.state = AppState(wParam)
		o.frame = 0
		if o.state == StateRecording {
			o.startTime = time.Now()
			// Reset waveform ring buffer
			for i := range o.levels {
				o.levels[i] = 0
			}
			o.levelIdx = 0
		}
		o.visible = true
		o.mu.Unlock()
		// Force topmost Z-order so overlay appears above all windows including WebView2
		const _HWND_TOPMOST = ^uintptr(0) // (HWND)-1
		const _SWP_NOMOVE = 0x0002
		const _SWP_NOSIZE = 0x0001
		const _SWP_NOACTIVATE = 0x0010
		const _SWP_SHOWWINDOW = 0x0040
		procSetWindowPos.Call(hwnd, _HWND_TOPMOST, 0, 0, 0, 0,
			_SWP_NOMOVE|_SWP_NOSIZE|_SWP_NOACTIVATE|_SWP_SHOWWINDOW)
		procSetTimer.Call(hwnd, _TIMER_ID, _TIMER_MS, 0)
		procInvalidateRect.Call(hwnd, 0, 1)
		return 0

	case _WM_OVL_HIDE:
		o.mu.Lock()
		o.visible = false
		o.mu.Unlock()
		procKillTimer.Call(hwnd, _TIMER_ID)
		procShowWindow.Call(hwnd, _SW_HIDE)
		return 0

	case _WM_OVL_LEVEL:
		o.mu.Lock()
		lvl := math.Float32frombits(uint32(wParam))
		o.level = lvl
		o.levels[o.levelIdx] = lvl
		o.levelIdx = (o.levelIdx + 1) % len(o.levels)
		o.mu.Unlock()
		return 0

	case _WM_DESTROY:
		procKillTimer.Call(hwnd, _TIMER_ID)
		if o.font != 0 {
			procDeleteObject.Call(o.font)
			o.font = 0
		}
		procPostQuitMessage.Call(0)
		return 0
	}

	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret
}

// NewOverlay creates the overlay window on a dedicated OS thread.
func NewOverlay() (*Overlay, error) {
	o := &Overlay{
		ready: make(chan error, 1),
		done:  make(chan struct{}),
	}
	globalOverlay = o

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		if err := o.initWindow(); err != nil {
			o.ready <- err
			return
		}
		o.ready <- nil

		var msg msgT
		for {
			ret, _, _ := procGetMessageW.Call(
				uintptr(unsafe.Pointer(&msg)), 0, 0, 0,
			)
			if ret == 0 || ret == ^uintptr(0) { // 0 = WM_QUIT, -1 = error
				break
			}
			procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
		}
		close(o.done)
	}()

	if err := <-o.ready; err != nil {
		return nil, err
	}
	return o, nil
}

func (o *Overlay) initWindow() error {
	hInst, _, _ := procGetModuleHandleW.Call(0)

	className, _ := windows.UTF16PtrFromString("WhispasteOverlay")

	var wc wndClassExW
	wc.CbSize = uint32(unsafe.Sizeof(wc))
	wc.Style = _CS_HREDRAW | _CS_VREDRAW
	wc.LpfnWndProc = overlayWndProcCB
	wc.HInstance = hInst
	wc.HCursor, _, _ = procLoadCursorW.Call(0, _IDC_ARROW)
	wc.LpszClassName = className

	atom, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
	if atom == 0 {
		return fmt.Errorf("RegisterClassExW failed")
	}

	screenW, _, _ := procGetSystemMetrics.Call(_SM_CXSCREEN)
	x := (int(screenW) - _OVL_WIDTH) / 2
	y := _OVL_MARGIN

	exStyle := uintptr(_WS_EX_TOPMOST | _WS_EX_LAYERED | _WS_EX_TRANSPARENT | _WS_EX_TOOLWINDOW)
	style := uintptr(_WS_POPUP)

	hwnd, _, _ := procCreateWindowExW.Call(
		exStyle,
		uintptr(unsafe.Pointer(className)),
		0, // no title
		style,
		uintptr(x), uintptr(y),
		_OVL_WIDTH, _OVL_HEIGHT,
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowExW failed")
	}
	o.hwnd = hwnd

	// 80 % opaque + magenta color-key for rounded-corner transparency
	procSetLayeredWindowAttributes.Call(
		hwnd, _CLR_COLORKEY, 204, _LWA_COLORKEY|_LWA_ALPHA,
	)

	// Create "Segoe UI" font
	fontName, _ := windows.UTF16PtrFromString("Segoe UI")
	fontHeight := int32(-16)
	o.font, _, _ = procCreateFontW.Call(
		uintptr(fontHeight), 0, 0, 0, // font height -16 = 12pt
		_FW_SEMIBOLD,
		0, 0, 0,
		_DEFAULT_CHARSET,
		0, 0,
		_CLEARTYPE_QUALITY,
		0,
		uintptr(unsafe.Pointer(fontName)),
	)
	return nil
}

// Show displays the overlay for the given state.
func (o *Overlay) Show(state AppState) {
	if o.hwnd != 0 {
		procPostMessageW.Call(o.hwnd, _WM_OVL_SHOW, uintptr(state), 0)
	}
}

// Hide hides the overlay window.
func (o *Overlay) Hide() {
	if o.hwnd != 0 {
		procPostMessageW.Call(o.hwnd, _WM_OVL_HIDE, 0, 0)
	}
}

// UpdateLevel updates the audio level for waveform display.
func (o *Overlay) UpdateLevel(level float32) {
	if o.hwnd != 0 {
		bits := math.Float32bits(level)
		procPostMessageW.Call(o.hwnd, _WM_OVL_LEVEL, uintptr(bits), 0)
	}
}

// Close destroys the overlay window and waits for cleanup.
func (o *Overlay) Close() {
	if o.hwnd != 0 {
		procPostMessageW.Call(o.hwnd, uintptr(_WM_CLOSE), 0, 0)
		<-o.done
	}
}

// ───────────────────── Drawing ─────────────────────

func (o *Overlay) paint(hwnd uintptr) {
	var ps paintStructT
	hdc, _, _ := procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
	if hdc == 0 {
		return
	}
	defer procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))

	// Fill window with color-key (corners become transparent)
	ckBrush, _, _ := procCreateSolidBrush.Call(_CLR_COLORKEY)
	rc := rectT{0, 0, _OVL_WIDTH, _OVL_HEIGHT}
	procFillRect.Call(hdc, uintptr(unsafe.Pointer(&rc)), ckBrush)
	procDeleteObject.Call(ckBrush)

	// Draw rounded rectangle background
	bgBrush, _, _ := procCreateSolidBrush.Call(_CLR_BACKGROUND)
	borderPen, _, _ := procCreatePen.Call(_PS_SOLID, 1, _CLR_BORDER)
	oldBrush, _, _ := procSelectObject.Call(hdc, bgBrush)
	oldPen, _, _ := procSelectObject.Call(hdc, borderPen)
	procRoundRect.Call(hdc, 0, 0, _OVL_WIDTH, _OVL_HEIGHT, 15, 15)
	procSelectObject.Call(hdc, oldBrush)
	procSelectObject.Call(hdc, oldPen)
	procDeleteObject.Call(bgBrush)
	procDeleteObject.Call(borderPen)

	procSetBkMode.Call(hdc, _TRANSPARENT)
	procSetTextColor.Call(hdc, _CLR_TEXT)
	if o.font != 0 {
		procSelectObject.Call(hdc, o.font)
	}

	o.mu.Lock()
	state := o.state
	frame := o.frame
	level := o.level
	startTime := o.startTime
	var levels [30]float32
	copy(levels[:], o.levels[:])
	levelIdx := o.levelIdx
	o.mu.Unlock()

	switch state {
	case StateRecording:
		o.paintRecording(hdc, frame, level, startTime, levels, levelIdx)
	case StateTranscribing:
		o.paintTranscribing(hdc, frame)
	case StateError:
		o.paintError(hdc)
	}
}

func (o *Overlay) paintRecording(hdc uintptr, frame int, level float32, start time.Time, levels [30]float32, levelIdx int) {
	// ── Pulsing red dot ──
	pulse := 7 + int32(math.Sin(float64(frame)*0.15)*2)
	cx, cy := int32(22), int32(30)

	dotBrush, _, _ := procCreateSolidBrush.Call(_CLR_RED_DOT)
	nullPen, _, _ := procGetStockObject.Call(_NULL_PEN)
	procSelectObject.Call(hdc, dotBrush)
	procSelectObject.Call(hdc, nullPen)
	procEllipse.Call(hdc,
		uintptr(cx-pulse), uintptr(cy-pulse),
		uintptr(cx+pulse), uintptr(cy+pulse),
	)
	procDeleteObject.Call(dotBrush)

	// ── "Recording" text ──
	drawText(hdc, T("overlay.recording"), 38, 12)

	// ── Elapsed timer ──
	elapsed := time.Since(start).Seconds()
	secs := int(elapsed)
	timer := fmt.Sprintf("%d:%02d", secs/60, secs%60)
	drawText(hdc, timer, 150, 12)

	// ── Scrolling waveform bars (newest on right) ──
	barBrush, _, _ := procCreateSolidBrush.Call(_CLR_BAR)
	procSelectObject.Call(hdc, barBrush)
	procSelectObject.Call(hdc, nullPen)
	numBars := len(levels)
	barW := int32(3)
	gap := int32(2)
	waveX := int32(200)
	for i := 0; i < numBars; i++ {
		idx := (levelIdx + i) % numBars
		lvl := levels[idx]
		// Amplify: speech RMS is typically 0.01-0.15
		amp := lvl * 6.0
		if amp > 1.0 {
			amp = 1.0
		}
		h := int32(amp * 32.0)
		if h < 2 {
			h = 2
		}
		x := waveX + int32(i)*(barW+gap)
		y1 := int32(30) - h/2
		y2 := int32(30) + h/2
		procRectangle.Call(hdc, uintptr(x), uintptr(y1), uintptr(x+barW), uintptr(y2))
	}
	procDeleteObject.Call(barBrush)
}

func (o *Overlay) paintTranscribing(hdc uintptr, frame int) {
	dots := ""
	n := (frame / 10) % 4
	for i := 0; i < n; i++ {
		dots += "."
	}
	text := T("overlay.transcribing")
	// Strip trailing dots from localized string and add animated ones
	for len(text) > 0 && text[len(text)-1] == '.' {
		text = text[:len(text)-1]
	}
	text += dots

	rc := rectT{0, 0, _OVL_WIDTH, _OVL_HEIGHT}
	utf16, _ := windows.UTF16FromString(text)
	procDrawTextW.Call(hdc,
		uintptr(unsafe.Pointer(&utf16[0])),
		uintptr(len(utf16)-1),
		uintptr(unsafe.Pointer(&rc)),
		_DT_CENTER|_DT_VCENTER|_DT_SINGLELINE,
	)
}

func (o *Overlay) paintError(hdc uintptr) {
	rc := rectT{0, 0, _OVL_WIDTH, _OVL_HEIGHT}
	text := T("error.no_api_key")
	utf16, _ := windows.UTF16FromString(text)
	procSetTextColor.Call(hdc, _CLR_RED_DOT)
	procDrawTextW.Call(hdc,
		uintptr(unsafe.Pointer(&utf16[0])),
		uintptr(len(utf16)-1),
		uintptr(unsafe.Pointer(&rc)),
		_DT_CENTER|_DT_VCENTER|_DT_SINGLELINE,
	)
}

func drawText(hdc uintptr, text string, x, y int32) {
	utf16, _ := windows.UTF16FromString(text)
	rc := rectT{x, y, x + 120, y + 36}
	procDrawTextW.Call(hdc,
		uintptr(unsafe.Pointer(&utf16[0])),
		uintptr(len(utf16)-1),
		uintptr(unsafe.Pointer(&rc)),
		0, // left-aligned
	)
}
