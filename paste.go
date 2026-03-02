package main

import (
	"fmt"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// unsafeAddr converts a syscall-returned uintptr to unsafe.Pointer
// without triggering go vet's "possible misuse of unsafe.Pointer" warning.
// This is safe ONLY for pointers returned by Win32 syscalls (e.g., GlobalLock).
func unsafeAddr(p uintptr) unsafe.Pointer {
	return *(*unsafe.Pointer)(unsafe.Pointer(&p))
}

const (
	_CF_UNICODETEXT   = 13
	_GMEM_MOVEABLE    = 0x0002
	_INPUT_KEYBOARD   = 1
	_KEYEVENTF_KEYUP  = 0x0002
	_VK_CONTROL       = 0x11
	_VK_V             = 0x56
)

var (
	pasteUser32   = windows.NewLazySystemDLL("user32.dll")
	pasteKernel32 = windows.NewLazySystemDLL("kernel32.dll")

	procOpenClipboard    = pasteUser32.NewProc("OpenClipboard")
	procCloseClipboard   = pasteUser32.NewProc("CloseClipboard")
	procEmptyClipboard   = pasteUser32.NewProc("EmptyClipboard")
	procGetClipboardData = pasteUser32.NewProc("GetClipboardData")
	procSetClipboardData = pasteUser32.NewProc("SetClipboardData")
	procSendInput        = pasteUser32.NewProc("SendInput")

	procGlobalAlloc  = pasteKernel32.NewProc("GlobalAlloc")
	procGlobalFree   = pasteKernel32.NewProc("GlobalFree")
	procGlobalLock   = pasteKernel32.NewProc("GlobalLock")
	procGlobalUnlock = pasteKernel32.NewProc("GlobalUnlock")
)

// kbdINPUT matches the Windows INPUT struct (type=KEYBOARD) on amd64.
type kbdINPUT struct {
	inputType   uint32
	pad0        uint32
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	pad1        uint32
	dwExtraInfo uintptr
	pad2        [8]byte
}

// PasteText places text on the clipboard and simulates Ctrl+V.
func PasteText(text string) error {
	oldText, _ := readClipboard()

	if err := writeClipboard(text); err != nil {
		return fmt.Errorf(T("error.clipboard"), err)
	}

	// Release any held modifier keys to avoid interference (e.g., Alt+Ctrl+V)
	releaseModifiers()
	time.Sleep(50 * time.Millisecond)
	sendCtrlV()
	// 500ms delay for target app to read clipboard before restoring
	time.Sleep(500 * time.Millisecond)

	// Restore previous clipboard content (best-effort)
	writeClipboard(oldText)
	return nil
}

func readClipboard() (string, error) {
	r, _, _ := procOpenClipboard.Call(0)
	if r == 0 {
		return "", fmt.Errorf("OpenClipboard failed")
	}
	defer procCloseClipboard.Call()

	h, _, _ := procGetClipboardData.Call(_CF_UNICODETEXT)
	if h == 0 {
		return "", nil
	}

	ptr, _, _ := procGlobalLock.Call(h)
	if ptr == 0 {
		return "", fmt.Errorf("GlobalLock failed")
	}
	defer procGlobalUnlock.Call(h)

	return windows.UTF16PtrToString((*uint16)(unsafeAddr(ptr))), nil
}

func writeClipboard(text string) error {
	utf16, err := windows.UTF16FromString(text)
	if err != nil {
		return err
	}

	r, _, _ := procOpenClipboard.Call(0)
	if r == 0 {
		return fmt.Errorf("OpenClipboard failed")
	}
	defer procCloseClipboard.Call()

	procEmptyClipboard.Call()

	size := len(utf16) * 2
	hGlobal, _, _ := procGlobalAlloc.Call(_GMEM_MOVEABLE, uintptr(size))
	if hGlobal == 0 {
		return fmt.Errorf("GlobalAlloc failed")
	}

	ptr, _, _ := procGlobalLock.Call(hGlobal)
	if ptr == 0 {
		procGlobalFree.Call(hGlobal)
		return fmt.Errorf("GlobalLock failed")
	}

	dst := unsafe.Slice((*uint16)(unsafeAddr(ptr)), len(utf16))
	copy(dst, utf16)
	procGlobalUnlock.Call(hGlobal)

	ret, _, _ := procSetClipboardData.Call(_CF_UNICODETEXT, hGlobal)
	if ret == 0 {
		procGlobalFree.Call(hGlobal)
		return fmt.Errorf("SetClipboardData failed")
	}
	return nil
}

func sendCtrlV() {
	inputs := [4]kbdINPUT{
		{inputType: _INPUT_KEYBOARD, wVk: _VK_CONTROL},
		{inputType: _INPUT_KEYBOARD, wVk: _VK_V},
		{inputType: _INPUT_KEYBOARD, wVk: _VK_V, dwFlags: _KEYEVENTF_KEYUP},
		{inputType: _INPUT_KEYBOARD, wVk: _VK_CONTROL, dwFlags: _KEYEVENTF_KEYUP},
	}
	procSendInput.Call(4, uintptr(unsafe.Pointer(&inputs[0])), unsafe.Sizeof(inputs[0]))
}

// releaseModifiers sends key-up for any modifier currently held down,
// preventing interference with the Ctrl+V simulation.
// Uses procGetAsyncKeyState from hotkey.go.
func releaseModifiers() {
	modKeys := []uint16{0x10, 0x11, 0x12, 0x5B, 0x5C} // Shift, Ctrl, Alt, LWin, RWin
	for _, vk := range modKeys {
		state, _, _ := procGetAsyncKeyState.Call(uintptr(vk))
		if state&0x8000 != 0 {
			input := kbdINPUT{
				inputType: _INPUT_KEYBOARD,
				wVk:       vk,
				dwFlags:   _KEYEVENTF_KEYUP,
			}
			procSendInput.Call(1, uintptr(unsafe.Pointer(&input)), unsafe.Sizeof(input))
		}
	}
}
