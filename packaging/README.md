# Distributions-Manifeste

Zusätzliche Installationskanäle für WhisPaste neben Microsoft Store, Website-DMG
und GitHub Releases. Alle Manifeste zeigen auf die Assets der GitHub Releases
(`whispaste/whispaste`, Tag `v<version>`).

Linux-Formate im Repo: `.deb` (`packaging/deb/`), AppImage (`packaging/appimage/`),
Snap (`packaging/snap/`), Flatpak (`packaging/flatpak/`). Es gibt **kein RPM-Spec**;
ein RPM-Kanal existiert nicht. Die Laufzeitabhängigkeit `libxss1` steht in `.deb`
`Depends`, im Snap-`runtime-libs` und ist für Flatpak noch nicht gegen die
GNOME-Runtime geprüft (beim ersten Flatpak-Build prüfen).

| Kanal | Datei | Plattform | Status |
|---|---|---|---|
| Scoop | `scoop/whispaste.json` | Windows x64 | ✅ sofort nutzbar |
| winget | `winget/SilvioLindstedt.WhisPaste.*.yaml` | Windows x64 | ⚠️ PR an `microsoft/winget-pkgs` nötig |
| Homebrew Cask | `homebrew/whispaste.rb` | macOS arm64 | ✅ veröffentlicht (Developer-ID-Notarization live seit v1.2.75) — `whispaste/homebrew-tap` |
| Flatpak / Flathub | `flatpak/de.whispaste.app.yml` | Linux x86_64 | ⚠️ PR an `flathub/flathub` nötig — Runbook: `flatpak/README.md` |

> **Flatpak caveat:** whether the GNOME 50 runtime ships libopusfile and libFLAC is not verified. Until it is, voice-note import (Ogg/Opus, FLAC, M4A) may be unavailable in the Flatpak build. The release notes say so (`CHANGELOG.md`, Unreleased).
| AppImage | `appimage/build-appimage.sh` | Linux x86_64 | ✅ in `release.yml` gebaut, als Release-Asset angehängt — Runbook: `appimage/README.md` |
| `.deb` (Debian/Ubuntu) | `deb/build-deb.sh` + `deb/control.template` | Linux x86_64 | ✅ in `release.yml` gebaut, als Release-Asset angehängt — Runbook: `deb/README.md` |
| Snap (Snap Store / Ubuntu App Center) | `snap/snapcraft.yaml` | Linux x86_64 | ⚠️ `snapcraft upload` an den Snap Store nötig — Runbook: `snap/README.md` |
| GNOME-Shell-Fokus-Erweiterung (optional) | `packaging/linux/gnome-shell-extension/` + `packaging/linux/install-gnome-extension.sh` | Linux, GNOME 45–50 | ✅ im `.deb` (deaktiviert) und im Linux-Tarball; EGO-Zip: `packaging/linux/make-gnome-extension-zip.sh` (vorbereitet, **nicht eingereicht**). AppImage und Snap: kein Installationsweg dokumentiert, die Erweiterung ist dort nicht geprüft (Laufzeitcheck offen, PAR-039) |

Beim Release einer neuen Version müssen `version` + `hash`/`sha256` in jedem
Manifest aktualisiert werden (Scoop kann das via `checkver`/`autoupdate` selbst).

---

## Scoop (Windows) — sofort nutzbar

Scoop installiert die portable ZIP, kein Installer/Admin nötig. Zwei Wege:

**A) Direkt aus dieser Datei (sofort testbar):**
```powershell
scoop install https://raw.githubusercontent.com/whispaste/whispaste/main/packaging/scoop/whispaste.json
```

**B) Eigener Bucket (empfohlen für `scoop install whispaste`):**
1. Repo `whispaste/scoop-bucket` anlegen, `whispaste.json` ins Root oder `bucket/` legen.
2. Nutzer:
   ```powershell
   scoop bucket add whispaste https://github.com/whispaste/scoop-bucket
   scoop install whispaste
   ```
`checkver: github` + `autoupdate` ziehen neue Versionen automatisch; Hash wird
beim `scoop update` neu berechnet. Manifest-Pflege per Bucket-eigener
`bin/checkver.ps1`/`auto-pr` möglich.

---

## winget (Windows) — Submission an microsoft/winget-pkgs

winget-Manifeste leben zentral in `microsoft/winget-pkgs`. Ablauf:

1. Lokal validieren:
   ```powershell
   winget validate --manifest packaging\winget
   ```
2. Optional lokal testen (Hash-Abgleich):
   ```powershell
   winget install --manifest packaging\winget
   ```
3. Mit `wingetcreate` submitten (legt den PR an microsoft/winget-pkgs an):
   ```powershell
   wingetcreate submit --token <gh-token> packaging\winget
   ```

**Hinweise:**
- Der NSIS-Installer ist aktuell **nicht signiert** → Windows SmartScreen warnt
  Nutzer; winget-Validierung lässt das zu, aber Signierung verbessert Trust.
- WhisPaste ist bereits im **Microsoft Store** (`9P22JVKRQ2V0`). winget indexiert
  Store-Apps automatisch über die `msstore`-Quelle — `winget install` findet die
  App also evtl. schon ohne dieses Manifest. Das Community-Manifest hier ist die
  „klassische" Quelle (Installer statt Store-Paket) als Ergänzung.
- Bei jeder neuen Version: `wingetcreate update SilvioLindstedt.WhisPaste
  --version <neu> --urls <installer-url>` erzeugt aktualisierte Manifeste.

---

## Homebrew Cask (macOS) — veröffentlicht

✅ **Live seit v1.2.75.** Die macOS-Builds sind Developer-ID-signiert und
notarisiert (`Sign, notarize and staple .app`-Step in `release.yml`); Homebrew
kann das Bundle ohne Gatekeeper-Quarantäne-Blockade installieren.

Tap-Repo: `whispaste/homebrew-tap`, Datei `Casks/whispaste.rb`. `release.yml`
bumpt `packaging/homebrew/whispaste.rb` in diesem Repo automatisch pro Release
(`Bump packaging manifests`-Job, Notarization-Guard); der Abgleich ins
`homebrew-tap`-Repo ist derzeit ein manueller `git push` dorthin (kein
Cross-Repo-Automatisierungsschritt in `release.yml`).

Nutzer:
```bash
brew install --cask whispaste/tap/whispaste
```
`livecheck` (strategy `github_latest`) meldet neue Versionen; `sha256` muss pro
Release aktualisiert werden (oder via `brew bump-cask-pr` automatisiert).

Cask nutzt das versionierte ZIP (`WhisPaste-<version>-macos-arm64.zip`), nicht die
unversionierte DMG — saubere URL fürs Versionstracking.

---

## Auto-Paste je Linux-Format

Auto-Paste schickt den Einfügetastendruck über ein virtuelles Eingabegerät
(`/dev/uinput`). Wie viel Zutun der Nutzer braucht, hängt vom Format ab. Der
Onboarding-Hinweis wählt den Text nach dem erkannten Format
(`lib/services/desktop_paste/linux_package_format.dart`).

| Format | Auto-Paste | Schritt für Nutzer |
|---|---|---|
| `.deb` / nativ | erst nach Zustimmung (R-02) | im Onboarding bzw. in den Einstellungen „Freigeben“ und Administratorpasswort (polkit-Aktion `de.whispaste.uinput.manage`, Hilfsprogramm `/usr/libexec/whispaste/uinput-access`). „Freigabe entfernen“ nimmt sie zurück, die Deinstallation ebenfalls (`prerm`) |
| Tarball | erst nach Zustimmung | `sudo ./install-uinput-rule.sh`, zurück mit `sudo ./uninstall-uinput-rule.sh` |
| Flatpak | über `--device=all` | udev-Regel `71-whispaste-uinput.rules` auf dem Host, Befehl kopierbar im Onboarding (Administratorrechte, sudo). WhisPaste selbst liest keine Eingabegeräte. Mit `--device=all` sind `/dev/input/*` in der Sandbox aber sichtbar: Hat der Benutzer auf dem Rechner Leserechte (z. B. als Mitglied der Gruppe `input`), könnte die App Tastatureingaben anderer Programme lesen. Mitglieder der Gruppe `input` können außerdem Tastatureingaben lesen und virtuelle Eingaben erzeugen. Wer das nicht möchte: Auto-Paste aus lassen, Text von Hand einfügen |
| Snap | braucht die Schnittstelle `uinput` | einmal `sudo snap connect whispaste:uinput` |
| AppImage | braucht Zugriff auf `/dev/uinput` | udev-Regel `71-whispaste-uinput.rules` nach `/etc/udev/rules.d/`, dann `sudo udevadm control --reload-rules && sudo udevadm trigger`. Der Befehl erscheint kopierbar im Onboarding, erst nach der Erklärung. Die Befehle brauchen **Administratorrechte** (sudo) |

Die Regel gibt Schreibzugriff nur der aktiven Sitzung (`TAG+="uaccess"`), keiner
Gruppe (R-02, Entscheidung 4a). Solange sie liegt, kann jedes Programm dieser
Sitzung virtuelle Eingaben erzeugen. Deshalb installiert kein Paket sie von
selbst. Der Tipp „Gruppe `input`“ ist entfallen: Mitglieder dieser Gruppe
können alle Tastatureingaben lesen.

**Warum kein engeres Recht für Flatpak:** `--device=input` gibt in Flatpak nur
`/dev/input` frei (Quelle: `common/flatpak-run.c`, Stand Flatpak-`main` am
2026-10-18, dev-bind von `/dev/input`; Doku `doc/flatpak-run.xml`, `--device`).
`/dev/uinput` liegt nicht darin, deshalb ist `--device=all` nötig. Ob der
Schreibzugriff auf dem Host klappt, hängt zusätzlich an der udev-Regel. Der Flatpak-Build ist auf einem echten System noch nicht
geprüft (offenes Release-Tor, siehe `flatpak/README.md`, Abschnitt „Release-Tor“).

**Lizenz:** `libXScrnSaver` 1.2.4 (X11, MIT-style) wird im Flatpak-Build gebaut
und dort unter `/app/share/licenses/libXScrnSaver/COPYING` installiert; der
Lizenztext liegt auch in `assets/licenses/libxscrnsaver-LICENSE.txt`.

Erkannt wird das Format am Pfad der laufenden Programmdatei und an Markern, die
nur die jeweilige Laufzeit setzt (`/.flatpak-info`, `SNAP`, `APPIMAGE` plus
`APPDIR`). Umgebungsvariablen allein reichen nicht, weil Kindprozesse sie erben.

## Linux Direkt-Download (AppImage + `.deb`) — als Release-Asset angehängt

Für Nutzer, die **nicht** über Flathub/Snap installieren wollen. Beide Pakete
werden im `build-linux`-Job in `.github/workflows/release.yml` **aus dem fertigen
Linux-x86_64-Release-Bundle** gebaut (kein Flutter-Rebuild — alle §3.1-Build-
Stolperfallen sind bereits im Bundle) und landen in `release-artifacts/`. Von
dort hängt sie der `create-release`-Job über das vorhandene `files: artifacts/*`-
Glob automatisch an das GitHub-Release an — keine separate Upload-Verdrahtung.

| Format | Build-Recipe | Runbook |
|---|---|---|
| AppImage (`WhisPaste-<version>-linux-x64.AppImage`) | `appimage/build-appimage.sh` (via `linuxdeploy`) | `appimage/README.md` |
| `.deb` (`WhisPaste-<version>-linux-x64.deb`) | `deb/build-deb.sh` + `deb/control.template` (via `dpkg-deb`) | `deb/README.md` |

Beide nutzen denselben `.desktop`-Entry, dieselbe AppStream-`metainfo.xml` und
dasselbe Icon wie der Flatpak-Kanal (`packaging/flatpak/` bzw.
`assets/icons/app_icon.png`) — eine Quelle für App-ID `de.whispaste.app`,
Name, Kategorien, Keywords. Validierung (Script-Syntax + `.deb`-`control`-Shape +
`Depends:`↔`release.yml`-Konsistenz) läuft toolchain-unabhängig im Job
`appimage-deb` in `packaging-validate.yml`.

**Self-Download des Sprachdienstes:** Beide Formate berücksichtigen den
Schreibpfad des selbst-heruntergeladenen Sprachdienstes
(`$XDG_CONFIG_HOME/whispaste/models/stt`, Default `~/.config/whispaste/models/stt`
— user-spezifisch, beschreibbar, nicht `noexec`). AppImage läuft unsandboxed
(Netzwerk + Schreibpfad frei); das `.deb` installiert read-only nach `/opt`, die
App schreibt zur Laufzeit ausschließlich in den User-Config-Pfad. Solange das
veröffentlichte Linux-`whisper-server`-Artefakt fehlt (Issue 03, human-blocked),
ist der Self-Download-E2E nur dokumentiert, nicht ausgeführt — Details in den
beiden Runbooks.

---

## Snap (Snap Store / Ubuntu App Center) — `snapcraft upload`

Vierter Linux-Kanal laut PRD §8.3 (Snap zuletzt). Das `snap/snapcraft.yaml`
stagt — wie Flatpak/AppImage/`.deb` — das fertige Linux-x86_64-Release-Bundle
des `build-linux`-Jobs (kein Flutter-Rebuild); die `gnome`-Extension verdrahtet
die GTK/GNOME-Laufzeit darum. **Strict** Confinement (Store-auto-review-
freundlich); die Plugs decken Display/Clipboard (`wayland`/`x11`/`desktop`/
`desktop-legacy`), Hotkey (`unity7`), Audio (`audio-record`/`audio-playback`)
und den Netzwerk-Self-Download (`network`) ab. Der Self-Download-Schreibpfad
funktioniert unter strict Confinement, weil snapd `$XDG_CONFIG_HOME` auf das
beschreibbare, exec-fähige `$SNAP_USER_DATA/.config` remappt. Desktop-Entry,
AppStream-`metainfo.xml` und Icon stammen aus derselben Quelle wie die anderen
Kanäle (`packaging/flatpak/` bzw. `assets/icons/app_icon.png`). Validierung
(YAML-Shape + Pflicht-Keys + Plug-Abdeckung) läuft toolchain-unabhängig im Job
`snap` in `packaging-validate.yml`; `snapcraft pack`/`upload` läuft in CI bzw.
auf der NAS-x86-VM. Runbook: `snap/README.md`.
