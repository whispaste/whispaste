#!/usr/bin/env bash
#
# version_numeric_consistency_test.sh — deterministic dry-run proving:
#   (1) the Windows numeric-version derivations (NSIS installer via
#       release.yml's PRODUCT_VERSION_NUMERIC, and the Sparkle appcast's
#       Windows <item> via generate_appcast.sh's WINDOWS_VERSION_COMPARE)
#       agree with each other AND with the value Flutter's own tooling
#       embeds into the actually-running whispaste.exe (FLUTTER_VERSION_BUILD,
#       derived from pubspec.yaml's "+N" build number by
#       packages/flutter_tools/lib/src/cmake.dart's _tryDetermineBuildVersion).
#   (2) the appcast's macOS <item> (MACOS_VERSION_COMPARE) independently
#       matches FLUTTER_BUILD_NAME — the value Flutter's Xcode tooling
#       embeds as CFBundleVersion/CFBundleShortVersionString in the actually-
#       running WhisPaste.app (build_info.dart's
#       validatedBuildNameForPlatform(), driven by the pubspec version's
#       PRE-"+N" part, beta counter included) — and that it is intentionally
#       NOT required to equal the Windows value.
#
# growth-reliability-conversion issue 06 (root cause of the reported bug):
# release.yml and generate_appcast.sh's Windows-side derivation used to
# re-derive the 4th numeric version component from the "-beta.B" pre-release
# counter instead of the pubspec "+N" build number. Those are two
# INDEPENDENT counters that can diverge (e.g. "1.2.44-beta.9+10" -> counter
# 9, build number 10) — when they did, the Windows installer/appcast item
# advertised a different numeric version than the binary it shipped, so
# WinSparkle's "check for updates" re-offered the just-installed build
# forever.
#
# Rework note (this file's previous version regressed macOS): a first fix
# pass made generate_appcast.sh share ONE version value between the macOS
# and Windows <item>s, switching it to the build-number scheme — which
# fixed Windows but broke macOS, since macOS's real CFBundleVersion is
# beta-counter-based (FLUTTER_BUILD_NAME), not build-number-based. This
# suite independently re-derives BOTH expected values (Windows: build
# number; macOS: FLUTTER_BUILD_NAME's strip/pad algorithm) so a future
# regression on either platform is caught mechanically.
#
# This exercises the REAL production code, not a reimplementation:
#   - the actual "Build installer" PowerShell block, extracted verbatim from
#     release.yml (only the trailing NSIS/EXE-build tail is cut, since NSIS
#     isn't installed here — the version-computation logic under test runs
#     unmodified) and executed via pwsh against a fixture pubspec.yaml.
#   - the actual scripts/generate_appcast.sh, executed against a fixture
#     PUBSPEC_FILE with a throwaway EdDSA key + fake sign_update shim
#     (network-free, mirrors generate_appcast_channel_test.sh's Box-Proof
#     Throwaway-Key pattern), with BOTH a macOS DMG and Windows Setup.exe
#     fixture present so both <item> entries are emitted.
#
# Run: bash test/scripts/version_numeric_consistency_test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/release.yml"
APPCAST_SCRIPT="$REPO_ROOT/scripts/generate_appcast.sh"

PASS=0
FAIL=0
ok()  { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

if ! command -v pwsh >/dev/null 2>&1; then
  echo "pwsh (PowerShell) not installed — skipping (informational, not a failure)."
  exit 0
fi
python3 -c 'import yaml' 2>/dev/null || { echo "python3 + PyYAML required"; exit 2; }
python3 -c 'import cryptography' 2>/dev/null || { echo "python3 + cryptography required"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- helper: extract the "Build installer" step's `run:` text from
# release.yml, substituting the literal ${{ github.ref_name }} GitHub Actions
# expression (which real PowerShell cannot parse) with a caller-supplied ref
# value — this is what GitHub Actions itself does before the shell ever
# sees the script. ---
extract_build_installer_run() {
  local ref_value="$1"
  python3 - "$WF" "$ref_value" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
ref_value = sys.argv[2]
job = wf["jobs"]["build-windows"]
for step in job["steps"]:
    if step.get("name") == "Build installer":
        text = step["run"].replace("${{ github.ref_name }}", ref_value)
        print(text)
        sys.exit(0)
sys.exit(1)
PY
}

# --- reference derivation: mirrors cmake.dart's _tryDetermineBuildVersion
# (single-integer build-metadata after the LAST '+', else 0). Used only to
# state the EXPECTED value independently of the scripts under test. ---
expected_build_number() {
  local pubspec_version="$1"
  if [[ "$pubspec_version" =~ \+([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "0"
  fi
}

# --- reference derivation: mirrors build_info.dart's
# validatedBuildNameForPlatform() for iOS/macOS — strip everything but
# digits/dots from the PRE-"+N" pubspec version (beta counter included),
# split on '.', drop empty segments, pad to a minimum of 3 segments with
# '0'. Independent (Python) re-implementation of the algorithm, so this
# doesn't just tautologically re-check generate_appcast.sh's own bash
# implementation of the same idea. Used only to state the EXPECTED macOS
# CFBundleVersion/FLUTTER_BUILD_NAME value. ---
expected_macos_build_name() {
  local build_name_pre_plus="$1"
  python3 - "$build_name_pre_plus" <<'PY'
import re, sys
build_name = sys.argv[1]
stripped = re.sub(r'[^\d.]', '', build_name)
segments = [s for s in stripped.split('.') if s]
while len(segments) < 3:
    segments.append('0')
print('.'.join(segments))
PY
}

# run_powershell_numeric <fixture-dir> <ref-value> — runs the REAL "Build
# installer" step's version-computation logic (trailing NSIS invocation cut)
# against a fixture pubspec.yaml and prints $numeric.
run_powershell_numeric() {
  local fixture_dir="$1" ref_value="$2"
  local run_text
  run_text="$(extract_build_installer_run "$ref_value")" || return 1
  {
    printf '%s\n' "$run_text" | sed '/makensis\.exe/,$d'
    printf 'Write-Output $numeric\n'
  } > "$fixture_dir/step.ps1"
  ( cd "$fixture_dir" && pwsh -NoProfile -NonInteractive -File "$fixture_dir/step.ps1" ) 2>"$fixture_dir/stderr.log"
}

# run_appcast <tag> [pubspec-file] — runs the REAL generate_appcast.sh
# (optionally against a fixture PUBSPEC_FILE; omitted = production default,
# i.e. the real repo pubspec.yaml next to the script) with BOTH a macOS DMG
# and a Windows Setup.exe fixture present, so BOTH <item> entries get
# emitted, and prints the path to the resulting appcast.xml.
run_appcast() {
  local tag="$1" pubspec_file="${2:-}"
  local art; art="$(mktemp -d "$WORK/art-XXXXXX")"
  head -c 512 /dev/urandom > "$art/WhisPaste-macos-arm64.dmg"
  head -c 512 /dev/urandom > "$art/WhisPaste-Setup.exe"
  ( [[ -n "$pubspec_file" ]] && export PUBSPEC_FILE="$pubspec_file"
    export SPARKLE_SIGNING_KEY="$SEED" SPARKLE_TOOLS_DIR="$TOOLS" WP_ENCLOSURE_BASE="http://localhost:8765"
    bash "$APPCAST_SCRIPT" "$tag" "$art" >"$art/stdout.log" 2>&1
  )
  echo "$art/appcast.xml"
}

# appcast_version_for_os <appcast-file> <macos|windows> — extracts the
# <sparkle:version> of the <item> whose <enclosure> carries the matching
# sparkle:os attribute. The two <item>s legitimately carry DIFFERENT
# numeric versions per this issue's fix — one per platform's real
# comparison-version scheme.
appcast_version_for_os() {
  local appcast_file="$1" os="$2"
  python3 - "$appcast_file" "$os" <<'PY'
import re, sys
content = open(sys.argv[1]).read()
os_name = sys.argv[2]
for item in re.findall(r'<item>.*?</item>', content, re.S):
    if 'sparkle:os="%s"' % os_name in item:
        m = re.search(r'<sparkle:version>([^<]*)</sparkle:version>', item)
        if m:
            print(m.group(1))
            sys.exit(0)
sys.exit(1)
PY
}

# --- throwaway Ed25519 keypair + fake sign_update shim (network-free) ---
TOOLS="$WORK/sparkle-tools"; mkdir -p "$TOOLS"
python3 - "$WORK/seed.b64" <<'PY'
import base64, sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
priv = Ed25519PrivateKey.generate()
seed = priv.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
open(sys.argv[1], "w").write(base64.b64encode(seed).decode())
PY
SEED="$(cat "$WORK/seed.b64")"
cat > "$TOOLS/sign_update" <<'PY'
#!/usr/bin/env python3
import sys, base64
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
seed = base64.b64decode(sys.stdin.read().strip())
payload = sys.argv[-1]
data = open(payload, "rb").read()
sig = Ed25519PrivateKey.from_private_bytes(seed).sign(data)
print('sparkle:edSignature="%s" length="%d"' % (base64.b64encode(sig).decode(), len(data)))
PY
chmod +x "$TOOLS/sign_update"

echo "== T0: syntax =="
bash -n "$REPO_ROOT/scripts/generate_appcast.sh"; check "generate_appcast.sh bash -n syntax-clean" "$?"
python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))" 2>/dev/null; check "release.yml yaml.safe_load valid" "$?"

# ---------------------------------------------------------------------------
# Case A: beta counter != build number — the reported bug's exact shape
# ---------------------------------------------------------------------------
echo "== T1: pubspec 1.2.44-beta.9+10 (beta counter 9 != build number 10) =="
FIX_A="$WORK/fixture-a"; mkdir -p "$FIX_A"
printf 'name: whispaste\nversion: 1.2.44-beta.9+10\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n' > "$FIX_A/pubspec.yaml"
EXPECTED_A="$(expected_build_number '1.2.44-beta.9+10')"
[[ "$EXPECTED_A" == "10" ]]; check "reference derivation: build number is 10, not the beta counter 9" "$?"

NSIS_NUMERIC_A="$(run_powershell_numeric "$FIX_A" "v1.2.44-beta.9")"
[[ "$NSIS_NUMERIC_A" == "1.2.44.$EXPECTED_A" ]]
check "release.yml PRODUCT_VERSION_NUMERIC = 1.2.44.$EXPECTED_A (got: '$NSIS_NUMERIC_A')" "$?"

APPCAST_A="$(run_appcast "v1.2.44-beta.9" "$FIX_A/pubspec.yaml")"

APPCAST_WIN_A="$(appcast_version_for_os "$APPCAST_A" windows)"
[[ "$APPCAST_WIN_A" == "1.2.44.$EXPECTED_A" ]]
check "generate_appcast.sh Windows item sparkle:version = 1.2.44.$EXPECTED_A (got: '$APPCAST_WIN_A')" "$?"

[[ "$NSIS_NUMERIC_A" == "$APPCAST_WIN_A" && -n "$NSIS_NUMERIC_A" ]]
check "installer + appcast Windows-item numerics are IDENTICAL for the same release (root-cause fix, AC4)" "$?"

EXPECTED_MACOS_A="$(expected_macos_build_name '1.2.44-beta.9')"
[[ "$EXPECTED_MACOS_A" == "1.2.44.9" ]]
check "reference derivation: FLUTTER_BUILD_NAME uses the beta counter 9, not the build number 10" "$?"

APPCAST_MAC_A="$(appcast_version_for_os "$APPCAST_A" macos)"
[[ "$APPCAST_MAC_A" == "$EXPECTED_MACOS_A" ]]
check "generate_appcast.sh macOS item sparkle:version = FLUTTER_BUILD_NAME-style $EXPECTED_MACOS_A (got: '$APPCAST_MAC_A')" "$?"

[[ "$APPCAST_MAC_A" != "$APPCAST_WIN_A" ]]
check "macOS and Windows appcast items intentionally carry DIFFERENT numeric versions when beta counter != build number (regression guard)" "$?"

# Also exercise the non-tag (branch-push / pubspec-fallback) code path in
# release.yml — must derive the identical numeric regardless of which
# branch computed \$version, since the build number always comes from a
# fresh, unconditional pubspec.yaml read.
NSIS_NUMERIC_A_FALLBACK="$(run_powershell_numeric "$FIX_A" "dev")"
[[ "$NSIS_NUMERIC_A_FALLBACK" == "$NSIS_NUMERIC_A" ]]
check "release.yml numeric identical on tag-push vs. pubspec-fallback branch" "$?"

# ---------------------------------------------------------------------------
# Case B: no build number present at all (cmake.dart falls back to 0)
# ---------------------------------------------------------------------------
echo "== T2: pubspec 2.0.0-beta.3 (no +N build metadata) =="
FIX_B="$WORK/fixture-b"; mkdir -p "$FIX_B"
printf 'name: whispaste\nversion: 2.0.0-beta.3\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n' > "$FIX_B/pubspec.yaml"
EXPECTED_B="$(expected_build_number '2.0.0-beta.3')"
[[ "$EXPECTED_B" == "0" ]]; check "reference derivation: no +N -> build number 0" "$?"

NSIS_NUMERIC_B="$(run_powershell_numeric "$FIX_B" "v2.0.0-beta.3")"
[[ "$NSIS_NUMERIC_B" == "2.0.0.0" ]]
check "release.yml falls back to .0 when pubspec has no +N (got: '$NSIS_NUMERIC_B')" "$?"

APPCAST_B="$(run_appcast "v2.0.0-beta.3" "$FIX_B/pubspec.yaml")"

APPCAST_WIN_B="$(appcast_version_for_os "$APPCAST_B" windows)"
[[ "$APPCAST_WIN_B" == "2.0.0.0" ]]
check "generate_appcast.sh Windows item falls back to .0 when pubspec has no +N (got: '$APPCAST_WIN_B')" "$?"

EXPECTED_MACOS_B="$(expected_macos_build_name '2.0.0-beta.3')"
[[ "$EXPECTED_MACOS_B" == "2.0.0.3" ]]
check "reference derivation: FLUTTER_BUILD_NAME still carries the beta counter 3 even with no +N build number" "$?"

APPCAST_MAC_B="$(appcast_version_for_os "$APPCAST_B" macos)"
[[ "$APPCAST_MAC_B" == "$EXPECTED_MACOS_B" ]]
check "generate_appcast.sh macOS item sparkle:version = FLUTTER_BUILD_NAME-style $EXPECTED_MACOS_B (got: '$APPCAST_MAC_B')" "$?"

# ---------------------------------------------------------------------------
# Case C: stable release (no -beta. at all), build number present
# ---------------------------------------------------------------------------
echo "== T3: pubspec 1.2.44+22 (stable, no -beta.) =="
FIX_C="$WORK/fixture-c"; mkdir -p "$FIX_C"
printf 'name: whispaste\nversion: 1.2.44+22\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n' > "$FIX_C/pubspec.yaml"
EXPECTED_C="$(expected_build_number '1.2.44+22')"
[[ "$EXPECTED_C" == "22" ]]; check "reference derivation: stable build number is 22" "$?"

NSIS_NUMERIC_C="$(run_powershell_numeric "$FIX_C" "v1.2.44")"
[[ "$NSIS_NUMERIC_C" == "1.2.44.22" ]]
check "release.yml numeric for stable tag = 1.2.44.22 (got: '$NSIS_NUMERIC_C')" "$?"

APPCAST_C="$(run_appcast "v1.2.44" "$FIX_C/pubspec.yaml")"

APPCAST_WIN_C="$(appcast_version_for_os "$APPCAST_C" windows)"
[[ "$APPCAST_WIN_C" == "1.2.44.22" ]]
check "generate_appcast.sh Windows item numeric for stable tag = 1.2.44.22 (got: '$APPCAST_WIN_C')" "$?"

[[ "$NSIS_NUMERIC_C" == "$APPCAST_WIN_C" ]]
check "installer + appcast Windows-item numerics IDENTICAL for a stable release too" "$?"

EXPECTED_MACOS_C="$(expected_macos_build_name '1.2.44')"
[[ "$EXPECTED_MACOS_C" == "1.2.44" ]]
check "reference derivation: FLUTTER_BUILD_NAME for a stable release stays a 3-component 1.2.44 (no beta suffix to pad)" "$?"

APPCAST_MAC_C="$(appcast_version_for_os "$APPCAST_C" macos)"
[[ "$APPCAST_MAC_C" == "$EXPECTED_MACOS_C" ]]
check "generate_appcast.sh macOS item sparkle:version = FLUTTER_BUILD_NAME-style $EXPECTED_MACOS_C, NOT the build-number-padded 1.2.44.22 (got: '$APPCAST_MAC_C')" "$?"

# ---------------------------------------------------------------------------
# Case D: real repo pubspec.yaml, no PUBSPEC_FILE override (production
# default path) — proves generate_appcast.sh's default resolves to the
# real repo file, and that its current 1.2.44-beta.9+10 (the exact reported
# bug shape) is handled correctly end-to-end.
# ---------------------------------------------------------------------------
echo "== T4: real repo pubspec.yaml (production default, no fixture override) =="
REAL_PUBSPEC_VERSION="$(grep -m1 '^version:' "$REPO_ROOT/pubspec.yaml" | sed 's/^version:[[:space:]]*//')"
REAL_TAG_VERSION="${REAL_PUBSPEC_VERSION%%+*}"  # git tags never carry the +N build metadata
EXPECTED_D="$(expected_build_number "$REAL_PUBSPEC_VERSION")"
CORE_D="$(echo "$REAL_TAG_VERSION" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
EXPECTED_MACOS_D="$(expected_macos_build_name "$REAL_TAG_VERSION")"
echo "  repo pubspec.yaml version: $REAL_PUBSPEC_VERSION -> expected Windows numeric: $CORE_D.$EXPECTED_D, expected macOS numeric: $EXPECTED_MACOS_D"

APPCAST_D="$(run_appcast "v$REAL_TAG_VERSION")"

APPCAST_WIN_D="$(appcast_version_for_os "$APPCAST_D" windows)"
[[ "$APPCAST_WIN_D" == "$CORE_D.$EXPECTED_D" ]]
check "generate_appcast.sh default PUBSPEC_FILE resolves to the real repo pubspec.yaml — Windows item (got: '$APPCAST_WIN_D', want: '$CORE_D.$EXPECTED_D')" "$?"

APPCAST_MAC_D="$(appcast_version_for_os "$APPCAST_D" macos)"
[[ "$APPCAST_MAC_D" == "$EXPECTED_MACOS_D" ]]
check "generate_appcast.sh default PUBSPEC_FILE resolves to the real repo pubspec.yaml — macOS item, FLUTTER_BUILD_NAME-style (got: '$APPCAST_MAC_D', want: '$EXPECTED_MACOS_D')" "$?"

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
