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
		"app.name":        "WhisPaste",
		"app.description": "Voice to text, pasted anywhere",
		"app.version":     "v" + AppVersion,

		// Tray menu
		"tray.tooltip":   "WhisPaste – Voice to Text",
		"tray.settings":  "Settings",
		"tray.about":     "About",
		"tray.support":   "Support WhisPaste",
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
		"firstrun.title":    "Welcome to WhisPaste",
		"firstrun.message":  "To get started, you need an OpenAI API key.",
		"firstrun.get_key":  "Get API Key",
		"firstrun.enter":    "Enter your API key:",
		"firstrun.continue": "Continue",

		// Errors
		"error.no_api_key":     "No API key configured. Right-click the tray icon → Settings.",
		"error.no_local_model": "No local model downloaded. Open Settings → Local Models and download a model first.",
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
		"settings.smart_preset_concise": "Concise",
		"settings.smart_preset_email": "Email Format",
		"settings.smart_preset_bullets": "Bullet List",
		"settings.smart_preset_formal": "Formal",
		"settings.smart_preset_aiprompt": "AI Prompt",
		"settings.smart_preset_summary": "Summary",
		"settings.smart_preset_notes": "Notes",
		"settings.smart_preset_meeting": "Meeting Minutes",
		"settings.smart_preset_social": "Social Media",
		"settings.smart_preset_technical": "Technical Docs",
		"settings.smart_preset_casual": "Casual",
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
		"tray.notebook":       "Dashboard",
		"tray.status_ready":   "WhisPaste – Ready",
		"tray.status_recording": "WhisPaste – Recording…",
		"tray.status_paused":  "WhisPaste – Paused",
		"tray.status_working": "WhisPaste – Processing…",

		// Balloon notifications
		"balloon.copied":   "Copied to clipboard",
		"balloon.minimize":       "WhisPaste is still running in the background. Use your hotkey to start dictating.",
		"balloon.sponsor_title":  "Enjoying WhisPaste?",
		"balloon.sponsor":        "You've completed 50 dictations! If WhisPaste saves you time, consider supporting its development. ❤️",
		"balloon.transcription_complete": "Transcription complete.",

		// Stats
		"stats.title":           "Usage This Month",
		"stats.dictations":      "Dictations",
		"stats.words":           "Words",
		"stats.time_saved":      "Time Saved",
		"stats.minutes":         "%d min",
		"stats.cost":            "Est. Cost",

		// Notebook
		"notebook.title":        "Dashboard",
		"notebook.search":       "Search…",
		"notebook.all":          "All",
		"notebook.pinned":       "Pinned",
		"notebook.today":        "Today",
		"notebook.this_week":    "This Week",
		"notebook.older":        "Older",
		"notebook.empty":        "No entries yet. Press your hotkey to start dictating.",
		"notebook.no_results":   "No matching entries found.",
		"notebook.copy":         "Copy to Clipboard",
		"notebook.delete":       "Delete",
		"notebook.pin":          "Pin",
		"notebook.unpin":        "Unpin",
		"notebook.copied":       "Copied!",
		"notebook.confirm_delete": "Delete this entry?",
		"notebook.export":       "Export",
		"notebook.export_txt":   "Export as TXT",
		"notebook.export_md":    "Export as Markdown",
		"notebook.exported":     "Exported!",
		"notebook.export_selected": "Export selected",
		"notebook.uncategorized": "Uncategorized",
		"notebook.sort_newest":   "Newest first",
		"notebook.sort_oldest":   "Oldest first",
		"notebook.sort_alpha":    "A–Z",
		"notebook.sort_duration": "Duration",
		"notebook.sort":          "Sort",
		"notebook.add_tag":       "Add tag…",
		"notebook.tag_updated":   "Tag updated",
	},
	"de": {
		// App
		"app.name":        "WhisPaste",
		"app.description": "Sprache zu Text, überall eingefügt",
		"app.version":     "v" + AppVersion,

		// Tray menu
		"tray.tooltip":   "WhisPaste – Sprache zu Text",
		"tray.settings":  "Einstellungen",
		"tray.about":     "Über",
		"tray.support":   "WhisPaste unterstützen",
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
		"firstrun.title":    "Willkommen bei WhisPaste",
		"firstrun.message":  "Um zu starten, benötigen Sie einen OpenAI API-Schlüssel.",
		"firstrun.get_key":  "API-Schlüssel erhalten",
		"firstrun.enter":    "API-Schlüssel eingeben:",
		"firstrun.continue": "Weiter",

		// Errors
		"error.no_api_key":     "Kein API-Schlüssel konfiguriert. Rechtsklick auf das Tray-Symbol → Einstellungen.",
		"error.no_local_model": "Kein lokales Modell heruntergeladen. Öffne Einstellungen → Lokale Modelle und lade zuerst ein Modell herunter.",
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
		"settings.smart_preset_concise": "Kompakt",
		"settings.smart_preset_email": "E-Mail-Format",
		"settings.smart_preset_bullets": "Aufzählung",
		"settings.smart_preset_formal": "Formell",
		"settings.smart_preset_aiprompt": "KI-Prompt",
		"settings.smart_preset_summary": "Zusammenfassung",
		"settings.smart_preset_notes": "Notizen",
		"settings.smart_preset_meeting": "Protokoll",
		"settings.smart_preset_social": "Social Media",
		"settings.smart_preset_technical": "Technische Doku",
		"settings.smart_preset_casual": "Locker",
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
		"tray.notebook":       "Dashboard",
		"tray.status_ready":   "WhisPaste – Bereit",
		"tray.status_recording": "WhisPaste – Aufnahme…",
		"tray.status_paused":  "WhisPaste – Pausiert",
		"tray.status_working": "WhisPaste – Verarbeitung…",

		// Balloon notifications
		"balloon.copied":   "In Zwischenablage kopiert",
		"balloon.minimize":       "WhisPaste läuft weiterhin im Hintergrund. Nutzen Sie die Tastenkombination zum Diktieren.",
		"balloon.sponsor_title":  "Gefällt dir WhisPaste?",
		"balloon.sponsor":        "Du hast 50 Diktate abgeschlossen! Wenn WhisPaste dir Zeit spart, unterstütze gerne die Weiterentwicklung. ❤️",
		"balloon.transcription_complete": "Transkription abgeschlossen.",

		// Stats
		"stats.title":           "Nutzung diesen Monat",
		"stats.dictations":      "Diktate",
		"stats.words":           "Wörter",
		"stats.time_saved":      "Eingesparte Zeit",
		"stats.minutes":         "%d Min.",
		"stats.cost":            "Gesch. Kosten",

		// Notebook
		"notebook.title":        "Dashboard",
		"notebook.search":       "Suchen…",
		"notebook.all":          "Alle",
		"notebook.pinned":       "Angepinnt",
		"notebook.today":        "Heute",
		"notebook.this_week":    "Diese Woche",
		"notebook.older":        "Älter",
		"notebook.empty":        "Noch keine Einträge. Drücken Sie die Hotkey-Taste, um mit dem Diktieren zu beginnen.",
		"notebook.no_results":   "Keine passenden Einträge gefunden.",
		"notebook.copy":         "In Zwischenablage kopieren",
		"notebook.delete":       "Löschen",
		"notebook.pin":          "Anpinnen",
		"notebook.unpin":        "Lösen",
		"notebook.copied":       "Kopiert!",
		"notebook.confirm_delete": "Diesen Eintrag löschen?",
		"notebook.export":       "Exportieren",
		"notebook.export_txt":   "Als TXT exportieren",
		"notebook.export_md":    "Als Markdown exportieren",
		"notebook.exported":     "Exportiert!",
		"notebook.export_selected": "Auswahl exportieren",
		"notebook.uncategorized": "Unkategorisiert",
		"notebook.sort_newest":   "Neueste zuerst",
		"notebook.sort_oldest":   "Älteste zuerst",
		"notebook.sort_alpha":    "A–Z",
		"notebook.sort_duration": "Dauer",
		"notebook.sort":          "Sortierung",
		"notebook.add_tag":       "Tag hinzufügen…",
		"notebook.tag_updated":   "Tag aktualisiert",
	},
}
