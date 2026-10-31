#!/usr/bin/env bash
#
# fastlane_app_version_test.sh — every `flutter build macos` in the local
# fastlane lanes must bake APP_VERSION in, like release.yml does. Store
# builds without it reported `whispaste@unknown` to Sentry (hang issues
# 150175307, 137343775, …), so their events matched no release and no
# uploaded dSYMs. Usage: bash test/scripts/fastlane_app_version_test.sh [Fastfile]
set -euo pipefail

FASTFILE="${1:-$(dirname "$0")/../../fastlane/Fastfile}"

# Join each sh(...) build command (split across string continuations) into
# one line, then check every macOS build line for the define.
builds=$(awk '/flutter build macos/ { line=$0; while (line !~ /\)[[:space:]]*$/ && (getline next_line) > 0) line = line next_line; print line }' "$FASTFILE")

if [[ -z "$builds" ]]; then
  echo "FAIL: no 'flutter build macos' found in $FASTFILE"
  exit 1
fi

fail=0
while IFS= read -r cmd; do
  if [[ "$cmd" != *"--dart-define=APP_VERSION="* ]]; then
    echo "FAIL: missing --dart-define=APP_VERSION: $cmd"
    fail=1
  fi
done <<< "$builds"

if ! grep -q 'upload_mas_dsyms(' "$FASTFILE"; then
  echo "FAIL: mas_release does not upload its dSYMs to Sentry"
  fail=1
fi

[[ $fail -eq 0 ]] && echo "PASS: all macOS fastlane builds set APP_VERSION and MAS uploads dSYMs"
exit $fail
