# Design System Master File — WhisPaste Landing Page

> **LOGIC:** When building a specific page, first check `design-system/whispaste/pages/[page-name].md`.
> If that file exists, its rules **override** this Master file.
> If not, strictly follow the rules below.
>
> **⚠️ Note:** This file reflects the **actual implemented** WhisPaste design system.
> See also `.agents/skills/whispaste-design/SKILL.md` for the full reference including app-UI tokens.

---

**Project:** WhisPaste
**Updated:** 2026-03-04
**Category:** Desktop App Landing Page (Astro + Tailwind)
**Style:** Dark-Mode-First, Minimalist Premium, Cyan Accent

---

## Global Rules

### Color Palette (Tailwind `@theme` in `global.css`)

| Role                  | Dark Mode Hex | Light Mode Hex | Tailwind Variable                   |
| --------------------- | ------------- | -------------- | ----------------------------------- |
| Primary Accent        | `#22D3EE`     | `#0891B2`      | `--color-brand-cyan`                |
| Secondary Accent      | `#0E7490`     | `#0E7490`      | `--color-brand-teal`                |
| Hero Background       | `#15171b`     | `#F1F5F9`      | `--color-brand-darker`              |
| Section Background    | `#1E2026`     | `#F8FAFC`      | `--color-brand-dark`                |
| Card Background       | `#252830`     | `#FFFFFF`      | `--color-brand-card`                |
| Borders / Dividers    | `#2e3138`     | `#E2E8F0`      | `--color-brand-border`              |
| Primary Text (dark)   | `#F1F5F9`     | `#1E293B`      | Tailwind `text-white` / override    |
| Secondary Text (dark) | `#94A3B8`     | `#64748B`      | Tailwind `text-gray-400` / override |

**Color Notes:** Cyan/Teal als einzige Akzentfarbe. Kein sekundärer CTA-Akzent. Kein Orange.

### Typography

- **Heading Font:** Inter
- **Body Font:** Inter

### Typography

- **Font Stack:** System-UI / Tailwind Default (kein separater Google Fonts Import nötig)
- **Optional Inter:** `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap')`
- **Mood:** minimal, clean, professional, dark, premium

| Ebene          | Größe (Tailwind)        | Gewicht               | Verwendung             |
| -------------- | ----------------------- | --------------------- | ---------------------- |
| Hero Headline  | `text-5xl` / `text-7xl` | `font-bold` (700)     | Haupt-Schlagzeile      |
| Section Title  | `text-3xl` / `text-4xl` | `font-semibold` (600) | Abschnittstitel        |
| Card Title     | `text-xl` / `text-2xl`  | `font-semibold`       | Feature-Titel          |
| Body           | `text-base` / `text-lg` | `font-normal` (400)   | Beschreibungen         |
| Small / Labels | `text-sm`               | `font-medium` (500)   | Tags, Badges, Captions |

### Spacing Variables (Tailwind Standard)

| Tailwind Token    | Value            | Usage                    |
| ----------------- | ---------------- | ------------------------ |
| `p-1` / `gap-1`   | `4px`            | Tight inline gaps        |
| `p-2` / `gap-2`   | `8px`            | Icon gaps                |
| `p-4` / `gap-4`   | `16px`           | Standard padding         |
| `p-6` / `gap-6`   | `24px`           | Card padding             |
| `p-8`             | `32px`           | Section inner padding    |
| `py-16` / `py-20` | `64px` / `80px`  | Section vertical padding |
| `py-24` / `py-32` | `96px` / `128px` | Hero vertical padding    |

### Hero Gradient

```css
/* Dark Mode: bright cyan left → deep teal right */
background-image: linear-gradient(
  135deg,
  #22d3ee 0%,
  #0e7490 50%,
  #22d3ee 100%
);

/* Light Mode (html.light .hero-gradient): */
background-image: linear-gradient(
  135deg,
  #0891b2 0%,
  #0e7490 50%,
  #0891b2 100%
);
```

### Shadow Depths (Website)

| Level         | Value                          | Usage                       |
| ------------- | ------------------------------ | --------------------------- |
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,0.05)`   | Subtle lift                 |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.1)`    | Cards, buttons              |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.1)`  | Modals, dropdowns           |
| `--shadow-xl` | `0 20px 25px rgba(0,0,0,0.15)` | Hero images, featured cards |

---

## Component Specs (Tailwind Classes)

### Download CTA Button (Primary)

```html
<!-- Cyan gradient, white text, glow on hover -->
<a
  class="inline-flex items-center gap-2 px-6 py-3 rounded-xl
          bg-gradient-to-r from-brand-cyan to-brand-teal
          text-white font-semibold text-base
          shadow-lg shadow-brand-cyan/20
          hover:shadow-brand-cyan/40 hover:scale-[1.02]
          transition-all duration-200 cursor-pointer"
>
  Download für Windows
</a>
```

### Secondary / Ghost Button

```html
<a
  class="inline-flex items-center gap-2 px-6 py-3 rounded-xl
          border border-white/10 text-gray-300
          hover:border-brand-cyan/40 hover:text-white
          transition-all duration-200 cursor-pointer"
>
  Mehr erfahren
</a>
```

### Feature Card

```html
<div
  class="bg-brand-card/60 border border-white/[0.06] rounded-2xl p-6
            hover:border-brand-cyan/20 hover:shadow-lg hover:shadow-brand-cyan/[0.05]
            transition-all duration-200"
>
  <!-- SVG Icon (Lucide, 24px, currentColor, text-brand-cyan) -->
  <!-- Title: text-lg font-semibold text-white -->
  <!-- Description: text-gray-400 text-sm leading-relaxed -->
</div>
```

### Section Background Alternation

```
Hero        → bg-brand-darker  (#15171b)
Features    → bg-brand-dark    (#1E2026)
How It Works→ bg-brand-darker
Testimonials→ bg-brand-dark
CTA Banner  → bg-gradient-to-r from-brand-cyan/10 to-brand-teal/10
Footer      → bg-brand-darker  border-t border-brand-border
```

---

## Style Guidelines

**Style:** Minimalist Premium Desktop App Landing

**Keywords:** Dark, professional, single accent color (cyan), no decorative clutter, screenshots as hero, features with SVG icons, clear download CTA

**Key Effects:**

- Cyan-glow hover auf Feature-Cards: `shadow-brand-cyan/[0.05]`
- Hero-Gradient: Cyan diagonal über App-Screenshot-Mockup
- Fade-in via Intersection Observer (progressive reveal)
- Subtle border-color transitions beim Hover

### Seitenstruktur (section order)

1. **Nav** — sticky, blur, Brand-Logo + Theme-Toggle
2. **Hero** — Headline + Subline + Download-CTA + App-Screenshot
3. **Features** — 6 Feature-Cards mit Lucide-Icons
4. **How It Works** — 3-Schritt-Ablauf mit Nummern
5. **Download / CTA** — Großes Banner mit Download-Button
6. **Footer** — Links (Impressum, Datenschutz) + Copyright

---

## Anti-Patterns (Do NOT Use)

- ❌ **Orange oder andere sekundäre Akzentfarben** — nur Cyan/Teal
- ❌ **Emojis als Icons** — ausschließlich Lucide SVG (`currentColor`, `stroke-width="1.5"`)
- ❌ **Fehlender `cursor-pointer`** — alle klickbaren Elemente
- ❌ **Shift-Hover** — kein Layout-Shift durch `scale > 1.05`
- ❌ **Zu niedriger Kontrast** — mind. 4.5:1 im Light Mode
- ❌ **Instant-State-Changes** — immer `transition-all duration-200` minimum
- ❌ **Light-Mode vergessen** — alle Dark-Variablen haben entsprechende `html.light`-Overrides in `global.css`

---

## Pre-Delivery Checklist

Before delivering any UI code, verify:

- [ ] Ausschließlich Lucide SVG-Icons (`currentColor`, keine Emojis)
- [ ] `cursor-pointer` auf allen klickbaren Elementen
- [ ] Hover-States mit `transition-all duration-200` minimum
- [ ] Light-Mode getestet (`html.light` Overrides greifen korrekt)
- [ ] Kontrast im Light-Mode: text mind. 4.5:1
- [ ] Focus-States sichtbar für Keyboard-Navigation
- [ ] `prefers-reduced-motion` respektiert (Tailwind: `motion-safe:`)
- [ ] Responsive: 375px, 768px, 1024px, 1440px
- [ ] Kein horizontaler Scroll auf Mobile
- [ ] Keine Inline-Styles mit mehr als 2 Eigenschaften
