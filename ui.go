package main

import (
	_ "embed"
	"unsafe"

	"golang.org/x/sys/windows"
)

//go:embed resources/app.ico
var embeddedAppIcon []byte

// setWindowIcon sets the window icon using the embedded .ico resource.
func setWindowIcon(hwndPtr unsafe.Pointer) {
	if hwndPtr == nil {
		return
	}
	hwnd := uintptr(hwndPtr)
	user32 := windows.NewLazySystemDLL("user32.dll")
	createIconFromResourceEx := user32.NewProc("CreateIconFromResourceEx")
	sendMessage := user32.NewProc("SendMessageW")

	const (
		wmSetIcon      = 0x0080
		iconSmall      = 0
		iconBig        = 1
		lrDefaultColor = 0x00000000
	)

	// Extract the first icon from the .ico resource
	if len(embeddedAppIcon) < 22 {
		return
	}
	// ICO header: 2 bytes reserved, 2 bytes type, 2 bytes count
	// Each entry: 16 bytes (w, h, colors, reserved, planes, bpp, size, offset)
	count := int(embeddedAppIcon[4]) | int(embeddedAppIcon[5])<<8
	if count < 1 {
		return
	}

	// Load both small (16x16) and large (32x32) icons
	for _, target := range []struct{ size, wparam uintptr }{{16, iconSmall}, {32, iconBig}} {
		bestIdx, bestSize := -1, uint32(0)
		for i := 0; i < count; i++ {
			off := 6 + i*16
			if off+16 > len(embeddedAppIcon) {
				break
			}
			w := uint32(embeddedAppIcon[off])
			if w == 0 {
				w = 256
			}
			// Find closest match to target size
			diff := int32(w) - int32(target.size)
			if diff < 0 {
				diff = -diff
			}
			bestDiff := int32(bestSize) - int32(target.size)
			if bestDiff < 0 {
				bestDiff = -bestDiff
			}
			if bestIdx < 0 || diff < bestDiff {
				bestIdx = i
				bestSize = w
			}
		}
		if bestIdx < 0 {
			continue
		}
		off := 6 + bestIdx*16
		dataSize := uint32(embeddedAppIcon[off+8]) | uint32(embeddedAppIcon[off+9])<<8 |
			uint32(embeddedAppIcon[off+10])<<16 | uint32(embeddedAppIcon[off+11])<<24
		dataOffset := uint32(embeddedAppIcon[off+12]) | uint32(embeddedAppIcon[off+13])<<8 |
			uint32(embeddedAppIcon[off+14])<<16 | uint32(embeddedAppIcon[off+15])<<24
		if dataOffset+dataSize > uint32(len(embeddedAppIcon)) {
			continue
		}
		iconData := embeddedAppIcon[dataOffset : dataOffset+dataSize]
		hIcon, _, _ := createIconFromResourceEx.Call(
			uintptr(unsafe.Pointer(&iconData[0])),
			uintptr(dataSize),
			1, // fIcon = TRUE
			0x00030000, // version
			uintptr(target.size), uintptr(target.size),
			lrDefaultColor,
		)
		if hIcon != 0 {
			sendMessage.Call(hwnd, wmSetIcon, target.wparam, hIcon)
		}
	}
}
