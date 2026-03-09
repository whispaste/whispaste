---
name: quality-audit
description: >
  Comprehensive quality audit for WhisPaste — Go app UI and Astro landing page.
  Evaluates target audience alignment, UX/UI quality, premium polish, cross-surface
  consistency, and content quality. Invoke automatically after UI changes, new
  features, or content updates. Use review.ps1 for periodic full-codebase audits.
---

# Quality Audit Skill — Qualitätsaudit

Umfassende Qualitätsprüfung für beide Oberflächen von WhisPaste: die Go-Desktop-App
(WebView2 UI) und die Astro-Landing-Page. Dieser Skill ist ein **Meta-Orchestrator** —
er ergänzt bestehende Skills um Dimensionen, die sonst nicht abgedeckt werden.

---

## 🎯 Purpose

Ensure WhisPaste delivers a **premium, audience-appropriate experience** across both
surfaces. This skill catches problems that individual review skills miss because they
focus on isolated concerns (text tone, translation completeness, design tokens).

**This skill evaluates holistically:**
- Does the UI make sense to a non-technical assistant AND a power-user developer?
- Do the app and website feel like the same product?
- Does every interaction feel polished and intentional?

---

## 👥 Target Audience

> Menschen, die regelmäßig Gedanken, Notizen, Aufgaben oder Inhalte per Sprache oder
> Text erfassen und daraus schnell strukturierte, weiterverwendbare Ergebnisse machen
> möchten — unabhängig davon, ob sie technisch versiert sind oder nicht — von
> Power-Usern und Entwicklern bis zu Content Creatorn, Assistenzen, Selbstständigen
> und alltäglichen Vielschreibern.

**Key implication**: The audience spans from tech-savvy developers to non-technical
everyday writers. Every UI element, text, and interaction must be understandable
without technical knowledge, while not being patronizing to power users.

### Audience Personas (use for evaluation)

| Persona | Description | Key needs |
|---------|-------------|-----------|
| **Power User** | Developer or tech professional, uses keyboard shortcuts, wants efficiency | Speed, customization, no hand-holding |
| **Content Creator** | Blogger, YouTuber, podcaster — tech-comfortable but not a developer | Quick capture, good formatting, export |
| **Assistant** | Office assistant, captures meeting notes, manages tasks | Simplicity, reliability, clear labels |
| **Self-Employed** | Freelancer, handles own communications, notes, invoices | Professional output, email templates |
| **Everyday Writer** | Student, hobbyist, journal keeper — varies widely in tech skill | Intuitive UI, forgiving errors, clear onboarding |

---

## 📐 Six Review Dimensions

### Dimension 1: Target Audience Alignment (Zielgruppen-Passung)

**Question**: Would ALL personas understand and successfully use this feature?

Check:
- [ ] Labels and descriptions use plain language (no unexplained jargon)
- [ ] Technical terms have context or tooltips (e.g., "API-Schlüssel" → explain what it is)
- [ ] Error messages tell the user what to DO, not just what went wrong
- [ ] Onboarding doesn't assume prior knowledge of speech-to-text workflows
- [ ] Feature names are self-explanatory (not internal codenames)
- [ ] The UI path to core features is discoverable without documentation
- [ ] Settings are grouped by task ("Aufnahme", "Ausgabe") not by technology ("API", "Model")

**Scoring**:
- 🟢 **All personas** can use this without confusion
- 🟡 **Most personas** understand it, but 1-2 would need help
- 🔴 **Only tech-savvy users** would understand this — needs rework

### Dimension 2: UX/UI Quality (Benutzerfreundlichkeit)

**Question**: Is every interaction smooth, predictable, and efficient?

Check:
- [ ] Every clickable element has visible hover/focus feedback
- [ ] Loading states exist for all async operations (no frozen UI)
- [ ] Destructive actions require confirmation
- [ ] Navigation is consistent across all pages
- [ ] Form inputs have visible labels, not just placeholders
- [ ] Error recovery is possible (undo, retry, clear guidance)
- [ ] Keyboard navigation works for all primary flows
- [ ] Touch targets are at least 44×44px equivalent
- [ ] Information hierarchy is clear (headings → content → actions)
- [ ] No dead-end states (user always has a next action available)

**Scoring**:
- 🟢 Fluid, predictable, no friction points
- 🟡 Generally good, 1-2 minor friction points
- 🔴 Confusing flow, missing feedback, or dead-end states

### Dimension 3: Premium Quality Score (Hochwertigkeit)

**Question**: Does this feel like a polished, premium product — or a prototype?

Check:
- [ ] Consistent spacing (matches design tokens in `00-variables.css`)
- [ ] Typography hierarchy is clear and intentional
- [ ] Transitions are smooth (150-300ms, ease-out)
- [ ] No visual glitches (overflow, clipping, misalignment)
- [ ] Icons are consistent (all Lucide SVG, same stroke width, same sizing)
- [ ] Colors follow the design system (no hardcoded hex outside tokens)
- [ ] Empty states have helpful content (not just blank space)
- [ ] Micro-interactions exist (button press feedback, toast animations)
- [ ] Dark mode is fully supported (no white flashes, proper contrast)
- [ ] Responsive behavior is graceful (no broken layouts at any size)

**Scoring**:
- 🟢 Apple-level polish — every detail is intentional
- 🟡 Good quality, but 1-3 rough edges visible
- 🔴 Prototype feel — inconsistent, rough, unfinished

### Dimension 4: Cross-Surface Consistency (Oberflächen-Konsistenz)

**Question**: Do the app UI and website feel like they belong to the same product?

Check:
- [ ] Same brand colors used (Cyan accent: `#22d3ee` / `#06b6d4`)
- [ ] Typography feels related (Segoe UI in app, system fonts on web)
- [ ] Button styles share the same visual language
- [ ] Feature descriptions match between app tooltips and website copy
- [ ] Screenshots/mockups on the website accurately reflect the current app
- [ ] Terminology is consistent (same feature = same name in both places)
- [ ] Tone is consistent (both approachable, both premium, both concise)

**Scoring**:
- 🟢 Seamless — clearly the same product
- 🟡 Related but with visible inconsistencies
- 🔴 Feel like different products — urgent alignment needed

### Dimension 5: Content Quality (Inhaltsqualität)

**Question**: Is every piece of text clear, concise, correct, and on-brand?

Check:
- [ ] Feature descriptions explain WHAT it does AND WHY the user cares
- [ ] Marketing copy (website) is benefit-focused, not feature-focused
- [ ] No placeholder text, lorem ipsum, or TODO markers visible
- [ ] Spelling and grammar are correct in both EN and DE
- [ ] Legal pages (Impressum, Datenschutz) are up to date
- [ ] Version numbers and changelogs are current
- [ ] README accurately reflects the current feature set
- [ ] No broken links or references to removed features

**Scoring**:
- 🟢 Professional, clear, up-to-date content
- 🟡 Mostly good, some outdated or unclear sections
- 🔴 Misleading, outdated, or missing content

### Dimension 6: Code Architecture & Maintainability (Wartbarkeit)

**Question**: Is the codebase structured for long-term maintainability and clean separation of concerns?

This dimension enforces the project's SoC rules from `.github/copilot-instructions.md` and flags refactoring needs proactively.

Check:
- [ ] **File size**: Files exceeding ~300 lines are flagged for split evaluation
- [ ] **Single responsibility**: Each file has one clear domain (Go: file-per-domain pattern)
- [ ] **HTML/CSS/JS separation**: Styles in `styles/`, scripts in `scripts/`, structure in `template.html`
- [ ] **No inline styles or scripts** in template HTML (except where embedded self-containment is required)
- [ ] **DRY across surfaces**: No duplicated logic between Go app and Astro website
- [ ] **Component extraction**: Repeated UI patterns are extracted into reusable components/functions
- [ ] **Go template structure**: Embedded HTML uses `//go:embed` with external files, not string literals
- [ ] **Astro components**: Scoped `<style>` blocks, shared CSS in `src/styles/`, shared JS in `src/scripts/`
- [ ] **Design token consistency**: CSS uses variables from `00-variables.css`, not hardcoded values
- [ ] **Import/dependency hygiene**: No circular imports, no unused imports, minimal coupling between domains

**File-size assessment triggers** (run during full audit — PowerShell):
```powershell
# Go files
Get-ChildItem *.go | ForEach-Object { [PSCustomObject]@{File=$_.Name; Lines=(Get-Content $_ | Measure-Object -Line).Lines} } | Sort-Object Lines -Descending | Select-Object -First 20
# JS files
Get-ChildItem ui_main/scripts/*.js | ForEach-Object { [PSCustomObject]@{File=$_.Name; Lines=(Get-Content $_ | Measure-Object -Line).Lines} } | Sort-Object Lines -Descending
# CSS files
Get-ChildItem ui_main/styles/*.css | ForEach-Object { [PSCustomObject]@{File=$_.Name; Lines=(Get-Content $_ | Measure-Object -Line).Lines} } | Sort-Object Lines -Descending
# Astro files
Get-ChildItem website/src -Recurse -Filter *.astro | ForEach-Object { [PSCustomObject]@{File=$_.FullName.Replace("$PWD\",''); Lines=(Get-Content $_ | Measure-Object -Line).Lines} } | Sort-Object Lines -Descending
```
Flag any file > 300 lines. For files > 500 lines, recommend immediate split.

**Scoring**:
- 🟢 Clean SoC, no oversized files, clear domain boundaries
- 🟡 1-3 files need refactoring, minor SoC violations
- 🔴 Multiple oversized files, mixed concerns, significant tech debt

---

## 📂 Scope — Files to Audit

### Go App (WebView2 UI)

| File / Pattern | What to check |
|---|---|
| `ui_main/template.html` | HTML structure, accessibility, semantic markup |
| `ui_main/styles/*.css` | Design token usage, consistency, responsiveness |
| `ui_main/scripts/*.js` | UX interactions, error handling, loading states |
| `ui_main/scripts/01-translations.js` | Content quality (EN + DE) |
| `l10n.go` | Tray/notification text quality |
| `postprocess.go` | Smart Mode template descriptions and prompts |
| `*.go` (all) | File size, SoC, single responsibility (Dimension 6) |

### Astro Landing Page

| File / Pattern | What to check |
|---|---|
| `website/src/pages/*.astro` | Content quality, SEO, accessibility |
| `website/src/components/*.astro` | Component quality, consistency |
| `website/src/styles/*.css` | Design token alignment with app |
| `website/src/scripts/*.ts` | Interaction quality |
| `website/public/*` | Assets, favicon, screenshots accuracy |

---

## 🔄 Two Operating Modes

### Mode 1: Incremental (Auto-Trigger)

Invoke automatically when:
- UI strings are added or changed
- New pages or components are created
- CSS/design changes are made
- Content is updated (README, website copy, feature descriptions)

**Incremental scope**: Only audit the changed files and their immediate context.
Focus on dimensions most relevant to the change type:
- Text changes → Dimension 1 (Audience) + Dimension 5 (Content)
- UI changes → Dimension 2 (UX) + Dimension 3 (Premium)
- Design changes → Dimension 3 (Premium) + Dimension 4 (Consistency)
- Code/architecture changes → Dimension 6 (Maintainability)

### Mode 2: Full (Periodic via review.ps1)

Run periodically (recommended: before each release, or weekly during active development).

**Full scope**: Audit ALL files in scope. Check ALL 5 dimensions.
Use `.\review.ps1` to collect files and execute the audit automatically.

---

## 📤 Output Format

Start every audit with:

```
## 🏆 Quality Audit Report
**Modus:** Inkrementell | Vollständig
**Scope:** [list of files/components audited]
**Datum:** [date]
```

Score each dimension:

```
### Dimension Scores
| # | Dimension | Score | Issues |
|---|-----------|-------|--------|
| 1 | Zielgruppen-Passung | 🟢/🟡/🔴 | X issues |
| 2 | Benutzerfreundlichkeit | 🟢/🟡/🔴 | X issues |
| 3 | Hochwertigkeit | 🟢/🟡/🔴 | X issues |
| 4 | Oberflächen-Konsistenz | 🟢/🟡/🔴 | X issues |
| 5 | Inhaltsqualität | 🟢/🟡/🔴 | X issues |
| 6 | Wartbarkeit (SoC) | 🟢/🟡/🔴 | X issues |

**Gesamtbewertung:** 🟢/🟡/🔴
```

For each issue found:

```
### [SEVERITY] Issue description
**Dimension:** [1-6]
**Datei:** `file.ext` L42
**Persona betroffen:** [which personas struggle with this]
**Problem:** Precise description
**Vorschlag:** Concrete fix or improvement
```

**Severity levels:**

| Level | Meaning | Action |
|---|---|---|
| 🔴 **BLOCKER** | Persona can't complete the task, or content is wrong/misleading | Fix immediately |
| 🟡 **MAJOR** | Friction, confusion, or quality gap visible to users | Fix before release |
| 🔵 **POLISH** | Works but could be better — refinement opportunity | Backlog |

Close with:

```
### Zusammenfassung
- 🔴 Blocker: X
- 🟡 Major: X
- 🔵 Polish: X

**Prioritized Refactoring List:**
1. [Highest impact fix — which files, what to change]
2. [Second highest]
3. ...

**Nächste Schritte:** [concrete recommendation]
```

---

## 🔗 Complementary Skills (do not duplicate)

This skill works alongside — never replaces — these existing skills:

| Skill | What it covers | Quality Audit adds |
|---|---|---|
| `code-reviewer` | Code quality, security, bugs | Audience alignment, premium polish |
| `l10n-review` | Translation completeness (key parity) | Content quality, tone consistency |
| `ui-text-review` | Text tone, clarity, du-form | Cross-surface consistency, persona evaluation |
| `whispaste-design` | Design tokens, component specs | Premium scoring, holistic UX flow |
| `ui-ux-pro-max` | Generic UI/UX best practices | Project-specific audience personas |
| `web-design-guidelines` | Web interface compliance | App ↔ website consistency |

**Rule**: If an issue is better handled by a complementary skill (e.g., a missing
translation key → `l10n-review`), note it but don't duplicate the full check.
Reference the skill: "→ Delegate to `l10n-review`".

---

## 💡 Review Guidance

- **Be critical.** This audit exists to catch quality gaps before users do.
- **Be specific.** "The button looks off" is not actionable. "The button uses hardcoded
  `#333` instead of `var(--text-primary)`, creating a contrast issue in dark mode" is.
- **Think in personas.** For every issue, ask: which persona is affected? An issue that
  only confuses the Assistant persona is still worth flagging.
- **Prioritize by audience impact.** A confusing onboarding step (affects ALL new users)
  ranks higher than an inconsistent icon (affects aesthetics only).
- **Screenshots matter.** When reviewing the website, note if screenshots/mockups
  are outdated compared to the current app UI.
