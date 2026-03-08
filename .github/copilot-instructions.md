# WhisPaste — Copilot Instructions

## Project Overview

- Single-binary Windows desktop app, Go + CGO (malgo audio)
- System tray app with WebView2 settings UI
- Records speech, transcribes via OpenAI Whisper API, and pastes text anywhere
- Dependencies: malgo, systray, webview_go, hotkey, golang.org/x/sys/windows

## Build & Test

- Build: `$env:CGO_ENABLED="1"; go build -ldflags="-s -w -H windowsgui" -o whispaste.exe .`
- Debug build: `$env:CGO_ENABLED="1"; go build -o whispaste.exe .` (no `-H windowsgui`)
- Tests: `$env:CGO_ENABLED="1"; go test -v -count=1 ./...`
- Requires MinGW GCC in PATH (CGO dependency)
- Go 1.24+ required (dependency constraint)
- **Always build the production exe** (`-H windowsgui`) after changes. Only build a debug exe additionally if needed for console output.
- **Always build a fresh exe before marking a task complete.** This is a mandatory final step for every coding task.

### Fixing "cannot find -lsherpa-onnx-c-api" linker error

If `go build` fails with `cannot find -lsherpa-onnx-c-api` or `cannot find -lonnxruntime`, the import libraries (`.a` files) are missing from the Go module cache. The sherpa-onnx module ships only DLLs — you must generate import libs from them. **This MUST be fixed immediately, never deferred.**

```powershell
$sherpaDir = "$env:USERPROFILE\go\pkg\mod\github.com\k2-fsa\sherpa-onnx-go-windows@v1.12.28\lib\x86_64-pc-windows-gnu"
Push-Location $sherpaDir
gendef sherpa-onnx-c-api.dll
dlltool -d sherpa-onnx-c-api.def -l libsherpa-onnx-c-api.a -D sherpa-onnx-c-api.dll
gendef onnxruntime.dll
dlltool -d onnxruntime.def -l libonnxruntime.a -D onnxruntime.dll
Remove-Item *.def -Force
Pop-Location
```

Requires `gendef` and `dlltool` from MinGW (both in `C:\ProgramData\mingw64\mingw64\bin`). After this, `go build` will link successfully. If the sherpa-onnx module version changes, update the path accordingly.

## Debugging

- **App log**: `%APPDATA%\Whispaste\whispaste.log` — always check this FIRST when investigating runtime bugs
- Log levels: `[DBG]`, `[INF]`, `[WRN]`, `[ERR]` — search for `WRN` and `ERR` to find issues
- Common log patterns to watch for:
  - `Shell_NotifyIconW failed` — notification delivery failure (Win32 struct/AUMID issues)
  - `Update check failed` — GitHub API issues (404 = wrong repo URL, rate limiting)
  - `Transcription error` — API or offline model failures
  - `Hotkey registration failed` — hotkey conflict with another app or stale registration
- When adding new features, include `logDebug()` calls at decision points and `logWarn()`/`logError()` for all failure paths
- For Win32 API calls: always log the raw errno value on failure, not just `GetLastError()` text

## Architecture

- File-per-domain: audio.go, api.go, config.go, hotkey.go, overlay.go, paste.go, tray.go, ui.go, update.go, etc.
- Settings UI: single embedded HTML file (ui_settings.html) with CSS/JS, loaded via WebView2
- Localization: data-i18n attributes + JS translations object (EN/DE)
- Logging: structured file logging in logger.go (logDebug/logInfo/logWarn/logError)
- Config: JSON in %APPDATA%\Whispaste\config.json, thread-safe with sync.RWMutex

## Code Conventions

- Use `sync.RWMutex` for shared state (Config, Updater, etc.)
- Config getters use `mu.RLock()/mu.RUnlock()` pattern
- Wrap errors with `fmt.Errorf("context: %w", err)`
- Use `logInfo()`, `logWarn()`, `logError()` from logger.go — never `log.Printf` directly
- Win32 API calls via `golang.org/x/sys/windows` LazyDLL/NewProc pattern
- Embedded resources via `//go:embed`

## Separation of Concerns

- **Prefer smaller, focused files** over large monolithic ones — each file should have a single clear responsibility
- Separate HTML structure, CSS styling, and JavaScript logic into distinct files or scoped blocks
- Extract reusable components rather than duplicating code across files
- For Astro: use component files (`*.astro`) with scoped `<style>` blocks; extract shared CSS into `src/styles/`; extract shared JS into `src/scripts/`
- For Go: maintain the existing file-per-domain pattern (audio.go, config.go, etc.)
- For HTML (WebView): keep CSS/JS in the same file only when the file is embedded and must be self-contained (e.g., `ui_settings.html`)
- General guideline: if a file exceeds ~300 lines, evaluate whether it can be split into focused modules

## UI Icons

- **Never use emojis as icons** — always use inline SVG icons from Lucide (https://lucide.dev)
- Icons in the WebView settings UI use the `.icon` CSS class with `currentColor` stroke
- For dynamic icon updates in JavaScript, use `element.innerHTML` with SVG markup, never `element.textContent` with emoji

## Design System

The project has a unified design system with two surfaces:

- **App UI** (WebView2): CSS Custom Properties in `ui_main/styles/00-variables.css` — Cyan/Slate token system, dark-mode-first, Segoe UI font stack
- **Landing Page** (Astro): Tailwind `@theme` in `website/src/styles/global.css` — `--color-brand-*` variables, same Cyan/Teal palette

Full reference: `.agents/skills/whispaste-design/SKILL.md` — consult before any UI work.
Persisted design system for the website: `website/design-system/whispaste/MASTER.md`

## Testing

**Full policy: `.agents/skills/testing-policy/SKILL.md`** — consult before writing or reviewing tests.

**Motto: so wenig Tests wie möglich, so viel wie nötig.**
Goal: maximum stability gain at minimum maintenance cost. Not a goal: coverage metrics, enterprise mocking patterns, exhaustive test suites.

### Priority tiers

| Tier   | Scope                                               | Write tests? |
| ------ | --------------------------------------------------- | ------------ |
| **P0** | Auth, payments, data deletion, irreversible actions | Always       |
| **P1** | Core user flows (primary happy + failure path)      | Always       |
| **P2** | Edge cases, nice-to-have coverage                   | Skip         |

Only write P0 and P1 tests. Skip P2.

- **When adding new code**: write 1–2 targeted tests covering the core happy path + primary error path
- Tests in `package main` (same package) for access to unexported functions
- Use `httptest.NewServer` for HTTP-dependent tests
- Use `t.TempDir()` for file isolation
- No mocking frameworks — keep it simple

## Security

- HTTPS-only for all network requests (API, updates, checksums)
- SHA256 checksum verification for auto-updates
- API key stored in config.json with 0600 permissions, never logged
- openURL binding validates https:// prefix before opening
- No admin rights required

## Release & Distribution

- CI: `.github/workflows/ci.yml` (vet + test + build + secret scan)
- Release: `.github/workflows/release.yml` (tag-triggered, version injection via ldflags, SHA256 checksums)
- Auto-update: GitHub Releases API, disabled when running as MSIX Store package
- MSIX packaging: `msix/AppxManifest.xml` for Microsoft Store distribution

## Versioning

- **Skill**: `.agents/skills/versioning/SKILL.md` — consult BEFORE every release tag
- Version lives in 5 places; 3 must be manually updated before tagging (types.go, winres.json, template.html)
- release.yml auto-handles msix manifest + ldflags injection from git tag
- NEVER create a release tag without first updating the 3 manual version locations

## Documentation Maintenance

- **README.md must be updated** whenever features are added, changed, or removed
- Keep the features table, settings table, project structure, and "How It Works" section in sync with the actual codebase
- When adding new files (e.g. `postprocess.go`, `history.go`), add them to the project structure listing
- When adding new config fields, add them to the settings table with defaults and descriptions
