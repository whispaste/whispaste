# Architecture

WhisPaste is a Flutter desktop app (macOS, Windows, Linux) with platform runners written in Swift, C++ and C. It records speech on a global hotkey, transcribes it on the device or in the cloud, post-processes the text and pastes it into the app that had focus. This page maps the code so you know where to look. For build instructions, see [BUILD.md](BUILD.md).

## Module map

| Path | Contents |
|---|---|
| `lib/core/` | Cross-cutting basics: settings model and provider (`config/`), the drift/SQLite database for history and notes (`data/`), localization (`l10n/`, ARB files), logging and crash reporting (`logging/`), recording state types (`recording/`), platform channels (`platform/`), theme tokens (`theme/`) |
| `lib/features/` | UI feature modules, one folder each: `settings`, `history`, `notes`, `snippets`, `replacements`, `onboarding`, `recording`, `feedback`, `about`, `analytics` |
| `lib/services/` | App logic without UI: hotkeys, audio capture, the recording pipeline, STT engines, Smart Mode, paste, tray, updates, the local automation API and the headless CLI |
| `lib/widgets/` | Shared `Wp*` widgets plus the floating overlay, floating button and side panel views |
| `macos/Runner/` | Swift hosts behind the platform channels (paste, clipboard monitor, floating windows, side panel, snippet picker, autostart, audio routing) |
| `windows/runner/` | C++ Win32 hosts for the same channels, plus the RawInput keyboard monitor |
| `linux/runner/` | C/GTK hosts for the same channels, plus the XInput2 / GlobalShortcuts portal keyboard monitor |
| `native/smart_mode/` | C++ shim between Dart FFI and llama.cpp, used by on-device Smart Mode |
| `test/`, `integration_test/` | Unit, widget and golden tests; integration tests |
| `website/` | The Astro project website, separate from the app |

State management is [Riverpod](https://riverpod.dev). Services are exposed as providers, and widgets read them through `ref`.

## From hotkey to pasted text

```
hotkey ──▶ trigger ──▶ audio capture ──▶ STT engine ──▶ post-processing ──▶ paste
          (toggle /                        whisper.cpp     filler words,        native host
           push-to-talk)                   Parakeet        Smart Mode,          per platform
                                           cloud API       replacements
```

1. **Hotkey.** `services/hotkey_service.dart` registers the global shortcut. `services/keyboard_up_monitor.dart` listens for key-up through a native monitor, which is needed for push-to-talk. `services/recording_trigger_handler.dart` maps key events to toggle, push-to-talk or the hybrid mode.
2. **Pipeline.** `services/recording_orchestrator.dart` runs one recording from start to paste. It drives the state machine in `services/recording/` and handles cancellation, errors and temporary files.
3. **Audio.** `services/audio_service.dart` and `services/audio/` capture 16 kHz mono PCM and write WAV files. During recording, `services/stt/live_preview/` can feed partial audio to the engine for the live transcript in the overlay.
4. **Transcription.** The selected engine turns the WAV into text:
   - **whisper.cpp** through FFI (`services/stt/whisper/`, native `libwhisper`)
   - **Parakeet** through `sherpa_onnx` (`services/stt_parakeet/`)
   - **cloud** through OpenAI or Deepgram (`services/transcription/`)

   The orchestrator only sees the engine-neutral lifecycle in `services/stt/on_device_engine_lifecycle.dart` and `services/stt_engine_lifecycle_provider.dart`.
5. **Post-processing.** These steps run in order:
   1. whitespace cleanup
   2. optional filler-word removal (`services/text_transforms.dart`)
   3. Smart Mode (`services/smart_mode/`), either on the device through `libllama` or through OpenAI
   4. text replacements (`services/replacements/`), applied together with the history save
6. **Paste.** `services/paste/` decides how to insert the text. It then calls the native desktop-paste host of the platform, which simulates the paste shortcut and restores the previous clipboard afterwards.

## Engine isolates

Every on-device engine runs in its own Dart isolate, so model loading and inference never block the UI thread:

| Engine | Isolate spawned in |
|---|---|
| Whisper | `services/stt/whisper/whisper_isolate_engine.dart` |
| Parakeet | `services/stt_parakeet/parakeet_engine_notifier.dart` |
| Smart Mode | `services/smart_mode/smart_mode_ffi_engine.dart` |

Each engine is loaded on demand, kept warm while in use and released after a period of inactivity. Several engines can live in the same process at once: for example, Whisper for transcription and llama.cpp for Smart Mode.

## Native code boundaries

Dart talks to native code in two ways:

- **Platform channels** (`MethodChannel`) for OS integration. The hosts live in each runner directory (table above).
- **FFI** for the inference engines: `libwhisper`, `libllama` through `native/smart_mode/`, and sherpa-onnx through its Flutter package.

Native libraries are built from pinned sources and bundled with the app (see [BUILD.md](BUILD.md)). `whispaste --diagnose` checks that a build can load them.

## Headless entry points

`lib/main.dart` handles these flags before any UI starts:

| Flag | Implementation | Purpose |
|---|---|---|
| `--transcribe-file` | `services/headless/` | Transcribe a WAV file and report timings |
| `--diagnose` | `services/headless/` | Start probe for the package smoke tests |
| `--toggle`, `--cancel` | single-instance service | Remote-control a running instance |

## Quality gates

See [CONTRIBUTING.md](CONTRIBUTING.md#gate-commands) for the format, analyze and test commands that CI runs, and [CONTRIBUTING_TRANSLATIONS.md](CONTRIBUTING_TRANSLATIONS.md) for the localization parity gate.
