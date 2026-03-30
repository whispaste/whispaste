package main

import (
	"encoding/json"
	"fmt"

	webview "github.com/webview/webview_go"
)

// bindSmartHandlers registers smart mode, template, text replacement, app detection, and LLM JS bindings.
func bindSmartHandlers(w webview.WebView, cfg *Config, history *History) {

	// resolveSmartEndpoint determines the correct endpoint and API key for smart
	// mode operations, based on the SmartModeProvider config setting.
	resolveSmartEndpoint := func() (endpoint, apiKey, modelType string, err error) {
		provider := cfg.GetSmartModeProvider()

		if provider == "local" || (provider == "auto" && IsLLMInstalled()) {
			localEndpoint, llmErr := localLLM.Start()
			if llmErr == nil {
				return localEndpoint, "local", "local", nil
			}
			if provider == "local" {
				return "", "", "", fmt.Errorf("local LLM required but not available: %w", llmErr)
			}
			logWarn("Local LLM start failed, falling back to cloud: %v", llmErr)
		}

		return cfg.GetAPIEndpoint(), cfg.GetAPIKey(), "cloud", nil
	}

	w.Bind("applySmartAction", func(entryID, preset, customPrompt string) string {
		entry := history.GetByID(entryID)
		if entry == nil {
			resp, _ := json.Marshal(map[string]string{"error": "Entry not found"})
			return string(resp)
		}
		endpoint, apiKey, modelType, err := resolveSmartEndpoint()
		if err != nil {
			resp, _ := json.Marshal(map[string]string{"error": err.Error()})
			return string(resp)
		}
		appLang := cfg.GetUILanguage()
		if appLang == "" {
			appLang = "en"
		}
		result, err := ApplySmartAction(entry.Text, preset, customPrompt, apiKey, endpoint, appLang, cfg.GetCustomTemplates())
		if err != nil {
			resp, _ := json.Marshal(map[string]string{"error": err.Error()})
			return string(resp)
		}
		resp, _ := json.Marshal(map[string]string{"text": result, "model": modelType})
		return string(resp)
	})

	w.Bind("applyBulkSmartAction", func(idsJSON, preset, customPrompt string) string {
		var ids []string
		if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
			resp, _ := json.Marshal(map[string]string{"error": "invalid input"})
			return string(resp)
		}
		if len(ids) < 2 {
			resp, _ := json.Marshal(map[string]string{"error": "need at least 2 entries"})
			return string(resp)
		}

		// Collect texts and languages from all selected entries
		var texts []string
		langCount := map[string]int{}
		for _, id := range ids {
			entry := history.GetByID(id)
			if entry != nil && entry.Text != "" {
				texts = append(texts, entry.Text)
				if entry.Language != "" {
					langCount[entry.Language]++
				}
			}
		}
		if len(texts) < 2 {
			resp, _ := json.Marshal(map[string]string{"error": "need at least 2 entries with text"})
			return string(resp)
		}

		// Join texts with separator for the LLM
		combined := joinTextsForBulk(texts)

		endpoint, apiKey, modelType, err := resolveSmartEndpoint()
		if err != nil {
			resp, _ := json.Marshal(map[string]string{"error": err.Error()})
			return string(resp)
		}
		appLang := cfg.GetUILanguage()
		if appLang == "" {
			appLang = "en"
		}

		// Use a compound prompt: merge coherently, then apply the preset
		bulkPrompt := buildBulkSmartPrompt(preset, customPrompt, appLang, cfg.GetCustomTemplates())
		if bulkPrompt == "" {
			resp, _ := json.Marshal(map[string]string{"error": "unknown preset"})
			return string(resp)
		}

		result, err := PostProcess(combined, "custom", bulkPrompt, "", apiKey, endpoint, appLang, cfg.GetCustomTemplates())
		if err != nil {
			resp, _ := json.Marshal(map[string]string{"error": err.Error()})
			return string(resp)
		}
		// Determine dominant language from source entries
		dominantLang := appLang
		maxCount := 0
		for lang, count := range langCount {
			if count > maxCount {
				maxCount = count
				dominantLang = lang
			}
		}
		resp, _ := json.Marshal(map[string]string{"text": result, "language": dominantLang, "model": modelType})
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

	w.Bind("addBulkSmartEntry", func(text, preset, lang string) {
		if lang == "" {
			lang = cfg.GetUILanguage()
			if lang == "" {
				lang = "en"
			}
		}
		history.AddSmart(text, lang, []string{"smart:bulk:" + preset})
		logInfo("New bulk smart entry created using preset %s", preset)
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

	w.Bind("getTextReplacementsAI", func() bool {
		return cfg.GetTextReplacementsAI()
	})

	w.Bind("setTextReplacementsAI", func(enabled bool) {
		cfg.SetTextReplacementsAI(enabled)
		if err := cfg.Save(); err != nil {
			logError("Save text replacements AI: %v", err)
		}
	})

	w.Bind("getTextReplacementProvider", func() string { return cfg.GetTextReplacementProvider() })

	w.Bind("setTextReplacementProvider", func(provider string) {
		cfg.SetTextReplacementProvider(provider)
		if err := cfg.Save(); err != nil {
			logError("Save text replacement provider: %v", err)
		}
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

	w.Bind("downloadLLM", func(modelID string) map[string]interface{} {
		if modelID == "" {
			modelID = cfg.GetLocalLLMModel()
		}
		mid := modelID // capture for goroutine
		go func() {
			err := DownloadLLM(mid, cfg.GetGPUAcceleration(), func(phase string, pct int) {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onLLMDownloadProgress==='function')onLLMDownloadProgress('%s',%d,'%s')", escapeJS(phase), pct, escapeJS(mid))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
			})
			if err != nil {
				logError("LLM download failed: %v", err)
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onLLMDownloadError==='function')onLLMDownloadError('%s','%s')", escapeJS(err.Error()), escapeJS(mid))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			if mainWebview != nil {
				js := fmt.Sprintf("if(typeof onLLMDownloadComplete==='function')onLLMDownloadComplete('%s')", escapeJS(mid))
				mainWebview.Dispatch(func() { mainWebview.Eval(js) })
			}
		}()
		return map[string]interface{}{"status": "started"}
	})

	w.Bind("deleteLLM", func(modelID string) bool {
		if modelID == "" {
			modelID = cfg.GetLocalLLMModel()
		}
		localLLM.Stop()
		return DeleteLLMModel(modelID) == nil
	})

	w.Bind("getLLMStatus", func() string {
		result := map[string]interface{}{
			"installed":       IsLLMInstalled(),
			"running":         localLLM.IsRunning(),
			"serverInstalled": IsLLMServerInstalled(),
			"selectedModel":   cfg.GetLocalLLMModel(),
			"models":          map[string]interface{}{},
		}
		models := result["models"].(map[string]interface{})
		for id, m := range LLMModels {
			models[id] = map[string]interface{}{
				"id":        m.ID,
				"name":      m.Name,
				"size":      m.Size,
				"langs":     m.Langs,
				"filename":  m.Filename,
				"installed": IsLLMModelInstalled(id),
			}
		}
		data, _ := json.Marshal(result)
		return string(data)
	})

	w.Bind("setLocalLLMModel", func(modelID string) {
		if _, ok := LLMModels[modelID]; !ok {
			return
		}
		cfg.mu.Lock()
		cfg.LocalLLMModel = modelID
		cfg.mu.Unlock()
		cfg.Save()
		// Restart server with new model if running
		if localLLM.IsRunning() {
			localLLM.Stop()
		}
		logInfo("Local LLM model set to: %s", modelID)
	})

	w.Bind("getAvailableLLMModels", func() string {
		result := make([]map[string]interface{}, 0, len(LLMModels))
		for _, m := range LLMModels {
			result = append(result, map[string]interface{}{
				"id":        m.ID,
				"name":      m.Name,
				"size":      m.Size,
				"langs":     m.Langs,
				"installed": IsLLMModelInstalled(m.ID),
			})
		}
		data, _ := json.Marshal(result)
		return string(data)
	})

	// Test the local LLM by starting the server (if needed) and sending a simple prompt.
	w.Bind("_testLLMModel", func() map[string]interface{} {
		logInfo("LLM model test started")
		if !IsLLMInstalled() {
			return map[string]interface{}{"success": false, "error": "LLM not installed"}
		}

		endpoint, err := localLLM.Start()
		if err != nil {
			logError("LLM model test: start failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		result, err := PostProcess("Hello, this is a test.", "cleanup", "", "", "", endpoint, "en", nil)
		if err != nil {
			logError("LLM model test failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		logInfo("LLM model test passed (result: %q)", result)
		return map[string]interface{}{"success": true, "text": result}
	})
}
