#!/usr/bin/env bash
# check-linux-bundled-codecs.sh — release guard for the Linux bundle (#84):
# every ELF file of the bundle that needs a Xiph codec library (FLAC, Ogg,
# Opus, Vorbis) must find exactly that file in the bundle's lib/, never on
# the system. libFLAC changes its soname between distributions (.so.8, .12,
# .14), so a system dependency only works where the build host's soname
# happens to exist; on Ubuntu 26.04 a build from 24.04 did not start at all.
#
# A file that needs one of them must also search only next to itself: every
# RUNPATH/RPATH entry starts with $ORIGIN. An absolute entry (the build tree,
# which flutter_soloud sets by default) would let the build host's copy win.
# The codec libraries themselves are exempt: they carry no RUNPATH and find
# their siblings by soname, which the loader has already loaded from lib/
# while resolving the NEEDED list of the file that uses them.
#
# Reads NEEDED entries with readelf (binutils), so it does not depend on the
# libraries the build host has installed, unlike ldd.
#
# Refuses to pass vacuously: no ELF file, or no codec dependency at all, is an
# error (the runner always needs libFLAC).
#
# Usage: scripts/check-linux-bundled-codecs.sh <bundle-dir>
set -uo pipefail
export LC_ALL=C

bundle="${1:?usage: check-linux-bundled-codecs.sh <bundle-dir>}"
lib="$bundle/lib"
command -v readelf >/dev/null || { echo "check-linux-bundled-codecs: readelf missing (binutils)" >&2; exit 2; }

elves=0
needs=0
failures=0
while IFS= read -r -d '' f; do
  [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
  elves=$((elves + 1))
  dyn="$(readelf -d "$f" 2>/dev/null)"
  # Full-version Vorbis identities load a second copy when the system audio
  # stack requests the standard ABI SONAMEs (#94). Check providers and users.
  if printf '%s\n' "$dyn" | grep -E '\((SONAME|NEEDED)\)' \
      | grep -qE '\[libvorbis(file)?\.so\.[0-9]+\.'; then
    echo "check-linux-bundled-codecs: ${f#"$bundle"/} uses a non-ABI Vorbis SONAME or NEEDED entry" >&2
    failures=$((failures + 1))
  fi
  codecs="$(printf '%s\n' "$dyn" \
    | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' \
    | grep -E '^lib(FLAC|ogg|opus|vorbis|vorbisfile)\.so')"
  [ -n "$codecs" ] || continue
  is_codec=0
  printf '%s\n' "$(basename "$f")" | grep -qE '^lib(FLAC|ogg|opus|vorbis|vorbisfile)\.so' && is_codec=1
  runpath="$(printf '%s\n' "$dyn" | grep -E '\((RUN)?PATH\)' | sed -n 's/.*\[\(.*\)\]/\1/p' | head -1)"
  if [ "$is_codec" -eq 1 ]; then
    :
  elif [ -z "$runpath" ]; then
    echo "check-linux-bundled-codecs: ${f#"$bundle"/} has no RUNPATH, the codecs would come from the system" >&2
    failures=$((failures + 1))
  else
    IFS=: read -ra entries <<< "$runpath"
    for entry in "${entries[@]}"; do
      case "$entry" in
        '$ORIGIN'|'$ORIGIN/'*) ;;
        *) echo "check-linux-bundled-codecs: ${f#"$bundle"/} RUNPATH entry $entry is outside the bundle" >&2
           failures=$((failures + 1)) ;;
      esac
    done
  fi
  while read -r name; do
    needs=$((needs + 1))
    if [ ! -f "$lib/$name" ]; then
      echo "check-linux-bundled-codecs: ${f#"$bundle"/} needs $name, not in lib/" >&2
      failures=$((failures + 1))
    fi
  done <<< "$codecs"
done < <(find "$bundle" -type f -print0)

if [ "$elves" -eq 0 ] || [ "$needs" -eq 0 ]; then
  echo "check-linux-bundled-codecs: FAILED — nothing checked ($elves ELF files, $needs codec dependencies) in $bundle" >&2
  exit 1
fi
if [ "$failures" -gt 0 ]; then
  echo "check-linux-bundled-codecs: FAILED — $failures codec dependencies or search paths point outside the bundle" >&2
  exit 1
fi
echo "check-linux-bundled-codecs: OK ($needs codec dependencies of $elves ELF files, all in lib/)"
