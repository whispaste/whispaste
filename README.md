<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="WhisPaste" width="140">
</p>

<h1 align="center">WhisPaste</h1>

<p align="center">
  <b>Voice to text, pasted anywhere.</b><br>
  An open-source Windows desktop tool that transcribes your speech<br>
  and pastes the result into any focused input field — using OpenAI Whisper or local models.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/whispaste/whispaste?style=flat-square&color=00ADD8&label=download" alt="Latest Release"></a>&nbsp;
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows 10/11">&nbsp;
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT License">&nbsp;
  <img src="https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go 1.24+">
</p>

<p align="center">
  <a href="../../releases/latest"><b>📥 Download</b></a>&ensp;·&ensp;
  <a href="https://whispaste.github.io/whispaste/"><b>🌐 Website</b></a>&ensp;·&ensp;
  <a href="#-quick-start"><b>🚀 Quick Start</b></a>&ensp;·&ensp;
  <a href="#-configuration"><b>⚙️ Config</b></a>&ensp;·&ensp;
  <a href="#-api-costs"><b>💰 Costs</b></a>&ensp;·&ensp;
  <a href="#%EF%B8%8F-building-from-source"><b>🏗️ Build</b></a>&ensp;·&ensp;
  <a href="#-support"><b>❤️ Support</b></a>
</p>

<br>

## ✨ Features

| | |
|---|---|
| 🎤 **Global Hotkey** | Press `Ctrl+Shift+V` from anywhere to start dictating. Fully configurable. |
| 🔄 **Push-to-Talk & Toggle** | Hold the hotkey while speaking, or press once to start and again to stop. |
| ☁️ **Cloud & Local Models** | Use OpenAI Whisper API or run offline with local Whisper models (base, small) — no API key needed for local. |
| 📋 **Auto-Paste** | Transcribed text is automatically pasted at your cursor via clipboard + simulated Ctrl+V. |
| 🧠 **Smart Mode** | Optional AI post-processing via GPT-4o-mini: clean up text, convert to email, bullet points, formal tone, translate, or use a custom prompt. |
| 🌍 **Multi-Language** | Transcribe in any language Whisper supports, or let it auto-detect. |
| 🖥️ **Recording Overlay** | A small overlay with live waveform, timer, and confirm/pause controls appears during recording. Draggable, always on top. |
| 📜 **History & Dashboard** | Browse, search, tag, pin, edit, and re-copy past transcriptions. Up to 500 entries, accessible from the tray or dashboard. |
| 📊 **Analytics** | Track transcription counts, duration distribution, model usage, API costs, and savings from using local models. |
| ✏️ **Text Editing** | Edit transcription text directly in the dashboard after dictation. |
| 🔔 **Audio Feedback** | Subtle sounds for start, stop, success, and error states. Adjustable volume. |
| 🔄 **Auto-Update** | SHA256-verified self-updater checks for new versions automatically. |
| 🌐 **Localized** | English & German UI, auto-detected from your system language. |
| ⚡ **Portable & Installer** | Run portable (just extract and run) or install via the Windows Setup installer with Start Menu integration. |

<br>

## 📦 Quick Start

### Installer (recommended)

1. **Download** `WhisPaste-x.x.x-Setup.exe` from the latest [**Release**](../../releases/latest)
2. **Run the installer** — follow the setup wizard
3. **Launch** from Start Menu → WhisPaste, or enable "Start with Windows" during installation
4. **Set up transcription** — enter your [OpenAI API key](https://platform.openai.com/api-keys) in Settings, or enable local models

### Portable

1. **Download** all files from the latest [**Release**](../../releases/latest):
   - `whispaste.exe` — the application
   - `onnxruntime.dll` — required for local speech recognition
   - `sherpa-onnx-c-api.dll` — required for local speech recognition
   - `sherpa-onnx-cxx-api.dll` — required for local speech recognition
2. **Place all files in the same folder** — the DLLs must be next to `whispaste.exe`
3. **Run** — double-click `whispaste.exe`. It will appear in your system tray.
4. **Set up transcription** — either:
   - Enter your [OpenAI API key](https://platform.openai.com/api-keys) in Settings → API Key, or
   - Enable local models in Settings → Local STT and download a model (no API key needed)
5. **Use** — press `Ctrl+Shift+V`, speak, release → text appears at your cursor!

> **Note:** If you don't need local models, the DLL files are optional — the app works with just the `.exe` and an OpenAI API key.

### MSIX Package

An `.msix` package is also available in each release for users who prefer managed installation via Windows.

<br>

## ⚙️ Configuration

Right-click the tray icon → **Settings** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| **API Key** | *(required for cloud)* | Your OpenAI API key |
| **Hotkey** | `Ctrl+Shift+V` | Global keyboard shortcut |
| **Mode** | Push-to-Talk | Hold hotkey or toggle on/off |
| **Language** | Auto-detect | Force a specific transcription language |
| **Model** | `whisper-1` | OpenAI Whisper model for cloud transcription |
| **Local STT** | Off | Use local Whisper models instead of the API |
| **Local Model** | *(none)* | Download and select a local model (base or small) |
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

## 🔄 Auto-Update

WhisPaste includes a secure self-updater that keeps the app current without manual downloads.

- **How it works** – on startup and periodically, WhisPaste queries the [GitHub Releases API](../../releases/latest) for newer versions. If one is found, it downloads the new binary alongside a SHA256 checksum file, verifies integrity, and replaces the executable.
- **Rate limiting** – at most one check per hour (`minCheckInterval`). Manual checks from Settings pass `force=true` to bypass the cooldown.
- **MSIX / Store package** – auto-update is automatically disabled when running as an MSIX package (detected via `GetCurrentPackageFullName`). Store users receive updates through the Microsoft Store instead.
- **HTTPS only** – all API calls and downloads use HTTPS exclusively.
- **Configuration** – controlled by the `check_updates` setting in `config.json` (default: `true`). Toggle it in Settings → "Check Updates".
- **Testing** – the `Updater` struct exposes an overridable `releasesURL` field, allowing tests to swap in an `httptest.NewServer` and verify update logic without hitting GitHub. See `update_test.go` for examples.

<br>

## 🏗️ Building from Source

### Prerequisites

- [Go 1.24+](https://go.dev/dl/)
- GCC for Windows ([MSYS2 MinGW-w64](https://www.msys2.org/) or [TDM-GCC](https://jmeubank.github.io/tdm-gcc/))
- The runtime DLLs (`onnxruntime.dll`, `sherpa-onnx-c-api.dll`, `sherpa-onnx-cxx-api.dll`) must be in the working directory for local model support

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
├── main.go            # Entry point, state machine
├── audio.go           # Microphone recording (miniaudio/WASAPI)
├── api.go             # OpenAI Whisper API client
├── offline.go         # Local Whisper transcription (sherpa-onnx)
├── models.go          # Local model management (download, paths)
├── wav.go             # PCM → WAV encoder
├── paste.go           # Clipboard + SendInput (Ctrl+V)
├── hotkey.go          # Global hotkey (PTT + toggle)
├── overlay.go         # Recording overlay (GDI+ with per-pixel alpha)
├── tray.go            # System tray icon, menu, history submenu
├── ui.go              # Window management helpers
├── ui_main.go         # Main dashboard window (WebView2 bindings)
├── ui_main/           # Dashboard UI (HTML/CSS/JS, modular)
│   ├── template.html  #   Page structure and layout
│   ├── styles/        #   CSS modules (variables, layout, pages)
│   └── scripts/       #   JS modules (translations, utils, pages)
├── config.go          # Configuration management
├── update.go          # Secure auto-updater (GitHub Releases)
├── logger.go          # File-based logging with rotation
├── l10n.go            # Localization (EN/DE)
├── sound.go           # Audio feedback with volume control
├── postprocess.go     # Smart Mode (GPT-4o-mini post-processing)
├── history.go         # Transcription history with model/cost tracking
├── history_db.go      # SQLite database layer (FTS5 full-text search)
├── stats.go           # Usage statistics
├── autostart.go       # Windows login autostart
├── windowdetect.go    # Active window detection (Win32)
├── llm.go             # Local LLM integration (llama-server)
├── llm_download.go    # LLM model download manager
├── export.go          # Export flows (TXT, MD, DOCX)
├── types.go           # Shared types and constants
├── build.ps1          # Build script
├── installer/         # NSIS installer configuration
│   └── whispaste.nsi  #   Windows Setup installer script
├── msix/              # MSIX packaging (Microsoft Store)
├── website/           # Landing page (Astro)
├── LICENSE            # MIT License
└── README.md          # This file
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
  <sub>© 2025 <a href="https://github.com/silvio-l">Silvio Lindstedt</a></sub>
</p>

<br>

## 💡 How It Works

```
 🎤 Hotkey        →  🔴 Record        →  📦 Encode        →  ☁️ Transcribe    →  🧠 Smart Mode   →  📋 Paste
 RegisterHotKey      miniaudio/WASAPI     PCM → WAV            Whisper API or      GPT-4o-mini        Clipboard +
 (global)            16 kHz mono          container             local Whisper       (optional)         SendInput
```

The recording overlay uses GDI+ with `UpdateLayeredWindow` for per-pixel alpha compositing, smooth waveform animation, and interactive controls.
