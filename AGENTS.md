# WhisPaste — AI Agent Guidelines

WhisPaste is a premium cross-platform dictation app (Flutter, Windows/macOS/Linux/iOS/Android). Local AI: whisper.cpp (STT) + llama.cpp (LLM). State: Riverpod, DB: Drift, Cloud: Supabase.

**Version**: 1.2.0 | **License**: MIT | **Repo**: public on GitHub

---

## Git Workflow
- Branch from `dev`, commit to `dev` only (never main)
- Naming: `feat/<desc>`, `fix/<issue>`, `refactor/<area>`
- Commits: Conventional Commits (`feat(scope): desc`, `fix(scope): desc`)
- Sentry issues referenced in commit messages when resolving bugs
- Commit push: immediately after commit

## Build & Test
```bash
flutter run -d windows
flutter build windows --release
flutter analyze
flutter test
flutter gen-l10n    # After ARB changes
dart format lib/ test/
```

## Design DNA (MANDATORY)
- Premium feel: Steam/gaming dashboards + WhatsApp/ChatGPT conversational UI
- Warm dark theme PRIMARY — light theme available but secondary
- NO glow effects, NO flat SaaS cards, NO Material Icons
- Micro-animations MANDATORY: 300ms fade+slide navigation, instant hover-in, 80ms hover-out
- WCAG AA contrast (4.5:1 body, 3:1 large) — enforced by test
- Mobile-first, responsive: 320px phone → 2560px desktop
- Touch targets ≥ 48×48px everywhere
- "Wow Test": Would a user screenshot and share this?

## i18n / Localization (CRITICAL)
- ALL user-facing text MUST use `L10n.of(context)` + ARB files in `lib/core/l10n/`
- EN + DE required. Run `flutter gen-l10n` after ARB changes
- NO hardcoded English strings in UI code ever
- ARB files: `app_en.arb`, `app_de.arb`
- Generated: `lib/core/l10n/generated/app_localizations.dart`

## Key Conventions
- Design tokens via `WpSpacing`, `WpRadius`, `WpColors` — NEVER hardcode values
- Icons: `lucide_icons_flutter` PRIMARY, `font_awesome_flutter` complementary
- NO glow/neon effects — use layered shadows + subtle gradients
- Riverpod providers for ALL business logic — no `setState` in feature code
- Drift/SQLite for persistence — config via providers
- Services in `lib/services/`, widgets in `lib/widgets/`, features in `lib/features/`

## AI Inference (Core Feature)
- STT: whisper.cpp subprocess (local desktop), cloud providers (all platforms)
- LLM: llama.cpp subprocess (local desktop), cloud providers (planned)
- GPU detection: NVIDIA (CUDA), AMD/Intel (Vulkan), CPU fallback
- Binary download: `lib/services/model_download_service.dart`
- STT service: `lib/services/stt_service.dart`
- Model tiers: compact/balanced/premium (VRAM-based safety warnings, NEVER disabled)

## VRAM / GPU UX (Important)
- Tiers NEVER blocked/disabled — only color-coded risk warnings
- `TierSafety` enum: usable, slowWithoutGpu, vramRisky, vramCritical
- CUDA OOM at runtime → graceful pipeline recovery (NO magic auto-switch)
- User decides: "Try smaller model" or "Switch to Cloud" — explicit choice only

## Error Handling
- All AI operations in try/catch with user-friendly UI feedback
- Sentry for crash reporting (DSN in app_monitoring.dart, GDPR-gated)
- Specific error codes → localized messages via `localizeRecordingError/L10n`
- No swallowed exceptions — log + report + inform user

## Skills Available
- `.agents/skills/whispaste-bug-analysis/` — Sentry crash analysis
- `.agents/skills/release-executor/` — Full release workflow
- `.agents/skills/release-readiness-review/` — Go/no-go pre-release check
- `.agents/skills/supabase-postgres-best-practices/` — Postgres optimization
- Use `skill` tool for bug fixes, release tasks, Postgres work

## Detailed Rules (Lazy-Load on Need)
See `rules/` for deep-dives:
- `rules/architecture.md` — Package structure, Riverpod, Drift, subprocesses
- `rules/security.md` — Zero-trust, Supabase Edge Functions, RLS
- `rules/design.md` — Design tokens, colors, animation timing, UI DNA
- `rules/testing.md` — Test pyramid, must-test清单, patterns
- `rules/ai-inference.md` — STT/LLM pipeline, GPU detection, models

## Quality Gates (Before Commit)
- [ ] `flutter analyze` passes (no errors)
- [ ] `flutter test` passes (or pre-existing failures documented)
- [ ] `flutter build windows --release` succeeds
- [ ] No hardcoded English strings in UI
- [ ] No console.log / debug code left
- [ ] No secrets/API keys committed
- [ ] New features have tests
- [ ] Bug fixes have regression tests
