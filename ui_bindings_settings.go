package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/gpu"
	"github.com/whispaste/whispaste/internal/models"
	"github.com/whispaste/whispaste/internal/provider"
	"github.com/whispaste/whispaste/internal/wav"

	webview "github.com/webview/webview_go"
)

type availableModelInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Meta    string `json:"meta"`
	IsLocal bool   `json:"isLocal"`
}

func selectedCloudSTTProviderInfo(providerID string) provider.STTProviderInfo {
	fallback := provider.STTProviderInfo{ID: "openai", Name: "OpenAI", DefaultModel: "whisper-1"}
	for _, info := range provider.CloudSTTProviders {
		if info.ID == "openai" {
			fallback = info
		}
		if info.ID == providerID {
			return info
		}
	}
	return fallback
}

func availableModelEntries(cfg *Config, downloaded []models.Info) []availableModelInfo {
	var modelList []availableModelInfo

	providerInfo := selectedCloudSTTProviderInfo(cfg.GetCloudSTTProvider())
	if cfg.HasCloudSTTKey() {
		apiModel := selectedCloudSTTModel(cfg)
		cloudName := providerInfo.Name
		if cloudName == "" {
			cloudName = "Cloud"
		}
		modelList = append(modelList, availableModelInfo{
			ID:      apiModel,
			Name:    cloudName + " (" + apiModel + ")",
			Meta:    "Cloud",
			IsLocal: false,
		})
	}
	for _, m := range downloaded {
		modelList = append(modelList, availableModelInfo{
			ID:      m.ID,
			Name:    m.Name,
			Meta:    "Local · " + m.Size,
			IsLocal: true,
		})
	}
	return modelList
}

func selectedCloudSTTModel(cfg *Config) string {
	providerInfo := selectedCloudSTTProviderInfo(cfg.GetCloudSTTProvider())
	cfg.mu.RLock()
	model := cfg.Model
	cfg.mu.RUnlock()
	if model == "" {
		model = providerInfo.DefaultModel
	}
	if model == "" {
		model = "whisper-1"
	}
	return model
}

func createSelectedCloudSTT(cfg *Config, apiKeyOverride string) (provider.STTProvider, string, error) {
	providerID := cfg.GetCloudSTTProvider()
	apiKey := apiKeyOverride
	if apiKey == "" {
		apiKey = cfg.CloudSTTAPIKey()
	}
	if apiKey == "" {
		return nil, "", fmt.Errorf("no API key configured for %s STT", providerID)
	}
	stt, err := provider.NewCloudSTT(providerID, apiKey)
	if err != nil {
		return nil, "", err
	}
	return stt, selectedCloudSTTModel(cfg), nil
}

// bindSettingsHandlers registers settings, config, audio, and model-related JS bindings.
func bindSettingsHandlers(w webview.WebView, cfg *Config, recorder *Recorder, onSaved func()) {

	w.Bind("getConfig", func() (string, error) {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		data, err := json.Marshal(cfg)
		if err != nil {
			return "", err
		}
		return string(data), nil
	})
	w.Bind("toggleAutoPaste", func() {
		cfg.mu.Lock()
		cfg.AutoPaste = !cfg.AutoPaste
		newState := cfg.AutoPaste
		cfg.mu.Unlock()
		cfg.Save()
		logInfo("Status bar toggled Auto-Paste: %v", newState)
		if onSaved != nil {
			onSaved()
		}
	})
	w.Bind("saveConfig", func(configJSON string) map[string]interface{} {
		var newCfg Config
		if err := json.Unmarshal([]byte(configJSON), &newCfg); err != nil {
			return map[string]interface{}{"success": false, "error": fmt.Sprintf("Invalid config: %v", err)}
		}
		cfg.mu.Lock()
		cfg.APIKey = newCfg.APIKey
		cfg.APIEndpoint = newCfg.APIEndpoint
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
		cfg.CloseToTray = newCfg.CloseToTray
		cfg.SoundVolume = newCfg.SoundVolume
		cfg.MaxRecordSec = newCfg.MaxRecordSec
		cfg.SmartMode = newCfg.SmartMode
		cfg.SmartModePreset = newCfg.SmartModePreset
		cfg.SmartModePrompt = newCfg.SmartModePrompt
		cfg.SmartModeTarget = newCfg.SmartModeTarget
		cfg.InputDevice = newCfg.InputDevice
		cfg.InputGain = newCfg.InputGain
		cfg.CleanupEnabled = newCfg.CleanupEnabled
		cfg.CleanupMaxEntries = newCfg.CleanupMaxEntries
		cfg.CleanupMaxAgeDays = newCfg.CleanupMaxAgeDays
		cfg.CleanupIncludePinned = newCfg.CleanupIncludePinned
		cfg.TrimSilence = newCfg.TrimSilence
		cfg.UseVAD = newCfg.UseVAD
		cfg.VADSensitivity = newCfg.VADSensitivity
		cfg.SmartModeProvider = newCfg.SmartModeProvider
		cfg.TextReplacementProvider = newCfg.TextReplacementProvider
		cfg.FloatingButtonEnabled = newCfg.FloatingButtonEnabled
		cfg.FloatingButtonColor = newCfg.FloatingButtonColor
		cfg.FloatingButtonSize = newCfg.FloatingButtonSize
		cfg.FloatingButtonOpacity = newCfg.FloatingButtonOpacity
		cfg.FloatingButtonLocked = newCfg.FloatingButtonLocked
		cfg.FloatingButtonBorder = newCfg.FloatingButtonBorder
		cfg.UpdateChannel = newCfg.UpdateChannel
		cfg.CloudSTTProvider = newCfg.CloudSTTProvider
		cfg.CloudLLMProvider = newCfg.CloudLLMProvider
		cfg.CloudLLMModel = newCfg.CloudLLMModel
		cfg.GroqAPIKey = newCfg.GroqAPIKey
		cfg.DeepgramAPIKey = newCfg.DeepgramAPIKey
		cfg.AnthropicAPIKey = newCfg.AnthropicAPIKey
		cfg.GeminiAPIKey = newCfg.GeminiAPIKey
		cfg.CustomDictionary = newCfg.CustomDictionary
		cfg.GPUAcceleration = newCfg.GPUAcceleration
		cfg.NotifyBackground = newCfg.NotifyBackground
		cfg.NotifyComplete = newCfg.NotifyComplete
		cfg.NotifyDonate = newCfg.NotifyDonate
		cfg.mu.Unlock()
		if err := SetAutostart(newCfg.Autostart); err != nil {
			logWarn("Failed to set autostart: %v", err)
		}
		SetLanguage(newCfg.UILanguage)
		if recorder != nil {
			recorder.SetGain(newCfg.InputGain)
			recorder.SetInputDevice(newCfg.InputDevice)
		}
		if err := cfg.Save(); err != nil {
			return map[string]interface{}{"success": false, "error": fmt.Sprintf("Save failed: %v", err)}
		}
		if onSaved != nil {
			onSaved()
		}
		return map[string]interface{}{"success": true, "error": ""}
	})

	// Provider metadata for UI dropdowns
	w.Bind("getCloudSTTProviders", func() string {
		data, _ := json.Marshal(provider.CloudSTTProviders)
		return string(data)
	})
	w.Bind("getCloudLLMProviders", func() string {
		data, _ := json.Marshal(provider.CloudLLMProviders)
		return string(data)
	})
	w.Bind("getGPUInfo", func(mode string) map[string]interface{} {
		info := gpu.Detect()
		return map[string]interface{}{
			"available":      info.Available,
			"name":           info.Name,
			"vendor":         string(info.Vendor),
			"backend":        string(info.Backend),
			"stt_backend":    string(gpu.RecommendSTTBackend(mode)),
			"llm_backend":    string(gpu.RecommendLLMBackend(mode)),
			"stt_asset_key":  gpu.RecommendSTTAssetKey(mode),
			"vram_mb":        info.VRAMMBytes,
			"driver_version": info.DriverVersion,
		}
	})

	w.Bind("_doTestRecording", func() map[string]interface{} {
		logInfo("Test recording started")
		if !cfg.HasAnyModel() {
			logWarn("Test recording: no model available")
			return map[string]interface{}{"success": false, "text": "", "error": T("error.no_api_key")}
		}
		if recorder == nil {
			logError("Test recording: recorder not available")
			return map[string]interface{}{"success": false, "text": "", "error": "Recorder not available"}
		}
		recorder.StopMonitor()
		recorder.SetGain(cfg.GetInputGain())
		recorder.SetInputDevice(cfg.GetInputDevice())
		if err := recorder.Start(); err != nil {
			logError("Test recording start failed: %v", err)
			return map[string]interface{}{"success": false, "text": "", "error": fmt.Sprintf(T("error.recording"), err)}
		}
		time.Sleep(3 * time.Second)
		pcm, err := recorder.Stop()
		if err != nil || len(pcm) == 0 {
			errMsg := "no audio captured"
			if err != nil {
				errMsg = err.Error()
			}
			logError("Test recording capture failed: %s", errMsg)
			return map[string]interface{}{"success": false, "text": "", "error": errMsg}
		}
		logInfo("Test recording captured %d bytes, transcribing...", len(pcm))
		model := cfg.Model
		if model == "" {
			model = "whisper-1"
		}
		var text string
		var err2 error
		if cfg.GetActiveModelLocal() {
			if err := ensureLocalSTTAllowed(cfg.GetLocalModelID(), "use"); err != nil {
				logWarn("Test transcription blocked by local STT preflight: %v", err)
				return map[string]interface{}{"success": false, "text": "", "error": err.Error()}
			}
			text, err2 = TranscribeLocal(pcm, 16000, cfg.Language, cfg.GetLocalModelID())
		} else {
			wavData := wav.Encode(pcm, 16000, 1, 16)
			stt, cloudModel, err := createSelectedCloudSTT(cfg, "")
			if err != nil {
				logWarn("Test transcription cloud setup failed: %v", err)
				return map[string]interface{}{"success": false, "text": "", "error": err.Error()}
			}
			model = cloudModel
			text, err2 = stt.Transcribe(context.Background(), wavData, cfg.Language, provider.STTOptions{
				Model:    model,
				Language: cfg.Language,
			})
		}
		if err2 != nil {
			logError("Test transcription failed: %v", err2)
			return map[string]interface{}{"success": false, "text": "", "error": err2.Error()}
		}
		logInfo("Test transcription succeeded: %q", strings.TrimSpace(text))
		return map[string]interface{}{"success": true, "text": strings.TrimSpace(text), "error": ""}
	})

	// Test a specific STT model by transcribing 1 second of silence.
	// Runs async to avoid blocking the WebView UI thread during model load.
	w.Bind("_testSTTModel", func(modelID string) map[string]interface{} {
		logInfo("STT model test started for %s", modelID)
		go func() {
			safeDispatch := func(js string) {
				mainWindowMu.Lock()
				open := mainWindowOpen
				mainWindowMu.Unlock()
				if open {
					w.Dispatch(func() { w.Eval(js) })
				}
			}

			silentPCM := make([]byte, 32000)
			lang := cfg.Language
			if lang == "" {
				lang = "en"
			}
			if err := ensureLocalSTTAllowed(modelID, "use"); err != nil {
				logWarn("STT model test blocked by local STT preflight: %v", err)
				safeDispatch(fmt.Sprintf("window._onSTTTestComplete('%s', false, '', '%s')", escapeJS(modelID), escapeJS(err.Error())))
				return
			}

			text, err := TranscribeLocal(silentPCM, 16000, lang, modelID)
			if err != nil {
				logError("STT model test failed: %v", err)
				safeDispatch(fmt.Sprintf("window._onSTTTestComplete('%s', false, '', '%s')", escapeJS(modelID), escapeJS(err.Error())))
				return
			}

			logInfo("STT model test passed for %s (result: %q)", modelID, text)
			safeDispatch(fmt.Sprintf("window._onSTTTestComplete('%s', true, '%s', '')", escapeJS(modelID), escapeJS(strings.TrimSpace(text))))
		}()
		return map[string]interface{}{"started": true}
	})

	w.Bind("_testSound", func() { PlayFeedback(SoundSuccess) })

	w.Bind("testNotification", func() {
		if t := globalTrayRef; t != nil {
			t.ShowBalloon("WhisPaste", T("balloon.test"))
		} else {
			logWarn("testNotification: no tray reference available")
		}
	})

	w.Bind("_testApiKey", func(key string) map[string]interface{} {
		err := TestCloudSTTKey(cfg.GetCloudSTTProvider(), key)
		if err != nil {
			return map[string]interface{}{"success": false, "error": err.Error()}
		}
		return map[string]interface{}{"success": true, "error": ""}
	})
	w.Bind("_getModels", func() []map[string]interface{} {
		var result []map[string]interface{}
		rec := models.Recommend(getSystemRAM())
		for _, m := range models.Available {
			purpose := "download"
			if models.IsDownloaded(m.ID) {
				purpose = "use"
			}
			preflight := localSTTPreflightViewFor(m.ID, purpose)
			result = append(result, map[string]interface{}{
				"id": m.ID, "name": m.Name, "size": m.Size,
				"downloaded":        models.IsDownloaded(m.ID),
				"preflight_blocked": preflight.Blocking,
				"preflight_status":  preflight.Status,
				"preflight_message": preflight.Message,
				"quality":           m.Quality,
				"min_ram_gb":        m.MinRAMBytes / (1024 * 1024 * 1024),
				"rec_ram_gb":        m.RecRAMBytes / (1024 * 1024 * 1024),
				"recommended":       m.ID == rec,
			})
		}
		return result
	})

	w.Bind("getLocalSTTPreflight", func(modelID string, purpose string) string {
		view := localSTTPreflightViewFor(modelID, purpose)
		data, _ := json.Marshal(view)
		return string(data)
	})

	w.Bind("_downloadModel", func(modelID string) map[string]interface{} {
		logInfo("Starting model download: %s", modelID)
		go func() {
			safeDispatch := func(js string) {
				mainWindowMu.Lock()
				open := mainWindowOpen
				mainWindowMu.Unlock()
				if open {
					w.Dispatch(func() { w.Eval(js) })
				}
			}

			model := models.Find(modelID)
			modelFileName := modelID
			if model != nil {
				modelFileName = model.Filename
			}
			if err := ensureLocalSTTAllowed(modelID, "download"); err != nil {
				logWarn("Model download blocked by local STT preflight: %v", err)
				safeDispatch(fmt.Sprintf("window.downloadComplete('%s', false, '%s')", escapeJS(modelID), escapeJS(err.Error())))
				return
			}
			needsServer := !IsSTTServerInstalled()

			err := DownloadSTT(modelID, cfg.GetGPUAcceleration(), func(phase string, pct int) {
				if phase == "server" && needsServer {
					safeDispatch(fmt.Sprintf("window.updateModelProgress('%s', %d, 1, 2, 'whisper-server')", escapeJS(modelID), pct))
				} else if phase == "model" {
					fileIdx, fileCount := 1, 1
					if needsServer {
						fileIdx, fileCount = 2, 2
					}
					safeDispatch(fmt.Sprintf("window.updateModelProgress('%s', %d, %d, %d, '%s')", escapeJS(modelID), pct, fileIdx, fileCount, escapeJS(modelFileName)))
				}
			})
			if err != nil {
				logError("Model download failed: %v", err)
				safeDispatch(fmt.Sprintf("window.downloadComplete('%s', false, '%s')", escapeJS(modelID), escapeJS(err.Error())))
				return
			}
			logInfo("Model downloaded: %s", modelID)
			invalidateLocalSTTPreflight()
			safeDispatch(fmt.Sprintf("window.downloadComplete('%s', true, '')", escapeJS(modelID)))
		}()
		return map[string]interface{}{"started": true}
	})

	w.Bind("_deleteModel", func(modelID string) map[string]interface{} {
		wasActive := cfg.GetActiveModelLocal() && cfg.GetLocalModelID() == modelID
		if err := models.Delete(modelID); err != nil {
			logError("Model delete failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}
		if wasActive {
			downloaded := models.ListDownloaded()
			if len(downloaded) > 0 {
				cfg.mu.Lock()
				cfg.LocalModelID = downloaded[0].ID
				cfg.mu.Unlock()
				cfg.Save()
				logInfo("Active model deleted, fell back to %s", downloaded[0].ID)
			} else if cfg.HasCloudSTTKey() {
				cfg.mu.Lock()
				cfg.ActiveModelLocal = false
				cfg.mu.Unlock()
				cfg.Save()
				logInfo("Active model deleted, fell back to cloud API")
			} else {
				cfg.mu.Lock()
				cfg.ActiveModelLocal = false
				cfg.mu.Unlock()
				cfg.Save()
				logWarn("Active model deleted, no model available")
			}
		}
		return map[string]interface{}{"success": true, "error": "", "wasActive": wasActive}
	})

	w.Bind("_isModelDownloaded", func(modelID string) bool { return models.IsDownloaded(modelID) })

	w.Bind("_getAudioDevices", func() string {
		devices, err := ListAudioDevices()
		if err != nil {
			logWarn("Failed to list audio devices: %v", err)
			return "[]"
		}
		data, _ := json.Marshal(devices)
		return string(data)
	})

	w.Bind("_getAudioLevel", func() string {
		if recorder == nil {
			return "0"
		}
		return fmt.Sprintf("%.4f", recorder.GetLevel())
	})

	w.Bind("_getAudioMonitorSnapshot", func() string {
		if recorder == nil {
			return `{"level":0,"peak":0,"average":0,"status":"checking"}`
		}
		data, _ := json.Marshal(recorder.GetMonitorSnapshot())
		return string(data)
	})

	w.Bind("_startAudioMonitor", func() string {
		if recorder == nil {
			return `{"success":false,"error":"no recorder"}`
		}
		recorder.SetGain(cfg.GetInputGain())
		recorder.SetInputDevice(cfg.GetInputDevice())
		if err := recorder.StartMonitor(); err != nil {
			logWarn("StartMonitor failed: %v", err)
			errJSON, _ := json.Marshal(err.Error())
			return fmt.Sprintf(`{"success":false,"error":%s}`, errJSON)
		}
		return `{"success":true}`
	})

	w.Bind("_stopAudioMonitor", func() {
		if recorder != nil {
			recorder.StopMonitor()
		}
	})

	w.Bind("openURL", func(url string) {
		if !strings.HasPrefix(url, "https://") {
			logWarn("openURL: blocked non-https URL: %s", url)
			return
		}
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	})

	w.Bind("switchRecordingMode", func(mode string) {
		if mode != "push_to_talk" && mode != "toggle" {
			return
		}
		cfg.mu.Lock()
		cfg.Mode = mode
		cfg.mu.Unlock()
		if err := cfg.Save(); err != nil {
			logError("Save config after recording mode switch: %v", err)
		}
		logInfo("Recording mode switched to: %s", mode)
	})

	w.Bind("getAvailableModels", func() string {
		modelList := availableModelEntries(cfg, models.ListDownloaded())
		data, _ := json.Marshal(modelList)
		return string(data)
	})

	w.Bind("switchModel", func(modelID string, isLocal bool) map[string]interface{} {
		if isLocal {
			if err := ensureLocalSTTAllowed(modelID, "use"); err != nil {
				logWarn("Model switch blocked by local STT preflight: %v", err)
				return map[string]interface{}{"success": false, "error": err.Error()}
			}
		}
		cfg.mu.Lock()
		if isLocal {
			cfg.ActiveModelLocal = true
			cfg.LocalModelID = modelID
		} else {
			cfg.ActiveModelLocal = false
			cfg.Model = modelID
		}
		cfg.mu.Unlock()
		if err := cfg.Save(); err != nil {
			logError("Save config after model switch failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}
		logInfo("Model switched to %s (local=%v)", modelID, isLocal)
		return map[string]interface{}{"success": true, "error": ""}
	})

	w.Bind("getSystemInfo", func() string {
		cfgPath, _ := configPath()
		dir, _ := configDir()
		logPath := filepath.Join(dir, logFile)
		preflight := localSTTPreflightViewFor("", "inspect")
		info := map[string]interface{}{
			"appVersion": AppVersion, "goVersion": runtime.Version(),
			"os": runtime.GOOS, "arch": runtime.GOARCH,
			"configPath": cfgPath, "logPath": logPath,
			"buildCommit": BuildCommit, "buildBranch": BuildBranch, "buildDate": BuildDate,
			"localSttPreflight": preflight,
		}
		data, _ := json.Marshal(info)
		return string(data)
	})

	// Error reporting toggle
	w.Bind("getErrorReportingEnabled", func() bool {
		return cfg.GetErrorReportingEnabled()
	})
	w.Bind("setErrorReportingEnabled", func(enabled bool) {
		cfg.SetErrorReportingEnabled(enabled)
		SetCrashReportingEnabled(enabled)
		if err := cfg.Save(); err != nil {
			logError("Save config after error reporting toggle: %v", err)
		}
		logInfo("Error reporting: enabled=%v", enabled)
	})
}
