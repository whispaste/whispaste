package main

import "sync"

var (
	langMu      sync.RWMutex
	currentLang = "en"
)

// T returns the localized string for the given key.
func T(key string) string {
	langMu.RLock()
	lang := currentLang
	langMu.RUnlock()
	if s, ok := translations[lang][key]; ok {
		return s
	}
	if s, ok := translations["en"][key]; ok {
		return s
	}
	return key
}

// SetLanguage sets the current UI language ("en" or "de").
func SetLanguage(lang string) {
	if _, ok := translations[lang]; ok {
		langMu.Lock()
		currentLang = lang
		langMu.Unlock()
	}
}

// GetLanguage returns the current UI language.
func GetLanguage() string {
	langMu.RLock()
	defer langMu.RUnlock()
	return currentLang
}

// SupportedLanguages returns all supported language codes.
func SupportedLanguages() []string {
	return []string{"en", "de"}
}

var translations = map[string]map[string]string{
	"en": {
		// App
		"app.name":        "Whispaste",
		"app.description": "Voice to text, pasted anywhere",
		"app.version":     AppVersion,

		// Tray menu
		"tray.tooltip":   "Whispaste – Voice to Text",
		"tray.settings":  "Settings",
		"tray.about":     "About",
		"tray.support":   "Support Whispaste",
		"tray.quit":      "Quit",

		// States
		"state.idle":          "Ready",
		"state.recording":     "Recording…",
		"state.transcribing":  "Transcribing…",
		"state.success":       "Done!",
		"state.error":         "Error",

		// Overlay
		"overlay.recording":    "Recording",
		"overlay.paused":       "Paused",
		"overlay.transcribing": "Transcribing…",
		"overlay.done":         "Pasted!",
		"overlay.copied":       "Copied to clipboard ✓",
		"overlay.error":        "Error: %s",

		// Settings
		"settings.title":           "Settings",
		"settings.api_key":         "OpenAI API Key",
		"settings.api_key_hint":    "Enter your OpenAI API key (starts with sk-)",
		"settings.hotkey":          "Hotkey",
		"settings.mode":            "Mode",
		"settings.mode_ptt":        "Push to Talk (hold key)",
		"settings.mode_toggle":     "Toggle (press to start/stop)",
		"settings.language":        "Transcription Language",
		"settings.language_auto":   "Auto-detect",
		"settings.ui_language":     "Interface Language",
		"settings.overlay":         "Overlay Position",
		"settings.overlay_top":     "Top Center",
		"settings.overlay_cursor":  "Near Cursor",
		"settings.auto_paste":      "Auto-paste transcription",
		"settings.play_sounds":     "Play sound feedback",
		"settings.check_updates":   "Check for updates automatically",
		"settings.save":            "Save",
		"settings.cancel":          "Cancel",
		"settings.test":            "Test",
		"settings.test_recording":  "Recording for 3 seconds…",
		"settings.test_success":    "Transcription: %s",
		"settings.test_error":      "Error: %s",
		"settings.saved":           "Settings saved!",
		"settings.about":           "About",
		"settings.general":         "General",
		"settings.audio":           "Audio",
		"settings.appearance":      "Appearance",
		"settings.show_key":        "Show",
		"settings.hide_key":        "Hide",
		"settings.theme":           "Theme",
		"settings.theme_light":     "Light",
		"settings.theme_dark":      "Dark",
		"settings.theme_system":    "System",

		// First run
		"firstrun.title":    "Welcome to Whispaste",
		"firstrun.message":  "To get started, you need an OpenAI API key.",
		"firstrun.get_key":  "Get API Key",
		"firstrun.enter":    "Enter your API key:",
		"firstrun.continue": "Continue",

		// Errors
		"error.no_api_key":     "No API key configured. Right-click the tray icon → Settings.",
		"error.recording":      "Recording failed: %s",
		"error.transcription":  "Transcription failed: %s",
		"error.hotkey":         "Could not register hotkey %s. It may be used by another application.",
		"error.microphone":     "Could not access microphone: %s",
		"error.clipboard":      "Could not access clipboard: %s",

		// Updates
		"update.available":     "Update available: v%s",
		"update.downloading":   "Downloading update…",
		"update.ready":         "Restart to update",
		"update.failed":        "Update failed: %s",
		"update.check":         "Check for updates",
		"update.up_to_date":    "Up to date ✓",

		// Smart Mode
		"settings.smart_mode":         "Smart Mode (AI Post-Processing)",
		"settings.smart_preset":       "Preset",
		"settings.smart_preset_off":   "Off",
		"settings.smart_preset_cleanup": "Clean Up",
		"settings.smart_preset_email": "Email Format",
		"settings.smart_preset_bullets": "Bullet List",
		"settings.smart_preset_formal": "Formal",
		"settings.smart_preset_translate": "Translate",
		"settings.smart_preset_custom": "Custom",
		"settings.smart_prompt":       "Custom Instruction",
		"settings.smart_prompt_hint":  "e.g. 'Always respond in formal German Markdown'",
		"settings.smart_target":       "Target Language",
		"settings.smart_cost_note":    "Uses GPT-4o-mini (~$0.002 per dictation)",

		// Advanced
		"settings.api_endpoint":       "API Endpoint",
		"settings.api_endpoint_hint":  "Custom Whisper-compatible endpoint (leave empty for OpenAI)",
		"settings.whisper_prompt":     "Whisper Prompt",
		"settings.whisper_prompt_hint": "Domain-specific terms for better accuracy (e.g. 'Kubernetes, kubectl')",
		"settings.max_duration":       "Max Recording Duration",
		"settings.max_duration_fmt":   "%d seconds",
		"settings.unlimited":          "∞ Unlimited",

		// Overlay
		"overlay.processing":   "Processing…",
		"overlay.cancelled":    "Cancelled",

		// Tray
		"tray.start_record":  "Start Recording",
		"tray.stop_record":   "Stop Recording",
		"tray.smart_mode":     "Smart Mode",
		"tray.history":        "Recent Transcriptions",
		"tray.history_empty":  "No transcriptions yet",
		"tray.status_ready":   "Whispaste – Ready",
		"tray.status_recording": "Whispaste – Recording…",
		"tray.status_paused":  "Whispaste – Paused",
		"tray.status_working": "Whispaste – Processing…",

		// Balloon notifications
		"balloon.copied":   "Copied to clipboard",
		"balloon.minimize": "Whispaste is still running in the background. Use your hotkey to start dictating.",

		// Stats
		"stats.title":           "Usage This Month",
		"stats.dictations":      "Dictations",
		"stats.words":           "Words",
		"stats.time_saved":      "Time Saved",
		"stats.minutes":         "%d min",
		"stats.cost":            "Est. Cost",
	},
	"de": {
		// App
		"app.name":        "Whispaste",
		"app.description": "Sprache zu Text, überall eingefügt",
		"app.version":     AppVersion,

		// Tray menu
		"tray.tooltip":   "Whispaste – Sprache zu Text",
		"tray.settings":  "Einstellungen",
		"tray.about":     "Über",
		"tray.support":   "Whispaste unterstützen",
		"tray.quit":      "Beenden",

		// States
		"state.idle":          "Bereit",
		"state.recording":     "Aufnahme…",
		"state.transcribing":  "Transkribiere…",
		"state.success":       "Fertig!",
		"state.error":         "Fehler",

		// Overlay
		"overlay.recording":    "Aufnahme",
		"overlay.paused":       "Pausiert",
		"overlay.transcribing": "Transkribiere…",
		"overlay.done":         "Eingefügt!",
		"overlay.copied":       "In Zwischenablage kopiert ✓",
		"overlay.error":        "Fehler: %s",

		// Settings
		"settings.title":           "Einstellungen",
		"settings.api_key":         "OpenAI API-Schlüssel",
		"settings.api_key_hint":    "OpenAI API-Schlüssel eingeben (beginnt mit sk-)",
		"settings.hotkey":          "Tastenkombination",
		"settings.mode":            "Modus",
		"settings.mode_ptt":        "Push-to-Talk (Taste gedrückt halten)",
		"settings.mode_toggle":     "Umschalten (Drücken zum Starten/Stoppen)",
		"settings.language":        "Transkriptions-Sprache",
		"settings.language_auto":   "Automatisch erkennen",
		"settings.ui_language":     "Oberflächensprache",
		"settings.overlay":         "Overlay-Position",
		"settings.overlay_top":     "Oben Mitte",
		"settings.overlay_cursor":  "In Cursornähe",
		"settings.auto_paste":      "Transkription automatisch einfügen",
		"settings.play_sounds":     "Akustische Rückmeldung",
		"settings.check_updates":   "Automatisch nach Updates suchen",
		"settings.save":            "Speichern",
		"settings.cancel":          "Abbrechen",
		"settings.test":            "Testen",
		"settings.test_recording":  "Aufnahme für 3 Sekunden…",
		"settings.test_success":    "Transkription: %s",
		"settings.test_error":      "Fehler: %s",
		"settings.saved":           "Einstellungen gespeichert!",
		"settings.about":           "Über",
		"settings.general":         "Allgemein",
		"settings.audio":           "Audio",
		"settings.appearance":      "Erscheinungsbild",
		"settings.show_key":        "Anzeigen",
		"settings.hide_key":        "Verbergen",
		"settings.theme":           "Design",
		"settings.theme_light":     "Hell",
		"settings.theme_dark":      "Dunkel",
		"settings.theme_system":    "System",

		// First run
		"firstrun.title":    "Willkommen bei Whispaste",
		"firstrun.message":  "Um zu starten, benötigen Sie einen OpenAI API-Schlüssel.",
		"firstrun.get_key":  "API-Schlüssel erhalten",
		"firstrun.enter":    "API-Schlüssel eingeben:",
		"firstrun.continue": "Weiter",

		// Errors
		"error.no_api_key":     "Kein API-Schlüssel konfiguriert. Rechtsklick auf das Tray-Symbol → Einstellungen.",
		"error.recording":      "Aufnahme fehlgeschlagen: %s",
		"error.transcription":  "Transkription fehlgeschlagen: %s",
		"error.hotkey":         "Tastenkombination %s konnte nicht registriert werden. Sie wird möglicherweise von einer anderen Anwendung verwendet.",
		"error.microphone":     "Zugriff auf Mikrofon nicht möglich: %s",
		"error.clipboard":      "Zugriff auf Zwischenablage nicht möglich: %s",

		// Updates
		"update.available":     "Update verfügbar: v%s",
		"update.downloading":   "Update wird heruntergeladen…",
		"update.ready":         "Neustart für Update",
		"update.failed":        "Update fehlgeschlagen: %s",
		"update.check":         "Nach Updates suchen",
		"update.up_to_date":    "Aktuell ✓",

		// Smart Mode
		"settings.smart_mode":         "Smart-Modus (KI-Nachbearbeitung)",
		"settings.smart_preset":       "Vorlage",
		"settings.smart_preset_off":   "Aus",
		"settings.smart_preset_cleanup": "Aufräumen",
		"settings.smart_preset_email": "E-Mail-Format",
		"settings.smart_preset_bullets": "Aufzählung",
		"settings.smart_preset_formal": "Formell",
		"settings.smart_preset_translate": "Übersetzen",
		"settings.smart_preset_custom": "Benutzerdefiniert",
		"settings.smart_prompt":       "Eigene Anweisung",
		"settings.smart_prompt_hint":  "z. B. 'Immer in formellem Deutsch als Markdown antworten'",
		"settings.smart_target":       "Zielsprache",
		"settings.smart_cost_note":    "Nutzt GPT-4o-mini (~0,002 $ pro Diktat)",

		// Advanced
		"settings.api_endpoint":       "API-Endpunkt",
		"settings.api_endpoint_hint":  "Eigener Whisper-kompatibler Endpunkt (leer = OpenAI)",
		"settings.whisper_prompt":     "Whisper-Prompt",
		"settings.whisper_prompt_hint": "Fachbegriffe für bessere Erkennung (z. B. 'Kubernetes, kubectl')",
		"settings.max_duration":       "Max. Aufnahmedauer",
		"settings.max_duration_fmt":   "%d Sekunden",
		"settings.unlimited":          "∞ Unbegrenzt",

		// Overlay
		"overlay.processing":   "Verarbeitung…",
		"overlay.cancelled":    "Abgebrochen",

		// Tray
		"tray.start_record":  "Aufnahme starten",
		"tray.stop_record":   "Aufnahme stoppen",
		"tray.smart_mode":     "Smart-Modus",
		"tray.history":        "Letzte Transkriptionen",
		"tray.history_empty":  "Noch keine Transkriptionen",
		"tray.status_ready":   "Whispaste – Bereit",
		"tray.status_recording": "Whispaste – Aufnahme…",
		"tray.status_paused":  "Whispaste – Pausiert",
		"tray.status_working": "Whispaste – Verarbeitung…",

		// Balloon notifications
		"balloon.copied":   "In Zwischenablage kopiert",
		"balloon.minimize": "Whispaste läuft weiterhin im Hintergrund. Nutzen Sie die Tastenkombination zum Diktieren.",

		// Stats
		"stats.title":           "Nutzung diesen Monat",
		"stats.dictations":      "Diktate",
		"stats.words":           "Wörter",
		"stats.time_saved":      "Eingesparte Zeit",
		"stats.minutes":         "%d Min.",
		"stats.cost":            "Gesch. Kosten",
	},
}
