#!/usr/bin/env bash
#
# macos_arm64_only_test.sh — macOS is Apple Silicon only (#224). The Xcode
# project must pin every project-level build configuration (Debug, Release,
# Profile) to arm64 and exclude x86_64, so release and MAS builds are
# arm64-only; the manual and the Store descriptions must name Apple Silicon
# as a requirement. Usage: bash test/scripts/macos_arm64_only_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PBX="${PBX_OVERRIDE:-$ROOT/macos/Runner.xcodeproj/project.pbxproj}"
fail=0

# Project-level configurations are the ones that set SDKROOT = macosx.
python3 - "$PBX" <<'PY' || fail=1
import re, sys
text = open(sys.argv[1]).read()
blocks = re.findall(r"isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\n\t\t\t\};\n\t\t\tname = (\w+);", text, re.S)
project = [(n, b) for b, n in blocks if "SDKROOT = macosx;" in b]
names = sorted(n for n, _ in project)
if names != ["Debug", "MAS", "Profile", "Release"]:
    print(f"FAIL: expected Debug/MAS/Profile/Release project configs, found {names}")
    sys.exit(1)
bad = 0
for n, b in project:
    if not re.search(r"^\s*ARCHS = arm64;$", b, re.M):
        print(f"FAIL: {n} lacks ARCHS = arm64"); bad = 1
    if not re.search(r"^\s*EXCLUDED_ARCHS = x86_64;$", b, re.M):
        print(f"FAIL: {n} lacks EXCLUDED_ARCHS = x86_64"); bad = 1
sys.exit(bad)
PY

# No build setting may re-enable x86_64 for the release lanes.
if grep -n -E "ARCHS.*x86_64|--target-platform=darwin-x64|universal" "$ROOT/fastlane/Fastfile" | grep -v EXCLUDED_ARCHS; then
  echo "FAIL: Fastfile builds x86_64/universal"; fail=1
fi

# Manual (all ARBs) and Store descriptions (all locales) name Apple Silicon.
for arb in "$ROOT"/lib/core/l10n/app_*.arb; do
  grep -q '"manualC01S2B3": ".*Apple Silicon' "$arb" || { echo "FAIL: $arb lacks Apple Silicon requirement"; fail=1; }
done
for d in "$ROOT"/fastlane/metadata/*/description.txt; do
  tail -n 3 "$d" | grep -q "Apple Silicon" || { echo "FAIL: $d lacks Apple Silicon requirement"; fail=1; }
done

[[ $fail -eq 0 ]] && echo "PASS: macOS is arm64-only"
exit $fail
