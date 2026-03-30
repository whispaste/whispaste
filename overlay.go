//go:build windows

package main

import (
	"fmt"
	"math"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ───────────────────── Win32 constants ─────────────────────

const (
	_WS_POPUP   = 0x80000000
	_WS_VISIBLE = 0x10000000

	_WS_EX_TOPMOST    = 0x00000008
	_WS_EX_LAYERED    = 0x00080000
	_WS_EX_TOOLWINDOW = 0x00000080
	_WS_EX_NOACTIVATE = 0x08000000

	_CS_HREDRAW = 0x0002
	_CS_VREDRAW = 0x0001

	_WM_CREATE     = 0x0001
	_WM_DESTROY    = 0x0002
	_WM_PAINT      = 0x000F
	_WM_CLOSE      = 0x0010
	_WM_ERASEBKGND = 0x0014
	_WM_NCHITTEST  = 0x0084
	_WM_TIMER      = 0x0113
	_WM_USER       = 0x0400

	_WM_OVL_SHOW  = _WM_USER + 1
	_WM_OVL_HIDE  = _WM_USER + 2
	_WM_OVL_LEVEL = _WM_USER + 3
	_WM_OVL_PAUSE = _WM_USER + 4

	_SW_HIDE   = 0
	_SW_SHOWNA = 8

	_SM_CXSCREEN        = 0
	_SM_CYSCREEN        = 1
	_SM_XVIRTUALSCREEN  = 76
	_SM_YVIRTUALSCREEN  = 77
	_SM_CXVIRTUALSCREEN = 78
	_SM_CYVIRTUALSCREEN = 79

	_LWA_COLORKEY = 0x00000001
	_LWA_ALPHA    = 0x00000002

	_IDC_ARROW = 32512
	_HTCAPTION = 2

	_TRANSPARENT       = 1
	_PS_SOLID          = 0
	_NULL_PEN          = 8
	_NULL_BRUSH        = 5
	_FW_NORMAL         = 400
	_FW_SEMIBOLD       = 600
	_FW_BOLD           = 700
	_DEFAULT_CHARSET   = 1
	_CLEARTYPE_QUALITY = 5
	_DT_CENTER         = 0x0001
	_DT_VCENTER        = 0x0004
	_DT_SINGLELINE     = 0x0020
	_DT_LEFT           = 0x0000

	_TIMER_ID = 1
	_TIMER_MS = 16 // ~60 FPS for smoother animations

	// Pill-shaped overlay dimensions
	_OVL_WIDTH  = 490
	_OVL_HEIGHT = 80
	_OVL_MARGIN = 24
	_OVL_RADIUS = 40 // fully rounded pill ends

	// Colors (COLORREF = 0x00BBGGRR) – derived from app logo palette
	_CLR_BACKGROUND = 0x00291A0A // RGB(10,26,41) – dark navy
	_CLR_TEXT       = 0x00FFFFFF // white
	_CLR_TEXT_DIM   = 0x00B0A090 // RGB(144,160,176) – dimmed text
	_CLR_RED_DOT    = 0x003C3CFF // RGB(255,60,60)
	_CLR_BAR        = 0x00EED322 // RGB(34,211,238) – cyan
	_CLR_BAR_DIM    = 0x00886618 // RGB(24,102,136) – dimmed cyan

	// Waveform layout
	_WAVE_BARS  = 20
	_WAVE_BAR_W = 4
	_WAVE_GAP   = 3
	_WAVE_AMP   = 1.5 // post-sqrt scale factor for waveform bars

	// Control button layout: [Dashboard] [Cancel] [Timer] [Waveform] [Pause] [Stop]
	_BTN_SIZE      = 40
	_BTN_GAP       = 8
	_BTN_Y         = (_OVL_HEIGHT - _BTN_SIZE) / 2
	_BTN_DASH_X    = 14                                    // left edge (dashboard)
	_BTN_CANCEL_X  = _BTN_DASH_X + _BTN_SIZE + _BTN_GAP    // right of dashboard
	_BTN_CONFIRM_X = _OVL_WIDTH - _BTN_SIZE - 14           // right edge (stop/confirm)
	_BTN_PAUSE_X   = _BTN_CONFIRM_X - _BTN_SIZE - _BTN_GAP // left of confirm

	// Topmost re-assert interval (every N frames at ~60fps ≈ 1 second)
	_TOPMOST_INTERVAL = 60
)

// GDI+ constants and types
const (
	_SmoothingModeAntiAlias              = 4
	_TextRenderingHintClearType          = 5
	_TextRenderingHintAntiAliasGridFit   = 3
	_InterpolationModeHighQualityBicubic = 7
	_UnitPixel                           = 2
	_FontStyleRegular                    = 0
	_FontStyleBold                       = 1
)

type gdiplusStartupInput struct {
	GdiplusVersion           uint32
	DebugEventCallback       uintptr
	SuppressBackgroundThread int32
	SuppressExternalCodecs   int32
}

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

type bitmapInfoHeader struct {
	BiSize          uint32
	BiWidth         int32
	BiHeight        int32
	BiPlanes        uint16
	BiBitCount      uint16
	BiCompression   uint32
	BiSizeImage     uint32
	BiXPelsPerMeter int32
	BiYPelsPerMeter int32
	BiClrUsed       uint32
	BiClrImportant  uint32
}

type blendFunction struct {
	BlendOp             byte
	BlendFlags          byte
	SourceConstantAlpha byte
	AlphaFormat         byte
}

type sizeT struct{ CX, CY int32 }

type gdipRectF struct {
	X, Y, Width, Height float32
}

// ───────────────────── Win32 procs ─────────────────────

var (
	ovlUser32   = windows.NewLazySystemDLL("user32.dll")
	ovlGdi32    = windows.NewLazySystemDLL("gdi32.dll")
	ovlKernel32 = windows.NewLazySystemDLL("kernel32.dll")
	ovlGdiplus  = windows.NewLazySystemDLL("gdiplus.dll")

	procRegisterClassExW           = ovlUser32.NewProc("RegisterClassExW")
	procCreateWindowExW            = ovlUser32.NewProc("CreateWindowExW")
	procShowWindow                 = ovlUser32.NewProc("ShowWindow")
	procSetTimer                   = ovlUser32.NewProc("SetTimer")
	procKillTimer                  = ovlUser32.NewProc("KillTimer")
	procGetMessageW                = ovlUser32.NewProc("GetMessageW")
	procTranslateMessage           = ovlUser32.NewProc("TranslateMessage")
	procDispatchMessageW           = ovlUser32.NewProc("DispatchMessageW")
	procDefWindowProcW             = ovlUser32.NewProc("DefWindowProcW")
	procBeginPaint                 = ovlUser32.NewProc("BeginPaint")
	procEndPaint                   = ovlUser32.NewProc("EndPaint")
	procInvalidateRect             = ovlUser32.NewProc("InvalidateRect")
	procGetSystemMetrics           = ovlUser32.NewProc("GetSystemMetrics")
	procSystemParametersInfoW      = ovlUser32.NewProc("SystemParametersInfoW")
	procPostMessageW               = ovlUser32.NewProc("PostMessageW")
	procSetWindowPos               = ovlUser32.NewProc("SetWindowPos")
	procSetLayeredWindowAttributes = ovlUser32.NewProc("SetLayeredWindowAttributes")
	procLoadCursorW                = ovlUser32.NewProc("LoadCursorW")
	procPostQuitMessage            = ovlUser32.NewProc("PostQuitMessage")
	procFillRect                   = ovlUser32.NewProc("FillRect")
	procDrawTextW                  = ovlUser32.NewProc("DrawTextW")
	procCreateIconFromResourceEx   = ovlUser32.NewProc("CreateIconFromResourceEx")
	procDrawIconEx                 = ovlUser32.NewProc("DrawIconEx")
	procDestroyIcon                = ovlUser32.NewProc("DestroyIcon")
	procGetCursorPos               = ovlUser32.NewProc("GetCursorPos")
	procScreenToClient             = ovlUser32.NewProc("ScreenToClient")
	procTrackMouseEvent            = ovlUser32.NewProc("TrackMouseEvent")

	procCreateSolidBrush       = ovlGdi32.NewProc("CreateSolidBrush")
	procCreatePen              = ovlGdi32.NewProc("CreatePen")
	procCreateFontW            = ovlGdi32.NewProc("CreateFontW")
	procDeleteObject           = ovlGdi32.NewProc("DeleteObject")
	procSelectObject           = ovlGdi32.NewProc("SelectObject")
	procSetBkMode              = ovlGdi32.NewProc("SetBkMode")
	procSetTextColor           = ovlGdi32.NewProc("SetTextColor")
	procRoundRect              = ovlGdi32.NewProc("RoundRect")
	procRectangle              = ovlGdi32.NewProc("Rectangle")
	procEllipse                = ovlGdi32.NewProc("Ellipse")
	procGetStockObject         = ovlGdi32.NewProc("GetStockObject")
	procCreateCompatibleDC     = ovlGdi32.NewProc("CreateCompatibleDC")
	procCreateCompatibleBitmap = ovlGdi32.NewProc("CreateCompatibleBitmap")
	procBitBlt                 = ovlGdi32.NewProc("BitBlt")
	procDeleteDC               = ovlGdi32.NewProc("DeleteDC")
	procSetStretchBltMode      = ovlGdi32.NewProc("SetStretchBltMode")

	procGetModuleHandleW = ovlKernel32.NewProc("GetModuleHandleW")

	// GDI+ procs for anti-aliased rendering
	procGdiplusStartup       = ovlGdiplus.NewProc("GdiplusStartup")
	procGdiplusShutdown      = ovlGdiplus.NewProc("GdiplusShutdown")
	procGdipCreateFromHDC    = ovlGdiplus.NewProc("GdipCreateFromHDC")
	procGdipDeleteGraphics   = ovlGdiplus.NewProc("GdipDeleteGraphics")
	procGdipSetSmoothingMode = ovlGdiplus.NewProc("GdipSetSmoothingMode")
	procGdipCreateSolidFill  = ovlGdiplus.NewProc("GdipCreateSolidFill")
	procGdipDeleteBrush      = ovlGdiplus.NewProc("GdipDeleteBrush")
	procGdipFillEllipseI     = ovlGdiplus.NewProc("GdipFillEllipseI")
	procGdipDrawEllipseI     = ovlGdiplus.NewProc("GdipDrawEllipseI")
	procGdipFillRectangleI   = ovlGdiplus.NewProc("GdipFillRectangleI")

	// ULW and DIB
	procUpdateLayeredWindow = ovlUser32.NewProc("UpdateLayeredWindow")
	procCreateDIBSection    = ovlGdi32.NewProc("CreateDIBSection")
	procGetDC               = ovlUser32.NewProc("GetDC")
	procReleaseDC           = ovlUser32.NewProc("ReleaseDC")

	// GDI+ path
	procGdipCreatePath      = ovlGdiplus.NewProc("GdipCreatePath")
	procGdipDeletePath      = ovlGdiplus.NewProc("GdipDeletePath")
	procGdipAddPathArc      = ovlGdiplus.NewProc("GdipAddPathArc")
	procGdipAddPathLine     = ovlGdiplus.NewProc("GdipAddPathLineI")
	procGdipClosePathFigure = ovlGdiplus.NewProc("GdipClosePathFigure")
	procGdipFillPath        = ovlGdiplus.NewProc("GdipFillPath")

	// GDI+ text
	procGdipCreateFontFamilyFromName = ovlGdiplus.NewProc("GdipCreateFontFamilyFromName")
	procGdipDeleteFontFamily         = ovlGdiplus.NewProc("GdipDeleteFontFamily")
	procGdipCreateFont               = ovlGdiplus.NewProc("GdipCreateFont")
	procGdipDeleteFont               = ovlGdiplus.NewProc("GdipDeleteFont")
	procGdipCreateStringFormat       = ovlGdiplus.NewProc("GdipCreateStringFormat")
	procGdipDeleteStringFormat       = ovlGdiplus.NewProc("GdipDeleteStringFormat")
	procGdipDrawString               = ovlGdiplus.NewProc("GdipDrawString")
	procGdipMeasureString            = ovlGdiplus.NewProc("GdipMeasureString")
	procGdipSetTextRenderingHint     = ovlGdiplus.NewProc("GdipSetTextRenderingHint")

	// GDI+ icon
	procGdipCreateBitmapFromHICON = ovlGdiplus.NewProc("GdipCreateBitmapFromHICON")
	procGdipDrawImageRectI        = ovlGdiplus.NewProc("GdipDrawImageRectI")
	procGdipDisposeImage          = ovlGdiplus.NewProc("GdipDisposeImage")
	procGdipSetInterpolationMode  = ovlGdiplus.NewProc("GdipSetInterpolationMode")

	// GDI+ pen
	procGdipCreatePen1          = ovlGdiplus.NewProc("GdipCreatePen1")
	procGdipDeletePen           = ovlGdiplus.NewProc("GdipDeletePen")
	procGdipDrawPath            = ovlGdiplus.NewProc("GdipDrawPath")
	procGdipDrawLineI           = ovlGdiplus.NewProc("GdipDrawLineI")
	procGdipSetPenLineCap197819 = ovlGdiplus.NewProc("GdipSetPenLineCap197819")
	procGdipSetPenLineJoin      = ovlGdiplus.NewProc("GdipSetPenLineJoin")

	// GDI+ graphics
	procGdipGraphicsClear = ovlGdiplus.NewProc("GdipGraphicsClear")

	// GDI+ gradient
	procGdipCreateLineBrushFromRectI = ovlGdiplus.NewProc("GdipCreateLineBrushFromRectI")
)

// ───────────────────── GDI+ helpers ─────────────────────

var gdiplusToken uintptr

func initGDIPlus() {
	input := gdiplusStartupInput{GdiplusVersion: 1}
	procGdiplusStartup.Call(
		uintptr(unsafe.Pointer(&gdiplusToken)),
		uintptr(unsafe.Pointer(&input)),
		0,
	)
}

func shutdownGDIPlus() {
	if gdiplusToken != 0 {
		procGdiplusShutdown.Call(gdiplusToken)
	}
}

// ───────────────────── Overlay ─────────────────────

var globalOverlay *Overlay

// Overlay displays a premium recording/transcribing indicator.
type Overlay struct {
	hwnd      uintptr
	fontMain  uintptr // GDI font (keep for measurement fallback)
	fontSmall uintptr // GDI font
	hIcon     uintptr
	// GDI+ fonts for anti-aliased text
	gdipFontFamily uintptr
	gdipFontMain   uintptr
	gdipFontSmall  uintptr
	gdipStrFmt     uintptr
	gdipIconBmp    uintptr // GDI+ bitmap from hIcon
	// DIB section for ULW
	dibDC           uintptr
	dibBmp          uintptr
	state           AppState
	level           float32
	levels          [_WAVE_BARS]float32
	levelIdx        int
	startTime       time.Time
	frame           int
	visible         bool
	position        string // "top_center" or "cursor"
	ready           chan error
	done            chan struct{}
	onConfirm       func()        // called when confirm/stop button clicked
	onCancel        func()        // called when cancel button clicked
	onPause         func()        // called when pause/resume button clicked
	onDash          func()        // called when dashboard button clicked
	paused          bool          // whether recording is paused
	pauseStart      time.Time     // when current pause began
	pauseAccum      time.Duration // accumulated pause time
	maxRecordSec    int           // max recording duration in seconds (0 = unlimited)
	transcribeStart time.Time     // when transcription began
	estimatedSec    float64       // estimated transcription duration in seconds
	hoverBtn        int           // 0=none, 1=dash, 2=cancel, 3=pause, 4=stop
	pressBtn        int           // 0=none, same mapping
	tracking        bool          // whether TrackMouseEvent is active
	scale           float64       // DPI scale factor (1.0 = 96 DPI)
	isSmartMode     bool          // whether Smart Mode post-processing is active
	mu              sync.Mutex
}

// dpiScale returns the DPI scale factor for the overlay window.
func (o *Overlay) dpiScale() float64 {
	if o.hwnd == 0 {
		return 1.0
	}
	dpi, _, _ := procGetDpiForWindow.Call(o.hwnd)
	if dpi == 0 {
		return 1.0
	}
	return float64(dpi) / 96.0
}

// sc scales a logical pixel value by the DPI scale factor.
func (o *Overlay) sc(v int) int32 {
	return int32(math.Round(float64(v) * o.scale))
}

// overlayPosition calculates screen position based on config.
// Uses virtual screen coordinates for correct multi-monitor support.
func (o *Overlay) overlayPosition(pos string) (int, int) {
	w := int(o.sc(_OVL_WIDTH))
	h := int(o.sc(_OVL_HEIGHT))
	m := int(o.sc(_OVL_MARGIN))
	if pos == "cursor" {
		var pt pointT
		procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
		// Use virtual screen bounds for multi-monitor support
		vsX, _, _ := procGetSystemMetrics.Call(_SM_XVIRTUALSCREEN)
		vsY, _, _ := procGetSystemMetrics.Call(_SM_YVIRTUALSCREEN)
		vsW, _, _ := procGetSystemMetrics.Call(_SM_CXVIRTUALSCREEN)
		vsH, _, _ := procGetSystemMetrics.Call(_SM_CYVIRTUALSCREEN)
		minX := int(vsX)
		minY := int(vsY)
		maxX := minX + int(vsW)
		maxY := minY + int(vsH)
		x := int(pt.X) - w/2
		y := int(pt.Y) - h - int(o.sc(16))
		if x < minX+8 {
			x = minX + 8
		}
		if x+w > maxX-8 {
			x = maxX - w - 8
		}
		if y < minY+8 {
			y = int(pt.Y) + int(o.sc(24)) // below cursor if no room above
		}
		if y+h > maxY-8 {
			y = maxY - h - 8
		}
		return x, y
	}
	if pos == "bottom" {
		// Bottom center, above the taskbar
		var rc rectT
		procSystemParametersInfoW.Call(0x0030, 0, uintptr(unsafe.Pointer(&rc)), 0) // SPI_GETWORKAREA
		workW := int(rc.Right - rc.Left)
		workH := int(rc.Bottom - rc.Top)
		x := int(rc.Left) + (workW-w)/2
		y := int(rc.Top) + workH - h - m
		return x, y
	}
	// Default: top center of primary monitor
	screenW, _, _ := procGetSystemMetrics.Call(_SM_CXSCREEN)
	return (int(screenW) - w) / 2, m
}

// NewOverlay creates the overlay window on a dedicated OS thread.
func NewOverlay() (*Overlay, error) {
	o := &Overlay{
		ready:    make(chan error, 1),
		done:     make(chan struct{}),
		position: "top_center",
		scale:    1.0,
	}
	globalOverlay = o

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		initGDIPlus()

		if err := o.initWindow(); err != nil {
			shutdownGDIPlus()
			o.ready <- err
			return
		}
		o.ready <- nil

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

	// WS_EX_NOACTIVATE: window won't steal focus when clicked/dragged
	exStyle := uintptr(_WS_EX_TOPMOST | _WS_EX_LAYERED | _WS_EX_TOOLWINDOW | _WS_EX_NOACTIVATE)

	hwnd, _, _ := procCreateWindowExW.Call(
		exStyle,
		uintptr(unsafe.Pointer(className)),
		0,
		uintptr(_WS_POPUP),
		uintptr(x), _OVL_MARGIN, _OVL_WIDTH, _OVL_HEIGHT,
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowExW failed")
	}
	o.hwnd = hwnd

	// Compute DPI scale factor for this window's monitor
	o.scale = o.dpiScale()
	if o.scale < 1.0 {
		o.scale = 1.0
	}

	// Main font: 13pt Segoe UI Semibold
	fontHeightMain := int32(-17)
	fontHeightSmall := int32(-13)
	fontName, _ := windows.UTF16PtrFromString("Segoe UI")
	o.fontMain, _, _ = procCreateFontW.Call(
		uintptr(fontHeightMain), 0, 0, 0, _FW_SEMIBOLD,
		0, 0, 0, _DEFAULT_CHARSET, 0, 0, _CLEARTYPE_QUALITY, 0,
		uintptr(unsafe.Pointer(fontName)),
	)

	// Small font: 10pt Segoe UI for timer
	o.fontSmall, _, _ = procCreateFontW.Call(
		uintptr(fontHeightSmall), 0, 0, 0, _FW_NORMAL,
		0, 0, 0, _DEFAULT_CHARSET, 0, 0, _CLEARTYPE_QUALITY, 0,
		uintptr(unsafe.Pointer(fontName)),
	)

	// Create GDI+ font resources for anti-aliased text
	fontName16, _ := windows.UTF16PtrFromString("Segoe UI")
	procGdipCreateFontFamilyFromName.Call(
		uintptr(unsafe.Pointer(fontName16)), 0, uintptr(unsafe.Pointer(&o.gdipFontFamily)))
	if o.gdipFontFamily != 0 {
		procGdipCreateFont.Call(o.gdipFontFamily,
			uintptr(math.Float32bits(15.0)), _FontStyleBold, _UnitPixel,
			uintptr(unsafe.Pointer(&o.gdipFontMain)))
		procGdipCreateFont.Call(o.gdipFontFamily,
			uintptr(math.Float32bits(11.0)), _FontStyleRegular, _UnitPixel,
			uintptr(unsafe.Pointer(&o.gdipFontSmall)))
	}
	procGdipCreateStringFormat.Call(0, 0, uintptr(unsafe.Pointer(&o.gdipStrFmt)))

	// Create persistent DIB section for ULW rendering
	o.createDIB()

	return nil
}

func (o *Overlay) loadIcon(targetSize int32) {
	if len(embeddedAppIcon) < 22 {
		return
	}
	count := int(embeddedAppIcon[4]) | int(embeddedAppIcon[5])<<8
	bestIdx, bestDiff := -1, int32(256)
	for i := 0; i < count; i++ {
		off := 6 + i*16
		if off+16 > len(embeddedAppIcon) {
			break
		}
		w := int32(embeddedAppIcon[off])
		if w == 0 {
			w = 256
		}
		d := w - targetSize
		if d < 0 {
			d = -d
		}
		if bestIdx < 0 || d < bestDiff {
			bestIdx, bestDiff = i, d
		}
	}
	if bestIdx < 0 {
		return
	}
	off := 6 + bestIdx*16
	dataSize := uint32(embeddedAppIcon[off+8]) | uint32(embeddedAppIcon[off+9])<<8 |
		uint32(embeddedAppIcon[off+10])<<16 | uint32(embeddedAppIcon[off+11])<<24
	dataOffset := uint32(embeddedAppIcon[off+12]) | uint32(embeddedAppIcon[off+13])<<8 |
		uint32(embeddedAppIcon[off+14])<<16 | uint32(embeddedAppIcon[off+15])<<24
	if dataOffset+dataSize <= uint32(len(embeddedAppIcon)) {
		iconData := embeddedAppIcon[dataOffset : dataOffset+dataSize]
		o.hIcon, _, _ = procCreateIconFromResourceEx.Call(
			uintptr(unsafe.Pointer(&iconData[0])),
			uintptr(dataSize),
			1, 0x00030000, uintptr(targetSize), uintptr(targetSize), 0,
		)
	}
}

// SetCallbacks sets the confirm, cancel, and pause button callbacks.
func (o *Overlay) SetCallbacks(onConfirm, onCancel, onPause, onDash func()) {
	o.mu.Lock()
	o.onConfirm = onConfirm
	o.onCancel = onCancel
	o.onPause = onPause
	o.onDash = onDash
	o.mu.Unlock()
}

// SetPaused updates the paused display state via window message.
func (o *Overlay) SetPaused(paused bool) {
	if o.hwnd != 0 {
		v := uintptr(0)
		if paused {
			v = 1
		}
		procPostMessageW.Call(o.hwnd, _WM_OVL_PAUSE, v, 0)
	}
}

// SetPosition updates the overlay position preference.
func (o *Overlay) SetPosition(pos string) {
	o.mu.Lock()
	o.position = pos
	o.mu.Unlock()
}

// SetMaxRecordSec sets the maximum recording duration for timer color warnings.
func (o *Overlay) SetMaxRecordSec(sec int) {
	o.mu.Lock()
	o.maxRecordSec = sec
	o.mu.Unlock()
}

// SetSmartMode sets whether the current processing uses Smart Mode.
func (o *Overlay) SetSmartMode(enabled bool) {
	o.mu.Lock()
	o.isSmartMode = enabled
	o.mu.Unlock()
}

// Show displays the overlay for the given state.
func (o *Overlay) Show(state AppState) {
	if o.hwnd != 0 {
		procPostMessageW.Call(o.hwnd, _WM_OVL_SHOW, uintptr(state), 0)
	}
}

// SetTranscribeEstimate sets the estimated transcription duration based on
// audio length and transcription method. Call before Show(StateTranscribing).
// Uses pessimistic speed ratios: cloud ≈ 0.5× real-time, local ≈ 1.5× real-time.
func (o *Overlay) SetTranscribeEstimate(audioDurationSec float64, isLocal bool) {
	o.mu.Lock()
	defer o.mu.Unlock()
	ratio := 0.5 // cloud: typically fast
	if isLocal {
		ratio = 1.5 // local: pessimistic estimate
	}
	o.estimatedSec = audioDurationSec * ratio
	if o.estimatedSec < 3 {
		o.estimatedSec = 3 // minimum 3 seconds to avoid flicker
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
