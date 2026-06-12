# Snap — Snap Store / Ubuntu App Center

WhisPaste als **Snap**: installierbar über den Snap Store bzw. das Ubuntu App
Center. **Vierter** Linux-Kanal laut PRD §8.3 (Flatpak → AppImage → `.deb` →
Snap — Snap zuletzt).

| Datei | Zweck |
|---|---|
| `snapcraft.yaml` | Snap-Manifest (`gnome`-Extension, strict Confinement, Plugs) |

`.desktop`-Entry, AppStream-`metainfo.xml` und Icon werden **nicht** dupliziert,
sondern verbatim aus `packaging/flatpak/` bzw. `assets/icons/app_icon.png`
übernommen — eine einzige Quelle für App-ID (`de.whispaste.app`), Name,
Kategorien, Keywords. Der Snap-**Name** im Store ist das kleingeschriebene
`whispaste`; die App-ID/Desktop-Referenzen bleiben `de.whispaste.app`.

---

## Build

Wie beim Flatpak/AppImage/`.deb` wird **nicht** Flutter neu gebaut, sondern das
fertige Linux-x86_64-Release-Bundle des `build-linux`-Jobs in
`.github/workflows/release.yml` (Artefakt `linux-release` →
`WhisPaste-<version>-linux-x64.tar.gz`) **gestaged**. Alle §3.1-Build-
Stolperfallen (sentry-native, `flutter_soloud`-Xiph, `crashpad_handler`
`chmod +x`) sind damit bereits im Bundle. Die `gnome`-Extension verdrahtet nur
die GTK/GNOME-Laufzeit (GSettings, GDK-Pixbuf-Loader, fontconfig, Launcher)
um das gestagte Bundle.

```bash
# Reproduzierbarer Build (CI oder NAS-x86-VM, Ubuntu x86_64):
cd packaging/snap
snapcraft pack            # erzeugt whispaste_<version>_amd64.snap
```

> `snapcraft` läuft auf macOS/dem Dev-Mac **nicht** (LXD/multipass + amd64-
> Toolchain nötig) — der Build (AC1) läuft in CI bzw. auf der NAS-x86-VM. CI
> validiert die Manifest-*Shape* toolchain-unabhängig (siehe unten), der echte
> `snapcraft pack` läuft auf dem Linux-x86_64-Runner.

### Datei-Layout im Snap

| Pfad (im Snap) | Inhalt |
|---|---|
| `$SNAP/whispaste/` | Flutter-Bundle (Executable, `lib/`, `data/`) — read-only |
| `$SNAP/bin/whispaste` | Symlink auf `../whispaste/whispaste` (Launcher) |
| `$SNAP/usr/share/applications/de.whispaste.app.desktop` | Desktop-Entry |
| `$SNAP/usr/share/metainfo/de.whispaste.app.metainfo.xml` | AppStream-Metainfo |
| `$SNAP/usr/share/icons/hicolor/512x512/apps/de.whispaste.app.png` | Icon |

---

## Confinement + Plugs

**Confinement: `strict`** (bewusst — `strict` ist Store-auto-review-freundlich,
`classic` wäre review-pflichtig und ist hier **nicht** nötig). Die Plugs decken
alle App-Funktionen ab:

| App-Funktion (CONTEXT.md) | Plug(s) |
|---|---|
| Display + Clipboard/Paste (§2.4) | `wayland`, `x11`, `desktop`, `desktop-legacy` |
| Global Hotkey (§2.5) | `unity7` (Session-Bus → WM / GlobalShortcuts-Portal / keybinder) |
| Audio-Aufnahme (§2.2) | `audio-record`, `audio-playback` |
| Self-Download Sprachdienst (Netzwerk) | `network` |
| Tray / App-Indicator + Notifications | `desktop` (Session-Bus → StatusNotifier/Notifications) |

Auto-Paste-Tastendruck-Synthese ist auf Linux **nicht unterstützt**
(`PasteCapabilityStatus.unsupported`, CONTEXT.md §2.7) — daher **kein**
Input-Injection-Interface angefragt (hält den Plug-Satz minimal → bessere
Store-Auto-Freigabe).

---

## Self-Download des Sprachdienstes + Schreibpfade (strict Confinement)

WhisPaste lädt den lokalen **Sprachdienst** (`whisper-server`) und das
**Sprachmodell** beim ersten Start selbst herunter. Unter **strict** Confinement:

- **Netzwerk**: das `network`-Plug erlaubt den Download.
- **Schreibpfad**: `appDataDir()` liest `$XDG_CONFIG_HOME` zuerst
  (`packages/whispaste_diagnostics/lib/src/probes/path_service.dart`). snapd
  remappt `$XDG_CONFIG_HOME` für strict-Snaps auf `$SNAP_USER_DATA/.config`
  (= `~/snap/whispaste/current/.config`). Dieser Pfad ist **beschreibbar** und
  **ausführbar** (kein `noexec`) — die heruntergeladene Binary wird `chmod +x`
  gesetzt und dort gestartet.

Damit funktioniert der Self-Download unter strict Confinement **ohne** zusätzliche
`home`/`removable-media`-Plugs (die die Store-Auto-Freigabe nur verschlechtern
würden). Der Snap-Mount (`$SNAP`) selbst bleibt read-only; alles Veränderliche
liegt unter `$SNAP_USER_DATA`.

> **Real-World-Constraint (Issue 03 ist human-blocked):** Ein veröffentlichtes
> Linux-`whisper-server`-Artefakt existiert noch **nicht**. Der Self-Download-E2E
> ist daher lokal **nicht** ausführbar. Dieser Slice stellt sicher, dass Plugs +
> Schreibpfad-Remapping korrekt sind, **damit** der Self-Download funktioniert,
> sobald das Linux-Manifest (WS-A) live ist. Dann: E2E auf der NAS-x86-VM.

---

## Lokale Validierung + Installation

```bash
# Manifest-Shape ohne Build prüfen (toolchain-unabhängig, läuft auch in CI):
python3 -c "import yaml; yaml.safe_load(open('packaging/snap/snapcraft.yaml'))"

# Extensions expandieren (zeigt das vollständige, von der gnome-Extension
# angereicherte Manifest — braucht snapcraft, also Linux):
cd packaging/snap && snapcraft expand-extensions

# Lokal bauen + ohne Store-Signatur installieren (Linux x86_64):
cd packaging/snap && snapcraft pack
sudo snap install --dangerous ./whispaste_<version>_amd64.snap

# Plugs nach der Installation prüfen:
snap connections whispaste
snap run whispaste
```

`snapcraft`/`snap` sind auf macOS/dem Dev-Mac **nicht** verfügbar — Build +
`--dangerous`-Install laufen in CI bzw. auf der NAS-x86-VM (Ubuntu x86_64).

---

## Store-Einreichung (Runbook)

> **Out of scope dieses Slices (§7):** die tatsächliche Canonical/Store-Review-
> Freigabe und das Konto-Setup. Die folgenden Schritte sind dokumentiert, damit
> die Einreichung **einreichbar** ist — ausgeführt werden sie vom Maintainer.

1. **Name registrieren** (einmalig, Maintainer-Konto):
   ```bash
   snapcraft login
   snapcraft register whispaste
   ```
2. **Version bumpen**: `version:` in `snapcraft.yaml` + `source:`-URL des Parts
   `whispaste-bundle` auf das neue Release-Tag-Asset
   (`…/releases/download/v<version>/WhisPaste-<version>-linux-x64.tar.gz`) setzen.
3. **Bauen** (CI/NAS-x86-VM): `snapcraft pack`.
4. **Hochladen + Channel** (`edge` → `beta` → `candidate` → `stable`):
   ```bash
   snapcraft upload ./whispaste_<version>_amd64.snap --release=edge
   # nach manuellem Smoke-Test:
   snapcraft release whispaste <revision> stable
   ```
5. **Store-Listing**: Titel, Kategorie, Icon + Screenshots im Snapcraft-
   Dashboard ergänzen (Metadaten stammen aus der gemeinsamen
   `de.whispaste.app.metainfo.xml`).

`strict`-Confinement-Snaps durchlaufen i. d. R. die **automatische** Review;
nur falls ein Plug ein manuelles Review triggert, ist ein Store-Request nötig
(hier durch den minimalen Plug-Satz vermieden).

---

## Per-Release-Pflege

Bei jeder neuen Version anzupassen:

- `version:` in `snapcraft.yaml`,
- `source:`-URL des Parts `whispaste-bundle` (Tag-Asset),

danach `snapcraft pack` + `snapcraft upload`. Das Bundle, die `Depends`-äquivalenten
`stage-packages` und die gemeinsame Desktop-/Metainfo-/Icon-Quelle bleiben stabil.
