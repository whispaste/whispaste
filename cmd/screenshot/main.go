package main

import (
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"math"
	"os"
)

const (
	width  = 600
	height = 100
	radius = 50
)

// Whispaste brand colors
var (
	accentCyan   = color.RGBA{34, 211, 238, 255}
	darkTeal     = color.RGBA{14, 116, 144, 255}
	recordingRed = color.RGBA{255, 60, 60, 255}
	bgDark       = color.RGBA{30, 32, 38, 240}
	successGreen = color.RGBA{52, 199, 89, 255}
	textWhite    = color.RGBA{255, 255, 255, 220}
	dimWhite     = color.RGBA{255, 255, 255, 100}
)

type overlayState struct {
	name       string
	dotColor   color.RGBA
	labelRects []labelRect // simplified text represented as small colored blocks
}

type labelRect struct {
	x, y, w, h int
	c           color.Color
}

func main() {
	if err := os.MkdirAll("screenshots", 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create screenshots dir: %v\n", err)
		os.Exit(1)
	}

	states := []overlayState{
		{
			name:     "recording",
			dotColor: recordingRed,
		},
		{
			name:     "paused",
			dotColor: color.RGBA{255, 60, 60, 128},
		},
		{
			name:     "transcribing",
			dotColor: accentCyan,
		},
		{
			name:     "success",
			dotColor: successGreen,
		},
	}

	for _, s := range states {
		img := renderOverlay(s)
		path := fmt.Sprintf("screenshots/%s.png", s.name)
		f, err := os.Create(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to create %s: %v\n", path, err)
			os.Exit(1)
		}
		if err := png.Encode(f, img); err != nil {
			f.Close()
			fmt.Fprintf(os.Stderr, "Failed to encode %s: %v\n", path, err)
			os.Exit(1)
		}
		f.Close()
		fmt.Printf("Generated %s\n", path)
	}
}

func renderOverlay(s overlayState) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// Pill-shaped background
	drawRoundedRect(img, 0, 0, width, height, radius, bgDark)

	// Subtle border glow
	drawRoundedRectOutline(img, 0, 0, width, height, radius, color.RGBA{255, 255, 255, 20})

	// App icon: cyan circle on the left
	drawCircle(img, 50, height/2, 18, accentCyan)
	// Inner icon detail: small dark circle to simulate the "W" icon area
	drawCircle(img, 50, height/2, 10, color.RGBA{20, 24, 28, 255})
	// Tiny accent dot inside
	drawCircle(img, 50, height/2, 4, accentCyan)

	switch s.name {
	case "recording":
		renderRecording(img, s)
	case "paused":
		renderPaused(img, s)
	case "transcribing":
		renderTranscribing(img)
	case "success":
		renderSuccess(img)
	}

	return img
}

func renderRecording(img *image.RGBA, s overlayState) {
	// Pulsing recording dot
	drawCircle(img, 92, 30, 8, s.dotColor)
	drawCircle(img, 92, 30, 5, color.RGBA{255, 100, 100, 255})

	// "Recording" label (simulated as a row of small rectangles)
	drawTextBlock(img, 108, 24, "RECORDING", textWhite)

	// Timer display: "0:12" style
	drawTextBlock(img, 92, 62, "0:12", dimWhite)

	// Waveform bars
	drawWaveform(img, 180, true)

	// Control buttons on the right
	drawControlButtons(img, true, false)
}

func renderPaused(img *image.RGBA, s overlayState) {
	// Dim recording dot
	drawCircle(img, 92, 30, 8, s.dotColor)

	// "Paused" label
	drawTextBlock(img, 108, 24, "PAUSED", dimWhite)

	// Timer
	drawTextBlock(img, 92, 62, "0:08", dimWhite)

	// Flat waveform (paused)
	drawWaveform(img, 180, false)

	// Control buttons (resume state)
	drawControlButtons(img, false, false)
}

func renderTranscribing(img *image.RGBA) {
	// Spinner
	drawSpinner(img, 120, height/2)

	// "Transcribing..." label
	drawTextBlock(img, 150, 38, "TRANSCRIBING...", accentCyan)

	// Progress bar
	drawRoundedRect(img, 150, 60, 280, 6, 3, color.RGBA{40, 44, 52, 255})
	drawRoundedRect(img, 150, 60, 180, 6, 3, accentCyan)

	// No control buttons during transcription, just a cancel X
	drawCircle(img, width-50, height/2, 17, color.RGBA{60, 64, 72, 255})
	// X mark
	drawRect(img, width-54, height/2-1, 8, 2, dimWhite)
}

func renderSuccess(img *image.RGBA) {
	// Success checkmark circle
	drawCircle(img, 120, height/2, 18, successGreen)
	// Checkmark (simplified as two small rectangles at angles)
	drawRect(img, 113, height/2, 6, 2, color.RGBA{255, 255, 255, 255})
	drawRect(img, 117, height/2-4, 2, 8, color.RGBA{255, 255, 255, 255})

	// "Pasted!" label
	drawTextBlock(img, 150, 32, "PASTED!", successGreen)

	// Subtitle
	drawTextBlock(img, 150, 58, "247 CHARACTERS", dimWhite)
}

// drawWaveform draws animated-looking waveform bars.
func drawWaveform(img *image.RGBA, startX int, active bool) {
	for i := 0; i < 28; i++ {
		var barH int
		if active {
			// Varying heights to simulate audio waveform
			barH = 6 + int(24*math.Abs(math.Sin(float64(i)*0.7+0.3)))
		} else {
			barH = 3
		}
		x := startX + i*10
		y := height/2 - barH/2

		var barColor color.RGBA
		if active {
			// Gradient from teal to cyan based on position
			t := float64(i) / 28.0
			barColor = color.RGBA{
				uint8(14 + t*20),
				uint8(116 + t*95),
				uint8(144 + t*94),
				200,
			}
		} else {
			barColor = color.RGBA{50, 56, 66, 180}
		}
		drawRect(img, x, y, 4, barH, barColor)
	}
}

// drawSpinner draws a circular spinner with varying opacity dots.
func drawSpinner(img *image.RGBA, cx, cy int) {
	for i := 0; i < 8; i++ {
		angle := float64(i) * math.Pi / 4
		dotX := cx + int(16*math.Cos(angle))
		dotY := cy + int(16*math.Sin(angle))
		alpha := uint8(60 + i*28)
		if alpha > 255 {
			alpha = 255
		}
		drawCircle(img, dotX, dotY, 3, color.RGBA{34, 211, 238, alpha})
	}
}

// drawControlButtons draws the confirm/pause/cancel buttons.
func drawControlButtons(img *image.RGBA, showPause, showResume bool) {
	// Confirm button (cyan filled circle with checkmark)
	drawCircle(img, width-50, height/2, 18, accentCyan)
	drawRect(img, width-57, height/2, 6, 2, color.RGBA{255, 255, 255, 255})
	drawRect(img, width-53, height/2-4, 2, 8, color.RGBA{255, 255, 255, 255})

	// Pause/Resume button
	btnColor := darkTeal
	drawCircle(img, width-100, height/2, 18, btnColor)
	if showPause {
		// Pause icon: two vertical bars
		drawRect(img, width-105, height/2-6, 3, 12, textWhite)
		drawRect(img, width-98, height/2-6, 3, 12, textWhite)
	} else {
		// Play/resume icon: triangle approximation
		drawRect(img, width-104, height/2-6, 3, 12, textWhite)
		drawRect(img, width-101, height/2-4, 3, 8, textWhite)
		drawRect(img, width-98, height/2-2, 3, 4, textWhite)
	}

	// Cancel button (dark circle with X)
	drawCircle(img, width-150, height/2, 18, color.RGBA{60, 64, 72, 255})
	drawRect(img, width-155, height/2-1, 10, 2, dimWhite)
}

// drawTextBlock simulates text by drawing a row of small rectangles per character.
func drawTextBlock(img *image.RGBA, x, y int, text string, c color.Color) {
	cx := x
	for _, ch := range text {
		if ch == ' ' {
			cx += 4
			continue
		}
		if ch == '.' {
			drawRect(img, cx, y+8, 2, 2, c)
			cx += 5
			continue
		}
		if ch == ':' {
			drawRect(img, cx, y+2, 2, 2, c)
			drawRect(img, cx, y+7, 2, 2, c)
			cx += 5
			continue
		}
		// Each character: small block
		charW := 6
		charH := 10
		drawRect(img, cx, y, charW, charH, c)
		cx += charW + 2
	}
}

// drawRoundedRect draws a filled rounded rectangle.
func drawRoundedRect(img *image.RGBA, x, y, w, h, r int, c color.Color) {
	if r > h/2 {
		r = h / 2
	}
	if r > w/2 {
		r = w / 2
	}
	for py := y; py < y+h; py++ {
		for px := x; px < x+w; px++ {
			dx, dy := 0, 0
			if px < x+r {
				dx = x + r - px
			}
			if px > x+w-r-1 {
				dx = px - (x + w - r - 1)
			}
			if py < y+r {
				dy = y + r - py
			}
			if py > y+h-r-1 {
				dy = py - (y + h - r - 1)
			}
			if dx > 0 && dy > 0 {
				if dx*dx+dy*dy > r*r {
					continue
				}
			}
			img.Set(px, py, c)
		}
	}
}

// drawRoundedRectOutline draws just the outline of a rounded rectangle.
func drawRoundedRectOutline(img *image.RGBA, x, y, w, h, r int, c color.Color) {
	if r > h/2 {
		r = h / 2
	}
	if r > w/2 {
		r = w / 2
	}
	for py := y; py < y+h; py++ {
		for px := x; px < x+w; px++ {
			dx, dy := 0, 0
			if px < x+r {
				dx = x + r - px
			}
			if px > x+w-r-1 {
				dx = px - (x + w - r - 1)
			}
			if py < y+r {
				dy = y + r - py
			}
			if py > y+h-r-1 {
				dy = py - (y + h - r - 1)
			}

			isEdge := false
			if dx > 0 && dy > 0 {
				dist := dx*dx + dy*dy
				if dist > r*r {
					continue
				}
				if dist > (r-2)*(r-2) {
					isEdge = true
				}
			} else {
				if px <= x+1 || px >= x+w-2 || py <= y+1 || py >= y+h-2 {
					isEdge = true
				}
			}
			if isEdge {
				img.Set(px, py, c)
			}
		}
	}
}

func drawCircle(img *image.RGBA, cx, cy, r int, c color.Color) {
	for py := cy - r; py <= cy+r; py++ {
		for px := cx - r; px <= cx+r; px++ {
			dx := px - cx
			dy := py - cy
			if dx*dx+dy*dy <= r*r {
				img.Set(px, py, c)
			}
		}
	}
}

func drawRect(img *image.RGBA, x, y, w, h int, c color.Color) {
	draw.Draw(img, image.Rect(x, y, x+w, y+h), &image.Uniform{c}, image.Point{}, draw.Over)
}
