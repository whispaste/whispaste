#!/usr/bin/env bash
#
# generate_appcast_channel_test.sh — smoke tests for the --channel flag of
# scripts/generate_appcast.sh (PRD §5.2/§5.3, Issue 03).
#
# This exercises the script's REAL code path (arg parsing → filename routing →
# enclosure emission → §5 signed-enclosure self-check) WITHOUT the real EdDSA
# seed, the network Sparkle bootstrap, or a real DMG. Two substitutions make it
# secret-safe and hermetic (Box-Proof Throwaway-Key pattern, PRD §2.2 Tier 3):
#
#   1. A throwaway Ed25519 keypair is generated in-process via Python
#      `cryptography`. Its 44-char base64 SEED is fed to the script through
#      SPARKLE_SIGNING_KEY; its PUBKEY verifies the emitted enclosures.
#   2. A fake `sign_update` shim (Python, Ed25519 detached-sign over the file
#      bytes) replaces the Sparkle CLI binary via SPARKLE_TOOLS_DIR, so the
#      script never reaches the internet. The shim honours the exact stdout
#      contract the real sign_update uses (`sparkle:edSignature="…" length="…"`),
#      so the script's grep-based parser is exercised verbatim.
#
# AC mapping:
#   AC-1  --channel beta → appcast-beta.xml; stable/default → appcast.xml
#   AC-2  both outputs xmllint-valid; bash -n syntax-clean
#   AC-3  both enclosures (macOS+Windows) verify against the (throwaway) pubkey
#         — secret-safe variant of "identisch signiert gegen Ek8FS/…". The
#         production Ek8FS/ wiring is asserted as a string-presence check.
#   AC-4  tampered edSignature fails verification (generator-side mechanics)
#
# No real secrets are read, logged, or committed. Run: bash test/scripts/generate_appcast_channel_test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/generate_appcast.sh"

PASS=0
FAIL=0
ok()   { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
# check <description> <0|nonzero>
check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

command -v xmllint  >/dev/null || { echo "xmllint required (libxml2)"; exit 2; }
python3 -c 'import cryptography' 2>/dev/null || { echo "python3 + cryptography required"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ART="$WORK/artifacts"; mkdir -p "$ART"
TOOLS="$WORK/sparkle-tools"; mkdir -p "$TOOLS"
KEYDIR="$WORK/keys"; mkdir -p "$KEYDIR"
SEED_FILE="$KEYDIR/seed.b64"
PUB_FILE="$KEYDIR/pub.b64"

# --- throwaway Ed25519 keypair (replaces the real ~/.config/whispaste-sparkle seed) ---
python3 - "$SEED_FILE" "$PUB_FILE" <<'PY'
import base64, sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
priv = Ed25519PrivateKey.generate()
seed = priv.private_bytes(serialization.Encoding.Raw,
                          serialization.PrivateFormat.Raw,
                          serialization.NoEncryption())
assert len(seed) == 32
pub = priv.public_key().public_bytes(serialization.Encoding.Raw,
                                      serialization.PublicFormat.Raw)
open(sys.argv[1], "w").write(base64.b64encode(seed).decode())
open(sys.argv[2], "w").write(base64.b64encode(pub).decode())
PY
SEED="$(cat "$SEED_FILE")"
[[ ${#SEED} -eq 44 ]] || { echo "seed not 44 chars"; exit 2; }

# --- fake `sign_update` shim: Ed25519 detached-sign over the payload bytes ---
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

# --- fake artifacts (bytes are irrelevant — the shim signs whatever it reads) ---
head -c 4096 /dev/urandom > "$ART/WhisPaste-macos-arm64.dmg"
head -c 2048 /dev/urandom > "$ART/WhisPaste-Setup.exe"

# common env for every invocation (no GITHUB_TOKEN → upload step is skipped)
export SPARKLE_SIGNING_KEY="$SEED"
export SPARKLE_TOOLS_DIR="$TOOLS"
export WP_ENCLOSURE_BASE="http://localhost:8765"   # deterministic, non-network URL

run_script() { bash "$SCRIPT" "$@"; }

# verifier: <appcast-xml> <artifacts-dir> <pub-file> → exit 0 iff every
# enclosure's edSignature verifies against the pubkey over its artifact bytes.
verify_enclosures() {
  python3 - "$1" "$2" "$3" <<'PY'
import re, base64, sys, pathlib
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
xml = pathlib.Path(sys.argv[1]).read_text()
adir = pathlib.Path(sys.argv[2])
pub = Ed25519PublicKey.from_public_bytes(base64.b64decode(pathlib.Path(sys.argv[3]).read_text().strip()))
fails = 0
found = 0
for m in re.finditer(r'<enclosure[^>]*url="([^"]+)"[^>]*sparkle:edSignature="([^"]+)"[^>]*length="([0-9]+)"', xml):
    found += 1
    url, sig_b64, length = m.group(1), m.group(2), m.group(3)
    data = (adir / pathlib.Path(url).name).read_bytes()
    try:
        pub.verify(base64.b64decode(sig_b64), data)
    except Exception:
        fails += 1
print("  enclosures verified: %d, failures: %d" % (found, fails))
sys.exit(1 if (fails or found == 0) else 0)
PY
}

echo "== T1: syntax + help =="
bash -n "$SCRIPT"; check "bash -n syntax-clean" "$?"
run_script --help >/dev/null; check "--help exits 0" "$?"
run_script --channel foo v1.2.44 "$ART" >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && check "invalid --channel rejected (rc=$rc)" 0 || bad "invalid --channel rejected"

echo "== T2: --channel beta → appcast-beta.xml (AC-1) =="
rm -f "$ART"/appcast*.xml
run_script --channel beta v1.2.44-beta.1 "$ART" >/dev/null
rc=$?
[[ -f "$ART/appcast-beta.xml" ]] && check "beta writes appcast-beta.xml" 0 || bad "beta writes appcast-beta.xml"
[[ ! -f "$ART/appcast.xml" ]] && check "beta does NOT write appcast.xml" 0 || bad "beta does NOT write appcast.xml"
BETA="$ART/appcast-beta.xml"
xmllint --noout "$BETA" 2>/dev/null; check "beta appcast xmllint-valid (rc=$?)" "$?"

echo "== T3: --channel stable → appcast.xml (AC-1) =="
rm -f "$ART"/appcast*.xml
run_script --channel stable v1.2.44 "$ART" >/dev/null
[[ -f "$ART/appcast.xml" ]] && check "stable writes appcast.xml" 0 || bad "stable writes appcast.xml"
STABLE="$ART/appcast.xml"
xmllint --noout "$STABLE" 2>/dev/null; check "stable appcast xmllint-valid" "$?"

echo "== T4: default (no --channel) → appcast.xml, backward-compat (AC-1) =="
rm -f "$ART"/appcast*.xml
run_script v1.2.44 "$ART" >/dev/null
[[ -f "$ART/appcast.xml" && ! -f "$ART/appcast-beta.xml" ]] && check "default = stable (no beta file)" 0 || bad "default = stable"
DEFAULT="$ART/appcast.xml"
xmllint --noout "$DEFAULT" 2>/dev/null; check "default appcast xmllint-valid" "$?"

# Re-create both channels for cross-channel checks.
rm -f "$ART"/appcast*.xml
run_script --channel beta v1.2.44-beta.1 "$ART" >/dev/null; BETA="$ART/appcast-beta.xml"
run_script --channel stable v1.2.44 "$ART" >/dev/null; STABLE="$ART/appcast.xml"

echo "== T5: both enclosures present + signed (macOS+Windows) in each channel =="
for f in "$BETA" "$STABLE"; do
  enc=$(grep -c '<enclosure' "$f" || true)
  sig=$(grep -c 'sparkle:edSignature=' "$f" || true)
  os_mac=$(grep -c 'sparkle:os="macos"' "$f" || true)
  os_win=$(grep -c 'sparkle:os="windows"' "$f" || true)
  name="$(basename "$f")"
  [[ "$enc" -eq 2 && "$sig" -eq 2 && "$os_mac" -eq 1 && "$os_win" -eq 1 ]] \
    && check "$name: 2 enclosures (macos+windows), all signed" 0 \
    || bad "$name: enclosure/signature counts enc=$enc sig=$sig mac=$os_mac win=$os_win"
done

echo "== T6: both enclosures verify against throwaway pubkey (AC-3 secret-safe) =="
verify_enclosures "$BETA"   "$ART" "$PUB_FILE"; check "beta enclosures verify vs throwaway pubkey" "$?"
verify_enclosures "$STABLE" "$ART" "$PUB_FILE"; check "stable enclosures verify vs throwaway pubkey" "$?"

echo "== T7: production Ek8FS/ pubkey wiring present (AC-3 committed-pubkey path) =="
grep -q 'Ek8FS/' "$REPO_ROOT/macos/Runner/Info.plist" \
  && check "Info.plist carries committed SUPublicEDKey (Ek8FS/)" 0 \
  || bad "Info.plist carries committed SUPublicEDKey (Ek8FS/)"
grep -q 'Ek8FS/' "$REPO_ROOT/packages/auto_updater_windows/windows/auto_updater.cpp" \
  && check "auto_updater.cpp carries committed kWhisPasteEdDSAPublicKey (Ek8FS/)" 0 \
  || bad "auto_updater.cpp carries committed kWhisPasteEdDSAPublicKey (Ek8FS/)"

echo "== T8: tampered edSignature fails verification (AC-4) =="
TAMPERED="$WORK/appcast-beta.tampered.xml"
# Flip the first base64 char of the FIRST (macOS) edSignature deterministically.
python3 - "$BETA" "$TAMPERED" <<'PY'
import sys, re, pathlib
xml = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'sparkle:edSignature="([^"]+)"', xml)
sig = m.group(1)
c0 = sig[0]
flipped = ('A' if c0 != 'A' else 'B') + sig[1:]
xml = xml.replace(sig, flipped, 1)
pathlib.Path(sys.argv[2]).write_text(xml)
PY
verify_enclosures "$TAMPERED" "$ART" "$PUB_FILE"; rc=$?
[[ $rc -ne 0 ]] && check "tampered edSignature rejected (rc=$rc)" 0 || bad "tampered edSignature rejected"

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
