<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="WhisPaste" width="128">
</p>

<h1 align="center">WhisPaste</h1>

<p align="center">
  <strong>Press. Speak. Done.</strong><br>
  Voice to text, pasted right where your cursor is — in any Windows app.<br>
  Cloud or fully offline. Free & open source.
</p>

<p align="center">
  <a href="../../releases/latest/download/WhisPaste-Setup.exe"><img src="https://img.shields.io/github/v/release/whispaste/whispaste?style=flat-square&color=06b6d4&label=download" alt="Download"></a>&nbsp;
  <img src="https://img.shields.io/badge/Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows 10/11">&nbsp;
  <img src="https://img.shields.io/badge/MIT-22c55e?style=flat-square&label=license" alt="MIT">&nbsp;
  <img src="https://img.shields.io/badge/Go%201.24+-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go">
</p>

<p align="center">
  <a href="../../releases/latest/download/WhisPaste-Setup.exe"><b>📥 Download</b></a>&ensp;·&ensp;
  <a href="https://whispaste.de"><b>🌐 Website</b></a>&ensp;·&ensp;
  <a href="../../releases/latest"><b>📦 All Assets</b></a>&ensp;·&ensp;
  <a href="#building-from-source"><b>🏗️ Build</b></a>
</p>

---

## How It Works

```
Hotkey → Speak → Text appears at your cursor
```

1. **Press your hotkey** — `Ctrl+Shift+D` by default, hold-to-talk or toggle mode
2. **Speak naturally** — a minimal overlay shows a live waveform while you record
3. **Done** — transcribed text is pasted wherever your cursor sits

Works in emails, chat apps, code editors, browsers, terminals — everywhere.

## Key Features

**Core** — Global hotkey · Push-to-talk & toggle · Auto-paste into any app · Voice Activity Detection · Recording overlay with waveform

**Transcription** — OpenAI Whisper API (cloud) or local Whisper models via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — fully offline, no API key needed · [99 languages](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py) · Hardware compatibility preflight

**Smart Mode** — 13 AI post-processing presets: grammar cleanup, formal email, bullet points, meeting notes, translation, and more · Custom prompts · Runs locally (Qwen3.5) or via OpenAI

**Productivity** — Snippets (spoken triggers → text expansion) · Command palette (`Ctrl+K`) · Floating record button · Audio feedback

**History** — Full-text search · Projects & color-coded tags · Auto-tagging via LLM · Pin, archive, merge, edit · Analytics dashboard · Export (TXT, MD, CSV, JSON, DOCX) · Audio playback

**System** — Portable or installer · Auto-update with SHA256 verification · Light/dark/system theme · EN/DE interface · Autostart

## Quick Start

1. **Download** [WhisPaste-Setup.exe](../../releases/latest/download/WhisPaste-Setup.exe) and run the installer
2. **Set up transcription** — enter an [OpenAI API key](https://platform.openai.com/api-keys), or enable local models (no key needed)
3. **Press `Ctrl+Shift+D`**, speak, release — text appears at your cursor

> A portable `whispaste.exe` and `.msix` package are also available on the [releases page](../../releases/latest).

## Privacy

- **Local mode** — audio never leaves your device
- **Cloud mode** — audio goes directly to OpenAI, not through WhisPaste servers
- **No telemetry**, no tracking, no account required
- **Open source** — audit every line

## Building from Source

```powershell
git clone https://github.com/whispaste/whispaste.git
cd whispaste
.\scripts\build.ps1 -Release   # requires Go 1.24+ and GCC (MSYS2 or TDM-GCC)
```

### Build integrated whisper-server assets

WhisPaste can also publish its own `whisper-server` release assets from this same repository for:

- `whisper-server-cpu-x64.zip`
- `whisper-server-cuda12-x64.zip`
- `whisper-server-vulkan-x64.zip`

The pinned upstream source ref lives in `scripts/whispercpp-ref.txt`.

```powershell
# CPU
$cpu = .\scripts\build-whisper-server.ps1 -Backend cpu

# Vulkan (auto-detects latest SDK under C:\VulkanSDK or uses VULKAN_SDK)
$vulkan = .\scripts\build-whisper-server.ps1 -Backend vulkan -VulkanSDKRoot C:\VulkanSDK

# Package an already-built binary into the release ZIP format
.\scripts\package-whisper-server.ps1 -Backend vulkan -ExecutablePath $vulkan.ExecutablePath
```

<details>
<summary>Manual build</summary>

```powershell
$env:CGO_ENABLED = "1"
go build -ldflags="-s -w -H windowsgui" -o whispaste.exe .
```
</details>

## Support

<p align="center">
  <a href="https://github.com/sponsors/silvio-l"><img src="https://img.shields.io/badge/Sponsor-❤-ea4aaa?style=for-the-badge&logo=github" alt="Sponsor"></a>&ensp;
  <a href="https://ko-fi.com/silviol"><img src="https://img.shields.io/badge/Ko--fi-☕-ff5e5b?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

Contributions welcome — fork, branch, PR. Licensed under [MIT](LICENSE).

<p align="center">
  <sub>© 2025–2026 <a href="https://github.com/silvio-l">Silvio Lindstedt</a></sub>
</p>
