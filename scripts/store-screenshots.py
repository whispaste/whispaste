#!/usr/bin/env python3
"""
Automated Microsoft Store screenshot generator for WhisPaste.

Assembles the app UI from embedded files (same as Go's assembleMainHTML),
injects mock Go bindings with demo data, and uses Playwright to capture
screenshots at 1366×768 for Store submission.

Usage:
    python scripts/store-screenshots.py [--lang en|de] [--theme dark|light]
    python scripts/store-screenshots.py --all   # EN+DE, dark only

Output: screenshots/ directory with PNG files.
"""

import argparse
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "ui_main"
TEMPLATE = UI_DIR / "template.html"
STYLES_DIR = UI_DIR / "styles"
SCRIPTS_DIR = UI_DIR / "scripts"
PAGES_DIR = UI_DIR / "pages"
OUTPUT_DIR = ROOT / "screenshots"

# ── Screenshot specs ───────────────────────────────────────────────────────────
WIDTH, HEIGHT = 1366, 768

SCREENSHOTS = [
    {"page": "history",   "file": "screenshot-03-history.png",   "wait": 1500},
    {"page": "smartmode", "file": "screenshot-02-smartmode.png",  "wait": 1200},
    {"page": "analytics", "file": "screenshot-06-analytics.png",  "wait": 2000},
    {"page": "settings",  "file": "screenshot-05-models.png",     "wait": 1500, "scroll_to": "section-ai"},
]


# ── HTML Assembly (mirrors Go's assembleMainHTML) ──────────────────────────────
def collect_files(directory: Path, ext: str) -> str:
    """Collect and concatenate files from a directory, sorted alphabetically."""
    parts = []
    files = sorted(directory.glob(f"*{ext}"))
    for f in files:
        name = f.name
        content = f.read_text(encoding="utf-8")
        if ext in (".css", ".js"):
            parts.append(f"/* --- {name} --- */\n{content}")
        else:
            parts.append(f"<!-- --- {name} --- -->\n{content}")
    return "\n".join(parts)


def assemble_html(theme: str, lang: str) -> str:
    """Build the full HTML page with mock bindings injected."""
    template = TEMPLATE.read_text(encoding="utf-8")
    css = collect_files(STYLES_DIR, ".css")
    js = collect_files(SCRIPTS_DIR, ".js")
    pages = collect_files(PAGES_DIR, ".html")

    mock_js = build_mock_bindings(theme, lang)

    html = template
    html = html.replace("/* {{STYLES}} */", css, 1)
    html = html.replace("<!-- {{PAGES}} -->", pages, 1)
    # Inject mocks BEFORE real scripts so bindings are available at init
    html = html.replace("/* {{SCRIPTS}} */", mock_js + "\n" + js, 1)
    return html


# ── Demo Data ──────────────────────────────────────────────────────────────────
def _demo_entries(lang: str) -> list:
    """Generate 12 realistic demo entries."""
    now = datetime.now()
    entries_de = [
        {"text": "Sehr geehrte Frau Mueller, vielen Dank für Ihre Nachricht bezüglich des Projekts Alpha. Ich bestätige hiermit den Termin am Donnerstag um 14 Uhr. Die Unterlagen werde ich bis Mittwoch vorbereiten und Ihnen zukommen lassen. Mit freundlichen Grüßen",
         "title": "E-Mail Terminbestätigung", "days": 0, "h": 10, "m": 15, "dur": 12.5, "proc": 1.8,
         "lang": "de", "tags": ["Meeting", "Wichtig"], "pinned": True, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_alpha"},
        {"text": "Die Quartalszahlen zeigen einen Anstieg von 15 Prozent im Vergleich zum Vorjahr. Besonders der Bereich digitale Transformation hat signifikant zugelegt. Wir sollten die Investitionen in Cloud-Infrastruktur weiter ausbauen.",
         "title": "Quartalsbericht Q4", "days": 0, "h": 14, "m": 30, "dur": 18.3, "proc": 2.1,
         "lang": "de", "tags": ["Bericht"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_beta"},
        {"text": "Please review the attached pull request for the authentication module. I've implemented JWT token refresh with sliding expiration and added comprehensive unit tests. The migration script handles the schema changes gracefully.",
         "title": "PR Review Auth Module", "days": 1, "h": 9, "m": 45, "dur": 22.1, "proc": 1.5,
         "lang": "en", "tags": ["Code Review"], "pinned": True, "source": "dictation",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.012, "project_id": "proj_alpha"},
        {"text": "Notiz für das nächste Team-Meeting: Onboarding-Prozess überarbeiten, neue Mitarbeiter brauchen bessere Dokumentation. Design-System aktualisieren. Sprint-Retrospektive auf Freitag verschieben.",
         "title": "Team-Meeting Notizen", "days": 1, "h": 16, "m": 0, "dur": 15.7, "proc": 1.9,
         "lang": "de", "tags": ["Meeting", "Follow-up"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "The new landing page design should emphasize our core value proposition: simplicity and speed. We need a hero section with a clear CTA, trust badges from enterprise customers, and a live demo section showing the voice-to-text workflow.",
         "title": "Landing Page Redesign", "days": 2, "h": 11, "m": 20, "dur": 25.4, "proc": 2.3,
         "lang": "en", "tags": ["Design"], "pinned": False, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.015, "project_id": "proj_beta"},
        {"text": "Einkaufsliste für das Büro: Druckerpapier, Toner für den Laserdrucker, Post-it Notizblöcke in drei Farben, Whiteboard-Marker, und neue Kugelschreiber. Außerdem brauchen wir noch Kaffee und Milch für die Küche.",
         "title": "Büro Einkaufsliste", "days": 2, "h": 13, "m": 45, "dur": 8.2, "proc": 1.1,
         "lang": "de", "tags": [], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "Customer feedback summary: Users love the floating button concept but request more customization options. Top requests are opacity control, position locking, and custom hotkey assignments. Mobile companion app was mentioned by 3 enterprise clients.",
         "title": "Customer Feedback Q4", "days": 3, "h": 10, "m": 0, "dur": 19.8, "proc": 2.0,
         "lang": "en", "tags": ["Feedback", "Wichtig"], "pinned": True, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.011, "project_id": "proj_alpha"},
        {"text": "Die neue Datenschutzrichtlinie muss bis Ende des Monats fertiggestellt werden. Wir müssen sicherstellen, dass alle DSGVO-Anforderungen erfüllt sind. Der externe Datenschutzbeauftragte hat einige Änderungsvorschläge gemacht.",
         "title": "DSGVO Compliance Update", "days": 4, "h": 15, "m": 30, "dur": 14.6, "proc": 1.7,
         "lang": "de", "tags": ["Compliance"], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_beta"},
        {"text": "Reminder: Book flight to Munich for the developer conference on March 25th. Hotel reservation at Marriott confirmed. Presentation slides need final review by March 20th. Don't forget to pack the demo hardware.",
         "title": "Conference Travel Planning", "days": 5, "h": 8, "m": 30, "dur": 11.3, "proc": 1.4,
         "lang": "en", "tags": ["Travel"], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "API-Rate-Limiting implementieren: Maximum 100 Anfragen pro Minute pro API-Key. Exponentielles Backoff bei Überschreitung. Redis als Cache-Layer für Token-Bucket-Algorithmus. Monitoring über Grafana Dashboard.",
         "title": "API Rate Limiting Spec", "days": 6, "h": 11, "m": 15, "dur": 16.9, "proc": 2.2,
         "lang": "de", "tags": ["Code Review", "Wichtig"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_alpha"},
        {"text": "Weekly standup notes: Backend team finished the migration to PostgreSQL 16. Frontend team is working on the new dashboard components. QA found 3 critical bugs in the payment flow that need immediate attention.",
         "title": "Weekly Standup Notes", "days": 7, "h": 9, "m": 0, "dur": 20.5, "proc": 1.8,
         "lang": "en", "tags": ["Meeting"], "pinned": False, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.013, "project_id": "proj_beta"},
        {"text": "Idee für ein neues Feature: Automatische Zusammenfassung von langen Transkriptionen mit KI. Der Benutzer könnte nach der Aufnahme wählen ob er den vollen Text oder eine Zusammenfassung in die Zwischenablage kopieren möchte.",
         "title": "Feature-Idee: Auto-Summary", "days": 8, "h": 14, "m": 45, "dur": 13.8, "proc": 1.6,
         "lang": "de", "tags": ["Idee"], "pinned": True, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
    ]

    entries_en = [
        {"text": "Dear Ms. Mueller, thank you for your message regarding the Alpha project. I hereby confirm the appointment on Thursday at 2 PM. I will prepare the documents by Wednesday and send them to you. Best regards",
         "title": "Email Appointment Confirmation", "days": 0, "h": 10, "m": 15, "dur": 12.5, "proc": 1.8,
         "lang": "en", "tags": ["Meeting", "Important"], "pinned": True, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_alpha"},
        {"text": "The quarterly numbers show a 15 percent increase compared to last year. The digital transformation area in particular has grown significantly. We should continue to expand investments in cloud infrastructure.",
         "title": "Quarterly Report Q4", "days": 0, "h": 14, "m": 30, "dur": 18.3, "proc": 2.1,
         "lang": "en", "tags": ["Report"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_beta"},
        {"text": "Please review the attached pull request for the authentication module. I've implemented JWT token refresh with sliding expiration and added comprehensive unit tests. The migration script handles the schema changes gracefully.",
         "title": "PR Review Auth Module", "days": 1, "h": 9, "m": 45, "dur": 22.1, "proc": 1.5,
         "lang": "en", "tags": ["Code Review"], "pinned": True, "source": "dictation",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.012, "project_id": "proj_alpha"},
        {"text": "Note for the next team meeting: Revise onboarding process, new employees need better documentation. Update design system. Move sprint retrospective to Friday.",
         "title": "Team Meeting Notes", "days": 1, "h": 16, "m": 0, "dur": 15.7, "proc": 1.9,
         "lang": "en", "tags": ["Meeting", "Follow-up"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "The new landing page design should emphasize our core value proposition: simplicity and speed. We need a hero section with a clear CTA, trust badges from enterprise customers, and a live demo section showing the voice-to-text workflow.",
         "title": "Landing Page Redesign", "days": 2, "h": 11, "m": 20, "dur": 25.4, "proc": 2.3,
         "lang": "en", "tags": ["Design"], "pinned": False, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.015, "project_id": "proj_beta"},
        {"text": "Office supply list: Printer paper, toner for the laser printer, post-it pads in three colors, whiteboard markers, and new ballpoint pens. We also need coffee and milk for the kitchen.",
         "title": "Office Supply List", "days": 2, "h": 13, "m": 45, "dur": 8.2, "proc": 1.1,
         "lang": "en", "tags": [], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "Customer feedback summary: Users love the floating button concept but request more customization options. Top requests are opacity control, position locking, and custom hotkey assignments. Mobile companion app was mentioned by 3 enterprise clients.",
         "title": "Customer Feedback Q4", "days": 3, "h": 10, "m": 0, "dur": 19.8, "proc": 2.0,
         "lang": "en", "tags": ["Feedback", "Important"], "pinned": True, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.011, "project_id": "proj_alpha"},
        {"text": "The new privacy policy must be completed by the end of the month. We need to ensure all GDPR requirements are met. The external data protection officer has made some suggestions for changes.",
         "title": "GDPR Compliance Update", "days": 4, "h": 15, "m": 30, "dur": 14.6, "proc": 1.7,
         "lang": "en", "tags": ["Compliance"], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_beta"},
        {"text": "Reminder: Book flight to Munich for the developer conference on March 25th. Hotel reservation at Marriott confirmed. Presentation slides need final review by March 20th. Don't forget to pack the demo hardware.",
         "title": "Conference Travel Planning", "days": 5, "h": 8, "m": 30, "dur": 11.3, "proc": 1.4,
         "lang": "en", "tags": ["Travel"], "pinned": False, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
        {"text": "Implement API rate limiting: Maximum 100 requests per minute per API key. Exponential backoff on exceeded limits. Redis as cache layer for token bucket algorithm. Monitoring via Grafana dashboard.",
         "title": "API Rate Limiting Spec", "days": 6, "h": 11, "m": 15, "dur": 16.9, "proc": 2.2,
         "lang": "en", "tags": ["Code Review", "Important"], "pinned": False, "source": "smart",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": "proj_alpha"},
        {"text": "Weekly standup notes: Backend team finished the migration to PostgreSQL 16. Frontend team is working on the new dashboard components. QA found 3 critical bugs in the payment flow that need immediate attention.",
         "title": "Weekly Standup Notes", "days": 7, "h": 9, "m": 0, "dur": 20.5, "proc": 1.8,
         "lang": "en", "tags": ["Meeting"], "pinned": False, "source": "smart",
         "model": "whisper-1", "is_local": False, "cost_usd": 0.013, "project_id": "proj_beta"},
        {"text": "Idea for a new feature: Automatic summarization of long transcriptions with AI. The user could choose after recording whether to copy the full text or a summary to the clipboard.",
         "title": "Feature Idea: Auto-Summary", "days": 8, "h": 14, "m": 45, "dur": 13.8, "proc": 1.6,
         "lang": "en", "tags": ["Idea"], "pinned": True, "source": "dictation",
         "model": "whisper-small", "is_local": True, "cost_usd": 0, "project_id": ""},
    ]

    raw = entries_de if lang == "de" else entries_en

    result = []
    for i, e in enumerate(raw):
        target_date = (now - timedelta(days=e["days"])).date()
        ts = datetime.combine(target_date, datetime.min.time().replace(hour=e["h"], minute=e["m"]))
        proj_name = ""
        if e["project_id"] == "proj_alpha":
            proj_name = "Project Alpha"
        elif e["project_id"] == "proj_beta":
            proj_name = "Project Beta"

        result.append({
            "id": f"demo_{i+1:03d}",
            "text": e["text"],
            "title": e["title"],
            "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S"),
            "duration_sec": e["dur"],
            "processing_duration_sec": e["proc"],
            "language": e["lang"],
            "tags": e["tags"],
            "pinned": e["pinned"],
            "source": e["source"],
            "model": e["model"],
            "is_local": e["is_local"],
            "cost_usd": e["cost_usd"],
            "project_id": e["project_id"],
            "project_name": proj_name,
            "archived": False,
        })
    return result


def _demo_projects() -> list:
    now = datetime.now()
    return [
        {"id": "proj_alpha", "name": "Project Alpha", "created_at": (now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%S"), "count": 4},
        {"id": "proj_beta", "name": "Project Beta", "created_at": (now - timedelta(days=20)).strftime("%Y-%m-%dT%H:%M:%S"), "count": 4},
    ]


def _demo_analytics() -> dict:
    now = datetime.now()
    daily_counts = {}
    daily_model_counts = {}
    for d in range(30):
        date_str = (now - timedelta(days=d)).strftime("%Y-%m-%d")
        count = max(0, 5 - abs(d - 5) + (d % 3))
        daily_counts[date_str] = count
        daily_model_counts[date_str] = [
            {"model": "whisper-small", "isLocal": True, "count": max(0, count - 1)},
            {"model": "whisper-1", "isLocal": False, "count": min(count, 1)},
        ]

    return {
        "totalEntries": 87,
        "localEntries": 62,
        "apiEntries": 25,
        "totalDuration": 1247.5,
        "totalCost": 0.312,
        "savings": 4.85,
        "dailyCounts": daily_counts,
        "dailyModelCounts": daily_model_counts,
        "modelCounts": {"whisper-small": 62, "whisper-1": 25},
        "durationBuckets": {"<15s": 28, "15-30s": 35, "30-60s": 18, "1-3m": 5, ">3m": 1},
        "avgDuration": 14.3,
        "minDuration": 3.2,
        "maxDuration": 195.7,
        "avgProcessingDuration": 1.8,
        "totalProcessingTime": 156.6,
        "totalWords": 12450,
        "avgWordsPerEntry": 143.1,
        "modelBenchmarks": {
            "whisper-small": {
                "count": 62, "duration": 892.3, "processing": 111.6,
                "words": 8860, "speedRatio": 8.0, "wordsPerMin": 85.2
            },
            "whisper-1": {
                "count": 25, "duration": 355.2, "processing": 45.0,
                "words": 3590, "speedRatio": 7.9, "wordsPerMin": 78.4
            },
        },
        "monthlyCosts": {
            (now - timedelta(days=60)).strftime("%Y-%m"): 0.089,
            (now - timedelta(days=30)).strftime("%Y-%m"): 0.115,
            now.strftime("%Y-%m"): 0.108,
        },
    }


def _demo_config(theme: str, lang: str) -> dict:
    return {
        "api_key": "sk-demo••••••••••••",
        "api_endpoint": "https://api.openai.com/v1",
        "hotkey_modifiers": ["Ctrl", "Shift"],
        "hotkey_key": "D",
        "mode": "push_to_talk",
        "language": "auto",
        "model": "whisper-1",
        "overlay_position": "bottom",
        "auto_paste": True,
        "play_sounds": True,
        "sound_volume": 0.8,
        "check_updates": True,
        "update_channel": "stable",
        "autostart": True,
        "close_to_tray": True,
        "delete_behavior": "archive",
        "ui_language": lang,
        "theme": theme,
        "max_record_sec": 120,
        "smart_mode": True,
        "smart_mode_preset": "cleanup",
        "smart_mode_prompt": "",
        "smart_mode_target": "clipboard",
        "smart_mode_provider": "auto",
        "text_replacement_provider": "local",
        "notify_background": True,
        "notify_complete": True,
        "notify_donate": False,
        "input_device": "",
        "input_gain": 1.0,
        "cleanup_enabled": True,
        "cleanup_max_entries": 500,
        "cleanup_max_age_days": 90,
        "cleanup_include_pinned": False,
        "trim_silence": True,
        "use_vad": True,
        "vad_sensitivity": 0.5,
        "floating_button_enabled": True,
        "floating_button_color": "cyan",
        "floating_button_size": 56,
        "floating_button_opacity": 70,
        "floating_button_locked": False,
        "floating_button_border": False,
        "active_model_local": True,
        "app_detection": True,
    }


BUILTIN_PRESETS = {
    "cleanup": "Clean up the following dictated text...",
    "concise": "Rewrite the following text to be significantly more concise...",
    "email": "Rewrite the following dictated text as a professional email...",
    "bullets": "Rewrite the following dictated text as a structured bullet-point list...",
    "formal": "Rewrite the following dictated text in formal, professional language...",
    "aiprompt": "Transform the following dictated text into an optimized AI prompt...",
    "summary": "Summarize the following text in 2-4 sentences maximum...",
    "notes": "Rewrite the following dictated text as structured notes...",
    "meeting": "Rewrite the following dictated text as structured meeting minutes...",
    "social": "Rewrite the following dictated text as a social media post...",
    "technical": "Rewrite the following dictated text as technical documentation...",
    "casual": "Rewrite the following dictated text in a casual, conversational tone...",
}

STT_MODELS = [
    {"id": "whisper-tiny", "name": "Tiny", "size": "31 MB", "downloaded": False,
     "preflight_blocked": False, "preflight_status": "ok", "preflight_message": "",
     "quality": "basic", "min_ram_gb": 2, "rec_ram_gb": 4, "recommended": False},
    {"id": "whisper-base", "name": "Base", "size": "57 MB", "downloaded": True,
     "preflight_blocked": False, "preflight_status": "ok", "preflight_message": "",
     "quality": "good", "min_ram_gb": 4, "rec_ram_gb": 4, "recommended": False},
    {"id": "whisper-small", "name": "Small", "size": "181 MB", "downloaded": True,
     "preflight_blocked": False, "preflight_status": "ok", "preflight_message": "",
     "quality": "very good", "min_ram_gb": 4, "rec_ram_gb": 8, "recommended": True},
    {"id": "whisper-medium", "name": "Medium", "size": "514 MB", "downloaded": False,
     "preflight_blocked": False, "preflight_status": "ok", "preflight_message": "",
     "quality": "excellent", "min_ram_gb": 8, "rec_ram_gb": 16, "recommended": False},
    {"id": "whisper-large-v3-turbo", "name": "Large v3 Turbo", "size": "547 MB", "downloaded": False,
     "preflight_blocked": False, "preflight_status": "ok", "preflight_message": "",
     "quality": "best", "min_ram_gb": 12, "rec_ram_gb": 16, "recommended": False},
]


# ── Mock Bindings JavaScript ──────────────────────────────────────────────────
def build_mock_bindings(theme: str, lang: str) -> str:
    entries = _demo_entries(lang)
    projects = _demo_projects()
    analytics = _demo_analytics()
    config = _demo_config(theme, lang)

    tag_colors = {"Meeting": 0, "Wichtig": 1, "Important": 1, "Code Review": 2,
                  "Follow-up": 3, "Design": 4, "Feedback": 5, "Compliance": 6,
                  "Travel": 7, "Idee": 8, "Idea": 8, "Bericht": 9, "Report": 9}
    custom_tags = list(set(t for e in entries for t in e.get("tags", [])))

    audio_devices = [
        {"id": "dev-1", "name": "Microphone (Realtek High Definition Audio)"},
        {"id": "dev-2", "name": "USB Headset (Jabra Link 370)"},
    ]

    available_models = [
        {"id": "whisper-small", "name": "Small", "meta": "Local · 181 MB", "isLocal": True},
        {"id": "whisper-1", "name": "Whisper-1", "meta": "OpenAI API", "isLocal": False},
    ]

    translations_de = {
        "navHistory": "Verlauf", "navSmartMode": "Smart-Modus", "navReplacements": "Snippets",
        "navAnalytics": "Statistik", "navSettings": "Einstellungen", "navAbout": "Über",
        "fab.record": "Aufnahme starten", "history.title": "Transkriptionsverlauf",
        "history.search": "Suchen...", "history.noEntries": "Noch keine Transkriptionen",
        "settings.title": "Einstellungen", "settings.save": "Speichern",
        "settings.api_key": "API-Schlüssel", "settings.hotkey": "Hotkey",
        "stats.title": "Statistik", "app.name": "WhisPaste",
        "notebook.title": "Verlauf", "notebook.search": "Einträge durchsuchen...",
        "update.check": "Nach Updates suchen",
    }
    translations_en = {
        "navHistory": "History", "navSmartMode": "Smart Mode", "navReplacements": "Snippets",
        "navAnalytics": "Analytics", "navSettings": "Settings", "navAbout": "About",
        "fab.record": "Start Recording", "history.title": "Transcription History",
        "history.search": "Search...", "history.noEntries": "No transcriptions yet",
        "settings.title": "Settings", "settings.save": "Save",
        "settings.api_key": "API Key", "settings.hotkey": "Hotkey",
        "stats.title": "Analytics", "app.name": "WhisPaste",
        "notebook.title": "History", "notebook.search": "Search entries...",
        "update.check": "Check for Updates",
    }
    translations = translations_de if lang == "de" else translations_en

    # Smart mode detection bindings
    detection_apps = [
        {"name": "Microsoft Outlook", "exe": "OUTLOOK.EXE", "preset": "email"},
        {"name": "Microsoft Teams", "exe": "ms-teams.exe", "preset": "meeting"},
        {"name": "Visual Studio Code", "exe": "Code.exe", "preset": "technical"},
    ]

    return f"""
// ══ MOCK BINDINGS (injected for screenshot automation) ══════════════════════
(function() {{
    // -- Theme & Language (set before init reads them) --
    // Init reads window._theme and window._lang (05-init.js:104,108)
    window._theme = {json.dumps(theme)};
    window._lang = {json.dumps(lang)};
    window._initialPage = 'history';
    window._showOnboarding = false;
    window._isStorePackage = false;

    // -- Global bindings --
    window.getTheme = () => Promise.resolve({json.dumps(theme)});
    window.getUILanguage = () => Promise.resolve({json.dumps(lang)});
    window.getTranslations = () => Promise.resolve(JSON.stringify({json.dumps(translations)}));
    window.getConfig = () => Promise.resolve(JSON.stringify({json.dumps(config)}));
    window.windowReady = () => {{}};
    window.startCapture = () => {{}};
    window.isStorePackage = () => Promise.resolve(false);
    window.setTheme = (t) => {{}};
    window.setUILanguage = (l) => {{}};
    window.openExternal = (u) => {{}};
    window.logJS = (m) => console.log('[JS]', m);
    window.showMainWindowOnPage = (p) => {{}};

    // -- History bindings --
    window.getEntries = () => Promise.resolve(JSON.stringify({json.dumps(entries)}));
    window.getProjects = () => Promise.resolve(JSON.stringify({json.dumps(projects)}));
    window.getCustomTags = () => Promise.resolve(JSON.stringify({json.dumps(custom_tags)}));
    window.getTagColors = () => Promise.resolve(JSON.stringify({json.dumps(tag_colors)}));
    window.deleteEntry = (id) => Promise.resolve();
    window.updateEntryText = (id, t) => Promise.resolve();
    window.updateEntryTitle = (id, t) => Promise.resolve();
    window.togglePin = (id) => Promise.resolve(true);
    window.setEntryProject = (id, p) => Promise.resolve();
    window.setEntryTags = (id, t) => Promise.resolve();
    window.hasAudio = (id) => Promise.resolve(false);
    window.copyToClipboard = (t) => Promise.resolve();
    window.archiveEntry = (id) => Promise.resolve();
    window.restoreEntry = (id) => Promise.resolve();
    window.getArchivedEntries = () => Promise.resolve('[]');

    // -- Analytics bindings --
    window.getAnalytics = (period) => Promise.resolve(JSON.stringify({json.dumps(analytics)}));

    // -- Smart mode bindings --
    window.getBuiltinPresets = () => Promise.resolve(JSON.stringify({json.dumps(BUILTIN_PRESETS)}));
    window.getCustomTemplates = () => Promise.resolve('[]');
    window.saveCustomTemplate = (t) => Promise.resolve();
    window.deleteCustomTemplate = (id) => Promise.resolve();
    window.getDetectionApps = () => Promise.resolve(JSON.stringify({json.dumps(detection_apps)}));
    window.setSmartModePreset = (p) => {{}};
    window.getActivePresetName = () => Promise.resolve('cleanup');

    // -- Settings bindings --
    window._getModels = () => Promise.resolve({json.dumps(STT_MODELS)});
    window.getAvailableModels = () => Promise.resolve(JSON.stringify({json.dumps(available_models)}));
    window._getAudioDevices = () => Promise.resolve(JSON.stringify({json.dumps(audio_devices)}));
    window.saveConfig = (c) => Promise.resolve();
    window.isDemoMode = () => Promise.resolve(false);
    window.toggleDemoMode = () => Promise.resolve(false);
    window.downloadModel = (id) => {{}};
    window.deleteModel = (id) => Promise.resolve();
    window.testTranscription = () => Promise.resolve('Test transcription successful.');
    window.checkForUpdates = () => Promise.resolve(JSON.stringify({{}}));
    window.getDownloadProgress = () => Promise.resolve(JSON.stringify({{"status": "idle"}}));
    window.registerHotkey = (m, k) => Promise.resolve(true);
    window.getCurrentHotkey = () => Promise.resolve('Ctrl+Shift+D');
    window.resetOnboarding = () => {{}};
    window.openLogFile = () => {{}};
    window.openConfigDir = () => {{}};
    window.getAppVersion = () => Promise.resolve('1.1.1');

    // -- Snippets/Replacements bindings --
    window.getTextReplacements = () => Promise.resolve(JSON.stringify({{
        "thx": "Thank you for your message. I appreciate your time and will get back to you shortly.",
        "addr": "123 Innovation Street, Suite 400, Munich 80331, Germany",
        "sig": "Best regards,\\nSilvio Lindstedt\\nSoftware Developer\\nWhisPaste"
    }}));
    window.setTextReplacements = (r) => Promise.resolve();

    // -- Profile bindings --
    window.getProfiles = () => Promise.resolve('[]');
    window.getActiveProfile = () => Promise.resolve('');
    window.saveProfile = (p) => Promise.resolve();
    window.switchProfile = (p) => Promise.resolve();
    window.deleteProfile = (p) => Promise.resolve();
    window.renameProfile = (o, n) => Promise.resolve();

    // -- LLM bindings --
    window.getLLMModels = () => Promise.resolve(JSON.stringify([
        {{"id": "qwen3.5-0.8b", "name": "Qwen 3.5 (0.8B)", "size": "533 MB", "downloaded": true, "isDefault": true}},
        {{"id": "smollm2", "name": "SmolLM2 (360M)", "size": "283 MB", "downloaded": false, "isDefault": false}}
    ]));
    window.downloadLLM = (id) => {{}};
    window.deleteLLM = (id) => Promise.resolve();
    window.getLLMDownloadProgress = () => Promise.resolve(JSON.stringify({{"status": "idle"}}));
    window.isLLMServerRunning = () => Promise.resolve(true);

    // -- Command palette --
    window.getCommandPaletteItems = () => Promise.resolve('[]');

    console.log('[MockBindings] All bindings injected for screenshot mode');
}})();
"""


# ── Playwright Screenshot Capture ──────────────────────────────────────────────
def capture_screenshots(html: str, lang: str, theme: str) -> list[str]:
    """Render HTML in Playwright and capture page screenshots."""
    from playwright.sync_api import sync_playwright

    suffix = f"_{lang}" if lang != "en" else ""
    output_files = []

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Write HTML to a temp file
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False, encoding="utf-8")
    tmp.write(html)
    tmp.close()
    tmp_path = tmp.name

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                viewport={"width": WIDTH, "height": HEIGHT},
                device_scale_factor=1,
                color_scheme=theme,
            )
            page = context.new_page()

            # Suppress console noise
            page.on("console", lambda msg: None)
            page.on("pageerror", lambda err: print(f"  ⚠ Page error: {err}"))

            file_url = f"file:///{tmp_path.replace(os.sep, '/')}"
            print(f"  Loading UI from {tmp_path}...")
            page.goto(file_url, wait_until="networkidle")

            # Wait for the UI to be ready (body.ready class)
            page.wait_for_selector("body.ready", timeout=10000)
            print("  ✓ UI initialized")

            # Take each screenshot
            for shot in SCREENSHOTS:
                pg = shot["page"]
                fname = shot["file"].replace(".png", f"{suffix}.png")
                wait_ms = shot["wait"]
                scroll_to = shot.get("scroll_to")

                print(f"  📸 Capturing {pg} → {fname}...")

                # Navigate to the page
                page.evaluate(f"switchPage('{pg}')")
                page.wait_for_timeout(wait_ms)

                # Scroll to specific section if requested
                if scroll_to:
                    page.evaluate(f"""
                        const el = document.getElementById('{scroll_to}');
                        if (el) el.scrollIntoView({{ behavior: 'instant', block: 'start' }});
                    """)
                    page.wait_for_timeout(500)

                # For analytics, wait for charts to render
                if pg == "analytics":
                    page.wait_for_timeout(1000)

                # Capture
                out_path = str(OUTPUT_DIR / fname)
                page.screenshot(path=out_path, type="png")
                output_files.append(out_path)
                print(f"    ✓ Saved ({WIDTH}×{HEIGHT})")

            browser.close()
    finally:
        os.unlink(tmp_path)

    return output_files


# ── Main ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Generate Microsoft Store screenshots")
    parser.add_argument("--lang", choices=["en", "de"], default="en", help="UI language")
    parser.add_argument("--theme", choices=["dark", "light"], default="dark", help="Color theme")
    parser.add_argument("--all", action="store_true", help="Generate EN + DE screenshots (dark)")
    args = parser.parse_args()

    combos = [("en", "dark"), ("de", "dark")] if args.all else [(args.lang, args.theme)]
    all_files = []

    for lang, theme in combos:
        print(f"\n{'='*60}")
        print(f"  Generating screenshots: lang={lang}, theme={theme}")
        print(f"{'='*60}")

        html = assemble_html(theme, lang)
        files = capture_screenshots(html, lang, theme)
        all_files.extend(files)

    print(f"\n{'='*60}")
    print(f"  ✅ Done! {len(all_files)} screenshots generated.")
    print(f"  📁 Output: {OUTPUT_DIR}")
    print(f"{'='*60}")
    for f in all_files:
        print(f"    • {os.path.basename(f)}")

    # Note about manual screenshots
    print(f"\n  ⚠ Manual screenshots still needed:")
    print(f"    • screenshot-01-dictation.png  (Hotkey in Outlook/Email)")
    print(f"    • screenshot-04-floating.png   (Floating Button on desktop)")


if __name__ == "__main__":
    main()
