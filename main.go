package main

import (
	"fmt"
	"os"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func main() {
	InitLogger(LogDebug)
	defer CloseLogger()

	// Detect system language on Windows via GetUserDefaultUILanguage
	detectAndSetLanguage()

	cfg, err := LoadConfig()
	if err != nil {
		logWarn("Config load error: %v (using defaults)", err)
	}
	SetLanguage(cfg.GetUILanguage())

	// Initialize audio recorder
	recorder, err := NewRecorder()
	if err != nil {
		showError(fmt.Sprintf(T("error.microphone"), err))
		os.Exit(1)
	}
	defer recorder.Close()

	// Initialize overlay
	overlay, err := NewOverlay()
	if err != nil {
		logWarn("Overlay init failed: %v", err)
	}

	// Application state
	var (
		state     = StateIdle
		stateMu   sync.Mutex
		levelDone chan struct{}
		hkMu      sync.Mutex // protects hkMgr
	)

	// Snapshot config values under lock to avoid data races
	snapshotConfig := func() (playSounds, autoPaste bool, lang, apiKey, model string) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		return cfg.PlaySounds, cfg.AutoPaste, cfg.Language, cfg.APIKey, cfg.Model
	}

	// State transition handler
	transition := func(newState AppState) {
		stateMu.Lock()
		oldState := state
		state = newState
		stateMu.Unlock()

		if oldState == newState {
			return
		}

		playSounds, autoPaste, lang, apiKey, model := snapshotConfig()

		switch newState {
		case StateRecording:
			if playSounds {
				PlayFeedback(SoundRecordStart)
			}
			if overlay != nil {
				overlay.Show(StateRecording)
			}
			if err := recorder.Start(); err != nil {
				logError("Recording error: %v", err)
				if playSounds {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					overlay.Hide()
				}
				stateMu.Lock()
				state = StateIdle
				stateMu.Unlock()
				return
			}
			// Start audio level monitoring for overlay
			ld := make(chan struct{})
			levelDone = ld
			go func() {
				for {
					select {
					case <-ld:
						return
					default:
						if overlay != nil {
							overlay.UpdateLevel(recorder.GetLevel())
						}
						time.Sleep(33 * time.Millisecond)
					}
				}
			}()

		case StateTranscribing:
			// Stop level monitoring
			if levelDone != nil {
				close(levelDone)
				levelDone = nil
			}
			if playSounds {
				PlayFeedback(SoundRecordStop)
			}
			if overlay != nil {
				overlay.Show(StateTranscribing)
			}
			pcm, err := recorder.Stop()
			if err != nil || len(pcm) == 0 {
				logWarn("No audio data captured")
				if playSounds {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					overlay.Hide()
				}
				stateMu.Lock()
				state = StateIdle
				stateMu.Unlock()
				return
			}

			// Transcribe in background (use snapshot values, not cfg directly)
			go func() {
				wav := EncodeWAV(pcm, 16000, 1, 16)
				text, err := Transcribe(wav, lang, apiKey, model)
				if err != nil {
					logError("Transcription error: %v", err)
					if playSounds {
						PlayFeedback(SoundError)
					}
					if overlay != nil {
						overlay.Hide()
					}
					stateMu.Lock()
					state = StateIdle
					stateMu.Unlock()
					return
				}

				if autoPaste {
					if err := PasteText(text); err != nil {
						logError("Paste error: %v", err)
						if playSounds {
							PlayFeedback(SoundError)
						}
					} else {
						if playSounds {
							PlayFeedback(SoundSuccess)
						}
					}
				}

				if overlay != nil {
					overlay.Hide()
				}
				stateMu.Lock()
				state = StateIdle
				stateMu.Unlock()
			}()

		case StateIdle:
			if overlay != nil {
				overlay.Hide()
			}
		}
	}

	// Check API key
	if !cfg.HasAPIKey() {
		logInfo("No API key configured – opening settings on launch")
	}

	// Hotkey callbacks
	onHotkeyDown := func() {
		logInfo("Hotkey DOWN event received")
		stateMu.Lock()
		s := state
		stateMu.Unlock()

		if s == StateIdle {
			if !cfg.HasAPIKey() {
				ps, _, _, _, _ := snapshotConfig()
				if ps {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					go func() {
						overlay.Show(StateError)
						time.Sleep(2 * time.Second)
						// Only hide if app is still idle (avoid hiding a recording overlay)
						stateMu.Lock()
						cur := state
						stateMu.Unlock()
						if cur == StateIdle {
							overlay.Hide()
						}
					}()
				}
				logInfo("Hotkey pressed but no API key configured")
				return
			}
			transition(StateRecording)
		}
	}

	onHotkeyUp := func() {
		stateMu.Lock()
		s := state
		stateMu.Unlock()

		if s == StateRecording {
			transition(StateTranscribing)
		}
	}

	// Start hotkey listener (protected by hkMu)
	var hkMgr *HotkeyManager
	hkMu.Lock()
	hkMgr = NewHotkeyManager(cfg, onHotkeyDown, onHotkeyUp)
	if err := hkMgr.Start(); err != nil {
		logWarn("Hotkey registration failed: %v", err)
	} else {
		logInfo("Hotkey registered: %v + %s", cfg.HotkeyMods, cfg.HotkeyKey)
	}
	hkMu.Unlock()

	defer func() {
		hkMu.Lock()
		if hkMgr != nil {
			hkMgr.Stop()
		}
		hkMu.Unlock()
	}()

	// Settings callback (called when config is saved from WebView goroutine)
	onSettingsSaved := func() {
		hkMu.Lock()
		defer hkMu.Unlock()
		if hkMgr != nil {
			hkMgr.Stop()
		}
		hkMgr = NewHotkeyManager(cfg, onHotkeyDown, onHotkeyUp)
		if err := hkMgr.Start(); err != nil {
			logWarn("Hotkey re-registration failed: %v", err)
		}
	}

	// Initialize updater
	updater := NewUpdater(AppVersion, cfg.GetCheckUpdates)

	// System tray (this blocks on the main thread)
	tray := NewAppTray(
		func(tab string) { ShowSettings(cfg, recorder, onSettingsSaved, tab) },
		func() {
			hkMu.Lock()
			if hkMgr != nil {
				hkMgr.Stop()
			}
			hkMu.Unlock()
			if overlay != nil {
				overlay.Close()
			}
			recorder.Close()
		},
		updater,
	)

	// Open settings on first run (no API key)
	if !cfg.HasAPIKey() {
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowSettings(cfg, recorder, onSettingsSaved, "general")
		}()
	}

	tray.Run() // blocks until quit
}

// detectAndSetLanguage uses GetUserDefaultUILanguage to detect system locale.
func detectAndSetLanguage() {
	kernel32 := windows.NewLazySystemDLL("kernel32.dll")
	proc := kernel32.NewProc("GetUserDefaultUILanguage")
	langID, _, _ := proc.Call()
	primaryLang := langID & 0xFF
	if primaryLang == 0x07 {
		SetLanguage("de")
	}
}

// showError displays a Windows message box with an error.
func showError(msg string) {
	user32 := windows.NewLazySystemDLL("user32.dll")
	proc := user32.NewProc("MessageBoxW")
	title, _ := windows.UTF16PtrFromString(AppName)
	text, _ := windows.UTF16PtrFromString(msg)
	proc.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
