package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"

	webview "github.com/webview/webview_go"
)

var (
	settingsMu   sync.Mutex
	settingsOpen bool
	settingsHwnd uintptr
)

//go:embed ui_settings.html
var settingsHTML string

//go:embed resources/app.ico
var embeddedAppIcon []byte

// ShowSettings opens the settings window with WebView2.
func ShowSettings(cfg *Config, recorder *Recorder, onSaved func(), initialTab string) {
	settingsMu.Lock()
	if settingsOpen {
		if settingsHwnd != 0 {
			user32 := windows.NewLazySystemDLL("user32.dll")
			setForeground := user32.NewProc("SetForegroundWindow")
			showWin := user32.NewProc("ShowWindow")
			showWin.Call(settingsHwnd, 9) // SW_RESTORE
			setForeground.Call(settingsHwnd)
		}
		settingsMu.Unlock()
		return
	}
	settingsOpen = true
	settingsMu.Unlock()

	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		defer func() {
			settingsMu.Lock()
			settingsOpen = false
			settingsHwnd = 0
			settingsMu.Unlock()
		}()

		w := webview.New(true)
		if w == nil {
			return
		}
		defer w.Destroy()

		w.SetTitle(T("settings.title") + " – " + AppName)
		w.SetSize(520, 640, webview.HintNone)
		w.SetSize(420, 500, webview.HintMin)
		w.SetSize(700, 900, webview.HintMax)

		// Hide window initially to prevent white flash before content loads
		hwndPtr := w.Window()
		hwnd := uintptr(hwndPtr)

		settingsMu.Lock()
		settingsHwnd = hwnd
		settingsMu.Unlock()
		user32 := windows.NewLazySystemDLL("user32.dll")
		showWindow := user32.NewProc("ShowWindow")
		const swHide = 0
		const swShow = 5
		showWindow.Call(hwnd, swHide)

		// Set window icon from embedded .ico
		setWindowIcon(hwndPtr)

		// Bind: windowReady → shows the window after HTML is fully loaded
		w.Bind("windowReady", func() {
			showWindow.Call(hwnd, swShow)
		})

		// Inject the current language and theme before page loads
		w.Init(fmt.Sprintf(`window._lang = "%s"; window._theme = "%s"; window._initialTab = "%s";`, cfg.UILanguage, cfg.Theme, initialTab))

		// Bind: getConfig → returns JSON config
		w.Bind("getConfig", func() (string, error) {
			cfg.mu.RLock()
			defer cfg.mu.RUnlock()
			data, err := json.Marshal(cfg)
			if err != nil {
				return "", err
			}
			return string(data), nil
		})

		// Bind: saveConfig → saves config from JSON
		w.Bind("saveConfig", func(configJSON string) map[string]interface{} {
			var newCfg Config
			if err := json.Unmarshal([]byte(configJSON), &newCfg); err != nil {
				return map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("Invalid config: %v", err),
				}
			}
			cfg.mu.Lock()
			cfg.APIKey = newCfg.APIKey
			cfg.HotkeyMods = newCfg.HotkeyMods
			cfg.HotkeyKey = newCfg.HotkeyKey
			cfg.Mode = newCfg.Mode
			cfg.Language = newCfg.Language
			cfg.Model = newCfg.Model
			cfg.OverlayPos = newCfg.OverlayPos
			cfg.AutoPaste = newCfg.AutoPaste
			cfg.PlaySounds = newCfg.PlaySounds
			cfg.CheckUpdates = newCfg.CheckUpdates
			cfg.UILanguage = newCfg.UILanguage
			cfg.Theme = newCfg.Theme
			cfg.Autostart = newCfg.Autostart
			cfg.mu.Unlock()

			// Apply autostart setting
			if err := SetAutostart(newCfg.Autostart); err != nil {
				logWarn("Failed to set autostart: %v", err)
			}

			SetLanguage(newCfg.UILanguage)

			if err := cfg.Save(); err != nil {
				return map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("Save failed: %v", err),
				}
			}
			if onSaved != nil {
				onSaved()
			}
			return map[string]interface{}{"success": true, "error": ""}
		})

		// Bind: testRecording → record 3s, transcribe, return result
		w.Bind("_doTestRecording", func() map[string]interface{} {
			logInfo("Test recording started")
			if !cfg.HasAPIKey() {
				logWarn("Test recording: no API key")
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   T("error.no_api_key"),
				}
			}
			if recorder == nil {
				logError("Test recording: recorder not available")
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   "Recorder not available",
				}
			}

			if err := recorder.Start(); err != nil {
				logError("Test recording start failed: %v", err)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   fmt.Sprintf(T("error.recording"), err),
				}
			}

			// Record for 3 seconds
			time.Sleep(3 * time.Second)
			pcm, err := recorder.Stop()
			if err != nil || len(pcm) == 0 {
				errMsg := "no audio captured"
				if err != nil {
					errMsg = err.Error()
				}
				logError("Test recording capture failed: %s", errMsg)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   errMsg,
				}
			}

			logInfo("Test recording captured %d bytes, transcribing...", len(pcm))
			model := cfg.Model
			if model == "" {
				model = "whisper-1"
			}
			wav := EncodeWAV(pcm, 16000, 1, 16)
			text, err := Transcribe(wav, cfg.Language, cfg.GetAPIKey(), model)
			if err != nil {
				logError("Test transcription failed: %v", err)
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   err.Error(),
				}
			}
			logInfo("Test transcription succeeded: %q", strings.TrimSpace(text))
			return map[string]interface{}{
				"success": true,
				"text":    strings.TrimSpace(text),
				"error":   "",
			}
		})

		// Bind: testSound → plays a success chime for preview
		w.Bind("_testSound", func() {
			PlayFeedback(SoundSuccess)
		})

		// Bind: openURL → opens URL in default browser (https only)
		w.Bind("openURL", func(url string) {
			if !strings.HasPrefix(url, "https://") {
				logWarn("openURL: blocked non-https URL: %s", url)
				return
			}
			exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
		})

		// Bind: closeSettings → closes the webview window
		w.Bind("closeSettings", func() {
			w.Terminate()
		})

		w.SetHtml(settingsHTML)
		w.Run()
	}()
}

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
		wmSetIcon   = 0x0080
		iconSmall   = 0
		iconBig     = 1
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
