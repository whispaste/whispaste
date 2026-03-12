package main

import (
	"fmt"
	"math"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

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

// gdipFillRoundedBar draws a waveform bar with rounded ends using a GDI+ path.
func gdipFillRoundedBar(g uintptr, argb uint32, x, y, w, h int32) {
	if h <= w {
		gdipFillCircleG(g, argb, x+w/2, y+h/2, w/2)
		return
	}
	var path uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
	if path == 0 {
		return
	}
	defer procGdipDeletePath.Call(path)
	r := float32(w) / 2.0
	fx, fy, fh := float32(x), float32(y), float32(h)
	d := r * 2
	// Top semicircle
	procGdipAddPathArc.Call(path, f32(fx), f32(fy), f32(d), f32(d), f32(180), f32(180))
	// Right edge line down (integer version)
	procGdipAddPathLine.Call(path, uintptr(x+w), uintptr(y+w/2), uintptr(x+w), uintptr(y+h-w/2))
	// Bottom semicircle
	procGdipAddPathArc.Call(path, f32(fx), f32(fy+fh-d), f32(d), f32(d), f32(0), f32(180))
	procGdipClosePathFigure.Call(path)
	var brush uintptr
	procGdipCreateSolidFill.Call(uintptr(argb), uintptr(unsafe.Pointer(&brush)))
	if brush == 0 {
		return
	}
	defer procGdipDeleteBrush.Call(brush)
	procGdipFillPath.Call(g, brush, path)
}

// ───────────────────── Drawing ─────────────────────

func f32(v float32) uintptr {
	return uintptr(math.Float32bits(v))
}

func min32(a, b uint32) uint32 {
	if a < b {
		return a
	}
	return b
}

func brightenARGB(argb uint32, amount uint32) uint32 {
	a := argb >> 24
	r := (argb >> 16) & 0xFF
	g := (argb >> 8) & 0xFF
	b := argb & 0xFF
	r = min32(r+amount, 255)
	g = min32(g+amount, 255)
	b = min32(b+amount, 255)
	return (a << 24) | (r << 16) | (g << 8) | b
}

func btnColor(baseColor uint32, btnID, hoverBtn, pressBtn int) uint32 {
	if pressBtn == btnID {
		return brightenARGB(baseColor, 40)
	}
	if hoverBtn == btnID {
		return brightenARGB(baseColor, 20)
	}
	return baseColor
}

func (o *Overlay) createDIB() {
	var bmi bitmapInfoHeader
	bmi.BiSize = uint32(unsafe.Sizeof(bmi))
	bmi.BiWidth = o.sc(_OVL_WIDTH)
	bmi.BiHeight = -o.sc(_OVL_HEIGHT) // top-down
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

	// Apply DPI scale transform so all drawing uses logical coordinates
	if o.scale > 1.0 {
		s := float32(o.scale)
		procGdipScaleWorldTransform.Call(g, uintptr(math.Float32bits(s)), uintptr(math.Float32bits(s)), 0)
	}

	// Clear to fully transparent
	procGdipGraphicsClear.Call(g, 0x00000000)

	// Drop shadow (subtle)
	o.drawPillPath(g, 3, 3, 0x30000000)

	// Main pill background — gradient (80% opaque)
	o.drawPillGradient(g, 0, 0, 0xCC122435, 0xCC070F19)

	// Content area starts after cancel button (no icon)
	contentX := int32(_BTN_CANCEL_X + _BTN_SIZE + 16)

	o.mu.Lock()
	state := o.state
	frame := o.frame
	startTime := o.startTime
	pauseAccum := o.pauseAccum
	isPaused := o.paused
	hoverBtn := o.hoverBtn
	pressBtn := o.pressBtn
	maxRecordSec := o.maxRecordSec
	smartMode := o.isSmartMode
	transcribeStart := o.transcribeStart
	estimatedSec := o.estimatedSec
	if isPaused {
		pauseAccum += time.Since(o.pauseStart)
	}
	var levels [_WAVE_BARS]float32
	copy(levels[:], o.levels[:])
	levelIdx := o.levelIdx
	o.mu.Unlock()

	switch state {
	case StateRecording, StatePaused:
		o.paintRecordingULW(g, frame, startTime, pauseAccum, isPaused, levels, levelIdx, contentX, hoverBtn, pressBtn, maxRecordSec)
	case StateTranscribing, StateProcessing:
		o.paintTranscribingULW(g, frame, contentX, hoverBtn, pressBtn, smartMode, transcribeStart, estimatedSec)
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
	sz := sizeT{o.sc(_OVL_WIDTH), o.sc(_OVL_HEIGHT)}

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

func (o *Overlay) drawPillGradient(g uintptr, offsetX, offsetY int32, topColor, bottomColor uint32) {
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

	type gpRect struct {
		X, Y, Width, Height int32
	}
	rect := gpRect{X: int32(x), Y: int32(y), Width: int32(w), Height: int32(h)}
	var brush uintptr
	procGdipCreateLineBrushFromRectI.Call(
		uintptr(unsafe.Pointer(&rect)),
		uintptr(topColor),
		uintptr(bottomColor),
		1, // LinearGradientModeVertical
		0, // WrapModeTile
		uintptr(unsafe.Pointer(&brush)),
	)
	if brush != 0 {
		defer procGdipDeleteBrush.Call(brush)
		procGdipFillPath.Call(g, brush, path)
	}
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

// measureGdipTextWidth measures the rendered width of text using GDI+.
func (o *Overlay) measureGdipTextWidth(g uintptr, text string, font uintptr) float32 {
	if font == 0 || o.gdipStrFmt == 0 {
		return 0
	}
	utf16, _ := windows.UTF16FromString(text)
	layout := gdipRectF{X: 0, Y: 0, Width: 1000, Height: 100}
	var bbox gdipRectF
	procGdipMeasureString.Call(g,
		uintptr(unsafe.Pointer(&utf16[0])),
		uintptr(len(utf16)-1),
		font,
		uintptr(unsafe.Pointer(&layout)),
		o.gdipStrFmt,
		uintptr(unsafe.Pointer(&bbox)),
		0, 0)
	return bbox.Width
}

func (o *Overlay) paintRecordingULW(g uintptr, frame int, start time.Time, pauseAccum time.Duration, isPaused bool, levels [_WAVE_BARS]float32, levelIdx int, contentX int32, hoverBtn, pressBtn int, maxRecordSec int) {
	cy := int32(_OVL_HEIGHT / 2)

	// Dashboard button (dark circle with grid icon) — far left
	gdipFillCircleG(g, btnColor(0xFF1E2A36, 1, hoverBtn, pressBtn), _BTN_DASH_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
	o.drawGridIcon(g, _BTN_DASH_X, int32(cy)-_BTN_SIZE/2)

	// Cancel button (dark circle with ✕)
	gdipFillCircleG(g, btnColor(0xFF1E2A36, 2, hoverBtn, pressBtn), _BTN_CANCEL_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
	o.drawXIcon(g, _BTN_CANCEL_X, int32(cy)-_BTN_SIZE/2)

	// Pulsing recording dot (next to timer)
	if isPaused {
		gdipFillCircleG(g, 0x80FF3C3C, contentX, cy, 5)
	} else {
		pulse := float64(frame) * 0.12
		alpha := uint32(180 + int(math.Sin(pulse)*75))
		if alpha > 255 {
			alpha = 255
		}
		argb := (alpha << 24) | 0x00FF3C3C
		gdipFillCircleG(g, argb, contentX, cy, 5)
	}

	// Elapsed timer (excludes paused time) — prominent, no text label
	elapsed := time.Since(start) - pauseAccum
	if elapsed < 0 {
		elapsed = 0
	}
	secs := int(elapsed.Seconds())
	timer := fmt.Sprintf("%d:%02d", secs/60, secs%60)
	timerX := float32(contentX + 10)
	timerColor := uint32(0xFFFFFFFF) // white (normal)
	if maxRecordSec > 0 {
		remaining := time.Duration(maxRecordSec)*time.Second - elapsed
		switch {
		case remaining <= 10*time.Second:
			timerColor = 0xFFEF4444 // red
		case remaining <= 30*time.Second:
			timerColor = 0xFFF97316 // orange
		case remaining <= 60*time.Second:
			timerColor = 0xFFEAB308 // yellow
		}
	}
	o.drawGdipText(g, timer, timerX, float32(cy)-10, 60, o.gdipFontMain, timerColor)

	// Scrolling waveform bars — centered between timer and pause button
	waveStart := int32(timerX + 56)
	waveEnd := int32(_BTN_PAUSE_X - 12)
	waveTotal := int32(_WAVE_BARS) * (_WAVE_BAR_W + _WAVE_GAP)
	waveX := waveStart + (waveEnd-waveStart-waveTotal)/2
	if waveX < waveStart {
		waveX = waveStart
	}

	for i := 0; i < _WAVE_BARS; i++ {
		idx := (levelIdx + i) % _WAVE_BARS
		lvl := levels[idx]
		if isPaused {
			lvl = 0
		}
		amp := math.Sqrt(float64(lvl)) * _WAVE_AMP
		if amp > 1.0 {
			amp = 1.0
		}
		h := int32(amp * 44.0)
		if h < 3 {
			h = 3
		}
		x := waveX + int32(i)*(_WAVE_BAR_W+_WAVE_GAP)
		y1 := cy - h/2
		y2 := cy + h/2
		if h > 6 {
			gdipFillRoundedBar(g, 0xE022D3EE, x, y1, _WAVE_BAR_W, y2-y1)
		} else {
			gdipFillRoundedBar(g, 0x80226688, x, y1, _WAVE_BAR_W, y2-y1)
		}
	}

	// Pause button — dark teal circle
	gdipFillCircleG(g, btnColor(0xFF0E3D4F, 3, hoverBtn, pressBtn), _BTN_PAUSE_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
	if isPaused {
		o.drawPlayIcon(g, _BTN_PAUSE_X, int32(cy)-_BTN_SIZE/2)
	} else {
		o.drawPauseIcon(g, _BTN_PAUSE_X, int32(cy)-_BTN_SIZE/2)
	}

	// Stop/confirm button — red circle (matching reference design)
	gdipFillCircleG(g, btnColor(0xFFE53935, 4, hoverBtn, pressBtn), _BTN_CONFIRM_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
	o.drawStopIcon(g, _BTN_CONFIRM_X, int32(cy)-_BTN_SIZE/2)

}

// drawXIcon draws an ✕ icon using GDI+ lines with round caps.
func (o *Overlay) drawXIcon(g uintptr, bx, by int32) {
	var pen uintptr
	procGdipCreatePen1.Call(uintptr(0xCCAAAABB), uintptr(math.Float32bits(2.5)), 2, uintptr(unsafe.Pointer(&pen)))
	if pen == 0 {
		return
	}
	defer procGdipDeletePen.Call(pen)
	procGdipSetPenLineCap197819.Call(pen, 2, 2, 0)
	cx := bx + _BTN_SIZE/2
	cy := by + _BTN_SIZE/2
	s := int32(7)
	procGdipDrawLineI.Call(g, pen, uintptr(cx-s), uintptr(cy-s), uintptr(cx+s), uintptr(cy+s))
	procGdipDrawLineI.Call(g, pen, uintptr(cx+s), uintptr(cy-s), uintptr(cx-s), uintptr(cy+s))
}

// drawGridIcon draws a 2×2 grid icon (dashboard) using GDI+ filled rectangles.
func (o *Overlay) drawGridIcon(g uintptr, bx, by int32) {
	cx := bx + _BTN_SIZE/2
	cy := by + _BTN_SIZE/2
	cell := int32(5)                                                   // cell size
	gap := int32(3)                                                    // gap between cells
	gdipFillRectG(g, 0xCCAABBCC, cx-gap-cell, cy-gap-cell, cell, cell) // top-left
	gdipFillRectG(g, 0xCCAABBCC, cx+gap, cy-gap-cell, cell, cell)      // top-right
	gdipFillRectG(g, 0xCCAABBCC, cx-gap-cell, cy+gap, cell, cell)      // bottom-left
	gdipFillRectG(g, 0xCCAABBCC, cx+gap, cy+gap, cell, cell)           // bottom-right
}

// drawStopIcon draws a ■ stop square icon using GDI+ filled rounded rect.
func (o *Overlay) drawStopIcon(g uintptr, bx, by int32) {
	cx := bx + _BTN_SIZE/2
	cy := by + _BTN_SIZE/2
	s := int32(7)
	gdipFillRectG(g, 0xFFFFFFFF, cx-s, cy-s, s*2, s*2)
}

// drawPauseIcon draws ❚❚ icon (Lucide-style) using GDI+ filled rectangles.
func (o *Overlay) drawPauseIcon(g uintptr, bx, by int32) {
	cx := bx + _BTN_SIZE/2
	cy := by + _BTN_SIZE/2
	barW := int32(4)
	barH := int32(14)
	gap := int32(3)
	gdipFillRectG(g, 0xFFFFFFFF, cx-gap-barW, cy-barH/2, barW, barH)
	gdipFillRectG(g, 0xFFFFFFFF, cx+gap, cy-barH/2, barW, barH)
}

// drawPlayIcon draws ▶ icon (Lucide-style) using GDI+ filled path.
func (o *Overlay) drawPlayIcon(g uintptr, bx, by int32) {
	cx := bx + _BTN_SIZE/2
	cy := by + _BTN_SIZE/2
	var path uintptr
	procGdipCreatePath.Call(0, uintptr(unsafe.Pointer(&path)))
	if path == 0 {
		return
	}
	defer procGdipDeletePath.Call(path)
	// Larger triangle pointing right, slightly offset for optical centering
	x1, y1 := cx-5, cy-9 // top-left
	x2, y2 := cx+9, cy   // right-center
	x3, y3 := cx-5, cy+9 // bottom-left
	procGdipAddPathLine.Call(path, uintptr(x1), uintptr(y1), uintptr(x2), uintptr(y2))
	procGdipAddPathLine.Call(path, uintptr(x2), uintptr(y2), uintptr(x3), uintptr(y3))
	procGdipClosePathFigure.Call(path)
	var brush uintptr
	procGdipCreateSolidFill.Call(uintptr(0xFFFFFFFF), uintptr(unsafe.Pointer(&brush)))
	if brush != 0 {
		defer procGdipDeleteBrush.Call(brush)
		procGdipFillPath.Call(g, brush, path)
	}
}

func (o *Overlay) paintTranscribingULW(g uintptr, frame int, contentX int32, hoverBtn, pressBtn int, smartMode bool, transcribeStart time.Time, estimatedSec float64) {
	cy := int32(_OVL_HEIGHT / 2)

	// Cancel button (dark circle with ✕)
	gdipFillCircleG(g, btnColor(0xFF1E2A36, 2, hoverBtn, pressBtn), _BTN_CANCEL_X+_BTN_SIZE/2, cy, _BTN_SIZE/2)
	o.drawXIcon(g, _BTN_CANCEL_X, int32(cy)-_BTN_SIZE/2)

	// Choose label and spinner color based on Smart Mode
	labelKey := "overlay.transcribing"
	spinnerColor := uint32(0x0022D3EE) // cyan (BGR for #22D3EE)
	if smartMode {
		labelKey = "overlay.smart_processing"
		spinnerColor = 0x0000B4FF // gold (BGR for #FFB400)
	}

	// Build text with animated dots
	text := T(labelKey)
	for len(text) > 0 && text[len(text)-1] == '.' {
		text = text[:len(text)-1]
	}
	n := (frame / 15) % 4
	for i := 0; i < n; i++ {
		text += "."
	}

	// Append time estimate if available
	timeText := ""
	if estimatedSec > 0 && !transcribeStart.IsZero() {
		elapsed := time.Since(transcribeStart).Seconds()
		remaining := estimatedSec - elapsed
		if remaining > 1 {
			secs := int(remaining + 0.5) // round up
			timeText = fmt.Sprintf(" ~%ds", secs)
		} else if remaining > -5 {
			// Estimate expired but not too long ago — show "almost done"
			timeText = " ..."
		}
	}

	// Spinner geometry
	const numDots = 8
	const spinR = 10
	const dotR = 3
	const gap = 16
	spinnerW := float32(spinR*2 + 2)

	// Center spinner+gap+text group in full overlay width
	fullText := text + timeText
	textW := o.measureGdipTextWidth(g, fullText, o.gdipFontMain)
	if textW < 80 {
		textW = 80
	}
	groupW := spinnerW + float32(gap) + textW
	groupX := (float32(_OVL_WIDTH) - groupW) / 2

	spinCx := int32(groupX) + spinR + 1
	spinCy := cy
	angleOffset := float64(frame) * 0.15
	for i := 0; i < numDots; i++ {
		angle := angleOffset + float64(i)*2.0*math.Pi/float64(numDots)
		dx := int32(float64(spinR) * math.Cos(angle))
		dy := int32(float64(spinR) * math.Sin(angle))
		alpha := uint32(60 + (195 * uint32(i) / uint32(numDots-1)))
		argb := (alpha << 24) | spinnerColor
		gdipFillCircleG(g, argb, spinCx+dx, spinCy+dy, dotR)
	}

	// Draw main text
	textX := groupX + spinnerW + float32(gap)
	o.drawGdipText(g, text, textX, float32(cy-10), textW+20, o.gdipFontMain, 0xFFFFFFFF)

	// Draw time estimate in subdued color next to main text
	if timeText != "" {
		mainTextW := o.measureGdipTextWidth(g, text, o.gdipFontMain)
		timeX := textX + mainTextW
		o.drawGdipText(g, timeText, timeX, float32(cy-10), 80, o.gdipFontSmall, 0xAA8899AA)
	}
}

func (o *Overlay) paintErrorULW(g uintptr, contentX int32) {
	text := T("error.no_api_key")
	o.drawGdipText(g, text, float32(contentX), float32(_OVL_HEIGHT/2-10), float32(_OVL_WIDTH-16-contentX), o.gdipFontMain, 0xFFFF3C3C)
}

func (o *Overlay) paintCopiedULW(g uintptr, contentX int32) {
	cy := int32(_OVL_HEIGHT / 2)
	text := T("overlay.copied")

	// Center checkmark+gap+text group in full overlay width
	const circleD = 16 // checkmark circle diameter
	const gap = 8
	textW := o.measureGdipTextWidth(g, text, o.gdipFontMain)
	if textW < 80 {
		textW = 80
	}
	groupW := float32(circleD+gap) + textW
	groupX := (float32(_OVL_WIDTH) - groupW) / 2

	gdipFillCircleG(g, 0xFF34C759, int32(groupX)+circleD/2, cy, circleD/2)
	o.drawGdipText(g, "\u2713", groupX+1, float32(cy-10), float32(circleD), o.gdipFontSmall, 0xFFFFFFFF)
	o.drawGdipText(g, text, groupX+float32(circleD+gap), float32(cy-10), textW+20, o.gdipFontMain, 0xFF34C759)
}
