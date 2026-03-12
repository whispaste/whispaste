<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="WhisPaste" width="140">
</p>

<h1 align="center">WhisPaste</h1>

<p align="center">
  <b>Voice to text, pasted anywhere.</b><br>
  Press a hotkey, speak, and your words appear wherever your cursor is.<br>
  Open-source speech-to-text for Windows — cloud or fully offline.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/whispaste/whispaste?style=flat-square&color=00ADD8&label=download" alt="Latest Release"></a>&nbsp;
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows 10/11">&nbsp;
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT License">&nbsp;
  <img src="https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go 1.24+">
</p>

<p align="center">
  <a href="../../releases/latest"><b>📥 Download Latest Release</b></a>&ensp;·&ensp;
  <a href="https://whispaste.de"><b>🌐 Website</b></a>&ensp;·&ensp;
  <a href="#-quick-start"><b>🚀 Quick Start</b></a>&ensp;·&ensp;
  <a href="#-configuration"><b>⚙️ Config</b></a>&ensp;·&ensp;
  <a href="#%EF%B8%8F-building-from-source"><b>🏗️ Build</b></a>&ensp;·&ensp;
  <a href="#-support"><b>❤️ Support</b></a>
</p>

<br>

## 🤔 What is WhisPaste?

WhisPaste is a Windows desktop app that turns your voice into text — instantly pasted wherever your cursor is. Press a hotkey, speak naturally, and your words appear in any application: emails, documents, chat, code editors, you name it.

It works with **OpenAI Whisper** for high-accuracy cloud transcription, or **fully offline** with local Whisper models — no API key, no internet, no data leaving your device. Smart Mode can optionally clean up your text, convert it to bullet points, formal emails, meeting notes, and more using AI post-processing.

Free, open source, and privacy-first. No telemetry, no tracking, no account required.

<br>

<br>

## 💡 How It Works

```
 🎤 Hotkey  →  🔴 Record  →  🎯 VAD  →  ☁️ Transcribe  →  🧠 Smart Mode  →  📋 Paste
```

1. **Press your hotkey** (`Ctrl+Shift+D` by default) — hold to talk or toggle on/off
2. **Speak naturally** — a small overlay shows a live waveform and timer while you record
3. **Text appears at your cursor** — transcribed, optionally post-processed, and auto-pasted

Voice Activity Detection strips silence before sending audio. Smart Mode can optionally clean up grammar, format as an email, create bullet points, translate, or apply a custom prompt — powered by GPT-4o-mini or a local LLM.

<br>

## ✨ Features

| | |
|---|---|
| 🎤 **Global Hotkey** | Press `Ctrl+Shift+D` from anywhere to start dictating. Fully configurable. |
| 🔄 **Push-to-Talk & Toggle** | Hold the hotkey while speaking, or press once to start and again to stop. |
| ☁️ **Cloud & Local Models** | Use OpenAI Whisper API or run offline with local Whisper models — no API key needed for local. |
| 🧪 **Local STT Compatibility Check** | Hardware/runtime preflight blocks unsupported devices before local downloads or onboarding finish, with detailed diagnostics in Settings and About. |
| 📋 **Auto-Paste** | Transcribed text is automatically pasted at your cursor. Smart terminal detection (Windows Terminal, WSL, mintty). |
| 🧠 **Smart Mode** | 13 AI post-processing presets: cleanup, email, bullets, formal, translate, meeting notes, and more. Custom prompts supported. |
| 🤖 **Local Smart Mode** | Run post-processing entirely offline with a local LLM (Qwen3.5-0.8B or SmolLM2-360M) — no cloud API needed. |
| 🎯 **Voice Activity Detection** | Automatic silence stripping improves accuracy and reduces API costs. Configurable sensitivity. |
| 🖥️ **Recording Overlay** | Pill-shaped overlay with live waveform, timer, pause, and cancel controls. Always on top, never steals focus. |
| 📜 **History & Dashboard** | Browse, search (full-text), tag, pin, archive, edit, merge, and re-copy past transcriptions. |
| 🗂️ **Projects & Tags** | Organize transcriptions into projects. Create, assign, and filter by color-coded tags with drag-and-drop. |
| 📊 **Analytics** | Track dictation counts, duration, model usage, API costs, and savings from local transcription. |
| 📤 **Export** | Export as TXT, Markdown, CSV, JSON, or DOCX — single entries or batch selections. |
| 🔊 **Audio Playback** | Re-listen to recorded audio directly from the dashboard. Compressed gzip storage. |
| 🏷️ **Auto-Tagging** | Automatically tag transcriptions using a local LLM based on your existing tags. |
| ✏️ **Snippets** | Define spoken trigger phrases that expand into links, signatures, and reusable text before pasting. |
| ⌨️ **Command Palette** | Press `Ctrl+K` to access actions, search transcriptions, and navigate quickly. |
| 💬 **Floating Button** | Optional always-visible desktop button for one-click recording without using the hotkey. |
| 🌍 **Multi-Language** | Transcribe in any language Whisper supports. English & German UI, auto-detected from system. |
| 🔔 **Audio Feedback** | Subtle sounds for start, stop, success, and error states. Adjustable volume. |
| 🔄 **Auto-Update** | SHA256-verified self-updater checks for new versions. HTTPS only. |
| ⚡ **Portable & Installer** | Run portable (just the exe) or install with Start Menu integration and autostart. |
| 🎓 **Onboarding** | First-run setup wizard guides through API key or local model configuration. |

<br>

## 📦 Quick Start

### Installer (recommended)

1. **Download** `WhisPaste-x.x.x-Setup.exe` from the latest [**Release**](../../releases/latest)
2. **Run the installer** — follow the setup wizard
3. **Launch** from Start Menu → WhisPaste, or enable "Start with Windows" during installation
4. **Set up transcription** — enter your [OpenAI API key](https://platform.openai.com/api-keys) in Settings, or enable local models

### Portable

1. **Download** `whispaste.exe` from the latest [**Release**](../../releases/latest)
2. **Run** — double-click `whispaste.exe`. It will appear in your system tray.
3. **Set up transcription** — either:
   - Enter your [OpenAI API key](https://platform.openai.com/api-keys) in Settings → API Key, or
   - Enable local models in Settings → Local STT and download a model (no API key needed)
4. **Use** — press `Ctrl+Shift+D`, speak, release → text appears at your cursor!

> **Note:** Local STT uses [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — the server binary and models are downloaded automatically on first use. WhisPaste now runs a compatibility preflight first and blocks unsupported hardware/runtime setups before local models are enabled.

### MSIX Package

An `.msix` package is also available in each release for users who prefer managed installation via Windows.

<br>

## ⚙️ Configuration

Right-click the tray icon → **Settings** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| **API Key** | *(required for cloud)* | Your OpenAI API key |
| **Hotkey** | `Ctrl+Shift+D` | Global keyboard shortcut |
| **Mode** | Push-to-Talk | Hold hotkey or toggle on/off |
| **Language** | Auto-detect | Force a specific transcription language |
| **Model** | `whisper-1` | OpenAI Whisper model for cloud transcription |
| **Local STT** | Off | Use local Whisper models instead of the API |
| **Local Model** | *(none)* | Download and select a local model (base, small, or medium) |
| **Local STT Compatibility Check** | Automatic | Scans CPU features, RAM, disk, and whisper-server runtime readiness before local downloads or activation |
| **Input Device** | *(system default)* | Select a specific microphone |
| **Input Gain** | 1.0 | Adjust microphone input level |
| **Prompt** | *(empty)* | System prompt sent with each Whisper request |
| **Max Recording** | 120 s | Maximum recording duration (0 = unlimited) |
| **Auto-Paste** | On | Automatically paste after transcription |
| **Sound Effects** | On | Play audio feedback |
| **Sound Volume** | 100% | Volume for start/stop/success/error sounds |
| **Smart Mode** | Off | AI post-processing (cleanup, email, bullets, formal, translate, custom) |
| **Overlay Position** | Top Center | Where the overlay appears during recording |
| **UI Language** | *(system)* | Interface language (English / German) |
| **Theme** | System | Color scheme: light, dark, or match OS |
| **Autostart** | Off | Launch WhisPaste on Windows login |
| **Check Updates** | On | Automatically check for new versions |
| **VAD** | Off | Voice Activity Detection — strip silence before transcription |
| **Floating Button** | Off | Show a floating record button on the desktop |
| **Snippets** | *(none)* | Spoken trigger phrases that expand into custom text before pasting |
| **Smart Provider** | OpenAI | Smart Mode engine: OpenAI (GPT), Local (SmolLM2), or Auto |
| **History Limit** | 500 | Maximum transcriptions stored (pinned/archived excluded) |
| **Auto-Cleanup** | Off | Automatically remove old transcriptions by age or count |

Config is stored in `%APPDATA%\Whispaste\config.json`. The API endpoint can be customized by editing this file directly.

<br>

## 💰 API Costs

When using the OpenAI Whisper API, transcription is billed per audio minute at **~$0.006/min**.

| Usage | Example | Cost |
|-------|---------|------|
| Short sentence (10–15 s) | Quick note | ~$0.001 |
| Half a minute | Longer thought | ~$0.003 |
| One full minute | Detailed dictation | ~$0.006 |

**Typical monthly cost estimates:**

| Profile | Daily usage | Monthly cost |
|---------|-------------|--------------|
| Occasional | ~5 min/day | ~$1 |
| Regular | ~20 min/day | ~$4 |
| Heavy | ~30 min/day | ~$6 |

> **Tip:** Using local models is completely free — no API key or internet connection needed. The Analytics page in the dashboard shows your API costs and savings from local transcription.

<br>

## 🛡️ Privacy & Security

- **Your API key stays local** – stored only in your user profile directory, never transmitted to WhisPaste
- **Direct API connection** – audio is sent directly from your device to OpenAI; WhisPaste never stores, processes, or relays your recordings. See [OpenAI's privacy policy](https://openai.com/policies/privacy-policy/)
- **Local models** – when using local STT, audio never leaves your device
- **Secure updates** – auto-updater verifies SHA256 checksums before applying, HTTPS only
- **No telemetry** – zero analytics, tracking, or phone-home
- **Open source** – audit every line of code yourself

<br>

## 🏗️ Building from Source

### Prerequisites

- [Go 1.24+](https://go.dev/dl/)
- GCC for Windows ([MSYS2 MinGW-w64](https://www.msys2.org/) or [TDM-GCC](https://jmeubank.github.io/tdm-gcc/))
- Local STT uses whisper.cpp (downloaded at runtime — no bundled DLLs required)

### Build

```powershell
# Clone
git clone https://github.com/whispaste/whispaste.git
cd whispaste

# Build (debug)
.\build.ps1

# Build (release – smaller binary, hidden console)
.\build.ps1 -Release
```

### Manual Build

```powershell
$env:CGO_ENABLED = "1"
go build -ldflags="-s -w -H windowsgui" -o whispaste.exe .
```

<br>

## 📁 Project Structure

```
whispaste/
├── internal/                ← Self-contained Go packages
│   ├── audiocache/          #   Audio file caching with gzip compression
│   ├── export/              #   Export flows (TXT, MD, CSV, JSON, DOCX)
│   ├── i18n/                #   Localization (EN/DE translations)
│   ├── models/              #   Local model management (download, SHA256 verify)
│   ├── preflight/           #   Local STT hardware/runtime compatibility checks
│   ├── stats/               #   Usage statistics
│   └── wav/                 #   PCM → WAV encoder
├── scripts/                 ← Build & review scripts
│   ├── build.ps1            #   Production build script
│   └── review.mjs           #   Code review script (Node.js)
├── resources/               ← Embedded assets (sounds, icons, debug logos)
├── ui_main/                 ← Dashboard UI (HTML/CSS/JS, modular)
│   ├── template.html        #   Page structure and layout
│   ├── pages/               #   Page partials (01-history through 06-about)
│   ├── components/          #   Reusable UI components
│   ├── styles/              #   CSS modules (variables, layout, pages)
│   └── scripts/             #   JS modules (translations, utils, pages)
├── installer/               ← NSIS installer configuration
│   └── whispaste.nsi        #   Windows Setup installer script
├── msix/                    ← MSIX packaging (Microsoft Store)
├── website/                 ← Landing page (Astro)
├── winres/                  ← Windows resource embedding
├── main.go                  # Entry point, state machine
├── main_state.go            # App state management (recording, processing)
├── main_handlers.go         # State transition handlers
├── audio.go                 # Microphone recording (miniaudio/WASAPI)
├── api.go                   # OpenAI Whisper API client
├── stt.go                   # Local STT subprocess (whisper.cpp HTTP server)
├── stt_download.go          # STT server + model download with SHA256 verify
├── offline.go               # Local Whisper transcription client
├── preflight.go             # Local STT compatibility bridge + UI payloads
├── paste.go                 # Clipboard + SendInput (Ctrl+V)
├── hotkey.go                # Global hotkey (PTT + toggle)
├── overlay.go               # Recording overlay (GDI+ with per-pixel alpha)
├── overlay_events.go        # Overlay event handling
├── overlay_gdi.go           # Overlay GDI+ rendering
├── floating.go              # Floating desktop record button
├── vad.go                   # Voice Activity Detection (silence stripping)
├── notification.go          # Windows toast notification support
├── tray.go                  # System tray icon, menu, history submenu
├── ui.go                    # Window management helpers
├── ui_main.go               # Main dashboard window (WebView2 bindings)
├── ui_bindings_settings.go  # Settings/model WebView bindings
├── ui_bindings_history.go   # History WebView bindings
├── ui_bindings_smart.go     # Smart mode WebView bindings
├── ui_bindings_ui.go        # UI utility WebView bindings
├── ui_log.go                # Log viewer window (WebView2)
├── ui_components.go         # Reusable Go UI component generators
├── config.go                # Configuration management
├── update.go                # Secure auto-updater (GitHub Releases)
├── logger.go                # File-based logging with rotation
├── l10n_bridge.go           # T() bridge to internal/i18n
├── sound.go                 # Audio feedback with volume control
├── postprocess.go           # Smart Mode (GPT-4o-mini post-processing)
├── history.go               # Transcription history CRUD
├── history_db.go            # SQLite database layer (FTS5 full-text search)
├── history_search.go        # Full-text search and tag queries
├── history_analytics.go     # Usage statistics and analytics
├── history_projects.go      # Project management
├── autotag.go               # Auto-tagging via local LLM
├── autostart.go             # Windows login autostart
├── windowdetect.go          # Active window detection (Win32)
├── llm.go                   # Local LLM integration (llama-server)
├── llm_download.go          # LLM model download manager
├── types.go                 # Shared types and constants
├── LICENSE                  # MIT License
└── README.md                # This file
```

<br>

## ❤️ Support

WhisPaste is free and open source. If you find it useful, consider supporting development:

<p align="center">
  <a href="https://github.com/sponsors/silvio-l"><img src="https://img.shields.io/badge/Sponsor_on_GitHub-❤-ea4aaa?style=for-the-badge&logo=github" alt="Sponsor silvio-l"></a>&ensp;
  <a href="https://ko-fi.com/silviol"><img src="https://img.shields.io/badge/Buy_a_Coffee-☕-ff5e5b?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

<br>

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

<br>

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

<p align="center">
  <sub>© 2025–2026 <a href="https://github.com/silvio-l">Silvio Lindstedt</a></sub>
</p>
