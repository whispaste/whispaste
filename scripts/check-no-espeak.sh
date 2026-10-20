#!/usr/bin/env bash
# check-no-espeak.sh — release guard: fails when any native binary under the
# given paths carries espeak-ng or piper-phonemize code, or when such a file
# name appears at all. WhisPaste is MIT and does not use TTS; espeak-ng is
# GPL-3.0-or-later, so no release bundle may contain it (see BUILD.md,
# "sherpa-onnx without TTS").
#
# Native binaries are recognised by their magic bytes (ELF, Mach-O incl. fat,
# PE/MZ), not only by extension, so a renamed library is still scanned. The
# markers are plain ASCII in the symbol/string tables of every format, so a
# byte-level grep works identically on macOS, Linux and Windows (Git Bash) and
# needs no nm/strings/dumpbin.
#
# The guard refuses to pass vacuously: zero scanned native files is an error.
#
# Two checks per native file (GS-009):
#   1. byte markers (above), works on any format;
#   2. symbol names of ELF and Mach-O files via nm (exported and imported
#      symbols). A name that is not in the marker list but starts with espeak or
#      piper is caught here. PE files use objdump -p when it is installed.
# Limits: both checks are name-based. Code that is compiled in without any
# symbol or string naming espeak/piper (renamed, stripped and obfuscated
# sources) is not detected; the license review of the build inputs
# (scripts/build-sherpa-onnx.sh, sherpa-onnx's TTS=OFF build) is the control for
# that. A native file whose symbols cannot be read is a failure, not a pass.
#
# Usage: scripts/check-no-espeak.sh <file-or-dir>...
set -uo pipefail
export LC_ALL=C

MARKERS='espeak_ng_|espeak-ng|espeak_Initialize|phontab|phondata|piper::|DEFAULT_PHONEME_MAP'

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <file-or-dir>..." >&2
  exit 2
fi

is_native_magic() {
  local magic
  magic="$(od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \n')"
  case "$magic" in
    7f454c46*) return 0 ;;                 # ELF
    feedfacf*|cffaedfe*|feedface*|cefaedfe*) return 0 ;;  # Mach-O thin
    cafebabe*|bebafeca*) return 0 ;;       # Mach-O fat (also Java class; harmless)
    4d5a*) return 0 ;;                     # PE / MZ (DLL, EXE)
  esac
  return 1
}

SYMBOL_PATTERN='^_{1,2}(ZN5piper|espeak|piper)'

is_elf_or_macho() {
  local magic
  magic="$(od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \n')"
  case "$magic" in
    7f454c46*|feedfacf*|cffaedfe*|feedface*|cefaedfe*|cafebabe*|bebafeca*) return 0 ;;
  esac
  return 1
}

is_pe() {
  [[ "$(od -An -N2 -tx1 "$1" 2>/dev/null | tr -d ' \n')" == 4d5a* ]]
}

# Prints the symbol names of an ELF or Mach-O file, one per line (last field of nm).
symbol_names() {
  local out
  out="$(nm -D "$1" 2>/dev/null)" || out="$(nm -g "$1" 2>/dev/null)" || return 1
  printf '%s\n' "$out" | awk 'NF { print $NF }'
}

fail=0
scanned=0
symbol_checked=0

check_file() {
  local path="$1" name native=0
  name="$(basename "$path")"
  if [[ "$name" == *espeak* || "$name" == *piper* ]]; then
    echo "FAIL (file name): $path"
    fail=1
  fi
  case "$name" in
    *.dylib|*.so|*.so.*|*.dll|*.exe) native=1 ;;
  esac
  if is_native_magic "$path"; then native=1; fi
  if [[ $native -eq 0 ]]; then
    return 0
  fi
  scanned=$((scanned + 1))
  if grep -a -q -E "$MARKERS" "$path"; then
    echo "FAIL (espeak/piper marker found): $path"
    grep -a -o -E "${MARKERS}[A-Za-z0-9_:.-]*" "$path" | sort -u | head -5 | sed 's/^/    /'
    fail=1
  fi
  check_symbols "$path"
}

check_symbols() {
  local path="$1" names hits
  if is_elf_or_macho "$path"; then
    if ! names="$(symbol_names "$path")"; then
      echo "FAIL (cannot read the symbol table with nm): $path"
      fail=1
      return 0
    fi
  elif is_pe "$path"; then
    if ! command -v objdump >/dev/null 2>&1; then
      echo "note: symbol check skipped for PE file (no objdump installed), marker check only: $path" >&2
      return 0
    fi
    names="$(objdump -p "$path" 2>/dev/null | awk 'NF { print $NF }')"
  else
    return 0
  fi
  symbol_checked=$((symbol_checked + 1))
  hits="$(printf '%s\n' "$names" | grep -E "$SYMBOL_PATTERN" | sort -u | head -5 || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL (espeak/piper symbol in the symbol table): $path"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fail=1
  fi
}

for root in "$@"; do
  if [[ -f "$root" ]]; then
    check_file "$root"
  elif [[ -d "$root" ]]; then
    while IFS= read -r -d '' path; do
      check_file "$path"
    done < <(find "$root" -type f -print0)
  else
    echo "error: $root does not exist" >&2
    exit 2
  fi
done

if [[ $scanned -eq 0 ]]; then
  echo "error: no native binaries found under: $*" >&2
  exit 1
fi

if [[ $fail -ne 0 ]]; then
  echo "check-no-espeak: FAILED — espeak-ng/piper code must not ship (scanned $scanned native files)." >&2
  exit 1
fi
echo "check-no-espeak: OK ($scanned native files scanned, $symbol_checked symbol-checked, no espeak-ng/piper markers or symbols)."
