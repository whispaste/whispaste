#!/usr/bin/env bash
# check-upstream-pins.sh — compares the pinned native sources with the newest
# stable upstream release (GitHub "latest release": drafts and pre-releases are
# never "latest").
#
#   scripts/whisper-cpp.pin   WHISPER_TAG  ggml-org/whisper.cpp
#   scripts/sherpa-onnx.pin   SHERPA_TAG   k2-fsa/sherpa-onnx
#   scripts/llama-cpp.pin     LLAMA_TAG    ggml-org/llama.cpp
#
# Default (pre-push): only warns and always exits 0. Offline, rate-limited or
# any other error → silently skipped. Upstream answers are cached for 24 h in
# the git directory, so a push costs one file read; a cache miss asks GitHub
# with a 1.5 s timeout per repo, both in parallel.
#
# --strict (before a release): exits 1 when a pin is older than upstream and
# its .pin file has no documented hold (UPSTREAM_HOLD_REASON and
# UPSTREAM_HOLD_CHECK), or when upstream cannot be checked at all.
#
# Test seams: UPSTREAM_PINS_ROOT (repo root), UPSTREAM_PINS_CACHE (cache file),
# UPSTREAM_PINS_OFFLINE=1 (never ask GitHub), UPSTREAM_PINS_NOW (epoch seconds).
set -uo pipefail

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

ROOT="${UPSTREAM_PINS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CACHE="${UPSTREAM_PINS_CACHE:-}"
if [[ -z "$CACHE" ]]; then
  gitdir="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" || gitdir=""
  [[ -n "$gitdir" && "$gitdir" != /* ]] && gitdir="$ROOT/$gitdir"
  CACHE="${gitdir:-$ROOT/.git}/upstream-pins.cache"
fi
NOW="${UPSTREAM_PINS_NOW:-$(date +%s)}"
MAX_AGE=$((24 * 3600))

# name | pin file | tag key | GitHub repo
PINS=(
  "whisper.cpp|scripts/whisper-cpp.pin|WHISPER_TAG|ggml-org/whisper.cpp"
  "sherpa-onnx|scripts/sherpa-onnx.pin|SHERPA_TAG|k2-fsa/sherpa-onnx"
  "llama.cpp|scripts/llama-cpp.pin|LLAMA_TAG|ggml-org/llama.cpp"
)


# Value of KEY in a pin file; surrounding single or double quotes removed.
pin_value() {
  sed -n "s/^$2=//p" "$ROOT/$1" 2>/dev/null | head -n 1 | tr -d '\r' |
    sed -e "s/^'\(.*\)'$/\1/" -e 's/^"\(.*\)"$/\1/'
}

# True when version $1 is older than $2 (leading "v" ignored). Build tags
# (b10150) compare by number. Tags of different schemes (b10150 against
# v0.8.0, after upstream changed its release naming) cannot be ordered and
# count as older, so the pin is reported instead of passing silently.
version_lt() {
  local a="${1#v}" b="${2#v}"
  [[ "$a" == "$b" ]] && return 1
  if [[ "$a" =~ ^b([0-9]+)$ && "$b" =~ ^b([0-9]+)$ ]]; then
    (( ${a#b} < ${b#b} )); return
  fi
  [[ "$a" =~ ^[0-9] && "$b" =~ ^[0-9] ]] || return 0
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)" == "$a" ]]
}

to_epoch() {
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null ||
    date -u -d "$1" +%s 2>/dev/null || echo ""
}

# Cache line: <repo> <tag> <published-epoch> <fetched-epoch>
cached() {
  [[ -f "$CACHE" ]] || return 1
  local line
  line="$(grep -F "$1 " "$CACHE" 2>/dev/null | tail -n 1)" || return 1
  [[ -n "$line" ]] || return 1
  local fetched="${line##* }"
  (( NOW - fetched < MAX_AGE )) || return 1
  echo "$line"
}

fetch() {
  [[ "${UPSTREAM_PINS_OFFLINE:-0}" == 1 ]] && return 1
  local json tag published
  json="$(curl -fsS --max-time 1.5 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$1/releases/latest" 2>/dev/null)" || return 1
  tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  published="$(printf '%s' "$json" | sed -n 's/.*"published_at": *"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "$tag" ]] || return 1
  published="$(to_epoch "$published")"
  echo "$1 $tag ${published:--} $NOW"
}

# Ask GitHub only for repos without a fresh cache entry, all in parallel.
tmp="$(mktemp -d)" || exit 0
trap 'rm -rf "$tmp"' EXIT
i=0
for p in "${PINS[@]}"; do
  IFS='|' read -r _ _ _ repo <<<"$p"
  if ! cached "$repo" >/dev/null; then
    fetch "$repo" >"$tmp/$i" &
  fi
  i=$((i + 1))
done
wait
if cat "$tmp"/* 2>/dev/null | grep -q .; then
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  { [[ -f "$CACHE" ]] && cat "$CACHE"; cat "$tmp"/*; } 2>/dev/null |
    awk '{ last[$1] = $0 } END { for (r in last) print last[r] }' >"$tmp/cache" &&
    cp "$tmp/cache" "$CACHE" 2>/dev/null
fi

fail=0
for p in "${PINS[@]}"; do
  IFS='|' read -r name file key repo <<<"$p"
  pinned="$(pin_value "$file" "$key")"
  line="$(cached "$repo")" || line=""
  if [[ -z "$pinned" || -z "$line" ]]; then
    if (( STRICT )); then
      echo "✗ $name: upstream release not checkable (offline or no pin) — check $repo by hand" >&2
      fail=1
    fi
    continue
  fi
  read -r _ latest published _ <<<"$line"
  version_lt "$pinned" "$latest" || continue

  days=""
  [[ "$published" != - ]] && days=" (seit $(( (NOW - published) / 86400 )) Tagen)"
  hold="$(pin_value "$file" UPSTREAM_HOLD_REASON)"
  hold_check="$(pin_value "$file" UPSTREAM_HOLD_CHECK)"
  if [[ -n "$hold" && -n "$hold_check" ]]; then
    echo "• $name $latest verfügbar$days, bewusst auf $pinned gehalten: $hold (aufheben, wenn: $hold_check)" >&2
  elif (( STRICT )); then
    echo "✗ $name $latest verfügbar$days, gepinnt ist $pinned — vor dem Release anheben (BUILD.md) oder Ausnahme in $file dokumentieren" >&2
    fail=1
  else
    echo "⚠ $name $latest verfügbar$days – Update-Paket einplanen (gepinnt: $pinned, $file)" >&2
  fi
done

(( STRICT )) && exit "$fail"
exit 0
