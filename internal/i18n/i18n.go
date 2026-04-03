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
		"app.notebook":    "Notebook",
		"app.description": "Voice to text, pasted anywhere",
		"app.version":     "",

		// Tray menu
		"tray.tooltip":  "WhisPaste – Voice to Text",
		"tray.settings": "Settings",
		"tray.about":    "About",
		"tray.support":  "Support WhisPaste",
		"tray.quit":     "Quit",
		"tray.feedback":      "Give Feedback",
		"tray.feedback_desc": "Rate and review WhisPaste",

		// Feedback dialog
		"feedback.title":       "How do you like WhisPaste?",
		"feedback.subtitle":    "Your feedback helps us improve the app.",
		"feedback.placeholder": "Tell us what you think... (optional)",
		"feedback.privacy":     "Only your rating, feedback text, and app version are transmitted. No personal data is collected.",
		"feedback.cancel":      "Cancel",
		"feedback.submit":      "Submit Feedback",
		"feedback.thanks":      "Thank you for your feedback!",

		// About – feedback prompt
		"about.feedback_prompt": "Enjoying WhisPaste?",
		"about.rate_us":         "★ Rate WhisPaste",

		// Floating button
		"floating.hide":           "Hide Button",
		"floating.lock":           "Lock Position",
		"floating.auto_paste":     "Auto-Paste",
		"floating.tooltip":        "Click to record",
		"floating.status_ready":   "Ready",
		"floating.status_record":  "Recording…",
		"floating.status_working": "Processing…",
		"floating.last_text":      "Last: \"%s\"",
		"floating.name":           "Quick Record",
		"floating.tip_ready":       "WhisPaste — Ready",
		"floating.tip_recording":   "WhisPaste — Recording…",
		"floating.tip_paused":      "WhisPaste — Paused",
		"floating.tip_transcribing":"WhisPaste — Transcribing…",
		"floating.tip_processing":  "WhisPaste — Processing…",

		// Floating button shapes & colors
		"shapeCircle":   "Circle",
		"shapeSquircle": "Squircle",
		"shapeRounded":  "Rounded Square",
		"shapeHexagon":  "Hexagon",
		"shapeDiamond":  "Diamond",
		"shapeStar":     "Star",
		"colorCyan":     "Cyan",
		"colorBlue":     "Blue",
		"colorPurple":   "Purple",
		"colorRose":     "Rose",
		"colorOrange":   "Orange",
		"colorAmber":    "Amber",
		"colorEmerald":  "Emerald",
		"colorSlate":    "Slate",
		"colorCustom":   "Custom Color",

		// Dashboard greeting
		"greeting.morning":       "Good morning",
		"greeting.afternoon":     "Good afternoon",
		"greeting.evening":       "Good evening",
		"greeting.recording":     "recording",
		"greeting.recordings":    "recordings",
		"greeting.today_suffix":  "today",
		"greeting.weekend":       "Enjoy your weekend!",
		"greeting.earlybird":     "Early start today!",
		"greeting.ready":         "Ready when you are.",
		"greeting.productive":    "Wow, {count} recordings today! 🔥",

		// Milestone celebrations
		"milestone.10":           "🎉 10 dictations! You're getting started!",
		"milestone.50":           "🔥 50 dictations! You're on a roll!",
		"milestone.100":          "🏆 100 dictations! Power user status!",
		"milestone.250":          "⚡ 250 dictations! Impressive dedication!",
		"milestone.500":          "🌟 500 dictations! You're a WhisPaste pro!",
		"milestone.1000":         "💎 1000 dictations! Legendary!",
		"milestone.dictations":   "dictations",

		// Empty state
		"emptyState.title":       "Your voice, your words",
		"emptyState.desc":        "Press the hotkey or click the floating button to start your first dictation.",

		// States
		"chars": "chars",

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
		"error.no_api_key":                        "No API key set up yet. Head to Settings to add yours.",
		"error.no_local_model":                    "No local model downloaded. Open Settings → Local Models and download a model first.",
		"error.recording":                         "Recording didn't work: %s",
		"error.transcription":                     "Couldn't transcribe the audio: %s",
		"error.hotkey":                            "Could not register hotkey %s. It may be used by another application.",
		"error.microphone":                        "Microphone not available: %s",
		"error.clipboard":                         "Couldn't reach the clipboard: %s",
		"error.postprocess_request":               "Smart Mode couldn't process this one",
		"error.postprocess_api":                   "Smart Mode ran into an issue (error %d)",
		"error.postprocess_empty":                 "Smart Mode returned nothing — try again",
		"error.postprocess_parse":                 "Couldn't read Smart Mode's response",
		"preflight.summary.pass":                  "Your device is ready for local transcription.",
		"preflight.summary.pass_download":         "Your device is ready — just download the model to get started.",
		"preflight.summary.warn":                  "Local transcription will work, but may be slower on this device.",
		"preflight.summary.fail":                  "This device can't run local transcription. Try cloud transcription instead.",
		"preflight.reason.os":                     "Local transcription currently requires Windows.",
		"preflight.reason.arch":                   "This device's processor isn't compatible with local transcription.",
		"preflight.reason.avx":                    "Your processor is too old for local transcription. Try cloud transcription instead.",
		"preflight.reason.avx2":                   "Your processor is a bit older — local transcription will work, but may be slower.",
		"preflight.reason.cores":                  "This device may be slow for local transcription. Shorter recordings work best.",
		"preflight.reason.memory":                 "Not enough memory (RAM) for local transcription. Try cloud transcription instead.",
		"preflight.reason.disk":                   "Not enough storage space for the selected model.",
		"preflight.reason.runtime":                "The transcription engine couldn't start. A system component may be missing — see aka.ms/vs/17/release/vc_redist.x64.exe",
		"preflight.reason.unknown":                "Local transcription isn't available yet — a compatibility check needs to pass first.",
		"preflight.check.os":                      "Operating system",
		"preflight.check.arch":                    "Processor type",
		"preflight.check.avx":                     "Processor compatibility",
		"preflight.check.avx2":                    "Processor speed features",
		"preflight.check.cores":                   "Processing power",
		"preflight.check.memory":                  "Memory (RAM)",
		"preflight.check.disk":                    "Storage space",
		"preflight.check.runtime":                 "Transcription engine",
		"preflight.detail.os.fail":                "Local transcription is currently available on Windows only.",
		"preflight.detail.arch.fail":              "Local transcription needs a modern 64-bit processor. Your device uses a different type.",
		"preflight.detail.avx.fail":               "Your processor doesn't support a feature needed for local transcription (AVX). Cloud transcription works on all devices.",
		"preflight.detail.avx2.warn":              "Your processor is missing a speed feature (AVX2). Transcription will still work, just a bit slower.",
		"preflight.detail.cores.warn":             "Your device has limited processing power, so longer recordings may take more time to transcribe.",
		"preflight.detail.memory.fail":            "Local transcription needs at least 4 GB of memory (RAM). Your device has less.",
		"preflight.detail.memory.warn":            "For best performance, 8 GB of memory (RAM) or more is recommended.",
		"preflight.detail.disk.fail":              "Please free up storage space before downloading a model (%s).",
		"preflight.detail.disk.warn":              "Storage space is getting low for model downloads.",
		"preflight.detail.runtime.fail":           "The transcription engine couldn't start: %s — Try installing the Visual C++ Runtime from aka.ms/vs/17/release/vc_redist.x64.exe and restarting.",
		"preflight.detail.runtime.fail_no_output": "The transcription engine couldn't start properly. Try installing the Visual C++ Runtime from aka.ms/vs/17/release/vc_redist.x64.exe and restarting.",
		"audio.device_unavailable":                "The selected microphone is no longer available. Choose another recording device in Settings.",

		// Updates
		"update.available":          "Update available: v%s",
		"update.downloading":        "Downloading update…",
		"update.ready":              "Restart to update",
		"update.failed":             "Update failed: %s",
		"update.check":              "Check for updates",
		"update.check_failed":       "Check for updates (⚠ last check failed)",
		"update.up_to_date":         "Up to date ✓",
		"update.notify_downloading": "Downloading update v%s…",
		"update.notify_ready":       "Update installed — click to restart WhisPaste",
		"update.permission_failed":  "Update cannot be installed",
		"update.permission_hint":    "Please reinstall WhisPaste from whispaste.de to fix auto-updates.",

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
		"tray.auto_paste":       "Auto-Paste",
		"tray.history":          "Recent Transcriptions",
		"tray.history_empty":    "No recordings yet",
		"tray.notebook":         "Open Notebook",
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
		"balloon.smart_mode_raw":         "Smart Mode failed - raw transcription was used.",
		"balloon.paste_clipboard_only":   "Could not paste here - the text was copied to your clipboard.",
		"balloon.test":                   "Test notification — if you see this, notifications work!",

		// Pending transcription
		"transcribing":            "Transcribing…",
		"transcription_cancelled": "Cancelled",
		"transcription_failed":    "Failed",

		// Relative time
		"time_just_now":  "just now",
		"time_min_ago":   "%d min ago",
		"time_hours_ago": "%dh ago",
		"time_yesterday": "Yesterday",
		"time_day_mon":   "Mon",
		"time_day_tue":   "Tue",
		"time_day_wed":   "Wed",
		"time_day_thu":   "Thu",
		"time_day_fri":   "Fri",
		"time_day_sat":   "Sat",
		"time_day_sun":   "Sun",

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
		"notebook.copy_text":       "Copy Text",
		"notebook.copy_markdown":   "Copy as Markdown",
		"notebook.date":            "Date",
		"notebook.language":        "Language",
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

		// Notes & Attachments
		"notebook.notes":              "Notes",
		"notebook.attachments":        "Attachments",
		"notebook.add_note":           "Add Note",
		"notebook.add_note_placeholder": "Write a note…",
		"notebook.add_file":           "Add File",
		"notebook.open_file":          "Open File",

		// Feature Discovery
		"discovery.smartmode.title": "AI-powered refinement",
		"discovery.smartmode.desc":  "Smart Mode refines your dictations with AI — try enabling it!",
		"discovery.analytics.title": "Your dictation insights",
		"discovery.analytics.desc":  "See your dictation patterns and productivity trends.",
		"discovery.replacements.title": "Auto-correct your words",
		"discovery.replacements.desc":  "Auto-correct words and phrases in every dictation.",
		"discovery.gotIt":           "Got it",

		// Keyboard Shortcuts Help
		"shortcuts.title":          "Keyboard Shortcuts",
		"shortcuts.nav":            "Navigation",
		"shortcuts.recording":      "Recording",
		"shortcuts.smartmode":      "Smart Mode",
		"shortcuts.other":          "Other",
		"shortcuts.record_stop":    "Record / Stop",
		"shortcuts.toggle_smartmode": "Toggle Smart Mode",
		"shortcuts.search_history": "Search History",
		"shortcuts.close_dialog":   "Close / Clear",
		"shortcuts.this_help":      "This Help",
		"shortcuts.previous_page":  "Previous Page",
		"shortcuts.command_palette": "Command Palette",

		"show_more": "Show more",

		// Title
		"title.edit":       "Edit title",
		"title.generating": "Generating title…",

		// Config Warnings
		"warn.no_api_key":           "Cloud API mode is active but no API key is configured. Recording will fail.",
		"warn.model_not_downloaded": "Local STT model is selected but not downloaded. Please download it in settings.",

		// Settings: Progressive Disclosure
		"settings.advanced": "Advanced Settings",

		// Tray
		"tray.open":      "Open WhisPaste",
		"tray.open_desc": "Open the main window",

		// History Groups
		"group.none":       "No grouping",
		"group.by_date":    "By date",
		"group.by_project": "By project",
		"group.by_language":"By language",
		"group.today":      "Today",
		"group.yesterday":  "Yesterday",
		"group.this_week":  "This week",
		"group.this_month": "This month",
		"group.older":      "Older",
		"group.no_project": "No project",
		"group.unknown":    "Unknown",
		"group.entry":      "entry",
		"group.entries":    "entries",
		"group.of":         "of",
		"group.select_all": "Select all in group",

		// View modes
		"view.card": "Card view",
		"view.list": "List view",
		"view.tile": "Tile view",
	},
	"de": {
		// App
		"app.name":        "WhisPaste",
		"app.notebook":    "Notizbuch",
		"app.description": "Sprache zu Text, überall eingefügt",
		"app.version":     "",

		// Tray menu
		"tray.tooltip":  "WhisPaste – Sprache zu Text",
		"tray.settings": "Einstellungen",
		"tray.about":    "Über",
		"tray.support":  "WhisPaste unterstützen",
		"tray.quit":     "Beenden",
		"tray.feedback":      "Feedback geben",
		"tray.feedback_desc": "WhisPaste bewerten",

		// Feedback-Dialog
		"feedback.title":       "Wie gefällt dir WhisPaste?",
		"feedback.subtitle":    "Dein Feedback hilft uns, die App zu verbessern.",
		"feedback.placeholder": "Erzähl uns, was du denkst... (optional)",
		"feedback.privacy":     "Nur deine Bewertung, dein Feedbacktext und die App-Version werden übermittelt. Es werden keine persönlichen Daten erfasst.",
		"feedback.cancel":      "Abbrechen",
		"feedback.submit":      "Feedback senden",
		"feedback.thanks":      "Vielen Dank für dein Feedback!",

		// About – feedback prompt
		"about.feedback_prompt": "Gefällt dir WhisPaste?",
		"about.rate_us":         "★ WhisPaste bewerten",

		// Floating button
		"floating.hide":           "Button ausblenden",
		"floating.lock":           "Position sperren",
		"floating.auto_paste":     "Auto-Einfügen",
		"floating.tooltip":        "Klicken zum Aufnehmen",
		"floating.status_ready":   "Bereit",
		"floating.status_record":  "Aufnahme…",
		"floating.status_working": "Verarbeitung…",
		"floating.last_text":      "Zuletzt: \"%s\"",
		"floating.name":           "Aufnahme-Button",
		"floating.tip_ready":       "WhisPaste — Bereit",
		"floating.tip_recording":   "WhisPaste — Aufnahme…",
		"floating.tip_paused":      "WhisPaste — Pausiert",
		"floating.tip_transcribing":"WhisPaste — Transkribiere…",
		"floating.tip_processing":  "WhisPaste — Verarbeite…",

		// Floating button shapes & colors
		"shapeCircle":   "Kreis",
		"shapeSquircle": "Abgerundetes Quadrat",
		"shapeRounded":  "Abgerundetes Rechteck",
		"shapeHexagon":  "Sechseck",
		"shapeDiamond":  "Raute",
		"shapeStar":     "Stern",
		"colorCyan":     "Cyan",
		"colorBlue":     "Blau",
		"colorPurple":   "Lila",
		"colorRose":     "Rosa",
		"colorOrange":   "Orange",
		"colorAmber":    "Bernstein",
		"colorEmerald":  "Smaragd",
		"colorSlate":    "Schiefer",
		"colorCustom":   "Eigene Farbe",

		// Dashboard greeting
		"greeting.morning":       "Guten Morgen",
		"greeting.afternoon":     "Guten Nachmittag",
		"greeting.evening":       "Guten Abend",
		"greeting.recording":     "Aufnahme",
		"greeting.recordings":    "Aufnahmen",
		"greeting.today_suffix":  "heute",
		"greeting.weekend":       "Schönes Wochenende!",
		"greeting.earlybird":     "Früh dran heute!",
		"greeting.ready":         "Bereit, wenn du es bist.",
		"greeting.productive":    "Wow, {count} Aufnahmen heute! 🔥",

		// Milestone celebrations
		"milestone.10":           "🎉 10 Diktate! Du bist gestartet!",
		"milestone.50":           "🔥 50 Diktate! Du bist richtig dabei!",
		"milestone.100":          "🏆 100 Diktate! Power-User-Status!",
		"milestone.250":          "⚡ 250 Diktate! Beeindruckendes Engagement!",
		"milestone.500":          "🌟 500 Diktate! Du bist ein WhisPaste-Profi!",
		"milestone.1000":         "💎 1000 Diktate! Legendär!",
		"milestone.dictations":   "Diktate",

		// Empty state
		"emptyState.title":       "Deine Stimme, deine Worte",
		"emptyState.desc":        "Drücke die Tastenkombination oder klicke den Aufnahme-Button, um dein erstes Diktat zu starten.",

		// States
		"chars": "Zeichen",

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
		"error.no_api_key":                        "Noch kein API-Key hinterlegt. Geh in die Einstellungen, um deinen einzutragen.",
		"error.no_local_model":                    "Kein lokales Modell heruntergeladen. Öffne Einstellungen → Lokale Modelle und lade zuerst ein Modell herunter.",
		"error.recording":                         "Aufnahme hat nicht geklappt: %s",
		"error.transcription":                     "Konnte das Audio nicht transkribieren: %s",
		"error.hotkey":                            "Tastenkombination %s konnte nicht registriert werden — vermutlich von einer anderen App belegt.",
		"error.microphone":                        "Mikrofon nicht verfügbar: %s",
		"error.clipboard":                         "Zwischenablage nicht erreichbar: %s",
		"error.postprocess_request":               "Smart Mode konnte das nicht verarbeiten",
		"error.postprocess_api":                   "Smart Mode hat ein Problem (Fehler %d)",
		"error.postprocess_empty":                 "Smart Mode hat nichts zurückgegeben — versuch es nochmal",
		"error.postprocess_parse":                 "Konnte die Smart-Mode-Antwort nicht lesen",
		"preflight.summary.pass":                  "Dein Gerät ist bereit für lokale Transkription.",
		"preflight.summary.pass_download":         "Dein Gerät ist bereit — lade einfach das Modell herunter.",
		"preflight.summary.warn":                  "Lokale Transkription funktioniert, kann aber auf diesem Gerät langsamer sein.",
		"preflight.summary.fail":                  "Dieses Gerät kann keine lokale Transkription ausführen. Nutze stattdessen die Cloud-Variante.",
		"preflight.reason.os":                     "Lokale Transkription ist derzeit nur unter Windows verfügbar.",
		"preflight.reason.arch":                   "Der Prozessor dieses Geräts ist nicht kompatibel mit lokaler Transkription.",
		"preflight.reason.avx":                    "Dein Prozessor ist zu alt für lokale Transkription. Nutze stattdessen die Cloud-Variante.",
		"preflight.reason.avx2":                   "Dein Prozessor ist etwas älter — lokale Transkription funktioniert, kann aber langsamer sein.",
		"preflight.reason.cores":                  "Dieses Gerät kann bei lokaler Transkription langsam sein. Kürzere Aufnahmen funktionieren am besten.",
		"preflight.reason.memory":                 "Nicht genug Arbeitsspeicher (RAM) für lokale Transkription. Nutze stattdessen die Cloud-Variante.",
		"preflight.reason.disk":                   "Nicht genug Speicherplatz für das gewählte Modell.",
		"preflight.reason.runtime":                "Die Transkriptions-Engine konnte nicht starten. Eine Systemkomponente fehlt möglicherweise — siehe aka.ms/vs/17/release/vc_redist.x64.exe",
		"preflight.reason.unknown":                "Lokale Transkription ist noch nicht verfügbar — eine Kompatibilitätsprüfung muss erst bestanden werden.",
		"preflight.check.os":                      "Betriebssystem",
		"preflight.check.arch":                    "Prozessor-Typ",
		"preflight.check.avx":                     "Prozessor-Kompatibilität",
		"preflight.check.avx2":                    "Prozessor-Geschwindigkeit",
		"preflight.check.cores":                   "Rechenleistung",
		"preflight.check.memory":                  "Arbeitsspeicher (RAM)",
		"preflight.check.disk":                    "Speicherplatz",
		"preflight.check.runtime":                 "Transkriptions-Engine",
		"preflight.detail.os.fail":                "Lokale Transkription ist aktuell nur unter Windows verfügbar.",
		"preflight.detail.arch.fail":              "Lokale Transkription benötigt einen modernen 64-Bit-Prozessor. Dein Gerät verwendet einen anderen Typ.",
		"preflight.detail.avx.fail":               "Dein Prozessor unterstützt eine nötige Funktion nicht (AVX). Cloud-Transkription funktioniert auf allen Geräten.",
		"preflight.detail.avx2.warn":              "Deinem Prozessor fehlt ein Geschwindigkeits-Feature (AVX2). Transkription funktioniert trotzdem, nur etwas langsamer.",
		"preflight.detail.cores.warn":             "Dein Gerät hat begrenzte Rechenleistung, daher kann die Transkription bei längeren Aufnahmen etwas dauern.",
		"preflight.detail.memory.fail":            "Lokale Transkription benötigt mindestens 4 GB Arbeitsspeicher (RAM). Dein Gerät hat weniger.",
		"preflight.detail.memory.warn":            "Für beste Leistung werden 8 GB Arbeitsspeicher (RAM) oder mehr empfohlen.",
		"preflight.detail.disk.fail":              "Bitte schaffe zuerst Speicherplatz frei, bevor du ein Modell herunterlädst (%s).",
		"preflight.detail.disk.warn":              "Der Speicherplatz wird knapp für Modell-Downloads.",
		"preflight.detail.runtime.fail":           "Die Transkriptions-Engine konnte nicht starten: %s — Installiere die Visual C++ Runtime von aka.ms/vs/17/release/vc_redist.x64.exe und starte neu.",
		"preflight.detail.runtime.fail_no_output": "Die Transkriptions-Engine konnte nicht richtig starten. Installiere die Visual C++ Runtime von aka.ms/vs/17/release/vc_redist.x64.exe und starte neu.",
		"audio.device_unavailable":                "Das gewählte Mikrofon ist nicht mehr verfügbar. Wähle in den Einstellungen ein anderes Aufnahmegerät.",

		// Updates
		"update.available":          "Update verfügbar: v%s",
		"update.downloading":        "Update wird heruntergeladen…",
		"update.ready":              "Neustart für Update",
		"update.failed":             "Update fehlgeschlagen: %s",
		"update.check":              "Nach Updates suchen",
		"update.check_failed":       "Nach Updates suchen (⚠ letzte Prüfung fehlgeschlagen)",
		"update.up_to_date":         "Aktuell ✓",
		"update.notify_downloading": "Update v%s wird heruntergeladen…",
		"update.notify_ready":       "Update installiert — zum Neustarten klicken",
		"update.permission_failed":  "Update kann nicht installiert werden",
		"update.permission_hint":    "Bitte installiere WhisPaste neu von whispaste.de, um Auto-Updates zu reparieren.",

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
		"tray.auto_paste":       "Auto-Einfügen",
		"tray.history":          "Letzte Transkriptionen",
		"tray.history_empty":    "Noch keine Aufnahmen",
		"tray.notebook":         "Notizbuch öffnen",
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
		"balloon.smart_mode_raw":         "Smart-Modus fehlgeschlagen - Rohtext wurde verwendet.",
		"balloon.paste_clipboard_only":   "Hier konnte nicht eingefügt werden - der Text liegt in deiner Zwischenablage.",
		"balloon.test":                   "Test-Benachrichtigung — wenn du das siehst, funktionieren Benachrichtigungen!",

		// Pending transcription
		"transcribing":            "Wird transkribiert…",
		"transcription_cancelled": "Abgebrochen",
		"transcription_failed":    "Fehlgeschlagen",

		// Relative time
		"time_just_now":  "gerade eben",
		"time_min_ago":   "vor %d Min.",
		"time_hours_ago": "vor %d Std.",
		"time_yesterday": "Gestern",
		"time_day_mon":   "Mo",
		"time_day_tue":   "Di",
		"time_day_wed":   "Mi",
		"time_day_thu":   "Do",
		"time_day_fri":   "Fr",
		"time_day_sat":   "Sa",
		"time_day_sun":   "So",

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
		"notebook.copy_text":       "Text kopieren",
		"notebook.copy_markdown":   "Als Markdown kopieren",
		"notebook.date":            "Datum",
		"notebook.language":        "Sprache",
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

		// Notes & Attachments
		"notebook.notes":              "Notizen",
		"notebook.attachments":        "Anhänge",
		"notebook.add_note":           "Notiz hinzufügen",
		"notebook.add_note_placeholder": "Notiz schreiben…",
		"notebook.add_file":           "Datei hinzufügen",
		"notebook.open_file":          "Datei öffnen",

		// Feature Discovery
		"discovery.smartmode.title": "KI-gestützte Verfeinerung",
		"discovery.smartmode.desc":  "Smart Mode verfeinert deine Diktate mit KI — probier es aus!",
		"discovery.analytics.title": "Deine Diktat-Einblicke",
		"discovery.analytics.desc":  "Sieh dir deine Diktatmuster und Produktivitätstrends an.",
		"discovery.replacements.title": "Automatische Wortkorrekturen",
		"discovery.replacements.desc":  "Korrigiere Wörter und Ausdrücke automatisch in jedem Diktat.",
		"discovery.gotIt":           "Verstanden",

		// Keyboard Shortcuts Help
		"shortcuts.title":          "Tastenkürzel",
		"shortcuts.nav":            "Navigation",
		"shortcuts.recording":      "Aufnahme",
		"shortcuts.smartmode":      "Smart Mode",
		"shortcuts.other":          "Sonstiges",
		"shortcuts.record_stop":    "Aufnahme / Stopp",
		"shortcuts.toggle_smartmode": "Smart Mode umschalten",
		"shortcuts.search_history": "Verlauf durchsuchen",
		"shortcuts.close_dialog":   "Schließen / Aufheben",
		"shortcuts.this_help":      "Diese Hilfe",
		"shortcuts.previous_page":  "Vorherige Seite",
		"shortcuts.command_palette": "Befehlspalette",

		"show_more": "Mehr anzeigen",

		// Title
		"title.edit":       "Titel bearbeiten",
		"title.generating": "Titel wird erstellt…",

		// Config Warnings
		"warn.no_api_key":           "Cloud-API-Modus ist aktiv, aber kein API-Key konfiguriert. Aufnahmen werden fehlschlagen.",
		"warn.model_not_downloaded": "Lokales STT-Modell ist ausgewählt, aber nicht heruntergeladen. Bitte in den Einstellungen herunterladen.",

		// Settings: Progressive Disclosure
		"settings.advanced": "Erweiterte Einstellungen",

		// Tray
		"tray.open":      "WhisPaste öffnen",
		"tray.open_desc": "Hauptfenster öffnen",

		// History Groups
		"group.none":       "Keine Gruppierung",
		"group.by_date":    "Nach Datum",
		"group.by_project": "Nach Projekt",
		"group.by_language":"Nach Sprache",
		"group.today":      "Heute",
		"group.yesterday":  "Gestern",
		"group.this_week":  "Diese Woche",
		"group.this_month": "Diesen Monat",
		"group.older":      "Älter",
		"group.no_project": "Kein Projekt",
		"group.unknown":    "Unbekannt",
		"group.entry":      "Eintrag",
		"group.entries":    "Einträge",
		"group.of":         "von",
		"group.select_all": "Alle in Gruppe auswählen",

		// View modes
		"view.card": "Kartenansicht",
		"view.list": "Listenansicht",
		"view.tile": "Kachelansicht",
	},
}
