package main

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func main() {
	// Detect system language on Windows via GetUserDefaultUILanguage
	detectAndSetLanguage()

	cfg, err := LoadConfig()
	if err != nil {
		log.Printf("Warning: config load error: %v (using defaults)", err)
	}
	SetLanguage(cfg.UILanguage)

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
		log.Printf("Warning: overlay init failed: %v", err)
	}

	// Application state
	var (
		state      = StateIdle
		stateMu    sync.Mutex
		levelDone  chan struct{}
	)

	// State transition handler
	transition := func(newState AppState) {
		stateMu.Lock()
		oldState := state
		state = newState
		stateMu.Unlock()

		if oldState == newState {
			return
		}

		switch newState {
		case StateRecording:
			if cfg.PlaySounds {
				PlayFeedback(SoundRecordStart)
			}
			if overlay != nil {
				overlay.Show(StateRecording)
			}
			if err := recorder.Start(); err != nil {
				log.Printf("Recording error: %v", err)
				if cfg.PlaySounds {
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
			if cfg.PlaySounds {
				PlayFeedback(SoundRecordStop)
			}
			if overlay != nil {
				overlay.Show(StateTranscribing)
			}
			pcm, err := recorder.Stop()
			if err != nil || len(pcm) == 0 {
				log.Printf("No audio data captured")
				if cfg.PlaySounds {
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

			// Transcribe in background
			go func() {
				wav := EncodeWAV(pcm, 16000, 1, 16)
				text, err := Transcribe(wav, cfg.Language, cfg.GetAPIKey(), cfg.Model)
				if err != nil {
					log.Printf("Transcription error: %v", err)
					if cfg.PlaySounds {
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

				if cfg.AutoPaste {
					if err := PasteText(text); err != nil {
						log.Printf("Paste error: %v", err)
						if cfg.PlaySounds {
							PlayFeedback(SoundError)
						}
					} else {
						if cfg.PlaySounds {
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
		log.Println("No API key configured – opening settings on launch")
	}

	// Hotkey callbacks
	onHotkeyDown := func() {
		stateMu.Lock()
		s := state
		stateMu.Unlock()

		if s == StateIdle {
			if !cfg.HasAPIKey() {
				if cfg.PlaySounds {
					PlayFeedback(SoundError)
				}
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

	// Start hotkey listener
	hkMgr := NewHotkeyManager(cfg, onHotkeyDown, onHotkeyUp)
	if err := hkMgr.Start(); err != nil {
		log.Printf("Warning: hotkey registration failed: %v", err)
	}
	defer hkMgr.Stop()

	// Settings callback (called when config is saved)
	onSettingsSaved := func() {
		// Re-register hotkey with new config
		hkMgr.Stop()
		hkMgr = NewHotkeyManager(cfg, onHotkeyDown, onHotkeyUp)
		if err := hkMgr.Start(); err != nil {
			log.Printf("Hotkey re-registration failed: %v", err)
		}
	}

	// System tray (this blocks on the main thread)
	tray := NewAppTray(
		func() { ShowSettings(cfg, recorder, onSettingsSaved) },
		func() {
			hkMgr.Stop()
			if overlay != nil {
				overlay.Close()
			}
			recorder.Close()
		},
	)

	// Open settings on first run (no API key)
	if !cfg.HasAPIKey() {
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowSettings(cfg, recorder, onSettingsSaved)
		}()
	}

	tray.Run() // blocks until quit
}

// detectAndSetLanguage uses GetUserDefaultUILanguage to detect system locale.
func detectAndSetLanguage() {
	kernel32 := windows.NewLazySystemDLL("kernel32.dll")
	proc := kernel32.NewProc("GetUserDefaultUILanguage")
	langID, _, _ := proc.Call()
	// Primary language ID for German is 0x07
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
	proc.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10) // MB_ICONERROR
}
