<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="WhisPaste" width="128">
</p>

<h1 align="center">WhisPaste</h1>

<p align="center">
  <strong>Press. Speak. Done.</strong><br>
  Voice to text, pasted right where your cursor is — in any app.<br>
  Cloud or fully offline. Free & open source.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/whispaste/whispaste?style=flat-square&color=06b6d4&label=download" alt="Download"></a>&nbsp;
  <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">&nbsp;
  <img src="https://img.shields.io/badge/MIT-22c55e?style=flat-square&label=license" alt="MIT">
</p>

<p align="center">
  <a href="https://whispaste.de"><b>🌐 Website</b></a>&ensp;·&ensp;
  <a href="../../releases/latest"><b>📦 Releases</b></a>&ensp;·&ensp;
  <a href="#development"><b>🏗️ Build</b></a>
</p>

---

## How It Works

```
Hotkey → Speak → Text appears at your cursor
```

1. **Press your hotkey** — `Ctrl+Shift+V` by default, hold-to-talk or toggle mode
2. **Speak naturally** — a minimal overlay shows a live waveform while you record
3. **Done** — transcribed text is pasted wherever your cursor sits

Works in emails, chat apps, code editors, browsers, terminals — everywhere.

## Key Features

**Core** — Global hotkey · Push-to-talk & toggle · Auto-paste into any app · Voice Activity Detection · Recording overlay with waveform · Floating record button

**Transcription** — Cloud providers (OpenAI, Groq, Deepgram) or local Whisper models via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — fully offline, no API key needed for local mode · [99 languages](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py)

**Post-Processing** — 13 AI presets: grammar cleanup, formal email, bullet points, meeting notes, translation, and more · Custom prompts · Runs locally or via cloud APIs (OpenAI, Anthropic, Gemini, Groq)

**Productivity** — Voice shortcuts (spoken triggers → text expansion) · Command palette (`Ctrl+K`) · Audio feedback sounds

**History** — Full-text search · Projects & color-coded tags · Auto-tagging via LLM · Pin, archive, merge, edit · Analytics dashboard · Export (TXT, MD, CSV, JSON, DOCX) · Audio playback · Voice notes

**System** — Auto-update with SHA256 verification · Light/dark/system theme · EN/DE interface · Autostart · System tray

## Development

**Prerequisites:** [Flutter](https://flutter.dev/docs/get-started/install) 3.x

```bash
git clone https://github.com/whispaste/whispaste.git
cd whispaste
flutter pub get
flutter run -d windows
```

### Project Structure

```
├── lib/                # Dart source code
│   ├── core/           # Theme, config, l10n, platform
│   ├── features/       # Feature modules (history, settings, recording, etc.)
│   ├── services/       # App services (audio, hotkey, tray, clipboard, etc.)
│   └── widgets/        # Shared widget library
├── test/               # Widget & unit tests
├── assets/             # Icons, fonts, sounds
├── windows/            # Windows platform runner
├── website/            # Astro-based project website
└── supabase/           # Edge Functions & migrations
```

### Commands

```bash
flutter analyze          # Lint + static analysis
flutter test             # Run all tests
flutter build windows    # Build for Windows
```

## Privacy

- **Local mode** — audio never leaves your device
- **Cloud mode** — audio goes directly to your selected provider, not through WhisPaste servers
- **No telemetry**, no tracking, no account required
- **Open source** — audit every line

## Support

<p align="center">
  <a href="https://github.com/sponsors/silvio-l"><img src="https://img.shields.io/badge/Sponsor-❤-ea4aaa?style=for-the-badge&logo=github" alt="Sponsor"></a>&ensp;
  <a href="https://ko-fi.com/silviol"><img src="https://img.shields.io/badge/Ko--fi-☕-ff5e5b?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

Contributions welcome — fork, branch, PR. Licensed under [MIT](LICENSE).

<p align="center">
  <sub>Made by <a href="https://github.com/silvio-l">Silvio Lindstedt</a></sub>
</p>
