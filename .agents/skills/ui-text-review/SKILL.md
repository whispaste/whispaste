---
name: ui-text-review
description: >
  Mandatory UI text tone/quality review. Invoke automatically when UI strings
  are added or changed in l10n.go, 01-translations.js, template.html, or
  website Astro pages. Checks tone, clarity, consistency, and du-form compliance.
---

# UI Text Review Skill — Textqualitätsprüfung

Prüft alle nutzersichtbaren Texte in WhisPaste auf Tonalität, Klarheit,
Konsistenz und korrekte Du-Ansprache. Ergänzt den L10n-Review um eine
inhaltlich-stilistische Qualitätsschicht.

---

## 🎯 Purpose

Ensure every user-facing string in WhisPaste is **approachable, clear,
professional, and premium** — matching the product's identity as a modern,
well-crafted tool for a tech-savvy audience.

---

## 👥 Target Audience & Voice

| Dimension | Definition |
|---|---|
| **Users** | Content creators, developers, students, tech-savvy everyday users |
| **Age range** | Primarily 18–45 |
| **Address form** | Informal **"du"** — NEVER "Sie/Ihnen/Ihr" in direct address |
| **Tone** | Approachable, clear, professional, premium |
| **Vibe** | Apple-level polish meets casual startup friendliness |
| **Conciseness** | Every word must earn its place — concise over verbose |
| **Jargon** | Only domain-specific terms the user would know (e.g. "API-Schlüssel", "Hotkey") |

---

## 🚫 Hard Rules (violations = must fix)

### ❌ NEVER

- **"Sie/Ihnen/Ihr/Ihre/Ihrem/Ihres"** for addressing the user
  (exception: pronoun referring to a noun, e.g. "Die Taste… sie wird…" is fine)
  (exception: `impressum.astro` — legal pages may use formal/neutral German as legally required)
- **Bureaucratic filler**: "hiermit", "diesbezüglich", "zwecks", "gemäß",
  "bezüglich", "hinsichtlich", "dahingehend"
- **Passive voice** when active is clearer
  ("wird heruntergeladen" → "lädt herunter" where possible;
  "wird heruntergeladen…" as a status indicator is okay)
- **Unnecessarily long compounds** when a simpler word exists

### ✅ ALWAYS

- **"du/dein/deine/dir/dich"** for direct address
- **≤ 80 characters** for settings descriptions (aim for, not hard-fail)
- **Sentence case** for labels — not Title Case in German
- **Consistent terminology** — pick one term and stick with it across the app
  (see Terminology Glossary below)

---

## 🎨 Tone Spectrum

| Context | Tone | Example |
|---|---|---|
| **Labels / Headings** | Neutral, concise | "Aufnahmemodus", "Tastenkürzel" |
| **Descriptions / Hints** | Friendly, helpful | "Töne abspielen beim Starten und Stoppen der Aufnahme" |
| **Errors** | Clear, reassuring, actionable | "Kein API-Schlüssel hinterlegt. Du kannst einen unter Einstellungen → Allgemein hinzufügen." |
| **Success messages** | Brief, positive | "Gespeichert ✓", "Kopiert!" |
| **Onboarding** | Warm, encouraging | "Los geht's!", "Dein persönlicher Sprache-zu-Text-Assistent" |
| **Confirmations** | Direct, non-threatening | "Dieses Modell löschen? Du kannst es jederzeit erneut herunterladen." |
| **Button labels** | Short action words | "Speichern", "Testen", "Herunterladen" |

---

## 📂 Scope — Dateien die geprüft werden müssen

| File / Pattern | What to check |
|---|---|
| `l10n.go` | Go-side translations (tray, balloon notifications, errors) |
| `ui_main/scripts/01-translations.js` | Main UI translations EN + DE |
| `ui_main/template.html` | Hardcoded text in HTML |
| `ui_main/scripts/*.js` | Hardcoded strings, toast messages |
| `website/src/scripts/i18n.ts` | Landing page translations EN + DE |
| `website/src/**/*.astro` | Landing page components — hardcoded text, feature descriptions |
| `website/src/pages/impressum.astro` | Legal page — **exempt from du-form** (legal requirement) |
| `website/src/pages/datenschutz.astro` | Privacy policy — du-form applies (modern style) |

---

## ✅ Review Checklist

Run through **every** item. Mark each as ✅ or ❌ in the report.

- [ ] No "Sie/Ihnen/Ihr" forms in direct address
- [ ] No bureaucratic filler phrases
- [ ] Descriptions are concise (aim for ≤ 80 chars)
- [ ] Error messages are actionable (tell user what to do, not just what went wrong)
- [ ] Terminology is consistent (same concept = same word everywhere)
- [ ] Tone matches context (labels = neutral, descriptions = friendly, errors = reassuring)
- [ ] No mixed languages within a single translation (all-German or all-English)
- [ ] Button labels are short action words ("Speichern", "Testen", "Herunterladen")
- [ ] Placeholder text is helpful and realistic (good examples, not lorem ipsum)

---

## 📖 Terminology Glossary

Use these terms consistently across the entire app.

| Concept | DE Term (use this) | ❌ Don't use |
|---|---|---|
| API key | API-Schlüssel | API-Key, Schlüssel |
| Keyboard shortcut | Tastenkürzel | Hotkey (except in branding), Tastaturkürzel |
| Recording | Aufnahme | Aufzeichnung |
| Transcription | Transkription | Abschrift, Übertragung |
| Download | Herunterladen / Download | Runterladen |
| Settings | Einstellungen | Optionen, Konfiguration |
| Overlay | Overlay | Einblendung |
| Smart Mode | Smart-Modus | Intelligenter Modus |
| Template / Preset | Vorlage | Template, Schablone |
| Tag | Tag | Schlagwort, Label |
| System tray | Infobereich | Systemtray, Tray |

---

## 🔍 Common Anti-Patterns

| ❌ Falsch | ✅ Richtig | Regel |
|---|---|---|
| "Geben Sie Ihre API-Key ein" | "Gib deinen API-Schlüssel ein" | Du-Form + Glossar |
| "Hiermit wird die Aufnahme gestartet" | "Aufnahme starten" | Kein Füllwort, aktiv |
| "Bezüglich der Konfiguration…" | "In den Einstellungen…" | Kein Amtsdeutsch |
| "Transkriptionsaufzeichnungsverwaltung" | "Verlauf" | Kein Kompositum-Monster |
| "Ein Fehler ist aufgetreten." | "Transkription fehlgeschlagen. Prüfe deine Internetverbindung." | Actionable Error |
| "Optionen" | "Einstellungen" | Glossar-Konsistenz |
| "AUFNAHME STARTEN" | "Aufnahme starten" | Sentence Case |

---

## 📤 Output Format

Start every review with:

```
## ✍️ UI Text Review Report
**Scope:** [list of files checked]
**Ergebnis:** ✅ Bestanden | ⚠️ Nachbesserung nötig | ❌ Kritische Probleme
```

For each issue found, report:

```
### [SEVERITY] Issue description
**Datei:** `file.js` L42
**Aktuell:** 'Geben Sie Ihre Anweisungen ein...'
**Vorschlag:** 'Gib deine Anweisungen ein...'
**Regel:** Du-Form verwenden
```

**Severity levels:**

| Level | Bedeutung | Aktion |
|---|---|---|
| 🔴 **MUST FIX** | Sie-Form, factual error, wrong language | Sofort fixen |
| 🟡 **SHOULD FIX** | Tone mismatch, unclear wording, glossary violation | Vor Merge beheben |
| 🔵 **CONSIDER** | Polish, conciseness, minor improvement | Optional, empfohlen |

Close the report with:

```
### Zusammenfassung
- 🔴 Must Fix: X
- 🟡 Should Fix: X
- 🔵 Consider: X

**Nächste Schritte:** [Konkrete Handlungsempfehlung]
```

---

## ⚡ Auto-Trigger

This skill should be invoked automatically when:

- Any UI string is added or changed in the scope files listed above
- New features are added that include user-facing text
- After localization work (complements the `l10n-review` skill)

---

## 💡 Hinweise für den Reviewer

- Dieser Skill ergänzt `l10n-review` — jener prüft Vollständigkeit,
  dieser prüft **Qualität und Ton**
- Bei Zweifeln an der korrekten Formulierung: Bevorzuge die kürzere,
  klarere Variante
- Englische UI-Texte werden auf Klarheit und Konsistenz geprüft,
  aber die Du/Sie-Regeln gelten nur für deutsche Texte
- Neue Features brauchen Texte, die dem Tone Spectrum entsprechen —
  nicht einfach technische Beschreibungen durchreichen
