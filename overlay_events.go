package main

import (
	"math"
	"syscall"
	"time"
	"unsafe"
)

// getHitButton returns which button is at position (x, y) in logical overlay
// coordinates: 1=dashboard, 2=cancel, 3=pause, 4=confirm, 0=none.
// Cancel is always checked. When allButtons is true, dashboard/pause/confirm
// are also checked (for recording/paused states).
func getHitButton(x, y int32, allButtons bool) int {
	if x >= _BTN_CANCEL_X && x <= _BTN_CANCEL_X+_BTN_SIZE &&
		y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
		return 2
	}
	if allButtons {
		if x >= _BTN_DASH_X && x <= _BTN_DASH_X+_BTN_SIZE &&
			y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
			return 1
		}
		if x >= _BTN_PAUSE_X && x <= _BTN_PAUSE_X+_BTN_SIZE &&
			y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
			return 3
		}
		if x >= _BTN_CONFIRM_X && x <= _BTN_CONFIRM_X+_BTN_SIZE &&
			y >= _BTN_Y && y <= _BTN_Y+_BTN_SIZE {
			return 4
		}
	}
	return 0
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
		if st == StateRecording || st == StatePaused || st == StateTranscribing || st == StateProcessing {
			xScreen := int32(lParam & 0xFFFF)
			yScreen := int32((lParam >> 16) & 0xFFFF)
			var pt pointT
			pt.X = xScreen
			pt.Y = yScreen
			procScreenToClient.Call(hwnd, uintptr(unsafe.Pointer(&pt)))
			// Convert physical client coords to logical for hit testing
			pt.X = int32(float64(pt.X) / o.scale)
			pt.Y = int32(float64(pt.Y) / o.scale)
			if getHitButton(pt.X, pt.Y, true) != 0 {
				return 1 // HTCLIENT
			}
		}
		return _HTCAPTION

	case 0x0200: // WM_MOUSEMOVE
		o.mu.Lock()
		st := o.state
		o.mu.Unlock()
		if st == StateRecording || st == StatePaused || st == StateTranscribing || st == StateProcessing {
			x := int32(float64(lParam&0xFFFF) / o.scale)
			y := int32(float64((lParam>>16)&0xFFFF) / o.scale)
			btn := getHitButton(x, y, st == StateRecording || st == StatePaused)
			o.mu.Lock()
			if !o.tracking {
				type trackMouseEventT struct {
					cbSize      uint32
					dwFlags     uint32
					hwndTrack   uintptr
					dwHoverTime uint32
				}
				tme := trackMouseEventT{
					cbSize:    uint32(unsafe.Sizeof(trackMouseEventT{})),
					dwFlags:   0x00000002, // TME_LEAVE
					hwndTrack: hwnd,
				}
				procTrackMouseEvent.Call(uintptr(unsafe.Pointer(&tme)))
				o.tracking = true
			}
			o.hoverBtn = btn
			o.mu.Unlock()
		}
		return 0

	case 0x02A3: // WM_MOUSELEAVE
		o.mu.Lock()
		o.hoverBtn = 0
		o.tracking = false
		o.mu.Unlock()
		return 0

	case _WM_TIMER:
		o.mu.Lock()
		o.frame++
		frame := o.frame
		vis := o.visible
		o.mu.Unlock()
		if vis && frame%_TOPMOST_INTERVAL == 0 {
			const _HWND_TOPMOST2 = ^uintptr(0)
			const _SWP_NOMOVE2 = 0x0002
			const _SWP_NOSIZE2 = 0x0001
			const _SWP_NOACTIVATE2 = 0x0010
			procSetWindowPos.Call(hwnd, _HWND_TOPMOST2, 0, 0, 0, 0, _SWP_NOMOVE2|_SWP_NOSIZE2|_SWP_NOACTIVATE2)
		}
		o.render()
		return 0

	case 0x0201: // WM_LBUTTONDOWN
		o.mu.Lock()
		st := o.state
		confirmCB := o.onConfirm
		cancelCB := o.onCancel
		pauseCB := o.onPause
		dashCB := o.onDash
		o.mu.Unlock()
		if st == StateRecording || st == StatePaused || st == StateTranscribing || st == StateProcessing {
			x := int32(float64(lParam&0xFFFF) / o.scale)
			y := int32(float64((lParam>>16)&0xFFFF) / o.scale)
			btn := getHitButton(x, y, st == StateRecording || st == StatePaused)
			if btn != 0 {
				o.mu.Lock()
				o.pressBtn = btn
				o.mu.Unlock()
				cbs := map[int]func(){1: dashCB, 2: cancelCB, 3: pauseCB, 4: confirmCB}
				if cb := cbs[btn]; cb != nil {
					go cb()
				}
				return 0
			}
		}
		ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
		return ret

	case 0x0202: // WM_LBUTTONUP
		o.mu.Lock()
		o.pressBtn = 0
		o.mu.Unlock()
		return 0

	case _WM_OVL_SHOW:
		o.mu.Lock()
		o.state = AppState(wParam)
		o.frame = 0
		if o.state == StateRecording {
			o.startTime = time.Now()
			o.pauseAccum = 0
			o.paused = false
			o.isSmartMode = false
			for i := range o.levels {
				o.levels[i] = 0
			}
			o.levelIdx = 0
		}
		if o.state == StateTranscribing {
			o.transcribeStart = time.Now()
			o.estimatedSec = 0
		}
		pos := o.position
		o.visible = true
		o.mu.Unlock()

		// Position window based on config (initially using current DPI scale)
		x, y := o.overlayPosition(pos)

		// Move window to target position to detect the correct monitor DPI
		const _SWP_NOSIZE_ = 0x0001
		const _SWP_NOACTIVATE_ = 0x0010
		const _SWP_NOZORDER_ = 0x0004
		procSetWindowPos.Call(hwnd, 0,
			uintptr(x), uintptr(y), 0, 0,
			_SWP_NOSIZE_|_SWP_NOACTIVATE_|_SWP_NOZORDER_)

		// Recompute DPI scale from the target monitor
		newScale := o.dpiScale()
		if newScale < 1.0 {
			newScale = 1.0
		}
		if newScale != o.scale {
			o.scale = newScale
			// Recreate DIB at new scale
			if o.dibDC != 0 {
				procDeleteDC.Call(o.dibDC)
				o.dibDC = 0
			}
			if o.dibBmp != 0 {
				procDeleteObject.Call(o.dibBmp)
				o.dibBmp = 0
			}
			o.createDIB()
			// Recompute position with new scale
			x, y = o.overlayPosition(pos)
		}

		const _HWND_TOPMOST = ^uintptr(0)
		const _SWP_NOACTIVATE = 0x0010
		const _SWP_SHOWWINDOW = 0x0040
		procSetWindowPos.Call(hwnd, _HWND_TOPMOST,
			uintptr(x), uintptr(y), uintptr(o.sc(_OVL_WIDTH)), uintptr(o.sc(_OVL_HEIGHT)),
			_SWP_NOACTIVATE|_SWP_SHOWWINDOW)
		procSetTimer.Call(hwnd, _TIMER_ID, _TIMER_MS, 0)
		o.render()
		return 0

	case _WM_OVL_HIDE:
		o.mu.Lock()
		o.visible = false
		o.hoverBtn = 0
		o.pressBtn = 0
		o.tracking = false
		o.mu.Unlock()
		procKillTimer.Call(hwnd, _TIMER_ID)
		procShowWindow.Call(hwnd, _SW_HIDE)
		return 0

	case _WM_OVL_PAUSE:
		o.mu.Lock()
		wasPaused := o.paused
		o.paused = wParam != 0
		if o.paused && !wasPaused {
			o.pauseStart = time.Now()
		} else if !o.paused && wasPaused {
			o.pauseAccum += time.Since(o.pauseStart)
		}
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
		if o.gdipFontMain != 0 {
			procGdipDeleteFont.Call(o.gdipFontMain)
		}
		if o.gdipFontSmall != 0 {
			procGdipDeleteFont.Call(o.gdipFontSmall)
		}
		if o.gdipFontFamily != 0 {
			procGdipDeleteFontFamily.Call(o.gdipFontFamily)
		}
		if o.gdipStrFmt != 0 {
			procGdipDeleteStringFormat.Call(o.gdipStrFmt)
		}
		if o.gdipIconBmp != 0 {
			procGdipDisposeImage.Call(o.gdipIconBmp)
		}
		// DIB section
		if o.dibDC != 0 {
			procDeleteDC.Call(o.dibDC)
		}
		if o.dibBmp != 0 {
			procDeleteObject.Call(o.dibBmp)
		}
		// GDI resources
		if o.fontMain != 0 {
			procDeleteObject.Call(o.fontMain)
			o.fontMain = 0
		}
		if o.fontSmall != 0 {
			procDeleteObject.Call(o.fontSmall)
			o.fontSmall = 0
		}
		if o.hIcon != 0 {
			procDestroyIcon.Call(o.hIcon)
			o.hIcon = 0
		}
		shutdownGDIPlus()
		procPostQuitMessage.Call(0)
		return 0
	}

	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret
}
