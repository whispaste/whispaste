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
	// Single-instance guard: only one WhisPaste process at a time
	mutexName, _ := windows.UTF16PtrFromString("Global\\WhisPaste_SingleInstance")
	kernel32 := windows.NewLazySystemDLL("kernel32.dll")
	createMutex := kernel32.NewProc("CreateMutexW")
	handle, _, err := createMutex.Call(0, 0, uintptr(unsafe.Pointer(mutexName)))
	if handle == 0 {
		os.Exit(1)
	}
	if err == windows.ERROR_ALREADY_EXISTS {
		windows.CloseHandle(windows.Handle(handle))
		// Try to bring existing instance's window to foreground
		user32 := windows.NewLazySystemDLL("user32.dll")
		findWindow := user32.NewProc("FindWindowW")
		title, _ := windows.UTF16PtrFromString("WhisPaste")
		hwnd, _, _ := findWindow.Call(0, uintptr(unsafe.Pointer(title)))
		if hwnd != 0 {
			showWindow := user32.NewProc("ShowWindow")
			setFg := user32.NewProc("SetForegroundWindow")
			showWindow.Call(hwnd, 9) // SW_RESTORE
			setFg.Call(hwnd)
		}
		os.Exit(0)
	}
	defer windows.CloseHandle(windows.Handle(handle))

	InitLogger(LogDebug)
	defer CloseLogger()

	// Register AppUserModelID so Windows 10/11 toast notifications work.
	// Without this, Shell_NotifyIconW NIF_INFO balloons are silently dropped.
	setAppUserModelID()

	// Detect --autostart flag (set by Windows autostart registry entry)
	isAutostart := false
	forceOnboarding := false
	for _, arg := range os.Args[1:] {
		switch arg {
		case "--autostart":
			isAutostart = true
		case "--onboarding":
			forceOnboarding = true
		}
	}

	// Enable debug mode via environment variable
	if os.Getenv("WHISPASTE_DEBUG") == "1" {
		debugMode = true
		logInfo("Debug mode enabled")
	}

	if forceOnboarding {
		forceOnboardingFlag = true
		logInfo("Onboarding forced via --onboarding flag")
	}

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
	defer history.Close()

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
		state        = StateIdle
		stateMu      sync.Mutex
		stateGen     uint64 // generation counter for auto-hide goroutines
		levelDone    chan struct{}
		recordStart  time.Time // wall-clock time when recording started
		hkMu         sync.Mutex // protects hkMgr
		tray         *AppTray   // set after creation, used by transition
		showDashboard func()    // opens main window, set after onSettingsSaved is defined
	)

	// Snapshot config values under lock to avoid data races
	snapshotConfig := func() (playSounds, autoPaste bool, lang, localLang, apiKey, model, endpoint, prompt string, useLocal bool) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		endpoint = cfg.APIEndpoint
		if endpoint == "" {
			endpoint = "https://api.openai.com/v1/audio/transcriptions"
		}
		localLang = cfg.TranscriptionLanguage
		if localLang == "" {
			localLang = cfg.Language
		}
		return cfg.PlaySounds, cfg.AutoPaste, cfg.Language, localLang, cfg.APIKey, cfg.Model, endpoint, cfg.Prompt, cfg.UseLocalSTT
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
		NotifyRecordingState(newState)

		playSounds, autoPaste, lang, localLang, apiKey, model, endpoint, prompt, useLocal := snapshotConfig()

		// Clean up level-monitoring goroutine when leaving recording/paused state
		if (oldState == StateRecording || oldState == StatePaused) && levelDone != nil {
			close(levelDone)
			levelDone = nil
		}

		switch newState {
		case StateRecording:
			// Validate transcription backend is available before starting
			if useLocal && !IsModelDownloaded(cfg.GetLocalModelID()) {
				logWarn("Recording aborted: local STT enabled but no model downloaded (model=%s)", cfg.GetLocalModelID())
				if tray != nil {
					tray.ShowBalloon(AppName, T("error.no_local_model"))
				}
				if playSounds {
					PlayFeedback(SoundError)
				}
				stateMu.Lock()
				state = StateIdle
				stateMu.Unlock()
				NotifyRecordingState(StateIdle)
				return
			}
			if !useLocal && apiKey == "" {
				logWarn("Recording aborted: API mode but no API key configured")
				if tray != nil {
					tray.ShowBalloon(AppName, T("error.no_api_key"))
				}
				if playSounds {
					PlayFeedback(SoundError)
				}
				stateMu.Lock()
				state = StateIdle
				stateMu.Unlock()
				NotifyRecordingState(StateIdle)
				return
			}
			if playSounds {
				PlayFeedback(SoundRecordStart)
			}
			if overlay != nil {
				overlay.Show(StateRecording)
			}
			recorder.SetGain(cfg.GetInputGain())
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
				NotifyRecordingState(StateIdle)
				return
			}
			recordStart = time.Now()
			// Max recording duration (read early for overlay warning colors)
			maxSec := cfg.GetMaxRecordSec()
			if overlay != nil {
				overlay.SetMaxRecordSec(maxSec)
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
			// Warning beep before auto-stop
			if maxSec >= 20 {
				go func(expectedGen uint64) {
					select {
					case <-ld:
						return
					case <-time.After(time.Duration(maxSec-10) * time.Second):
						stateMu.Lock()
						s := state
						gen := stateGen
						stateMu.Unlock()
						if s == StateRecording && gen == expectedGen {
							ps, _, _, _, _, _, _, _, _ := snapshotConfig()
							if ps {
								PlayFeedback(SoundWarning)
							}
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
				NotifyRecordingState(StateIdle)
				return
			}

			// Trim silence if enabled
			if cfg.GetTrimSilence() {
				before := len(pcm)
				pcm = TrimSilence(pcm, 0.01, 30)
				if len(pcm) < before {
					logDebug("Trimmed silence: %d → %d bytes", before, len(pcm))
				}
			}

			// Transcribe in background (use snapshot values, not cfg directly)
			go func() {
				durationSec := time.Since(recordStart).Seconds()
				transcribeStart := time.Now()
				var text string
				var err error
				if useLocal {
					modelDir, mdErr := GetModelDir(cfg.GetLocalModelID())
					if mdErr != nil {
						logError("Model directory error: %v", mdErr)
						text, err = "", mdErr
					} else {
						text, err = GetLocalRecognizer().Transcribe(pcm, 16000, localLang, modelDir)
					}
				} else {
					wav := EncodeWAV(pcm, 16000, 1, 16)
					text, err = Transcribe(wav, lang, apiKey, model, endpoint, prompt)
				}
				processingDurationSec := time.Since(transcribeStart).Seconds()
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
					NotifyRecordingState(StateIdle)
					return
				}

				// Apply text replacements before smart mode
				text = cfg.ApplyTextReplacements(text)

				// Smart Mode: post-process with AI
				smartEnabled, smartPreset, smartCustom, smartTarget := snapshotSmart()
				// Template matching: keyword-based auto-detection
				if cfg.GetAppDetectionEnabled() {
					appName := GetActiveAppName()
					winTitle := GetActiveWindowTitle()
					metas := cfg.GetTemplateMetas()
					defaults := GetDefaultTemplateMetas()
					for k, v := range defaults {
						if _, exists := metas[k]; !exists {
							metas[k] = v
						}
					}
					if matched, ok := MatchTemplate(appName, winTitle, metas); ok {
						smartEnabled = true
						smartPreset = matched
						logInfo("Auto-detected template: %s (app: %s, title: %s)", matched, appName, winTitle)
					} else if cfg.GetFallbackPreset() != "" {
						smartEnabled = true
						smartPreset = cfg.GetFallbackPreset()
						logDebug("Using fallback template: %s", smartPreset)
					}
				} else if appPreset, ok := ResolveAppPreset(cfg); ok {
					smartEnabled = true
					smartPreset = appPreset
				}
				if smartEnabled && smartPreset != "" && smartPreset != "off" {
					if overlay != nil {
						overlay.Show(StateProcessing)
					}

					// Determine endpoint based on provider
					provider := cfg.GetSmartModeProvider()
					ppEndpoint := endpoint
					ppAPIKey := apiKey
					skipPostProcess := false

					if provider == "local" || (provider == "auto" && IsLLMInstalled()) {
						if localEndpoint, llmErr := localLLM.Start(); llmErr == nil {
							ppEndpoint = localEndpoint + "/chat/completions"
							ppAPIKey = "local"
						} else {
							logWarn("Local LLM start failed: %v", llmErr)
							if provider == "local" {
								logError("Local LLM required but not available, skipping post-processing")
								skipPostProcess = true
							}
						}
					}

					if !skipPostProcess {
						processed, err := PostProcess(text, smartPreset, smartCustom, smartTarget, ppAPIKey, ppEndpoint, cfg.GetUILanguage(), cfg.GetCustomTemplates())
						if err != nil {
							logWarn("Smart mode error (using raw text): %v", err)
						} else {
							text = processed
						}
					}
				}

				// Record stats and history with model info
				totalDictations := stats.RecordDictation(text, durationSec, useLocal)
				if useLocal {
					history.AddWithModel(text, durationSec, processingDurationSec, lang, cfg.GetLocalModelID(), true)
				} else {
					history.AddWithModel(text, durationSec, processingDurationSec, lang, model, false)
				}
				// Auto-cleanup if enabled
				if cfg.GetCleanupEnabled() {
					history.Cleanup(cfg.GetCleanupMaxEntries(), cfg.GetCleanupMaxAgeDays())
				}
				NotifyHistoryChanged()
				if tray != nil {
					tray.RefreshHistory()
					tray.MaybeSponsorBalloon(totalDictations)
					if cfg.GetNotifyComplete() {
						tray.ShowBalloon(AppName, T("balloon.transcription_complete"))
					}
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
				NotifyRecordingState(StateIdle)

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
	if !cfg.GetUseLocalSTT() && !cfg.HasAPIKey() {
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
			func() { // onCancel: abort recording, discard audio
				stateMu.Lock()
				s := state
				if s != StateRecording && s != StatePaused {
					stateMu.Unlock()
					return
				}
				state = StateIdle
				ld := levelDone
				levelDone = nil
				stateMu.Unlock()

				logInfo("Recording cancelled via overlay button")
				if recorder.IsPaused() {
					recorder.Resume()
				}
				recorder.Stop() // discard audio
				ps, _, _, _, _, _, _, _, _ := snapshotConfig()
				if ps {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					overlay.Hide()
				}
				if ld != nil {
					close(ld)
				}
				if tray != nil {
					tray.SetTooltipState(StateIdle)
				}
				NotifyRecordingState(StateIdle)
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
					NotifyRecordingState(StatePaused)
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
					NotifyRecordingState(StateRecording)
				}
			},
			func() { // onDash: open dashboard/main window
				stateMu.Lock()
				fn := showDashboard
				stateMu.Unlock()
				if fn != nil {
					go fn()
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
			if !cfg.GetUseLocalSTT() && !cfg.HasAPIKey() {
				ps, _, _, _, _, _, _, _, _ := snapshotConfig()
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
			if cfg.GetUseLocalSTT() || cfg.HasAPIKey() {
				transition(StateRecording)
			}
		} else if s == StateRecording || s == StatePaused {
			if recorder.IsPaused() {
				recorder.Resume()
			}
			transition(StateTranscribing)
		}
	}
	// onWindowClose handles window close: minimize to tray or quit
	onWindowClose := func() {
		if cfg.GetCloseToTray() {
			if tray != nil {
				tray.ShowMinimizeBalloon()
			}
		} else {
			if tray != nil {
				tray.Quit()
			}
		}
	}
	stateMu.Lock()
	showDashboard = func() {
		ShowMainWindow(cfg, recorder, history, onSettingsSaved, onWindowClose, onToggle, "")
	}
	stateMu.Unlock()
	tray = NewAppTray(
		func(page string) {
			ShowMainWindow(cfg, recorder, history, onSettingsSaved, onWindowClose, onToggle, page)
		},
		func() {
			hkMu.Lock()
			if hkMgr != nil {
				hkMgr.Stop()
			}
			hkMu.Unlock()
			localLLM.Stop()
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

	// Open settings on first run (no API key and not using local STT)
	if !cfg.GetUseLocalSTT() && !cfg.HasAPIKey() {
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowMainWindow(cfg, recorder, history, onSettingsSaved, onWindowClose, onToggle, "settings")
		}()
	} else if !isAutostart {
		// Manual launch: show dashboard immediately
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowMainWindow(cfg, recorder, history, onSettingsSaved, onWindowClose, onToggle, "history")
		}()
	}

	tray.Run() // blocks until quit
}

// enableDarkMode opts the process into Windows dark mode so native menus
// (system tray context menu) follow the system theme. Uses uxtheme.dll
// setAppUserModelID registers the application's AUMID so that
// Shell_NotifyIconW toast notifications are not silently dropped
// by Windows 10/11. Must be called before any notification code.
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
