package main

import (
	"github.com/getlantern/systray"
)

// AppTray manages the system tray icon and menu.
type AppTray struct {
	onSettings func()
	onQuit     func()
}

// NewAppTray creates a tray manager. Callbacks are invoked on menu clicks.
func NewAppTray(onSettings func(), onQuit func()) *AppTray {
	return &AppTray{
		onSettings: onSettings,
		onQuit:     onQuit,
	}
}

// Run starts the system tray. This blocks the calling goroutine.
func (t *AppTray) Run() {
	systray.Run(t.onReady, t.onExit)
}

// Quit terminates the system tray event loop.
func (t *AppTray) Quit() {
	systray.Quit()
}

func (t *AppTray) onReady() {
	systray.SetIcon(trayIconData())
	systray.SetTitle(AppName)
	systray.SetTooltip(T("tray.tooltip"))

	mSettings := systray.AddMenuItem(T("tray.settings"), T("tray.settings"))
	mAbout := systray.AddMenuItem(T("tray.about"), T("tray.about"))
	systray.AddSeparator()
	mQuit := systray.AddMenuItem(T("tray.quit"), T("tray.quit"))

	go func() {
		for {
			select {
			case <-mSettings.ClickedCh:
				if t.onSettings != nil {
					t.onSettings()
				}
			case <-mAbout.ClickedCh:
				if t.onSettings != nil {
					t.onSettings()
				}
			case <-mQuit.ClickedCh:
				if t.onQuit != nil {
					t.onQuit()
				}
				return
			}
		}
	}()
}

func (t *AppTray) onExit() {}

// trayIconData returns a minimal 16x16 ICO-format icon (blue microphone glyph).
// In production, this would be replaced with a proper embedded .ico file.
func trayIconData() []byte {
	// Minimal 16x16 32-bit BMP ICO with a simple microphone shape
	// This is a valid ICO file structure with a blue (#0078D4) mic on transparent bg
	width, height := 16, 16
	bmpSize := width * height * 4
	ico := make([]byte, 0, 22+40+bmpSize)

	// ICO header (6 bytes)
	ico = append(ico, 0, 0) // reserved
	ico = append(ico, 1, 0) // type = ICO
	ico = append(ico, 1, 0) // count = 1

	// ICO directory entry (16 bytes)
	ico = append(ico, byte(width), byte(height)) // w, h
	ico = append(ico, 0)                         // colors
	ico = append(ico, 0)                         // reserved
	ico = append(ico, 1, 0)                      // planes
	ico = append(ico, 32, 0)                     // bpp
	dataSize := uint32(40 + bmpSize)
	ico = append(ico,
		byte(dataSize), byte(dataSize>>8),
		byte(dataSize>>16), byte(dataSize>>24),
	)
	ico = append(ico, 22, 0, 0, 0) // offset = 22

	// BITMAPINFOHEADER (40 bytes)
	ico = append(ico,
		40, 0, 0, 0, // size
		byte(width), 0, 0, 0, // width
		byte(height*2), 0, 0, 0, // height (2x for ICO)
		1, 0, // planes
		32, 0, // bpp
		0, 0, 0, 0, // compression
		byte(bmpSize), byte(bmpSize>>8), byte(bmpSize>>16), byte(bmpSize>>24),
		0, 0, 0, 0, // x ppm
		0, 0, 0, 0, // y ppm
		0, 0, 0, 0, // colors
		0, 0, 0, 0, // important colors
	)

	// Pixel data (BGRA, bottom-up)
	// Draw a simple microphone icon: circle at top, stem, base
	pixels := make([]byte, bmpSize)
	accent := [4]byte{0xD4, 0x78, 0x00, 0xFF} // Blue #0078D4 in BGRA

	setPixel := func(x, y int) {
		// ICO bitmaps are bottom-up
		row := (height - 1 - y)
		off := (row*width + x) * 4
		if off >= 0 && off+3 < len(pixels) {
			copy(pixels[off:off+4], accent[:])
		}
	}

	// Microphone body (rounded rect, cols 6-9, rows 2-8)
	for y := 2; y <= 8; y++ {
		for x := 6; x <= 9; x++ {
			setPixel(x, y)
		}
	}
	// Mic top curve
	setPixel(7, 1)
	setPixel(8, 1)
	// Stem
	for y := 9; y <= 11; y++ {
		setPixel(7, y)
		setPixel(8, y)
	}
	// Holder arc
	for x := 5; x <= 10; x++ {
		setPixel(x, 9)
	}
	setPixel(5, 8)
	setPixel(10, 8)
	setPixel(5, 7)
	setPixel(10, 7)
	// Base
	for x := 5; x <= 10; x++ {
		setPixel(x, 12)
	}

	ico = append(ico, pixels...)
	return ico
}
