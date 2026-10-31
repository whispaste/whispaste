#!/usr/bin/env bash
# packaging-validate.sh — the deterministic checks of the distribution
# manifests under packaging/ (Scoop, Homebrew, Flatpak, AppImage/.deb, Snap,
# GNOME Shell extension). One source for CI (.github/workflows/
# packaging-validate.yml) and the pre-push hook, which runs it on the lab's
# Ubuntu guest whenever a push touches an input listed in INPUTS below.
# winget needs Windows and stays in the workflow.
#
# Usage: bash scripts/ci/packaging-validate.sh [--install-deps] [check...]
#   check           scoop homebrew flatpak appimage-deb snap gnome-extension
#                   (default: all)
#   --install-deps  apt-get the missing validators (Ubuntu with sudo)
#   --inputs        print the input paths (for the pre-push hook) and exit
# Exit 0: all checks pass. 1: a check failed. 2: a validator is missing.
# Runs every check even after a failure, so one run names all findings.
set -uo pipefail

# Every path the checks read. The workflow's push filter and the pre-push
# hook both use this list; a check that reads a new path adds it here.
INPUTS=(
  packaging
  assets/icons/app_icon_512.png
  test/scripts/gnome_extension_test.sh
  test/scripts/deb_uinput_consent_test.sh
  .github/workflows/release.yml
  .github/workflows/packaging-validate.yml
  scripts/ci/packaging-validate.sh
)

ALL=(scoop homebrew flatpak appimage-deb snap gnome-extension)
INSTALL=0
CHECKS=()
for a in "$@"; do
  case "$a" in
    --install-deps) INSTALL=1 ;;
    --inputs) printf '%s\n' "${INPUTS[@]}"; exit 0 ;;
    -*) echo "packaging-validate: unknown option $a" >&2; exit 2 ;;
    *) CHECKS+=("$a") ;;
  esac
done
[ "${#CHECKS[@]}" -gt 0 ] || CHECKS=("${ALL[@]}")

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")" || exit 2

# Validator -> apt package, only for the checks that need it.
missing_pkgs() {
  local c
  for c in "${CHECKS[@]}"; do
    case "$c" in
      homebrew) command -v ruby >/dev/null || echo ruby ;;
      flatpak)
        python3 -c 'import yaml' 2>/dev/null || echo python3-yaml
        command -v desktop-file-validate >/dev/null || echo desktop-file-utils
        command -v appstreamcli >/dev/null || echo appstream ;;
      snap) python3 -c 'import yaml' 2>/dev/null || echo python3-yaml ;;
    esac
  done | sort -u
}

for c in "${CHECKS[@]}"; do
  case " ${ALL[*]} " in *" $c "*) ;; *) echo "packaging-validate: unknown check $c" >&2; exit 2 ;; esac
done

PKGS="$(missing_pkgs | tr '\n' ' ')"
if [ -n "$PKGS" ] && [ "$INSTALL" = 1 ]; then
  # Retried + hard-bounded: run 32296050925 hit an azure.archive.ubuntu.com
  # mirror that answered every line with `Ign:` and never returned, so the
  # job sat until GitHub killed it at exactly 6h00m. A dead mirror is
  # transient and unrelated to the manifests under test, so retry it, but
  # never wait more than 2 min per attempt.
  for attempt in 1 2 3; do
    timeout 120 sudo apt-get update -qq && break
    if [ "$attempt" -eq 3 ]; then
      echo "::error::apt-get update failed after 3 attempts."
      exit 2
    fi
    echo "apt-get update failed (attempt $attempt/3), retrying in 15s."
    sleep 15
  done
  # shellcheck disable=SC2086 # one word per package
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PKGS >/dev/null || exit 2
  PKGS="$(missing_pkgs | tr '\n' ' ')"
fi
if [ -n "$PKGS" ]; then
  echo "packaging-validate: missing validators (apt packages: ${PKGS% }); rerun with --install-deps" >&2
  exit 2
fi

scoop_manifest_valid() { # <manifest>
( # Validate Scoop JSON
set -euo pipefail
MANIFEST="$1"
echo "Validating $MANIFEST …"

# 1. JSON-parseable?
python3 -c "import json,sys; json.load(open('$MANIFEST'))" \
  || { echo "::error::$MANIFEST is not valid JSON"; exit 1; }
echo "  ✓ JSON parse OK"

# 2. Required top-level fields
python3 - "$MANIFEST" <<'PYEOF'
import json, sys, pathlib

MANIFEST = pathlib.Path(sys.argv[1])
data = json.loads(MANIFEST.read_text())

errors = []

# version
if not data.get("version"):
    errors.append("missing required field: version")

# url / architecture (Scoop accepts either a top-level url or an
# architecture block with per-arch url entries)
has_url = bool(data.get("url"))
has_arch = isinstance(data.get("architecture"), dict)
if not has_url and not has_arch:
    errors.append("missing required field: url (or architecture)")

# hash (same dual-path logic as url)
has_hash = bool(data.get("hash"))
arch = data.get("architecture") or {}
has_arch_hash = any(
    isinstance(v, dict) and v.get("hash")
    for v in arch.values()
)
if not has_hash and not has_arch_hash:
    errors.append("missing required field: hash (or architecture.<arch>.hash)")

# bin
if not data.get("bin"):
    errors.append("missing required field: bin")

# autoupdate
if not data.get("autoupdate"):
    errors.append("missing required field: autoupdate")

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

print("  ✓ All required fields present")
PYEOF
)
}

# The real manifest must pass and each broken fixture must fail, so a check
# that accepts anything cannot pass unnoticed.
check_scoop() {
  scoop_manifest_valid packaging/scoop/whispaste.json || return 1
  local f ok=0
  for f in packaging/test-fixtures/scoop-broken-*; do
    if scoop_manifest_valid "$f" >/dev/null 2>&1; then
      echo "::error::the Scoop check accepted the broken fixture $f"
      ok=1
    fi
  done
  [ "$ok" -eq 0 ] && echo "  ✓ broken fixtures rejected"
}

check_homebrew() {
( # Validate Homebrew cask
set -euo pipefail
CASK="packaging/homebrew/whispaste.rb"
echo "Validating $CASK …"

# 1. Ruby-parseable?
ruby -c "$CASK" >/dev/null \
  || { echo "::error::$CASK is not valid Ruby"; exit 1; }
echo "  ✓ Ruby syntax OK"

# 2. Required cask stanzas present
fail=0
for stanza in 'cask "whispaste" do' 'version ' 'sha256 ' 'url ' 'name ' 'desc ' 'homepage ' 'app '; do
  grep -qF "$stanza" "$CASK" \
    || { echo "::error::missing required stanza: ${stanza% }"; fail=1; }
done
[ "$fail" -eq 0 ] || exit 1
echo "  ✓ All required stanzas present"
)
}

check_flatpak() {
( # Validate Flatpak manifest YAML + required finish-args
set -euo pipefail
MANIFEST="packaging/flatpak/de.whispaste.app.yml"
echo "Validating $MANIFEST …"

# 1. YAML-parseable?
python3 -c "import yaml; yaml.safe_load(open('$MANIFEST'))" \
  || { echo "::error::$MANIFEST is not valid YAML"; exit 1; }
echo "  ✓ YAML parse OK"

# 2. Required top-level keys + finish-args covering every app function
#    (Hotkey, Clipboard/Paste, Audio, Network self-download +
#    writable data dir). See packaging/flatpak/README.md audit table.
python3 - "$MANIFEST" <<'PYEOF'
import sys, yaml, pathlib

MANIFEST = pathlib.Path(sys.argv[1])
data = yaml.safe_load(MANIFEST.read_text())
errors = []

# App-ID must match the existing reverse-DNS identifier.
if data.get("app-id") != "de.whispaste.app":
    errors.append("app-id must be de.whispaste.app")

for key in ("runtime", "sdk", "command", "modules", "finish-args"):
    if not data.get(key):
        errors.append(f"missing required key: {key}")

fa = data.get("finish-args") or []
required_args = {
    # Audio (Aufnahme)
    "--socket=pulseaudio": "audio",
    # Network self-download of the Sprachdienst
    "--share=network": "network self-download",
    # Display sockets (clipboard/paste and the X11 hotkey ride on these)
    "--socket=wayland": "wayland display",
    "--socket=fallback-x11": "x11 display",
    # Named session-bus services (F-18 / R-03)
    "--talk-name=org.kde.StatusNotifierWatcher": "tray",
    "--talk-name=org.freedesktop.Notifications": "notifications",
    "--talk-name=org.freedesktop.secrets": "secret service",
}
for arg, label in required_args.items():
    if arg not in fa:
        errors.append(f"missing finish-arg for {label}: {arg}")

# Whole session bus is a sandbox escape (F-18 / R-03).
if "--socket=session-bus" in fa:
    errors.append(
        "--socket=session-bus is forbidden; use named --talk-name= grants"
    )

# Writable data dir for the self-downloaded + executed whisper-server.
if not any(a.startswith("--filesystem=xdg-data/whispaste") for a in fa):
    errors.append(
        "missing writable data-dir finish-arg "
        "(--filesystem=xdg-data/whispaste:create)"
    )

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)
print("  ✓ Required keys + finish-args present "
      "(hotkey, clipboard/paste, audio, network self-download, "
      "writable data dir)")
PYEOF
) &&
( # Validate desktop entry
set -euo pipefail
DESKTOP="packaging/flatpak/de.whispaste.app.desktop"
echo "Validating $DESKTOP …"
desktop-file-validate "$DESKTOP" \
  || { echo "::error::$DESKTOP failed desktop-file-validate"; exit 1; }
echo "  ✓ desktop-file-validate OK"
) &&
( # Validate AppStream metainfo
set -euo pipefail
META="packaging/flatpak/de.whispaste.app.metainfo.xml"
echo "Validating $META …"
# --no-net: skip remote screenshot/URL fetches (deterministic, offline).
appstreamcli validate --no-net "$META" \
  || { echo "::error::$META failed appstreamcli validate"; exit 1; }
echo "  ✓ appstreamcli validate OK"
)
}

check_appimage_deb() {
( # Validate build-script syntax
set -euo pipefail
for s in packaging/deb/build-deb.sh packaging/appimage/build-appimage.sh; do
  echo "bash -n $s …"
  bash -n "$s" || { echo "::error::$s has a syntax error"; exit 1; }
  echo "  ✓ $s syntax OK"
done
) &&
( # .deb grants no uinput access before consent (R-02)
set -euo pipefail
bash test/scripts/deb_uinput_consent_test.sh
) &&
( # Validate .deb control metadata
set -euo pipefail
CTRL="packaging/deb/control.template"
echo "Validating $CTRL …"
fail=0
# Required control fields (Debian policy minimum for a binary package).
for field in 'Package:' 'Version:' 'Architecture:' 'Maintainer:' \
             'Depends:' 'Description:' 'Section:' 'Priority:' 'Homepage:'; do
  grep -q "^$field" "$CTRL" \
    || { echo "::error::missing control field: ${field%:}"; fail=1; }
done
# Architecture must be amd64 (x86_64 build).
grep -q '^Architecture: amd64$' "$CTRL" \
  || { echo "::error::Architecture must be amd64"; fail=1; }
# __VERSION__ placeholder must be present (substituted by build-deb.sh).
grep -q '__VERSION__' "$CTRL" \
  || { echo "::error::missing __VERSION__ placeholder in Version"; fail=1; }
# Runtime deps must cover the libraries the build-linux job links
# against (cross-checked vs the -dev packages in release.yml).
for dep in libgtk-3-0 libsecret-1-0 libnotify4 \
           libayatana-appindicator3-1 libasound2 libcurl4 \
           libkeybinder-3.0-0 libxss1; do
  grep -q "$dep" "$CTRL" \
    || { echo "::error::Depends: is missing $dep"; fail=1; }
done
# Runtime Depends: every required group must appear exactly (see
# packaging/deb/check_depends.py; libFLAC alternatives are a group).
python3 packaging/deb/check_depends.py "$CTRL" || fail=1
python3 packaging/deb/test_check_depends.py || fail=1
[ "$fail" -eq 0 ] || exit 1
echo "  ✓ control metadata + Depends complete"
) &&
( # Cross-check Depends vs build-linux -dev packages
set -euo pipefail
# The .deb runtime Depends must correspond to the -dev packages the
# build-linux job installs. Map each runtime dep → its -dev sibling and
# assert that sibling is installed in release.yml.
REL=".github/workflows/release.yml"
fail=0
# runtime-dep  ->  -dev package expected in release.yml
check() {
  grep -q "$2" "$REL" \
    || { echo "::error::release.yml lacks $2 (sibling of $1)"; fail=1; }
}
check libgtk-3-0                  libgtk-3-dev
check libsecret-1-0               libsecret-1-dev
check libnotify4                  libnotify-dev
check libayatana-appindicator3-1  libayatana-appindicator3-dev
check libasound2                  libasound2-dev
check libcurl4                    libcurl4-openssl-dev
check libkeybinder-3.0-0          libkeybinder-3.0-dev
check libxss1                     libxss-dev
check libopusfile0                libopusfile-dev
check libogg0                     libogg-dev
check libflac12                   libflac-dev
[ "$fail" -eq 0 ] || exit 1
echo "  ✓ Depends ↔ build-linux -dev packages consistent"
)
}

check_snap() {
( # Validate snapcraft.yaml YAML + required keys + plugs + confinement
set -euo pipefail
MANIFEST="packaging/snap/snapcraft.yaml"
echo "Validating $MANIFEST …"

# 1. YAML-parseable?
python3 -c "import yaml; yaml.safe_load(open('$MANIFEST'))" \
  || { echo "::error::$MANIFEST is not valid YAML"; exit 1; }
echo "  ✓ YAML parse OK"

# 2. Required top-level keys + strict confinement + plug coverage for
#    every app function (Display/Clipboard, Hotkey, Audio, Network
#    self-download). See packaging/snap/README.md confinement table.
python3 - "$MANIFEST" <<'PYEOF'
import sys, yaml, pathlib

MANIFEST = pathlib.Path(sys.argv[1])
data = yaml.safe_load(MANIFEST.read_text())
errors = []

# Snap store name is the lowercase `whispaste`; the app-id stays
# de.whispaste.app (carried in the app's common-id + desktop file).
if data.get("name") != "whispaste":
    errors.append("name must be whispaste")

for key in ("base", "version", "summary", "description",
            "grade", "confinement", "apps", "parts"):
    if not data.get(key):
        errors.append(f"missing required key: {key}")

# Strict confinement keeps the snap store-auto-reviewable.
if data.get("confinement") != "strict":
    errors.append("confinement must be strict")

# The app must reference the reverse-DNS id via common-id + desktop.
app = (data.get("apps") or {}).get("whispaste") or {}
if app.get("common-id") != "de.whispaste.app":
    errors.append("apps.whispaste.common-id must be de.whispaste.app")
if "gnome" not in (app.get("extensions") or []):
    errors.append("apps.whispaste must use the gnome extension")

# Plug coverage for every app function.
plugs = set(app.get("plugs") or [])
required_plugs = {
    # Audio (Aufnahme)
    "audio-record": "audio record",
    "audio-playback": "audio playback",
    # Network self-download of the Sprachdienst
    "network": "network self-download",
    # Hotkey + tray/appindicator (session bus)
    "unity7": "hotkey / appindicator",
    # Display sockets (clipboard/paste rides on these)
    "wayland": "wayland display",
    "x11": "x11 display",
    "desktop": "desktop session",
}
for plug, label in required_plugs.items():
    if plug not in plugs:
        errors.append(f"missing plug for {label}: {plug}")

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)
print("  ✓ Required keys + strict confinement + plugs present "
      "(display/clipboard, hotkey, audio, network self-download)")
PYEOF
)
}

check_gnome_extension() {
( # Run extension checks
set -euo pipefail
bash test/scripts/gnome_extension_test.sh
)
}

failed=()
for c in "${CHECKS[@]}"; do
  echo "── $c"
  "check_${c//-/_}" || failed+=("$c")
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "packaging-validate: FAILED: ${failed[*]}"
  exit 1
fi
echo "packaging-validate: all ${#CHECKS[@]} checks passed"
