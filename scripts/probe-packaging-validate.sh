#!/usr/bin/env bash
# probe-packaging-validate.sh — local re-runnable probe for the
# packaging-validate CI gate (issue 03).
#
# Usage: bash scripts/probe-packaging-validate.sh
#
# Runs the same Python validation logic that packaging-validate.yml uses:
#   - verifies the REAL manifest exits 0 (valid)
#   - verifies the BROKEN fixture exits non-zero (invalid)
# Exits 0 only when both assertions hold.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VALIDATE_PY() {
  local manifest="$1"
  python3 - "$manifest" <<'PYEOF'
import json, sys, pathlib

MANIFEST = pathlib.Path(sys.argv[1])

# 1. JSON-parseable?
try:
    data = json.loads(MANIFEST.read_text())
except json.JSONDecodeError as e:
    print(f"::error::not valid JSON: {e}")
    sys.exit(1)

errors = []

if not data.get("version"):
    errors.append("missing required field: version")

has_url = bool(data.get("url"))
has_arch = isinstance(data.get("architecture"), dict)
if not has_url and not has_arch:
    errors.append("missing required field: url (or architecture)")

has_hash = bool(data.get("hash"))
arch = data.get("architecture") or {}
has_arch_hash = any(
    isinstance(v, dict) and v.get("hash")
    for v in arch.values()
)
if not has_hash and not has_arch_hash:
    errors.append("missing required field: hash (or architecture.<arch>.hash)")

if not data.get("bin"):
    errors.append("missing required field: bin")

if not data.get("autoupdate"):
    errors.append("missing required field: autoupdate")

if errors:
    for e in errors:
        print(f"  ERROR: {e}")
    sys.exit(1)

print("  OK: all required fields present")
PYEOF
}

PASS=0
FAIL=0

echo "=== packaging-validate probe ==="
echo ""

# --- Test 1: real manifest must pass ---
REAL="$REPO_ROOT/packaging/scoop/whispaste.json"
echo "[1/3] Real manifest should pass: $REAL"
if VALIDATE_PY "$REAL"; then
  echo "  PASS"
  PASS=$((PASS+1))
else
  echo "  FAIL (real manifest rejected — manifest is broken!)"
  FAIL=$((FAIL+1))
fi

echo ""

# --- Test 2: broken fixture (missing required fields) must fail ---
BROKEN_FIELDS="$REPO_ROOT/packaging/test-fixtures/scoop-broken-missing-fields.json"
echo "[2/3] Broken fixture (missing fields) should fail: $BROKEN_FIELDS"
if VALIDATE_PY "$BROKEN_FIELDS" 2>/dev/null; then
  echo "  FAIL (broken fixture was accepted — validation logic is broken!)"
  FAIL=$((FAIL+1))
else
  echo "  PASS (correctly rejected)"
  PASS=$((PASS+1))
fi

echo ""

# --- Test 3: broken fixture (invalid JSON) must fail ---
BROKEN_JSON="$REPO_ROOT/packaging/test-fixtures/scoop-broken-invalid-json.txt"
echo "[3/3] Broken fixture (invalid JSON) should fail: $BROKEN_JSON"
if VALIDATE_PY "$BROKEN_JSON" 2>/dev/null; then
  echo "  FAIL (invalid JSON was accepted — validation logic is broken!)"
  FAIL=$((FAIL+1))
else
  echo "  PASS (correctly rejected)"
  PASS=$((PASS+1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
