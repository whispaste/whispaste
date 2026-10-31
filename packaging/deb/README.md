# `.deb` — Direkt-Download (Debian/Ubuntu)

WhisPaste als installierbares Debian-Paket für Nutzer, die **nicht** über
Flathub/Snap installieren wollen. Dritter Linux-Kanal laut PRD §8.3
(Flatpak → AppImage → `.deb` → Snap).

| Datei | Zweck |
|---|---|
| `control.template` | Debian-`control`-Metadaten (`__VERSION__`-Platzhalter, wird beim Build ersetzt) |
| `build-deb.sh` | Baut das `.deb` aus dem fertigen Linux-Release-Bundle |

`.desktop`-Entry, AppStream-`metainfo.xml` und Icon werden **nicht** dupliziert,
sondern verbatim aus `packaging/flatpak/` bzw. `assets/icons/app_icon.png`
übernommen — eine einzige Quelle für App-ID (`de.whispaste.app`), Name,
Kategorien, Keywords.

---

## Build

Das Paket wird **nicht** aus einem frischen Flutter-Build erzeugt, sondern aus
dem fertigen Linux-x86_64-Release-Bundle des `build-linux`-Jobs in
`.github/workflows/release.yml` (Artefakt `linux-release` →
`WhisPaste-<version>-linux-x64.tar.gz`). Alle §3.1-Build-Stolperfallen
(sentry-native, `flutter_soloud`-Xiph, `crashpad_handler` `chmod +x`) sind damit
bereits im Bundle abgebildet.

```bash
# In CI direkt aus dem gebauten Bundle:
bash packaging/deb/build-deb.sh build/linux/x64/release/bundle <version> release-artifacts
```

Ergebnis: `release-artifacts/WhisPaste-<version>-linux-x64.deb`.

### Datei-Layout im Paket

| Pfad (im Paket) | Inhalt |
|---|---|
| `/opt/whispaste/` | Flutter-Bundle (Executable, `lib/`, `data/`) — read-only |
| `/usr/bin/whispaste` | Symlink auf `/opt/whispaste/whispaste` (PATH) |
| `/usr/share/applications/de.whispaste.app.desktop` | Desktop-Entry |
| `/usr/share/metainfo/de.whispaste.app.metainfo.xml` | AppStream-Metainfo |
| `/usr/share/icons/hicolor/512x512/apps/de.whispaste.app.png` | Icon |

---

## Abhängigkeiten (`Depends:`)

Die Laufzeit-`Depends:` entsprechen den `-dev`-Paketen, gegen die der
`build-linux`-Job linkt (1:1 abgeleitet, runtime-Soname statt `-dev`):

| `-dev` in `release.yml` | Laufzeit-`Depends:` |
|---|---|
| `libgtk-3-dev` | `libgtk-3-0` |
| `libsecret-1-dev` | `libsecret-1-0` |
| `libnotify-dev` | `libnotify4` |
| `libayatana-appindicator3-dev` | `libayatana-appindicator3-1` |
| `libasound2-dev` | `libasound2` |
| `libcurl4-openssl-dev` | `libcurl4` |
| `libkeybinder-3.0-dev` | `libkeybinder-3.0-0` |
| `liblzma-dev` | `liblzma5` |
| (glibc/zlib baseline) | `libc6`, `zlib1g` |

Die Konsistenz wird in CI (`packaging-validate.yml` → Job `appimage-deb`)
gegen `release.yml` geprüft.

---

## Self-Download des Sprachdienstes + Schreibpfade

WhisPaste lädt den lokalen **Sprachdienst** (`whisper-server`) und das
**Sprachmodell** beim ersten Start selbst herunter. Der Schreibpfad ist
**user-spezifisch**, nicht der System-Installationspfad:

- `$XDG_CONFIG_HOME/whispaste/models/stt`, Default `~/.config/whispaste/models/stt`
  (`appDataDir()`/`sttDir()` in
  `packages/whispaste_diagnostics/lib/src/probes/path_service.dart`).

Dieser Pfad ist beschreibbar **und** ausführbar (kein `noexec`) — die
heruntergeladene Binary wird `chmod +x` gesetzt und dort gestartet. Die
System-Installation unter `/opt/whispaste` bleibt korrekt read-only; zur Laufzeit
wird **nichts** unter `/opt` geschrieben. Netzwerk braucht das System sowieso
(kein Sandbox); kein zusätzliches Paket-Recht nötig.

> **Real-World-Constraint (Issue 03 ist human-blocked):** Ein veröffentlichtes
> Linux-`whisper-server`-Artefakt existiert noch **nicht**. Der Self-Download-E2E
> ist daher lokal **nicht** ausführbar. Dieser Slice stellt sicher, dass
> `Depends:` + Schreibpfade korrekt sind, **damit** der Self-Download
> funktioniert, sobald das Linux-Manifest (WS-A) live ist. Dann: E2E auf der
> NAS-x86-VM.

---

## Lokale Installation / Validierung

```bash
# Control-Metadaten + Abhängigkeiten ansehen:
dpkg-deb --info release-artifacts/WhisPaste-<version>-linux-x64.deb

# Datei-Liste:
dpkg-deb --contents release-artifacts/WhisPaste-<version>-linux-x64.deb

# Installieren (zieht Depends automatisch):
sudo apt install ./release-artifacts/WhisPaste-<version>-linux-x64.deb

# Optionaler Policy-Lint:
lintian release-artifacts/WhisPaste-<version>-linux-x64.deb
```

`dpkg-deb`/`apt` sind auf macOS/dem Dev-Mac **nicht** verfügbar — der Build (AC2)
läuft in CI bzw. auf der NAS-x86-VM (Ubuntu x86_64). CI validiert die
`control`-Shape + Script-Syntax toolchain-unabhängig.
