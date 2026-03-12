package i18n

import "sync"

var (
	langMu      sync.RWMutex
	currentLang = "en"
)

// Init injects the app version into translation strings.
// Must be called before T() is used.
func Init(appVersion string) {
	translations["en"]["app.version"] = "v" + appVersion
	translations["de"]["app.version"] = "v" + appVersion
}

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
		"app.version":     "",

		// Tray menu
		"tray.tooltip":  "WhisPaste – Voice to Text",
		"tray.settings": "Settings",
		"tray.about":    "About",
		"tray.support":  "Support WhisPaste",
		"tray.quit":     "Quit",

		// Floating button
		"floating.hide":    "Hide Button",
		"floating.tooltip": "Click to record",

		// States
		"state.idle":         "Ready",
		"state.recording":    "Recording…",
		"state.transcribing": "Transcribing…",
		"state.success":      "Done!",
		"state.error":        "Error",

		// Overlay
		"overlay.recording":    "Recording",
		"overlay.paused":       "Paused",
		"overlay.transcribing": "Transcribing…",
		"overlay.done":         "Pasted!",
		"overlay.copied":       "Copied to clipboard ✓",
		"overlay.error":        "Error: %s",

		// Settings
		"settings.title":          "Settings",
		"settings.api_key":        "OpenAI API Key",
		"settings.api_key_hint":   "Enter your OpenAI API key (starts with sk-)",
		"settings.hotkey":         "Hotkey",
		"settings.mode":           "Mode",
		"settings.mode_ptt":       "Push to Talk (hold key)",
		"settings.mode_toggle":    "Toggle (press to start/stop)",
		"settings.language":       "Transcription Language",
		"settings.language_auto":  "Auto-detect",
		"settings.ui_language":    "Interface Language",
		"settings.overlay":        "Overlay Position",
		"settings.overlay_top":    "Top Center",
		"settings.overlay_cursor": "Near Cursor",
		"settings.auto_paste":     "Auto-paste transcription",
		"settings.play_sounds":    "Play sound feedback",
		"settings.check_updates":  "Check for updates automatically",
		"settings.save":           "Save",
		"settings.cancel":         "Cancel",
		"settings.test":           "Test",
		"settings.test_recording": "Recording for 3 seconds…",
		"settings.test_success":   "Transcription: %s",
		"settings.test_error":     "Error: %s",
		"settings.saved":          "Settings saved!",
		"settings.about":          "About",
		"settings.general":        "General",
		"settings.audio":          "Audio",
		"settings.appearance":     "Appearance",
		"settings.show_key":       "Show",
		"settings.hide_key":       "Hide",
		"settings.theme":          "Theme",
		"settings.theme_light":    "Light",
		"settings.theme_dark":     "Dark",
		"settings.theme_system":   "System",

		// First run
		"firstrun.title":    "Welcome to WhisPaste",
		"firstrun.message":  "To get started, you need an OpenAI API key — a personal access code from openai.com. Or choose local models for free, offline transcription.",
		"firstrun.get_key":  "Get API Key",
		"firstrun.enter":    "Enter your API key:",
		"firstrun.continue": "Continue",

		// Errors
		"error.no_api_key":                        "No API key configured. Right-click the tray icon → Settings.",
		"error.no_local_model":                    "No local model downloaded. Open Settings → Local Models and download a model first.",
		"error.recording":                         "Recording failed: %s",
		"error.transcription":                     "Transcription failed: %s",
		"error.hotkey":                            "Could not register hotkey %s. It may be used by another application.",
		"error.microphone":                        "Could not access microphone: %s",
		"error.clipboard":                         "Could not access clipboard: %s",
		"error.postprocess_request":               "Smart Mode request failed",
		"error.postprocess_api":                   "Smart Mode API error %d",
		"error.postprocess_empty":                 "Empty response from Smart Mode",
		"error.postprocess_parse":                 "Failed to parse response",
		"preflight.summary.pass":                  "This device is ready for local transcription.",
		"preflight.summary.pass_download":         "This device is ready to download and run local transcription.",
		"preflight.summary.warn":                  "This device should run local transcription, but performance headroom is limited.",
		"preflight.summary.fail":                  "This device cannot run local transcription reliably yet.",
		"preflight.reason.os":                     "Local transcription currently requires Windows.",
		"preflight.reason.arch":                   "Local transcription requires a 64-bit x86 CPU.",
		"preflight.reason.avx":                    "Your CPU is missing AVX support required by the bundled whisper-server build.",
		"preflight.reason.avx2":                   "AVX2 is missing, so local transcription may work but with less performance headroom.",
		"preflight.reason.cores":                  "This device has limited CPU parallelism for local transcription.",
		"preflight.reason.memory":                 "There is not enough RAM for reliable local transcription.",
		"preflight.reason.disk":                   "There is not enough free disk space for the selected local setup.",
		"preflight.reason.runtime":                "The installed whisper-server runtime could not start on this device.",
		"preflight.reason.unknown":                "Local transcription is blocked until the compatibility check passes.",
		"preflight.check.os":                      "Operating system",
		"preflight.check.arch":                    "CPU architecture",
		"preflight.check.avx":                     "AVX instruction support",
		"preflight.check.avx2":                    "AVX2 acceleration",
		"preflight.check.cores":                   "Logical CPU cores",
		"preflight.check.memory":                  "Installed memory",
		"preflight.check.disk":                    "Free disk space",
		"preflight.check.runtime":                 "whisper-server runtime",
		"preflight.detail.os.fail":                "WhisPaste local transcription is currently available on Windows only.",
		"preflight.detail.arch.fail":              "The downloaded whisper-server build targets 64-bit x86 systems only.",
		"preflight.detail.avx.fail":               "The current whisper-server build requires AVX CPU instructions and cannot run without them.",
		"preflight.detail.avx2.warn":              "AVX2 is missing. The runtime may still work, but slower office notebooks will have less margin.",
		"preflight.detail.cores.warn":             "Fewer than four logical CPU cores can make local transcription feel sluggish during longer dictations.",
		"preflight.detail.memory.fail":            "At least 4 GB RAM is required for reliable local STT startup.",
		"preflight.detail.memory.warn":            "8 GB RAM or more is recommended for smoother local transcription on everyday notebooks.",
		"preflight.detail.disk.fail":              "Free up disk space before using local models (%s).",
		"preflight.detail.disk.warn":              "Disk space is getting tight for local model downloads and updates.",
		"preflight.detail.runtime.fail":           "The installed whisper-server probe failed: %s",
		"preflight.detail.runtime.fail_no_output": "The installed whisper-server probe failed before any diagnostic output was available.",
		"audio.device_unavailable":                "The selected microphone is no longer available. Choose another recording device in Settings.",

		// Updates
		"update.available":   "Update available: v%s",
		"update.downloading": "Downloading update…",
		"update.ready":       "Restart to update",
		"update.failed":      "Update failed: %s",
		"update.check":       "Check for updates",
		"update.up_to_date":  "Up to date ✓",

		// Smart Mode
		"settings.smart_mode":             "Smart Mode (AI Post-Processing)",
		"settings.smart_preset":           "Preset",
		"settings.smart_preset_off":       "Off",
		"settings.smart_preset_cleanup":   "Clean Up",
		"settings.smart_preset_concise":   "Condense",
		"settings.smart_preset_email":     "Email Format",
		"settings.smart_preset_bullets":   "Bullet List",
		"settings.smart_preset_formal":    "Formal",
		"settings.smart_preset_aiprompt":  "AI Prompt",
		"settings.smart_preset_summary":   "Summary",
		"settings.smart_preset_notes":     "Notes",
		"settings.smart_preset_meeting":   "Meeting Minutes",
		"settings.smart_preset_social":    "Social Media",
		"settings.smart_preset_technical": "Technical Docs",
		"settings.smart_preset_casual":    "Casual",
		"settings.smart_preset_translate": "Translate",
		"settings.smart_preset_custom":    "Custom",
		"settings.smart_prompt":           "Custom Instruction",
		"settings.smart_prompt_hint":      "e.g. 'Always respond in formal German Markdown'",
		"settings.smart_target":           "Target Language",
		"settings.smart_cost_note":        "Uses GPT-4o-mini (~$0.002 per dictation)",

		// Advanced
		"settings.api_endpoint":        "API Endpoint",
		"settings.api_endpoint_hint":   "Custom Whisper-compatible endpoint (leave empty for OpenAI)",
		"settings.whisper_prompt":      "Whisper Prompt",
		"settings.whisper_prompt_hint": "Domain-specific terms for better accuracy (e.g. 'Kubernetes, kubectl')",
		"settings.max_duration":        "Max Recording Duration",
		"settings.max_duration_fmt":    "%d seconds",
		"settings.unlimited":           "∞ Unlimited",

		// Overlay
		"overlay.processing":       "Processing…",
		"overlay.smart_processing": "Smart processing…",
		"overlay.cancelled":        "Cancelled",

		// Tray
		"tray.start_record":     "Start Recording",
		"tray.stop_record":      "Stop Recording",
		"tray.smart_mode":       "Smart Mode",
		"tray.history":          "Recent Transcriptions",
		"tray.history_empty":    "No transcriptions yet",
		"tray.notebook":         "Dashboard",
		"tray.status_ready":     "WhisPaste – Ready",
		"tray.status_recording": "WhisPaste – Recording…",
		"tray.status_paused":    "WhisPaste – Paused",
		"tray.status_working":   "WhisPaste – Processing…",

		// Balloon notifications
		"balloon.copied":                 "Copied to clipboard",
		"balloon.minimize":               "WhisPaste is still running in the background. Use your hotkey to start dictating.",
		"balloon.sponsor_title":          "Enjoying WhisPaste?",
		"balloon.sponsor":                "You've completed 50 dictations! If WhisPaste saves you time, consider supporting its development. ❤️",
		"balloon.transcription_complete": "Transcription complete.",
		"balloon.test":                   "Test notification — if you see this, notifications work!",

		// Pending transcription
		"transcribing":            "Transcribing…",
		"transcription_cancelled": "Cancelled",
		"transcription_failed":    "Failed",

		// Stats
		"stats.title":      "Usage This Month",
		"stats.dictations": "Dictations",
		"stats.words":      "Words",
		"stats.time_saved": "Time Saved",
		"stats.minutes":    "%d min",
		"stats.cost":       "Est. Cost",

		// Notebook
		"notebook.title":           "Dashboard",
		"notebook.search":          "Search…",
		"notebook.all":             "All",
		"notebook.pinned":          "Pinned",
		"notebook.today":           "Today",
		"notebook.this_week":       "This Week",
		"notebook.older":           "Older",
		"notebook.empty":           "No entries yet. Press your hotkey to start dictating.",
		"notebook.no_results":      "No matching entries found.",
		"notebook.copy":            "Copy to Clipboard",
		"notebook.delete":          "Delete",
		"notebook.pin":             "Pin",
		"notebook.unpin":           "Unpin",
		"notebook.copied":          "Copied!",
		"notebook.confirm_delete":  "Delete this entry?",
		"notebook.export":          "Export",
		"notebook.export_txt":      "Export as TXT",
		"notebook.export_md":       "Export as Markdown",
		"notebook.exported":        "Exported!",
		"notebook.export_selected": "Export selected",
		"notebook.uncategorized":   "Uncategorized",
		"notebook.sort_newest":     "Newest first",
		"notebook.sort_oldest":     "Oldest first",
		"notebook.sort_alpha":      "A–Z",
		"notebook.sort_duration":   "Duration",
		"notebook.sort":            "Sort",
		"notebook.add_tag":         "Add tag…",
		"notebook.tag_updated":     "Tag updated",
		"notebook.project_created": "Project created",
		"notebook.project_deleted": "Project deleted",
	},
	"de": {
		// App
		"app.name":        "WhisPaste",
		"app.description": "Sprache zu Text, überall eingefügt",
		"app.version":     "",

		// Tray menu
		"tray.tooltip":  "WhisPaste – Sprache zu Text",
		"tray.settings": "Einstellungen",
		"tray.about":    "Über",
		"tray.support":  "WhisPaste unterstützen",
		"tray.quit":     "Beenden",

		// Floating button
		"floating.hide":    "Button ausblenden",
		"floating.tooltip": "Klicken zum Aufnehmen",

		// States
		"state.idle":         "Bereit",
		"state.recording":    "Aufnahme…",
		"state.transcribing": "Transkribiere…",
		"state.success":      "Fertig!",
		"state.error":        "Fehler",

		// Overlay
		"overlay.recording":    "Aufnahme",
		"overlay.paused":       "Pausiert",
		"overlay.transcribing": "Transkribiere…",
		"overlay.done":         "Eingefügt!",
		"overlay.copied":       "In Zwischenablage kopiert ✓",
		"overlay.error":        "Fehler: %s",

		// Settings
		"settings.title":          "Einstellungen",
		"settings.api_key":        "OpenAI API-Schlüssel",
		"settings.api_key_hint":   "OpenAI API-Schlüssel eingeben (beginnt mit sk-)",
		"settings.hotkey":         "Tastenkombination",
		"settings.mode":           "Modus",
		"settings.mode_ptt":       "Push-to-Talk (Taste gedrückt halten)",
		"settings.mode_toggle":    "Umschalten (Drücken zum Starten/Stoppen)",
		"settings.language":       "Transkriptions-Sprache",
		"settings.language_auto":  "Automatisch erkennen",
		"settings.ui_language":    "Oberflächensprache",
		"settings.overlay":        "Overlay-Position",
		"settings.overlay_top":    "Oben Mitte",
		"settings.overlay_cursor": "In Cursornähe",
		"settings.auto_paste":     "Transkription automatisch einfügen",
		"settings.play_sounds":    "Tonsignale",
		"settings.check_updates":  "Automatisch nach Updates suchen",
		"settings.save":           "Speichern",
		"settings.cancel":         "Abbrechen",
		"settings.test":           "Testen",
		"settings.test_recording": "Aufnahme für 3 Sekunden…",
		"settings.test_success":   "Transkription: %s",
		"settings.test_error":     "Fehler: %s",
		"settings.saved":          "Einstellungen gespeichert!",
		"settings.about":          "Über",
		"settings.general":        "Allgemein",
		"settings.audio":          "Audio",
		"settings.appearance":     "Erscheinungsbild",
		"settings.show_key":       "Anzeigen",
		"settings.hide_key":       "Verbergen",
		"settings.theme":          "Design",
		"settings.theme_light":    "Hell",
		"settings.theme_dark":     "Dunkel",
		"settings.theme_system":   "System",

		// First run
		"firstrun.title":    "Willkommen bei WhisPaste",
		"firstrun.message":  "Zum Starten benötigst du einen OpenAI API-Key — einen persönlichen Zugangscode von openai.com. Oder wähle lokale Modelle für kostenlose Offline-Transkription.",
		"firstrun.get_key":  "API-Schlüssel erhalten",
		"firstrun.enter":    "API-Schlüssel eingeben:",
		"firstrun.continue": "Weiter",

		// Errors
		"error.no_api_key":                        "Kein API-Schlüssel konfiguriert. Rechtsklick auf das Tray-Symbol → Einstellungen.",
		"error.no_local_model":                    "Kein lokales Modell heruntergeladen. Öffne Einstellungen → Lokale Modelle und lade zuerst ein Modell herunter.",
		"error.recording":                         "Aufnahme fehlgeschlagen: %s",
		"error.transcription":                     "Transkription fehlgeschlagen: %s",
		"error.hotkey":                            "Tastenkombination %s konnte nicht registriert werden — vermutlich von einer anderen App belegt.",
		"error.microphone":                        "Zugriff auf Mikrofon nicht möglich: %s",
		"error.clipboard":                         "Zugriff auf Zwischenablage nicht möglich: %s",
		"error.postprocess_request":               "Smart-Mode-Anfrage fehlgeschlagen",
		"error.postprocess_api":                   "Smart-Mode-API-Fehler %d",
		"error.postprocess_empty":                 "Leere Antwort vom Smart Mode",
		"error.postprocess_parse":                 "Antwort konnte nicht verarbeitet werden",
		"preflight.summary.pass":                  "Dieses Gerät ist bereit für lokale Transkription.",
		"preflight.summary.pass_download":         "Dieses Gerät ist bereit, lokale Transkription herunterzuladen und auszuführen.",
		"preflight.summary.warn":                  "Lokale Transkription sollte laufen, aber die Leistungsreserve ist begrenzt.",
		"preflight.summary.fail":                  "Dieses Gerät kann lokale Transkription aktuell nicht zuverlässig ausführen.",
		"preflight.reason.os":                     "Lokale Transkription ist derzeit nur unter Windows verfügbar.",
		"preflight.reason.arch":                   "Lokale Transkription erfordert eine 64-Bit-x86-CPU.",
		"preflight.reason.avx":                    "Deiner CPU fehlt die für den mitgelieferten whisper-server benötigte AVX-Unterstützung.",
		"preflight.reason.avx2":                   "AVX2 fehlt. Lokale Transkription kann eventuell laufen, aber mit weniger Leistungsreserve.",
		"preflight.reason.cores":                  "Dieses Gerät hat nur begrenzte CPU-Parallelität für lokale Transkription.",
		"preflight.reason.memory":                 "Für zuverlässige lokale Transkription ist nicht genug RAM vorhanden.",
		"preflight.reason.disk":                   "Für das gewählte lokale Setup ist nicht genug freier Speicherplatz vorhanden.",
		"preflight.reason.runtime":                "Die installierte whisper-server-Laufzeit konnte auf diesem Gerät nicht starten.",
		"preflight.reason.unknown":                "Lokale Transkription bleibt blockiert, bis der Kompatibilitätscheck besteht.",
		"preflight.check.os":                      "Betriebssystem",
		"preflight.check.arch":                    "CPU-Architektur",
		"preflight.check.avx":                     "AVX-Unterstützung",
		"preflight.check.avx2":                    "AVX2-Beschleunigung",
		"preflight.check.cores":                   "Logische CPU-Kerne",
		"preflight.check.memory":                  "Installierter Arbeitsspeicher",
		"preflight.check.disk":                    "Freier Speicherplatz",
		"preflight.check.runtime":                 "whisper-server-Laufzeit",
		"preflight.detail.os.fail":                "WhisPaste-Lokaltranskription ist aktuell nur unter Windows verfügbar.",
		"preflight.detail.arch.fail":              "Der heruntergeladene whisper-server-Build unterstützt nur 64-Bit-x86-Systeme.",
		"preflight.detail.avx.fail":               "Der aktuelle whisper-server-Build benötigt AVX-Befehle und kann ohne sie nicht laufen.",
		"preflight.detail.avx2.warn":              "AVX2 fehlt. Die Laufzeit kann trotzdem funktionieren, aber langsame Office-Notebooks haben weniger Reserve.",
		"preflight.detail.cores.warn":             "Weniger als vier logische CPU-Kerne können lokale Transkription bei längeren Diktaten träge machen.",
		"preflight.detail.memory.fail":            "Für einen zuverlässigen lokalen STT-Start werden mindestens 4 GB RAM benötigt.",
		"preflight.detail.memory.warn":            "8 GB RAM oder mehr sind für flüssigere lokale Transkription auf Alltags-Notebooks empfohlen.",
		"preflight.detail.disk.fail":              "Bitte zuerst Speicherplatz freigeben, bevor lokale Modelle genutzt werden (%s).",
		"preflight.detail.disk.warn":              "Der freie Speicherplatz wird knapp für lokale Modelldownloads und Updates.",
		"preflight.detail.runtime.fail":           "Die installierte whisper-server-Probe ist fehlgeschlagen: %s",
		"preflight.detail.runtime.fail_no_output": "Die installierte whisper-server-Probe ist fehlgeschlagen, bevor Diagnosedaten verfügbar waren.",
		"audio.device_unavailable":                "Das gewählte Mikrofon ist nicht mehr verfügbar. Wähle in den Einstellungen ein anderes Aufnahmegerät.",

		// Updates
		"update.available":   "Update verfügbar: v%s",
		"update.downloading": "Update wird heruntergeladen…",
		"update.ready":       "Neustart für Update",
		"update.failed":      "Update fehlgeschlagen: %s",
		"update.check":       "Nach Updates suchen",
		"update.up_to_date":  "Aktuell ✓",

		// Smart Mode
		"settings.smart_mode":             "Smart-Modus (KI-Nachbearbeitung)",
		"settings.smart_preset":           "Vorlage",
		"settings.smart_preset_off":       "Aus",
		"settings.smart_preset_cleanup":   "Bereinigen",
		"settings.smart_preset_concise":   "Straffen",
		"settings.smart_preset_email":     "E-Mail-Format",
		"settings.smart_preset_bullets":   "Aufzählung",
		"settings.smart_preset_formal":    "Formell",
		"settings.smart_preset_aiprompt":  "KI-Prompt",
		"settings.smart_preset_summary":   "Zusammenfassung",
		"settings.smart_preset_notes":     "Notizen",
		"settings.smart_preset_meeting":   "Protokoll",
		"settings.smart_preset_social":    "Social Media",
		"settings.smart_preset_technical": "Technische Doku",
		"settings.smart_preset_casual":    "Locker",
		"settings.smart_preset_translate": "Übersetzen",
		"settings.smart_preset_custom":    "Benutzerdefiniert",
		"settings.smart_prompt":           "Eigene Anweisung",
		"settings.smart_prompt_hint":      "z. B. 'Immer in formellem Deutsch als Markdown antworten'",
		"settings.smart_target":           "Zielsprache",
		"settings.smart_cost_note":        "Nutzt GPT-4o-mini (~0,002 $ pro Diktat)",

		// Advanced
		"settings.api_endpoint":        "API-Endpunkt",
		"settings.api_endpoint_hint":   "Eigener Whisper-kompatibler Endpunkt (leer = OpenAI)",
		"settings.whisper_prompt":      "Whisper-Prompt",
		"settings.whisper_prompt_hint": "Fachbegriffe für bessere Erkennung (z. B. 'Kubernetes, kubectl')",
		"settings.max_duration":        "Max. Aufnahmedauer",
		"settings.max_duration_fmt":    "%d Sekunden",
		"settings.unlimited":           "∞ Unbegrenzt",

		// Overlay
		"overlay.processing":       "Verarbeitung…",
		"overlay.smart_processing": "Smart-Verarbeitung…",
		"overlay.cancelled":        "Abgebrochen",

		// Tray
		"tray.start_record":     "Aufnahme starten",
		"tray.stop_record":      "Aufnahme stoppen",
		"tray.smart_mode":       "Smart-Modus",
		"tray.history":          "Letzte Transkriptionen",
		"tray.history_empty":    "Noch keine Transkriptionen",
		"tray.notebook":         "Dashboard",
		"tray.status_ready":     "WhisPaste – Bereit",
		"tray.status_recording": "WhisPaste – Aufnahme…",
		"tray.status_paused":    "WhisPaste – Pausiert",
		"tray.status_working":   "WhisPaste – Verarbeitung…",

		// Balloon notifications
		"balloon.copied":                 "In Zwischenablage kopiert",
		"balloon.minimize":               "WhisPaste läuft weiterhin im Hintergrund. Nutze die Tastenkombination zum Diktieren.",
		"balloon.sponsor_title":          "Gefällt dir WhisPaste?",
		"balloon.sponsor":                "Du hast 50 Diktate abgeschlossen! Wenn WhisPaste dir Zeit spart, unterstütze gerne die Weiterentwicklung. ❤️",
		"balloon.transcription_complete": "Transkription abgeschlossen.",
		"balloon.test":                   "Test-Benachrichtigung — wenn du das siehst, funktionieren Benachrichtigungen!",

		// Pending transcription
		"transcribing":            "Wird transkribiert…",
		"transcription_cancelled": "Abgebrochen",
		"transcription_failed":    "Fehlgeschlagen",

		// Stats
		"stats.title":      "Nutzung diesen Monat",
		"stats.dictations": "Diktate",
		"stats.words":      "Wörter",
		"stats.time_saved": "Eingesparte Zeit",
		"stats.minutes":    "%d Min.",
		"stats.cost":       "Gesch. Kosten",

		// Notebook
		"notebook.title":           "Dashboard",
		"notebook.search":          "Suchen…",
		"notebook.all":             "Alle",
		"notebook.pinned":          "Angepinnt",
		"notebook.today":           "Heute",
		"notebook.this_week":       "Diese Woche",
		"notebook.older":           "Älter",
		"notebook.empty":           "Noch keine Einträge. Drück die Hotkey-Taste, um mit dem Diktieren zu beginnen.",
		"notebook.no_results":      "Keine passenden Einträge gefunden.",
		"notebook.copy":            "In Zwischenablage kopieren",
		"notebook.delete":          "Löschen",
		"notebook.pin":             "Anpinnen",
		"notebook.unpin":           "Lösen",
		"notebook.copied":          "Kopiert!",
		"notebook.confirm_delete":  "Diesen Eintrag löschen?",
		"notebook.export":          "Exportieren",
		"notebook.export_txt":      "Als TXT exportieren",
		"notebook.export_md":       "Als Markdown exportieren",
		"notebook.exported":        "Exportiert!",
		"notebook.export_selected": "Auswahl exportieren",
		"notebook.uncategorized":   "Unkategorisiert",
		"notebook.sort_newest":     "Neueste zuerst",
		"notebook.sort_oldest":     "Älteste zuerst",
		"notebook.sort_alpha":      "A–Z",
		"notebook.sort_duration":   "Dauer",
		"notebook.sort":            "Sortierung",
		"notebook.add_tag":         "Tag hinzufügen…",
		"notebook.tag_updated":     "Tag aktualisiert",
		"notebook.project_created": "Projekt erstellt",
		"notebook.project_deleted": "Projekt gelöscht",
	},
}
