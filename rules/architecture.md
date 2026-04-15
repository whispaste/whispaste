# WhisPaste Architecture

## Stack
- **Frontend + Logic**: Flutter/Dart (single codebase: Windows, macOS, Linux, iOS, Android)
- **Database**: SQLite via `drift` (cross-platform, type-safe)
- **AI Inference**: whisper.cpp (STT) + llama.cpp (LLM) as native subprocesses
- **State Management**: Riverpod (NOT setState in feature code)
- **System Integration**: Platform channels + native plugins

## Key Packages
| Purpose | Package |
|---------|---------|
| State | `flutter_riverpod` |
| SQLite | `drift` |
| Audio | `record` + platform channels |
| Clipboard | `super_clipboard` |
| Icons | `lucide_icons_flutter` + `font_awesome_flutter` |
| Crash | `sentry_flutter` |
| Window (desktop) | `window_manager` |
| Window effects | `flutter_acrylic` (Mica/Acrylic) |
| Tray | `tray_manager` |
| Hotkeys | `hotkey_manager` |
| Multi-window | `desktop_multi_window` |
| Audio effects | `flutter_soloud` |
| Autostart | `launch_at_startup` |

## Project Structure
```
lib/
├── main.dart              # Entry point
├── app.dart               # MaterialApp, routing, theme
├── core/
│   ├── theme/             # Design tokens, colors, ThemeData
│   ├── l10n/              # Translations (ARB files + generated)
│   ├── config/            # Settings provider, enums, secure key store
│   ├── data/              # Drift database definition
│   ├── logging/           # AppLogger, CrashReporter (Sentry)
│   ├── multi_window/      # Multi-window messaging
│   ├── recording/         # Recording state machine
│   └── app_info.dart      # Version constant (single source of truth)
├── features/
│   ├── about/
│   ├── analytics/
│   ├── feedback/
│   ├── history/
│   ├── onboarding/
│   ├── recording/
│   ├── replacements/
│   └── settings/
├── screens/               # Multi-window screens
├── widgets/               # Shared widget library
└── services/              # Business logic services
    ├── stt_service.dart
    ├── llm_service.dart
    ├── recording_orchestrator.dart
    ├── model_download_service.dart
    ├── hardware_info_service.dart
    ├── hotkey_service.dart
    ├── tray_service.dart
    └── ...
```

## State Management (Riverpod)
- Providers for ALL business logic — no `setState` in feature code
- Settings via `settingsProvider` → persisted in SQLite
- AI services expose state (e.g., `SttStatus`) + operations
- Use `ref.watch()` for reactive, `ref.read()` for one-shot

## Database (Drift)
- Tables defined in `lib/core/data/database.dart`
- Migrations: additive only, never destructive without migration path
- Config stored in SQLite key-value table (not JSON files)
- Sensitive keys (API keys): `FlutterSecureStorage` (platform-native)

## Native Subprocesses
- whisper.cpp: `whisper-server` subprocess managed by `SttService`
- llama.cpp: `llama-server` subprocess managed by `LlmService`
- Binary download: `ModelDownloadService` with SHA256 verification
- GPU detection: `HardwareInfoService` (nvidia-smi/WMI/IOKit/sysfs)

## Platform Channels
- Audio capture: WASAPI (Win), AVAudioEngine (macOS), ALSA/Pulse (Linux)
- Clipboard simulation: SendInput (Win), CGEventPost (macOS), xdotool (Linux)
