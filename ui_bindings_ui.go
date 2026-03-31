package main

import (
	"encoding/json"

	webview "github.com/webview/webview_go"
	"github.com/whispaste/whispaste/internal/stats"
)

// bindUIHandlers registers theme, language, translation, onboarding, and window control JS bindings.
func bindUIHandlers(w webview.WebView, cfg *Config, recorder *Recorder, history *History, usageStats *stats.UsageStats) {

	w.Bind("completeOnboarding", func() {
		cfg.SetOnboardingDone(true)
		if err := cfg.Save(); err != nil {
			logError("Save config after onboarding: %v", err)
		}
		logInfo("Onboarding completed")
	})

	w.Bind("resetOnboarding", func() {
		cfg.SetOnboardingDone(false)
		if err := cfg.Save(); err != nil {
			logError("Save config after onboarding reset: %v", err)
		}
		logInfo("Onboarding reset")
	})

	w.Bind("recordOnboardingEvent", func(name string) {
		if usageStats == nil {
			return
		}
		usageStats.RecordEvent(name)
	})

	w.Bind("getTheme", func() string {
		cfg.mu.RLock()
		defer cfg.mu.RUnlock()
		return cfg.Theme
	})

	w.Bind("setTheme", func(theme string) {
		if theme != "system" && theme != "light" && theme != "dark" {
			return
		}
		logDebug("Theme: saving '%s' to config", theme)
		cfg.mu.Lock()
		cfg.Theme = theme
		cfg.mu.Unlock()
		if err := cfg.Save(); err != nil {
			logWarn("Failed to save theme: %v", err)
		}
	})

	w.Bind("getUILanguage", func() string { return cfg.GetUILanguage() })

	w.Bind("setUILanguage", func(lang string) {
		if lang != "en" && lang != "de" {
			return
		}
		cfg.mu.Lock()
		cfg.UILanguage = lang
		cfg.mu.Unlock()
		SetLanguage(lang)
		if err := cfg.Save(); err != nil {
			logWarn("Failed to save language: %v", err)
		}
	})

	w.Bind("getTranslations", func() (string, error) {
		keys := []string{
			"notebook.title", "notebook.search", "notebook.all",
			"notebook.pinned", "notebook.today", "notebook.this_week",
			"notebook.older", "notebook.empty", "notebook.no_results",
			"notebook.copy", "notebook.delete", "notebook.pin",
			"notebook.unpin", "notebook.copied", "notebook.confirm_delete",
			"notebook.uncategorized",
			"notebook.sort", "notebook.sort_newest", "notebook.sort_oldest",
			"notebook.sort_alpha", "notebook.sort_duration",
			"notebook.add_tag", "notebook.tag_updated",
			"notebook.export", "notebook.export_txt", "notebook.export_md",
			"notebook.exported", "notebook.export_selected",
			"settings.title", "settings.api_key", "settings.api_key_hint",
			"settings.hotkey", "settings.mode", "settings.mode_ptt", "settings.mode_toggle",
			"settings.language", "settings.language_auto", "settings.ui_language",
			"settings.overlay", "settings.overlay_top", "settings.overlay_cursor",
			"settings.auto_paste", "settings.play_sounds", "settings.check_updates",
			"settings.save", "settings.cancel", "settings.test",
			"settings.test_recording", "settings.test_success", "settings.test_error",
			"settings.saved", "settings.about", "settings.general",
			"settings.audio", "settings.appearance",
			"settings.show_key", "settings.hide_key",
			"settings.theme", "settings.theme_light", "settings.theme_dark", "settings.theme_system",
			"settings.smart_mode", "settings.smart_preset",
			"settings.smart_preset_off", "settings.smart_preset_cleanup",
			"settings.smart_preset_email", "settings.smart_preset_bullets",
			"settings.smart_preset_formal", "settings.smart_preset_translate",
			"settings.smart_preset_custom",
			"settings.smart_prompt", "settings.smart_prompt_hint",
			"settings.smart_target", "settings.smart_cost_note",
			"settings.api_endpoint", "settings.api_endpoint_hint",
			"settings.whisper_prompt", "settings.whisper_prompt_hint",
			"settings.max_duration", "settings.max_duration_fmt", "settings.unlimited",
			"stats.title", "stats.dictations", "stats.words",
			"stats.time_saved", "stats.minutes", "stats.cost",
			"app.name", "app.description", "app.version",
			"update.check", "update.up_to_date", "update.available",
		}
		tr := map[string]string{}
		for _, k := range keys {
			tr[k] = T(k)
		}
		data, err := json.Marshal(tr)
		if err != nil {
			return "{}", err
		}
		return string(data), nil
	})

	w.Bind("closeWindow", func() {
		if recorder != nil {
			recorder.StopMonitor()
		}
		w.Terminate()
	})

	w.Bind("isStorePackage", func() bool {
		return isStorePackage()
	})

	// Demo mode toggle (hidden on About page for marketing screenshots)
	// Blocked in Store package builds — demo data could confuse Store reviewers
	w.Bind("isDemoMode", func() bool {
		if isStorePackage() {
			return false
		}
		return history.IsDemoMode()
	})

	w.Bind("toggleDemoMode", func() bool {
		if isStorePackage() {
			return false
		}
		if history.IsDemoMode() {
			history.DisableDemoMode()
			return false
		}
		if err := history.EnableDemoMode(); err != nil {
			logError("Enable demo mode: %v", err)
			return false
		}
		return true
	})
}
