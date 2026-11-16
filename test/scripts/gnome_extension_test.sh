#!/usr/bin/env bash
#
# gnome_extension_test.sh - static checks for the WhisPaste Focus GNOME Shell
# extension, plus a check that the .deb ships it.
#
# Guards: metadata (JSON, UUID = folder name, shell-version 45-50), the D-Bus
# contract (names, interface XML with one read-only method and one read-only
# Version property), no eval, no window titles, no objects created in the
# constructor, the installer scripts parse, release.yml packs the extension, and
# build-deb.sh installs it under /usr/share/gnome-shell/extensions.
# Usage: bash test/scripts/gnome_extension_test.sh [repo_root]
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
UUID="whispaste-focus@whispaste.de"
EXT="$ROOT/packaging/linux/gnome-shell-extension/$UUID"
JS="$EXT/extension.js"
META="$EXT/metadata.json"
fail=0

check() { # <description> <command...>
  local desc=$1
  shift
  if "$@"; then
    echo "  ok    $desc"
  else
    echo "  FAIL  $desc"
    fail=1
  fi
}

# Static checks on the sources, all in one Python pass.
contract_ok() { # <extension.js> <metadata.json> <folder name>
  python3 - "$@" <<'PYEOF'
import json
import re
import sys
import xml.etree.ElementTree as ET

js_path, meta_path, folder = sys.argv[1:4]
js = open(js_path, encoding="utf-8").read()
meta = json.load(open(meta_path, encoding="utf-8"))
errors = []

if meta.get("uuid") != folder:
    errors.append(f"metadata uuid {meta.get('uuid')!r} != folder {folder!r}")
if meta.get("shell-version") != [str(v) for v in range(45, 51)]:
    errors.append(f"shell-version must be 45..50, got {meta.get('shell-version')!r}")
for key in ("name", "description", "url"):
    if not meta.get(key):
        errors.append(f"metadata lacks {key}")

consts = {
    "BUS_NAME": "de.whispaste.ShellFocus",
    "OBJECT_PATH": "/de/whispaste/ShellFocus",
    "PROTOCOL_VERSION": "1",
}
for name, value in consts.items():
    m = re.search(rf"const {name} = (.+?);", js)
    if not m or m.group(1).strip("'") != value:
        errors.append(f"{name} must be {value}")

m = re.search(r"INTERFACE_XML = `(.*?)`", js, re.S)
if not m:
    errors.append("INTERFACE_XML not found in extension.js")
else:
    root = ET.fromstring(m.group(1).strip())
    ifaces = root.findall("interface")
    if [i.get("name") for i in ifaces] != ["de.whispaste.ShellFocus1"]:
        errors.append("interface must be de.whispaste.ShellFocus1 only")
    iface = ifaces[0]
    methods = iface.findall("method")
    if [x.get("name") for x in methods] != ["GetFocusedWindow"]:
        errors.append("the only method must be GetFocusedWindow")
    else:
        args = methods[0].findall("arg")
        if [(a.get("direction"), a.get("type")) for a in args] != [("out", "a{sv}")]:
            errors.append("GetFocusedWindow must have exactly one out arg a{sv}")
    if iface.findall("signal"):
        errors.append("the interface must not declare signals")
    props = iface.findall("property")
    if [(p.get("name"), p.get("type"), p.get("access")) for p in props] != [
            ("Version", "u", "read")]:
        errors.append("the only property must be Version (u, read)")

if re.search(r"\beval\b|Shell\.Eval|get_title|\.title\b", js):
    errors.append("extension.js uses eval, Shell.Eval, or a window title")
if re.search(r"^\s*constructor\s*\(", js, re.M):
    errors.append("the extension must not define a constructor (create objects in enable)")
for fn in ("enable()", "disable()"):
    if fn not in js:
        errors.append(f"missing {fn}")

for e in errors:
    print(f"        {e}")
sys.exit(1 if errors else 0)
PYEOF
}

deb_ships_extension() { # <repo_root>
  local root=$1 work stub out xdir rc=0
  work="$(mktemp -d)"
  stub="$work/bundle"
  out="$work/out"
  xdir="$work/x"
  mkdir -p "$stub/lib" "$out" "$xdir"
  printf '#!/bin/sh\n' >"$stub/whispaste"
  bash "$root/packaging/deb/build-deb.sh" "$stub" 0.0.0-test "$out" >"$work/build.log" 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "        build-deb.sh failed:" >&2
    tail -n 20 "$work/build.log" >&2
  else
    dpkg-deb -x "$out/WhisPaste-0.0.0-test-linux-x64.deb" "$xdir" || rc=$?
    local dest="$xdir/usr/share/gnome-shell/extensions/$UUID"
    for f in metadata.json extension.js; do
      if ! cmp -s "$EXT/$f" "$dest/$f"; then
        echo "        $f in the .deb differs from the source (or is missing)" >&2
        rc=1
      fi
    done
  fi
  rm -rf -- "$work"
  return "$rc"
}

echo "GNOME Shell focus extension:"
check "metadata.json and extension.js exist" test -f "$META" -a -f "$JS"
check "metadata.json and extension.js pass the contract checks" contract_ok "$JS" "$META" "$UUID"
check "metadata.json is valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$META"

echo "Installer scripts:"
check "install-gnome-extension.sh parses (sh)" sh -n "$ROOT/packaging/linux/install-gnome-extension.sh"
check "make-gnome-extension-zip.sh parses (sh)" sh -n "$ROOT/packaging/linux/make-gnome-extension-zip.sh"

echo "Packaging:"
check "build-deb.sh parses" bash -n "$ROOT/packaging/deb/build-deb.sh"
check "release.yml packs the extension into the Linux tarball" \
  grep -qF "gnome-shell-extension install-gnome-extension.sh" "$ROOT/.github/workflows/release.yml"
check ".deb installs extension files under /usr/share/gnome-shell/extensions" deb_ships_extension "$ROOT"

if [[ $fail -ne 0 ]]; then
  echo "gnome_extension_test: FAILED" >&2
  exit 1
fi
echo "gnome_extension_test: all checks passed"
