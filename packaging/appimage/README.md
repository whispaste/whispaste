# AppImage — Direkt-Download (distro-unabhängig)

WhisPaste als **AppImage**: eine einzelne, ausführbare Datei ohne Installation,
für Nutzer, die **nicht** über Flathub/Snap installieren wollen. Zweiter
Linux-Kanal laut PRD §8.3 (Flatpak → AppImage → `.deb` → Snap).

| Datei | Zweck |
|---|---|
| `build-appimage.sh` | Baut das AppImage aus dem fertigen Linux-Release-Bundle via `linuxdeploy` |
| `AppRun` | Startskript im AppImage: setzt `usr/bin` des AppImage vorn in den `PATH` und startet `usr/bin/whispaste` |

**Mitgelieferte Tonwerkzeuge `parecord` und `pactl` (#1608):** Das
`record`-Paket nimmt mit `parecord` auf und listet Mikrofone mit `pactl`, beide
aus `pulseaudio-utils`. Ein frisches Ubuntu 26.04 Desktop hat `pipewire-pulse`
und `libpulse0`, aber nicht `pulseaudio-utils`; ohne die Werkzeuge fand die App
kein Mikrofon. Das AppImage bringt deshalb beide mit: `build-appimage.sh`
kopiert sie vom Build-Host nach `usr/bin` (unter Debian/Ubuntu ist `parecord`
ein Symlink auf `pacat`, das seine Betriebsart am eigenen Namen erkennt; kopiert
wird die echte Datei unter dem Namen `parecord`), `linuxdeploy` bündelt ihre
Bibliotheken (`libpulse`, `libpulsecommon`, `libsndfile` …) nach `usr/lib`, und
das eigene `AppRun` stellt `usr/bin` an den Anfang des `PATH`. Die
mitgelieferten Werkzeuge gehen damit nur innerhalb des AppImage vor installierte
Kopien; sie sprechen mit PulseAudio und PipeWire (`pipewire-pulse`) gleich. Der
Build bricht ab, wenn eins fehlt, nicht startet oder nicht die gebündelte
`libpulse` lädt, oder wenn `AppRun` nicht diese Datei ist. Der Build-Host braucht
dafür `pulseaudio-utils` (`release.yml` installiert es). Lizenz: LGPL-2.1+; die
Debian-`copyright`-Datei von `pulseaudio-utils` liegt im AppImage unter
`usr/share/licenses/`, die der Bibliotheken legt `linuxdeploy` unter
`usr/share/doc/` ab; in der App steht der Text auf der Lizenzseite
(`assets/licenses/pulseaudio-LICENSE.txt`, `THIRD_PARTY_NOTICES.md`). Weil `libpulse.so.0` jetzt in `usr/lib`
liegt, lädt auch die Tonausgabe (SoLoud/miniaudio, per `dlopen`) diese Kopie
statt der des Systems.

**Laufzeit-Abhängigkeit `libxss1` (XScreenSaver, Undo-Idle-Quelle):** Ob
`linuxdeploy` `libXss.so.1` mitbündelt, ist im Repo nicht verifiziert (der
Build läuft nur in CI). Bis das im Release-Build geprüft ist, gilt `libxss1` als
optionale Host-Abhängigkeit. Die Binary lädt `libXss.so.1` zur Laufzeit per
`dlopen` (`linux/runner/`), sie ist nicht dagegen gelinkt. Fehlt die Bibliothek,
startet die App normal; nur der Undo-Idle-Gate meldet „nicht verfügbar“ und
fällt sicher zurück (kein automatisches Rückgängig über die Tastatur).

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

Auf dem Build-Host müssen `linuxdeploy` und `pulseaudio-utils` liegen. Der
Release baut im Testlabor auf `ubu` (Ubuntu 26.04, GLIBC 2.43).

`linuxdeploy` bündelt die Shared-Library-Abhängigkeiten der Executable plus die
Plugin-`.so`-Dateien aus dem Flutter-`lib/`-Verzeichnis (`--library-path`) in den
AppDir und emittiert ein relocatable AppImage. Weil linuxdeploy den RUNPATH der Executable auf `$ORIGIN/../lib` umschreibt, die zur Laufzeit per Dart-FFI geladenen Bibliotheken (Sherpa, whisper, SoLoud) aber in `usr/bin/lib` liegen, verlinkt das Skript sie nach `usr/lib` und bricht den Build ab, wenn eine dort fehlt. In CI läuft das ohne FUSE über
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

## Mindestbasis (GLIBC)

Linux-Builds zielen immer auf die **aktuelle Ubuntu-LTS** (Maintainer 2026-11-16), derzeit
**Ubuntu 26.04 (GLIBC 2.43)**, ab v1.5.0. Gebaut wird auf genau dieser Version (`ubu`), und
`build-appimage.sh` bricht ab, wenn eine Datei im AppDir eine höhere GLIBC-Version verlangt
(`MAX_GLIBC`, Standard `2.43`; `linux-stage.sh` setzt den Wert ausdrücklich). Mit der nächsten
LTS steigen Build-Host und `MAX_GLIBC` gemeinsam. Bis v1.4.2 war die Basis Ubuntu 24.04 (2.39).

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
