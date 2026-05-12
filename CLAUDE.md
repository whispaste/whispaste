# CLAUDE.md

Guidance for AI coding agents working in this repository. Single source of truth — no AGENTS.md, no rules/ deep-dives. Detail values live in the code (`tokens.dart`, `colors.dart`, table definitions). Version is read from `pubspec.yaml`.

## Project

**WhisPaste** — cross-platform dictation app (Windows/macOS/Linux, iOS/Android planned). Hotkey → speak → pasted into any app. Local STT via whisper.cpp, cloud STT via OpenAI/Groq/Deepgram. Flutter/Dart, MIT, public repo.

## Stack

| Area | Choice |
|---|---|
| UI / logic | Flutter, Dart |
| State | Riverpod 3.x (`Notifier<T>`) — no `setState` in feature code |
| Persistence | Drift (SQLite) + FTS5; `flutter_secure_storage` for API keys |
| Backend | Supabase PostgREST (feedback) — **no Edge Functions** |
| Crash reporting | Sentry (`de.sentry.io`, EU region) |
| STT local | whisper.cpp subprocess (CUDA / Vulkan / CPU) |
| Icons | `lucide_icons_flutter` primary, `font_awesome_flutter` complementary |

## Commands

```bash
flutter pub get
flutter run -d windows                # or -d macos
flutter analyze --fatal-infos
flutter test                          # excludes golden by default
flutter test --tags=golden            # widget/screenshot tests
flutter gen-l10n                      # after editing app_*.arb
dart format lib/ test/
flutter build windows --release --no-tree-shake-icons
flutter build macos   --release --no-tree-shake-icons \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Supabase values live in `.env` (gitignored). For local runs pass them via `--dart-define`.

## Layout

```
lib/
  main.dart, app.dart
  core/         config, data (Drift), l10n, logging, recording, theme
  features/    about, analytics, feedback, history, onboarding, recording,
                replacements, settings
  services/    recording_orchestrator, stt_service, audio_service,
                model_download_service, hotkey_service, tray_service,
                desktop_paste/, floating_button/, floating_overlay/, ...
  widgets/     shared UI
test/          mirrors lib/; screenshots/ for goldens; fixtures/ for helpers
supabase/migrations/   SQL only — no functions deployed
```

## Recording pipeline

`RecordingOrchestrator` drives the flow:
hotkey → capture (amplitude stream) → WAV temp → ensure STT server → transcribe → save to Drift → desktop paste → cleanup.

State machine `RecordingPhase`: `idle → recording → transcribing → processing → done|error`.
OOM/STT failure → up to 3 retries; GPU crash → CPU fallback (`SttStatus.cpuFallbackActive`). All errors localized via `L10n`.

## Conventions

- **Riverpod everywhere.** Providers at feature/service level; `ref.watch` reactive, `ref.read` one-shot.
- **Design tokens only.** Use `WpSpacing`, `WpRadius`, `WpColors`, `WpMotion`. Never hardcode pixel/color/duration values.
- **Localization.** All user-facing strings via `L10n.of(context).x`. Edit `lib/core/l10n/app_en.arb` and `app_de.arb`, then `flutter gen-l10n`. Generated file (`generated/app_localizations.dart`) is not edited by hand.
- **Drift migrations.** Additive only. Never destructive without an explicit migration path.
- **Secrets.** API keys via `flutter_secure_storage` (not plain Drift). Never commit credentials.
- **Tests.** New feature → unit + widget test. Bug fix → regression test. Mocking via `mocktail`. Path mirrors `lib/`.
- **Touch targets ≥ 48×48.** WCAG AA contrast (enforced by tests). No glow effects, no flat SaaS cards.
- **Icons.** Lucide first; Font Awesome only when Lucide lacks the symbol. No Material Icons.

## Security

- Zero-trust client: never enforce gating/quota/permissions in Flutter — server-side only (Supabase RLS).
- Feedback: rate-limited (3/24h per device) + 1000-char cap, enforced by DB trigger.
- Sentry: 4-layer PII scrub (consent gate, cascade guard, `beforeSend` regex, SDK config). Device ID is `md5(hostname)`.
- Sentry DSN is the only credential safe to embed; everything else via `--dart-define`.

## Git workflow

- Branches: `main` (stable), `dev` (development). No others.
- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- **Solo project — never open GitHub PRs.** Merge `dev → main` locally, push.
- Hooks: run `scripts/install-hooks.sh` once after clone (analyze, secret scan, protected-file check).

## Quality gates before commit

- [ ] `flutter analyze --fatal-infos` clean
- [ ] `flutter test` green (or pre-existing failures noted)
- [ ] No hardcoded UI strings (EN/DE both updated, `flutter gen-l10n` run)
- [ ] No `print` / debug code
- [ ] No secrets staged
- [ ] New behaviour has tests; bug fix has regression test

## Versioning & release

- Version source: `pubspec.yaml` (`version:` field) + `lib/core/app_info.dart` + `msix_version`. Keep all three in sync.
- Tag `vX.Y.Z` on `main`, push → CI builds Windows/macOS, creates GitHub release, Sentry release, triggers website redeploy.
- Required secrets (set via `scripts/setup-gh-secrets.py`): `SENTRY_AUTH_TOKEN`, `SENTRY_DSN`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Optional: `MSIX_PUBLISHER`, `OPENAI_API_KEY` (release-notes enhancement).

## Common tasks

**Add a settings field** — extend `AppSettings` (`fromDb`/`toDb`), add Drift column + migration, build section widget in `lib/features/settings/sections/`, wire via `settingsScrollTargetProvider`, localize, `flutter gen-l10n`.

**Add a UI page** — new folder under `lib/features/`, register in `wpNavItems()` and `wpPageWidgets` in `app.dart`.

**Debug STT** — check `whispaste.log` for `[STT]` entries, inspect `SttStatus`, verify GPU detection in `hardware_info_service.dart`. CPU fallback is automatic on GPU crash.

**Test Drift queries** — `HistoryDatabase.forTesting(NativeDatabase.memory())` for in-memory DB.

## Hard requirement

App needs ≥ 8 GB RAM (threshold 7500 MB in `hardware_info_service.dart`). Below that, `InsufficientRamScreen` shows and the app exits.

## Agent skills

### Issue tracker

**Local markdown only — never GitHub.** Issues and PRDs live under `.scratch/<feature-slug>/` (gitignored). Never call `gh issue create` or push issue content to GitHub. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each markdown issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CLAUDE.md` (this file) is the source of truth; `CONTEXT.md` and `docs/adr/` are optional and gitignored when present. See `docs/agents/domain.md`.
