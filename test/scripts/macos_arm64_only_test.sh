#!/usr/bin/env bash
#
# macos_arm64_only_test.sh — macOS is Apple Silicon only (#224). The Xcode
# project must pin every project-level build configuration (Debug, Release,
# Profile) to arm64 and exclude x86_64, so release and MAS builds are
# arm64-only; the manual and the Store descriptions must name Apple Silicon
# as a requirement. Dropping Intel needs macOS 13.0 as the minimum, or the
# Mac App Store rejects the update (ITMS 90981, #1740): every deployment
# target, the Podfile, the appcast and the Homebrew cask must say 13.0.
# Usage: bash test/scripts/macos_arm64_only_test.sh
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
    if not re.search(r"^\s*MACOSX_DEPLOYMENT_TARGET = 13\.0;$", b, re.M):
        print(f"FAIL: {n} lacks MACOSX_DEPLOYMENT_TARGET = 13.0"); bad = 1
for m in re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);", text):
    if m != "13.0":
        print(f"FAIL: MACOSX_DEPLOYMENT_TARGET = {m} (expected 13.0)"); bad = 1
sys.exit(bad)
PY

# No build setting may re-enable x86_64 for the release lanes.
if grep -n -E "ARCHS.*x86_64|--target-platform=darwin-x64|universal" "$ROOT/fastlane/Fastfile" | grep -v EXCLUDED_ARCHS; then
  echo "FAIL: Fastfile builds x86_64/universal"; fail=1
fi

# Minimum macOS 13.0 everywhere the build or the update feed sets it.
grep -q "^platform :osx, '13.0'" "$ROOT/macos/Podfile" || { echo "FAIL: Podfile platform is not 13.0"; fail=1; }
grep -q "\['MACOSX_DEPLOYMENT_TARGET'\] = '13.0'" "$ROOT/macos/Podfile" || { echo "FAIL: Podfile pod targets are not 13.0"; fail=1; }
grep -q "<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>" "$ROOT/scripts/generate_appcast.sh" || { echo "FAIL: appcast minimumSystemVersion is not 13.0"; fail=1; }
grep -q 'depends_on macos: ">= :ventura"' "$ROOT/packaging/homebrew/whispaste.rb" || { echo "FAIL: Homebrew cask does not require Ventura"; fail=1; }
# Bundled native libraries carry the same floor; outside Xcode cmake/clang
# would otherwise take the SDK version and the libs would not load on 13.
grep -q 'MACOS_DEPLOYMENT_TARGET="13.0"' "$ROOT/scripts/build-libwhisper-macos.sh" || { echo "FAIL: libwhisper floor is not 13.0"; fail=1; }
grep -q 'MACOS_DEPLOYMENT_TARGET="13.0"' "$ROOT/scripts/build-sherpa-onnx.sh" || { echo "FAIL: sherpa-onnx floor is not 13.0"; fail=1; }
grep -q -- '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0' "$ROOT/scripts/build-libllama-macos.sh" || { echo "FAIL: libllama floor is not 13.0"; fail=1; }
grep -q -- '-mmacosx-version-min=13.0' "$ROOT/scripts/build-smartmode-shim-macos.sh" || { echo "FAIL: smartmode shim floor is not 13.0"; fail=1; }

# Manual (all ARBs) and Store descriptions (all locales) name Apple Silicon.
for arb in "$ROOT"/lib/core/l10n/app_*.arb; do
  grep -q '"manualC01S2B3": ".*Apple Silicon.*macOS 13' "$arb" || { echo "FAIL: $arb lacks Apple Silicon / macOS 13 requirement"; fail=1; }
done
for d in "$ROOT"/fastlane/metadata/*/description.txt; do
  tail -n 3 "$d" | grep -q "Apple Silicon.*macOS 13" || { echo "FAIL: $d lacks Apple Silicon / macOS 13 requirement"; fail=1; }
done
# Developer docs name the same floor.
grep -q 'macOS:\*\* 13.0 (Ventura) or newer, Apple Silicon' "$ROOT/README.md" || { echo "FAIL: README lacks macOS 13.0 / Apple Silicon requirement"; fail=1; }
grep -q 'macOS 13 Ventura or newer (Apple Silicon)' "$ROOT/CONTRIBUTING.md" || { echo "FAIL: CONTRIBUTING lacks macOS 13 / Apple Silicon requirement"; fail=1; }
if grep -n -E 'macOS 1[0-2]([^0-9]|$)|Big Sur|Monterey' "$ROOT/CONTRIBUTING.md" "$ROOT/BUILD.md"; then
  echo "FAIL: developer docs name a macOS floor below 13"; fail=1
fi
# Website copy (all 8 locales, FAQ + schema): the floor is macOS 13; macOS 12
# may only appear as "stays on 1.4.2", never as a supported minimum.
if grep -n -E 'Big Sur|Monterey' "$ROOT"/website/src/i18n/*.ts; then
  echo "FAIL: website i18n names a macOS floor below 13"; fail=1
fi

[[ $fail -eq 0 ]] && echo "PASS: macOS is arm64-only, minimum macOS 13.0"
exit $fail
