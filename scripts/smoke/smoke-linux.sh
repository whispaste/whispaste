#!/usr/bin/env bash
# smoke-linux.sh — release package smoke test (Linux x86_64).
#
# Usage: bash scripts/smoke/smoke-linux.sh <artifact-dir>
#
# Installs the .deb, extracts every AppImage, checks each bundled ELF file for
# unresolved shared libraries (ldd) and starts each installation once with
# `whispaste --diagnose` (lib/services/headless/package_diagnose.dart) under
# Xvfb — the GTK runner opens its window before Dart's main() runs. Exits
# non-zero on any failure, so the release job stops before publishing.
#
# Needs xvfb-run, dbus-run-session and apt-get (as root or via sudo). The .deb
# is removed again at the end; nothing else outside a temp dir is touched.
#
# SMOKE_OPTIONAL_LIBS (space-separated sonames) may be missing without failing:
# libvulkan.so.1 is only needed by the ggml Vulkan backend module, which the
# engines dlopen on demand (GGML_BACKEND_DL) — a machine without a Vulkan
# loader still runs on the CPU backend.
set -euo pipefail

ARTIFACT_DIR="${1:?usage: smoke-linux.sh <artifact-dir>}"
OPTIONAL_LIBS="${SMOKE_OPTIONAL_LIBS:-libvulkan.so.1}"
DIAGNOSE_TIMEOUT="${SMOKE_DIAGNOSE_TIMEOUT:-120}"

ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

failures=0
fail() {
  echo "::error::$*"
  failures=$((failures + 1))
}

# Every ELF file under <dir> must resolve all its NEEDED libraries.
check_ldd() {
  local dir="$1" f missing lib checked=0
  while IFS= read -r -d '' f; do
    [ "$(head -c 4 "$f" | tail -c 3)" = "ELF" ] || continue
    checked=$((checked + 1))
    missing="$(ldd "$f" 2>/dev/null | awk '/=> not found/ {print $1}' | sort -u || true)"
    for lib in $OPTIONAL_LIBS; do
      missing="$(grep -vxF "$lib" <<<"$missing" || true)"
    done
    if [ -n "$missing" ]; then
      fail "$f: unresolved libraries: $(tr '\n' ' ' <<<"$missing")"
    fi
  done < <(find "$dir" -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) -print0)
  echo "ldd: checked $checked ELF files under $dir"
  if [ "$checked" -eq 0 ]; then fail "no ELF files found under $dir"; fi
}

# Starts <exe> with --diagnose; it must exit 0 and write its JSON report.
run_diagnose() {
  local exe="$1" label="$2" report="$WORK/$2.json" rc=0
  echo "── $label: $exe --diagnose"
  timeout "$DIAGNOSE_TIMEOUT" xvfb-run -a dbus-run-session -- \
    "$exe" --diagnose --out "$report" || rc=$?
  if [ -f "$report" ]; then
    cat "$report"
  else
    fail "$label: --diagnose wrote no report (the app did not reach Dart's main)"
  fi
  if [ "$rc" -ne 0 ]; then fail "$label: --diagnose exited with $rc"; fi
}

# Prints the files among its arguments with distinct content: the packaging
# scripts add a stable-name alias (a byte-identical copy) next to each
# versioned artifact, which needs no second run.
distinct() {
  [ "$#" -eq 0 ] || sha256sum "$@" | sort -k1,1 -u | cut -d' ' -f3-
}

shopt -s nullglob
mapfile -t debs < <(distinct "$ARTIFACT_DIR"/*.deb)
mapfile -t appimages < <(distinct "$ARTIFACT_DIR"/*.AppImage)

if [ "${#debs[@]}" -ne 1 ]; then
  fail "expected one distinct .deb in $ARTIFACT_DIR, found ${#debs[@]}"
else
  echo "── .deb: ${debs[0]}"
  $SUDO apt-get install -y --no-install-recommends "${debs[0]}"
  check_ldd /opt/whispaste
  run_diagnose /usr/bin/whispaste deb
  $SUDO apt-get remove -y whispaste
fi

if [ "${#appimages[@]}" -eq 0 ]; then
  fail "no .AppImage in $ARTIFACT_DIR"
fi
for img in "${appimages[@]}"; do
  name="$(basename "$img")"
  echo "── AppImage: $name"
  dir="$WORK/$name.d"
  mkdir -p "$dir"
  chmod +x "$img"
  (cd "$dir" && "$img" --appimage-extract >/dev/null)
  check_ldd "$dir/squashfs-root"
  run_diagnose "$dir/squashfs-root/AppRun" "$name"
done

if [ "$failures" -ne 0 ]; then
  echo "Linux package smoke test: $failures failure(s)."
  exit 1
fi
echo "Linux package smoke test: all packages passed."
