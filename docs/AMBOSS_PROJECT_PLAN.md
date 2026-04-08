# Projekt-Plan

> Automatisch gepflegt von Amboss. Letzte Aktualisierung: 2026-04-08 15:26

## Projekt-Übersicht
WhisPaste — cross-platform Flutter dictation app (Windows, macOS, Linux, iOS, Android). Speech-to-text via whisper.cpp subprocess, LLM post-processing via llama.cpp/cloud APIs, SQLite via Drift, Riverpod state management. Migrating from Go v1.1.3 to Flutter v1.2.0.

## Architektur-Entscheidungen

- 2026-04-08: Factory Reset as separate option from Reset to Defaults — Reset to Defaults clears settings/keys/analytics only; Factory Reset deletes ALL data, models, logs, and files for a true zero-state.
- 2026-04-08: Go v1.1.3 → Flutter migration runs in `_reconcileGoSchema()` during Drift's `beforeOpen` — each schema fix is independent (not all-or-nothing), timestamps use COALESCE for NULL safety, migration count exposed for user feedback toast.
- 2026-04-08: Provider invalidation after factory reset happens in UI layer (cloud_advanced_section.dart), not settings_provider.dart, to avoid circular imports between core/ and features/.

## Aktuelle Aufgaben & Nächste Schritte

- [x] Wire up migration toast for first launch after Go→Flutter upgrade (integrated in app.dart initState)
- [x] Onboarding UX overhaul — quality tiers, download fixes, settings unification, visual polish
- [ ] Push main to origin (31+ commits ahead)
- [ ] Merge `amboss/onboarding-ux-overhaul` branch to main (4 commits ahead)
- [ ] Manual testing: Factory Reset button, Reset to Defaults, Go migration path
- [ ] Manual testing: Full onboarding flow end-to-end (welcome → mic → model download → ready)
- [ ] Consider centralizing reset orchestration into a single service (currently split between UI + provider)

## Bekannte Probleme & Technische Schulden

- SttService.stop() is synchronous and fire-and-forget (process.kill + non-awaited exitCode timeout). Factory reset adds 800ms delay as workaround. A proper `stopAndAwaitExit()` Future would be cleaner. | Entdeckt: 2026-04-08 | Priorität: Niedrig
- JSON tag migration guard is table-level (checks if entry_tags is empty). Partial migrations where some tags already exist but others don't won't re-migrate. Edge case is extremely unlikely. | Entdeckt: 2026-04-08 | Priorität: Niedrig
- Deferred secure-key loading in settings_provider could theoretically race with factory reset. Guard with generation token if it becomes an issue. | Entdeckt: 2026-04-08 | Priorität: Niedrig
- No automated tests for factoryReset() or Go schema reconciliation edge cases. | Entdeckt: 2026-04-08 | Priorität: Mittel

## Gelernte Muster & Konventionen

- `WpToast.show()` for all user feedback (success, error, warning, info) — slides in from bottom-right
- `showWpConfirmDialog()` for destructive actions — centered modal with frosted backdrop
- `_tryDeleteDir/_tryDeleteFile` pattern for best-effort cleanup with logging (swallows errors)
- Settings STT section: replaced 6-model quality dropdown with tier-based SttModelManager + inline cloud API key when cloud provider selected
- Download progress from model_download_service uses int 0-100 (not 0.0-1.0) — always normalize with `/ 100.0` in UI
- `modelsForTier()` must sort descending by `sizeBytes` to return best quality first
- `recommendTier()` VRAM thresholds: ≥1536MB → premium, ≥512MB → balanced, else compact
- Flag SVGs for language selector live in `assets/flags/` (us.svg, de.svg)

## Letzte Änderungen

| Datum | Aufgabe | Größe | Branch | Zusammenfassung |
|-------|---------|-------|--------|-----------------|
| 2026-04-08 | onboarding-ux-overhaul | G | amboss/onboarding-ux-overhaul | 14 fixes: download progress/error/tier bugs, FAB gate, duplicate logo, skip-drag, close button, settings STT unification, country flags, theme toggle shadow, mic step gate |
| 2026-04-08 | fts5-rebuild-fix | K | main | Remove FTS5 'rebuild' from deleteAllData — contentless FTS5 table forbids it; triggers handle cleanup |
| 2026-04-08 | factory-reset-migration | G | main | Factory Reset + Go migration fixes + adversarial review fixes (COALESCE, transaction, provider invalidation, async toast) |
