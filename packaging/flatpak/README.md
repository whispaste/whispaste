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
| Hotkey (§2.5) | X11-Grab über `--socket=fallback-x11` (XWayland), Push-to-talk unter Wayland über das GlobalShortcuts-Portal (keine Freigabe nötig). Kein `--socket=session-bus` (F-18 / R-03) |
| Clipboard / Paste (§2.4) | über Wayland-/X11-Socket (kein Extra-Arg) |
| Auto-Paste (Keystroke über uinput, §2.4) | `--device=all` (einzige Flatpak-Option, die `/dev/uinput` sichtbar macht; `--device=input` gibt nur `/dev/input` frei, siehe `flatpak-run.c`) |
| Aufnahme / Audio (§2.2) | `--socket=pulseaudio` |
| Self-Download Sprachdienst | `--share=network` + `--filesystem=xdg-data/whispaste:create` |
| Display | `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`, `--share=ipc` |
| Tray / Notifications | `--talk-name=org.kde.StatusNotifierWatcher`, `--talk-name=org.freedesktop.Notifications` |
| Secret Service (flutter_secure_storage) | `--talk-name=org.freedesktop.secrets` (bewusste Entscheidung, siehe unten) |
| Stromereignisse, Sicherheitsnetz (ticket, PAR-030) | `--system-talk-name=org.freedesktop.login1` (nur dieser Dienst) |

**Secret Service, bewusste Entscheidung (R-03, 2026-10-19):** Die Freigabe
reicht an alle Einträge des entsperrten Schlüsselbunds, nicht nur an die von
WhisPaste. Ohne sie fiele libsecret in der Sandbox auf das Portal-Dateibackend
zurück, und bereits gespeicherte API-Schlüssel wären nach dem Update weg. Der
Maintainer hat den breiten Zugriff gegen diesen Schlüsselverlust abgewogen und
die Freigabe behalten.

**Stromereignisse, Sicherheitsnetz (PAR-030, 2026-10-19):** Der Linux-Runner
abonniert Suspend und Resume auf dem System-Bus (`org.freedesktop.login1`,
`linux/runner/power_event_host.cc`). Ohne die benannte Freigabe ist in der Sandbox
kein System-Bus erreichbar. Die Abonnierung scheitert dann still, und die Ereignisse
erreichen die App nicht. Die Freigabe gilt nur für diesen einen Dienst.

Laufzeitprüfung (Probe auf dem damaligen Linux-Testgerät, GNOME-50-Runtime, nur über
`flatpak-builder --run` ohne Installation): Mit Freigabe meldet die Sandbox
`login1: reachable, PrepareForSleep present`, ohne Freigabe `login1: NOT reachable`.
Das echte Manifest parst mit flatpak-builder 1.4.8 und führt die Freigabe in den
effektiven finish-args. Offen: voller Manifest-Build und ein Suspend-Zyklus in der
installierten App (Release-Tor unten).

Auto-Paste ist im Flatpak **nicht** mehr „nicht unterstützt“: es braucht
`--device=all` und auf dem Host die udev-Regel `71-whispaste-uinput.rules`
(Befehl mit sudo, kopierbar im Onboarding; Entscheidung 2b zu R-02). Die Aussage dazu lautet: WhisPaste selbst
liest keine Eingabegeräte. Mit `--device=all` sind sie in der Sandbox aber
sichtbar: Hat der Benutzer auf dem Rechner Leserechte (z. B. als Mitglied der
Gruppe `input`), könnte die App Tastatureingaben anderer Programme lesen.
Mitglieder der Gruppe `input` können außerdem virtuelle Eingaben erzeugen.
Ob das Einfügen auf dem Host klappt, ist noch nicht gebaut und geprüft (Release-Tor unten).

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

`whispaste --diagnose` startet in der Sandbox kein eigenes Xvfb; ohne Display
schreibt es einen Fehlerreport und endet mit 2. Headless daher unter Xvfb
prüfen: `xvfb-run -a flatpak run --socket=x11 --nosocket=wayland de.whispaste.app --diagnose`.

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

**Bekannte Abweichung (Stand 2026-10-19):** Das Manifest bezieht noch das Archiv
von v1.2.65, die Metainfo nennt als neuesten Eintrag aber 1.2.67. `flatpak info`
meldet deshalb 1.2.67 für einen Build, der den Code von 1.2.65 enthält. Beim
nächsten Release Schritt 1 und 2 auf denselben Tag ziehen.

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

## Release-Tor: flatpak-builder-Lauf

Stand 2026-10-19 auf dem damaligen Linux-Testgerät (Ubuntu 26.04, Flatpak 1.16.6,
flatpak-builder 1.4.8, `org.gnome.Platform`/`Sdk` 50). Gebaut wurde das Manifest
mit einem lokalen Release-Bundle von `agent-review-int1` @563ee8b25 statt des
`archive`-Eintrags (Scratch-Kopie; nur `url`/`sha256` → `path`):

1. ✓ `flatpak-builder --user --force-clean build-dir de.whispaste.app.yml` läuft
   durch, alle Module inklusive `libXScrnSaver`.
2. ✓ `libXScrnSaver` findet die `scrnsaverproto`- und `libXext`-Header aus dem
   SDK; `ldd /app/whispaste/whispaste` meldet keine fehlende Bibliothek
   (`libXss.so.1`, `libkeybinder-3.0.so.0`, `libayatana-appindicator3.so.1`
   kommen aus `/app/lib`).
3. ✓ `/app/share/licenses/libXScrnSaver/COPYING` ist installiert.
4. ✓ `/dev/uinput` und `/dev/input/*` sind in der Sandbox sichtbar.
5. offen: Schreibzugriff auf `/dev/uinput` ist nur mit der udev-Regel auf dem
   Host (`packaging/linux/71-whispaste-uinput.rules`) möglich. Auf dem Testhost fehlt die Gruppe; Host und Sandbox verweigern den
   Zugriff gleich. Der Positivfall ist noch nicht belegt.
6. ✓ Headless-Start (`xvfb-run`, `flatpak run --socket=x11`) läuft stabil, bis
   ein Timeout ihn beendet. `crashpad_handler` startet. Er braucht das
   Ausführungsrecht aus dem Release-Tarball (`release.yml`, „Ensure
   crashpad_handler is executable“); flatpak-builder übernimmt es.

Lokale Stolperfallen, keine Paketfehler:

- **glibc:** Ein auf Ubuntu 26.04 gebautes Bundle verlangt glibc 2.43 (SoLoud-
  Plugin), die GNOME-50-Runtime hat 2.42 → Ton fällt aus. Das Release-Bundle aus
  CI (`ubuntu-latest`, glibc 2.39) passt.
- **Cache:** flatpak-builder nimmt bei geändertem lokalem Archiv unter Umständen
  den alten Modulstand aus dem Cache. Für einen frischen Lauf `--state-dir` neu
  anlegen bzw. `--disable-cache` setzen.
- **Document-Portal:** In einer SSH-Sitzung ohne eingehängtes
  `/run/user/<uid>/doc` bricht `flatpak run` mit „Can't find source path“ ab;
  `--no-documents-portal` umgeht das.

## GNOME-Shell-Fokus-Erweiterung (Host-Schritt, optional)

Unter GNOME auf Wayland kann WhisPaste das fokussierte Fenster nur über die
Erweiterung `whispaste-focus@whispaste.de` erfahren (Terminal-Erkennung,
Auto-Paste-Sperrliste, App-Profile). Die Erweiterung läuft in der
GNOME-Shell des **Hosts**, nicht in der Sandbox; die Flatpak-App spricht sie
über den Session-Bus an, dafür reicht `--socket=session-bus` (bereits gesetzt),
es ist keine zusätzliche `finish-args`-Zeile nötig.

Der Nutzer installiert sie einmal auf dem Host, aus dem Linux-Tarball oder
dem Quellbaum:

```bash
bash packaging/linux/install-gnome-extension.sh
```

Danach unter Wayland einmal ab- und wieder anmelden. Ohne die Erweiterung
funktioniert WhisPaste weiter, nur ohne Fenstererkennung.

## Fokuserkennung unter Wayland in der Sandbox

Welches Fenster den Fokus hat (Terminal-Erkennung, Sperrliste), fragt die App den
Compositor. In der Flatpak gilt pro Desktop:

- **KDE (KWin):** geht über den Session-Bus. Das kurze KWin-Skript liegt in
  `$XDG_RUNTIME_DIR/app/$FLATPAK_ID`, weil `/tmp` in der Sandbox privat ist und
  KWin es sonst nicht lesen kann.
- **GNOME:** nur mit der Host-Erweiterung (Abschnitt oben).
- **Sway, niri, Hyprland und andere wlroots-Compositors (labwc, Wayfire):**
  Die IPC-Sockets von Sway und niri sind in der Sandbox nicht sichtbar. Die App
  fragt dann über den Wayland-Socket per `zwlr_foreign_toplevel_manager_v1`.
  Das Protokoll liefert nur einen Namen: bei Wayland-Fenstern die App-ID, bei
  XWayland-Fenstern die WM_CLASS-Klasse. Hyprland nutzt den genaueren eigenen
  Socket, sobald er freigegeben ist:
  `flatpak override --user --filesystem=xdg-run/hypr:ro de.whispaste.app`.
- **Ohne erreichbare Quelle** (z. B. ein Compositor ohne das Protokoll, etwa
  COSMIC) zeigt die Statuszeile „nicht unterstützt“. Dann greift der Schalter
  „Immer mit Strg+Umschalt+V einfügen“.

## Tastatureingabe über das Portal (libei)

Neben uinput gibt es einen zweiten Tastaturpfad über das Portal
`org.freedesktop.portal.RemoteDesktop` (Version 2, `ConnectToEIS`, libei). Er
braucht kein `/dev/uinput` und läuft deshalb auch in der Flatpak-Sandbox ohne
Gerätezugriff. Das Manifest braucht dafür keine zusätzlichen `finish-args`: der
Portal-Zugriff ist ohne Freigabe-Loch erlaubt.

- **Build:** `libei.so.1` wird zur Laufzeit per `dlopen` geladen. Im Build ist nur
  optional `libei-1.0` (Header) nötig; ohne sie meldet `portalInputAvailable`
  `false` und uinput bleibt der einzige Pfad.
- **Offener Punkt:** Ob `org.gnome.Platform` 50 `libei` mitliefert, ist offline
  nicht prüfbar (Runtime lokal nicht installiert). Falls nicht, bleibt der Pfad in
  der Flatpak auf `unavailable` und fällt auf uinput zurück. Vor einem Flathub-Release
  mit `flatpak run --command=sh org.gnome.Platform//50` prüfen (`ls /usr/lib/*/libei*`).
- **Consent:** Der Portal-Dialog erscheint beim ersten Verbinden; das Restore-Token
  (`persist_mode` 2) wird in SharedPreferences abgelegt, damit er bei späteren
  Starts entfällt, bis der Nutzer die Freigabe im System widerruft.
- **Nicht gemessen:** Die Hotkey-bis-Text-Latenz auf dem Portal-Pfad muss auf
  Hardware gemessen werden (Testlabor-VM linux-vm bzw. echte Linux-Hardware); die uinput-Latenz ist hier ausdrücklich
  nicht gemessen.
