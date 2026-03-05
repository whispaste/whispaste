package main

import (
	"path/filepath"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	wdUser32              = windows.NewLazySystemDLL("user32.dll")
	procGetWindowThreadPID = wdUser32.NewProc("GetWindowThreadProcessId")
	procGetForegroundWindow = wdUser32.NewProc("GetForegroundWindow")
)

// GetActiveAppName returns the executable name (e.g. "Code.exe") of the
// foreground window's process. Returns "" on failure.
func GetActiveAppName() string {
	hwnd, _, _ := procGetForegroundWindow.Call()
	if hwnd == 0 {
		return ""
	}
	var pid uint32
	procGetWindowThreadPID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid == 0 {
		return ""
	}

	hProc, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return ""
	}
	defer windows.CloseHandle(hProc)

	var buf [260]uint16
	n := uint32(len(buf))
	err = windows.QueryFullProcessImageName(hProc, 0, &buf[0], &n)
	if err != nil {
		return ""
	}
	fullPath := windows.UTF16ToString(buf[:n])
	return strings.ToLower(filepath.Base(fullPath))
}

// ResolveAppPreset checks if there's an app-specific smart mode preset
// for the currently active window. Returns the preset name and true if found.
func ResolveAppPreset(cfg *Config) (string, bool) {
	if !cfg.GetAppDetectionEnabled() {
		return "", false
	}
	appName := GetActiveAppName()
	if appName == "" {
		return "", false
	}
	mappings := cfg.GetAppPresets()
	if preset, ok := mappings[appName]; ok {
		logDebug("App detection: %s → preset %s", appName, preset)
		return preset, true
	}
	return "", false
}
