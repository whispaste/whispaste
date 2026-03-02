package main

import (
	"runtime"
	"strings"
	"sync"
	"time"

	"golang.design/x/hotkey"
	"golang.org/x/sys/windows"
)

var (
	hkUser32          = windows.NewLazySystemDLL("user32.dll")
	procGetAsyncKeyState = hkUser32.NewProc("GetAsyncKeyState")
)

// HotkeyManager registers a global hotkey and dispatches recording events.
type HotkeyManager struct {
	cfg       *Config
	onDown    func()
	onUp      func()
	hk        *hotkey.Hotkey
	done      chan struct{}
	closeOnce sync.Once
}

// NewHotkeyManager creates a manager that calls onDown/onUp on hotkey events.
func NewHotkeyManager(cfg *Config, onDown func(), onUp func()) *HotkeyManager {
	return &HotkeyManager{
		cfg:    cfg,
		onDown: onDown,
		onUp:   onUp,
		done:   make(chan struct{}),
	}
}

// Start registers the hotkey and begins listening.
func (m *HotkeyManager) Start() error {
	mods := mapModifiers(m.cfg.HotkeyMods)
	key := mapKey(m.cfg.HotkeyKey)

	m.hk = hotkey.New(mods, key)
	if err := m.hk.Register(); err != nil {
		return err
	}

	go m.listen()
	return nil
}

// Stop unregisters the hotkey and stops the listener.
func (m *HotkeyManager) Stop() {
	m.closeOnce.Do(func() {
		close(m.done)
	})
	if m.hk != nil {
		m.hk.Unregister()
	}
}

func (m *HotkeyManager) listen() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	isPTT := m.cfg.IsPushToTalk()
	recording := false
	vk := mapVK(m.cfg.HotkeyKey)

	for {
		select {
		case <-m.done:
			return
		case <-m.hk.Keydown():
			if isPTT {
				m.onDown()
				go m.waitForRelease(vk)
			} else {
				if !recording {
					m.onDown()
					recording = true
				} else {
					m.onUp()
					recording = false
				}
			}
		}
	}
}

// waitForRelease polls GetAsyncKeyState until the main key is released.
func (m *HotkeyManager) waitForRelease(vk int) {
	for {
		select {
		case <-m.done:
			return
		default:
		}
		r, _, _ := procGetAsyncKeyState.Call(uintptr(vk))
		if r&0x8000 == 0 {
			m.onUp()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func mapModifiers(mods []string) []hotkey.Modifier {
	var result []hotkey.Modifier
	for _, m := range mods {
		switch strings.ToLower(m) {
		case "ctrl":
			result = append(result, hotkey.ModCtrl)
		case "shift":
			result = append(result, hotkey.ModShift)
		case "alt":
			result = append(result, hotkey.ModAlt)
		case "win":
			result = append(result, hotkey.ModWin)
		}
	}
	return result
}

func mapKey(key string) hotkey.Key {
	switch strings.ToUpper(key) {
	case "A":
		return hotkey.KeyA
	case "B":
		return hotkey.KeyB
	case "C":
		return hotkey.KeyC
	case "D":
		return hotkey.KeyD
	case "E":
		return hotkey.KeyE
	case "F":
		return hotkey.KeyF
	case "G":
		return hotkey.KeyG
	case "H":
		return hotkey.KeyH
	case "I":
		return hotkey.KeyI
	case "J":
		return hotkey.KeyJ
	case "K":
		return hotkey.KeyK
	case "L":
		return hotkey.KeyL
	case "M":
		return hotkey.KeyM
	case "N":
		return hotkey.KeyN
	case "O":
		return hotkey.KeyO
	case "P":
		return hotkey.KeyP
	case "Q":
		return hotkey.KeyQ
	case "R":
		return hotkey.KeyR
	case "S":
		return hotkey.KeyS
	case "T":
		return hotkey.KeyT
	case "U":
		return hotkey.KeyU
	case "V":
		return hotkey.KeyV
	case "W":
		return hotkey.KeyW
	case "X":
		return hotkey.KeyX
	case "Y":
		return hotkey.KeyY
	case "Z":
		return hotkey.KeyZ
	case "0":
		return hotkey.Key0
	case "1":
		return hotkey.Key1
	case "2":
		return hotkey.Key2
	case "3":
		return hotkey.Key3
	case "4":
		return hotkey.Key4
	case "5":
		return hotkey.Key5
	case "6":
		return hotkey.Key6
	case "7":
		return hotkey.Key7
	case "8":
		return hotkey.Key8
	case "9":
		return hotkey.Key9
	case "F1":
		return hotkey.KeyF1
	case "F2":
		return hotkey.KeyF2
	case "F3":
		return hotkey.KeyF3
	case "F4":
		return hotkey.KeyF4
	case "F5":
		return hotkey.KeyF5
	case "F6":
		return hotkey.KeyF6
	case "F7":
		return hotkey.KeyF7
	case "F8":
		return hotkey.KeyF8
	case "F9":
		return hotkey.KeyF9
	case "F10":
		return hotkey.KeyF10
	case "F11":
		return hotkey.KeyF11
	case "F12":
		return hotkey.KeyF12
	case "SPACE":
		return hotkey.KeySpace
	case "RETURN", "ENTER":
		return hotkey.KeyReturn
	case "ESCAPE", "ESC":
		return hotkey.KeyEscape
	case "DELETE", "DEL":
		return hotkey.KeyDelete
	case "TAB":
		return hotkey.KeyTab
	default:
		return hotkey.KeyV
	}
}

// mapVK returns the Windows virtual key code for GetAsyncKeyState polling.
func mapVK(key string) int {
	upper := strings.ToUpper(key)
	if len(upper) == 1 {
		c := upper[0]
		if (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
			return int(c)
		}
	}
	switch upper {
	case "F1":
		return 0x70
	case "F2":
		return 0x71
	case "F3":
		return 0x72
	case "F4":
		return 0x73
	case "F5":
		return 0x74
	case "F6":
		return 0x75
	case "F7":
		return 0x76
	case "F8":
		return 0x77
	case "F9":
		return 0x78
	case "F10":
		return 0x79
	case "F11":
		return 0x7A
	case "F12":
		return 0x7B
	case "SPACE":
		return 0x20
	case "RETURN", "ENTER":
		return 0x0D
	case "ESCAPE", "ESC":
		return 0x1B
	case "DELETE", "DEL":
		return 0x2E
	case "TAB":
		return 0x09
	default:
		return 0x56 // VK_V
	}
}
