#!/usr/bin/env bash
# worktree-prepare.sh <worktree> — prepares a WhisPaste worktree for a local
# macOS build. Idempotent; prints one short line per step.
#
#  1. deps: copies every missing .build/deps/<lib>/<version> from the main
#     checkout as an APFS clone (cp -c, plain copy as fallback). Without them
#     the Release build stops with "Refusing to build Release without Smart Mode".
#  2. soloud: removes a flutter_soloud cmake_build in the shared pub cache whose
#     CMakeCache points to another checkout (CMakeCache mismatch on configure).
#     Only that cache directory is removed; the next build reconfigures it.
#
# Env: PUB_CACHE overrides ~/.pub-cache (scripts/worktree-prepare.test.sh uses it).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <worktree>" >&2
  exit 2
fi
if [[ ! -d "$1" ]]; then
  echo "error: not a directory: $1" >&2
  exit 2
fi
WT="$(cd "$1" && pwd)"
COMMON_DIR="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
  echo "error: $WT is not a git worktree" >&2
  exit 2
}
MAIN="$(dirname "$COMMON_DIR")"

echo "worktree-prepare: $WT"

# 1. deps — copy what the main checkout has and this worktree lacks.
src_root="$MAIN/.build/deps"
dst_root="$WT/.build/deps"
copied=0
present=0
if [[ "$MAIN" == "$WT" ]]; then
  echo "  deps: main checkout, nothing to copy"
elif [[ ! -d "$src_root" ]]; then
  echo "  deps: none in main checkout ($src_root), nothing to copy"
else
  shopt -s nullglob
  for lib in "$src_root"/*/; do
    lib_name="$(basename "$lib")"
    for ver in "$lib"*/; do
      ver_name="$(basename "$ver")"
      dst="$dst_root/$lib_name/$ver_name"
      if [[ -e "$dst" ]]; then
        present=$((present + 1))
        continue
      fi
      mkdir -p "$dst_root/$lib_name"
      if ! cp -cR "${ver%/}" "$dst" 2>/dev/null; then
        rm -rf "$dst"
        cp -R "${ver%/}" "$dst"
      fi
      copied=$((copied + 1))
      echo "  deps: copied $lib_name/$ver_name"
    done
  done
  shopt -u nullglob
  echo "  deps: copied $copied, already present $present"
fi

# 2. soloud — a cmake_build whose cache names another home directory breaks
#    configure with a CMakeCache mismatch. The pub cache is shared by all
#    worktrees, so the expected home is the one under THIS worktree's ephemeral
#    symlink. A false positive only costs one reconfigure.
pub="${PUB_CACHE:-$HOME/.pub-cache}"
expected_home="$WT/macos/Flutter/ephemeral/.symlinks/plugins/flutter_soloud/macos"
removed=0
shopt -s nullglob
for build in "$pub"/hosted/pub.dev/flutter_soloud-*/macos/cmake_build; do
  for cache in "$build"/CMakeCache.txt "$build"/*/CMakeCache.txt; do
    [[ -f "$cache" ]] || continue
    home="$(grep -m1 '^CMAKE_HOME_DIRECTORY:INTERNAL=' "$cache" | cut -d= -f2- || true)"
    if [[ "$home" != "$expected_home" ]]; then
      rm -rf "$build"
      removed=$((removed + 1))
      echo "  soloud: removed foreign cmake_build (cache home: ${home:-none}): $build"
    fi
    break
  done
done
shopt -u nullglob
if (( removed == 0 )); then
  echo "  soloud: ok, no foreign cmake_build"
fi

echo "done"
