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
		"tray.quit":      "Quit",

		// States
		"state.idle":          "Ready",
		"state.recording":     "Recording…",
		"state.transcribing":  "Transcribing…",
		"state.success":       "Done!",
		"state.error":         "Error",

		// Overlay
		"overlay.recording":    "Recording",
		"overlay.transcribing": "Transcribing…",
		"overlay.done":         "Pasted!",
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
		"tray.quit":      "Beenden",

		// States
		"state.idle":          "Bereit",
		"state.recording":     "Aufnahme…",
		"state.transcribing":  "Transkribiere…",
		"state.success":       "Fertig!",
		"state.error":         "Fehler",

		// Overlay
		"overlay.recording":    "Aufnahme",
		"overlay.transcribing": "Transkribiere…",
		"overlay.done":         "Eingefügt!",
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
	},
}
