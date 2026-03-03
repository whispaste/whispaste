<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="Whispaste" width="140">
</p>

<h1 align="center">Whispaste</h1>

<p align="center">
  <b>Voice to text, pasted anywhere.</b><br>
  A lightweight, open-source Windows desktop tool that transcribes your speech<br>
  with OpenAI Whisper and pastes the result into any focused input field.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/silvio-l/whispaste?style=flat-square&color=00ADD8&label=download" alt="Latest Release"></a>&nbsp;
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows 10/11">&nbsp;
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT License">&nbsp;
  <img src="https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go 1.24+">
</p>

<p align="center">
  <a href="../../releases/latest"><b>📥 Download</b></a>&ensp;·&ensp;
  <a href="#-quick-start"><b>🚀 Quick Start</b></a>&ensp;·&ensp;
  <a href="#-configuration"><b>⚙️ Config</b></a>&ensp;·&ensp;
  <a href="#-api-costs"><b>💰 Costs</b></a>&ensp;·&ensp;
  <a href="#%EF%B8%8F-building-from-source"><b>🏗️ Build</b></a>&ensp;·&ensp;
  <a href="#-support"><b>❤️ Support</b></a>
</p>

<br>

## ✨ Features

| | | |
|---|---|---|
| 🎤 **Global Hotkey** | Press `Ctrl+Shift+V` from anywhere | Fully configurable |
| 🔄 **Two Modes** | Push-to-Talk or Toggle | Hold or press to start/stop |
| 📋 **Auto-Paste** | Text appears at your cursor | Clipboard + simulated Ctrl+V |
| 🌍 **Multi-Language** | Any language Whisper supports | Or auto-detect |
| 🖥️ **Visual Overlay** | Waveform + timer while recording | Non-intrusive, always on top |
| 🔔 **Audio Feedback** | Subtle sounds for each state | Start, stop, success, error |
| 🔑 **BYOK** | Bring Your Own API Key | No subscription needed |
| ⚡ **Lightweight** | Single ~8 MB portable `.exe` | No installer, no dependencies |
| 🔄 **Auto-Update** | SHA256-verified self-updater | Notifies via system tray |
| 🌐 **Localized** | English & German UI | Auto-detected from system |
| ♿ **Accessible** | Full keyboard navigation | Screen reader support |

<br>

## 📦 Quick Start

1. **Download** the latest `whispaste.exe` from [**Releases**](../../releases/latest)
2. **Run** — double-click the `.exe` (no installation needed)
3. **Configure** — enter your [OpenAI API key](https://platform.openai.com/api-keys) in the settings window
4. **Use** — press `Ctrl+Shift+V`, speak, release → text appears at your cursor!

<br>

## ⚙️ Configuration

Right-click the tray icon → **Settings** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| API Key | *(required)* | Your OpenAI API key |
| Hotkey | `Ctrl+Shift+V` | Global keyboard shortcut |
| Mode | Push-to-Talk | Hold hotkey or toggle on/off |
| Language | Auto-detect | Force a specific transcription language |
| Model | `whisper-1` | OpenAI Whisper model |
| Auto-Paste | On | Automatically paste after transcription |
| Sound Effects | On | Play audio feedback |
| Check Updates | On | Automatically check for new versions |

Config is stored in `%APPDATA%\Whispaste\config.json`.

<br>

## 💰 API Costs

Whispaste uses the OpenAI Whisper API, billed per audio minute at **~$0.006/min**.

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
| Power user | ~2 hrs/day | ~$22 |

> **Bottom line:** For most users, it's a few dollars per month — single dictations cost fractions of a cent.

<br>

## 🛡️ Privacy & Security

- **Your API key stays local** – stored only in your user profile directory
- **Audio is never saved** – recorded audio is sent directly to OpenAI's API and discarded
- **Secure updates** – auto-updater verifies SHA256 checksums before applying, HTTPS only, no silent updates
- **No telemetry** – zero analytics, tracking, or phone-home
- **Open source** – audit every line of code yourself

<br>

## 🏗️ Building from Source

### Prerequisites

- [Go 1.24+](https://go.dev/dl/)
- GCC for Windows ([MSYS2 MinGW-w64](https://www.msys2.org/) or [TDM-GCC](https://jmeubank.github.io/tdm-gcc/))

### Build

```powershell
# Clone
git clone https://github.com/silvio-l/whispaste.git
cd whispaste

# Build (debug)
.\build.ps1

# Build (release – smaller binary)
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
├── wav.go             # PCM → WAV encoder
├── paste.go           # Clipboard + SendInput (Ctrl+V)
├── hotkey.go          # Global hotkey (PTT + toggle)
├── overlay.go         # Recording overlay (Win32 GDI)
├── tray.go            # System tray icon + menu
├── ui.go              # Settings window (WebView2)
├── ui_settings.html   # Settings UI (HTML/CSS/JS)
├── config.go          # Configuration management
├── update.go          # Secure auto-updater (GitHub Releases)
├── logger.go          # File-based logging with rotation
├── l10n.go            # Localization (EN/DE)
├── sound.go           # Audio feedback
├── types.go           # Shared types and constants
├── build.ps1          # Build script
├── LICENSE            # MIT License
└── README.md          # This file
```

<br>

## ❤️ Support

Whispaste is free and open source. If you find it useful, consider supporting development:

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
 🎤 Hotkey        →  🔴 Record        →  📦 Encode        →  ☁️ Transcribe    →  📋 Paste
 RegisterHotKey      miniaudio/WASAPI     PCM → WAV            Whisper API         Clipboard +
 (global)            16 kHz mono          container             multipart POST      SendInput
```

The overlay uses Win32 GDI with `WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT` for a non-intrusive, always-visible recording indicator.
