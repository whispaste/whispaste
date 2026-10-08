#!/usr/bin/env bash
# smoke-macos.sh — release package smoke test (macOS).
#
# Usage: bash scripts/smoke/smoke-macos.sh <WhisPaste.dmg | WhisPaste.app>
#
# Mounts the DMG read-only (or takes the .app directly) and checks:
#   1. the code signature (`codesign --verify --deep --strict`);
#   2. every Mach-O file in Contents/MacOS and Contents/Frameworks: each
#      linked dylib (`otool -l` LC_LOAD_DYLIB & co.) must be a system library
#      (/usr/lib, /System) or resolve to a file inside the bundle via
#      @rpath/@loader_path/@executable_path — a Homebrew or build-machine
#      path would load on the build host and fail on every user's Mac;
#   3. a start with `whispaste --diagnose`
#      (lib/services/headless/package_diagnose.dart): the report must say
#      "ok": true. Launched through `open -n` like a double click (raw Mach-O
#      execs break LaunchServices registration); --diagnose exits before any
#      UI, settings or permission (TCC) access, and -n keeps an already
#      running WhisPaste untouched.
# Exits non-zero on any failure, so the release job stops before publishing.
set -euo pipefail

TARGET="${1:?usage: smoke-macos.sh <WhisPaste.dmg | WhisPaste.app>}"
DIAGNOSE_TIMEOUT="${SMOKE_DIAGNOSE_TIMEOUT:-120}"
# SMOKE_SKIP_LAUNCH=1 runs only checks 1 and 2 (e.g. against an older build
# that has no --diagnose yet and would start the full app).
SKIP_LAUNCH="${SMOKE_SKIP_LAUNCH:-0}"

WORK="$(mktemp -d)"
MOUNT=""
# The image can stay busy for a moment after the app exits; retry before
# forcing, and never rm -rf into a still-mounted image.
cleanup() {
  if [ -n "$MOUNT" ]; then
    for _ in 1 2 3 4 5; do
      if hdiutil detach "$MOUNT" -quiet; then MOUNT=""; break; fi
      sleep 2
    done
    if [ -n "$MOUNT" ] && hdiutil detach -force "$MOUNT" -quiet; then MOUNT=""; fi
  fi
  if [ -z "$MOUNT" ]; then
    rm -rf "$WORK"
  else
    echo "::warning::could not detach $MOUNT; leaving $WORK in place"
  fi
}
trap cleanup EXIT

failures=0
fail() {
  echo "::error::$*"
  failures=$((failures + 1))
}

case "$TARGET" in
  *.dmg)
    MOUNT="$WORK/mnt"
    mkdir -p "$MOUNT"
    hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$TARGET" >/dev/null
    APP="$(find "$MOUNT" -maxdepth 1 -name '*.app' -print -quit)"
    ;;
  *.app) APP="$(cd "$TARGET" && pwd)" ;;
  *) echo "usage: smoke-macos.sh <WhisPaste.dmg | WhisPaste.app>" >&2; exit 64 ;;
esac
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "::error::no .app found in $TARGET"
  exit 1
fi
echo "── App: $APP"
EXEC_DIR="$APP/Contents/MacOS"

# 1. Code signature.
if ! codesign --verify --deep --strict "$APP"; then
  fail "codesign --verify --deep --strict failed for $APP"
fi

# 2. Linked libraries.
# Prints "<kind> <path>" for every load command of <file>; kind is LOAD,
# WEAK or RPATH.
load_commands() {
  otool -l "$1" | awk '
    /cmd LC_(LOAD_DYLIB|REEXPORT_DYLIB|LAZY_LOAD_DYLIB|LOAD_UPWARD_DYLIB)$/ { kind = "LOAD"; next }
    /cmd LC_LOAD_WEAK_DYLIB$/ { kind = "WEAK"; next }
    /cmd LC_RPATH$/ { kind = "RPATH"; next }
    kind != "" && ($1 == "name" || $1 == "path") { print kind, $2; kind = "" }
  ' | sort -u
}

# Replaces @loader_path/@executable_path in <path> for a file in <dir>.
expand_path() {
  local path="$1" dir="$2"
  path="${path/#@loader_path/$dir}"
  path="${path/#@executable_path/$EXEC_DIR}"
  printf '%s' "$path"
}

check_links() {
  local file="$1" dir kind path dep resolved rpath
  dir="$(dirname "$file")"
  # dyld searches the rpaths of the whole loader chain, so a library loaded
  # by the app also sees the main executable's rpaths.
  local -a rpaths=("${MAIN_RPATHS[@]+"${MAIN_RPATHS[@]}"}")
  while read -r kind path; do
    [ "$kind" = "RPATH" ] && rpaths+=("$(expand_path "$path" "$dir")")
  done < <(load_commands "$file")
  while read -r kind dep; do
    [ "$kind" = "RPATH" ] && continue
    case "$dep" in
      /usr/lib/* | /System/*) continue ;;
    esac
    resolved=""
    if [[ "$dep" == @rpath/* ]]; then
      for rpath in "${rpaths[@]+"${rpaths[@]}"}"; do
        if [ -e "$rpath/${dep#@rpath/}" ]; then resolved="$rpath/${dep#@rpath/}"; break; fi
      done
    elif [[ "$dep" == @loader_path/* || "$dep" == @executable_path/* ]]; then
      local candidate
      candidate="$(expand_path "$dep" "$dir")"
      if [ -e "$candidate" ]; then resolved="$candidate"; fi
    else
      fail "${file#"$APP"/} links $dep outside the bundle and the system"
      continue
    fi
    if [ -z "$resolved" ]; then
      if [ "$kind" = "WEAK" ]; then
        echo "::warning::${file#"$APP"/}: weak dependency $dep not found in the bundle"
      else
        fail "${file#"$APP"/}: $dep does not resolve inside the bundle"
      fi
    fi
  done < <(load_commands "$file")
}

MAIN_EXE="$EXEC_DIR/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
MAIN_RPATHS=()
while read -r kind path; do
  [ "$kind" = "RPATH" ] && MAIN_RPATHS+=("$(expand_path "$path" "$EXEC_DIR")")
done < <(load_commands "$MAIN_EXE")

macho_count=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  macho_count=$((macho_count + 1))
  check_links "$f"
done < <(find "$EXEC_DIR" "$APP/Contents/Frameworks" -type f -print0)
echo "otool: checked $macho_count Mach-O files"
if [ "$macho_count" -eq 0 ]; then fail "no Mach-O files found in $APP"; fi
for lib in libwhisper.dylib libsmartmode_shim.dylib; do
  if [ -f "$APP/Contents/Frameworks/$lib" ]; then
    otool -L "$APP/Contents/Frameworks/$lib"
  fi
done

# 3. Start probe.
if [ "$SKIP_LAUNCH" = "1" ]; then
  echo "SMOKE_SKIP_LAUNCH=1 — skipping the --diagnose start."
  if [ "$failures" -ne 0 ]; then exit 1; fi
  exit 0
fi
report="$WORK/diagnose.json"
log="$WORK/diagnose.log"
echo "── open -n $APP --args --diagnose"
open -W -n --stdout "$log" --stderr "$log" "$APP" --args --diagnose --out "$report" &
open_pid=$!
for _ in $(seq "$DIAGNOSE_TIMEOUT"); do
  kill -0 "$open_pid" 2>/dev/null || break
  sleep 1
done
if kill -0 "$open_pid" 2>/dev/null; then
  fail "--diagnose did not exit within ${DIAGNOSE_TIMEOUT}s"
  pkill -f "$EXEC_DIR/" || true
fi
wait "$open_pid" || true
# The app prints the same JSON report to stdout, so the log normally shows it.
if [ -s "$log" ]; then cat "$log"; fi
if [ -f "$report" ]; then
  if [ ! -s "$log" ]; then cat "$report"; fi
  if [ "$(plutil -extract ok raw -o - "$report" 2>/dev/null)" != "true" ]; then
    fail "--diagnose reported a failure"
  fi
else
  fail "--diagnose wrote no report (the app did not reach Dart's main)"
fi

if [ "$failures" -ne 0 ]; then
  echo "macOS package smoke test: $failures failure(s)."
  exit 1
fi
echo "macOS package smoke test: passed."
