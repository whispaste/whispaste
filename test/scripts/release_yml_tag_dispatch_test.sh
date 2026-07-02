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
#       prerelease/make_latest, the beta-appcast-pointer branch push, the
#       docs-attest gate, stable-only manifest-bump). Verified by grep on the YAML.
#   (2) LOGIC — given sample tags (v1.2.44-beta.1 / v1.2.44), the SAME
#       tag-matching primitives the workflow uses (contains '-beta.' / no '-')
#       yield the per-job decisions required by the acceptance criteria.
#
# AC mapping:
#   AC-5  Beta-Tag → kein MSIX, keine Store-Submission       → T3 + T10
#   AC    Stable-Tag → Release + Stable-Feed + MSIX + Store-Trigger → T4/T3 + T11
#   AC    releases/latest (Stable in, Beta out)              → T5 + T12
#   AC    docs-attest-Gate im Release-Pfad                   → T7
#   NEU   Beta-Appcast-Zeiger ist ein force-gepushter Git-Branch, kein
#         GitHub-Release-Objekt (immutable-releases burnt den tag_name
#         sonst dauerhaft) — Issue 08 Fix v2                          → T13
#   NEU   Release wird als Draft erzeugt + erst NACH publish-appcast
#         veröffentlicht (GitHub immutable-release Fix)                → T14
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
# T6: STRUCTURE — beta-appcast-pointer branch push exists, is beta-gated, and
#     is NOT a GitHub Release object. Issue 08 fix v2: a Release-object pointer
#     (`beta-latest`, tried first) hits GitHub's immutable-releases feature —
#     a tag_name is permanently burned the moment ANY release (even deleted
#     and recreated) is published under it, so delete-then-recreate cannot
#     work either. A force-pushed branch carries no such restriction.
# ---------------------------------------------------------------------------
echo "== T6: beta-appcast-pointer branch push, no Release object (§5.3) =="
grep -qF 'beta-appcast-pointer' "$WF"
b1=$?
grep -qE 'if: contains\(github\.ref_name, .-beta\.' "$WF"
b2=$?
grep -qE -- 'git push -q --force origin beta-appcast-pointer' "$WF"
b3=$?
! grep -qE 'gh release (create|delete) beta-latest' "$WF"
b4=$?
[[ $b1 -eq 0 && $b2 -eq 0 && $b3 -eq 0 && $b4 -eq 0 ]]
check "beta-appcast-pointer branch push beta-gated, no Release-object pointer" "$?"

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
    echo "beta_appcast_pointer_updated=true"
    echo "manifest_bump=false"       # stable-only channel
  elif is_stable "$tag"; then
    echo "channel=stable"
    echo "msix_built=true"           # MSIX_PUBLISHER present → built
    echo "store_submission_trigger=true"  # MSIX is the local submission prerequisite
    echo "prerelease=false"
    echo "make_latest=true"
    echo "in_releases_latest=true"   # non-prerelease + make_latest → latest
    echo "appcast_asset=appcast.xml"
    echo "beta_appcast_pointer_updated=false"
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
[[ "$(dec "$BTAG" beta_appcast_pointer_updated)" == "true" ]]; check "beta → beta-appcast-pointer branch updated (§5.3)" "$?"

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
# T13: STRUCTURE + IDEMPOTENCY — beta-appcast-pointer is a force-pushed git
#      branch (Issue 08 fix v2), not a reused GitHub Release object. A Release
#      object was tried first (delete-then-recreate under the `beta-latest`
#      tag_name) but GitHub's immutable-releases feature (GA 2025-10)
#      permanently burns a tag_name the moment ANY release is published under
#      it — deleting and recreating cannot work around that. A branch carries
#      no such restriction, so a plain `--force` push is idempotent forever.
# ---------------------------------------------------------------------------
echo "== T13: beta-appcast-pointer git branch, idempotent (Issue 08 fix v2) =="

# The workflow comment must explain WHY a Release object was abandoned
# (immutable-releases permanently burning the tag_name), not just what
# replaced it — otherwise a future maintainer could plausibly reintroduce it.
grep -qi 'immutable-releases' "$WF"
check "comment explains GitHub's immutable-releases permanently burns a tag_name (why Release-object pointer was abandoned)" "$?"

# No trace of the old Release-object mechanism should remain.
! grep -qE 'gh release (view|delete|create) beta-latest' <<<"$PUBLISH_APPCAST_TEXT"
check "no gh release view/delete/create beta-latest remains (old immutable-release-incompatible mechanism fully removed)" "$?"

# The new mechanism: isolated fresh git repo, commit, force-push to the
# dedicated branch. Isolated (mktemp -d + git init) so it never touches the
# actual release.yml checkout or its history.
grep -qE 'git init -q -b beta-appcast-pointer' <<<"$PUBLISH_APPCAST_TEXT"; d1=$?
grep -qE 'git push -q --force origin beta-appcast-pointer' <<<"$PUBLISH_APPCAST_TEXT"; d2=$?
[[ $d1 -eq 0 && $d2 -eq 0 ]]
check "beta-appcast-pointer: isolated git repo, force-pushed to dedicated branch" "$?"

# The correct asset (appcast-beta.xml) is what gets published on the pointer
# branch — not the installers (those stay on the versioned release).
grep -qE 'appcast-beta\.xml' <<<"$PUBLISH_APPCAST_TEXT"
check "beta-appcast-pointer branch carries appcast-beta.xml" "$?"

# The pointer-branch step is beta-gated (the tag-move step it used to share
# this guard with was removed — see T6).
grep -c "if: contains(github.ref_name, '-beta.')" "$WF" | grep -qE '^[1-9][0-9]*$'
check "beta-appcast-pointer step is beta-gated" "$?"

# --- T13b: idempotency is structural, not conditional ------------------------
# Unlike the abandoned delete-then-recreate dance, a force-push needs no
# existence guard at all — every beta cycle, first or repeat, runs the exact
# same unconditional git init/commit/push. Assert there is no `gh release
# view`-style existence check guarding this step (a regression back to that
# pattern would reintroduce the immutable-release trap).
echo "== T13b: force-push idempotency needs no existence guard =="
! grep -qE 'gh release view beta' <<<"$PUBLISH_APPCAST_TEXT"
check "no existence-check guard around the pointer push (force-push is unconditionally idempotent)" "$?"

# ---------------------------------------------------------------------------
# T14: STRUCTURE — the release is created as a draft and only published after
#      publish-appcast has finished uploading (GitHub immutable-release fix:
#      asset uploads to an already-published release are rejected outright,
#      so create-release's own multi-file upload AND publish-appcast's
#      appcast upload must both land while the release is still a draft).
# ---------------------------------------------------------------------------
echo "== T14: draft-then-publish release (immutable-release fix) =="

grep -qE '^\s*draft:\s*true\s*$' "$WF"
check "create-release creates the release as a draft" "$?"

! grep -qE '^\s*draft:\s*false\s*$' "$WF"
check "no step still hardcodes draft: false (would race publish-appcast's upload)" "$?"

grep -qE '^\s*finalize-release:\s*$' "$WF"
check "finalize-release job exists" "$?"

python3 - "$WF" <<'PY' >/dev/null 2>&1; check "finalize-release needs both create-release and publish-appcast" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
needs = wf.get("jobs", {}).get("finalize-release", {}).get("needs", [])
sys.exit(0 if set(needs) == {"create-release", "publish-appcast"} else 1)
PY

python3 - "$WF" <<'PY' >/dev/null 2>&1; check "finalize-release runs 'gh release edit ... --draft=false' to publish" "$?"
import sys, re, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("finalize-release", {})
run = "\n".join(str(s.get("run", "")) for s in job.get("steps", []))
ok = bool(re.search(r'gh release edit .*--draft=false', run))
sys.exit(0 if ok else 1)
PY

# manifest-bump downloads assets straight from the release's download URL,
# which only resolves once published — it must wait for finalize-release,
# not just create-release (which now only produces a draft).
python3 - "$WF" <<'PY' >/dev/null 2>&1; check "manifest-bump needs finalize-release (waits for the release to be published)" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
needs = wf.get("jobs", {}).get("manifest-bump", {}).get("needs", [])
sys.exit(0 if "finalize-release" in needs else 1)
PY

# ---------------------------------------------------------------------------
# T15: STRUCTURE — the release-download-URL appcast gate runs AFTER publish,
#      not inside publish-appcast. releases/download/<tag>/<file> (and
#      releases/latest/download/...) 404 on a still-draft release, so
#      verifying them before finalize-release publishes would fail by
#      construction on every run, not just when something is actually broken.
# ---------------------------------------------------------------------------
echo "== T15: release-download appcast gate runs after publish =="

python3 - "$WF" <<'PY' >/dev/null 2>&1; check "publish-appcast no longer fetches releases/download or releases/latest/download URLs" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("publish-appcast", {})
run = "\n".join(str(s.get("run", "")) for s in job.get("steps", []))
sys.exit(0 if ("releases/download/" not in run and "releases/latest/download" not in run) else 1)
PY

python3 - "$WF" <<'PY' >/dev/null 2>&1; check "finalize-release fetches + verifies the published appcast (releases/download or releases/latest/download)" "$?"
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf.get("jobs", {}).get("finalize-release", {})
run = "\n".join(str(s.get("run", "")) for s in job.get("steps", []))
ok = "releases/download/" in run and "releases/latest/download" in run and "sparkle:edSignature=" in run
sys.exit(0 if ok else 1)
PY

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
echo "NOTE: real GitHub-Actions live proof is deferred to Issue 07 (beta cycle)."
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
