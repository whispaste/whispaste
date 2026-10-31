# AppImage — Direkt-Download (distro-unabhängig)

WhisPaste als **AppImage**: eine einzelne, ausführbare Datei ohne Installation,
für Nutzer, die **nicht** über Flathub/Snap installieren wollen. Zweiter
Linux-Kanal laut PRD §8.3 (Flatpak → AppImage → `.deb` → Snap).

| Datei | Zweck |
|---|---|
| `build-appimage.sh` | Baut das AppImage aus dem fertigen Linux-Release-Bundle via `linuxdeploy` |

`.desktop`-Entry, AppStream-`metainfo.xml` und Icon werden **nicht** dupliziert,
sondern verbatim aus `packaging/flatpak/` bzw. `assets/icons/app_icon.png`
übernommen — eine einzige Quelle für App-ID (`de.whispaste.app`).

---

## Build

Wie beim `.deb` wird **nicht** Flutter neu gebaut, sondern das fertige
Linux-x86_64-Release-Bundle des `build-linux`-Jobs in
`.github/workflows/release.yml` verpackt (Artefakt `linux-release`). Alle
§3.1-Build-Stolperfallen sind damit bereits im Bundle.

```bash
# CI lädt linuxdeploy und ruft dann:
bash packaging/appimage/build-appimage.sh build/linux/x64/release/bundle <version> release-artifacts
```

Ergebnis: `release-artifacts/WhisPaste-<version>-linux-x64.AppImage`.

`linuxdeploy` bündelt die Shared-Library-Abhängigkeiten der Executable plus die
Plugin-`.so`-Dateien aus dem Flutter-`lib/`-Verzeichnis (`--library-path`) in den
AppDir und emittiert ein relocatable AppImage. In CI läuft das ohne FUSE über
`APPIMAGE_EXTRACT_AND_RUN=1`.

---

## Self-Download des Sprachdienstes + Schreibpfade

Ein AppImage läuft **unsandboxed** — der Self-Download des **Sprachdienstes**
(`whisper-server`) + **Sprachmodells** beim ersten Start ist daher unkompliziert:

- **Netzwerk** ist ohne Sandbox frei verfügbar.
- **Schreibpfad**: `$XDG_CONFIG_HOME/whispaste/models/stt`, Default
  `~/.config/whispaste/models/stt` (`appDataDir()`/`sttDir()` in
  `packages/whispaste_diagnostics/lib/src/probes/path_service.dart`). Dieser Pfad
  ist beschreibbar und nicht `noexec` — die heruntergeladene Binary wird
  `chmod +x` gesetzt und dort gestartet.

Das AppImage-Mount selbst ist read-only; zur Laufzeit wird **nichts** im Mount
geschrieben — korrekt, alles Veränderliche liegt im User-Config-Dir.

> **Real-World-Constraint (Issue 03 ist human-blocked):** Ein veröffentlichtes
> Linux-`whisper-server`-Artefakt existiert noch **nicht**. Der Self-Download-E2E
> ist lokal **nicht** ausführbar. Dieser Slice stellt sicher, dass das AppImage
> startfähig ist und der Schreibpfad korrekt liegt, **damit** der Self-Download
> funktioniert, sobald das Linux-Manifest (WS-A) live ist. Dann: E2E auf der
> NAS-x86-VM.

---

## Lokale Ausführung / Validierung

```bash
chmod +x WhisPaste-<version>-linux-x64.AppImage
./WhisPaste-<version>-linux-x64.AppImage          # startet die App
./WhisPaste-<version>-linux-x64.AppImage --appimage-extract  # Inhalt inspizieren
```

`linuxdeploy`/`appimagetool` sind auf macOS/dem Dev-Mac **nicht** verfügbar — der
Build (AC1) läuft in CI bzw. auf der NAS-x86-VM (Ubuntu x86_64). CI validiert die
Script-Syntax toolchain-unabhängig (`bash -n`); der echte AppImage-Build läuft im
`build-linux`-Job, der das Release-Bundle bereitstellt.
