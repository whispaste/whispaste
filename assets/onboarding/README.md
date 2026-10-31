# Onboarding-Standbilder

Die Onboarding-Seiten zeigen statische Standbilder (Maintainer-Entscheidung 7b, 2026-10-28). Animierte WebP werden nicht ausgeliefert, Bewegung gibt es auf keiner Seite.

| Beat | Seite | Dateien |
|---|---|---|
| 2 | Sprachmodell (`speech`) | `beat_2_still_{hell,dunkel,marine}.webp` |
| 4 | Zugriffe (`access`) | `beat_4_still_{hell,dunkel,marine}.webp` |

- Format: 920 x 576 px, Panel-Verhältnis 460:288 (`kOnboardingMotionClipAspect`).
- Je Farbsatz eine Datei (hell, dunkel, marine), gewählt über `onboardingBeatAssetPath()`.
- Kein Text im Bild. Beschriftungen kommen aus den ARB-Dateien.
- Die geteilten Seiten ab Screen 2 tragen je ein eigenes Gletscher-Gemälde (`*-glacier.webp`, `welcome-klangbaender.webp`, 1920 x 1280, kein Text im Bild). Der Hotkey-Schritt zeigt darauf die Live-Taste (`hotkey-glacier.webp`). Die Abschlussseite (Datenschutz, Screen 7) zeigt nur das Gemälde ohne Panel (`privacy-glacier.webp`: Gletschertal mit Hütte und bernsteinfarbenem Fenster, linke Seite ruhig für den Text); darüber groß die Wellenmarke des App-Logos ohne Kachel und Schriftzug, `privacy-logo-mark.webp`, gerendert aus `assets/icons/logo-light.svg` mit `rsvg-convert -w 1024`, beschnitten, 720 px breit).
- Grenzen, geprüft in `test/features/onboarding/beat_motion_test.dart`: genau diese sechs Dateien, je Datei ein Standbild ohne Animation, Gesamtgröße höchstens 2 MB.
