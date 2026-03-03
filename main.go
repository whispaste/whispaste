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

	enableDarkMode()

	// Detect system language on Windows via GetUserDefaultUILanguage
	detectAndSetLanguage()

	cfg, err := LoadConfig()
	if err != nil {
		logWarn("Config load error: %v (using defaults)", err)
	}
	SetLanguage(cfg.GetUILanguage())
	SetSoundVolume(cfg.SoundVolume)

	// Initialize audio recorder
	recorder, err := NewRecorder()
	if err != nil {
		showError(fmt.Sprintf(T("error.microphone"), err))
		os.Exit(1)
	}
	defer recorder.Close()

	// Initialize stats and history
	stats := LoadStats()
	history := LoadHistory()

	// Initialize overlay
	overlay, err := NewOverlay()
	if err != nil {
		logWarn("Overlay init failed: %v", err)
	}
	if overlay != nil {
		overlay.SetPosition(cfg.GetOverlayPos())
	}

	// Application state
	var (
		state     = StateIdle
		stateMu   sync.Mutex
		stateGen  uint64 // generation counter for auto-hide goroutines
		levelDone chan struct{}
		hkMu      sync.Mutex // protects hkMgr
		tray      *AppTray   // set after creation, used by transition
	)

	// Snapshot config values under lock to avoid data races
	snapshotConfig := func() (playSounds, autoPaste bool, lang, apiKey, model, endpoint, prompt string) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		endpoint = cfg.APIEndpoint
		if endpoint == "" {
			endpoint = "https://api.openai.com/v1/audio/transcriptions"
		}
		return cfg.PlaySounds, cfg.AutoPaste, cfg.Language, cfg.APIKey, cfg.Model, endpoint, cfg.Prompt
	}
	snapshotSmart := func() (enabled bool, preset, customPrompt, targetLang string) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		return cfg.SmartMode, cfg.SmartModePreset, cfg.SmartModePrompt, cfg.SmartModeTarget
	}

	// State transition handler
	var transition func(AppState)
	transition = func(newState AppState) {
		stateMu.Lock()
		oldState := state
		state = newState
		stateGen++
		currentGen := stateGen
		stateMu.Unlock()

		if oldState == newState {
			return
		}

		// Update tray tooltip
		if tray != nil {
			tray.SetTooltipState(newState)
		}

		playSounds, autoPaste, lang, apiKey, model, endpoint, prompt := snapshotConfig()

		// Clean up level-monitoring goroutine when leaving recording/paused state
		if (oldState == StateRecording || oldState == StatePaused) && levelDone != nil {
			close(levelDone)
			levelDone = nil
		}

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
			// Max recording duration auto-stop (0 = unlimited)
			maxSec := cfg.GetMaxRecordSec()
			if maxSec > 0 {
				go func(expectedGen uint64) {
					timer := time.NewTimer(time.Duration(maxSec) * time.Second)
					defer timer.Stop()
					select {
					case <-ld:
						return
					case <-timer.C:
						stateMu.Lock()
						s := state
						gen := stateGen
						stateMu.Unlock()
						if s == StateRecording && gen == expectedGen {
							logInfo("Max recording duration reached (%ds)", maxSec)
							transition(StateTranscribing)
						}
					}
				}(currentGen)
			}

		case StateTranscribing:
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
				startTime := time.Now()
				wav := EncodeWAV(pcm, 16000, 1, 16)
				text, err := Transcribe(wav, lang, apiKey, model, endpoint, prompt)
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

				durationSec := time.Since(startTime).Seconds()

				// Smart Mode: post-process with GPT-4o-mini
				smartEnabled, smartPreset, smartCustom, smartTarget := snapshotSmart()
				if smartEnabled && smartPreset != "" && smartPreset != "off" {
					if overlay != nil {
						overlay.Show(StateProcessing)
					}
					processed, err := PostProcess(text, smartPreset, smartCustom, smartTarget, apiKey, endpoint)
					if err != nil {
						logWarn("Smart mode error (using raw text): %v", err)
					} else {
						text = processed
					}
				}

				// Record stats and history
				totalDictations := stats.RecordDictation(text, durationSec)
				history.Add(text, durationSec, lang)
				if tray != nil {
					tray.RefreshHistory()
					tray.MaybeSponsorBalloon(totalDictations)
				}

				if autoPaste {
					// PasteText writes to clipboard and simulates Ctrl+V
					if err := PasteText(text); err != nil {
						logError("Paste error: %v", err)
						if playSounds {
							PlayFeedback(SoundError)
						}
					} else {
						logInfo("Transcription pasted (%d chars)", len(text))
						if playSounds {
							PlayFeedback(SoundSuccess)
						}
					}
				} else {
					// No auto-paste: copy to clipboard only
					if clipErr := writeClipboard(text); clipErr != nil {
						logWarn("Clipboard copy failed: %v", clipErr)
					} else {
						logInfo("Transcription copied to clipboard (%d chars)", len(text))
					}
					if playSounds {
						PlayFeedback(SoundSuccess)
					}
				}

				// Show "Copied" feedback briefly, then auto-hide
				stateMu.Lock()
				state = StateIdle
				stateGen++
				gen := stateGen
				stateMu.Unlock()

				if overlay != nil {
					overlay.Show(StateCopied)
					go func(expectedGen uint64) {
						time.Sleep(2 * time.Second)
						stateMu.Lock()
						match := stateGen == expectedGen
						stateMu.Unlock()
						if match {
							overlay.Hide()
						}
					}(gen)
				}
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

	// Wire overlay button callbacks (after transition is defined)
	if overlay != nil {
		overlay.SetCallbacks(
			func() { // onConfirm: end recording → transcribe
				stateMu.Lock()
				s := state
				stateMu.Unlock()
				if s == StateRecording || s == StatePaused {
					if recorder.IsPaused() {
						recorder.Resume()
					}
					transition(StateTranscribing)
				}
			},
			func() { // onPause: toggle pause/resume
				stateMu.Lock()
				s := state
				stateMu.Unlock()
				if s == StateRecording {
					recorder.Pause()
					stateMu.Lock()
					state = StatePaused
					stateMu.Unlock()
					if overlay != nil {
						overlay.SetPaused(true)
					}
					if tray != nil {
						tray.SetTooltipState(StatePaused)
					}
				} else if s == StatePaused {
					recorder.Resume()
					stateMu.Lock()
					state = StateRecording
					stateMu.Unlock()
					if overlay != nil {
						overlay.SetPaused(false)
					}
					if tray != nil {
						tray.SetTooltipState(StateRecording)
					}
				}
			},
		)
	}

	// Hotkey callbacks
	onHotkeyDown := func() {
		logInfo("Hotkey DOWN event received")
		stateMu.Lock()
		s := state
		stateMu.Unlock()

		if s == StateIdle {
			if !cfg.HasAPIKey() {
				ps, _, _, _, _, _, _ := snapshotConfig()
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

		if s == StateRecording || s == StatePaused {
			if recorder.IsPaused() {
				recorder.Resume()
			}
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
		SetSoundVolume(cfg.SoundVolume)
		if overlay != nil {
			overlay.SetPosition(cfg.GetOverlayPos())
		}
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
	onToggle := func() {
		stateMu.Lock()
		s := state
		stateMu.Unlock()
		if s == StateIdle {
			if cfg.HasAPIKey() {
				transition(StateRecording)
			}
		} else if s == StateRecording || s == StatePaused {
			if recorder.IsPaused() {
				recorder.Resume()
			}
			transition(StateTranscribing)
		}
	}
	tray = NewAppTray(
		func(tab string) { ShowSettings(cfg, recorder, onSettingsSaved, func() { tray.ShowMinimizeBalloon() }, tab) },
		func() { ShowNotebook(history, func() { ShowSettings(cfg, recorder, onSettingsSaved, func() { tray.ShowMinimizeBalloon() }, "general") }) },
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
		history,
		cfg,
		onSettingsSaved,
		onToggle,
	)

	// Open settings on first run (no API key)
	if !cfg.HasAPIKey() {
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowSettings(cfg, recorder, onSettingsSaved, func() { tray.ShowMinimizeBalloon() }, "general")
		}()
	}

	tray.Run() // blocks until quit
}

// enableDarkMode opts the process into Windows dark mode so native menus
// (system tray context menu) follow the system theme. Uses uxtheme.dll
// ordinals 135 (SetPreferredAppMode) and 136 (FlushMenuThemes).
// Requires Windows 10 1903+; fails silently on older versions.
func enableDarkMode() {
	dll, err := windows.LoadDLL("uxtheme.dll")
	if err != nil {
		return
	}
	defer dll.Release()
	if proc, err := dll.FindProcByOrdinal(135); err == nil {
		proc.Call(1) // AllowDark
	}
	if proc, err := dll.FindProcByOrdinal(136); err == nil {
		proc.Call()
	}
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
