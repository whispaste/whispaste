# 🎙️ Whispaste

**Voice to text, pasted anywhere.** A lightweight, open-source Windows desktop tool that transcribes your speech with OpenAI Whisper and pastes the result into any focused input field.

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-blue" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/size-~8MB-orange" alt="~8MB">
  <img src="https://img.shields.io/badge/Go-1.24+-00ADD8?logo=go" alt="Go 1.24+">
</p>

---

## ✨ Features

- **🎤 Global Hotkey** – Press `Ctrl+Shift+V` (configurable) to start recording from anywhere
- **🔄 Two Modes** – Push-to-Talk (hold hotkey) or Toggle (press to start/stop)
- **📋 Auto-Paste** – Transcribed text is automatically pasted into the active input field
- **🌍 Multi-Language** – Transcribe in any language supported by OpenAI Whisper
- **🖥️ Visual Overlay** – Animated overlay shows recording status with waveform and timer
- **🔔 Audio Feedback** – Subtle sounds for start/stop/success/error
- **🔑 BYOK** – Bring Your Own Key: uses your OpenAI API key, no subscription
- **⚡ Lightweight** – Single ~8MB portable `.exe`, no installer needed
- **🌐 UI Languages** – English and German interface (auto-detected)
- **♿ Accessible** – Full keyboard navigation and screen reader support in settings

## 📦 Quick Start

1. **Download** `whispaste.exe` from [Releases](../../releases)
2. **Run** – double-click the `.exe` (no installation needed)
3. **Configure** – enter your [OpenAI API key](https://platform.openai.com/api-keys) in the settings window
4. **Use** – press `Ctrl+Shift+V`, speak, release → text appears at your cursor!

## 🔧 Configuration

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

Config is stored in `%APPDATA%\Whispaste\config.json`.

## 🛡️ Privacy & Security

- **Your API key stays local** – stored only in your user profile directory
- **Audio is never saved** – recorded audio is sent directly to OpenAI's API and discarded
- **No telemetry** – zero analytics, tracking, or phone-home
- **Open source** – audit every line of code yourself

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
├── l10n.go            # Localization (EN/DE)
├── sound.go           # Audio feedback
├── types.go           # Shared types and constants
├── build.ps1          # Build script
├── LICENSE            # MIT License
└── README.md          # This file
```

## ❤️ Support

Whispaste is free and open source. If you find it useful, consider supporting its development:

<a href="https://github.com/sponsors/silvio-l"><img src="https://img.shields.io/badge/Sponsor-❤-ea4aaa?logo=github" alt="Sponsor silvio-l"></a>

- [💜 GitHub Sponsors](https://github.com/sponsors/silvio-l)
- [☕ Ko-fi](https://ko-fi.com/silviol)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

MIT License – see [LICENSE](LICENSE) for details.

© 2025 [Silvio Lindstedt](https://github.com/silvio-l)

## 💡 How It Works

1. **Hotkey** → Windows `RegisterHotKey` API captures your shortcut globally
2. **Recording** → miniaudio (WASAPI backend) captures 16kHz mono PCM audio
3. **Encoding** → PCM data is wrapped in a WAV container
4. **Transcription** → WAV is sent to OpenAI's `whisper-1` API via multipart POST
5. **Pasting** → Text is placed on the clipboard, then `Ctrl+V` is simulated via `SendInput`

The overlay window uses Win32 GDI with `WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT` for a non-intrusive, always-visible indicator.
