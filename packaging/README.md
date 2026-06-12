# Distributions-Manifeste

Zusätzliche Installationskanäle für WhisPaste neben Microsoft Store, Website-DMG
und GitHub Releases. Alle Manifeste zeigen auf die Assets der GitHub Releases
(`whispaste/whispaste`, Tag `v<version>`).

| Kanal | Datei | Plattform | Status |
|---|---|---|---|
| Scoop | `scoop/whispaste.json` | Windows x64 | ✅ sofort nutzbar |
| winget | `winget/SilvioLindstedt.WhisPaste.*.yaml` | Windows x64 | ⚠️ PR an `microsoft/winget-pkgs` nötig |
| Homebrew Cask | `homebrew/whispaste.rb` | macOS arm64 | ⛔ erst nach Notarization veröffentlichen |
| Flatpak / Flathub | `flatpak/com.whispaste.whispaste.yml` | Linux x86_64 | ⚠️ PR an `flathub/flathub` nötig — Runbook: `flatpak/README.md` |

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

## Homebrew Cask (macOS) — erst nach Notarization

⛔ **Noch nicht veröffentlichen.** Die macOS-Builds sind derzeit nicht
Developer-ID-signiert/notarisiert. Homebrew setzt heruntergeladene Apps unter
Quarantäne; ohne Notarization blockt Gatekeeper den Start → defektes Nutzererlebnis.

Sobald der Notarization-Schritt in `release.yml` steht:
1. Tap-Repo `whispaste/homebrew-tap` anlegen, Datei als `Casks/whispaste.rb`.
2. Nutzer:
   ```bash
   brew install --cask whispaste/tap/whispaste
   ```
`livecheck` (strategy `github_latest`) meldet neue Versionen; `sha256` muss pro
Release aktualisiert werden (oder via `brew bump-cask-pr` automatisiert).

Cask nutzt das versionierte ZIP (`WhisPaste-<version>-macos-arm64.zip`), nicht die
unversionierte DMG — saubere URL fürs Versionstracking.
