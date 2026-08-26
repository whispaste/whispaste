# OG / Social-Share Cards — Source Templates

Diese HTML-Dateien sind die **bearbeitbare Quelle** für die Open-Graph-Bilder
(`website/public/og-image-de.png` / `og-image.png`), die bei Links zu whispaste.de
als Vorschau-Karte erscheinen (Twitter, WhatsApp, Slack, iMessage, …).

## Aufbau
- `og-card-de.html` → `public/og-image-de.png`  (DE Pages)
- `og-card-en.html` → `public/og-image.png`     (EN Pages)
- 1200×630 px (der OG-Standard), Dark/Teal-Brand, Fraunces-Serif-Tagline,
  App-Icon-Halo + Waveform-Motiv, 3 Plattform-Pills (Windows · macOS · Linux).
- Asset-Refs sind root-absolut (`/fonts/…`, `/wordmark-light.png`, …) und
  nutzen **dieselben** Self-Host-Fonts/Assets wie die Live-Site → 1:1-Brand-Konsistenz.

## Regenerieren (manuell, nach Design- oder Copy-Änderung)

Voraussetzung: Dev-Server läuft (`npm run dev` im `website/`-Verzeichnis) und ein
Headless-Browser/Screenshot-Tool (z. B. Playwright).

```bash
cd website
npm run dev &                                 # :4321
# Temporär unter Public legen, damit der Dev-Server sie ausliefert:
cp scripts/og-card/og-card-de.html public/og-card-render.html
cp scripts/og-card/og-card-en.html public/og-card-render-en.html

# Bei exakt 1200×630 (DPR 1) screenshoten, z. B. via Playwright:
#   page.setViewportSize({width:1200,height:630})
#   page.goto('http://localhost:4321/og-card-render.html'); await document.fonts.ready
#   page.screenshot({path:'public/og-image-de.png', type:'png'})   # css scale
#   (analog -en → public/og-image.png)

rm public/og-card-render.html public/og-card-render-en.html   # Temps entfernen!
```

**Wichtig:** Die Render-HTMLs nur temporär in `public/` ablegen und nach dem
Screenshot wieder löschen — sie dürfen nicht ausgeliefert werden. Die kanonischen
Assets sind ausschließlich `og-image-de.png` und `og-image.png`.

## Bezug zur Site
- Tagline aus `src/scripts/i18n.ts`: `hero.title1/2` (DE: „Sprechen statt
  tippen." / EN: „Speak instead of typing.").
- Meta-Wiring: `src/layouts/Layout.astro` (`ogImage = lang === "en" ? "/og-image.png" : "/og-image-de.png"`).
- Marken-Tokens: `src/styles/global.css` (`--color-brand-cyan/teal/darker`,
  `--font-serif`/`--font-display`).
