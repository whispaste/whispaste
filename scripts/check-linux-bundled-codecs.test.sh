#!/usr/bin/env bash
# Exercise the ELF identity guard with real, minimal shared libraries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/lib"
printf 'int cue(void) { return 1; }\n' > "$work/codec.c"
printf 'extern int cue(void); int play(void) { return cue(); }\n' > "$work/player.c"
cc -shared -fPIC "$work/codec.c" -Wl,-soname,libvorbis.so.0 -o "$work/lib/libvorbis.so.0"
# shellcheck disable=SC2016 # The ELF loader expands ORIGIN at runtime.
cc -shared -fPIC "$work/player.c" "$work/lib/libvorbis.so.0" \
  -Wl,-rpath,'$ORIGIN' -o "$work/lib/player.so"
bash "$ROOT/scripts/check-linux-bundled-codecs.sh" "$work" > "$work/result"

# A malformed provider must fail even when every NEEDED file exists.
patchelf --set-soname libvorbis.so.0.4.9 "$work/lib/libvorbis.so.0"
if bash "$ROOT/scripts/check-linux-bundled-codecs.sh" "$work" > "$work/result" 2>&1; then
  echo 'FAIL: full-version provider accepted' >&2; exit 1
fi
grep -q 'non-ABI Vorbis' "$work/result"
patchelf --set-soname libvorbis.so.0 "$work/lib/libvorbis.so.0"

# A stale plugin dependency must fail, including with a compatibility alias.
ln -s libvorbis.so.0 "$work/lib/libvorbis.so.0.4.9"
patchelf --replace-needed libvorbis.so.0 libvorbis.so.0.4.9 "$work/lib/player.so"
if bash "$ROOT/scripts/check-linux-bundled-codecs.sh" "$work" > "$work/result" 2>&1; then
  echo 'FAIL: full-version dependency accepted' >&2; exit 1
fi
grep -q 'non-ABI Vorbis' "$work/result"
echo 'PASS: canonical identity accepted; full-version provider and dependency rejected'
