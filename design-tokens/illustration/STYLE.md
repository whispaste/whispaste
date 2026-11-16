# WhisPaste-Illustrationsstil

Festgelegt 2026-11-15 (Maintainer), Issue #172. Richtung: **Scherenschnitt-Ebenen** (§3). Prompt-Vorlage:
`master-prompt.md`. Referenzbilder: `refs/` (Palettenstreifen, ein Kopf, ein Fuß).

## 1. Zweck

Ein eigener, wiedererkennbarer Bildstil für Newsletter (Kopf, Fuß, Abschnitte), Website (Abschnitte, leere Zustände)
und App (Leerzustände, Onboarding). Der Stil ist per Bildmodell nachstellbar (`master-prompt.md`) und für Website und
App als Vektor nachzeichenbar. Er folgt der Optik des Nordsterns: flach und ruhig, Tiefe über Fläche, kein Glow, kein
Verlauf, keine Schatten.

Grundsatz: Das Bild begleitet, es trägt die Aussage nicht. Aussage, Titel und Handlung stehen als Text im Layout
(ARB in der App, HTML auf der Website und im Newsletter), nie im Bild.

## 2. Palette (nur Tokens aus `primitives.tokens.json`)

| Rolle im Bild | Token | Hex |
|---|---|---|
| Dunkle Bühne | `color.navy.900` | `#0B122A` |
| Ton auf Dunkel, Kleidung | `color.navy.800` | `#122247` |
| Heller Grund | `color.glacier.50` | `#F3F7FB` |
| Heller Grund (Leerzustand) | `color.glacier.100` | `#E6EEF7` |
| Linien und Flächen auf Dunkel | `color.glacier.200` | `#D6E2F0` |
| Ruhe-Pille, Kopf und Hände | `color.glacier.300` | `#BFCFE3` |
| Linien und Zeilen auf Hell, Kopf und Hände | `color.glacier.600` | `#52607A` |
| Aktion und Aufnahme | `color.cyan.400` | `#1ACBE9` |
| Akzent | `color.amber.400` | `#FFB547` |
| Karten | `color.white` | `#FFFFFF` |

- Cyan nur für Aktion und Aufnahme (Wellenform-Pille, aktive Teile), nie als Dekorfläche.
- Bernstein genau einmal je Motiv (Punkt oder kurze Markierung).
- Verboten: Creme, Papier- und Gelbtöne (auch `coffee.*`), Pastell, Rosa, Lila, Status-Rot und -Grün.
- Kontrast: Bildteile, die Bedeutung tragen, erreichen 3:1 zum Grund (WCAG 1.4.11).

## 3. Formensprache: Scherenschnitt-Ebenen

Flache Formen wie geschnittenes Papier, in genau drei Ebenen, getrennt nur durch Farbwechsel. Wortgleich mit dem
Stilblock in `master-prompt.md` §3. Neue Bilder passen ohne Nachjustieren zu den vorhandenen, weil Ebenen und Dekor
festgelegt sind.

### 3.1 Festes Dekor-Vokabular (nur diese Formen, sonst nichts)

| Id | Form | Regel |
|---|---|---|
| **D1 Schnittband** | eine einzige ruhige Welle, sinusartige Silhouette über die ganze Bildbreite | höchstens eines je Bild, im unteren oder mittleren Drittel, höchstens 40 % der Bildhöhe, Kante gerade geschnitten; läuft randlos vom linken bis zum rechten Bildrand, auch hinter Karten, beginnt oder endet nie im Bild (sonst verwerfen) |
| **D2 Halbkreis** | ein Halbkreis am Bildrand oder hinter dem Motiv | höchstens einer je Bild, nur als Gegengewicht zum Motiv |
| **D3 Markierung** | ein Bernstein-Punkt | genau einer je Motiv, Durchmesser etwa 2 % der Bildbreite |
| **B Bausteine** | Wellenform-Pille, Textzeilen, Dokumentkarte, Cursor, Tasten, Geräte (§6) | das eigentliche Motiv, nur daraus |

Verboten als Dekor: Blobs, Amöben-Formen, Wolken, Sonnen (außer D3), Hügel, Pflanzen, Landschaften, Wasser.

### 3.2 Feste Ebenen (immer drei, nie mehr)

| Ebene | Inhalt | Dunkel (Navy-Bühne) | Hell (Gletscher-Grund) |
|---|---|---|---|
| E1 hinten | D1 Schnittband oder D2 Halbkreis (optional) | `navy.800` `#122247` | `glacier.200` `#D6E2F0` |
| E2 mitte | Trägerform: Dokumentkarte, Gerät oder eine Kapsel | Weiß `#FFFFFF` | Weiß `#FFFFFF` |
| E3 vorne | Motivbausteine (Pille, Zeilen, Cursor, Tasten) | Cyan für Aktion, `glacier.200` für Zeilen | Cyan für Aktion, `glacier.600` für Zeilen |
| Akzent | D3 Markierung | Bernstein `#FFB547` | Bernstein `#FFB547` |

Keine Ebene liegt halbtransparent über einer anderen.

### 3.3 Kanten und Licht

- Kanten scharf und gerade geschnitten, Rundungen nur an Kapseln und Karten (§4). Keine Konturen.
- Kein Pinselstrich, keine Körnung, keine Lichtkante.
- Keine Lichtrichtung: alles flach und gleichmäßig, keine Schatten, auch nicht an Karten.

### 3.4 Wellenform-Pille als Pflichtbaustein

- Jedes Motiv enthält die Wellenform-Pille (Cyan, 5 bis 11 Stäbe).
- Ausnahme Leerzustände: Dort ruht die Pille in `glacier.300` `#BFCFE3` ohne Cyan, weil keine Aufnahme läuft.

### 3.5 Abgrenzung von generischer Blob-Illustration

Erkennbar ist der Stil an drei Dingen:
1. Die Welle ist eine Schnittkante über die ganze Breite, keine geschlossene Klecksform (D1).
2. Die Formen sind Kapseln, Karten und Halbkreise, nie freie Flächen.
3. Genau drei Ebenen, dasselbe Dekor-Vokabular in jedem Bild.

## 4. Linie und Flächen (gemeinsam)

- Keine dicken dunklen Umrisse, keine skizzenhaften oder zittrigen Linien, kein Pinsel, keine Körnung.
- Flächen vollfarbig mit scharfer Kante. Überlappung nur durch Farbwechsel, nie durch Transparenz.
- Rundungen: Kapseln mit vollem Radius, Karten mit Ecken von etwa 8 % der Kartenbreite.
- Kein Verlauf, kein Glow, kein Schlag- oder Kontaktschatten, keine Lichtkante, keine 3D- oder Isometrie-Perspektive.

## 5. Figuren

- Erwachsene, vereinfacht, ruhig. Ganzfigur etwa fünf Kopfhöhen, sonst Halbfigur ab Hüfte.
- **Kein Gesicht:** Kopf ist eine schlichte Form ohne Augen, Mund, Nase, Brauen. Haare höchstens eine flache Form.
- **Hände als Fäustling:** eine gerundete Form, Daumen höchstens angedeutet, keine Finger, kein Schatten.
- Arme als durchgehende Form ohne Naht; Ellbogen außerhalb des Kopfumrisses; keine Hand vor dem Gesicht.
- Farben: Kopf und Hände `glacier.300` oder `glacier.600`, Kleidung `navy.800` oder `glacier.200`. Keine Hauttöne
  außerhalb der Palette.
- Haltung natürlich, keine übertriebene Geste, keine Requisiten in der Hand, keine Sprechblasen.
- Silhouettentest: Pose als einfarbige Fläche bei 64 px lesbar.
- Höchstens eine Figur je Motiv. Leerzustände in der App zeigen keine Figur.

## 6. Motivbausteine

| Baustein | Form | Einsatz |
|---|---|---|
| Wellenform-Pille | Kapsel in Cyan, 5 bis 11 senkrechte Stäbe mit runden Enden | Aufnahme, Diktat; Erkennungszeichen, in jedem Motiv |
| Ruhe-Pille | wie oben in `glacier.300`, flache Stäbe | Leerzustand, keine Aufnahme |
| Tastatur | Reihe gerundeter Tasten ohne Zeichen | nur wenn „tippen“ Thema ist |
| Cursor | senkrechter Balken mit runden Enden | Schreibstelle |
| Textzeilen | waagrechte Kapseln in drei Längen, letzte kürzer | Text, Ergebnis |
| Dokumentkarte | weiße Karte mit Textzeilen, ohne Eselsohr | Ergebnis im Feld |
| Geräte | Laptop, Monitor mit Fuß; ohne Kerbe, Anschlüsse, Logos | „Auf jedem Rechner“ |

## 7. Komposition

- Ein Hauptmotiv, höchstens drei Hauptelemente, viel freie Fläche.
- Mindestens 10 % Rand. Motiv mittig oder im Drittel; Platz für Text im Layout bleibt frei.
- Formate: Newsletter-Kopf 2:1 (1200 × 600), Fuß 3:1 (1200 × 400), Abschnitt 16:10 (1600 × 1000), Leerzustand 1:1
  (800 × 800). Mail-Export 1200 px Breite für 600 px Anzeige.

## 8. Hintergrund und Freistellung

- Rasterbilder liegen auf einer einfarbigen, randlosen Fläche (`navy.900` oder `glacier.50`/`glacier.100`), damit sie
  im Mail- und Website-Kontext ohne Kante sitzen.
- Website und App nutzen das Motiv als nachgezeichnetes SVG mit Farben aus den Tokens (`--wp-*` bzw. `WpColors`),
  `aria-hidden`, Alternativtext nur bei Bedeutung. Das generierte Bild ist Vorlage, kein Produktivbild.

## 9. Verbote

- Kein Text im Bild: keine Buchstaben, Ziffern, Pseudo-Schrift.
- Keine Fremdmarken, Herstellerlogos, Betriebssystem-Symbole, keine Nachahmung fremder Illustrationen oder Figuren.
- Kein Creme-/Papiergrund, kein Pastell, keine Comic-Figuren mit Mimik, keine Sprechblasen, keine Zauber- oder
  Uhren-Metaphern.
- Kein Verlauf, Glow, Schatten, keine Glasoptik, keine Emojis, keine Stockfoto-Anmutung, keine Wasserzeichen.
- Keine fotorealistischen Bilder in diesem Stil (sonst Kennzeichnungspflicht nach EU AI Act Art. 50).

## 10. Bewegung

- Website: Bewegung nur aus dem Motiv selbst (Pillenstäbe atmen gestaffelt, Zeilen erscheinen nacheinander, Cursor
  blinkt), Dauer und Kurven aus `motion.tokens.json`. Endzustand ohne JavaScript sichtbar; nie Einblendung nur per
  Scroll-Beobachter.
- App: Bewegung nur, wo sie erklärt (Onboarding-Schritt), mit HyperFrames oder Remotion, gleiche Darstellung auf
  macOS, Windows, Linux, ohne Start- oder Speicherkosten, keine Dauerschleifen im Hintergrund.
- Newsletter: keine Bewegung.
- Reduzierte Bewegung: Website `prefers-reduced-motion`, App `MediaQuery.disableAnimationsOf`: Standbild im
  Endzustand, Übergänge sofort oder als kurze Überblendung.

## 11. Prüfliste für jedes neue Bild

1. Nur Palette aus §2, Cyan nur für Aktion, Bernstein einmal.
2. Kein Text, kein Logo, kein Gesicht.
3. Flach: kein Verlauf, Glow, Schatten.
4. Drei Ebenen, nur Dekor aus §3.1, Bausteine aus §6; Wellenform-Pille vorhanden (Leerzustand: Ruhe-Pille).
5. Randlose Vollfläche, mindestens 10 % Rand.
6. Im Kontaktbogen neben den Referenzbildern (`refs/`) beurteilt, nicht einzeln.
7. Lesbar bei Einsatzgröße (600 px Mail, 160 px Leerzustand).
