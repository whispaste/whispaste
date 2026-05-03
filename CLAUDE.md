# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**WhisPaste** is a premium cross-platform dictation app (Windows, macOS, Linux, iOS, Android) built with Flutter/Dart. Press a hotkey, speak, and text is pasted directly into any application. Features local AI transcription via whisper.cpp or cloud providers (OpenAI, Groq, Deepgram, Anthropic, Gemini), with post-processing, history management, voice shortcuts, and analytics.

**License**: MIT | **Repository**: Public on GitHub

---

## Build & Run Commands

### Development

```bash
# Install dependencies
flutter pub get

# Run on Windows (primary development platform)
flutter run -d windows

# Run on macOS
flutter run -d macos

# Generate localization files after editing ARB
flutter gen-l10n

# Format code
dart format lib/ test/

# Static analysis (lint + type checking)
flutter analyze --fatal-infos
```

### Testing

```bash
# Run all tests (excludes golden/screenshot tests)
flutter test

# Run a single test file
flutter test test/core/data/database_test.dart

# Run golden/screenshot tests only (includes widget comparisons)
flutter test --tags=golden

# Run tests with coverage
flutter test --coverage
```

### Building

```bash
# Windows debug build (fast iteration)
flutter build windows --debug

# Windows release build (optimized)
flutter build windows --release --no-tree-shake-icons

# macOS release build with Supabase secrets (required for feedback)
flutter build macos --release --no-tree-shake-icons \
  --dart-define=SUPABASE_URL="https://PROJECT_REF.supabase.co" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="sb_publishable_..."

# MSIX (Windows Store package) — requires MSIX_PUBLISHER secret
dart run msix:create --store
```

### Local Development with Services

To develop with Supabase feedback enabled locally:

```bash
flutter run -d windows \
  --dart-define=SUPABASE_URL="https://cnyniyflnefxrwafuqig.supabase.co" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="YOUR_PUBLISHABLE_KEY"
```

Values are in `.env` (gitignored) or Supabase Dashboard → Project Settings → API.

---

## Architecture & Data Flow

### Core Patterns

- **State Management**: Riverpod 3.x with `.notifier` and `Notifier<T>` classes. Providers are defined at the feature/service level and imported globally.
- **Persistence**: Drift (SQLite) for history, settings, tags, and stats. Supabase PostgREST for feedback (direct INSERT, no Edge Function relay).
- **Services**: Stateful lifecycle managers (audio capture, hotkey binding, STT subprocess, tray, floating UI). Bootstrapped in `ServiceBootstrapWidget`.
- **Error Handling**: Sentry for crash reporting (EU region: `de.sentry.io`), with 4-layer PII filtering (consent gate, cascade guard, beforeSend, SDK config).
- **Logging**: Structured logger with breadcrumb ring (last 30 entries in RAM) + rotating file (`whispaste.log`, 2 MB max).

### Recording Pipeline

The full dictation flow orchestrates in `RecordingOrchestrator` (a `Notifier<void>`):

```
User hotkey / FAB press
  ↓ toggleRecording()
  ↓ (audio capture starts)
Amplitude streaming → waveform display
  ↓ (user stops / timeout)
  ↓ WAV file saved to temp
  ↓ Ensure STT server running
  ↓ Transcribe WAV (local whisper.cpp or cloud provider)
  ↓ Save to Drift DB (HistoryEntries table)
  ↓ Desktop paste (PasteController writes to clipboard)
  ↓ Clean temp WAV
  ↓ State = done/error
```

**State Machine**: `RecordingPhase` enum: `idle`, `recording`, `transcribing`, `processing`, `done`, `error`. Each transition updates `RecordingState` (immutable snapshot with phase, elapsed, audioLevel, transcript, errorMessage, sessionId).

**Error Recovery**: OOM during STT → pipeline retries up to 3 times. GPU crash → automatic CPU fallback (marked in `SttStatus.cpuFallbackActive`). All errors surface in UI as localized messages.

### STT Service Architecture

`SttServiceNotifier` manages the local whisper-server subprocess:

- **Subprocess Lifecycle**: Find free port → spawn process → health-poll loop (until `SttServerState.ready`) → transcribe → auto-restart on crash.
- **GPU Detection**: Detects NVIDIA (CUDA), AMD/Intel (Vulkan), CPU fallback. Binary download service chooses architecture-specific build.
- **Model Tiers**: Compact, Balanced, Premium. Each tier has `TierSafety` warnings (usable, slowWithoutGpu, vramRisky, vramCritical) — tiers are never disabled, only color-coded.
- **Idle Timeout**: Server auto-stops after N minutes (default 5) if not transcribing, to free VRAM.

Cloud STT (OpenAI, Groq, Deepgram) routes through HTTP clients configured in `stt_service.dart`.

### Settings & Persistence

`AppSettings` is a single immutable data class with ~80 fields (theme, hotkey, microphone, STT provider, overlay config, API keys, etc.). Persisted to Drift's `app_settings` table, accessed via `settingsProvider` notifier.

**Sensitive Data**: API keys stored in platform secure storage (`flutter_secure_storage`), not in plain-text DB. `SecureKeyStore` handles encryption/decryption.

### History Database (Drift)

**Tables**:
- `history_entries` — transcribed text, metadata, timestamps
- `projects` — user-defined project groupings
- `daily_stats` — aggregated recording counts/durations per day
- `entry_notes` — rich-text notes attached to entries
- `entry_attachments` — file references (screenshots, audio clips)
- `text_replacements` — regex rules for post-transcription cleanup
- `tags` / `entry_tags` — full-text search via FTS5 virtual table

**Key Features**:
- Full-text search (FTS5) on title, content, tags
- Trigger-based auto-sync to FTS table on INSERT/UPDATE
- Migration strategy handles schema upgrades and Go-era data reconciliation
- Backfill support for analytics (DailyStats populated on startup for legacy entries)

### UI & Theme

**Design Tokens**:
- Colors: `WpColorsLight`, `WpColorsDark` (warm dark PRIMARY, light secondary)
- Spacing: `WpSpacing` (xs, sm, md, lg, xl in 8px increments)
- Radius: `WpRadius` (sm, md, lg, xl)
- Motion: `WpMotion.fast` (200ms), `.smooth` (300ms for page transitions)

**Navigation**: Single-page app with sidebar (5 main nav items + Settings pinned at bottom). Active page tracked in `activePageProvider` notifier. Page widgets lazy-loaded via `AnimatedSwitcher`.

**Internationalization**: EN + DE. All user text via `L10n.of(context)` + ARB files in `lib/core/l10n/`. Run `flutter gen-l10n` after editing ARB to regenerate `lib/core/l10n/generated/app_localizations.dart`.

### Floating UI & Desktop Integration

- **Floating Button**: Always-on-top window showing a recording button. Persists position across sessions.
- **Recording Overlay**: Minimal widget showing live waveform while recording, with amplitude metering.
- **System Tray**: macOS/Windows/Linux. Click tray icon to show/hide main window. Right-click menu for quit, settings.
- **Global Hotkey**: `hotkey_manager` captures `Ctrl+Shift+D` (default, user-configurable) system-wide. Works in any app.
- **Clipboard Integration**: `super_clipboard` for cross-platform paste. `DesktopPasteController` handles platform-specific implementation.

---

## Project Structure

```
lib/
├── main.dart                    # Entry point, bootstrap, window setup, RAM preflight
├── app.dart                     # Root app widget, navigation, layout shell
├── core/
│   ├── app_info.dart            # Version, Sentry release metadata
│   ├── config/
│   │   ├── settings_provider.dart     # AppSettings notifier (main config)
│   │   ├── settings_enums.dart        # Enums for settings (SttProvider, etc.)
│   │   ├── settings_labels.dart       # UI labels for settings
│   │   └── secure_key_store.dart      # API key encryption
│   ├── data/
│   │   ├── database.dart              # Drift database class, migrations, FTS
│   │   ├── database.g.dart            # Generated (do not edit)
│   │   ├── tables.dart                # Drift table definitions
│   │   ├── analytics_provider.dart    # Daily stats notifier
│   │   └── history_providers.dart     # Derived providers (search, filters)
│   ├── l10n/
│   │   ├── app_en.arb                 # English translations
│   │   ├── app_de.arb                 # German translations
│   │   ├── locale_provider.dart       # Locale notifier
│   │   └── generated/                 # Generated localization class (do not edit)
│   ├── logging/
│   │   ├── app_monitoring.dart        # Sentry + crash reporting bootstrap
│   │   ├── crash_reporter.dart        # CrashReporter singleton, beforeSend hooks
│   │   └── app_logger.dart            # Structured logger, breadcrumb ring
│   ├── recording/
│   │   └── recording_state.dart       # RecordingPhase, RecordingState, SttServerState
│   ├── platform/
│   │   └── macos_lifecycle_channel.dart # Platform channel for macOS tray
│   └── theme/
│       ├── theme.dart                 # wpLightTheme(), wpDarkTheme()
│       ├── theme_provider.dart        # ThemeMode notifier
│       ├── colors.dart                # WpColorsLight, WpColorsDark
│       └── tokens.dart                # WpSpacing, WpRadius, WpMotion
├── features/
│   ├── history/                 # Main page: search, view, edit, export entries
│   ├── settings/                # Settings pages (hotkey, STT, overlay, behavior)
│   ├── replacements/            # Text replacement rules
│   ├── analytics/               # Charts, stats, trends
│   ├── about/                   # App info, links, version
│   ├── feedback/                # Rating form, Supabase submission
│   ├── onboarding/              # First-launch overlay flow
│   └── recording/               # Recording state UI (phase, error display)
├── services/
│   ├── recording_orchestrator.dart    # Full dictation pipeline notifier
│   ├── stt_service.dart               # STT subprocess manager notifier
│   ├── audio_service.dart             # Audio capture & waveform metering
│   ├── model_download_service.dart    # GPU detection, binary fetch, cache
│   ├── hotkey_service.dart            # Global hotkey binding
│   ├── tray_service.dart              # System tray lifecycle
│   ├── desktop_paste/
│   │   └── desktop_paste_controller.dart # Paste to active window
│   ├── floating_button/               # Always-on-top button window
│   ├── floating_overlay/              # Recording overlay (waveform, amplitude)
│   ├── path_service.dart              # Cross-platform path helpers (appdata, docs, cache)
│   ├── update_service.dart            # Auto-update check & download
│   ├── deploy_channel_service.dart    # Detect if app came from Store vs portable
│   ├── sound_feedback_service.dart    # Audio cues (beeps, chimes)
│   ├── autostart_service.dart         # Launch at OS startup
│   ├── subprocess_guard.dart          # Orphaned process cleanup
│   ├── hardware_info_service.dart     # System RAM, GPU, architecture detection
│   ├── review_prompt_service.dart     # In-app review rating dialog
│   └── single_instance_service.dart   # Prevent multiple app instances
└── widgets/                     # Shared UI components (sidebar, FAB, status bar, etc.)

test/
├── core/
├── features/
├── services/
├── widgets/
├── screenshots/                 # Golden/screenshot tests
└── fixtures/                    # Test data & mocks

windows/ / android/ / ios/ / macos/ / linux/
└── Platform-specific runners & native configuration

website/
└── Astro-based marketing site (separate npm build, not Flutter)

supabase/
├── migrations/                  # SQL schema & triggers
└── functions/                   # Edge Functions (analytics, testimonials, feedback)
```

---

## Key External Integrations

### Sentry (Crash Reporting)

- **Endpoint**: `de.sentry.io` (EU region, GDPR-compliant)
- **Release Tracking**: Set in CI/CD via `SENTRY_AUTH_TOKEN` secret
- **Scope**: Device ID (anonymous MD5), app version, OS, architecture
- **PII Filtering**: 4 layers (consent, cascade guard, beforeSend regex, SDK config)
- **Breadcrumbs**: Last 30 log entries auto-attached to crashes
- **Env**: `environment: production` for releases, `development` for dev builds

### Supabase (Feedback & Analytics)

- **Project Ref**: `cnyniyflnefxrwafuqig`
- **Feedback Table**: `user_feedback` (direct PostgREST INSERT, no Edge Function)
  - Rate-limited: 3 feedback per device per 24h (DB trigger)
  - Char limit: 1000 per message
  - Categories: feature request, bug report, general feedback
- **Analytics**: Legacy—data now stored locally in DailyStats (Drift)
- **Credentials**: `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` via `--dart-define` at build time

### whisper.cpp

- **Subprocess**: Spawned on-demand at first transcription, runs HTTP server on localhost:random-port
- **Binary**: Downloaded to platform-specific cache directory via `ModelDownloadService`
- **Architecture**: Separate builds for CPU, NVIDIA CUDA, AMD/Intel Vulkan
- **Health-Check**: Polls `/health` endpoint until ready
- **Endpoint**: `POST /inference` with WAV file → JSON with text

---

## Common Development Tasks

### Adding a New Settings Field

1. Add field to `AppSettings` class in `settings_provider.dart`
2. Update `fromDb()` and `toDb()` constructors
3. Add persistent column to `app_settings` table if needed (Drift migration)
4. Create a settings section widget in `lib/features/settings/sections/`
5. Wire into `SettingsPage` via `settingsScrollTargetProvider` navigation
6. Localize labels in `app_en.arb` / `app_de.arb`, run `flutter gen-l10n`

### Adding a New UI Page

1. Create a new feature folder in `lib/features/` (e.g., `lib/features/my_feature/`)
2. Add `my_feature_page.dart` widget
3. Add nav item to `wpNavItems()` list in `app.dart`
4. Add page widget to `wpPageWidgets` map
5. Run `flutter analyze` and `flutter test`

### Debugging STT Issues

1. Check `SttStatus` in Riverpod DevTools or logs
2. Verify GPU detection: `hardware_info_service.dart` logs device info at startup
3. Check subprocess health: Look for `[STT]` logs in `whispaste.log`
4. Manual model download: Run `ModelDownloadService.downloadModel()` in Dart REPL
5. CPU fallback: If GPU crashes mid-recording, automatically retries on CPU (check `cpuFallbackActive` flag)

### Testing Database Queries

Use `HistoryDatabase.forTesting()` with an in-memory executor:

```dart
final db = HistoryDatabase.forTesting(NativeDatabase.memory());
await db.insertEntry(...);
final entries = await db.getAllEntries().get();
expect(entries, hasLength(1));
```

---

## CI/CD Workflows

All workflows in `.github/workflows/`:

### `ci.yml` (on push to `dev`, PR to `main`)

- Runs on Windows + macOS
- `flutter analyze --fatal-infos`
- `flutter test --exclude-tags=golden`
- cppcheck (C++ static analysis on Windows runner)
- `flutter build windows --debug` / `flutter build macos --debug`
- Secret scan (regex for API key patterns)
- Website build (npm in `website/`)

### `release.yml` (on tag `v*.*.*` or push to `main`)

- Builds Windows release + MSIX (if `MSIX_PUBLISHER` secret set)
- Builds macOS release + DMG
- Generates release notes (AI-enhanced if `OPENAI_API_KEY` set)
- Creates GitHub release with artifacts
- Creates Sentry release (if `SENTRY_AUTH_TOKEN` set)
- Triggers website redeploy

### Secrets Required

```bash
# Setup via: python3 scripts/setup-gh-secrets.py
SENTRY_AUTH_TOKEN       # Sentry API — for release tracking
SENTRY_DSN              # Sentry DSN — embedded in app
SUPABASE_URL            # Feedback database endpoint
SUPABASE_PUBLISHABLE_KEY # Feedback authentication
MSIX_PUBLISHER          # Windows Store publisher cert (optional)
OPENAI_API_KEY          # Release notes enhancement (optional)
```

Set via `gh secret set SECRET_NAME -b "value"` or the setup script.

---

## Design & UX Conventions

**From AGENTS.md:**

- **Premium Feel**: Inspired by Steam, gaming dashboards, WhatsApp/ChatGPT conversational UI
- **Theme**: Warm dark PRIMARY (default), light secondary
- **No**: Glow effects, flat SaaS cards, Material Icons
- **Yes**: Micro-animations (300ms fade+slide for nav, 80ms hover), WCAG AA contrast (4.5:1 body, 3:1 large)
- **Touch Targets**: Minimum 48×48px
- **Wow Test**: Would a user screenshot and share this UI?
- **Icons**: Lucide primary, Font Awesome complementary
- **Tokens**: Always use `WpSpacing`, `WpRadius`, `WpColors` — never hardcode pixel values

---

## Git Workflow

- **Branches**: `main` (stable) and `dev` (development only)
- **Commits**: Conventional Commits (feat, fix, refactor, docs, test, chore)
- **Merge**: `dev` → `main` directly — **never create GitHub Pull Requests**. This is a solo project; PRs add friction with no benefit. Use `git merge` or push directly to `main` after tagging.
- **Hooks**: Pre-commit checks (run `scripts/install-hooks.sh` once after clone)
  - Protected files not staged
  - No secrets in committed files
  - `flutter analyze` on Dart changes
  - Website build on website changes

---

## Analysis & Linting

- **Config**: `analysis_options.yaml`
- **Rules**: Strict; treats many warnings as errors
- **Run**: `flutter analyze --fatal-infos`
- **Excluded**: Generated files (`*.g.dart`, `*.freezed.dart`), build/, .dart_tool/

---

## Localization

**Files to Edit**:
- `lib/core/l10n/app_en.arb` — English
- `lib/core/l10n/app_de.arb` — German

**After Editing ARB**:

```bash
flutter gen-l10n
```

This regenerates `lib/core/l10n/generated/app_localizations.dart` (do not edit).

**In Code**: Always use `L10n.of(context).labelName` — never hardcode UI strings.

---

## Troubleshooting

### "RAM below 8 GB"

App shows `InsufficientRamScreen` and exits. Check `hardware_info_service.dart` for detection logic. Threshold is 7500 MB (accounts for OS reservations); user-facing requirement is 8 GB.

### "Flutter build fails on Windows"

- Ensure Visual Studio Build Tools installed (C++ compiler required)
- Run `flutter pub get`
- Delete `build/` folder and retry

### "STT server won't start"

- Check `whispaste.log` for subprocess errors
- Verify VRAM available (GPU models need 4–8 GB VRAM)
- Check `ModelDownloadService` logs — may be stuck downloading binary
- Manual fallback: Change STT provider to "Cloud" in settings

### "Tests fail with golden comparison"

Golden tests are excluded in CI by default. Run locally with:

```bash
flutter test --tags=golden --update-goldens
```

Commit updated `.png` files with `git add test/screenshots/`.

---

## Performance Notes

- **STT Cold Start**: ~10 seconds first transcription (subprocess spawn + GPU warmup). Pre-warmed in background via `_prewarmStt()`.
- **Audio Metering**: Amplitude streamed at ~100 ms intervals for waveform visualization.
- **Database**: FTS5 for full-text search is fast (< 100ms for typical queries).
- **Clipboard**: `super_clipboard` is cross-platform; native implementation per OS.

---

## Version & Release

- **Current**: 1.2.10 (from `pubspec.yaml`)
- **Bumping**: Edit `pubspec.yaml` version + `lib/core/app_info.dart` + `pubspec.yaml` `msix_version`
- **Release**: Tag `v1.2.x` on `main`, push → CI builds all platforms → GitHub release created

