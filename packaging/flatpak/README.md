# Flatpak / Flathub — Runbook

WhisPaste als **Flatpak** für den primären cross-distro Linux-Kanal (erscheint in
GNOME Software / KDE Discover, sauberes Update). Dies ist der **erste** Linux-Kanal
laut PRD §8.3 (Channel-Priorität: Flatpak → AppImage → `.deb` → Snap).

| Datei | Zweck |
|---|---|
| `de.whispaste.app.yml` | Flatpak-Manifest (App-ID = bestehende Reverse-DNS-ID aus `linux/CMakeLists.txt`) |
| `de.whispaste.app.desktop` | Desktop-Entry (Flathub-Pflicht) |
| `de.whispaste.app.metainfo.xml` | AppStream-Metainfo (Flathub-Pflicht) |

Das Manifest baut **nicht** Flutter neu, sondern verpackt das fertige
Linux-x86_64-Release-Bundle aus dem `build-linux`-Job in
`.github/workflows/release.yml` (Artefakt `linux-release` →
`WhisPaste-<version>-linux-x64.tar.gz`). Damit sind alle §3.1-Build-Anpassungen
(sentry-native-Libs, `flutter_soloud` Xiph, `crashpad_handler` `chmod +x` usw.)
bereits im Tarball abgebildet — der Flatpak-Build erbt sie.

---

## Self-Download des Sprachdienstes im Sandbox-Kontext

WhisPaste lädt den lokalen **Sprachdienst** (`whisper-server`) und das
**Sprachmodell** beim ersten Start selbst herunter
(`lib/services/whisper_server_*.dart`, `local_stt_server.dart`). Im
Flatpak-Sandbox braucht das zwei Dinge, die die `finish-args` setzen:

1. **Netzwerk** — `--share=network`. Holt das Manifest von
   `raw.githubusercontent.com/whispaste/whispaste` und die Binary/Modell-Assets.
2. **Beschreibbarer, ausführbarer Datenpfad** — `--filesystem=xdg-data/whispaste:create`.
   Die heruntergeladene Binary wird `chmod +x` gesetzt und **in-sandbox**
   ausgeführt. `XDG_DATA_HOME` (`~/.var/app/de.whispaste.app/data`) ist im
   Sandbox beschreib- **und** ausführbar (kein `noexec`), daher läuft der
   selbst-heruntergeladene `whisper-server` dort.

> **Real-World-Constraint (Issue 03 ist human-blocked):** Ein veröffentlichtes
> Linux-`whisper-server`-Artefakt existiert noch **nicht**. Der Self-Download-E2E
> ist daher lokal **nicht** ausführbar. Dieser Slice stellt sicher, dass die
> `finish-args` korrekt sind, **damit** der Self-Download im Sandbox funktioniert,
> sobald das Linux-Manifest-Eintrag (WS-A) live ist. Sobald das Artefakt
> publiziert ist: E2E auf der NAS-x86-VM (PRD §C1) fahren.

### finish-args ↔ App-Funktion (Audit-Tabelle)

| App-Funktion (CONTEXT.md) | finish-arg |
|---|---|
| Hotkey (§2.5) | `--socket=session-bus` (+ X11/Wayland-Sockets) |
| Clipboard / Paste (§2.4) | über Wayland-/X11-Socket (kein Extra-Arg) |
| Aufnahme / Audio (§2.2) | `--socket=pulseaudio` |
| Self-Download Sprachdienst | `--share=network` + `--filesystem=xdg-data/whispaste:create` |
| Display | `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`, `--share=ipc` |
| Tray / Notifications | `--talk-name=org.kde.StatusNotifierWatcher`, `--talk-name=org.freedesktop.Notifications` |

Auto-Paste (Keystroke-Synthese) ist auf Linux **nicht** unterstützt
(`PasteCapabilityStatus.unsupported`, CONTEXT.md §2.7) — daher wird **bewusst
kein** Input-Device-Injection-Arg angefordert.

---

## Validierung (lokal & CI)

CI validiert das Manifest im Job `flatpak` in
`.github/workflows/packaging-validate.yml` (läuft auf jedem Push nach `dev`, der
`packaging/**` berührt). Die Validierung ist toolchain-unabhängig (YAML-Parse +
Pflichtfeld-/finish-arg-Asserts + AppStream-/Desktop-Validierung), analog zu den
Scoop-/winget-/Homebrew-Jobs.

**Lokal** (sofern `flatpak`-Tooling installiert ist):

```bash
# 1. Manifest-YAML parsebar + Struktur (kein flatpak nötig):
python3 -c "import yaml,sys; yaml.safe_load(open('packaging/flatpak/de.whispaste.app.yml'))"

# 2. Desktop-Entry validieren:
desktop-file-validate packaging/flatpak/de.whispaste.app.desktop

# 3. AppStream-Metainfo validieren:
appstreamcli validate packaging/flatpak/de.whispaste.app.metainfo.xml

# 4. Manifest-Build (braucht flatpak + flatpak-builder + Freedesktop-Runtime):
flatpak install -y flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
flatpak-builder --force-clean --user --install build-dir \
  packaging/flatpak/de.whispaste.app.yml
flatpak run de.whispaste.app
```

`flatpak-builder` ist auf macOS/dem Dev-Mac **nicht** verfügbar — der
reproduzierbare Build (AC1) läuft daher in CI bzw. auf der NAS-x86-VM
(Ubuntu x86_64).

---

## Pro-Release-Schritte (Manifest aktualisieren)

Vor jeder Einreichung / jedem Release:

1. **Archive-Quelle pinnen** in `de.whispaste.app.yml` → `sources[0]`:
   - `url` auf das Release-Asset des Tags setzen:
     `https://github.com/whispaste/whispaste/releases/download/v<version>/WhisPaste-<version>-linux-x64.tar.gz`
   - `sha256` auf den echten Digest setzen:
     ```bash
     curl -L <url> | sha256sum
     ```
2. **Release-Eintrag** in `de.whispaste.app.metainfo.xml` voranstellen
   (`<release version="<version>" date="<YYYY-MM-DD">`).
3. Lokal/CI validieren (siehe oben).

---

## Flathub-Einreichung (Folgearbeit — out of scope für diesen Slice, PRD §7)

> Konto-Setup und der **tatsächliche** Flathub-Review-Ausgang liegen außerhalb
> dieses Slices. Dieser Slice stellt **Konformität + Einreichbarkeit** her.

Ablauf, sobald ein Linux-Release-Tag + veröffentlichtes Linux-`whisper-server`
(WS-A) existieren:

1. Fork `github.com/flathub/flathub`, neuer Branch `de.whispaste.app`.
2. Manifest + `.desktop` + `.metainfo.xml` ins Flathub-Repo-Layout legen
   (App-ID als Verzeichnis-/Dateiname).
3. PR an `flathub/flathub` öffnen (das ist der **einzige** erlaubte externe PR —
   die Solo-Dev-„keine-PRs"-Regel betrifft das eigene Repo, nicht Flathub).
   Flathub-Bot baut + linted automatisch (`flatpak-builder` + `appstreamcli
   validate` + `flatpak-builder-lint`).
4. Nach Review-Freigabe wird die App in GNOME Software / KDE Discover sichtbar;
   Updates per neuem Tag → Manifest-Bump (Schritt „Pro-Release" oben).

---

## App-ID

`de.whispaste.app` — die **bestehende** Reverse-DNS-ID aus
`linux/CMakeLists.txt` (`APPLICATION_ID`) und der macOS-`PRODUCT_BUNDLE_IDENTIFIER`.
**Nicht** neu erfinden. (Der im Distributions-Strang vorgesehene Switch auf
`de.whispaste.app` ist noch **nicht** vollzogen — sobald er es ist, ziehen
App-ID, Datei-Namen und der `--filesystem`-Pfad gemeinsam nach.)
