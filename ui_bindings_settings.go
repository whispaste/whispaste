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

	"github.com/whispaste/whispaste/internal/models"
	"github.com/whispaste/whispaste/internal/wav"

	webview "github.com/webview/webview_go"
)

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
		cfg.FloatingButtonEnabled = newCfg.FloatingButtonEnabled
		cfg.FloatingButtonColor = newCfg.FloatingButtonColor
		cfg.FloatingButtonSize = newCfg.FloatingButtonSize
		cfg.mu.Unlock()
		if err := SetAutostart(newCfg.Autostart); err != nil {
			logWarn("Failed to set autostart: %v", err)
		}
		SetLanguage(newCfg.UILanguage)
		if err := cfg.Save(); err != nil {
			return map[string]interface{}{"success": false, "error": fmt.Sprintf("Save failed: %v", err)}
		}
		if onSaved != nil {
			onSaved()
		}
		return map[string]interface{}{"success": true, "error": ""}
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
			modelDir, mdErr := models.GetDir(cfg.GetLocalModelID())
			if mdErr != nil {
				return map[string]interface{}{"success": false, "text": "", "error": mdErr.Error()}
			}
			text, err2 = GetLocalRecognizer().Transcribe(pcm, 16000, cfg.Language, modelDir)
		} else {
			wavData := wav.Encode(pcm, 16000, 1, 16)
			text, err2 = Transcribe(context.Background(), wavData, cfg.Language, cfg.GetAPIKey(), model, cfg.GetAPIEndpoint(), "")
		}
		if err2 != nil {
			logError("Test transcription failed: %v", err2)
			return map[string]interface{}{"success": false, "text": "", "error": err2.Error()}
		}
		logInfo("Test transcription succeeded: %q", strings.TrimSpace(text))
		return map[string]interface{}{"success": true, "text": strings.TrimSpace(text), "error": ""}
	})

	// Test a specific STT model by transcribing 1 second of silence.
	// Validates the model loads and the recognizer pipeline works end-to-end.
	w.Bind("_testSTTModel", func(modelID string) map[string]interface{} {
		logInfo("STT model test started for %s", modelID)
		modelDir, err := models.GetDir(modelID)
		if err != nil {
			logError("STT model test: model dir: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		// Generate 1 second of silence at 16 kHz, 16-bit mono (32000 bytes)
		silentPCM := make([]byte, 32000)

		lang := cfg.Language
		if lang == "" {
			lang = "en"
		}

		// Use the panic-safe singleton recognizer (has defer/recover protection)
		text, err := GetLocalRecognizer().Transcribe(silentPCM, 16000, lang, modelDir)
		if err != nil {
			logError("STT model test failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		logInfo("STT model test passed for %s (result: %q)", modelID, text)
		return map[string]interface{}{"success": true, "text": strings.TrimSpace(text)}
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
		err := TestAPIKey(key, cfg.GetAPIEndpoint())
		if err != nil {
			return map[string]interface{}{"success": false, "error": err.Error()}
		}
		return map[string]interface{}{"success": true, "error": ""}
	})
	w.Bind("_getModels", func() []map[string]interface{} {
		var result []map[string]interface{}
		for _, m := range models.Available {
			result = append(result, map[string]interface{}{
				"id": m.ID, "name": m.Name, "size": m.Size,
				"downloaded": models.IsDownloaded(m.ID),
			})
		}
		return result
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
			err := models.Download(modelID, func(fileDownloaded, fileTotal int64, fileIdx, fileCount int, fileName string) {
				var pct int
				if fileTotal > 0 {
					pct = int(float64(fileDownloaded) / float64(fileTotal) * 100)
					if pct > 100 {
						pct = 100
					}
				}
				safeDispatch(fmt.Sprintf("window.updateModelProgress('%s', %d, %d, %d, '%s')", escapeJS(modelID), pct, fileIdx+1, fileCount, escapeJS(fileName)))
			})
			if err != nil {
				logError("Model download failed: %v", err)
				safeDispatch(fmt.Sprintf("window.downloadComplete('%s', false, '%s')", escapeJS(modelID), escapeJS(err.Error())))
				return
			}
			logInfo("Model downloaded: %s", modelID)
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
			} else if cfg.HasAPIKey() {
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

	w.Bind("_startAudioMonitor", func() string {
		if recorder == nil {
			return `{"success":false,"error":"no recorder"}`
		}
		recorder.SetGain(cfg.GetInputGain())
		if err := recorder.StartMonitor(); err != nil {
			logWarn("StartMonitor failed: %v", err)
			return fmt.Sprintf(`{"success":false,"error":"%s"}`, err.Error())
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
		type modelInfo struct {
			ID      string `json:"id"`
			Name    string `json:"name"`
			Meta    string `json:"meta"`
			IsLocal bool   `json:"isLocal"`
		}
		var modelList []modelInfo
		if cfg.GetAPIKey() != "" {
			cfg.mu.RLock()
			apiModel := cfg.Model
			cfg.mu.RUnlock()
			if apiModel == "" {
				apiModel = "whisper-1"
			}
			modelList = append(modelList, modelInfo{ID: apiModel, Name: "Whisper API (" + apiModel + ")", Meta: "Cloud", IsLocal: false})
		}
		for _, m := range models.ListDownloaded() {
			modelList = append(modelList, modelInfo{ID: m.ID, Name: m.Name, Meta: "Local · " + m.Size, IsLocal: true})
		}
		data, _ := json.Marshal(modelList)
		return string(data)
	})

	w.Bind("switchModel", func(modelID string, isLocal bool) {
		cfg.mu.Lock()
		if isLocal {
			cfg.ActiveModelLocal = true
			cfg.LocalModelID = modelID
		} else {
			cfg.ActiveModelLocal = false
			cfg.Model = modelID
		}
		cfg.mu.Unlock()
		cfg.Save()
		logInfo("Model switched to %s (local=%v)", modelID, isLocal)
	})

	w.Bind("getSystemInfo", func() string {
		cfgPath, _ := configPath()
		dir, _ := configDir()
		logPath := filepath.Join(dir, logFile)
		info := map[string]string{
			"appVersion": AppVersion, "goVersion": runtime.Version(),
			"os": runtime.GOOS, "arch": runtime.GOARCH,
			"configPath": cfgPath, "logPath": logPath,
			"buildCommit": BuildCommit, "buildBranch": BuildBranch, "buildDate": BuildDate,
		}
		data, _ := json.Marshal(info)
		return string(data)
	})
}
