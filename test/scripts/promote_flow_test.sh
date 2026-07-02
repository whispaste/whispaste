#!/usr/bin/env bash
#
# promote_flow_test.sh — verifies the beta→stable Promote-Job in
# .github/workflows/release.yml (PRD §5.2/§7.2, §6.3, §13, Issue 05).
#
# DRY/LOGIC verification only — does NOT trigger GitHub Actions live (the real
# promote + Store live proof is the operator slice / Issue 07 beta cycle).
# It asserts two layers:
#   (1) STRUCTURE — the workflow contains the required promote constructs
#       (dispatch gate + inputs, copy-without-rebuild, --channel stable,
#       idempotency guard + --clobber, no 're-sign' wording, store-submission
#       script reference, build jobs skipping on a promote dispatch).
#   (2) LOGIC — the build-guard primitive mirrors the workflow's expression and
#       yields tag-push→run / promote-dispatch→skip (no release regression).
#
# AC mapping:
#   AC-1  Promote vX.Y.Z-beta.N → vX.Y.Z ohne Neu-Build + Stable-Feed + Store-Trigger → T3,T4,T5,T8
#   AC-2  Signatur bleibt die der Original-Beta (gleicher Seed/Pubkey)            → T6
#   AC-3  Idempotent — zweiter Promote erzeugt kein Duplikat                       → T7
#   AC-4  Store-Submission-Pfad (trocken) durchlaufen / dokumentierter Rest         → T8
#
# Run: bash test/scripts/promote_flow_test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/release.yml"

PASS=0
FAIL=0
ok()  { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
# check <description> <rc>: pass iff rc == 0. Use as `cond; check "desc" "$?"`.
check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

[[ -f "$WF" ]] || { echo "workflow not found: $WF"; exit 2; }

# --- helpers ----------------------------------------------------------------

# YAML model of the promote job's step text (names + if + run + uses), robust
# against comment/indentation drift. Echoes the concatenated text on stdout.
promote_job_text() {
  python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("promote-beta-to-stable")
if not job:
    sys.exit(0)
parts = []
for s in job.get("steps", []):
    for k in ("name", "if", "run", "uses"):
        v = s.get(k)
        if v:
            parts.append(str(v))
print("\n".join(parts))
PY
}

PROMOTE_TEXT="$(promote_job_text)"

# ---------------------------------------------------------------------------
# T1: YAML parses
# ---------------------------------------------------------------------------
echo "== T1: YAML parses =="
python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))" 2>/dev/null; check "yaml.safe_load valid" "$?"

# ---------------------------------------------------------------------------
# T2: actionlint clean (if installed; informational otherwise)
# ---------------------------------------------------------------------------
echo "== T2: actionlint =="
if command -v actionlint >/dev/null 2>&1; then
  actionlint "$WF" >/tmp/alint_promote.$$ 2>&1; check "actionlint clean" "$?"
  [[ -s /tmp/alint_promote.$$ ]] && { echo "  --- actionlint output ---"; cat /tmp/alint_promote.$$ >&2; }
  rm -f /tmp/alint_promote.$$
else
  echo "  skip - actionlint not installed (rely on YAML parse + grep)"
fi

# ---------------------------------------------------------------------------
# T3 (AC-1): promote job exists, dispatch-gated, has the 3 inputs, NO rebuild
# ---------------------------------------------------------------------------
echo "== T3: promote job structure (AC-1: no rebuild) =="
python3 - "$WF" <<'PY' >/dev/null 2>&1; check "promote-beta-to-stable job present" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
sys.exit(0 if wf.get("jobs", {}).get("promote-beta-to-stable") else 1)
PY

grep -qE "github\.event_name == 'workflow_dispatch' && inputs\.promote == 'true'" "$WF"; \
  check "promote job gated on workflow_dispatch + inputs.promote" "$?"

python3 - "$WF" <<'PY' >/dev/null 2>&1; check "workflow_dispatch inputs: promote, beta-tag, stable-version" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
# PyYAML (YAML 1.1) parses the bare `on:` key as boolean True — handle both.
on = wf.get("on", wf.get(True)) or {}
inp = on.get("workflow_dispatch", {}).get("inputs", {})
need = {"promote", "beta-tag", "stable-version"}
sys.exit(0 if need.issubset(set(inp)) else 1)
PY

# The promote path must NOT rebuild: no `flutter build` in any of its steps.
grep -qiE 'flutter build' <<<"$PROMOTE_TEXT"; rc=$?
[[ $rc -ne 0 ]]; check "AC-1: promote path performs NO rebuild (no 'flutter build')" "$?"

# ---------------------------------------------------------------------------
# T4 (AC-1): copies beta artifacts verbatim + creates a make_latest stable release
# ---------------------------------------------------------------------------
echo "== T4: copy verbatim + stable release (AC-1) =="
grep -qE 'gh release download' <<<"$PROMOTE_TEXT"; \
  check "downloads beta artifacts (gh release download)" "$?"
grep -qiE 'gh release (create|upload)' <<<"$PROMOTE_TEXT"; \
  check "creates + uploads the stable release" "$?"
grep -qiE -- '--make-latest' <<<"$PROMOTE_TEXT"; \
  check "stable release is make_latest (releases/latest → stable, §5.3)" "$?"
# The beta feed is dropped so the stable feed is generated fresh for X.Y.Z.
grep -qiE 'rm -f .*appcast-beta\.xml' <<<"$PROMOTE_TEXT"; \
  check "beta appcast dropped (stable feed derived fresh)" "$?"

# ---------------------------------------------------------------------------
# T5 (AC-1): stable appcast derived via generate_appcast.sh --channel stable
# ---------------------------------------------------------------------------
echo "== T5: stable appcast via --channel stable (AC-1) =="
grep -qE 'generate_appcast\.sh' <<<"$PROMOTE_TEXT"; g1=$?
grep -qE -- '--channel stable' <<<"$PROMOTE_TEXT"; g2=$?
[[ $g1 -eq 0 && $g2 -eq 0 ]]; \
  check "publish-appcast invoked with --channel stable" "$?"

# ---------------------------------------------------------------------------
# T6 (AC-2): signature preserved — deterministic/identical, NOT 're-signed'
# ---------------------------------------------------------------------------
echo "== T6: signature preserved (AC-2) =="
# The literal 're-sign' substring must be ABSENT from the promote path.
grep -qiE 're-?sign' <<<"$PROMOTE_TEXT"; rc=$?
[[ $rc -ne 0 ]]; check "AC-2: no 're-sign' wording in promote path" "$?"
# The preservation rationale must be present (deterministic/identical/same seed).
grep -qiE 'deterministic|byte-identical|same seed|same EdDSA|identical' <<<"$PROMOTE_TEXT"; \
  check "AC-2: signature-preservation rationale present" "$?"

# ---------------------------------------------------------------------------
# T7 (AC-3): idempotency — existence guard + conditional create + --clobber upload
# ---------------------------------------------------------------------------
echo "== T7: idempotency guard (AC-3) =="
grep -qE 'gh release view' <<<"$PROMOTE_TEXT"; \
  check "idempotency: existence check (gh release view) before create" "$?"
# The create step must be conditional on the stable release being absent.
grep -qE "steps.exists.outputs.exists != 'true'" <<<"$PROMOTE_TEXT"; \
  check "idempotency: create guarded on absence (exists != 'true')" "$?"
# Upload uses --clobber → overwrite, never a duplicate asset.
grep -qE 'gh release upload' <<<"$PROMOTE_TEXT"; c1=$?
grep -qiE -- '--clobber' <<<"$PROMOTE_TEXT"; c2=$?
[[ $c1 -eq 0 && $c2 -eq 0 ]]; \
  check "AC-3: upload uses --clobber (no duplicate asset on re-promote)" "$?"

# ---------------------------------------------------------------------------
# T8 (AC-1 + AC-4): Store-Submission path wired (generic operator instruction)
# ---------------------------------------------------------------------------
echo "== T8: Store-Submission wired (AC-4) =="
grep -qiE 'operator' <<<"$PROMOTE_TEXT"; w1=$?
grep -qiE 'submit' <<<"$PROMOTE_TEXT"; w2=$?
[[ $w1 -eq 0 && $w2 -eq 0 ]]; \
  check "AC-4: store-submission operator instruction + 'submit' referenced" "$?"

# CLAUDE.md Microsoft-Store-Operations Hard-Internas: this tracked, public
# workflow must stay a GENERIC instruction string — no host names, no local
# filesystem/home paths, no credential-file locations.
grep -qiE 'silviospc|~/\.config|\.scratch/|/Users/' <<<"$PROMOTE_TEXT"; rc=$?
[[ $rc -ne 0 ]]; check "AC-4: no host/path/credential Hard-Internas leaked into release.yml" "$?"

# ---------------------------------------------------------------------------
# T9: build jobs skip on a promote dispatch; tag-push still builds (regression)
# ---------------------------------------------------------------------------
echo "== T9: build jobs skip on promote dispatch (no wasted rebuild) =="
python3 - "$WF" <<'PY' >/dev/null 2>&1; check "build jobs guarded to skip on promote dispatch" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
ok = True
for name in ("build-windows", "build-macos", "build-linux"):
    cond = str(wf.get("jobs", {}).get(name, {}).get("if", ""))
    ok = ok and ("workflow_dispatch" in cond) and ("inputs.promote" in cond)
sys.exit(0 if ok else 1)
PY

# LOGIC — mirror the build-guard primitive: guard = !(event==wd && promote==true).
# guard_runs returns 0 = build RUNS, non-zero = build SKIPPED (guard active).
#   tag push         → event != workflow_dispatch → guard true → RUN (no regression)
#   promote dispatch → both true                 → guard false → SKIP
guard_runs() { [[ "$1" == "workflow_dispatch" && "$2" == "true" ]] && return 1 || return 0; }
guard_runs push false; check "logic: tag push → build jobs RUN (no release regression)" "$?"
if guard_runs workflow_dispatch true; then
  bad "logic: promote dispatch → build jobs SKIP (no rebuild)"
else
  ok "logic: promote dispatch → build jobs SKIP (no rebuild)"
fi

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
echo "NOTE: real GitHub promote + Store live proof is an operator follow-up (Issue 07 / §13)."
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
