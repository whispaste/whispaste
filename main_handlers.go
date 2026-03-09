package main

import (
	"unsafe"

	"golang.org/x/sys/windows"
)

func setAppUserModelID() {
	shell32 := windows.NewLazySystemDLL("shell32.dll")
	proc := shell32.NewProc("SetCurrentProcessExplicitAppUserModelID")
	appID, _ := windows.UTF16PtrFromString("WhisPaste.WhisPaste")
	hr, _, _ := proc.Call(uintptr(unsafe.Pointer(appID)))
	if hr != 0 {
		logWarn("SetCurrentProcessExplicitAppUserModelID failed: HRESULT 0x%X", hr)
	} else {
		logDebug("AUMID set: WhisPaste.WhisPaste")
	}
}

func enableDarkMode() {
	dll, err := windows.LoadDLL("uxtheme.dll")
	if err != nil {
		return
	}
	defer dll.Release()
	if proc, err := dll.FindProcByOrdinal(135); err == nil {
		proc.Call(1)
	}
	if proc, err := dll.FindProcByOrdinal(136); err == nil {
		proc.Call()
	}
}

func detectAndSetLanguage() {
	kernel32 := windows.NewLazySystemDLL("kernel32.dll")
	proc := kernel32.NewProc("GetUserDefaultUILanguage")
	langID, _, _ := proc.Call()
	primaryLang := langID & 0xFF
	if primaryLang == 0x07 {
		SetLanguage("de")
	}
}

func showError(msg string) {
	user32 := windows.NewLazySystemDLL("user32.dll")
	proc := user32.NewProc("MessageBoxW")
	title, _ := windows.UTF16PtrFromString(AppName)
	text, _ := windows.UTF16PtrFromString(msg)
	proc.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
