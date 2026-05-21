<p align="center">
  <img src="resources/app-icon%20mit%20bg.png" alt="WhisPaste" width="128">
</p>

<h1 align="center">WhisPaste</h1>

<p align="center">
  <strong>Press. Speak. Done.</strong><br>
  Stop typing — speak, and your words land at the cursor in any app.<br>
  Offline by default · Windows · macOS · Linux · MIT-licensed.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/whispaste/whispaste?style=flat-square&color=06b6d4&label=download" alt="Download"></a>&nbsp;
  <img src="https://img.shields.io/badge/Windows-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows">&nbsp;
  <img src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS">&nbsp;
  <img src="https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux">&nbsp;
  <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">&nbsp;
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT license">
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

1. **Press your hotkey** — `Ctrl+Shift+D` by default, push-to-talk or toggle mode
2. **Speak naturally** — a minimal overlay shows a live waveform while the mic is open
3. **Done** — the transcript is pasted wherever your cursor sits

Works in emails, chat apps, code editors, browsers, terminals — anywhere you would otherwise type.

## Key Features

**Core** — Global hotkey · Push-to-talk & toggle · Auto-paste into any app · Recording overlay with waveform · Floating record button

**Transcription** — Offline by default: local Whisper models via [whisper.cpp](https://github.com/ggml-org/whisper.cpp), no API key required · Optional cloud providers (OpenAI, Deepgram) when you want them · [99 languages](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py)

**Productivity** — Voice Snippets (spoken triggers → text expansion) · Audio feedback sounds

**History** — Tags · Full-text search · Pin, archive, merge, edit · Analytics dashboard · Export (TXT, MD, CSV, JSON, DOCX)

**System** — Auto-update with SHA256 verification · Light/dark/system theme · EN/DE interface · Autostart · System tray

## Development

**Prerequisites:** [Flutter](https://flutter.dev/docs/get-started/install) 3.x · Windows 10 (64-bit), macOS 10.15+, or a recent Linux distro

```bash
git clone https://github.com/whispaste/whispaste.git
cd whispaste
flutter pub get
flutter run -d windows   # or: flutter run -d macos / flutter run -d linux
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
├── macos/              # macOS platform runner
├── linux/              # Linux platform runner
├── website/            # Astro-based project website
└── supabase/           # Database migrations (PostgREST + RLS only, no Edge Functions)
```

### Commands

```bash
flutter analyze --fatal-infos          # Lint + static analysis
flutter test                           # Run all tests (excludes goldens)
flutter test --tags=golden             # Run widget/screenshot tests
flutter build windows --release --no-tree-shake-icons
flutter build macos   --release --no-tree-shake-icons \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

## Privacy

- **Local mode** — audio never leaves your device
- **Cloud mode** — audio goes directly to your selected provider, not through WhisPaste servers
- **No tracking**, no account required — optional crash reporting can be turned off
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
