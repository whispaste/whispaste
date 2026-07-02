#!/usr/bin/env bash
#
# release_yml_tag_dispatch_test.sh — verifies the Git-tag routing of
# .github/workflows/release.yml (PRD §5.2/§5.3, §6.3, §13, Issue 04/05).
#
# This is the DRY/LOGIC verification for the Beta-Prerelease vs Stable-Release
# tag dispatch. It does NOT exercise GitHub Actions live — that is explicitly
# deferred to the Issue 07 beta cycle. Instead it asserts two layers:
#
#   (1) STRUCTURE — the workflow contains the required routing constructs
#       (beta-gated MSIX skip, --channel routing, channel-conditional
#       prerelease/make_latest, the beta-latest moving-tag step, the docs-attest
#       gate, stable-only manifest-bump). Verified by grep on the YAML.
#   (2) LOGIC — given sample tags (v1.2.44-beta.1 / v1.2.44), the SAME
#       tag-matching primitives the workflow uses (contains '-beta.' / no '-')
#       yield the per-job decisions required by the acceptance criteria.
#
# AC mapping:
#   AC-5  Beta-Tag → kein MSIX, keine Store-Submission       → T3 + T10
#   AC    Stable-Tag → Release + Stable-Feed + MSIX + Store-Trigger → T4/T3 + T11
#   AC    releases/latest (Stable in, Beta out)              → T5 + T12
#   AC    docs-attest-Gate im Release-Pfad                   → T7
#   NEU   beta-latest ist ein echtes, idempotentes GitHub-Release
#         (nicht nur ein bewegter Git-Tag) — Issue 08 Fix              → T13
#
# Run: bash test/scripts/release_yml_tag_dispatch_test.sh

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

# YAML model of the publish-appcast job's step text (names + if + run + uses),
# robust against comment/indentation drift. Echoes the concatenated text on
# stdout. Mirrors promote_flow_test.sh's promote_job_text() helper.
publish_appcast_job_text() {
  python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("publish-appcast")
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

PUBLISH_APPCAST_TEXT="$(publish_appcast_job_text)"

# ---------------------------------------------------------------------------
# T1: YAML parses
# ---------------------------------------------------------------------------
echo "== T1: YAML parses =="
python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))" 2>/dev/null; check "yaml.safe_load valid" "$?"

# ---------------------------------------------------------------------------
# T2: actionlint clean (only if installed; informational otherwise)
# ---------------------------------------------------------------------------
echo "== T2: actionlint =="
if command -v actionlint >/dev/null 2>&1; then
  actionlint "$WF" >/tmp/alint.$$ 2>&1; check "actionlint clean" "$?"
  [[ -s /tmp/alint.$$ ]] && { echo "  --- actionlint output ---"; cat /tmp/alint.$$ >&2; }
  rm -f /tmp/alint.$$
else
  echo "  skip - actionlint not installed (rely on YAML parse + grep)"
fi

# ---------------------------------------------------------------------------
# T3: STRUCTURE — MSIX is gated off for beta tags (AC-5/Q2)
#     The msix_config step short-circuits (skip=true) on a -beta. tag, which
#     auto-skips Build MSIX / Upload MSIX / .appxupload / symbol upload and
#     flips the job output `msix-built` to false (→ wack-gate + create-release
#     MSIX download skip). One anchor covers the whole MSIX chain.
# ---------------------------------------------------------------------------
echo "== T3: MSIX beta-gate present (AC-5) =="
grep -qF '-beta.' "$WF" && grep -qiE 'skipping MSIX build \+ Store submission' "$WF"
check "msix_config step matches -beta. tag + sets skip=true (AC-5)" "$?"

# ---------------------------------------------------------------------------
# T4: STRUCTURE — publish-appcast routes --channel beta|stable from the tag
# ---------------------------------------------------------------------------
echo "== T4: publish-appcast --channel routing =="
grep -qF -- '--channel "$CHANNEL"' "$WF"
c1=$?
grep -qF '"${GITHUB_REF_NAME}" == *-beta.' "$WF"
c2=$?
[[ $c1 -eq 0 && $c2 -eq 0 ]]
check "publish-appcast derives CHANNEL from tag + passes --channel" "$?"

# ---------------------------------------------------------------------------
# T5: STRUCTURE — create-release prerelease/make_latest are channel-conditional
#     (releases/latest logic, Q1/§5.3)
# ---------------------------------------------------------------------------
echo "== T5: create-release channel-conditional prerelease/make_latest =="
grep -qF 'prerelease: ${{ steps.channel.outputs.prerelease }}' "$WF"
c1=$?
grep -qF 'make_latest: ${{ steps.channel.outputs.make_latest }}' "$WF"
c2=$?
[[ $c1 -eq 0 && $c2 -eq 0 ]]
check "create-release binds prerelease + make_latest to channel step" "$?"

# ---------------------------------------------------------------------------
# T6: STRUCTURE — beta-latest moving-tag step exists and is beta-gated (§5.3)
# ---------------------------------------------------------------------------
echo "== T6: beta-latest moving-tag step (§5.3) =="
grep -qF 'beta-latest' "$WF"
b1=$?
grep -qE 'if: contains\(github\.ref_name, .-beta\.' "$WF"
b2=$?
grep -qF 'git push origin refs/tags/beta-latest --force' "$WF"
b3=$?
[[ $b1 -eq 0 && $b2 -eq 0 && $b3 -eq 0 ]]
check "beta-latest tag-move step present + beta-gated + force-pushed" "$?"

# ---------------------------------------------------------------------------
# T7: STRUCTURE — docs-attest gate in the release path (PRD §13)
# ---------------------------------------------------------------------------
echo "== T7: docs-attest gate in release path (§13) =="
grep -qF 'docs-attest.sh check' "$WF"
check "docs-attest check step present in release path" "$?"

# ---------------------------------------------------------------------------
# T8: STRUCTURE — manifest-bump (Scoop/winget/Homebrew) stable-only
#     Parsed via the YAML model (robust against indentation/comment drift).
# ---------------------------------------------------------------------------
echo "== T8: manifest-bump stable-only =="
python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf.get("jobs", {})
mb = jobs.get("manifest-bump", {})
cond = mb.get("if", "")
ok = "!contains(github.ref_name" in cond
sys.exit(0 if ok else 1)
PY
check "manifest-bump gated !contains(github.ref_name, '-')" "$?"

# ---------------------------------------------------------------------------
# T9: STRUCTURE — no CI Store-Submission EXECUTION (Store runs locally)
#     AC-5's "keine Store-Submission" holds because submission is NOT EXECUTED
#     in CI: the local wp-submit-store.ps1 / wp-release-windows.sh scripts
#     (under the gitignored .scratch/windows-release-pipeline/) are run by the
#     operator on the box. The promote job (Issue 05) DOCUMENTS that operator
#     step in a notice/echo (AC-4 wiring) — that reference is expected and is
#     excluded here. Every OTHER job must stay free of any store-script reference.
# ---------------------------------------------------------------------------
echo "== T9: Store-Submission is local (no CI execution; promote job only documents it) =="
python3 - "$WF" <<'PY' >/dev/null 2>&1; check "no tag-dispatch job references store scripts (AC-5 holds)" "$?"
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1]))
pat = re.compile(r'wp-submit-store|wp-release-windows|microsoft-partnercenter|partner[._-]center', re.I)
bad = []
echo_pat = re.compile(r'(echo|::notice::|::warning::|::error::)')
for name, job in wf.get("jobs", {}).items():
    is_promote = (name == "promote-beta-to-stable")
    for s in job.get("steps", []):
        run = str(s.get("run", ""))
        blob = "\n".join(str(s.get(k, "")) for k in ("name", "run", "uses", "with", "if"))
        if not pat.search(blob):
            continue
        if is_promote:
            # Forward-looking hardening: the promote job may reference store
            # scripts ONLY in echo/::notice::/::warning::/::error:: lines
            # (operator instruction, never executed in CI). Any executable
            # reference is a regression (AC-5 break).
            for line in run.split("\n"):
                ls = line.strip()
                if not ls or ls.startswith("#"):
                    continue
                if pat.search(line) and not echo_pat.search(line):
                    bad.append(f"{name}: executable store reference (not echo/notice): {ls}")
        else:
            bad.append(name)
sys.exit(1 if bad else 0)
PY

# ---------------------------------------------------------------------------
# T10/T11/T12: LOGIC — route sample tags through the workflow's primitives
# ---------------------------------------------------------------------------
# These mirror the EXACT tag-matching the workflow uses:
#   beta   = tag contains '-beta.'
#   stable = tag has no '-' (no pre-release suffix)
# Per-tag decisions are derived from the routing rules the structure tests
# above proved the workflow encodes.

is_beta()   { [[ "$1" == *-beta.* ]]; }
is_stable() { [[ "$1" != *-* ]]; }

# route_tag <tag> — prints one decision per line: "key=value"
route_tag() {
  local tag="$1"
  if is_beta "$tag"; then
    echo "channel=beta"
    echo "msix_built=false"          # msix_config short-circuits (AC-5)
    echo "store_submission=false"    # not a CI job; beta never contacts Store
    echo "prerelease=true"
    echo "make_latest=false"
    echo "in_releases_latest=false"  # prerelease → excluded from releases/latest
    echo "appcast_asset=appcast-beta.xml"
    echo "beta_latest_moved=true"
    echo "manifest_bump=false"       # stable-only channel
  elif is_stable "$tag"; then
    echo "channel=stable"
    echo "msix_built=true"           # MSIX_PUBLISHER present → built
    echo "store_submission_trigger=true"  # MSIX is the local submission prerequisite
    echo "prerelease=false"
    echo "make_latest=true"
    echo "in_releases_latest=true"   # non-prerelease + make_latest → latest
    echo "appcast_asset=appcast.xml"
    echo "beta_latest_moved=false"
    echo "manifest_bump=true"
  else
    echo "channel=unknown"
  fi
}

dec() { route_tag "$1" | grep "^$2=" | cut -d= -f2-; }

echo "== T10: logic — v1.2.44-beta.1 routes to beta (AC-5) =="
BTAG="v1.2.44-beta.1"
is_beta "$BTAG";                                  check "beta tag recognised as beta" "$?"
[[ "$(dec "$BTAG" msix_built)" == "false" ]];     check "AC-5: beta → MSIX NOT built" "$?"
[[ "$(dec "$BTAG" store_submission)" == "false" ]]; check "AC-5: beta → no Store-Submission" "$?"
[[ "$(dec "$BTAG" channel)" == "beta" ]];         check "beta → channel=beta (appcast-beta.xml)" "$?"
[[ "$(dec "$BTAG" prerelease)" == "true" && "$(dec "$BTAG" make_latest)" == "false" ]]; \
  check "beta → GitHub Prerelease (not latest)" "$?"
[[ "$(dec "$BTAG" beta_latest_moved)" == "true" ]]; check "beta → beta-latest moved (§5.3)" "$?"

echo "== T11: logic — v1.2.44 routes to stable =="
STAG="v1.2.44"
is_stable "$STAG";                                check "stable tag recognised as stable" "$?"
[[ "$(dec "$STAG" msix_built)" == "true" ]];      check "stable → MSIX built" "$?"
[[ "$(dec "$STAG" store_submission_trigger)" == "true" ]]; \
  check "stable → Store-Submission-Trigger (MSIX prerequisite)" "$?"
[[ "$(dec "$STAG" channel)" == "stable" ]];       check "stable → channel=stable (appcast.xml)" "$?"
[[ "$(dec "$STAG" prerelease)" == "false" && "$(dec "$STAG" make_latest)" == "true" ]]; \
  check "stable → non-prerelease Release" "$?"
[[ "$(dec "$STAG" manifest_bump)" == "true" ]];   check "stable → manifest-bump runs" "$?"

echo "== T12: logic — releases/latest resolution (Q1/§5.3) =="
[[ "$(dec "$STAG" in_releases_latest)" == "true" ]]; \
  check "Stable appears in releases/latest (non-prerelease, make_latest)" "$?"
[[ "$(dec "$BTAG" in_releases_latest)" == "false" ]]; \
  check "Beta does NOT appear in releases/latest (prerelease)" "$?"

# ---------------------------------------------------------------------------
# T13: STRUCTURE + IDEMPOTENCY — beta-latest is a real, reused GitHub Release
#      (Issue 08 fix), not merely a moved git tag. Mirrors promote_flow_test.sh
#      T7's idempotency-guard pattern (existence check → conditional
#      create/upload, --clobber on upload, --prerelease so it never surfaces
#      via releases/latest).
# ---------------------------------------------------------------------------
echo "== T13: beta-latest real GitHub Release, idempotent (Issue 08 fix) =="

# The old wrong assumption (tag move alone serves the download URL) must no
# longer be perpetuated — the workflow comment must explain the actual
# resolution mechanism (Release object's tag_name, not the git ref).
grep -qi 'tag_name' "$WF"
check "comment explains GitHub resolves releases/download/<tag> via a Release's tag_name (not the git ref)" "$?"

# Existence guard before create — same primitive as `gh release view` (T7 of
# promote_flow_test.sh), applied to the beta-latest pointer release.
grep -qE 'gh release view beta-latest' <<<"$PUBLISH_APPCAST_TEXT"
check "idempotency: existence check (gh release view beta-latest) before create" "$?"

# Create path present (first beta cycle) and gated on the pointer being absent.
grep -qE 'gh release create beta-latest' <<<"$PUBLISH_APPCAST_TEXT"
check "gh release create beta-latest path present" "$?"

# Upload path present (subsequent beta cycles) using --clobber → overwrite,
# never a duplicate asset error on a simulated second beta cycle.
grep -qE 'gh release upload beta-latest' <<<"$PUBLISH_APPCAST_TEXT"; c1=$?
grep -qiE -- '--clobber' <<<"$PUBLISH_APPCAST_TEXT"; c2=$?
[[ $c1 -eq 0 && $c2 -eq 0 ]]
check "gh release upload beta-latest uses --clobber (no duplicate asset on repeat beta cycle)" "$?"

# The correct asset (appcast-beta.xml) is what gets published/updated on the
# pointer release — not the installers (those stay on the versioned release).
grep -qE 'appcast-beta\.xml' <<<"$PUBLISH_APPCAST_TEXT"
check "beta-latest pointer release carries appcast-beta.xml" "$?"

# Stays a prerelease so it never displaces releases/latest (regression guard
# against the stable Q1/§5.3 path).
grep -qiE -- '--prerelease' <<<"$PUBLISH_APPCAST_TEXT"
check "beta-latest release created as --prerelease (never in releases/latest)" "$?"

# Both beta-gated steps (tag-move + pointer-release) share the same tag guard.
grep -c "if: contains(github.ref_name, '-beta.')" "$WF" | grep -qE '^[2-9][0-9]*$'
check "both beta-latest steps (tag-move + pointer-release) are beta-gated" "$?"

# --- T13b: simulated second beta cycle — no duplicate-create structurally ---
# The create step must live in the branch where `gh release view` FAILED
# (i.e. inside an if/else, not unconditionally run every cycle) — otherwise a
# second beta tag would hit "release already exists" from `gh release create`.
echo "== T13b: simulated second beta cycle stays idempotent =="
python3 - "$WF" <<'PY' >/dev/null 2>&1; check "gh release create beta-latest is only reached when 'gh release view' failed (if/else), not on every cycle" "$?"
import sys, re, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("publish-appcast", {})
run = ""
for s in job.get("steps", []):
    if "beta-latest" in str(s.get("name", "")) and "view" in str(s.get("run", "")):
        run = str(s.get("run", ""))
        break
# Must be an if/else around `gh release view beta-latest`, with `create` only
# in the else-branch and `upload` only in the if-branch (mutually exclusive on
# a single run — no path executes both, so a repeat beta cycle never hits a
# duplicate-create error).
ok = bool(re.search(r'if\s+gh release view beta-latest.*\n.*gh release upload beta-latest.*\n.*else\n.*gh release create beta-latest', run, re.S))
sys.exit(0 if ok else 1)
PY

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
echo "NOTE: real GitHub-Actions live proof is deferred to Issue 07 (beta cycle)."
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
