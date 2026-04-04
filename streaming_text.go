//go:build windows

package main

import (
	"fmt"
	"math"
	"runtime"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// StreamingTextWindow displays live transcription preview text
// in a separate layered window below the recording overlay.
type StreamingTextWindow struct {
	hwnd    uintptr
	dibDC   uintptr
	dibBmp  uintptr
	gdipFF  uintptr // GDI+ font family
	gdipF   uintptr // GDI+ font
	gdipSF  uintptr // GDI+ string format
	text    string
	visible bool
	scale   float64
	ready   chan struct{}
	done    chan struct{}
	mu      sync.Mutex
}

const (
	_STW_WIDTH   = 500
	_STW_HEIGHT  = 42
	_STW_GAP     = 10 // gap between overlay and this window
	_STW_RADIUS  = 14
	_STW_TIMER   = 2
	_STW_TIMEMS  = 100 // repaint interval (10 FPS)
	_WM_STW_TEXT = _WM_USER + 10
)

var (
	stwClass     *uint16
	stwClassErr  error
	stwClassOnce sync.Once
	globalSTW    atomic.Pointer[StreamingTextWindow]
)

var stwWndProcCB = syscall.NewCallback(streamTextWndProc)

func streamTextWndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	stw := globalSTW.Load()

	switch msg {
	case _WM_TIMER:
		if stw != nil && wParam == _STW_TIMER {
			stw.paint()
		}
		return 0

	case _WM_STW_TEXT:
		if stw != nil {
			stw.paint()
		}
		return 0

	case uintptr(_WM_DESTROY):
		procKillTimer.Call(hwnd, _STW_TIMER)
		procPostQuitMessage.Call(0)
		return 0
	}

	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret
}

// NewStreamingTextWindow creates but does not show the streaming text window.
func NewStreamingTextWindow() (*StreamingTextWindow, error) {
	stw := &StreamingTextWindow{
		ready: make(chan struct{}),
		done:  make(chan struct{}),
	}
	globalSTW.Store(stw)

	go stw.run()

	select {
	case <-stw.ready:
		if stw.hwnd == 0 {
			return nil, fmt.Errorf("failed to create streaming text window")
		}
		return stw, nil
	case <-time.After(3 * time.Second):
		return nil, fmt.Errorf("timeout creating streaming text window")
	}
}

func (stw *StreamingTextWindow) run() {
	runtime.LockOSThread()
	defer close(stw.done)

	initGDIPlus() // ensure GDI+ is initialized (safe to call multiple times via sync.Once)

	stwClassOnce.Do(func() {
		name := "WhisPasteStreamText"
		stwClass, _ = windows.UTF16PtrFromString(name)

		var wc wndClassExW
		wc.CbSize = uint32(unsafe.Sizeof(wc))
		wc.LpfnWndProc = stwWndProcCB
		hInst, _, _ := procGetModuleHandleW.Call(0)
		wc.HInstance = hInst
		wc.HCursor, _, _ = procLoadCursorW.Call(0, _IDC_ARROW)
		wc.LpszClassName = stwClass

		atom, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
		if atom == 0 {
			stwClassErr = fmt.Errorf("RegisterClassExW failed for StreamText")
		}
	})

	if stwClassErr != nil {
		close(stw.ready)
		return
	}

	hInst, _, _ := procGetModuleHandleW.Call(0)
	screenW, _, _ := procGetSystemMetrics.Call(_SM_CXSCREEN)
	x := (int(screenW) - _STW_WIDTH) / 2
	y := _OVL_MARGIN + _OVL_HEIGHT + _STW_GAP

	// WS_EX_TRANSPARENT (0x20) makes the window click-through
	exStyle := uintptr(_WS_EX_TOPMOST | _WS_EX_LAYERED | _WS_EX_TOOLWINDOW | _WS_EX_NOACTIVATE | 0x20)

	hwnd, _, _ := procCreateWindowExW.Call(
		exStyle,
		uintptr(unsafe.Pointer(stwClass)),
		0,
		uintptr(_WS_POPUP),
		uintptr(x), uintptr(y), _STW_WIDTH, _STW_HEIGHT,
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		close(stw.ready)
		return
	}
	stw.hwnd = hwnd

	// DPI scale
	dpi, _, _ := procGetDpiForWindow.Call(hwnd)
	if dpi > 0 {
		stw.scale = float64(dpi) / 96.0
	} else {
		stw.scale = 1.0
	}

	scaledW := int(float64(_STW_WIDTH) * stw.scale)
	scaledH := int(float64(_STW_HEIGHT) * stw.scale)

	// Resize window to DPI-scaled dimensions
	procSetWindowPos.Call(hwnd, 0,
		uintptr((int(screenW)-scaledW)/2), uintptr(_OVL_MARGIN+_OVL_HEIGHT+_STW_GAP),
		uintptr(scaledW), uintptr(scaledH),
		0x0010|0x0004) // SWP_NOACTIVATE | SWP_NOZORDER

	// Create DIB section for UpdateLayeredWindow
	stw.createDIB(scaledW, scaledH)

	// Create GDI+ font (DPI-scaled)
	fontSize := float32(14.0 * stw.scale)
	fontName, _ := windows.UTF16PtrFromString("Segoe UI")
	procGdipCreateFontFamilyFromName.Call(uintptr(unsafe.Pointer(fontName)), 0, uintptr(unsafe.Pointer(&stw.gdipFF)))
	if stw.gdipFF != 0 {
		procGdipCreateFont.Call(stw.gdipFF, f32(fontSize), _FontStyleRegular, _UnitPixel, uintptr(unsafe.Pointer(&stw.gdipF)))
	}
	procGdipCreateStringFormat.Call(0, 0, uintptr(unsafe.Pointer(&stw.gdipSF)))
	if stw.gdipSF != 0 {
		procGdipSetStringFormatAlign.Call(stw.gdipSF, 1)    // center
		procGdipSetStringFormatLineAlign.Call(stw.gdipSF, 1) // center vertically
		procGdipSetStringFormatTrimming.Call(stw.gdipSF, 3)  // EllipsisCharacter
	}

	procSetTimer.Call(hwnd, _STW_TIMER, _STW_TIMEMS, 0)

	close(stw.ready)

	// Message loop
	var msg msgT
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if ret == 0 || ret == uintptr(math.MaxUint64) {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}

	// Cleanup GDI+ resources
	if stw.gdipSF != 0 {
		procGdipDeleteStringFormat.Call(stw.gdipSF)
	}
	if stw.gdipF != 0 {
		procGdipDeleteFont.Call(stw.gdipF)
	}
	if stw.gdipFF != 0 {
		procGdipDeleteFontFamily.Call(stw.gdipFF)
	}
	if stw.dibBmp != 0 {
		procDeleteObject.Call(stw.dibBmp)
	}
	if stw.dibDC != 0 {
		procDeleteDC.Call(stw.dibDC)
	}
}

func (stw *StreamingTextWindow) createDIB(w, h int) {
	var bmi bitmapInfoHeader
	bmi.BiSize = uint32(unsafe.Sizeof(bmi))
	bmi.BiWidth = int32(w)
	bmi.BiHeight = -int32(h) // top-down
	bmi.BiPlanes = 1
	bmi.BiBitCount = 32

	screenDC, _, _ := procGetDC.Call(0)
	var bits uintptr
	stw.dibBmp, _, _ = procCreateDIBSection.Call(
		screenDC,
		uintptr(unsafe.Pointer(&bmi)),
		0, // DIB_RGB_COLORS
		uintptr(unsafe.Pointer(&bits)),
		0, 0)
	procReleaseDC.Call(0, screenDC)

	stw.dibDC, _, _ = procCreateCompatibleDC.Call(0)
	if stw.dibDC != 0 && stw.dibBmp != 0 {
		procSelectObject.Call(stw.dibDC, stw.dibBmp)
	}
}

// SetText updates the streaming text. Thread-safe.
func (stw *StreamingTextWindow) SetText(text string) {
	stw.mu.Lock()
	stw.text = text
	stw.mu.Unlock()
	if stw.hwnd != 0 {
		procPostMessageW.Call(stw.hwnd, _WM_STW_TEXT, 0, 0)
	}
}

// Show makes the window ready to display (actual visibility depends on text).
func (stw *StreamingTextWindow) Show() {
	stw.mu.Lock()
	stw.visible = true
	stw.text = ""
	stw.mu.Unlock()
}

// Hide hides the window and clears text.
func (stw *StreamingTextWindow) Hide() {
	stw.mu.Lock()
	stw.visible = false
	stw.text = ""
	stw.mu.Unlock()
	if stw.hwnd != 0 {
		procShowWindow.Call(stw.hwnd, _SW_HIDE)
	}
}

// Close destroys the window.
func (stw *StreamingTextWindow) Close() {
	if stw.hwnd != 0 {
		procPostMessageW.Call(stw.hwnd, uintptr(_WM_CLOSE), 0, 0)
		select {
		case <-stw.done:
		case <-time.After(2 * time.Second):
			logWarn("StreamingTextWindow.Close() timed out")
		}
	}
}

func (stw *StreamingTextWindow) paint() {
	stw.mu.Lock()
	text := stw.text
	vis := stw.visible
	stw.mu.Unlock()

	if !vis || text == "" {
		procShowWindow.Call(stw.hwnd, _SW_HIDE)
		return
	}

	if stw.dibDC == 0 {
		return
	}

	w := int32(float64(_STW_WIDTH) * stw.scale)
	h := int32(float64(_STW_HEIGHT) * stw.scale)
	r := float32(float64(_STW_RADIUS) * stw.scale)

	// Get GDI+ graphics from DIB DC
	var g uintptr
	procGdipCreateFromHDC.Call(stw.dibDC, uintptr(unsafe.Pointer(&g)))
	if g == 0 {
		return
	}
	defer procGdipDeleteGraphics.Call(g)

	procGdipSetSmoothingMode.Call(g, _SmoothingModeAntiAlias)
	procGdipSetTextRenderingHint.Call(g, _TextRenderingHintClearType)

	// Clear to transparent
	procGdipGraphicsClear.Call(g, 0x00000000)

	// Draw rounded rectangle background (semi-transparent dark)
	var bgPath uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&bgPath)))
	if bgPath == 0 {
		return
	}
	defer procGdipDeletePath.Call(bgPath)

	d := r * 2
	fw := float32(w) - 2
	fh := float32(h) - 2
	procGdipAddPathArc.Call(bgPath, f32(1), f32(1), f32(d), f32(d), f32(180), f32(90))
	procGdipAddPathArc.Call(bgPath, f32(fw-d+1), f32(1), f32(d), f32(d), f32(270), f32(90))
	procGdipAddPathArc.Call(bgPath, f32(fw-d+1), f32(fh-d+1), f32(d), f32(d), f32(0), f32(90))
	procGdipAddPathArc.Call(bgPath, f32(1), f32(fh-d+1), f32(d), f32(d), f32(90), f32(90))
	procGdipClosePathFigure.Call(bgPath)

	// Semi-transparent dark background (clearly visible below overlay)
	var bgBrush uintptr
	procGdipCreateSolidFill.Call(0xDD0A1A29, uintptr(unsafe.Pointer(&bgBrush)))
	if bgBrush != 0 {
		procGdipFillPath.Call(g, bgBrush, bgPath)
		procGdipDeleteBrush.Call(bgBrush)
	}

	// Draw text centered
	if stw.gdipF != 0 && stw.gdipSF != 0 {
		textU16, _ := windows.UTF16PtrFromString(text)
		u16Len := 0
		for p := textU16; *p != 0; p = (*uint16)(unsafe.Pointer(uintptr(unsafe.Pointer(p)) + 2)) {
			u16Len++
		}

		rect := [4]float32{float32(r), 0, float32(w) - 2*float32(r), float32(h)}

		var textBrush uintptr
		procGdipCreateSolidFill.Call(0xF0FFFFFF, uintptr(unsafe.Pointer(&textBrush)))
		if textBrush != 0 {
			procGdipDrawString.Call(
				g,
				uintptr(unsafe.Pointer(textU16)),
				uintptr(u16Len),
				stw.gdipF,
				uintptr(unsafe.Pointer(&rect[0])),
				stw.gdipSF,
				textBrush,
			)
			procGdipDeleteBrush.Call(textBrush)
		}
	}

	// UpdateLayeredWindow
	ptSrc := pointT{0, 0}
	sz := [2]int32{w, h}
	bf := [4]byte{0, 0, 255, 1} // AC_SRC_OVER, 0, 255, AC_SRC_ALPHA
	procUpdateLayeredWindow.Call(
		stw.hwnd, 0,
		0, // don't change position
		uintptr(unsafe.Pointer(&sz[0])),
		stw.dibDC,
		uintptr(unsafe.Pointer(&ptSrc)),
		0,
		uintptr(unsafe.Pointer(&bf[0])),
		2, // ULW_ALPHA
	)

	// Ensure window stays on top of all other windows
	const _HWND_TOPMOST_STW = ^uintptr(0)
	procSetWindowPos.Call(stw.hwnd, _HWND_TOPMOST_STW, 0, 0, 0, 0,
		0x0001|0x0002|0x0010) // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
	procShowWindow.Call(stw.hwnd, _SW_SHOWNA) // show without activating
}

