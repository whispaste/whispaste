#!/usr/bin/env bash
#
# WhisPaste — third-party product name guard.
#
# Names of other dictation/transcription products must never enter this
# repository: not in code, comments, docs, website copy, file paths or commit
# messages. The patterns are stored base64-encoded on purpose, so this file
# itself never contains any of the names in plain text.
#
# Usage (all modes exit 1 and print the offending lines on a match):
#   name-guard.sh stdin            scan text from stdin
#   name-guard.sh staged           scan added lines + paths of the index
#   name-guard.sh file <path>      scan one file (e.g. a commit message)
#   name-guard.sh tree <rev>       scan every text file of a tree
#   name-guard.sh range <range>    scan messages, added lines and paths of
#                                  all commits in a rev range
#
# Bash-3.2-compatible (macOS /bin/bash).
#
set -euo pipefail

NAME_GUARD_B64='d1tpMSF8XXNwcnx3aD9pc3BbZTNdclteYS16MC05XXswLDN9ZmxbbzBdd3xzW3XDvF1wW2UzXXJbXmEtejAtOV17MCwzfXdoP2lzcFtlM11yfHR5cFtlM11bXmEtejAtOV17MCwzfXdoP2lzcFtlM11yfG1bYTRdY1teYS16MC05XXswLDN9d2g/aXNwW2UzXXJ8ZmxbdcO8XVtpMV1kW15hLXowLTldezAsM312W28wXVtpMV1jW2UzXXx2W28wXVtpMV1jW2UzXVteYS16MC05XXswLDN9W2kxXW5rfChefFteYS16MC05XSlbbzBddHRbZTNdclteYS16MC05XXswLDN9YVtpMV0oW15hLXowLTldfCQpfChefFteYS16MC05XSlncmFuW28wXWxhKFteYS16MC05XXwkKXxoYW5keVteYS16MC05XXswLDN9Y1tvMF1tcHV0W2UzXXJ8YXF1YVteYS16MC05XXswLDN9dltvMF1baTFdY1tlM118W28wXXBbZTNdblteYS16MC05XXswLDN9d2g/W2kxXXNwcg=='

name_guard_regex() {
  printf '%s' "$NAME_GUARD_B64" | base64 --decode 2>/dev/null || printf '%s' "$NAME_GUARD_B64" | base64 -D
}

RX="$(name_guard_regex)"

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
    git diff --cached --name-only --diff-filter=ACMR | scan_stdin "staged path"
    git diff --cached -U0 --no-color --diff-filter=ACMR \
      | { grep -E '^\+' || true; } | { grep -vE '^\+\+\+ ' || true; } \
      | scan_stdin "staged change"
    ;;
  tree)
    rev="${2:?rev}"
    hits="$(git grep -I -n -i -E -e "$RX" "$rev" -- || true)"
    [ -z "$hits" ] || printf '%s\n' "$hits" | report "tree $rev"
    git ls-tree -r --name-only "$rev" | scan_stdin "path in $rev"
    ;;
  range)
    range="${2:?range}"
    # shellcheck disable=SC2086
    git log --format='%H %B' $range | scan_stdin "commit message in $range"
    # shellcheck disable=SC2086
    git log -p -U0 --no-color --format='commit %H' $range \
      | grep -E '^(\+|commit )' | grep -vE '^\+\+\+ ' | grep -E '^\+' \
      | scan_stdin "added line in $range"
    # shellcheck disable=SC2086
    git log --name-only --format='' $range | scan_stdin "path in $range"
    ;;
  *)
    echo "usage: name-guard.sh stdin|staged|file <path>|tree <rev>|range <range>" >&2
    exit 2
    ;;
esac
