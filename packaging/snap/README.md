# Snap — Snap Store / Ubuntu App Center

## Stand 2026-11-18

Name `whispaste`, Publisher `silvioli`, Snap-ID `L8btngjUpqlBSGW6hhUn6U9zL5SWq3SY`.
Revision 2 (1.5.2, amd64) wurde am 18.11. über Launchpad gebaut und hochgeladen;
sie ersetzt die am 17.11. eingereichte Revision 1 (1.5.1). Die alte Revision
wurde aus der Review-Warteschlange genommen, damit Revision 2 geprüft wird.
Das Listing ist privat, ohne veröffentlichten Kanal. Die Store-Prüfung verlangt
für `uinput` eine `allow-installation`-Deklaration; strict Confinement umgeht
sie nicht. [Freigabeanfrage](https://forum.snapcraft.io/t/54267): uinput-Installation
und Auto-Verbindung sowie audio-record-Auto-Verbindung. Genehmigung steht aus.

Das Manifest verwendet 1.5.2 und **core26**: Bibliotheken im Linux-Release
benötigen GLIBC_2.43. core24 mit glibc 2.39 reicht nicht aus. Snapcraft 9.2
unterstützt die GNOME-Erweiterung auf core26. Paketbau ersetzt keinen Laufzeittest.

Der erste 1.5.2-Build (#3351905) wurde wegen einer fehlenden direkten
Runner-Abhängigkeit (`libopusfile.so.0`) nicht hochgeladen. `libopusfile0` ist nun
explizit enthalten. Die verbleibende Linter-Warnung für `libdartjni.so` /
`libjvm.so` betrifft Sentrys Android-Anbindung: `sentry_flutter` 9.25.0 wählt in
`lib/src/native/factory_real.dart` unter Linux `SentryNative` (C), nicht Java.
Die Java-Bibliothek wird deshalb nicht als zusätzliche Laufzeit installiert.

Korrigiertes Artefakt: `whispaste_1.5.2_amd64.snap`, 155918336 Bytes,
SHA-256 `24830bb115117f08aa55f9258f9647aca42cdcb286edc92fc6787cc89a6befc6`.
Paketmetadaten (`core26`, `strict`, Version 1.5.2) und die enthaltene
`libopusfile.so.0` wurden direkt im SquashFS geprüft.

## Build

Das fertige Linux-x86_64-Release-Bundle wird über eine versionierte URL mit
SHA-256-Prüfung geladen. Kein Flutter-Neubau. `gnome` ergänzt die Desktop-Laufzeit.
Snap-Name: `whispaste`, App-ID: `de.whispaste.app`.

Desktop-Datei, Metainfo und Icon sind **Snap-lokale Kopien**; verwaltete Builds
können Nachbarverzeichnisse nicht lesen. Desktop/Metainfo mit `packaging/flatpak/`
und Icon mit `assets/icons/app_icon.png` synchron halten.

```bash
cd packaging/snap
snapcraft expand-extensions
# Linux amd64 mit snapd und Build-Provider:
snapcraft pack
```

macOS unterstützt Snapcraft-Manifestprüfung, Store-Verwaltung und Launchpad-
Remote-Builds. Die Snap-Ausführung benötigt Linux. Remote-Builds laden den
Projektinhalt öffentlich hoch: nur die vier Paketdateien separat bereitstellen:

```bash
# Vom Repository-Root:
build_dir=$(mktemp -d /tmp/whispaste-snap.XXXXXX)
cp packaging/snap/snapcraft.yaml packaging/snap/de.whispaste.app.* "$build_dir/"
cd "$build_dir"
git init -b main
git add .
git commit -m "build: prepare snap package"
snapcraft remote-build --build-for=amd64 --launchpad-accept-public-upload
# Unterbrochenen Lauf abrufen:
snapcraft remote-build --recover --launchpad-accept-public-upload
```

Snapcraft 9.2.1 kann beim Wiederaufnehmen ein automatisch angelegtes Launchpad-
Projekt übersehen (`Could not find repository at path ~silvioli/+git/…`). Dann
den bestehenden Build auf Launchpad öffnen und dessen Artefakt herunterladen;
keinen zweiten Build für denselben Stand starten. Korrigierter Build 1.5.2 mit
Opus-Laufzeit: [Launchpad #3351915](https://launchpad.net/~silvioli/silvioli-craft-remote-build/+snap/snapcraft-whispaste-bba6db7aeca782dbea7ea5ff110e41ef/+build/3351915).

Das aktuelle Lenovo-Testlab `ubu` verwendet Ubuntu 26.04.1 LTS in einem
unprivilegierten LXC-Container. Am 18.11. scheiterte der erste Snap-Test noch mit
`cannot mount squashfs image ... failed to setup loop device`. Die separate
Lab-Wartung hat die FUSE-Einbindung und Basis inzwischen korrigiert;
`hello-world` läuft nach dem Neustart mit snapd 2.78. Das korrigierte WhisPaste-
Paket wurde anschließend ohne `devmode` installiert. `--diagnose` beendet sich
mit Exit 0 / `ok: true`; Whisper, FFI-Guard und Smart-Mode-Bibliothek samt
CPU-Backends laden erfolgreich. Auch der normale Start zeigt das Onboarding.

Die Standard-Schnittstellen und GNOME-/Mesa-Inhalte wurden automatisch verbunden;
`audio-record` und `uinput` ließen sich manuell verbinden. `/dev/uinput` fehlt im
Lab weiterhin, der virtuelle Desktop hat keinen Tray-Host. Aufnahme, tatsächliche
Transkription, automatisches Einfügen, Import und Autostart sind mit diesem
Starttest noch nicht abgenommen. Vor `stable` bleibt die vollständige Desktop-
Abnahme erforderlich.

## Berechtigungen und Abnahme

| Funktion | Schnittstelle |
|---|---|
| Fenster und Zwischenablage | wayland, x11, desktop, desktop-legacy |
| Hotkey / Desktop-Integration | unity7, Desktop-Portale |
| Mikrofon / Wiedergabe | audio-record, audio-playback |
| Downloads / optionale Cloud | network |
| Virtuelle Tastatureingabe | uinput |

Ohne Store-Auto-Verbindungsfreigabe bei Bedarf manuell verbinden:

```bash
sudo snap connect whispaste:audio-record
sudo snap connect whispaste:uinput
snap connections whispaste
```

Die uinput-Verbindung hebt Unix-Dateirechte auf `/dev/uinput` **nicht** auf.
Host-Berechtigungen bzw. ein geeigneter Portal-Weg müssen separat funktionieren.
Ohne automatische Eingabe bleibt manuelles Einfügen aus der Zwischenablage.
Eine hostweite udev-Regel wird nicht automatisch durch den Snap installiert.

Vor `stable` auf einem frischen Linux-Desktop prüfen:

- Start ohne fehlende Bibliotheken oder AppArmor-Abbrüche;
- Mikrofonaufnahme, Modell-Download und lokale Transkription;
- Hotkey, Zwischenablage und Einfügen unter Wayland/X11;
- Audiodatei-Import, Tray, Autostart und gespeicherte Einstellungen.

Der Snap-Inhalt ist read-only. Veränderliche Daten und heruntergeladene
Komponenten gehören in die Snap-Benutzerverzeichnisse. Schreibpfade und Ausführung
dieser Komponenten sind Teil der Laufzeitabnahme, keine Zusicherung des Manifests.

```bash
sudo snap install --dangerous ./whispaste_1.5.2_amd64.snap
snap run whispaste
# Diagnose benötigt ein Display, headless gegebenenfalls:
xvfb-run -a snap run whispaste --diagnose
```

## Store und Versionspflege

1. `version`, Release-URL und `source-checksum` gemeinsam aktualisieren. Hash
   gegen das heruntergeladene Asset prüfen.
2. Release-Notiz in beiden Metainfo-Kopien ergänzen.
3. Erweiterungen prüfen, bauen und Artefakt kontrollieren.
4. `snapcraft upload ./whispaste_<version>_amd64.snap` lädt ohne Kanal-Freigabe
   hoch. Review-Status im Dashboard prüfen.
5. Erst nach Store-Freigabe und Laufzeitabnahme mit
   `snapcraft release whispaste <revision> stable` veröffentlichen, Listing
   öffentlich schalten und Installation über den Store prüfen.

Keine erneute Namensregistrierung nötig. Zugangsdaten verbleiben in der lokalen
Snapcraft-Konfiguration und gehören niemals ins Build-Verzeichnis.
