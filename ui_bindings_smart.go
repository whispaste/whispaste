package main

import (
	"encoding/json"
	"fmt"

	webview "github.com/webview/webview_go"
)

// bindSmartHandlers registers smart mode, template, text replacement, app detection, and LLM JS bindings.
func bindSmartHandlers(w webview.WebView, cfg *Config, history *History) {

	w.Bind("applySmartAction", func(entryID, preset, customPrompt string) string {
		entry := history.GetByID(entryID)
		if entry == nil {
			resp, _ := json.Marshal(map[string]string{"error": "Entry not found"})
			return string(resp)
		}
		apiKey := cfg.GetAPIKey()
		endpoint := cfg.GetAPIEndpoint()
		appLang := cfg.GetUILanguage()
		if appLang == "" {
			appLang = "en"
		}
		result, err := ApplySmartAction(entry.Text, preset, customPrompt, apiKey, endpoint, appLang, cfg.GetCustomTemplates())
		if err != nil {
			resp, _ := json.Marshal(map[string]string{"error": err.Error()})
			return string(resp)
		}
		resp, _ := json.Marshal(map[string]string{"text": result})
		return string(resp)
	})

	w.Bind("addSmartEntry", func(sourceID, text, preset string) {
		entry := history.GetByID(sourceID)
		if entry == nil {
			return
		}
		history.AddSmart(text, entry.Language, []string{"smart:" + preset})
		logInfo("New smart entry created from %s using preset %s", sourceID, preset)
	})

	w.Bind("setSmartPreset", func(preset string) {
		cfg.SetSmartModePreset(preset)
		if err := cfg.Save(); err != nil {
			logError("Save config after smart preset switch: %v", err)
		}
		logInfo("Smart mode preset switched to: %s (enabled=%v)", preset, cfg.GetSmartMode())
	})

	w.Bind("saveCustomTemplate", func(name, prompt string) {
		cfg.SaveCustomTemplate(name, prompt)
		if err := cfg.Save(); err != nil {
			logError("Save custom template %q: %v", name, err)
		}
		logInfo("Custom template saved: %s", name)
	})

	w.Bind("deleteCustomTemplate", func(name string) {
		cfg.DeleteCustomTemplate(name)
		if err := cfg.Save(); err != nil {
			logError("Delete custom template %q: %v", name, err)
		}
		logInfo("Custom template deleted: %s", name)
	})

	w.Bind("getCustomTemplates", func() string {
		templates := cfg.GetCustomTemplates()
		data, _ := json.Marshal(templates)
		return string(data)
	})

	w.Bind("getBuiltinPresets", func() string {
		presets := GetBuiltinPresets()
		data, _ := json.Marshal(presets)
		return string(data)
	})

	w.Bind("getTextReplacements", func() string {
		items := cfg.GetTextReplacements()
		data, _ := json.Marshal(items)
		return string(data)
	})

	w.Bind("setTextReplacements", func(jsonStr string) {
		var items []TextReplacement
		if err := json.Unmarshal([]byte(jsonStr), &items); err != nil {
			logError("Parse text replacements: %v", err)
			return
		}
		cfg.SetTextReplacements(items)
		if err := cfg.Save(); err != nil {
			logError("Save text replacements: %v", err)
		}
	})

	w.Bind("setTextReplacementsEnabled", func(enabled bool) {
		cfg.SetTextReplacementsEnabled(enabled)
		if err := cfg.Save(); err != nil {
			logError("Save text replacements enabled: %v", err)
		}
	})

	w.Bind("getTextReplacementsEnabled", func() bool {
		return cfg.GetTextReplacementsEnabled()
	})

	w.Bind("getAppPresets", func() string {
		m := cfg.GetAppPresets()
		data, _ := json.Marshal(m)
		return string(data)
	})

	w.Bind("setAppPresets", func(jsonStr string) {
		var m map[string]string
		if err := json.Unmarshal([]byte(jsonStr), &m); err != nil {
			logError("Parse app presets: %v", err)
			return
		}
		cfg.SetAppPresets(m)
		if err := cfg.Save(); err != nil {
			logError("Save app presets: %v", err)
		}
	})

	w.Bind("setAppDetectionEnabled", func(enabled bool) {
		cfg.mu.Lock()
		cfg.AppDetection = enabled
		cfg.mu.Unlock()
		if err := cfg.Save(); err != nil {
			logError("Save app detection: %v", err)
		}
	})

	w.Bind("getAppDetectionEnabled", func() bool { return cfg.GetAppDetectionEnabled() })
	w.Bind("getActiveAppName", func() string { return GetActiveAppName() })
	w.Bind("getSmartModeProvider", func() string { return cfg.GetSmartModeProvider() })

	w.Bind("setSmartModeProvider", func(provider string) {
		cfg.mu.Lock()
		cfg.SmartModeProvider = provider
		cfg.mu.Unlock()
		cfg.Save()
	})

	w.Bind("getFallbackPreset", func() string { return cfg.GetFallbackPreset() })

	w.Bind("setFallbackPreset", func(preset string) {
		cfg.mu.Lock()
		cfg.FallbackPreset = preset
		cfg.mu.Unlock()
		cfg.Save()
	})

	w.Bind("getTemplateMetas", func() string {
		metas := cfg.GetTemplateMetas()
		defaults := GetDefaultTemplateMetas()
		for k, v := range defaults {
			if _, exists := metas[k]; !exists {
				metas[k] = v
			}
		}
		data, _ := json.Marshal(metas)
		return string(data)
	})

	w.Bind("setTemplateMeta", func(name, metaJSON string) {
		var meta TemplateMeta
		if err := json.Unmarshal([]byte(metaJSON), &meta); err != nil {
			logWarn("Invalid template meta JSON: %v", err)
			return
		}
		cfg.mu.Lock()
		if cfg.TemplateMetas == nil {
			cfg.TemplateMetas = make(map[string]TemplateMeta)
		}
		cfg.TemplateMetas[name] = meta
		cfg.mu.Unlock()
		cfg.Save()
	})

	w.Bind("checkConnectivity", func() bool { return checkConnectivity() })
	w.Bind("isLLMInstalled", func() bool { return IsLLMInstalled() })

	w.Bind("downloadLLM", func() map[string]interface{} {
		go func() {
			err := DownloadLLM(func(phase string, pct int) {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onLLMDownloadProgress==='function')onLLMDownloadProgress('%s',%d)", phase, pct)
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
			})
			if err != nil {
				logError("LLM download failed: %v", err)
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onLLMDownloadError==='function')onLLMDownloadError('%s')", escapeJS(err.Error()))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			if mainWebview != nil {
				mainWebview.Dispatch(func() { mainWebview.Eval("if(typeof onLLMDownloadComplete==='function')onLLMDownloadComplete()") })
			}
		}()
		return map[string]interface{}{"status": "started"}
	})

	w.Bind("deleteLLM", func() bool {
		localLLM.Stop()
		return DeleteLLM() == nil
	})

	w.Bind("getLLMStatus", func() string {
		status := map[string]interface{}{
			"installed": IsLLMInstalled(),
			"running":   localLLM.IsRunning(),
		}
		data, _ := json.Marshal(status)
		return string(data)
	})
}
