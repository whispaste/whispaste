# WhisPaste — Architectural Project Plan

> Persistent architectural record for the WhisPaste project.
> This document captures key design decisions, dependency health, cross-platform roadmap, and technical debt.

---

## 1. Project Overview

WhisPaste is a premium Windows desktop voice-to-text application built entirely in Go. It combines real-time speech transcription with intelligent text processing through its **Smart Mode** pipeline.

### Core Capabilities

- **Local inference**: Ships bundled whisper.cpp and llama.cpp servers for fully offline, privacy-first transcription and text processing.
- **Cloud providers**: Supports OpenAI, Groq, Deepgram, Anthropic, and Gemini APIs for users who prefer cloud-based accuracy or speed.
- **Smart Mode**: Post-processes raw transcriptions through LLM pipelines — formatting, punctuation, translation, summarization, and context-aware rewriting.
- **Seamless UX**: Floating microphone button, system tray integration, global hotkeys, overlay notifications, and direct paste into any application.
- **History & Analytics**: SQLite-backed history with full-text search, project grouping, and usage analytics.

### Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Go |
| UI (Settings) | WebView2 + HTML/CSS/JS with Go bindings |
| UI (Floating/Overlay) | Win32 API (GDI+, layered windows) |
| Audio Capture | malgo (miniaudio bindings) |
| Local STT | whisper.cpp server (bundled) |
| Local LLM | llama.cpp server (bundled) |
| Database | SQLite via modernc.org/sqlite |
| Distribution | MSIX (Microsoft Store) + Standalone installer |

---

## 2. Architecture Decisions Record

### ADR-1: Provider Abstraction Layer

**Location**: `internal/provider/`

All STT and LLM backends implement unified interfaces, allowing the application to swap between local and cloud providers transparently. Each provider registers itself and exposes a consistent API for transcription or text completion.

### ADR-2: GPU Detection System

**Location**: `internal/gpu/`

A multi-vendor GPU detection system identifies available hardware at startup:

- **NVIDIA**: CUDA detection via `nvidia-smi` and driver APIs.
- **AMD / Intel**: Vulkan capability detection.
- **CPU fallback**: Always available as a baseline.

Detection results drive automatic selection of the correct whisper.cpp and llama.cpp binaries (CUDA, Vulkan, or CPU builds).

### ADR-3: Inference Configuration Profiles

**Location**: `internal/inference/`

Pre-defined use-case profiles control LLM behavior:

| Profile | Temperature | Use Case |
|---------|-------------|----------|
| `precise` | Low | Code dictation, technical terms |
| `balanced` | Medium | General dictation |
| `creative` | High | Brainstorming, free-form writing |
| `factual` | Very low | Data entry, numbers, addresses |

### ADR-4: WebView2 Settings UI with JavaScript Bridge

The settings interface is built as a single-page HTML/CSS/JS application rendered inside a WebView2 control. Go functions are exposed to JavaScript through explicit bindings (`ui_bindings_*.go`), keeping the UI layer decoupled from application logic.

### ADR-5: Win32 Native UI for Performance-Critical Elements

The floating microphone button, recording overlays, and hotkey registration use direct Win32 API calls for minimal latency and precise window management. These are implemented in dedicated Go files with `//go:build windows` tags.

### ADR-6: SQLite for History Storage

All transcription history is stored in a local SQLite database, providing full-text search, project-based grouping, and analytics without requiring an external database server.

### ADR-7: malgo for Audio Capture

Audio capture uses the malgo library (Go bindings for miniaudio), which provides low-level access to audio devices with minimal overhead. This supports real-time streaming to both local and cloud STT providers.

---

## 3. Dependency Monitoring

The following packages require periodic review for security, maintenance status, and potential replacements.

### Critical Dependencies

| Package | Status | Last Update | Notes |
|---------|--------|-------------|-------|
| `gen2brain/malgo` | ✅ Active | Nov 2025 | Healthy, well-maintained. Core audio capture dependency. |
| `mattn/go-sqlite3` | ✅ Active | Mar 2026 | Healthy. CGo-based SQLite driver. |
| `golang.org/x/sys` | ✅ Active | Mar 2026 | Healthy. Official Go extended library for system calls. |

### Stale Dependencies (Monitor)

| Package | Status | Last Update | Risk | Notes |
|---------|--------|-------------|------|-------|
| `faiface/mainthread` | ⚠️ Stale | — | Low | Thin wrapper ensuring code runs on the OS main thread. Minimal API surface, unlikely to need updates. |
| `getlantern/systray` | ⚠️ Stale (2.5yr) | Nov 2023 | Medium | 97 open issues upstream. Consider `energye/systray` as a replacement. |
| `MakeNowJust/hotkey` | ⚠️ Stale (3yr) | Feb 2023 | Low | Minimal API surface, works reliably. No known issues. |

### Indirect / Transitive Dependencies

| Package | Status | Last Update | Notes |
|---------|--------|-------------|-------|
| `getlantern/*` (indirect) | 🔴 Ancient | 2019 | Pulled in transitively by `getlantern/systray`. Will be resolved automatically when systray is replaced. |

### Review Cadence

- **Quarterly**: Check all stale dependencies for security advisories.
- **Before each release**: Run `go list -m -u all` to identify available updates.
- **Annually**: Re-evaluate replacement candidates for stale packages.

---

## 4. Cross-Platform Roadmap

### Phase 1 — Build Tags ✅ (Completed)

Fourteen pure-Windows source files have been tagged with `//go:build windows` constraints. This prevents compilation errors on non-Windows platforms for all tagged files and establishes a clean separation baseline.

### Phase 2 — Mixed File Splitting (Future)

Several files mix cross-platform business logic with Windows-specific API calls. These need to be split into platform-agnostic and platform-specific pairs:

| Current File | Cross-Platform | Windows-Specific |
|-------------|----------------|------------------|
| `main.go` | `main.go` | `main_windows.go` |
| `tray.go` | `tray.go` | `tray_windows.go` |
| `update.go` | `update.go` | `update_windows.go` |
| `llm.go` | — | `proc_windows.go` (extract `hideWindowSysProcAttr()`) |
| `stt.go` | — | `proc_windows.go` (same helper) |
| `internal/gpu/detect.go` | `detect.go` | `detect_windows.go` |
| `internal/export/export.go` | `export.go` | `export_windows.go` |
| `internal/preflight/preflight.go` | `preflight.go` | `preflight_windows.go` |

**Pattern**: Extract all `syscall.SysProcAttr` and Win32 API usage into `_windows.go` files. Provide no-op stubs or alternative implementations in `_linux.go` / `_darwin.go` files as needed.

### Phase 3 — Linux / macOS Support (Future)

- Replace Win32 APIs with cross-platform alternatives where feasible.
- Implement platform-specific UI backends (e.g., GTK on Linux, Cocoa on macOS).
- Adapt audio capture configuration per platform (malgo already supports multiple backends).
- Test and validate on each target platform.
- Evaluate alternative system tray libraries with native cross-platform support.

---

## 5. Test Coverage Strategy

### Critical Paths Requiring Coverage

#### Asset Matching

- **`matchSTTAsset`**: Verify correct GPU/CPU binary selection based on detected hardware. Test CUDA, Vulkan, and CPU fallback paths.
- **`matchLLMAsset`**: Verify the CUDA → Vulkan → CPU fallback chain selects the optimal binary for the detected GPU.

#### Model Management (`internal/models/`)

- **`Find`**: Locate models by name and type.
- **`Recommend`**: Suggest appropriate models based on hardware capabilities and VRAM thresholds.
- **SHA256 verification**: Ensure downloaded model files pass integrity checks.

#### GPU Detection (`internal/gpu/`)

- **Vendor detection**: Correctly identify NVIDIA, AMD, and Intel GPUs.
- **VRAM thresholds**: Apply memory-based constraints when recommending model sizes.
- **Asset key recommendations**: Map detected hardware to the correct asset key for binary downloads.

#### Provider Connections

- Mock-based integration tests for each cloud provider (OpenAI, Groq, Deepgram, Anthropic, Gemini).
- Verify request construction, response parsing, and error handling.
- Test timeout and retry behavior.

### Testing Principles

- Focus on logic-heavy code paths with high defect potential.
- Use table-driven tests for asset matching and GPU detection (many input combinations).
- Mock external dependencies (HTTP clients, GPU detection syscalls) at the interface boundary.
- Keep tests fast — no real network calls or GPU access in unit tests.

---

## 6. Tech Debt Items

### TD-1: systray Replacement

**Priority**: Medium
**Impact**: Maintenance risk, blocked bug fixes upstream

The `getlantern/systray` package has 97 open issues and has not been updated in over two years. Evaluate `energye/systray` or other actively maintained alternatives. The replacement must support:

- Custom tray icons (including dynamic icon changes)
- Context menus with submenus
- Tooltip text
- Windows 10/11 compatibility

### TD-2: SysProcAttr HideWindow Helper

**Priority**: Medium
**Impact**: Cross-platform compilation

Both `llm.go` and `stt.go` use `syscall.SysProcAttr{HideWindow: true}` to suppress console windows when launching whisper.cpp and llama.cpp servers. This Windows-only struct field causes compilation failures on other platforms.

**Resolution**: Extract a shared helper function into `proc_windows.go` with a build-tag gate, and provide a no-op stub for non-Windows platforms.

### TD-3: WebView2 User Data Path

**Priority**: Low
**Impact**: Cosmetic

The WebView2 runtime stores its user data in `%APPDATA%\whispaste.exe\EBWebView` — the `.exe` suffix in the directory name is a cosmetic issue inherited from the upstream `go-webview2` library. This does not affect functionality but looks unprofessional in file explorers.

**Resolution**: Monitor upstream library for a fix, or patch the user data directory path when initializing WebView2.

---

*Last updated: 2026-04-01 20:00 UTC*

---

## Recent Changes

| Date | Task | Size | Branch | Summary |
|------|------|------|--------|---------|
| 2026-04-03 | fix-7-bugs | Large | main | Fixed 7 bugs: floating button Advanced Settings padding (HTML nesting), removed star shape (unsuitable for mic), shape-aware countdown arc (GdipFlattenPath), custom color live preview (input event), overlay mic alpha pulsing (sqrt amplification), preflight false blocking (probe→warning), autotag title language (explicit lang in LLM prompt). Also fixed darkenColor channel overflow found in adversarial review. |
| 2026-04-02 | fix-crash-report-noise | Large | amboss/fix-crash-report-noise → main | Analyzed 22 crash reports (6 patterns), reduced noise by downgrading non-actionable logWarn→logInfo (preflight non-blocking, STT asset fallback, update permissions), filtered WebView2 about:blank localStorage SecurityError in JS, improved update permission error UX with clear toast notification (EN+DE i18n). 3-reviewer adversarial review (Opus, Sonnet, GPT-5.4) found and fixed over-broad error suppression. |
| 2026-04-01 | crash-report-analysis | Medium | main | Analyzed 23 Discord crash reports, fixed 5 root causes (noise reduction, localStorage SecurityError, llama-server lifecycle race, download resilience with retry+resume, postprocess false positive), enriched crash diagnostics (app state, uptime, memory, goroutine count, log breadcrumbs), cleaned up all Discord messages and Supabase records. |
| 2026-03-30 | integrated-vulkan-stt | Large | amboss/integrated-vulkan-stt | Completed the same-repo whisper-server delivery path: app-side STT release selection now prefers WhisPaste CPU/CUDA/Vulkan assets, added pinned whisper.cpp ref plus local build/package scripts, and introduced a GitHub Actions workflow that builds and uploads whisper-server release assets to this repository's releases. |
| 2026-03-30 | smartmode-vulkan-completion (app repo) | Large | amboss/smartmode-vulkan-completion | Hardened Smart Mode language behavior, fixed App Rules/runtime targeting, unified translate target handling, and introduced persistent `language_hint` history metadata so local auto-STT keeps a stable prompt hint without faking detected language. |
| 2026-03-30 | compliance-remediation | Large | amboss/multi-provider-upgrade | Build tags on 14 Windows files, extracted matchSTTAsset/matchLLMAsset pure functions with tests, models_test.go (22 subtests), expanded GPU detect tests (9 new), fixed CUDA 12 preference bug (cu12 vs cuda-12), project plan doc |

---

## Current Focus

- Crash report pipeline hardened: 5 root causes fixed, diagnostics enriched with runtime state/memory/breadcrumbs.
- Discord crash report channel cleaned (0 remaining reports).
- App-repo Smart-Mode hardening is complete and verified.
- Vulkan-STT now follows a same-repo release model:
  - build dedicated whisper-server Vulkan/CUDA/CPU assets from this repository
  - upload them to the matching GitHub release in this repository
  - app download logic prefers these WhisPaste-owned assets before upstream fallbacks
- Remaining validation is operational rather than architectural:
  - execute the workflow against a real published release
  - confirm AMD/Intel Vulkan download path end-to-end on target hardware

## Learned Patterns

- History metadata now distinguishes between `language` (known user-visible language metadata) and `language_hint` (stable processing hint, especially for local auto-STT flows). New history write paths must preserve both consistently.
