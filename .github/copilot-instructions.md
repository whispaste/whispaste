# WhisPaste — Technical Reference for AI Assistants

This document provides comprehensive technical details about the WhisPaste project for AI assistants working on the codebase. Read this before making any changes.

## Product Vision

WhisPaste is a premium desktop dictation application that combines best-in-class voice-to-text transcription with intelligent note management. Think of it as the perfect fusion of a professional speech-to-text tool and a lightweight productivity workspace — clean, intuitive, and powerful.

**Core promise**: Dictate anywhere, paste everywhere — with AI-powered post-processing that transforms raw speech into polished, context-aware text.

**Quality bar**: This is a $20M-caliber product. Every feature, every UI element, every interaction must reflect premium craftsmanship. We ship polished, not "good enough."

**UI philosophy**: Clean, intuitive, lightweight. All features must be quickly accessible yet the interface must remain uncluttered. When in doubt, hide complexity behind progressive disclosure — not behind missing functionality.

## Architecture Overview

### Core Technologies

- **Language**: Go 1.26+ (pure Go where possible, CGO only for audio capture)
- **Desktop Framework**: WebView2 (Windows) via `github.com/webview/webview_go`
- **UI**: Server-side assembled HTML/CSS/JS embedded in the binary (no framework, vanilla JS)
- **Database**: SQLite via `modernc.org/sqlite` (pure Go, no C dependency)
- **Audio**: miniaudio via `github.com/gen2brain/malgo` (CGO — cross-platform C library)
- **System Tray**: `github.com/getlantern/systray` (cross-platform)
- **Hotkeys**: `golang.design/x/hotkey` (cross-platform)
- **AI Inference**: whisper.cpp (STT) and llama.cpp (LLM) as managed subprocesses

### Key Architectural Decisions

1. **Single binary distribution**: The Go app compiles to one executable. AI inference binaries (whisper-server, llama-server) are downloaded on first use from GitHub releases.

2. **Provider abstraction**: STT and LLM backends are pluggable via `internal/provider` interfaces. Local inference and cloud APIs (OpenAI, Groq, Deepgram, Anthropic, Gemini) share the same interface.

3. **Multi-vendor GPU support**: GPU detection covers NVIDIA (nvidia-smi), AMD, and Intel (registry/sysfs). Binary selection: CUDA for NVIDIA, Vulkan for AMD/Intel, OpenBLAS for CPU.

4. **Thread-safe configuration**: All config access goes through `sync.RWMutex`-protected getters/setters. Config persists as JSON in the user's app data directory.

5. **Embedded UI**: HTML is assembled at startup from template + pages + styles + scripts (sorted alphabetically). No dev server needed — changes are visible after rebuild.

## Project Structure

```
whispaste/
├── .github/workflows/    # CI/CD (ci.yml, release.yml, codeql.yml)
├── .agents/skills/       # Copilot agent skills
├── internal/
│   ├── audiocache/       # Audio segment caching with TTL
│   ├── export/           # Multi-format history export (TXT, MD, CSV, JSON, DOCX)
│   ├── gpu/              # Multi-vendor GPU detection (NVIDIA, AMD, Intel)
│   ├── i18n/             # Translations (en, de) — hardcoded maps
│   ├── inference/        # Tuning profiles + thread optimization
│   ├── models/           # STT model registry (Whisper variants) with SHA256
│   ├── preflight/        # Hardware compatibility checks (OS, CPU, RAM, AVX)
│   ├── provider/         # STT/LLM provider interfaces + implementations
│   ├── stats/            # Usage statistics tracking
│   └── wav/              # WAV file generation from PCM samples
├── ui_main/
│   ├── template.html     # Main HTML template (injection points)
│   ├── pages/            # Tab pages (history, settings, smartmode, etc.)
│   ├── styles/           # CSS files (sorted alphabetically, injected)
│   ├── scripts/          # JS files (sorted alphabetically, injected)
│   └── components/       # Reusable HTML components (Go text/template)
├── installer/            # NSIS installer scripts
├── msix/                 # Windows MSIX packaging
├── scripts/              # Build & utility PowerShell scripts
├── website/              # Astro-based project website (separate)
├── winres/               # Windows resource files (icons, versioning)
├── resources/            # App icons and assets
│
├── main.go               # Entry point, single-instance guard, initialization
├── config.go             # Configuration management (~76 fields, RWMutex)
├── types.go              # App constants, states, version variables
├── logger.go             # File-based logging (5MB rotation, 4 levels)
├── api.go                # Cloud API transcription with retry logic
├── audio.go              # Audio capture via miniaudio (CGO)
├── stt.go                # Local STT subprocess management
├── stt_download.go       # STT binary + model download with SHA256
├── llm.go                # Local LLM subprocess management
├── llm_download.go       # LLM binary + model download
├── postprocess.go        # AI post-processing (Smart Mode presets)
├── history.go            # SQLite history with full-text search
├── history_db.go         # Database schema and migrations
├── hotkey.go             # Global hotkey registration
├── floating.go           # Floating record button (Win32 GDI+)
├── overlay.go            # Recording overlay with waveform
├── paste.go              # Clipboard + keyboard input synthesis
├── tray.go               # System tray icon and menus
├── update.go             # Auto-updater with SHA256 verification
├── ui_main.go            # WebView2 UI initialization + HTML assembly
├── ui_bindings_*.go      # Go↔JS bindings (settings, history, smart, ui)
├── ui_components.go      # HTML component template system
└── l10n_bridge.go        # i18n bridge (T(), SetLanguage())
```

## Build & Test Commands

```powershell
# Build (development — with console window for debugging)
go build -o whispaste.exe .

# Build (production — NO console window, stripped symbols)
go build -ldflags="-s -w -H windowsgui" -o whispaste.exe .

# Build (release with version injection — see scripts/build.ps1)
.\scripts\build.ps1 -Version "1.2.3"

# Test (all packages, no cache)
go test -count=1 ./...

# Test (specific package)
go test -v ./internal/gpu/...

# Vet (static analysis)
go vet ./...

# Lint (requires golangci-lint)
golangci-lint run

# Generate Windows resources (icons, version info)
go-winres make
```

**CGO requirement**: `CGO_ENABLED=1` is required (miniaudio audio capture). MinGW-w64 must be installed for Windows builds.

**Critical**: Production builds MUST use `-H windowsgui` in ldflags. Without it, Windows opens a terminal window alongside the GUI app.

## Dependencies Policy

### Selection Criteria

Every dependency must meet ALL of these:

1. **Actively maintained**: Last commit within 12 months, responsive to issues
2. **Cross-platform potential**: Must work on Windows. Ideally also Linux and macOS, or provide clean platform abstraction via build tags
3. **Not deprecated/legacy**: No packages marked as deprecated, archived, or superseded
4. **Minimal transitive dependencies**: Prefer packages with few or zero indirect deps
5. **Security-reviewed**: No known CVEs in current version. Run `govulncheck` before adding

### Current Direct Dependencies (6)

| Package | Purpose | Cross-Platform |
|---------|---------|----------------|
| `github.com/gen2brain/malgo` | Audio capture (miniaudio C bindings) | ✅ Win/Mac/Linux |
| `github.com/getlantern/systray` | System tray icon | ✅ Win/Mac/Linux |
| `github.com/webview/webview_go` | WebView2 UI | ⚠️ Win only (WebView2), needs platform switch |
| `golang.design/x/hotkey` | Global hotkeys | ✅ Win/Mac/Linux |
| `golang.org/x/sys` | OS syscalls | ✅ Win/Mac/Linux |
| `modernc.org/sqlite` | SQLite (pure Go) | ✅ Win/Mac/Linux |

### Adding New Dependencies

Before adding a dependency:
1. Check if Go stdlib or existing deps already cover the need
2. Verify the package is not archived/deprecated on GitHub
3. Check `go.sum` growth — prefer packages with minimal transitive deps
4. For platform-specific needs, prefer build-tag-gated imports over runtime checks
5. Run `go mod tidy` after adding; verify no unused deps remain

### Forbidden Patterns

- ❌ `github.com/mattn/go-sqlite3` — requires CGO for SQLite; we use `modernc.org/sqlite` (pure Go)
- ❌ Packages that vendor entire C libraries without build tag isolation
- ❌ Packages last updated > 2 years ago without being "complete" (e.g., UUID libs are fine)
- ❌ Alpha/beta-tagged packages in production paths

## Cross-Platform Strategy

### Current State: Windows-First

WhisPaste currently targets Windows exclusively. The codebase uses Win32 APIs directly for several features. The goal is to architect for cross-platform from the start, even if Linux/macOS support ships later.

### Platform Abstraction Rules

1. **Use build tags for platform-specific code**: Create `_windows.go`, `_linux.go`, `_darwin.go` files when platform behavior diverges. Never use runtime `GOOS` checks for compile-time decisions.

2. **Keep platform-specific code in leaf functions**: Business logic must be platform-agnostic. Only the lowest-level I/O layer touches OS APIs.

3. **Cross-platform packages preferred**: When choosing between a Windows-only solution and a cross-platform package, prefer cross-platform — unless the Windows-only approach is significantly better for users.

4. **Platform-dependent features to isolate**:

| Feature | Windows | Linux (future) | macOS (future) |
|---------|---------|----------------|----------------|
| UI Framework | WebView2 | WebKitGTK | WKWebView |
| System Tray | getlantern/systray ✅ | getlantern/systray ✅ | getlantern/systray ✅ |
| Global Hotkeys | golang.design/x/hotkey ✅ | golang.design/x/hotkey ✅ | golang.design/x/hotkey ✅ |
| Clipboard/Paste | Win32 SendInput | xdotool/wtype | AppleScript |
| Audio Capture | miniaudio (malgo) ✅ | miniaudio (malgo) ✅ | miniaudio (malgo) ✅ |
| Floating Button | Win32 GDI+ | GTK/X11 | NSWindow |
| Overlay | Win32 GDI+ | GTK/X11 overlay | NSWindow |
| GPU Detection | nvidia-smi + registry | nvidia-smi + sysfs | nvidia-smi + IOKit |
| Notifications | Win32 Toast/UWP | D-Bus/libnotify | NSUserNotification |
| Auto-start | Registry | XDG autostart | launchd |
| File Dialogs | GetSaveFileNameW | zenity/GTK | NSOpenPanel |

5. **Build tag naming convention**:
```go
//go:build windows
// +build windows

package main
```

### GPU Detection Cross-Platform Notes

The `internal/gpu/` package currently uses Windows-specific detection:
- NVIDIA: `nvidia-smi` (cross-platform ✅ — works on all OS)
- AMD/Intel: Windows registry (`HKLM\...\{4d36e968-e325-11ce-bfc1-08002be10318}`)

For Linux: Read `/sys/class/drm/card*/device/vendor` and `/proc/driver/nvidia/gpus/*/information`.
For macOS: Use `system_profiler SPDisplaysDataType` or IOKit.

Split into `detect_windows.go`, `detect_linux.go`, `detect_darwin.go` when adding platform support.

## Coding Conventions

### Go Style

- **Formatting**: `gofmt` (enforced by CI)
- **Naming**: Follow Go conventions — `CamelCase` for exported, `camelCase` for unexported
- **Win32 constants**: Prefix with underscore: `_WM_CREATE`, `_WS_POPUP`
- **JSON tags**: Always `snake_case`: `json:"field_name"`
- **Error wrapping**: Use `fmt.Errorf("context: %w", err)` for wrappable errors

### Logging

Use the project logger — never `log.Printf` or `fmt.Println`:

```go
logDebug("Detailed operational data: %v", value)   // Verbose, dev-only
logInfo("User-facing milestone: model loaded")       // Normal operations
logWarn("Recoverable issue: %v", err)                // Degraded but functional
logError("Unrecoverable failure: %v", err)           // User-visible error
```

**Never log API keys, tokens, or credentials.** Use `logDebug("API key present: %v", key != "")` instead.

### Configuration

All config access MUST use getters/setters (thread-safe):

```go
// ✅ Correct
value := cfg.GetAPIKey()
cfg.SetAPIKey(newValue)

// ❌ Wrong — data race
value := cfg.APIKey
cfg.APIKey = newValue
```

Config file: `%APPDATA%\WhisPaste\config.json` (Windows), `~/.config/whispaste/config.json` (Linux, future).

### Error Handling

```go
// Critical errors: log + propagate
if err != nil {
    logError("Operation failed: %v", err)
    return fmt.Errorf("operation: %w", err)
}

// Non-critical: log + continue with fallback
if err != nil {
    logWarn("Optional feature unavailable: %v", err)
    // Continue with default behavior
}
```

### Concurrency

- **Config**: `sync.RWMutex` — use `RLock` for reads, `Lock` for writes
- **Singletons**: `sync.Once` for lazy initialization (logger, GPU detection)
- **Subprocess management**: Mutex-guarded `running` flag + `waitCh` channel pattern
- **Win32 message loops**: `runtime.LockOSThread()` required
- **Never**: Access shared state without a lock. No exceptions.

### UI Development

The UI uses server-side HTML assembly (no React, no framework):

```
ui_main/template.html        → Main shell (injection points)
ui_main/pages/01-history.html → Tab content
ui_main/styles/01-base.css    → Styles (sorted, concatenated)
ui_main/scripts/00-utils.js   → JS (sorted, concatenated)
```

**File naming**: Prefix with number for load order (`00-`, `01-`, `02-`...).

**Go↔JS binding**: Functions registered via `w.Bind("name", func)` in `ui_bindings_*.go` files are callable from JS as `window.name()`.

**Component system**: Self-closing HTML markers expanded via Go `text/template`:
```html
<!-- @toggle-row key="smartMode" label="settings.smartMode" -->
```

**i18n in JS**: Use `t('key')` function. All translatable strings must have keys in `internal/i18n/i18n.go` (EN + DE).

**Page visibility**: Pages are toggled via `hidden` CSS class, not inline styles. MutationObservers must watch `class` attribute changes.

### Design Tokens

Use CSS custom properties from the design system — never hardcode colors or spacing:

```css
/* ✅ Correct */
color: var(--text-primary);
background: var(--bg-secondary);
padding: var(--spacing-md);
border-radius: var(--radius-md);

/* ❌ Wrong */
color: #333;
background: #f5f5f5;
padding: 16px;
```

## Testing Requirements

### Philosophy

Test critical business logic and hardware-dependent code thoroughly. UI layout and cosmetic details are verified through manual review and agent-based UI audits.

### What MUST Be Tested

**Critical business functions** (regressions here = user data loss or broken core flow):
- Configuration save/load and field marshaling (`config_test.go`)
- History database operations — CRUD, search, tagging (`history_test.go`)
- API transcription retry logic and error handling (`api_test.go`)
- Audio input health classification (`audio_test.go`)
- Smart Mode post-processing (`postprocess_test.go`)

**Hardware detection and model management** (regressions here = wrong binary downloaded, GPU not detected):
- GPU vendor identification from device names (`internal/gpu/detect_test.go`)
- GPU VRAM threshold checks (`internal/gpu/detect_test.go`)
- Asset key recommendation for STT and LLM downloads (`internal/gpu/detect_test.go`)
- STT model registry — SHA256 hashes, model selection (`internal/models/`)
- Inference profile thread calculation (`internal/inference/config_test.go`)
- Preflight hardware checks (`internal/preflight/preflight_test.go`)

**Provider abstraction** (regressions here = cloud API calls fail silently):
- Provider interface compliance (`internal/provider/provider_test.go`)
- Request/response format validation per provider

**Infrastructure** (regressions here = app won't start or update):
- Logger initialization and rotation (`logger_test.go`)
- Auto-update version detection (`update_test.go`)
- HTML assembly and component expansion (`ui_main_test.go`, `ui_components_test.go`)
- Export format generation (`internal/export/export_test.go`)
- i18n key completeness (`internal/i18n/i18n_test.go`)

### Testing Patterns

```go
// Table-driven tests (preferred)
func TestVendorFromName(t *testing.T) {
    tests := []struct {
        name   string
        vendor Vendor
    }{
        {"NVIDIA GeForce RTX 4090", VendorNVIDIA},
        {"AMD Radeon RX 7900 XTX", VendorAMD},
        {"Intel(R) UHD Graphics 770", VendorIntel},
    }
    for _, tc := range tests {
        if got := vendorFromName(tc.name); got != tc.vendor {
            t.Errorf("vendorFromName(%q) = %q, want %q", tc.name, got, tc.vendor)
        }
    }
}

// Temp directory isolation for file I/O
func TestConfigSaveLoad(t *testing.T) {
    dir := t.TempDir()
    // ... test with isolated directory
}

// Dependency injection for external systems
// Override function vars in tests (e.g., preflight checks)
```

### When to Add Tests

- **New internal package**: Must ship with `*_test.go` covering exported functions
- **Bug fix**: Add a regression test that would have caught the bug
- **New provider**: Add interface compliance test + request format validation
- **Hardware detection changes**: Add test cases for new GPU name patterns
- **Config field additions**: Add marshal/unmarshal test case

### When Tests Are NOT Required

- Pure UI/CSS changes (covered by UI review skills)
- Documentation changes
- CI/CD workflow changes
- Build script changes (verified by CI pipeline)

## AI Inference Architecture

### STT (Speech-to-Text)

**Local**: whisper.cpp `whisper-server` subprocess
- Binary downloaded from `ggml-org/whisper.cpp` GitHub releases
- Asset selection: `cublas-12` (NVIDIA CUDA), `blas-bin-x64` (CPU OpenBLAS)
- Models: Whisper Tiny → Large v3 Turbo (31 MB → 547 MB)
- All models verified via SHA256 before use

**Cloud**: Provider-based (OpenAI, Groq, Deepgram)
- Interface: `provider.STTProvider.Transcribe(ctx, audio, lang, opts)`
- Automatic retry with exponential backoff (3 attempts)

### LLM (Large Language Model)

**Local**: llama.cpp `llama-server` subprocess
- Binary downloaded from `ggml-org/llama.cpp` GitHub releases
- Asset selection: `win-cuda` (NVIDIA), `win-vulkan-x64` (AMD/Intel), `win-cpu-x64`
- CUDA 12.x preferred over 13.x (broader driver compatibility)
- Vulkan is the universal GPU fallback (works on all vendors)
- Context size: 4096 tokens, thread cap: 12

**Cloud**: Provider-based (OpenAI, Groq, Gemini, Anthropic)
- Interface: `provider.LLMProvider.ChatCompletion(ctx, messages, opts)`

### GPU Detection Flow

```
Detect() → nvidia-smi (NVIDIA?) → yes: CUDA backend
                                  → no: Registry/sysfs (AMD/Intel?)
                                        → yes: Vulkan backend
                                        → no: CPU fallback
```

Results are cached via `sync.Once` — detection runs once per app lifecycle.

### Download Safety

- All model downloads include SHA256 verification against hardcoded manifest
- Server binaries are downloaded from official GitHub releases only
- Downloads support resume for interrupted transfers
- Progress callbacks update the UI

## Security Considerations

### API Keys & Credentials

- Stored in `config.json` with file permission `0600`
- Never logged (not even at debug level) — log presence only: `key != ""`
- Never included in error messages
- Never transmitted to unintended endpoints

### Network Security

- Local AI servers bind to `127.0.0.1` only — never exposed on network
- HTTP used for localhost only (no TLS needed for loopback)
- All external API calls use HTTPS
- GitHub API calls include proper `Accept` headers

### Binary Downloads

- SHA256 verification for all model files
- Server binaries from official GitHub releases only
- No arbitrary code execution from downloaded content

### Win32 Security

- Single-instance guard via named mutex (prevents duplicate instances)
- Clipboard operations use proper Win32 API lifecycle (Open → Set → Close)
- No elevation required — runs as standard user

## CI/CD Pipeline

### CI (`ci.yml`) — Runs on every push/PR

1. Setup Go (from `go.mod`) + MinGW (CGO)
2. `go-winres make` (Windows resource generation)
3. `go vet ./...` (static analysis)
4. `go test -count=1 ./...` (all tests, no cache)
5. `go build -ldflags="-s -w -H windowsgui"` (production build)
6. Secret scan (grep for API key patterns)
7. Upload artifact (14-day retention)

### Release (`release.yml`) — Triggered by `v*` tags

1. Same build pipeline as CI
2. Version injection via `-ldflags` (from git tag)
3. SHA256 checksum generation
4. NSIS installer build
5. MSIX packaging
6. GitHub Release creation with all artifacts

### Security Scanning

- **CodeQL**: Automated on push + weekly schedule
- **Secret scan**: Regex patterns in CI for `sk-`, `AKIA`, `ghp_`, `password=`
- **DevSkim**: Run locally before commits (all severity levels)
- **golangci-lint**: gosec, staticcheck, errcheck, gocritic, and more (see `.golangci.yml`)

## Localization (i18n)

**Supported languages**: English (en), German (de)

**Storage**: Hardcoded maps in `internal/i18n/i18n.go`

**Key namespaces**:
- `app.*` — App metadata (name, description)
- `tray.*` — System tray menu items
- `settings.*` — Settings UI labels
- `error.*` — Error messages
- `state.*` — Recording state labels
- `preflight.*` — Hardware compatibility messages

**Adding new strings**:
1. Add key to both `en` and `de` maps in `internal/i18n/i18n.go`
2. Use in Go: `T("key")`
3. Use in JS: `t('key')` (injected via `01-translations.js`)
4. Run `go test ./internal/i18n/...` to verify completeness

**Rules**:
- Every user-visible string must be localized (both EN + DE)
- Use du-Form (informal "you") in German translations
- Keep translations concise — UI space is limited
- Technical terms may stay in English if commonly used (e.g., "API Key", "GPU")

## Competitor Awareness

When implementing new features or optimizing existing ones, research how leading voice-to-text and productivity tools solve similar problems. Look at their approaches for inspiration — particularly around:

- Cross-platform binary management and GPU acceleration
- Audio pipeline reliability and format handling
- Privacy-first local inference with cloud fallback
- Meeting detection and context-aware dictation
- History management with search and organization

**Rules**:
- Never reference competitors by name in code, comments, or documentation
- Never copy code verbatim — understand the approach, then implement it better
- Always verify that our solution handles edge cases the reference may miss
- Our quality bar is higher: if the reference solution is "good enough," make ours excellent
