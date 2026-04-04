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

	w.Bind("applySmartAction", func(entryID, preset, customPrompt, targetLang string) string {
		entry := history.GetByID(entryID)
		if entry == nil {
			resp, _ := json.Marshal(map[string]string{"error": T("error.entry_not_found")})
			return string(resp)
		}
		// Capture values for goroutine (avoid data race on entry pointer)
		entryText := entry.Text
		entryLang := entry.Language
		langHint := entry.Language
		if langHint == "" {
			langHint = entry.LanguageHint
		}
		if (langHint == "" || langHint == "auto") && entry.IsLocal {
			langHint = cfg.GetEffectiveLocalTranscriptionLanguage()
		}
		customTemplates := cfg.GetCustomTemplates()

		go func() {
			endpoint, apiKey, modelType, err := resolveSmartEndpoint()
			if err != nil {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onSmartActionComplete==='function')onSmartActionComplete(%s,'','%s')", jsStr(entryID), escapeJS(err.Error()))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			result, err := ApplySmartAction(entryText, preset, customPrompt, targetLang, apiKey, endpoint, langHint, customTemplates)
			if err != nil {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onSmartActionComplete==='function')onSmartActionComplete(%s,'','%s')", jsStr(entryID), escapeJS(err.Error()))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			resultLang := ""
			if preset == "translate" && targetLang != "" {
				resultLang = targetLang
			} else if entryLang != "" && entryLang != "auto" {
				resultLang = entryLang
			}
			respJSON, _ := json.Marshal(map[string]string{"text": result, "model": modelType, "language": resultLang})
			if mainWebview != nil {
				js := fmt.Sprintf("if(typeof onSmartActionComplete==='function')onSmartActionComplete(%s,%s,'')", jsStr(entryID), jsStr(string(respJSON)))
				mainWebview.Dispatch(func() { mainWebview.Eval(js) })
			}
		}()

		resp, _ := json.Marshal(map[string]string{"status": "processing"})
		return string(resp)
	})

	w.Bind("applyBulkSmartAction", func(idsJSON, preset, customPrompt, targetLang string) string {
		var ids []string
		if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
			resp, _ := json.Marshal(map[string]string{"error": "invalid input"})
			return string(resp)
		}
		if len(ids) < 2 {
			resp, _ := json.Marshal(map[string]string{"error": "need at least 2 entries"})
			return string(resp)
		}

		// Collect texts and languages synchronously (fast, no I/O)
		var texts []string
		langCount := map[string]int{}
		allLocal := true
		for _, id := range ids {
			entry := history.GetByID(id)
			if entry != nil && entry.Text != "" {
				texts = append(texts, entry.Text)
				if !entry.IsLocal {
					allLocal = false
				}
				entryLang := entry.Language
				if entryLang == "" {
					entryLang = entry.LanguageHint
				}
				if entryLang != "" && entryLang != "auto" {
					langCount[entryLang]++
				}
			}
		}
		if len(texts) < 2 {
			resp, _ := json.Marshal(map[string]string{"error": "need at least 2 entries with text"})
			return string(resp)
		}

		combined := joinTextsForBulk(texts)
		dominantLang := ""
		maxCount := 0
		for lang, count := range langCount {
			if count > maxCount {
				maxCount = count
				dominantLang = lang
			}
		}
		if dominantLang == "" && allLocal {
			dominantLang = cfg.GetEffectiveLocalTranscriptionLanguage()
		}
		customTemplates := cfg.GetCustomTemplates()

		go func() {
			endpoint, apiKey, modelType, err := resolveSmartEndpoint()
			if err != nil {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onBulkSmartActionComplete==='function')onBulkSmartActionComplete('','%s')", escapeJS(err.Error()))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			bulkPrompt := buildBulkSmartPrompt(preset, customPrompt, targetLang, dominantLang, customTemplates)
			if bulkPrompt == "" {
				if mainWebview != nil {
					js := "if(typeof onBulkSmartActionComplete==='function')onBulkSmartActionComplete('','unknown preset')"
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			result, err := PostProcess(combined, "system", bulkPrompt, "", apiKey, endpoint, dominantLang, "", customTemplates)
			if err != nil {
				if mainWebview != nil {
					js := fmt.Sprintf("if(typeof onBulkSmartActionComplete==='function')onBulkSmartActionComplete('','%s')", escapeJS(err.Error()))
					mainWebview.Dispatch(func() { mainWebview.Eval(js) })
				}
				return
			}
			finalLang := dominantLang
			if preset == "translate" && targetLang != "" {
				finalLang = targetLang
			} else if finalLang == "auto" {
				finalLang = ""
			}
			respJSON, _ := json.Marshal(map[string]string{"text": result, "language": finalLang, "model": modelType})
			if mainWebview != nil {
				js := fmt.Sprintf("if(typeof onBulkSmartActionComplete==='function')onBulkSmartActionComplete(%s,'')", jsStr(string(respJSON)))
				mainWebview.Dispatch(func() { mainWebview.Eval(js) })
			}
		}()

		resp, _ := json.Marshal(map[string]string{"status": "processing"})
		return string(resp)
	})

	w.Bind("addSmartEntry", func(sourceID, text, preset, lang string) {
		entry := history.GetByID(sourceID)
		if entry == nil {
			return
		}
		if lang == "" {
			lang = entry.Language
		}
		langHint := lang
		if langHint == "" {
			langHint = entry.LanguageHint
		}
		history.AddSmartHint(text, lang, langHint, []string{"smart:" + preset})
		logInfo("New smart entry created from %s using preset %s", sourceID, preset)
	})

	w.Bind("addBulkSmartEntry", func(text, preset, lang string) {
		if lang == "auto" {
			lang = ""
		}
		history.AddSmartHint(text, lang, lang, []string{"smart:bulk:" + preset})
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

	w.Bind("exportTemplate", func(name string) string {
		templates := cfg.GetCustomTemplates()
		prompt, ok := templates[name]
		if !ok {
			return ""
		}
		export := TemplateExport{
			Name:    name,
			Prompt:  prompt,
			Version: 1,
		}
		data, _ := json.Marshal(export)
		return string(data)
	})

	w.Bind("exportAllTemplates", func() string {
		templates := cfg.GetCustomTemplates()
		exports := make([]TemplateExport, 0, len(templates))
		for name, prompt := range templates {
			exports = append(exports, TemplateExport{
				Name:    name,
				Prompt:  prompt,
				Version: 1,
			})
		}
		data, _ := json.Marshal(exports)
		return string(data)
	})

	w.Bind("importTemplate", func(jsonStr string) string {
		var tmpl TemplateExport
		if err := json.Unmarshal([]byte(jsonStr), &tmpl); err != nil {
			return `{"error":"invalid template format"}`
		}
		if tmpl.Name == "" || tmpl.Prompt == "" {
			return `{"error":"name and prompt are required"}`
		}
		if len(tmpl.Name) > 50 {
			return `{"error":"name too long (max 50 characters)"}`
		}
		if len(tmpl.Prompt) > 2000 {
			return `{"error":"prompt too long (max 2000 characters)"}`
		}
		// Reject names that collide with builtin presets
		if _, isBuiltin := smartModePresets[tmpl.Name]; isBuiltin {
			return `{"error":"cannot overwrite builtin preset"}`
		}
		cfg.SaveCustomTemplate(tmpl.Name, tmpl.Prompt)
		if err := cfg.Save(); err != nil {
			logError("Import template %q: %v", tmpl.Name, err)
			return `{"error":"save failed"}`
		}
		logInfo("Template imported: %s", tmpl.Name)
		return `{"ok":true,"name":"` + tmpl.Name + `"}`
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
				"size":      formatBytes(uint64(m.Size)),
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
				"size":      formatBytes(uint64(m.Size)),
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
			return map[string]interface{}{"success": false, "error": T("error.llm_not_installed")}
		}

		endpoint, err := localLLM.Start()
		if err != nil {
			logError("LLM model test: start failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		result, err := PostProcess("Hello, this is a test.", "cleanup", "", "", "", endpoint, "en", cfg.GetLocalLLMModel(), nil)
		if err != nil {
			logError("LLM model test failed: %v", err)
			return map[string]interface{}{"success": false, "error": err.Error()}
		}

		logInfo("LLM model test passed (result: %q)", result)
		return map[string]interface{}{"success": true, "text": result}
	})
}
