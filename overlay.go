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
_WS_POPUP   = 0x80000000
_WS_VISIBLE = 0x10000000

_WS_EX_TOPMOST      = 0x00000008
_WS_EX_LAYERED      = 0x00080000
_WS_EX_TOOLWINDOW   = 0x00000080
_WS_EX_NOACTIVATE   = 0x08000000

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

_SM_CXSCREEN         = 0
_SM_CYSCREEN         = 1
_SM_XVIRTUALSCREEN   = 76
_SM_YVIRTUALSCREEN   = 77
_SM_CXVIRTUALSCREEN  = 78
_SM_CYVIRTUALSCREEN  = 79

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
_OVL_HEIGHT = 64
_OVL_MARGIN = 24
_OVL_RADIUS = 32 // fully rounded pill ends

// Icon display size (48x48 from ICO for crisp rendering)
_ICON_SIZE    = 36
_ICON_PADDING = 14

// Colors (COLORREF = 0x00BBGGRR) – derived from app logo palette
_CLR_BACKGROUND = 0x00291A0A // RGB(10,26,41) – dark navy
_CLR_BORDER     = 0x00B86600 // RGB(0,102,184) – deep blue
_CLR_TEXT       = 0x00FFFFFF // white
_CLR_TEXT_DIM   = 0x00B0A090 // RGB(144,160,176) – dimmed text
_CLR_RED_DOT    = 0x003C3CFF // RGB(255,60,60)
_CLR_BAR        = 0x00EED322 // RGB(34,211,238) – cyan
_CLR_BAR_DIM    = 0x00886618 // RGB(24,102,136) – dimmed cyan
_CLR_GREEN      = 0x0059C734 // RGB(52,199,89)

// Waveform layout
_WAVE_BARS   = 20  // fewer, wider bars for cleaner look
_WAVE_BAR_W  = 4
_WAVE_GAP    = 3
_WAVE_RIGHT  = 12 // right margin
_WAVE_AMP    = 30.0

// Control button layout (right side of pill, after waveform)
_BTN_SIZE      = 28
_BTN_GAP       = 6
_BTN_Y         = (_OVL_HEIGHT - _BTN_SIZE) / 2
_BTN_CONFIRM_X = _OVL_WIDTH - _BTN_SIZE - 10
_BTN_PAUSE_X   = _BTN_CONFIRM_X - _BTN_SIZE - _BTN_GAP
)

// GDI+ constants and types
const (
_SmoothingModeAntiAlias                  = 4
_TextRenderingHintClearType              = 5
_TextRenderingHintAntiAliasGridFit       = 3
_InterpolationModeHighQualityBicubic     = 7
_UnitPixel                               = 2
_FontStyleRegular                        = 0
_FontStyleBold                           = 1
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

procCreateSolidBrush     = ovlGdi32.NewProc("CreateSolidBrush")
procCreatePen            = ovlGdi32.NewProc("CreatePen")
procCreateFontW          = ovlGdi32.NewProc("CreateFontW")
procDeleteObject         = ovlGdi32.NewProc("DeleteObject")
procSelectObject         = ovlGdi32.NewProc("SelectObject")
procSetBkMode            = ovlGdi32.NewProc("SetBkMode")
procSetTextColor         = ovlGdi32.NewProc("SetTextColor")
procRoundRect            = ovlGdi32.NewProc("RoundRect")
procRectangle            = ovlGdi32.NewProc("Rectangle")
procEllipse              = ovlGdi32.NewProc("Ellipse")
procGetStockObject       = ovlGdi32.NewProc("GetStockObject")
procCreateCompatibleDC   = ovlGdi32.NewProc("CreateCompatibleDC")
procCreateCompatibleBitmap = ovlGdi32.NewProc("CreateCompatibleBitmap")
procBitBlt               = ovlGdi32.NewProc("BitBlt")
procDeleteDC             = ovlGdi32.NewProc("DeleteDC")
procSetStretchBltMode    = ovlGdi32.NewProc("SetStretchBltMode")

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
procGdipFillRectangleI   = ovlGdiplus.NewProc("GdipFillRectangleI")

// ULW and DIB
procUpdateLayeredWindow = ovlUser32.NewProc("UpdateLayeredWindow")
procCreateDIBSection    = ovlGdi32.NewProc("CreateDIBSection")
procGetDC               = ovlUser32.NewProc("GetDC")
procReleaseDC           = ovlUser32.NewProc("ReleaseDC")

// GDI+ path
procGdipCreatePath          = ovlGdiplus.NewProc("GdipCreatePath")
procGdipDeletePath          = ovlGdiplus.NewProc("GdipDeletePath")
procGdipAddPathArc          = ovlGdiplus.NewProc("GdipAddPathArc")
procGdipClosePathFigure     = ovlGdiplus.NewProc("GdipClosePathFigure")
procGdipFillPath            = ovlGdiplus.NewProc("GdipFillPath")

// GDI+ text
procGdipCreateFontFamilyFromName = ovlGdiplus.NewProc("GdipCreateFontFamilyFromName")
procGdipDeleteFontFamily         = ovlGdiplus.NewProc("GdipDeleteFontFamily")
procGdipCreateFont               = ovlGdiplus.NewProc("GdipCreateFont")
procGdipDeleteFont               = ovlGdiplus.NewProc("GdipDeleteFont")
procGdipCreateStringFormat       = ovlGdiplus.NewProc("GdipCreateStringFormat")
procGdipDeleteStringFormat       = ovlGdiplus.NewProc("GdipDeleteStringFormat")
procGdipDrawString               = ovlGdiplus.NewProc("GdipDrawString")
procGdipSetTextRenderingHint     = ovlGdiplus.NewProc("GdipSetTextRenderingHint")

// GDI+ icon
procGdipCreateBitmapFromHICON = ovlGdiplus.NewProc("GdipCreateBitmapFromHICON")
procGdipDrawImageRectI         = ovlGdiplus.NewProc("GdipDrawImageRectI")
procGdipDisposeImage           = ovlGdiplus.NewProc("GdipDisposeImage")
procGdipSetInterpolationMode   = ovlGdiplus.NewProc("GdipSetInterpolationMode")

// GDI+ pen
procGdipCreatePen1 = ovlGdiplus.NewProc("GdipCreatePen1")
procGdipDeletePen  = ovlGdiplus.NewProc("GdipDeletePen")
procGdipDrawPath   = ovlGdiplus.NewProc("GdipDrawPath")

// GDI+ graphics
procGdipGraphicsClear = ovlGdiplus.NewProc("GdipGraphicsClear")
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

// gdipFillCircle draws an anti-aliased filled circle.
func gdipFillCircle(hdc uintptr, argb uint32, cx, cy, r int32) {
var g uintptr
procGdipCreateFromHDC.Call(hdc, uintptr(unsafe.Pointer(&g)))
if g == 0 {
return
}
defer procGdipDeleteGraphics.Call(g)
procGdipSetSmoothingMode.Call(g, _SmoothingModeAntiAlias)

var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)

procGdipFillEllipseI.Call(g, brush,
uintptr(cx-r), uintptr(cy-r), uintptr(2*r), uintptr(2*r))
}

// gdipFillRect draws an anti-aliased filled rectangle.
func gdipFillRect(hdc uintptr, argb uint32, x, y, w, h int32) {
var g uintptr
procGdipCreateFromHDC.Call(hdc, uintptr(unsafe.Pointer(&g)))
if g == 0 {
return
}
defer procGdipDeleteGraphics.Call(g)
procGdipSetSmoothingMode.Call(g, _SmoothingModeAntiAlias)

var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)

procGdipFillRectangleI.Call(g, brush, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
}

// gdipFillCircleG draws a circle using a pre-created GDI+ Graphics handle (avoids create/destroy churn).
func gdipFillCircleG(g uintptr, argb uint32, cx, cy, r int32) {
var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)
procGdipFillEllipseI.Call(g, brush,
uintptr(cx-r), uintptr(cy-r), uintptr(2*r), uintptr(2*r))
}

// gdipFillRectG draws a filled rectangle using a pre-created GDI+ Graphics handle.
func gdipFillRectG(g uintptr, argb uint32, x, y, w, h int32) {
var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)
procGdipFillRectangleI.Call(g, brush, uintptr(x), uintptr(y), uintptr(w), uintptr(h))
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
dibDC  uintptr
dibBmp uintptr
state     AppState
level     float32
levels    [_WAVE_BARS]float32
levelIdx  int
startTime time.Time
frame     int
visible   bool
position  string // "top_center" or "cursor"
ready     chan error
done      chan struct{}
onConfirm func() // called when confirm button clicked
onPause   func() // called when pause/resume button clicked
paused    bool   // whether recording is paused
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
// ULW windows don't use WM_PAINT - all rendering via UpdateLayeredWindow
var ps paintStructT
procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
return 0

case _WM_ERASEBKGND:
return 1

case _WM_NCHITTEST:
	o.mu.Lock()
	st := o.state
	o.mu.Unlock()
	if st == StateRecording || st == StatePaused {
		xScreen := int32(lParam & 0xFFFF)
		yScreen := int32((lParam >> 16) & 0xFFFF)
		var pt pointT
		pt.X = xScreen
		pt.Y = yScreen
		procScreenToClient.Call(hwnd, uintptr(unsafe.Pointer(&pt)))
		if pt.X >= _BTN_CONFIRM_X && pt.X <= _BTN_CONFIRM_X+_BTN_SIZE &&
			pt.Y >= _BTN_Y && pt.Y <= _BTN_Y+_BTN_SIZE {
			return 1 // HTCLIENT
		}
		if pt.X >= _BTN_PAUSE_X && pt.X <= _BTN_PAUSE_X+_BTN_SIZE &&
			pt.Y >= _BTN_Y && pt.Y <= _BTN_Y+_BTN_SIZE {
			return 1 // HTCLIENT
		}
	}
	return _HTCAPTION

case _WM_TIMER:
o.mu.Lock()
o.frame++
o.mu.Unlock()
o.render()
return 0

case 0x0201: // WM_LBUTTONDOWN
	o.mu.Lock()
	st := o.state
	confirmCB := o.onConfirm
	pauseCB := o.onPause
	o.mu.Unlock()
	if st == StateRecording || st == StatePaused {
		x := int32(lParam & 0xFFFF)
		y := int32((lParam >> 16) & 0xFFFF)
		if x >= _BTN_CONFIRM_X && x <= _BTN_CONFIRM_X+_BTN_SIZE &&
			y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
			if confirmCB != nil {
				go confirmCB()
			}
			return 0
		}
		if x >= _BTN_PAUSE_X && x <= _BTN_PAUSE_X+_BTN_SIZE &&
			y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
			if pauseCB != nil {
				go pauseCB()
			}
			return 0
		}
	}
	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret

case _WM_OVL_SHOW:
o.mu.Lock()
o.state = AppState(wParam)
o.frame = 0
if o.state == StateRecording {
o.startTime = time.Now()
for i := range o.levels {
o.levels[i] = 0
}
o.levelIdx = 0
}
pos := o.position
o.visible = true
o.mu.Unlock()

// Position window based on config
x, y := overlayPosition(pos)

const _HWND_TOPMOST = ^uintptr(0)
const _SWP_NOACTIVATE = 0x0010
const _SWP_SHOWWINDOW = 0x0040
procSetWindowPos.Call(hwnd, _HWND_TOPMOST,
uintptr(x), uintptr(y), _OVL_WIDTH, _OVL_HEIGHT,
_SWP_NOACTIVATE|_SWP_SHOWWINDOW)
procSetTimer.Call(hwnd, _TIMER_ID, _TIMER_MS, 0)
o.render()
return 0

case _WM_OVL_HIDE:
o.mu.Lock()
o.visible = false
o.mu.Unlock()
procKillTimer.Call(hwnd, _TIMER_ID)
procShowWindow.Call(hwnd, _SW_HIDE)
return 0

case _WM_OVL_PAUSE:
	o.mu.Lock()
	o.paused = wParam != 0
	o.mu.Unlock()
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
// GDI+ resources
if o.gdipFontMain != 0 { procGdipDeleteFont.Call(o.gdipFontMain) }
if o.gdipFontSmall != 0 { procGdipDeleteFont.Call(o.gdipFontSmall) }
if o.gdipFontFamily != 0 { procGdipDeleteFontFamily.Call(o.gdipFontFamily) }
if o.gdipStrFmt != 0 { procGdipDeleteStringFormat.Call(o.gdipStrFmt) }
if o.gdipIconBmp != 0 { procGdipDisposeImage.Call(o.gdipIconBmp) }
// DIB section
if o.dibDC != 0 { procDeleteDC.Call(o.dibDC) }
if o.dibBmp != 0 { procDeleteObject.Call(o.dibBmp) }
// GDI resources
if o.fontMain != 0 { procDeleteObject.Call(o.fontMain); o.fontMain = 0 }
if o.fontSmall != 0 { procDeleteObject.Call(o.fontSmall); o.fontSmall = 0 }
if o.hIcon != 0 { procDestroyIcon.Call(o.hIcon); o.hIcon = 0 }
shutdownGDIPlus()
procPostQuitMessage.Call(0)
return 0
}

ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
return ret
}

// overlayPosition calculates screen position based on config.
// Uses virtual screen coordinates for correct multi-monitor support.
func overlayPosition(pos string) (int, int) {
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
x := int(pt.X) - _OVL_WIDTH/2
y := int(pt.Y) - _OVL_HEIGHT - 16
if x < minX+8 {
x = minX + 8
}
if x+_OVL_WIDTH > maxX-8 {
x = maxX - _OVL_WIDTH - 8
}
if y < minY+8 {
y = int(pt.Y) + 24 // below cursor if no room above
}
if y+_OVL_HEIGHT > maxY-8 {
y = maxY - _OVL_HEIGHT - 8
}
return x, y
}
// Default: top center of primary monitor
screenW, _, _ := procGetSystemMetrics.Call(_SM_CXSCREEN)
return (int(screenW) - _OVL_WIDTH) / 2, _OVL_MARGIN
}

// NewOverlay creates the overlay window on a dedicated OS thread.
func NewOverlay() (*Overlay, error) {
o := &Overlay{
ready:    make(chan error, 1),
done:     make(chan struct{}),
position: "top_center",
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

// Load app icon at 48x48 for crisp display
o.loadIcon(48)

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

// Create GDI+ bitmap from icon for bicubic rendering
if o.hIcon != 0 {
procGdipCreateBitmapFromHICON.Call(o.hIcon, uintptr(unsafe.Pointer(&o.gdipIconBmp)))
}

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

// SetCallbacks sets the confirm and pause button callbacks.
func (o *Overlay) SetCallbacks(onConfirm, onPause func()) {
o.mu.Lock()
o.onConfirm = onConfirm
o.onPause = onPause
o.mu.Unlock()
}

// SetPaused updates the paused display state via window message.
func (o *Overlay) SetPaused(paused bool) {
if o.hwnd != 0 {
v := uintptr(0)
if paused { v = 1 }
procPostMessageW.Call(o.hwnd, _WM_OVL_PAUSE, v, 0)
}
}

// SetPosition updates the overlay position preference.
func (o *Overlay) SetPosition(pos string) {
o.mu.Lock()
o.position = pos
o.mu.Unlock()
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

func f32(v float32) uintptr {
return uintptr(math.Float32bits(v))
}

func (o *Overlay) createDIB() {
var bmi bitmapInfoHeader
bmi.BiSize = uint32(unsafe.Sizeof(bmi))
bmi.BiWidth = _OVL_WIDTH
bmi.BiHeight = -_OVL_HEIGHT // top-down
bmi.BiPlanes = 1
bmi.BiBitCount = 32

screenDC, _, _ := procGetDC.Call(0)
var bits uintptr
o.dibBmp, _, _ = procCreateDIBSection.Call(
screenDC,
uintptr(unsafe.Pointer(&bmi)),
0, // DIB_RGB_COLORS
uintptr(unsafe.Pointer(&bits)),
0, 0)
procReleaseDC.Call(0, screenDC)

o.dibDC, _, _ = procCreateCompatibleDC.Call(0)
if o.dibDC != 0 && o.dibBmp != 0 {
procSelectObject.Call(o.dibDC, o.dibBmp)
}
}

func (o *Overlay) render() {
if o.dibDC == 0 {
return
}

// Create GDI+ Graphics from the persistent DIB DC
var g uintptr
procGdipCreateFromHDC.Call(o.dibDC, uintptr(unsafe.Pointer(&g)))
if g == 0 {
return
}
defer procGdipDeleteGraphics.Call(g)

procGdipSetSmoothingMode.Call(g, _SmoothingModeAntiAlias)
procGdipSetTextRenderingHint.Call(g, _TextRenderingHintAntiAliasGridFit)
procGdipSetInterpolationMode.Call(g, _InterpolationModeHighQualityBicubic)

// Clear to fully transparent
procGdipGraphicsClear.Call(g, 0x00000000)

// Drop shadow (subtle)
o.drawPillPath(g, 3, 3, 0x40000000)

// Main pill background
o.drawPillPath(g, 0, 0, 0xE80A1A29)

// Pill border
o.drawPillBorder(g, 0, 0, 0xA00066B8)

// App icon (bicubic interpolation)
if o.gdipIconBmp != 0 {
iconY := int32((_OVL_HEIGHT - _ICON_SIZE) / 2)
procGdipDrawImageRectI.Call(g, o.gdipIconBmp,
uintptr(_ICON_PADDING), uintptr(iconY), uintptr(_ICON_SIZE), uintptr(_ICON_SIZE))
}

// Content area starts after icon
contentX := int32(_ICON_PADDING + _ICON_SIZE + 12)

o.mu.Lock()
state := o.state
frame := o.frame
startTime := o.startTime
var levels [_WAVE_BARS]float32
copy(levels[:], o.levels[:])
levelIdx := o.levelIdx
o.mu.Unlock()

switch state {
case StateRecording, StatePaused:
o.paintRecordingULW(g, frame, startTime, levels, levelIdx, contentX)
case StateTranscribing, StateProcessing:
o.paintTranscribingULW(g, frame, contentX)
case StateError:
o.paintErrorULW(g, contentX)
case StateCopied:
o.paintCopiedULW(g, contentX)
}

// Call UpdateLayeredWindow
blend := blendFunction{
BlendOp:             0, // AC_SRC_OVER
SourceConstantAlpha: 255,
AlphaFormat:         1, // AC_SRC_ALPHA
}
ptSrc := pointT{0, 0}
sz := sizeT{_OVL_WIDTH, _OVL_HEIGHT}

procUpdateLayeredWindow.Call(
o.hwnd,
0, // hdcDst (NULL = screen)
0, // pptDst (NULL = keep position)
uintptr(unsafe.Pointer(&sz)),
o.dibDC,
uintptr(unsafe.Pointer(&ptSrc)),
0, // crKey (unused)
uintptr(unsafe.Pointer(&blend)),
2, // ULW_ALPHA
)
}

func (o *Overlay) drawPillPath(g uintptr, offsetX, offsetY int32, argb uint32) {
var path uintptr
procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
if path == 0 {
return
}
defer procGdipDeletePath.Call(path)

x := float32(1 + offsetX)
y := float32(1 + offsetY)
w := float32(_OVL_WIDTH - 2)
h := float32(_OVL_HEIGHT - 2)
r := float32(_OVL_RADIUS)
d := r * 2

procGdipAddPathArc.Call(path, f32(x), f32(y), f32(d), f32(d), f32(180), f32(90))
procGdipAddPathArc.Call(path, f32(x+w-d), f32(y), f32(d), f32(d), f32(270), f32(90))
procGdipAddPathArc.Call(path, f32(x+w-d), f32(y+h-d), f32(d), f32(d), f32(0), f32(90))
procGdipAddPathArc.Call(path, f32(x), f32(y+h-d), f32(d), f32(d), f32(90), f32(90))
procGdipClosePathFigure.Call(path)

var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)

procGdipFillPath.Call(g, brush, path)
}

func (o *Overlay) drawPillBorder(g uintptr, offsetX, offsetY int32, argb uint32) {
var path uintptr
procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
if path == 0 {
return
}
defer procGdipDeletePath.Call(path)

x := float32(1 + offsetX)
y := float32(1 + offsetY)
w := float32(_OVL_WIDTH - 2)
h := float32(_OVL_HEIGHT - 2)
r := float32(_OVL_RADIUS)
d := r * 2

procGdipAddPathArc.Call(path, f32(x), f32(y), f32(d), f32(d), f32(180), f32(90))
procGdipAddPathArc.Call(path, f32(x+w-d), f32(y), f32(d), f32(d), f32(270), f32(90))
procGdipAddPathArc.Call(path, f32(x+w-d), f32(y+h-d), f32(d), f32(d), f32(0), f32(90))
procGdipAddPathArc.Call(path, f32(x), f32(y+h-d), f32(d), f32(d), f32(90), f32(90))
procGdipClosePathFigure.Call(path)

var pen uintptr
procGdipCreatePen1.Call(uintptr(argb), f32(1.5), _UnitPixel, uintptr(unsafe.Pointer(&pen)))
if pen == 0 {
return
}
defer procGdipDeletePen.Call(pen)

procGdipDrawPath.Call(g, pen, path)
}

func (o *Overlay) drawGdipText(g uintptr, text string, x, y, w float32, font uintptr, argb uint32) {
if font == 0 || o.gdipStrFmt == 0 {
return
}
utf16, _ := windows.UTF16FromString(text)
var brush uintptr
procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
if brush == 0 {
return
}
defer procGdipDeleteBrush.Call(brush)

rect := gdipRectF{X: x, Y: y, Width: w, Height: 24}
procGdipDrawString.Call(g,
uintptr(unsafe.Pointer(&utf16[0])),
uintptr(len(utf16)-1),
font,
uintptr(unsafe.Pointer(&rect)),
o.gdipStrFmt,
brush)
}

func (o *Overlay) paintRecordingULW(g uintptr, frame int, start time.Time, levels [_WAVE_BARS]float32, levelIdx int, contentX int32) {
cy := int32(_OVL_HEIGHT / 2)

o.mu.Lock()
isPaused := o.paused
o.mu.Unlock()

// Pulsing recording dot
if isPaused {
gdipFillCircleG(g, 0x80FF3C3C, contentX+7, cy, 7)
} else {
pulse := float64(frame) * 0.12
alpha := uint32(180 + int(math.Sin(pulse)*75))
if alpha > 255 {
alpha = 255
}
argb := (alpha << 24) | 0x00FF3C3C
gdipFillCircleG(g, argb, contentX+7, cy, 7)
}

// Status text
textX := float32(contentX + 7*2 + 8)
if isPaused {
o.drawGdipText(g, T("overlay.paused"), textX, 14, 120, o.gdipFontMain, 0xFFFFFFFF)
} else {
o.drawGdipText(g, T("overlay.recording"), textX, 14, 120, o.gdipFontMain, 0xFFFFFFFF)
}

// Elapsed timer
elapsed := time.Since(start).Seconds()
secs := int(elapsed)
timer := fmt.Sprintf("%d:%02d", secs/60, secs%60)
o.drawGdipText(g, timer, textX, 36, 60, o.gdipFontSmall, 0xFFB0A090)

// Scrolling waveform bars
waveX := int32(_OVL_WIDTH - _WAVE_RIGHT - _WAVE_BARS*(_WAVE_BAR_W+_WAVE_GAP) - _BTN_SIZE*2 - _BTN_GAP - 16)
for i := 0; i < _WAVE_BARS; i++ {
idx := (levelIdx + i) % _WAVE_BARS
lvl := levels[idx]
if isPaused {
lvl = 0
}
amp := lvl * _WAVE_AMP
if amp > 1.0 {
amp = 1.0
}
h := int32(amp * 36.0)
if h < 2 {
h = 2
}
x := waveX + int32(i)*(_WAVE_BAR_W+_WAVE_GAP)
y1 := cy - h/2
y2 := cy + h/2
if h > 6 {
gdipFillRectG(g, 0xE022D3EE, x, y1, _WAVE_BAR_W, y2-y1)
} else {
gdipFillRectG(g, 0x80226688, x, y1, _WAVE_BAR_W, y2-y1)
}
}

// Control buttons
gdipFillCircleG(g, 0xFF34C759, _BTN_CONFIRM_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
if isPaused {
gdipFillCircleG(g, 0xFF22D3EE, _BTN_PAUSE_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
} else {
gdipFillCircleG(g, 0xFF0066B8, _BTN_PAUSE_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
}

// Button icons
o.drawGdipText(g, "\u2713", float32(_BTN_CONFIRM_X+7), float32(cy-7), 20, o.gdipFontSmall, 0xFFFFFFFF)
if isPaused {
o.drawGdipText(g, "\u25B6", float32(_BTN_PAUSE_X+8), float32(cy-7), 20, o.gdipFontSmall, 0xFFFFFFFF)
} else {
o.drawGdipText(g, "\u23F8", float32(_BTN_PAUSE_X+6), float32(cy-8), 20, o.gdipFontSmall, 0xFFFFFFFF)
}
}

func (o *Overlay) paintTranscribingULW(g uintptr, frame int, contentX int32) {
cy := int32(_OVL_HEIGHT / 2)

// Spinner
const numDots = 8
const spinR = 10
const dotR = 3
spinCx := contentX + spinR + 2
spinCy := cy
angleOffset := float64(frame) * 0.15
for i := 0; i < numDots; i++ {
angle := angleOffset + float64(i)*2.0*math.Pi/float64(numDots)
dx := int32(float64(spinR) * math.Cos(angle))
dy := int32(float64(spinR) * math.Sin(angle))
alpha := uint32(60 + (195 * uint32(i) / uint32(numDots-1)))
argb := (alpha << 24) | 0x0022D3EE
gdipFillCircleG(g, argb, spinCx+dx, spinCy+dy, dotR)
}

// Text
textX := float32(contentX + spinR*2 + 16)
text := T("overlay.transcribing")
for len(text) > 0 && text[len(text)-1] == '.' {
text = text[:len(text)-1]
}
n := (frame / 15) % 4
for i := 0; i < n; i++ {
text += "."
}
o.drawGdipText(g, text, textX, float32(cy-10), 200, o.gdipFontMain, 0xFFFFFFFF)
}

func (o *Overlay) paintErrorULW(g uintptr, contentX int32) {
text := T("error.no_api_key")
o.drawGdipText(g, text, float32(contentX), float32(_OVL_HEIGHT/2-10), float32(_OVL_WIDTH-16-contentX), o.gdipFontMain, 0xFFFF3C3C)
}

func (o *Overlay) paintCopiedULW(g uintptr, contentX int32) {
cy := int32(_OVL_HEIGHT / 2)
gdipFillCircleG(g, 0xFF34C759, contentX+8, cy, 8)
o.drawGdipText(g, "\u2713", float32(contentX+1), float32(cy-10), 16, o.gdipFontSmall, 0xFFFFFFFF)
text := T("overlay.copied")
o.drawGdipText(g, text, float32(contentX+24), float32(cy-10), 260, o.gdipFontMain, 0xFF34C759)
}