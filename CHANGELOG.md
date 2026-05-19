# Changelog

## Unreleased

## 1.2.21

### Features

- **Onboarding gains a dedicated Auto-Paste step**. New users now hit a guided `AutoPasteStep` before reaching the Ready screen. On macOS it triggers the Accessibility prompt, polls TCC state via a `PollingPhase` controller, surfaces a "Waiting for permission…" hint card while the System Settings sheet is open, exposes a lazy "Repair permissions" button (`tccutil reset Accessibility + AppleEvents`) that only appears once the user has had a chance to grant manually, and shows a sharper TCC-mismatch banner with a restart hint when the bundle ID granted in TCC no longer matches the running app. On Windows the same step runs a verify branch that detects the UIPI edge case (elevated foreground window blocks `SendInput`) and skips cleanly with a Windows-specific explanation. The step counter at the top of the wizard is now dynamic, so users on `clipboardOnly` mode (where the Auto-Paste step is skipped) no longer see misleading "Step 3 of 4" labels. A new diagnostic-paste endpoint backs a **Test-Paste sub-step** that lets the user verify the paste path end-to-end without recording first.

- **Hotkey conflict detection in `ReadyStep`**. The Ready screen now checks whether the configured global hotkey is already claimed by another running app or by the OS before the user hits Start. If a conflict is detected, the step blocks the Start CTA and points the user back to the Hotkey step instead of letting them finish onboarding into a broken state.

- **Dynamic language selector in `WelcomeStep`**. The welcome screen picks up the user's OS locale on first paint and proposes it as the default transcription language. The old static pill-row selector has been replaced by a shared `LanguageSelector` dropdown that scales to the full Whisper language catalog without overflowing.

- **`ReadyStep` reacts to `afterTranscriptionAction`**. The "What happens after recording?" preview on step 3 now updates live when the user changes the after-transcription mode (`copy` / `paste` / `clipboardAndPaste`) elsewhere in onboarding, so the preview text always matches the active mode.

- **Status-bar Auto-Paste-Off hint**. Users who skip the Auto-Paste onboarding step now see a one-time hint in the status bar explaining that Auto-Paste is off and how to enable it later, so the skipped path is recoverable without the user having to remember the setting exists.

- **Soft release-out on the floating overlay when recording ends**. The waveform now animates out gracefully when the overlay transitions from `recording` to `transcribing`, instead of snapping flat. The new `WaveformPipeline` drives a ring-buffer of bar heights with configurable attack/release smoothing, so the visualisation tracks speech energy faithfully on rises and decays smoothly on silence.

- **Perceptual `SpeechLevelMapper`**. The raw RMS level from the audio engine is now mapped through a perceptual dB → visual curve before reaching the overlay. Quiet speech registers visibly, loud speech doesn't clip the bars, and the silence floor sits where the user expects it.

### Refactor

- **`PasteCapabilityNotifier` extracted from the indicator widget**. The Auto-Paste capability state (the `ready` / `permissionMissing` / `unsupported` machine shipped in 1.2.19) now lives in a dedicated Riverpod notifier instead of being tangled into the Settings indicator widget. The new onboarding `AutoPasteStep` and the existing Settings indicator both observe the same source of truth, so a permission grant in onboarding immediately reflects in Settings and vice versa.

- **History UI adopts split-view + search-filter-bar naming**. The history pane's internal widgets and providers have been renamed to match the `CONTEXT.md` glossary (`SplitView`, `SearchFilterBar`). No behaviour change — pure terminology alignment so future references match the canonical vocabulary.

- **Shared `LanguageSelector` widget**. Onboarding and Settings now both consume the same dropdown widget for transcription-language selection, eliminating the duplicated pill-row in onboarding and the bespoke dropdown in Settings.

- **`AudioService` routes level through `SpeechLevelMapper`**. The internal audio level path no longer exposes raw RMS to consumers. The new `setWaveformBars` channel is the supported way to drive visualisations, and the legacy `setAudioLevel` hook has been removed.

### Bug Fixes

- **Sentry no longer ingests user-config noise**. Settings-page navigation, preference toggles, and the routine config-load breadcrumbs that contributed nothing diagnostic but inflated event payloads have been filtered out at the breadcrumb level. Crash reports stay focused on the path that led to the failure instead of being buried under setting reads.

- **Disposal guard on `AutoPasteStep`**. The onboarding step now cancels its TCC poll and Sentry breadcrumb timer when disposed, so navigating away mid-grant no longer leaks a timer or fires a breadcrumb against a dead context.

## 1.2.20

### Bug Fixes

- **Release pipeline no longer fails when an action's Post-step exits non-zero**. In v1.2.19 every functional Windows build step (compile, Sentry symbol upload, NSIS installer, MSIX, both artifact uploads) succeeded, but the `subosito/flutter-action` Post-step (cache save on a cache hit) returned a non-zero exit code. That flipped `needs.build-windows.result` to `failure` and the conditional gates on `create-release` and `submit-ms-store` (`result == 'success'`) skipped both jobs, leaving the binaries stranded in the artifact storage with no GitHub Release and no Microsoft Store submission. The workflow now exposes an explicit `build-succeeded` output set by a `Mark build succeeded` step that runs after every real build/upload step. Downstream jobs gate on that output (combined with `!cancelled()`) instead of the job result, so cache-save quirks or other Post-step failures can no longer block a release.

## 1.2.19

### Bug Fixes

- **Auto-Paste now works on ad-hoc-signed macOS builds**. The old code aborted with `Paste failed` whenever `AXIsProcessTrusted()` returned `false`, but on macOS Sequoia that API lies for ad-hoc-signed apps: every rebuild produces a new content hash, TCC binds permissions to that hash, and the visible "Accessibility ON" toggle in System Settings keeps referring to a previous build. The Swift host no longer treats the AX check as a hard gate. Instead it posts the keystroke through **two independent permission channels** (`CGEvent` + AppleScript via `System Events.keystroke`), reports honest success only when at least one channel can be proven to have landed, and includes a structured detail string (`ax=… cg=… as=… target=…`) in the result so silent-drop scenarios are diagnosable from `whispaste.log`.

- **Paste failures are no longer silent when the main window is hidden**. The previous in-app toast was invisible in the normal use case where the user is focused on Terminal / VS Code / Warp and WhisPaste lives in the tray. Three additional surfaces fire on every paste failure: a **native OS notification** via `local_notifier` (Toast on Windows, Notification Center on macOS), a **Dock-icon bounce** (`NSApp.requestUserAttention(.criticalRequest)`) on macOS / **taskbar flash** (`FlashWindowEx(FLASHW_TRAY|FLASHW_TIMERNOFG)`) on Windows, and a **persistent tray-menu badge** ("⚠ Auto-Einfügen blockiert — Berechtigung erteilen") that survives until the next successful paste auto-clears it. Attention requests are throttled to one per minute per failure kind to avoid spamming during a recording session.

### Features

- **Auto-Paste capability indicator in Settings**. The "After Transcription" section now hosts a live status card that probes both permission channels without actually pasting, shown as soon as the user enables `paste` or `clipboardAndPaste` mode. The card surfaces three actionable states (`ready` / `permissionMissing` / `unsupported`) with platform-specific repair actions: **"Test now"** runs a fresh `AXIsProcessTrusted` + AppleScript probe; **"Grant permission"** triggers `AXIsProcessTrustedWithOptions(prompt: true)` and opens System Settings → Privacy → Accessibility; and a new **"Repair permissions"** button that spawns `tccutil reset Accessibility com.whispaste.whispaste && tccutil reset AppleEvents com.whispaste.whispaste`, the documented Apple workaround for stale TCC entries on ad-hoc-signed apps. The repair button is hidden on Windows where TCC doesn't apply.

- **Structured paste-outcome reporting end-to-end**. The native bridges now return `{status, detail}` maps (`success` / `no_target` / `no_accessibility` / `post_failed` on macOS; `success` / `no_target` / `foreground_blocked` / `send_input_failed` on Windows) which Dart maps to a typed `PasteOutcome` enum (`success` / `blocked` / `platformUnavailable` / `noTarget` / `permissionMissing` / `failed`). Toast messages, native notifications, and tray badges are tailored to the specific failure mode so the user gets actionable guidance instead of a generic "Paste failed".

- **Visible native logging via `os_log`** in the macOS Swift host (`subsystem=com.whispaste.paste`) replaces the prior `NSLog` calls, which Apple's unified logging filters from non-Apple processes. Combined with the Dart-side `DesktopPaster.info` line logging the full native detail string, every paste attempt now leaves a triage-ready record in `~/Library/Application Support/WhisPaste/logs/whispaste.log`.

## 1.2.17

### Features

- **Streamlined model selection**: The STT model catalog now exposes exactly one model per quality tier — `whisper-small` (Compact), `whisper-medium` (Balanced), and `whisper-large-v3-turbo` (Premium). The previous catalog mixed redundant variants (`whisper-tiny`, `whisper-base`, non-turbo `whisper-large-v3`) that made tier-based defaults ambiguous and shipped large files for marginal quality wins. Existing installations are migrated automatically on settings load: any removed model ID is rewritten to its tier representative, so users keep a valid selection without manual intervention.

### Cleanup

- **CI/release pipeline consolidation**: The release workflow now triggers only on tag push (a stray merge to `main` no longer burns ~15 min on Win + macOS + MSIX builds whose artifacts are never published). The Windows and MSIX builds were merged into a single job that reuses one `flutter build windows --release` for both the NSIS installer and the MSIX store package, cutting roughly a duplicate Windows build off every release. Redundant `flutter analyze` + `flutter test` steps were dropped from the release job because CI on `dev` already gates them. The flaky Linux secure-storage job was removed (Linux is not a release target and the same path is covered on Win + macOS), the secret scan was deduplicated into a single Ubuntu job, and the changelog-refresh cron dropped from daily to weekly.

## 1.2.16

### Bug Fixes

- **Sentry consent gating**: Transactions are now suppressed alongside events when the user revokes monitoring consent. Previously the kill switch only stopped event capture, so performance spans and Drift query traces could still leak after opt-out. The consent check now runs in the transaction sampler, so revoking consent silences the SDK end-to-end with no restart needed.

### Observability

- **Sentry SDK 9.20 upgrade**: `sentry_flutter` moves from 8.14 to 9.20, with the matching `sentry_dio` and `sentry_drift` integrations enabled. HTTP requests through the update service's Dio client and every Drift database query now produce performance spans, so a slow update check or a regressed query shows up in the Sentry transaction list instead of staying invisible. Trace propagation is explicitly scoped to an empty allow-list so no `sentry-trace` headers leak to third-party APIs.

- **Native crash symbolication**: Release builds upload PDB/DLL symbols on Windows and `.dSYM` bundles on macOS to Sentry via `sentry_dart_plugin` during the release workflow. Native crash frames in the Rust audio engine, the whisper.cpp bridge, and platform plugins now resolve to source lines instead of raw addresses. Symbol upload uses a separate Sentry billing bucket and does not consume the event/span quota.

- **Route breadcrumbs**: A `SentryNavigatorObserver` is wired into both top-level `MaterialApp`s so dialog opens, settings panels, and the review prompt land as navigation breadcrumbs on the next error event — the path that led to a crash is now reconstructable.

### Distribution

- **Microsoft Store submission automated**: The release workflow now pushes a successful MSIX build to the Microsoft Store via the Partner Center Submission API. The "What's new" field is populated from the same AI-enhanced release notes that the GitHub Release uses, in both English and German. The job self-skips when the `MS_STORE_APP_ID` secret is unset, so forks and dispatch-only runs stay clean. Listing copy (description, features) lives in `store/` per locale.

### Cleanup

- **Dependency wave**: `flutter_secure_storage` 9 → 10 (consolidated iOS+macOS pod, Linux drops the `libjsoncpp1` system dep), `drift` family + `analyzer` + `sqlite3` upgraded, Dart utilities (`flutter_soloud`, `flutter_svg`, `lucide_icons_flutter`, `in_app_review`, `mocktail`) on current minor, website npm dependencies refreshed (Tailwind held at 4.2 until an upstream Vite/rolldown compatibility issue is resolved), CI action major pins bumped (checkout v6, setup-node v6, upload-artifact v7, download-artifact v8, withastro/action v6, deploy-pages v5, softprops/action-gh-release v3).

## 1.2.15

### Bug Fixes

- **Auto-Paste reports the real outcome (macOS)**: The macOS paste host now waits for the synthesised ⌘V to complete before reporting success back to Flutter, hard-stops with a clear error when the Accessibility permission is missing, clears stale target-app state when WhisPaste itself is frontmost, and uses the modern `activate(options:)` API on macOS 14+. The Auto-Paste toast no longer claims success when nothing was actually pasted.

### New Features

- **Multi-format export activation**: The history detail panel can now export the selected entry to TXT, MD, CSV, JSON, and DOCX. The action is wired up from the detail panel overflow menu and uses the platform file save dialog — no third-party services involved.

### Removals

- **`Projects` table and `project_id` column removed**: The unused `Projects` table and the `HistoryEntries.project_id` column have been deleted. A one-time destructive Drift v9 → v10 migration drops both on first launch. **Migration note**: Existing user databases auto-migrate from schema v9 to v10 on first launch. The migration is idempotent and requires no user action; transcripts, notes, tags, and timestamps are preserved.

- **Command Palette removed**: The entry-scoped Ctrl+K popup has been removed. All actions it exposed (export, copy, delete, etc.) remain available through the history detail panel's overflow menu, so no functionality is lost.

- **`useVAD` and `vadSensitivity` settings removed**: The Recording stack never read these two settings, so the corresponding UI controls and persisted columns have been dropped. Old persisted `use_vad` / `vad_sensitivity` keys in existing databases are silently ignored — no migration required.

### Cleanup

- **README and website Features alignment**: The README and the website Features section have been trimmed to match the actually-shipping feature set after the removals above. Outdated mentions of Projects, the Command Palette, and the VAD toggle have been removed from public-facing documentation.

## 1.2.13

### Bug Fixes

- **Model-failure classification with re-download prompt**: WhisPaste now classifies whisper-server exit codes more precisely. A code-3 failure (failed to load model) triggers an actionable "Please re-download the model" prompt and clears the cached model path, so a single corrupt or incompatible file no longer locks the user into an unrecoverable state. Subsequent recordings resume normally after re-download.

- **Heartbeat startup timeout**: The STT server heartbeat now enforces a hard deadline during startup. If the server does not become ready within the configured timeout, the pipeline fails fast with a clear error instead of hanging indefinitely while the process idles in the background.

- **Recording idempotency**: Rapid hotkey presses and overlapping trigger signals no longer start a second recording while one is already in flight. The orchestrator gates on the current `RecordingPhase` so only one session is active at a time, preventing corrupted WAV files and duplicate history entries.

- **Hotkey `TypeError` fallback**: On platforms where the hotkey manager returns a non-string key token, WhisPaste now catches the `TypeError` and degrades gracefully instead of crashing. The hotkey is marked as unregistered and the user sees an actionable settings nudge.

### Observability

- **Sentry fingerprint extension**: Error events are now grouped by a richer fingerprint that includes the recording phase and STT status at the time of failure. This collapses noisy duplicate issues in the Sentry dashboard and makes regression tracking more reliable.

- **Info-level guard fires**: Sentry now captures info-level breadcrumbs when safety guards (OOM guard, CPU fallback gate, idempotency gate) activate. These breadcrumbs are attached to the next error event, giving support the full decision trail without PII.

### Removals

- **Smart-Mode dead code removed**: All `SmartMode`-prefixed fields, providers, and UI fragments have been deleted. The feature was never shipped publicly; removing the dead code reduces bundle size and eliminates confusion in the settings diff. No user-visible behaviour changes.

- **Groq STT removed**: The Groq cloud STT backend has been removed from WhisPaste. **Migration note**: Existing users who had Groq selected as their STT provider will automatically fall back to On-Device STT (whisper.cpp) on first launch after the update. No data is lost; the API key stored in secure storage is left intact but is no longer read.

### New Features

- **Deepgram STT — production-ready**: The Deepgram Nova-2 cloud STT backend is now fully functional and supported as a first-class provider alongside OpenAI and On-Device. Real-time streaming transcription, automatic language detection, and speaker diarisation are all supported. Configure your Deepgram API key in Settings → Cloud STT.

- **Free-tier onboarding hints**: Settings now shows inline signup links for Deepgram (free tier: 45 hours/month) and OpenAI (pay-as-you-go) directly beneath the API key fields. New users no longer need to leave the app to find sign-up links.

### Cleanup

- **README and website consistency**: Removed Post-Processing, LLM auto-tagging, and Groq from the README feature list and the website landing page. The public-facing documentation now accurately reflects the shipped feature set.

### Internal Refactors

- **`AppSettings` section-based architecture**: `AppSettings` is now split into focused section classes (`RecordingSettings`, `SttSettings`, `UiSettings`, etc.) instead of a flat record. Each section owns its own `fromDb`/`toDb` logic, making future column additions additive rather than requiring edits across the entire settings surface.

- **STT subsystem modularisation**: The monolithic `SttService` has been split into deep, independently testable modules — `SttProcessManager`, `SttHealthMonitor`, `SttTranscriber`, and `SttProviderRouter`. Each module has its own unit tests and a clearly defined interface boundary.

- **Recording orchestrator decomposition**: `RecordingOrchestrator` has been refactored into three collaborating components — `SafetyGuard` (pre-flight checks and idempotency), `OomRecoveryHandler` (RAM monitoring and retry logic), and `RecordingStateMachine` (phase transitions and event emission). This separation makes the flow easier to test and audit.

- **Floating UI platform host**: The floating button, floating overlay, and recording pill now share a single `FloatingPlatformHost` that manages the native window lifecycle. Duplicated window-positioning and always-on-top logic has been consolidated into one place.

## 1.2.10

### New Features

- **Minimum system requirements enforced**: WhisPaste now checks available RAM at startup and shows a clear, localized error screen when the system does not meet the 8 GB minimum. Users on underpowered hardware receive a friendly explanation with a link to the FAQ instead of encountering confusing failures mid-session.

### Improvements

- **System requirements updated on website**: The FAQ now lists accurate hardware requirements — 8 GB RAM minimum (enforced), 16 GB recommended, and a detailed GPU VRAM table for each model tier (compact ~300 MB, balanced ~900 MB, premium ~2.6 GB). Apple Silicon unified-memory users are also noted.

## 1.2.9

### Bug Fixes

- **Model load failure loop prevented**: When whisper-server exits with code 3 (failed to load model — typically a corrupted or incompatible model file), WhisPaste now fails fast on all subsequent recording attempts with an actionable "Please re-download" message instead of silently retrying indefinitely. The failed-model flag resets when the user re-downloads the model or changes model/GPU settings.

- **Duplicate error toast eliminated**: The generic "Something went wrong" toast no longer appears alongside the specific "model file corrupted" error message after a code-3 model load failure. The exit handler's specific message now takes priority.

- **Misleading "Could not save audio file" toast fixed**: When a recording pipeline abort is caused by STT startup failure (not by an audio capture issue), WhisPaste now shows the STT error message instead of the confusing "Could not save the audio file" toast.

## 1.2.8

### Bug Fixes

- **GPU → CPU automatic fallback**: When the speech engine crashes with a fatal GPU error (e.g. on older NVIDIA cards like GTX 650 with insufficient VRAM or unsupported compute features), WhisPaste now silently activates CPU mode instead of showing an error dialog. Subsequent recordings automatically use the CPU backend. The fallback resets when the user changes the GPU setting or active model.

- **Flash-attention compatibility**: GTX 650 and other pre-Turing GPUs (pre-sm_75) no longer receive the `--flash-attn` flag, preventing the STATUS_STACK_BUFFER_OVERRUN crash that occurred on these cards at runtime.

- **Waveform animation**: The audio visualiser in the macOS recording overlay is no longer static at high amplitude levels. The per-frame dual-oscillator now applies correct normalisation so the waveform remains visibly dynamic across the full input range.

### New Features

- **Review prompts**: After a configurable number of successful recordings, the app now gently invites users to rate WhisPaste in the App Store / Microsoft Store or star the project on GitHub. The prompt is non-intrusive and only shown once per milestone.

- **Download support modal**: The landing page now shows a friendly post-download modal with low-pressure information about how visitors can support the project (review, star, share).

### Infrastructure

- Supabase security advisor warnings resolved: RLS policies tightened, analytics functions hardened against injection, unused indexes dropped.

## 1.2.7

### Bug Fixes

- **Crash on quit**: Fixed a SIGABRT crash when quitting via the floating button context menu or tray icon. The Drift/SQLite database is now explicitly closed before the window is destroyed, preventing an assertion failure in SQLite's mutex cleanup.

### Screenshots & Store Assets

- Mac App Store screenshots now use the correct **1440×900** resolution (16:10) with authentic macOS window chrome (traffic-light close/minimise/maximise dots). Previously, both stores incorrectly used 1920×1080 Windows-style chrome.
- OG images no longer carry a double window frame — the fake CSS title bar overlay has been removed and border-radius corrected to match real macOS window corners.
- Screenshot pipeline is now fully cross-platform (macOS + Windows): golden tests generate separate `windowsStoreScreenshots/` and `macStoreScreenshots/` sets; the Node compositor renders each store panorama at its native resolution with injected CSS variables.

## 1.2.6

### Improvements

- MSIX package for Microsoft Store now included in release artifacts with correct Partner Center publisher identity.
- MSIX build failure now properly blocks the release workflow instead of being silently ignored.

## 1.2.3

### Bug Fixes

- **History detail editor**: Enter, Backspace, and Delete keys are no longer intercepted by list-level keyboard shortcuts when a text field has focus. All standard editing operations (line breaks, character deletion, cursor movement) now work correctly in the transcript editor, notes field, and tag input.

## 1.2.2

### macOS

- macOS app ships as a native ARM64 DMG with every release — direct download and Gatekeeper instructions included.
- Floating button context menu expanded: open WhisPaste, start recording, view history, open settings, or quit — all accessible via right-click on the floating button.
- macOS menu bar icon now displays correctly and resolves paths reliably across all bundle layouts.

## 1.2.1

Re-release of 1.2.0 with consistent version metadata and release pipeline
stabilization. No user-visible app changes.

## 1.2.0

Complete rewrite: WhisPaste is now a native **Flutter** application replacing the previous Go+WebView2 architecture.

### What's New

- **Native Flutter UI** — truly cross-platform (Windows, macOS, Linux, iOS, Android) with a single Dart codebase
- **SQLite via Drift** — all data stored locally in a type-safe database; no shared config files
- **Riverpod state management** — reactive, testable, maintainable architecture
- **Unified design system** — WpToast notifications, WpDialog modals, consistent theme tokens
- **Recording pill overlay** — slim, elegant status bar during dictation with progress ring
- **Floating button** — always-on-top recording trigger with context menu and multi-monitor support
- **Premium UI** — warm gradients, frosted glass effects, micro-animations, WCAG AA contrast
- **469+ automated tests** — widget, unit, and integration tests with >90% feature coverage

### Architecture

- All Go backend code removed — zero Go dependencies
- CI/CD updated for Flutter-only builds (Windows debug + release)
- Security scanning migrated from golangci-lint/gosec to flutter analyze + gitleaks
- Version centralized in `pubspec.yaml` with `app_info.dart` constant

### Breaking Changes

- Settings are stored in SQLite, not the legacy Go `config.json`
- No Go FFI bridge — all inference via whisper-server subprocess

---

## 1.1.3.0

A polished UI update that makes WhisPaste feel faster, clearer, and more intuitive to use.

### Highlights

- Redesigned dashboard, Smart Mode, and Voice Snippets screens with cleaner cards and better spacing.
- Smart Mode and Voice Snippets now have separate AI provider settings — choose local or cloud independently.
- Silence removal is now a single, unified setting combining voice detection and trim in one step.
- Page transitions are now smooth and animated for a more premium feel.
- Auto-generated tags now use Title Case and block system tags from leaking into your entries.

### UI and copy improvements

- Settings reorganized into clearer sections with more descriptive labels.
- Replaced jargon like "Transcription" and "Diktat" with everyday language throughout.
- All German translations reviewed and aligned with the current English copy.
- Contextual tips explain features where you need them, not just in onboarding.

### Reliability

- Fixed a race condition when switching pages quickly during transitions.
- Version metadata in Windows resources now stays in sync with the release version.
- Silence detection margins tuned to industry best practices (250 ms pre-speech, 350 ms post-speech).

## 1.1.2.0

This release focuses on safer crash reporting, clearer setup flows, and more consistent communication across the app and website.

### Highlights

- Crash reporting now uses a Supabase relay instead of shipping a direct Discord webhook in the app.
- Release builds now require the public crash-relay URL, so packaged builds keep crash delivery working reliably.
- The onboarding try-dictation flow no longer marks onboarding complete too early while transcription is still finishing.

### Privacy and security

- Public builds ship only the relay URL. Private secrets stay server-side in Supabase.
- Crash-message sanitization is stricter for API keys, bearer tokens, and similar secrets.
- Setup docs now clearly explain which Supabase values are public and which must never be committed.

### Product and copy updates

- Website copy now reflects the real product setup more accurately: local transcription or the cloud provider you choose.
- Privacy messaging now explains optional crash reporting more transparently.
- Download and release messaging no longer implies an OpenAI-only setup.

### Reliability

- Release workflow validation now fails early if the crash-relay configuration is missing or malformed.
- Build metadata stays aligned with the release version more consistently.
