#!/usr/bin/env bash
#
# WhisPaste — third-party product name guard.
#
# Names of other dictation/transcription products must never reach the
# public export: not in public code, comments, docs, website copy or file
# paths, and never in a commit message. Public means listed in .ossallowlist
# (oss-public.sh); internal files, such as research notes, may name them. The
# patterns are stored base64-encoded on purpose, so this file itself never
# contains any of the names in plain text.
#
# Usage (exit 1 and print the offending lines on a match):
#   name-guard.sh stdin            scan text from stdin
#   name-guard.sh staged           public added lines + paths of the index
#                                  block; internal ones only get a note
#   name-guard.sh file <path>      scan one file (e.g. a commit message)
#   name-guard.sh tree <rev>       scan every public text file of a tree
#                                  (CI on the exported tree)
#
# Push ranges are not scanned: GitHub receives only the NAS export, which
# rebuilds tree and commits and checks them.
#
# Bash-3.2-compatible (macOS /bin/bash).
#
set -euo pipefail

NAME_GUARD_B64='d1tpMSF8XXNwcnx3aD9pc3BbZTNdclteYS16MC05XXswLDN9ZmxbbzBdd3xzW3XDvF1wW2UzXXJbXmEtejAtOV17MCwzfXdoP2lzcFtlM11yfHR5cFtlM11bXmEtejAtOV17MCwzfXdoP2lzcFtlM11yfG1bYTRdY1teYS16MC05XXswLDN9d2g/aXNwW2UzXXJ8ZmxbdcO8XVtpMV1kW15hLXowLTldezAsM312W28wXVtpMV1jW2UzXXx2W28wXVtpMV1jW2UzXVteYS16MC05XXswLDN9W2kxXW5rfChefFteYS16MC05XSlbbzBddHRbZTNdclteYS16MC05XXswLDN9YVtpMV0oW15hLXowLTldfCQpfChefFteYS16MC05XSlncmFuW28wXWxhKFteYS16MC05XXwkKXxoYW5keVteYS16MC05XXswLDN9Y1tvMF1tcHV0W2UzXXJ8YXF1YVteYS16MC05XXswLDN9dltvMF1baTFdY1tlM118W28wXXBbZTNdblteYS16MC05XXswLDN9d2g/W2kxXXNwcnwoXnxbXmEtejAtOV0pZHJbYTRdZ1tvMF1uKFteYS16MC05XXwkKQ=='

name_guard_regex() {
  printf '%s' "$NAME_GUARD_B64" | base64 --decode 2>/dev/null || printf '%s' "$NAME_GUARD_B64" | base64 -D
}

RX="$(name_guard_regex)"
ROOT="$(git rev-parse --show-toplevel)"
PUBLIC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/oss-public.sh"

# Pathspecs of the public paths (the .ossallowlist entries, literal). Empty
# without an allowlist, so every path is checked.
SPECS=()
if [ -f "$ROOT/.ossallowlist" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    SPECS+=("$line")
  done < "$ROOT/.ossallowlist"
fi
pub() { git --literal-pathspecs "$@" -- "${SPECS[@]+"${SPECS[@]}"}"; }

# Paths of the index that are not public.
internal_staged() {
  comm -23 <(git diff --cached --name-only --diff-filter=ACMR | sort) \
    <(git diff --cached --name-only --diff-filter=ACMR | "$PUBLIC" | sort)
}

report() {
  echo "╳ name-guard: BLOCKED — name of another dictation/transcription product found ($1):" >&2
  sed 's/^/    /' >&2
  echo "  Describe the idea in WhisPaste's own words; never name other products." >&2
  exit 1
}

scan_stdin() {
  local hits
  hits="$(grep -n -i -E -- "$RX" || true)"
  [ -z "$hits" ] || printf '%s\n' "$hits" | report "$1"
}

mode="${1:-}"
case "$mode" in
  stdin)
    scan_stdin "stdin"
    ;;
  file)
    scan_stdin "${2:?path}" < "${2:?path}"
    ;;
  staged)
    git diff --cached --name-only --diff-filter=ACMR | "$PUBLIC" \
      | scan_stdin "staged path"
    pub diff --cached -U0 --no-color --diff-filter=ACMR \
      | { grep -E '^\+' || true; } | { grep -vE '^\+\+\+ ' || true; } \
      | scan_stdin "staged change"
    internal=()
    while IFS= read -r f; do internal+=("$f"); done < <(internal_staged)
    added=""
    [ ${#internal[@]} -eq 0 ] || added="$(git --literal-pathspecs diff --cached -U0 --no-color -- "${internal[@]}" \
      | { grep -E '^\+' || true; } | { grep -vE '^\+\+\+ ' || true; })"
    if printf '%s\n' "$added" | grep -i -E -- "$RX" >/dev/null; then
      echo "name-guard: note — a product name in internal files (allowed, never exported)" >&2
    fi
    ;;
  tree)
    rev="${2:?rev}"
    hits="$(pub grep -I -n -i -E -e "$RX" "$rev" || true)"
    [ -z "$hits" ] || printf '%s\n' "$hits" | report "tree $rev"
    git ls-tree -r --name-only "$rev" | "$PUBLIC" | scan_stdin "path in $rev"
    ;;
  *)
    echo "usage: name-guard.sh stdin|staged|file <path>|tree <rev>" >&2
    exit 2
    ;;
esac
