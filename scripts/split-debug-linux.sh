#!/usr/bin/env bash
#
# split-debug-linux.sh — move the DWARF debug info of every staged .so into a
# separate <name>.debug file, so the shipped libraries stay as small as a build
# without -g while Sentry can still symbolicate native crash frames.
#
# Usage: bash scripts/split-debug-linux.sh <stage_dir> <debug_dir>
#
# Called at the end of build-libwhisper-linux.sh / build-libllama-linux.sh
# (both build with -g). release.yml uploads <debug_dir> via sentry-cli; Sentry
# matches each .debug file to its stripped library by the GNU build-id, which
# objcopy --only-keep-debug preserves. Fails when a library has no build-id or
# no debug info, so a lost -g flag cannot silently ship unsymbolicated builds.
set -euo pipefail

STAGE_DIR="${1:?usage: split-debug-linux.sh <stage_dir> <debug_dir>}"
DEBUG_DIR="${2:?usage: split-debug-linux.sh <stage_dir> <debug_dir>}"

rm -rf "$DEBUG_DIR"
mkdir -p "$DEBUG_DIR"

count=0
while IFS= read -r so; do
  name="$(basename "$so")"
  if ! readelf -n "$so" | grep -q 'Build ID'; then
    echo "ERROR: $name has no GNU build-id — Sentry could not match its debug file." >&2
    exit 1
  fi
  if ! readelf -S "$so" | grep -q '\.debug_info'; then
    echo "ERROR: $name has no debug info — was it built without -g?" >&2
    exit 1
  fi
  objcopy --only-keep-debug "$so" "$DEBUG_DIR/$name.debug"
  objcopy --strip-debug "$so"
  count=$((count + 1))
done < <(find "$STAGE_DIR" -maxdepth 1 -type f -name '*.so*')

if [[ $count -eq 0 ]]; then
  echo "ERROR: no .so files found in $STAGE_DIR" >&2
  exit 1
fi
echo "      split debug info of $count libraries → $DEBUG_DIR"
