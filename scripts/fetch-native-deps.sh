#!/usr/bin/env bash
#
# fetch-native-deps.sh — puts the pinned native sources into
# .build/deps/<lib>/<tag>: whisper.cpp (scripts/whisper-cpp.pin), llama.cpp
# (scripts/llama-cpp.pin) and sherpa-onnx (scripts/sherpa-onnx.pin).
#
# Each source is cloned at its pinned tag into a temporary directory next to
# the target, its commit is checked against the pin (supply-chain guard), and
# only then is it moved into place, so an interrupted or wrong fetch never
# leaves a half or foreign tree under the real name. A lock serialises
# parallel callers (two builds in one checkout). An existing tree at the
# wrong commit is an error and stays untouched.
#
#   bash scripts/fetch-native-deps.sh [whisper|llama|sherpa ...]   (default: all)
#
# Overrides (tests): NATIVE_DEPS_DIR, NATIVE_DEPS_PIN_DIR,
# NATIVE_DEPS_URL_<WHISPER|LLAMA|SHERPA>, NATIVE_DEPS_LOCK_TIMEOUT (seconds).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="${NATIVE_DEPS_DIR:-$ROOT/.build/deps}"
PINS="${NATIVE_DEPS_PIN_DIR:-$ROOT/scripts}"
LOCK="$DEPS/.fetch.lock"

die() {
  echo "fetch-native-deps: $*" >&2
  exit 1
}

# pin <file> <KEY> — the value of KEY in a pin file.
pin() {
  local value
  value="$(sed -n "s/^$2=//p" "$PINS/$1" | head -1)"
  [[ -n "$value" ]] || die "no $2 in $PINS/$1"
  printf '%s' "$value"
}

release_lock() { rm -rf "$LOCK"; }

# A mkdir lock (no flock on macOS). A lock whose owner is gone is taken over.
# A lock without a pid file is only that briefly (between mkdir and the pid
# write); one that stays ownerless longer was left by a killed run.
take_lock() {
  local waited=0 ownerless=0 owner
  local timeout="${NATIVE_DEPS_LOCK_TIMEOUT:-900}" orphan="${NATIVE_DEPS_LOCK_ORPHAN:-10}"
  mkdir -p "$DEPS"
  until mkdir "$LOCK" 2>/dev/null; do
    owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      echo "fetch-native-deps: stale lock of pid $owner, taking it over" >&2
      rm -rf "$LOCK"
      continue
    fi
    if [[ -z "$owner" ]]; then
      ownerless=$((ownerless + 1))
      if ((ownerless > orphan)); then
        echo "fetch-native-deps: lock without owner for ${orphan}s, taking it over" >&2
        rm -rf "$LOCK"
        ownerless=0
        continue
      fi
    else
      ownerless=0
    fi
    ((waited >= timeout)) && die "lock $LOCK still held by pid ${owner:-?} after ${timeout}s"
    ((waited % 30 == 0)) && echo "fetch-native-deps: waiting for pid ${owner:-?} ($LOCK)" >&2
    sleep 1
    waited=$((waited + 1))
  done
  echo $$ >"$LOCK/pid"
  trap release_lock EXIT
}

# fetch <name> <url> <tag> <commit>
fetch() {
  local name="$1" url="$2" tag="$3" commit="$4"
  local target="$DEPS/$name/$tag" actual tmp
  if [[ -e "$target" ]]; then
    actual="$(git -C "$target" rev-parse HEAD 2>/dev/null || echo unknown)"
    [[ "$actual" == "$commit" ]] ||
      die "$target is at $actual, expected $commit ($tag); remove it and run again"
    echo "  $name $tag: present"
    return 0
  fi
  mkdir -p "$DEPS/$name"
  tmp="$(mktemp -d "$DEPS/$name/.tmp.$tag.XXXXXX")"
  if ! git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$url" "$tmp/src"; then
    rm -rf "$tmp"
    die "clone of $url at $tag failed"
  fi
  actual="$(git -C "$tmp/src" rev-parse HEAD)"
  if [[ "$actual" != "$commit" ]]; then
    rm -rf "$tmp"
    die "$name $tag is at $actual upstream, the pin says $commit (supply-chain guard)"
  fi
  mv "$tmp/src" "$target"
  rm -rf "$tmp"
  echo "  $name $tag: fetched ($commit)"
}

fetch_one() {
  case "$1" in
    whisper)
      fetch whisper.cpp "${NATIVE_DEPS_URL_WHISPER:-https://github.com/ggml-org/whisper.cpp}" \
        "$(pin whisper-cpp.pin WHISPER_TAG)" "$(pin whisper-cpp.pin WHISPER_COMMIT)"
      ;;
    llama)
      fetch llama.cpp "${NATIVE_DEPS_URL_LLAMA:-https://github.com/ggml-org/llama.cpp}" \
        "$(pin llama-cpp.pin LLAMA_TAG)" "$(pin llama-cpp.pin LLAMA_COMMIT)"
      ;;
    sherpa)
      fetch sherpa-onnx "${NATIVE_DEPS_URL_SHERPA:-https://github.com/k2-fsa/sherpa-onnx}" \
        "$(pin sherpa-onnx.pin SHERPA_TAG)" "$(pin sherpa-onnx.pin SHERPA_COMMIT)"
      ;;
    *)
      echo "usage: fetch-native-deps.sh [whisper|llama|sherpa ...]" >&2
      exit 2
      ;;
  esac
}

libs=("$@")
[[ ${#libs[@]} -gt 0 ]] || libs=(whisper llama sherpa)
for lib in "${libs[@]}"; do
  case "$lib" in whisper | llama | sherpa) ;; *) fetch_one "$lib" ;; esac
done
take_lock
for lib in "${libs[@]}"; do
  fetch_one "$lib"
done
