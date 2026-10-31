#!/usr/bin/env bash
#
# fastlane_release_defines_test.sh — the local fastlane macOS builds must
# get the same build-time defines as the "Build macOS release" step in
# release.yml. The MAS lane shipped 1.3.0 without SUPABASE_*/WHISPASTE_MATOMO_*,
# so feedback and opt-in telemetry had no endpoint in the store build.
# Usage: bash test/scripts/fastlane_release_defines_test.sh [Fastfile] [release.yml]
set -euo pipefail

ROOT="$(dirname "$0")/../.."
FASTFILE="${1:-$ROOT/fastlane/Fastfile}"
RELEASE_YML="${2:-$ROOT/.github/workflows/release.yml}"

# Define names passed by release.yml's macOS build step (APP_VERSION has its
# own guard in fastlane_app_version_test.sh).
names=$(awk '/- name: Build macOS release/ { in_step = 1; next }
             in_step && /^      - name:/ { in_step = 0 }
             in_step' "$RELEASE_YML" \
  | grep -oE -- '--dart-define=[A-Z_]+' | sed 's/--dart-define=//' \
  | grep -v '^APP_VERSION$' | sort -u)

if [[ -z "$names" ]]; then
  echo "FAIL: no --dart-define found in release.yml's 'Build macOS release' step"
  exit 1
fi

fail=0

# The Fastfile lists the release defines it resolves in RELEASE_DART_DEFINES.
for name in $names; do
  if ! awk '/^RELEASE_DART_DEFINES = /,/\]\.freeze/' "$FASTFILE" | grep -q "\"$name\""; then
    echo "FAIL: $name from release.yml is missing in RELEASE_DART_DEFINES"
    fail=1
  fi
done

# Every macOS build passes them via the generated defines file.
builds=$(awk '/flutter build macos/ { line=$0; while (line !~ /\)[[:space:]]*$/ && (getline next_line) > 0) line = line next_line; print line }' "$FASTFILE")
if [[ -z "$builds" ]]; then
  echo "FAIL: no 'flutter build macos' found in $FASTFILE"
  exit 1
fi
while IFS= read -r cmd; do
  if [[ "$cmd" != *"--dart-define-from-file="* ]]; then
    echo "FAIL: macOS build without the release defines file: $cmd"
    fail=1
  fi
done <<< "$builds"

[[ $fail -eq 0 ]] && echo "PASS: fastlane macOS builds get every release.yml define ($(echo $names | tr '\n' ' '))"
exit $fail
