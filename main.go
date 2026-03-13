package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"

	"github.com/whispaste/whispaste/internal/audiocache"
	"github.com/whispaste/whispaste/internal/i18n"
	"github.com/whispaste/whispaste/internal/models"
	"github.com/whispaste/whispaste/internal/stats"
	"github.com/whispaste/whispaste/internal/wav"
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
	i18n.Init(AppVersion)
	models.Init(AppName)

	// Log build metadata for debugging
	logStartupMetadata()

	// Register AppUserModelID so Windows 10/11 toast notifications work.
	// Without this, Shell_NotifyIconW NIF_INFO balloons are silently dropped.
	setAppUserModelID()

	// Ensure a Start Menu shortcut with the AUMID exists. Windows 10/11
	// requires this for toast notifications (converted from balloons via
	// NOTIFYICON_VERSION_4) to actually display on screen.
	ensureStartMenuShortcut()

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
	migrateLegacyLLMModel()
	localLLM.cfg = cfg
	SetLanguage(cfg.GetUILanguage())
	SetSoundVolume(cfg.SoundVolume)

	// Initialize audio recorder
	recorder, err := NewRecorder()
	if err != nil {
		showError(fmt.Sprintf(T("error.microphone"), err))
		os.Exit(1)
	}
	defer recorder.Close()
	recorder.SetGain(cfg.GetInputGain())
	recorder.SetInputDevice(cfg.GetInputDevice())

	// Initialize stats, audiocache, and history
	cfgDir, _ := configDir()
	usageStats := stats.Load(cfgDir)
	audiocache.Init(cfgDir)
	history := LoadHistory()
	defer history.Close()

	// Clean up orphaned audio files and stale pending entries on startup
	go func() {
		history.CleanupStalePending(1 * time.Hour)
		validIDs := history.AllEntryIDs()
		audiocache.CleanupOrphaned(validIDs)
	}()

	// Initialize overlay
	overlay, err := NewOverlay()
	if err != nil {
		logWarn("Overlay init failed: %v", err)
	}
	if overlay != nil {
		overlay.SetPosition(cfg.GetOverlayPos())
	}

	// Initialize floating record button (always created, shown only if enabled)
	var floatingBtn *FloatingButton
	floatingBtn, err = NewFloatingButton(cfg)
	if err != nil {
		logWarn("Floating button init failed: %v", err)
	} else {
		logInfo("Floating record button initialized (enabled=%v)", cfg.GetFloatingButtonEnabled())
	}

	// Application state
	var (
		state            = StateIdle
		stateMu          sync.Mutex
		stateGen         uint64 // generation counter for auto-hide goroutines
		levelDone        chan struct{}
		recordStart      time.Time          // wall-clock time when recording started
		recordSource     RecordSource       // what triggered the current recording
		transcribeCancel context.CancelFunc // cancels in-flight transcription
		transcribeGen    uint64             // generation counter for transcription ownership
		hkMu             sync.Mutex         // protects hkMgr
		tray             *AppTray           // set after creation, used by transition
		showDashboard    func()             // opens main window, set after onSettingsSaved is defined
		showMainPage     func(string)       // opens main window at specific page
		settingsSaved    func()             // refreshes UI after config changes, set after onSettingsSaved is defined
	)

	// Snapshot config values under lock to avoid data races
	snapshotConfig := func() (playSounds, autoPaste bool, lang, localLang, apiKey, model, endpoint string, useLocal bool) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		endpoint = cfg.APIEndpoint
		if endpoint == "" {
			endpoint = "https://api.openai.com/v1/audio/transcriptions"
		}
		// For local STT, fall back to UI language when transcription language is "auto".
		// Small local whisper models are unreliable at auto-detecting language.
		localLang = cfg.Language
		if localLang == "auto" && cfg.UILanguage != "" && cfg.UILanguage != "auto" {
			localLang = cfg.UILanguage
		}
		return cfg.PlaySounds, cfg.AutoPaste, cfg.Language, localLang, cfg.APIKey, cfg.Model, endpoint, cfg.ActiveModelLocal
	}
	snapshotSmart := func() (enabled bool, preset, customPrompt, targetLang string) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		return cfg.SmartMode, cfg.SmartModePreset, cfg.SmartModePrompt, cfg.SmartModeTarget
	}

	// State transition handler
	var transition func(AppState)
	transition = func(newState AppState) {
		oldState, currentGen := func() (AppState, uint64) {
			stateMu.Lock()
			defer stateMu.Unlock()
			old := state
			state = newState
			stateGen++
			return old, stateGen
		}()

		if oldState == newState {
			return
		}

		// Update tray tooltip
		if tray != nil {
			tray.SetTooltipState(newState)
		}
		NotifyRecordingState(newState)

		playSounds, autoPaste, lang, localLang, apiKey, model, endpoint, useLocal := snapshotConfig()

		// Clean up level-monitoring goroutine when leaving recording/paused state
		if (oldState == StateRecording || oldState == StatePaused) && levelDone != nil {
			close(levelDone)
			levelDone = nil
		}

		// resetToIdle sets state back to idle under lock and sends notifications.
		resetToIdle := func() {
			func() {
				stateMu.Lock()
				defer stateMu.Unlock()
				state = StateIdle
			}()
			NotifyRecordingState(StateIdle)
			if tray != nil {
				tray.SetTooltipState(StateIdle)
			}
		}

		switch newState {
		case StateRecording:
			// Validate transcription backend is available before starting
			if useLocal && !models.IsDownloaded(cfg.GetLocalModelID()) {
				logWarn("Recording aborted: local STT enabled but no model downloaded (model=%s)", cfg.GetLocalModelID())
				if tray != nil {
					tray.ShowBalloon(AppName, T("error.no_local_model"))
				}
				if playSounds {
					PlayFeedback(SoundError)
				}
				resetToIdle()
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
				resetToIdle()
				return
			}
			if playSounds {
				PlayFeedback(SoundRecordStart)
			}
			if overlay != nil {
				overlay.Show(StateRecording)
			}
			// Hide floating button during recording
			if floatingBtn != nil {
				floatingBtn.Hide()
			}
			if err := recorder.Start(); err != nil {
				logError("Recording error: %v", err)
				if playSounds {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					overlay.Hide()
				}
				if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
					floatingBtn.Show()
				}
				resetToIdle()
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
						s, gen := func() (AppState, uint64) {
							stateMu.Lock()
							defer stateMu.Unlock()
							return state, stateGen
						}()
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
						s, gen := func() (AppState, uint64) {
							stateMu.Lock()
							defer stateMu.Unlock()
							return state, stateGen
						}()
						if s == StateRecording && gen == expectedGen {
							ps, _, _, _, _, _, _, _ := snapshotConfig()
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
				if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
					floatingBtn.Show()
				}
				resetToIdle()
				return
			}

			// Create cancellable context early so cancel works during VAD too
			transcribeCtx, tCancel := context.WithCancel(context.Background())
			myGen, recSrc := func() (uint64, RecordSource) {
				stateMu.Lock()
				defer stateMu.Unlock()
				transcribeGen++
				transcribeCancel = tCancel
				return transcribeGen, recordSource
			}()

			// Voice Activity Detection or simple silence trimming
			vadApplied := false
			if cfg.GetUseVAD() {
				origPCM := make([]byte, len(pcm))
				copy(origPCM, pcm)
				before := len(pcm)
				vadResult, vadErr := GetVADProcessor().ProcessPCM(pcm, cfg.GetVADSensitivity())
				if vadErr != nil {
					logWarn("VAD processing failed, falling back to RMS: %v", vadErr)
					// Fallback to existing pipeline
					if cfg.GetTrimSilence() {
						pcm = TrimSilence(pcm, 0.01, 30)
						if len(pcm) < 9600 {
							logWarn("TrimSilence result too short (%d bytes), using original audio", len(pcm))
							pcm = origPCM
						}
					}
				} else if len(vadResult) < 9600 {
					logWarn("VAD result too short (%d bytes), using original audio", len(vadResult))
					pcm = origPCM
				} else {
					if len(vadResult) < before {
						logDebug("VAD trimmed: %d → %d bytes", before, len(vadResult))
					}
					pcm = vadResult
					vadApplied = true
				}
			} else if cfg.GetTrimSilence() {
				origPCM := make([]byte, len(pcm))
				copy(origPCM, pcm)
				before := len(pcm)
				pcm = TrimSilence(pcm, 0.01, 30)
				if len(pcm) < 9600 {
					logWarn("TrimSilence result too short (%d bytes), using original audio", len(pcm))
					pcm = origPCM
				} else if len(pcm) < before {
					logDebug("Trimmed silence: %d → %d bytes", before, len(pcm))
				}
			}

			// Strip long internal silence (>1s) to reduce duration and API cost.
			// Skipped only when VAD actually succeeded (it removes silence itself).
			if !vadApplied {
				before := len(pcm)
				stripped := StripInternalSilence(pcm, 0.01, 1000)
				if len(stripped) >= 2 && len(stripped) < before {
					logDebug("Stripped internal silence: %d → %d bytes", before, len(stripped))
					pcm = stripped
				}
			}

			// Set transcription time estimate on overlay (16-bit mono = 2 bytes/sample at 16kHz)
			if overlay != nil {
				audioDurSec := float64(len(pcm)) / (16000.0 * 2.0)
				overlay.SetTranscribeEstimate(audioDurSec, useLocal)
			}

			// Transcribe in background
			go func() {
				defer func() {
					func() {
						stateMu.Lock()
						defer stateMu.Unlock()
						if transcribeGen == myGen {
							transcribeCancel = nil
						}
					}()
					tCancel() // ensure context resources are freed
					if r := recover(); r != nil {
						logError("Transcription goroutine panic: %v", r)
						if playSounds {
							PlayFeedback(SoundError)
						}
						if overlay != nil {
							overlay.Hide()
						}
						if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
							floatingBtn.Show()
						}
						resetToIdle()
					}
				}()
				durationSec := time.Since(recordStart).Seconds()
				modelName := model
				if useLocal {
					modelName = cfg.GetLocalModelID()
				}

				// Create pending entry BEFORE transcription so audio is preserved if app crashes
				pendingID := ""
				if len(pcm) >= 9600 {
					pendingID = history.AddPendingEntry(durationSec, lang, modelName, useLocal, T("transcribing"))
					if pendingID != "" {
						projID := getSelectedProjectID()
						if projID != "" {
							history.SetEntryProject(pendingID, projID)
						}
						if err := audiocache.Save(pendingID, pcm); err != nil {
							logWarn("Save pre-transcription audio: %v", err)
						}
						logDebug("Created pre-transcription pending entry %s", pendingID)
						NotifyHistoryChanged()
					}
				}

				transcribeStart := time.Now()
				var text string
				var err error
				logInfo("Transcribing with: useLocal=%v model=%s", useLocal, modelName)
				if useLocal {
					localModelID := cfg.GetLocalModelID()
					logDebug("starting local transcription: model=%s lang=%s audioBytes=%d", localModelID, localLang, len(pcm))
					text, err = TranscribeLocal(pcm, 16000, localLang, localModelID)
				} else {
					wavData := wav.Encode(pcm, 16000, 1, 16)
					text, err = Transcribe(transcribeCtx, wavData, lang, apiKey, model, endpoint, "")
				}
				processingDurationSec := time.Since(transcribeStart).Seconds()
				if err != nil {
					if errors.Is(err, context.Canceled) {
						logInfo("Transcription cancelled by user")
						if pendingID != "" {
							logDebug("Removing cancelled pending entry %s", pendingID)
							history.Delete(pendingID)
						}
						return
					}
					logError("Transcription error: %v", err)
					if pendingID != "" {
						history.UpdatePendingReason(pendingID, T("transcription_failed"))
					}
					if playSounds {
						PlayFeedback(SoundError)
					}
					if overlay != nil {
						overlay.Hide()
					}
					if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
						floatingBtn.Show()
					}
					resetToIdle()
					return
				}

				// Check if user cancelled while local transcription was running
				if transcribeCtx.Err() != nil {
					logInfo("Transcription cancelled by user (post-return)")
					if pendingID != "" {
						logDebug("Removing cancelled pending entry %s", pendingID)
						history.Delete(pendingID)
					}
					return
				}

				// Apply text replacements (exact match + optional AI semantic match)
				if cfg.GetTextReplacementsEnabled() {
					replacements := cfg.GetTextReplacements()
					trProvider := cfg.GetTextReplacementProvider()
					text = ApplyTextReplacementsWithAI(text, replacements, cfg.GetTextReplacementsAI(), trProvider, apiKey, endpoint)
				}

				// Treat empty/whitespace-only transcription as failed
				if strings.TrimSpace(text) == "" {
					logWarn("Transcription returned empty text")
					if pendingID != "" {
						logDebug("Removing empty pending entry %s", pendingID)
						history.Delete(pendingID)
					}
					if playSounds {
						PlayFeedback(SoundError)
					}
					if overlay != nil {
						overlay.Hide()
					}
					if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
						floatingBtn.Show()
					}
					resetToIdle()
					return
				}

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
						overlay.SetSmartMode(true)
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

				// Bail out if cancelled during smart mode post-processing
				// (transcription already succeeded, save raw text without auto-paste)
				postProcCancelled := transcribeCtx.Err() != nil
				if postProcCancelled {
					logInfo("Transcription cancelled during post-processing, saving raw text")
				}

				// Record stats and history with model info
				totalDictations := usageStats.RecordDictation(text, durationSec, useLocal)
				var entryID string
				activeModel := model
				activeLocal := false
				if useLocal {
					activeModel = cfg.GetLocalModelID()
					activeLocal = true
				}
				history.RecordDailyStats(durationSec, processingDurationSec, text, activeModel, activeLocal)

				// Complete the pending entry or create a new one
				if pendingID != "" {
					if history.CompletePendingEntry(pendingID, text, processingDurationSec, activeModel, activeLocal) {
						entryID = pendingID
						logDebug("Completed pending entry %s with transcription", pendingID)
					} else {
						logWarn("Failed to complete pending entry %s, creating new entry", pendingID)
						entryID = history.AddWithModel(text, durationSec, processingDurationSec, lang, activeModel, activeLocal, getSelectedProjectID())
					}
				} else {
					entryID = history.AddWithModel(text, durationSec, processingDurationSec, lang, activeModel, activeLocal, getSelectedProjectID())
				}

				// Auto-tag with local LLM if available
				if entryID != "" && IsLLMInstalled() {
					tagEntryID, tagText, tagCustom := entryID, text, cfg.GetCustomTags()
					go AutoTagEntry(history, tagEntryID, tagText, tagCustom)
				}

				// Audio already cached for pending entries; cache for new entries
				if entryID != "" && pendingID == "" {
					if err := audiocache.Save(entryID, pcm); err != nil {
						logWarn("Save audio cache: %v", err)
					}
				}
				// Auto-cleanup if enabled
				if cfg.GetCleanupEnabled() {
					history.Cleanup(cfg.GetCleanupMaxEntries(), cfg.GetCleanupMaxAgeDays(), cfg.GetCleanupIncludePinned())
				}
				NotifyHistoryChanged()
				if tray != nil {
					tray.RefreshHistory()
					tray.MaybeSponsorBalloon(totalDictations)
					if cfg.GetNotifyComplete() {
						tray.ShowBalloon(AppName, T("balloon.transcription_complete"))
					}
				}

				if autoPaste && recSrc != SourceAppUI && !postProcCancelled {
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
				gen := func() uint64 {
					stateMu.Lock()
					defer stateMu.Unlock()
					state = StateIdle
					stateGen++
					return stateGen
				}()
				NotifyRecordingState(StateIdle)
				// Re-show floating button now that we're idle
				if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
					floatingBtn.Show()
				}
				if tray != nil {
					tray.SetTooltipState(StateIdle)
				}

				if overlay != nil {
					overlay.Show(StateCopied)
					go func(expectedGen uint64) {
						time.Sleep(2 * time.Second)
						match := func() bool {
							stateMu.Lock()
							defer stateMu.Unlock()
							return stateGen == expectedGen
						}()
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
			// Show floating button again when returning to idle
			if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
				floatingBtn.Show()
			}
		}
	}

	// Check API key
	if !cfg.HasAnyModel() {
		logInfo("No API key configured – opening settings on launch")
	}

	// Wire overlay button callbacks (after transition is defined)
	if overlay != nil {
		overlay.SetCallbacks(
			func() { // onConfirm: end recording → transcribe
				s := func() AppState {
					stateMu.Lock()
					defer stateMu.Unlock()
					return state
				}()
				if s == StateRecording || s == StatePaused {
					if recorder.IsPaused() {
						recorder.Resume()
					}
					transition(StateTranscribing)
				}
			},
			func() { // onCancel: abort recording or transcription
				s, ld, tc := func() (AppState, chan struct{}, context.CancelFunc) {
					stateMu.Lock()
					defer stateMu.Unlock()
					s := state
					if s != StateRecording && s != StatePaused && s != StateTranscribing && s != StateProcessing {
						return s, nil, nil
					}
					state = StateIdle
					ld := levelDone
					levelDone = nil
					tc := transcribeCancel
					transcribeCancel = nil
					return s, ld, tc
				}()
				if s != StateRecording && s != StatePaused && s != StateTranscribing && s != StateProcessing {
					return
				}

				if s == StateTranscribing || s == StateProcessing {
					logInfo("Transcription cancelled via overlay button")
					if tc != nil {
						tc() // cancel in-flight HTTP request
					}
				} else {
					logInfo("Recording cancelled via overlay button")
					if recorder.IsPaused() {
						recorder.Resume()
					}
					recorder.Stop() // discard audio
				}
				ps, _, _, _, _, _, _, _ := snapshotConfig()
				if ps {
					PlayFeedback(SoundError)
				}
				if overlay != nil {
					overlay.Hide()
				}
				if floatingBtn != nil && cfg.GetFloatingButtonEnabled() {
					floatingBtn.Show()
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
				s := func() AppState {
					stateMu.Lock()
					defer stateMu.Unlock()
					return state
				}()
				if s == StateRecording {
					recorder.Pause()
					func() {
						stateMu.Lock()
						defer stateMu.Unlock()
						state = StatePaused
					}()
					if overlay != nil {
						overlay.SetPaused(true)
					}
					if tray != nil {
						tray.SetTooltipState(StatePaused)
					}
					NotifyRecordingState(StatePaused)
				} else if s == StatePaused {
					recorder.Resume()
					func() {
						stateMu.Lock()
						defer stateMu.Unlock()
						state = StateRecording
					}()
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
				fn := func() func() {
					stateMu.Lock()
					defer stateMu.Unlock()
					return showDashboard
				}()
				if fn != nil {
					go fn()
				}
			},
		)
	}

	// Wire floating button callbacks
	if floatingBtn != nil {
		floatingBtn.SetCallbacks(
			func() { // onStartRecording
				ok := func() bool {
					stateMu.Lock()
					defer stateMu.Unlock()
					if state != StateIdle {
						return false
					}
					recordSource = SourceFloating
					return true
				}()
				if ok {
					transition(StateRecording)
				}
			},
			func(page string) { // onOpenWindow
				fn := func() func(string) {
					stateMu.Lock()
					defer stateMu.Unlock()
					return showMainPage
				}()
				if fn != nil {
					go fn(page)
				}
			},
			func() { // onQuit
				if tray != nil {
					tray.Quit()
				}
			},
			func(newState bool) { // onSmartToggled - push to WebView
				mainWindowMu.Lock()
				wv := mainWebview
				mainWindowMu.Unlock()
				if wv != nil {
					wv.Dispatch(func() {
						wv.Eval("if(typeof window.refreshFromConfig==='function')window.refreshFromConfig()")
					})
				}
			},
			func() { // onHide - sync WebView settings after context menu hide
				if settingsSaved != nil {
					settingsSaved()
				}
			},
		)
		floatingBtn.SetMenuCallbacks(
			func() { // onToggle - start/stop recording
				s, started := func() (AppState, bool) {
					stateMu.Lock()
					defer stateMu.Unlock()
					if state == StateIdle {
						recordSource = SourceFloating
						return state, true
					}
					if state == StateRecording || state == StatePaused {
						return state, false
					}
					return state, false
				}()
				if started {
					transition(StateRecording)
				} else if s == StateRecording || s == StatePaused {
					if recorder.IsPaused() {
						recorder.Resume()
					}
					transition(StateTranscribing)
				}
			},
			func() AppState { // getState
				stateMu.Lock()
				defer stateMu.Unlock()
				return state
			},
			func() string { // getHotkeyStr
				cfg.mu.RLock()
				mods := cfg.HotkeyMods
				key := cfg.HotkeyKey
				cfg.mu.RUnlock()
				return strings.Join(mods, "+") + "+" + key
			},
			func() string { // getLatestText
				entries := history.Recent(1)
				if len(entries) == 0 || entries[0].Text == "" {
					return ""
				}
				return entries[0].Text
			},
		)
		// Show the button initially if enabled and onboarding is complete
		if cfg.GetFloatingButtonEnabled() && cfg.GetOnboardingDone() {
			floatingBtn.Show()
		}
	}

	// Hotkey callbacks
	onHotkeyDown := func() {
		logInfo("Hotkey DOWN event received")
		if func() bool {
			stateMu.Lock()
			defer stateMu.Unlock()
			return state != StateIdle
		}() {
			return
		}

		if !cfg.HasAnyModel() {
			ps, _, _, _, _, _, _, _ := snapshotConfig()
			if ps {
				PlayFeedback(SoundError)
			}
			if overlay != nil {
				go func() {
					overlay.Show(StateError)
					time.Sleep(3 * time.Second)
					// Only hide if app is still idle (avoid hiding a recording overlay)
					cur := func() AppState {
						stateMu.Lock()
						defer stateMu.Unlock()
						return state
					}()
					if cur == StateIdle {
						overlay.Hide()
					}
				}()
			}
			logInfo("Hotkey pressed but no API key configured")
			return
		}
		ok := func() bool {
			stateMu.Lock()
			defer stateMu.Unlock()
			if state != StateIdle {
				return false
			}
			recordSource = SourceHotkey
			return true
		}()
		if ok {
			transition(StateRecording)
		}
	}

	onHotkeyUp := func() {
		s := func() AppState {
			stateMu.Lock()
			defer stateMu.Unlock()
			return state
		}()

		if s == StateRecording || s == StatePaused {
			if recorder.IsPaused() {
				recorder.Resume()
			}
			transition(StateTranscribing)
		}
	}

	// Start hotkey listener (protected by hkMu)
	var hkMgr *HotkeyManager
	func() {
		hkMu.Lock()
		defer hkMu.Unlock()
		hkMgr = NewHotkeyManager(cfg, onHotkeyDown, onHotkeyUp)
		if err := hkMgr.Start(); err != nil {
			logWarn("Hotkey registration failed: %v", err)
		} else {
			logInfo("Hotkey registered: %v + %s", cfg.HotkeyMods, cfg.HotkeyKey)
		}
	}()

	defer func() {
		hkMu.Lock()
		defer hkMu.Unlock()
		if hkMgr != nil {
			hkMgr.Stop()
		}
	}()

	// Settings callback (called when config is saved from WebView goroutine)
	onSettingsSaved := func() {
		SetSoundVolume(cfg.SoundVolume)
		if overlay != nil {
			overlay.SetPosition(cfg.GetOverlayPos())
		}
		// Live-toggle floating button based on setting
		if floatingBtn != nil {
			floatingBtn.UpdateColor()   // pick up any color change
			floatingBtn.UpdateSize()    // pick up any size change
			floatingBtn.UpdateOpacity() // pick up any opacity/border change
			s := func() AppState {
				stateMu.Lock()
				defer stateMu.Unlock()
				return state
			}()
			if cfg.GetFloatingButtonEnabled() && s == StateIdle {
				floatingBtn.Show()
			} else if !cfg.GetFloatingButtonEnabled() {
				floatingBtn.Hide()
			}
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
	settingsSaved = onSettingsSaved

	// Initialize updater
	updater := NewUpdater(AppVersion, cfg.GetCheckUpdates, cfg.GetUpdateChannel)

	// System tray (this blocks on the main thread)
	onToggle := func() {
		s, started := func() (AppState, bool) {
			stateMu.Lock()
			defer stateMu.Unlock()
			s := state
			if s == StateIdle && cfg.HasAnyModel() {
				recordSource = SourceAppUI
				return s, true
			}
			return s, false
		}()
		if started {
			transition(StateRecording)
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
	func() {
		stateMu.Lock()
		defer stateMu.Unlock()
		showDashboard = func() {
			ShowMainWindow(cfg, recorder, history, usageStats, onSettingsSaved, onWindowClose, onToggle, "")
		}
		showMainPage = func(page string) {
			ShowMainWindow(cfg, recorder, history, usageStats, onSettingsSaved, onWindowClose, onToggle, page)
		}
	}()
	tray = NewAppTray(
		func(page string) {
			ShowMainWindow(cfg, recorder, history, usageStats, onSettingsSaved, onWindowClose, onToggle, page)
		},
		func() {
			func() {
				hkMu.Lock()
				defer hkMu.Unlock()
				if hkMgr != nil {
					hkMgr.Stop()
				}
			}()
			localLLM.Stop()
			localSTT.Stop()
			GetVADProcessor().Close()
			CloseMainWindow()
			CloseLogViewer()
			if overlay != nil {
				overlay.Close()
			}
			if floatingBtn != nil {
				floatingBtn.Close()
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
	if !cfg.HasAnyModel() {
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowMainWindow(cfg, recorder, history, usageStats, onSettingsSaved, onWindowClose, onToggle, "settings")
		}()
	} else if !isAutostart {
		// Manual launch: show dashboard immediately
		go func() {
			time.Sleep(500 * time.Millisecond)
			ShowMainWindow(cfg, recorder, history, usageStats, onSettingsSaved, onWindowClose, onToggle, "history")
		}()
	}

	tray.Run() // blocks until quit
}
