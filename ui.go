package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"log"
	"os/exec"
	"runtime"
	"strings"
	"time"

	webview "github.com/webview/webview_go"
)

//go:embed ui_settings.html
var settingsHTML string

// ShowSettings opens the settings window with WebView2.
func ShowSettings(cfg *Config, recorder *Recorder, onSaved func()) {
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		w := webview.New(true)
		if w == nil {
			return
		}
		defer w.Destroy()

		w.SetTitle(T("settings.title") + " – " + AppName)
		w.SetSize(520, 640, webview.HintNone)

		// Inject the current language before page loads
		w.Init(fmt.Sprintf(`window._lang = "%s";`, cfg.UILanguage))

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
			cfg.UILanguage = newCfg.UILanguage
			cfg.mu.Unlock()

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
		w.Bind("testRecording", func() map[string]interface{} {
			if !cfg.HasAPIKey() {
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   T("error.no_api_key"),
				}
			}
			if recorder == nil {
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   "Recorder not available",
				}
			}

			if err := recorder.Start(); err != nil {
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
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   errMsg,
				}
			}

			wav := EncodeWAV(pcm, 16000, 1, 16)
			text, err := Transcribe(wav, cfg.Language, cfg.GetAPIKey(), cfg.Model)
			if err != nil {
				return map[string]interface{}{
					"success": false,
					"text":    "",
					"error":   err.Error(),
				}
			}
			return map[string]interface{}{
				"success": true,
				"text":    strings.TrimSpace(text),
				"error":   "",
			}
		})

		// Bind: openURL → opens URL in default browser (https only)
		w.Bind("openURL", func(url string) {
			if !strings.HasPrefix(url, "https://") {
				log.Printf("openURL: blocked non-https URL: %s", url)
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


