#!/usr/bin/env bash
# mac-build-smoke.sh <worktree> — release build of the macOS app in a worktree,
# then one start of the built app as a smoke test. Run once per merge into dev
# (fast lane, internal-notes). Local only, never
# a GitHub workflow.
#
#  1. scripts/worktree-prepare.sh (deps, stale flutter_soloud cache).
#  2. nice -n 10 flutter build macos --release (log: build/mac-smoke/build.log).
#  3. Ad-hoc re-sign of the BUILD OUTPUT without Hardened Runtime, entitlements
#     kept. Cause: ad-hoc dylibs (libonnxruntime.1.28.2.dylib) inside a
#     hardened-runtime app fail in dyld with "mapping process and mapped file
#     (non-platform)". Release signing (release-macos-local.sh, archive) is not
#     touched. Before signing, the copy takes its own bundle id
#     de.whispaste.direct.smoke: preferences live in the real
#     ~/Library/Preferences whatever HOME says, so with the preview's id
#     (.dev) a smoke run left its settings in the preview (the welcome sound
#     counted as played). MAC_SMOKE_RESIGN=0 skips this step, to reproduce the
#     dyld error.
#  4. open -n --stdout/--stderr <log> --env HOME=<throw-away dir> <App>.app
#     -n: without it LaunchServices re-activates a running app with the same
#     bundle id instead of starting this build. HOME: appDataDir()
#     derives from $HOME (packages/whispaste_diagnostics path_service), so the
#     smoke never reads or locks the user's data.
#  5. Waits up to 20 s for a process of THIS build (exact executable path) and
#     no dyld error in the log, then requires it alive 5 s more.
#  6. SIGTERM to that PID only (installed app and other previews are never
#     touched). Up to 15 s for the orderly shutdown, else SIGKILL and exit 6.
#  7. On every exit: the built app leaves LaunchServices (lsregister -u, a
#     registration of a build/ folder outlives the folder and makes System
#     Settings resolve the id to a dead path), and the smoke id's preferences,
#     caches, saved state and privacy grants are removed.
#
# Exit: 0 ok, 2 usage, 3 build, 4 signing, 5 start (no process / dyld), 6 stop.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <worktree>" >&2
  exit 2
fi
if [[ ! -d "$1" ]]; then
  echo "error: not a directory: $1" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
WT="$(cd "$1" && pwd)"
OUT="$WT/build/mac-smoke"
LOG="$OUT/app.log"
BUILD_LOG="$OUT/build.log"
SMOKE_HOME="$OUT/home"
SMOKE_ID=de.whispaste.direct.smoke
NEW=""
APP=""

stamp() { date '+%H:%M:%S'; }
log() { echo "[$(stamp)] $*"; }
die() {
  local rc=$1
  shift
  echo "smoke: FAIL — $*" >&2
  exit "$rc"
}

# PIDs whose full command line is exactly the given executable (optionally
# followed by arguments). Matching the exact build path keeps the installed
# app and other previews out of reach.
pids_of() {
  local pid cmd
  ps -axww -o pid=,command= | while read -r pid cmd; do
    if [[ "$cmd" == "$1" || "$cmd" == "$1 "* ]]; then
      echo "$pid"
    fi
  done
}

cleanup() {
  if [[ -n "$NEW" ]] && kill -0 "$NEW" 2>/dev/null; then
    kill -KILL "$NEW" 2>/dev/null || true
    echo "[$(stamp)] cleanup: killed leftover smoke pid $NEW"
  fi
  if [[ -n "$APP" ]]; then
    bash "$HERE/lsregister-cleanup.sh" "$APP" >/dev/null
  fi
  defaults delete "$SMOKE_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Preferences/$SMOKE_ID.plist" \
    "$HOME/Library/Caches/$SMOKE_ID" \
    "$HOME/Library/HTTPStorages/$SMOKE_ID" \
    "$HOME/Library/Saved Application State/$SMOKE_ID.savedState"
  tccutil reset All "$SMOKE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$OUT"

log "prepare: $WT"
"$HERE/worktree-prepare.sh" "$WT"

cd "$WT"
log "build: nice -n 10 flutter build macos --release (log: $BUILD_LOG)"
start=$SECONDS
if ! nice -n 10 flutter build macos --release >"$BUILD_LOG" 2>&1; then
  tail -n 40 "$BUILD_LOG" >&2
  die 3 "flutter build macos --release failed (full log: $BUILD_LOG)"
fi
log "build: ok after $((SECONDS - start)) s"

REL="$WT/build/macos/Build/Products/Release"
NAME_FILE="$WT/macos/Flutter/ephemeral/.app_filename"
if [[ -f "$NAME_FILE" ]]; then
  NAME="$(cat "$NAME_FILE")"
else
  shopt -s nullglob
  apps=("$REL"/*.app)
  shopt -u nullglob
  (( ${#apps[@]} == 1 )) || die 3 "cannot find the built .app in $REL"
  NAME="$(basename "${apps[0]}")"
fi
APP="$REL/$NAME"
[[ -d "$APP" ]] || die 3 "built app missing: $APP"

if [[ "${MAC_SMOKE_RESIGN:-1}" == "1" ]]; then
  ENT="$OUT/entitlements.plist"
  codesign -d --entitlements :- "$APP" >"$ENT" 2>/dev/null || true
  ent_args=()
  if [[ -s "$ENT" ]]; then
    ent_args=(--entitlements "$ENT")
  fi
  # The release build carries the release identity; the smoke copy takes its
  # own, so its start never reads or writes the installed release's or the
  # preview's privacy grants and preferences.
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $SMOKE_ID" \
    "$APP/Contents/Info.plist" || die 4 "cannot set the smoke bundle id"
  log "sign: ad hoc, without Hardened Runtime (build output only)"
  codesign --force --deep --sign - ${ent_args[@]+"${ent_args[@]}"} "$APP" >>"$BUILD_LOG" 2>&1 \
    || die 4 "ad-hoc re-sign failed (see $BUILD_LOG)"
  SIG="$OUT/signature.txt"
  codesign -dv --verbose=4 "$APP" >"$SIG" 2>&1 || true
  if grep -Eq 'flags=.*runtime' "$SIG"; then
    die 4 "runtime flag still set after re-sign (see $SIG)"
  fi
  codesign --verify --deep "$APP" >>"$BUILD_LOG" 2>&1 || die 4 "signature verify failed (see $BUILD_LOG)"
  log "sign: ok, no runtime flag"
else
  log "sign: skipped (MAC_SMOKE_RESIGN=0)"
fi

EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
EXE_PATH="$APP/Contents/MacOS/$EXE"
if [[ -n "$(pids_of "$EXE_PATH")" ]]; then
  die 5 "this build is already running (pid $(pids_of "$EXE_PATH" | tr '\n' ' ')); stop it first"
fi

rm -rf "$SMOKE_HOME"
mkdir -p "$SMOKE_HOME"
: >"$LOG"
log "start: open -n $NAME (HOME=$SMOKE_HOME, log: $LOG)"
open -n --stdout "$LOG" --stderr "$LOG" --env "HOME=$SMOKE_HOME" "$APP" \
  || die 5 "open failed"

dyld_error() {
  grep -Eq 'dyld|not valid for use in process|Library not loaded' "$LOG"
}

deadline=$((SECONDS + 20))
while :; do
  if dyld_error; then
    die 5 "dyld or code signature error at startup (see $LOG)"
  fi
  NEW="$(pids_of "$EXE_PATH" | head -n1 || true)"
  if [[ -n "$NEW" ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    die 5 "no process of this build within 20 s (see $LOG)"
  fi
  sleep 0.5
done
sleep 5
if dyld_error; then
  die 5 "dyld or code signature error after start (see $LOG)"
fi
kill -0 "$NEW" 2>/dev/null || die 5 "pid $NEW exited within 5 s (see $LOG)"
log "running: pid $NEW, no dyld errors"

log "stop: SIGTERM to pid $NEW only"
kill -TERM "$NEW"
stopped=""
for _ in $(seq 1 15); do
  if ! kill -0 "$NEW" 2>/dev/null; then
    stopped=1
    break
  fi
  sleep 1
done
if [[ -z "$stopped" ]]; then
  kill -KILL "$NEW" 2>/dev/null || true
  die 6 "pid $NEW did not quit within 15 s after SIGTERM (sent SIGKILL)"
fi

DATA="$SMOKE_HOME/Library/Application Support/WhisPaste"
if [[ -d "$DATA" ]]; then
  data="written"
else
  data="not created"
fi
rm -rf "$SMOKE_HOME"
log "smoke: OK — built, started, quit cleanly; throw-away data dir: $data; log: $LOG"
