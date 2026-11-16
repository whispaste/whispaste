# Master-Prompt: Illustrationsstil Scherenschnitt-Ebenen

Festgelegt 2026-11-15 (Maintainer), Issue #172. Gilt zusammen mit `STYLE.md`.

## 1. Generator und Parameter

- Codex CLI, eingebautes Bildwerkzeug (Projektregel: Bilder nur per Codex CLI), aus diesem Ordner:
  `codex exec -s read-only --skip-git-repo-check -i refs/palette-swatch.png -i refs/kopf-kulissen.png -i refs/fuss-plattformen.png "<Anweisung>" < prompt.txt`.
  Modell laut Lauf-Log (2026-11: `gpt-6-astra`, Denkaufwand `medium`). Keine anderen Bilddienste.
- Referenzbilder in `refs/`: Palettenstreifen aus den Tokens (`palette-swatch.png`, nur Farbe) und zwei freigegebene
  Bilder des Stils (`kopf-kulissen.png` dunkel mit Schnittband, `fuss-plattformen.png` hell mit Halbkreis, je 1200 px).
- **Seed:** nicht verfügbar; das Werkzeug nimmt keinen an und gibt keinen aus. Nachstellbar sind Stil und Bausteine,
  nicht das Pixel. Festgehalten je Bild: Prompt-Datei, Referenzbilder, Session-ID des Laufs, Datum.
- Ein freigegebenes Bild ist selbst die Referenz; für Varianten wird es per `-i` angehängt und nur `{MOTIV}` geändert.

## 2. Vorlage

Platzhalter: `{ASSET}` Einsatzart und Maß, `{MOTIV}` Szene aus Bausteinen (`STYLE.md` §6), `{HINTERGRUND}` einfarbige
Fläche mit Hex, `{FORMAT}` Seitenverhältnis und Rand, `{STILBLOCK}` fester Stilblock (§3),
`{FIGURENREGELN}` (§4, entfällt ohne Figur), `{PALETTE}` (§5), `{NEGATIVLISTE}` (§6).

```
Use case: stylized-concept
Asset type: {ASSET}
Primary request: {MOTIV}
Scene/backdrop: {HINTERGRUND}
Style/medium: {STILBLOCK}
{FIGURENREGELN}
Composition/framing: {FORMAT}
Lighting/mood: flat and even, no light direction, calm, friendly, quiet
Color palette: use ONLY these hex colours: {PALETTE}. The attached palette image is the exact colour reference (colours only, not composition).
Materials/textures: none, flat vector-like fills with crisp edges
Text (verbatim): none. No letters, no digits, no words, no logos, no brand marks anywhere in the image.
Constraints: one single image; flat surfaces only; generic devices without manufacturer detail; one main motif with at most three main elements; no decoration beyond the motif.
Avoid: {NEGATIVLISTE}
```

## 3. Stilblock (fest, wortgleich verwenden)

```
Paper-cut silhouette layers, strictly three flat layers and nothing else. Layer 1 (back): at most one smooth horizontal wave band, a single gentle sine-shaped silhouette with crisp straight-cut edges; no blobs, no amoeba shapes. Layer 2 (middle): one carrier shape, a rounded rectangle card or a single full-radius capsule. Layer 3 (front): only the motif elements (waveform pill, text bars, cursor, keys). Optional decor from this list only: one half circle at an edge, one small amber dot. Layers are separated by colour steps only. No shadows, no gradients, no transparency, no outlines, no brush texture, no grain.
```

## 4. Figurenregeln (fest)

```
Figure rules: adults only, simplified and calm, about five head heights tall when shown full, otherwise shown from the waist up. The head is a plain shape with NO facial features at all (no eyes, no mouth, no nose, no eyebrows, no hair detail beyond one flat hair shape). Hands are simple mittens (one rounded shape, thumb at most hinted), never detailed fingers. Skin and clothing use only palette colours: head and hands Glacier grey #BFCFE3 or slate #52607A, clothing Navy #122247 or Glacier #D6E2F0. Relaxed, natural posture, no exaggerated gestures, no props in the hands, no speech bubbles.
```

## 5. Palette (fest)

```
Navy #0B122A, Navy #122247, Glacier #F3F7FB, Glacier #E6EEF7, Glacier #D6E2F0, Glacier grey #BFCFE3, slate #52607A, Cyan #1ACBE9, Amber #FFB547, white #FFFFFF
```

## 6. Negativliste (fest)

```
thick black outlines, wobbly hand-drawn or sketchy lines, cream, beige, paper or yellowish backgrounds, pastel pink, lilac or lavender, orange clothing, quirky cartoon characters, moustaches, bow ties, expressive faces, speech bubbles, magic or circus props, clocks, gradients, glow, drop shadows, contact shadows, inner shading, 3D or isometric perspective, texture, grain, noise, brush strokes, emoji, stock-photo look, watermark, logos, brand marks, any letters, digits or pseudo-writing
```

## 7. Beispiel-Motive

| Motiv | `{ASSET}` | `{HINTERGRUND}` |
|---|---|---|
| kopf: Dictating instead of typing. A person sits relaxed and upright beside a generic laptop, hands resting in the lap, not touching the keyboard. Next to the head floats a horizontal waveform pill in Cyan #1ACBE9 (a capsule with 7 to 9 vertical rounded bars of varying height). From the pill, three short text bars travel to the right into a white document card on the laptop screen, which ends with a small vertical cursor bar. One small Amber #FFB547 dot marks the cursor. The keyboard is a row of plain rounded keys without any symbols. | newsletter header illustration, landscape 2:1 (1200 x 600 px) | single flat Navy #0B122A field, edge to edge |
| fuss: On every computer. Three generic computers side by side on one line: a laptop, a desktop monitor on a stand, a second laptop. Each screen shows the same small Cyan #1ACBE9 waveform pill. No people. No manufacturer details, no logos, no ports, no notch. | newsletter footer illustration, wide 3:1 (1200 x 400 px) | single flat Glacier #F3F7FB field, edge to edge |
| leerzustand: No recordings yet. A single white card with three empty placeholder rows. Above the card a resting waveform pill in Glacier grey #BFCFE3 with low flat bars (no Cyan, nothing is recording). One small Amber #FFB547 dot at the start of the first row. No people. Quiet and sparse. | empty-state illustration for a desktop app, square 1:1 (800 x 800 px) | single flat Glacier #E6EEF7 field, edge to edge |
| privat: Your dictations stay on your computer. A generic desktop monitor on a stand; its screen shows a Cyan #1ACBE9 waveform pill. Behind the monitor one large half circle in Navy #122247 rises from the bottom edge (back layer). One small Amber #FFB547 dot near the upper right of the screen. No people, no cloud, no network or lock symbols. | website section illustration, landscape 16:10 (1600 x 1000 px) | single flat Navy #0B122A field, edge to edge |

## 8. Ablauf für ein neues Bild

1. `{MOTIV}` aus Bausteinen formulieren (höchstens drei Hauptelemente, eine Pille, ein Bernstein-Akzent).
2. Prompt aus der Vorlage bauen und als Datei neben dem Bild ablegen.
3. Erzeugen; das Bild aus dem Ausgabeordner des Werkzeugs übernehmen, Session-ID notieren.
4. Prüfliste `STYLE.md` §11 im Kontaktbogen neben `refs/`. Ausreißer höchstens einmal neu erzeugen; verworfene Fassungen aufheben.
5. Für Website/App als SVG mit Token-Farben nachzeichnen.
