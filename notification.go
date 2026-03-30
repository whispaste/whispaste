//go:build windows

package main

import (
	"os"
	"path/filepath"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// COM GUIDs for shortcut creation
var (
	clsidShellLink    = windows.GUID{Data1: 0x00021401, Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
	iidIShellLinkW    = windows.GUID{Data1: 0x000214F9, Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
	iidIPersistFile   = windows.GUID{Data1: 0x0000010B, Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
	iidIPropertyStore = windows.GUID{Data1: 0x886D8EEB, Data2: 0x8CF2, Data3: 0x4446, Data4: [8]byte{0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99}}
	pkeyAUMID_fmtid   = windows.GUID{Data1: 0x9F4C2855, Data2: 0x9F79, Data3: 0x4B39, Data4: [8]byte{0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}
)

var (
	ole32            = windows.NewLazySystemDLL("ole32.dll")
	procCoCreateInst = ole32.NewProc("CoCreateInstance")
)

// COM vtable structs — fields ordered per Windows SDK.

type iShellLinkWVtbl struct {
	queryInterface      uintptr
	addRef              uintptr
	release             uintptr
	getPath             uintptr
	getIDList           uintptr
	setIDList           uintptr
	getDescription      uintptr
	setDescription      uintptr // index 7
	getWorkingDirectory uintptr
	setWorkingDirectory uintptr
	getArguments        uintptr
	setArguments        uintptr
	getHotkey           uintptr
	setHotkey           uintptr
	getShowCmd          uintptr
	setShowCmd          uintptr
	getIconLocation     uintptr
	setIconLocation     uintptr
	setRelativePath     uintptr
	resolve             uintptr
	setPath             uintptr // index 20
}
type iShellLinkW struct{ vtbl *iShellLinkWVtbl }

type iPersistFileVtbl struct {
	queryInterface uintptr
	addRef         uintptr
	release        uintptr
	getClassID     uintptr // IPersist
	isDirty        uintptr
	load           uintptr
	save           uintptr // index 6
	saveCompleted  uintptr
	getCurFile     uintptr
}
type iPersistFile struct{ vtbl *iPersistFileVtbl }

type iPropertyStoreVtbl struct {
	queryInterface uintptr
	addRef         uintptr
	release        uintptr
	getCount       uintptr
	getAt          uintptr
	getValue       uintptr
	setValue       uintptr // index 6
	commit         uintptr // index 7
}
type iPropertyStore struct{ vtbl *iPropertyStoreVtbl }

type propertyKey struct {
	fmtid windows.GUID
	pid   uint32
}

type propVariant struct {
	vt     uint16
	_pad   [3]uint16
	val    uintptr
	_extra uintptr
}

const _VT_LPWSTR = 31

// ensureStartMenuShortcut creates a Start Menu shortcut with the AUMID so
// Windows 10/11 toast notifications (from Shell_NotifyIconW NIF_INFO with
// NOTIFYICON_VERSION_4) are actually displayed. Without this shortcut,
// Shell_NotifyIconW may return success while silently dropping the toast.
func ensureStartMenuShortcut() {
	exe, err := os.Executable()
	if err != nil {
		logWarn("ensureStartMenuShortcut: Executable() failed: %v", err)
		return
	}
	exe, _ = filepath.Abs(exe)

	appdata := os.Getenv("APPDATA")
	if appdata == "" {
		return
	}
	lnkPath := filepath.Join(appdata, "Microsoft", "Windows", "Start Menu", "Programs", "WhisPaste.lnk")

	if _, err := os.Stat(lnkPath); err == nil {
		logDebug("ensureStartMenuShortcut: shortcut exists, skipping")
		return
	}

	if err := windows.CoInitializeEx(0, windows.COINIT_APARTMENTTHREADED); err != nil {
		// S_FALSE (Errno 1): COM already initialized with same threading model — continue, no uninit
		// RPC_E_CHANGED_MODE: COM initialized with different model — still usable
		if err != windows.Errno(1) && err != windows.Errno(0x80010106) {
			logWarn("ensureStartMenuShortcut: CoInitializeEx: %v", err)
			return
		}
	} else {
		defer windows.CoUninitialize()
	}

	// Create IShellLinkW via COM
	var pslRaw unsafe.Pointer
	hr, _, _ := procCoCreateInst.Call(
		uintptr(unsafe.Pointer(&clsidShellLink)),
		0,
		0x1, // CLSCTX_INPROC_SERVER
		uintptr(unsafe.Pointer(&iidIShellLinkW)),
		uintptr(unsafe.Pointer(&pslRaw)),
	)
	if hr != 0 || pslRaw == nil {
		logWarn("ensureStartMenuShortcut: CoCreateInstance HRESULT=0x%X", hr)
		return
	}
	psl := (*iShellLinkW)(pslRaw)
	defer syscall.SyscallN(psl.vtbl.release, uintptr(pslRaw))

	// SetPath
	exePtr, _ := windows.UTF16PtrFromString(exe)
	hr, _, _ = syscall.SyscallN(psl.vtbl.setPath, uintptr(pslRaw), uintptr(unsafe.Pointer(exePtr)))
	if hr != 0 {
		logWarn("ensureStartMenuShortcut: SetPath HRESULT=0x%X", hr)
		return
	}

	// SetDescription
	descPtr, _ := windows.UTF16PtrFromString("WhisPaste – Speech to Text")
	syscall.SyscallN(psl.vtbl.setDescription, uintptr(pslRaw), uintptr(unsafe.Pointer(descPtr)))

	// QI for IPropertyStore → set AUMID
	var ppsRaw unsafe.Pointer
	hr, _, _ = syscall.SyscallN(psl.vtbl.queryInterface, uintptr(pslRaw),
		uintptr(unsafe.Pointer(&iidIPropertyStore)), uintptr(unsafe.Pointer(&ppsRaw)))
	if hr != 0 || ppsRaw == nil {
		logWarn("ensureStartMenuShortcut: QI(IPropertyStore) HRESULT=0x%X", hr)
		return
	}
	pps := (*iPropertyStore)(ppsRaw)
	defer syscall.SyscallN(pps.vtbl.release, uintptr(ppsRaw))

	aumidPtr, _ := windows.UTF16PtrFromString("WhisPaste.WhisPaste")
	pkey := propertyKey{fmtid: pkeyAUMID_fmtid, pid: 5}
	pv := propVariant{vt: _VT_LPWSTR, val: uintptr(unsafe.Pointer(aumidPtr))}

	hr, _, _ = syscall.SyscallN(pps.vtbl.setValue, uintptr(ppsRaw),
		uintptr(unsafe.Pointer(&pkey)), uintptr(unsafe.Pointer(&pv)))
	if hr != 0 {
		logWarn("ensureStartMenuShortcut: SetValue(AUMID) HRESULT=0x%X", hr)
		return
	}
	hr, _, _ = syscall.SyscallN(pps.vtbl.commit, uintptr(ppsRaw))
	if hr != 0 {
		logWarn("ensureStartMenuShortcut: Commit HRESULT=0x%X", hr)
		return
	}

	// QI for IPersistFile → save .lnk
	var ppfRaw unsafe.Pointer
	hr, _, _ = syscall.SyscallN(psl.vtbl.queryInterface, uintptr(pslRaw),
		uintptr(unsafe.Pointer(&iidIPersistFile)), uintptr(unsafe.Pointer(&ppfRaw)))
	if hr != 0 || ppfRaw == nil {
		logWarn("ensureStartMenuShortcut: QI(IPersistFile) HRESULT=0x%X", hr)
		return
	}
	ppf := (*iPersistFile)(ppfRaw)
	defer syscall.SyscallN(ppf.vtbl.release, uintptr(ppfRaw))

	lnkPtr, _ := windows.UTF16PtrFromString(lnkPath)
	hr, _, _ = syscall.SyscallN(ppf.vtbl.save, uintptr(ppfRaw), uintptr(unsafe.Pointer(lnkPtr)), 1)
	if hr != 0 {
		logWarn("ensureStartMenuShortcut: Save HRESULT=0x%X", hr)
		return
	}

	// Verify the .lnk file was actually written to disk
	if _, err := os.Stat(lnkPath); err != nil {
		logWarn("ensureStartMenuShortcut: file not found after Save: %v", err)
		return
	}

	logInfo("Created Start Menu shortcut with AUMID for toast notifications: %s", lnkPath)
}
