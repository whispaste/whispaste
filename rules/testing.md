# WhisPaste Testing

## Test Pyramid
Unit (broad) → Widget (medium) → Integration (narrow)

## CI Gate
`flutter test` MUST pass before every push and release. No `continue-on-error`.

## Must-Test清单

### AI Pipeline (Critical — regressions = broken core feature)
- Audio capture + level metering
- STT/LLM provider interface compliance (local + cloud)
- Post-processing preset application
- Dead mic detection guard timing
- Auto-stop on silence
- Model download + SHA256 verification

### Data Integrity (regressions = user data loss)
- History DB CRUD, search, tagging (drift)
- Config save/load + field marshaling
- Export format generation (TXT, MD, CSV, JSON, DOCX)
- Voice shortcuts CRUD

### Design Contracts (regressions = broken theme)
- Theme colors (light + dark)
- Design tokens (spacing, radius, shadows)
- WCAG contrast (CI-enforced)

### Hardware Detection (regressions = wrong binary)
- GPU vendor identification
- VRAM threshold checks
- Binary asset recommendation
- Preflight hardware checks

### Widget Contracts (regressions = broken navigation)
- Sidebar nav items + selection callback
- FAB tap + icon
- Empty state rendering
- Section header + content
- Settings all sections

## Test Conventions
- Naming: `{source_file}_test.dart`
- Path mirrors lib/: `lib/core/theme/colors.dart` → `test/core/theme/colors_test.dart`
- Mocking: `mocktail` only (NOT mockito, no codegen)
- Shared fixtures: `test/fixtures/test_helpers.dart`
- Descriptive names: `'Dark theme background is warm navy (#131826)'`
- `makeTestable()` wrapper for all widget tests

## When to Add Tests
- New feature: widget test + unit test (BEFORE marking done)
- Bug fix: regression test MANDATORY
- New widget: widget test
- New provider: interface compliance test
- Config field: marshal/unmarshal test
