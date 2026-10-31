#!/usr/bin/env bash
# check-workflow-hygiene.sh — local pre-push gate for the workflow failure
# classes that actionlint structurally cannot see.
#
# Usage: bash scripts/check-workflow-hygiene.sh
#
# actionlint validates workflow *syntax and semantics* (expressions, contexts,
# runs-on, needs, embedded shell). It is already wired into .githooks/pre-push
# and it is clean on every file here. None of the checks below are things it
# models — they are policy rules this repo learned the hard way:
#
#   1. Every job must set `timeout-minutes`.
#      Without it a job runs until GitHub's 360-minute default. On a billed
#      runner that is catastrophic for the Actions free tier: macos-latest
#      bills at 10x, so ONE hung macOS job = 3600 billed minutes = the entire
#      monthly quota. This is not hypothetical — packaging-validate run
#      32296050925 sat on a stalled `apt-get update` until GitHub killed it at
#      exactly 6h00m. 14 of 42 jobs were missing this limit when the quota ran
#      out; that is the single cheapest guardrail in this file.
#
#   2. Every `subosito/flutter-action` must pin `flutter-version`.
#      An unpinned action silently follows whatever `stable` currently is, so
#      CI stops testing the SDK the app is built against and a red run no
#      longer tells you whether your code or Flutter changed. The pin is read
#      from ci.yml rather than hardcoded, so this file cannot itself go stale
#      (cf. 19b24e8a, which fixed exactly that failure mode in the docs-drift
#      auditor).
#
#   3. Every `uses:` must be pinned to a full 40-char commit SHA with a
#      trailing `# vX.Y.Z` comment (docker:// refs: @sha256 digest; local
#      ./ refs exempt). A tag can be moved after review, so a tag-pinned
#      action runs code nobody reviewed. Checked as plain text.
#
#   4. The CI gates are defined once, in scripts/ci-gates.sh. ci.yml must run
#      every gate defined there, the pre-commit and pre-push hooks must call
#      the script too, and the secret-scan job must not carry gate logic of
#      its own. A gate that lives only in CI is found by a red run (2026-10).
#
#   5. Jobs that `needs: secret-scan` must say `always()` in their `if:`. A
#      failing gate otherwise skips every test job and hides the test results.
#
#   6. packaging-validate.yml's push filter lists exactly the inputs that
#      scripts/ci/packaging-validate.sh names (`--inputs`). The pre-push hook
#      runs the checks for the same list; a path missing from either let
#      findings slip to the next push that happened to match (2026-10-31).
#
# Rules 1, 2, 5 and 6 need PyYAML. It is a hard requirement: a missing module
# fails the check instead of skipping it (a skip looked like a pass).
#
# Fast (pure YAML parse, no network, no runner), so it belongs on the push
# path next to actionlint rather than in CI, where it would cost the very
# minutes it is protecting.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PYEOF'
import sys, pathlib, re

# --- rule 3: every uses: pinned to a commit SHA + version comment ----------
# Text-based on purpose: this must run even without PyYAML (see below).
PIN_RE = re.compile(r'^\s*(?:-\s+)?uses:\s*(\S+)(.*)$')
SHA_REF = re.compile(r'^[^@\s]+@[0-9a-f]{40}$')
DIGEST_REF = re.compile(r'^docker://.+@sha256:[0-9a-f]{64}$')
VERSION_COMMENT = re.compile(r'^#\s*v[0-9]+(\.[0-9]+){0,2}\s*$')

_root = pathlib.Path(sys.argv[1])
_wf = _root / ".github" / "workflows"
_pin_files = (sorted(_wf.glob("*.yml")) + sorted(_wf.glob("*.yaml"))
              + sorted((_root / ".github" / "actions").glob("*/action.y*ml")))
pin_problems = []
pin_refs = 0
for _f in _pin_files:
    for _no, _line in enumerate(_f.read_text().splitlines(), 1):
        _m = PIN_RE.match(_line)
        if not _m:
            continue
        _ref, _rest = _m.group(1), _m.group(2).strip()
        if _ref.startswith(("./", "../")):
            continue
        pin_refs += 1
        _where = f"{_f.relative_to(_root)}:{_no}"
        if _ref.startswith("docker://"):
            if not DIGEST_REF.match(_ref):
                pin_problems.append(f"{_where}: docker reference not pinned by digest: {_ref}")
        elif not SHA_REF.match(_ref):
            pin_problems.append(f"{_where}: not pinned to a full commit SHA: {_ref}")
        elif not VERSION_COMMENT.match(_rest):
            pin_problems.append(f"{_where}: missing trailing '# vX.Y.Z' comment: {_ref}")
if pin_problems:
    print("")
    print("Action pin problems (pin to <owner/repo>@<40-char-sha> # vX.Y.Z):")
    for _p in pin_problems:
        print(f"  - {_p}")
    print("")
    sys.exit(1)
print(f"  action pins: clean ({pin_refs} references)")

# --- rule 4: CI gates are defined once, in scripts/ci-gates.sh -------------
gate_problems = []
gates_sh = _root / "scripts" / "ci-gates.sh"
ci_yml = _wf / "ci.yml"
gate_names = re.findall(r"^gate_([a-z_]+)\(\)", gates_sh.read_text(), re.M)
if not gate_names:
    gate_problems.append("scripts/ci-gates.sh defines no gate_<name>() function")
ci_text = ci_yml.read_text()
for g in gate_names:
    if not re.search(r"ci-gates\.sh[^\n]*\b" + re.escape(g) + r"\b", ci_text):
        gate_problems.append(f"ci.yml does not run gate '{g}' via scripts/ci-gates.sh")
for hook in (".githooks/pre-commit", ".githooks/pre-push"):
    hook_text = (_root / hook).read_text()
    if "ci-gates.sh" not in hook_text:
        gate_problems.append(f"{hook} does not call scripts/ci-gates.sh")
secret_job = re.search(
    r"^  secret-scan:\n(.*?)(?=^  [a-z][a-z0-9-]*:\n|\Z)", ci_text, re.M | re.S)
if secret_job and re.search(r"\bgrep -r", secret_job.group(1)):
    gate_problems.append(
        "ci.yml secret-scan job carries inline grep gate logic — move it into "
        "scripts/ci-gates.sh")
if gate_problems:
    print("")
    print("CI gate wiring problems (gates live in scripts/ci-gates.sh):")
    for p in gate_problems:
        print(f"  - {p}")
    print("")
    sys.exit(1)
print(f"  ci gates: wired ({', '.join(gate_names)})")

try:
    import yaml
except ImportError:
    print("check-workflow-hygiene: PyYAML fehlt — Regeln 1, 2 und 5 können nicht "
          "geprüft werden. Installieren: python3 -m pip install --user "
          "--break-system-packages pyyaml", file=sys.stderr)
    sys.exit(1)

root = pathlib.Path(sys.argv[1])
wf_dir = root / ".github" / "workflows"
files = sorted(wf_dir.glob("*.yml")) + sorted(wf_dir.glob("*.yaml"))
if not files:
    print("check-workflow-hygiene: no workflow files found", file=sys.stderr)
    sys.exit(0)

problems = []

# Single source of truth for the SDK pin: whatever ci.yml uses.
expected_flutter = None
ci = wf_dir / "ci.yml"
if ci.exists():
    versions = set(re.findall(r"flutter-version:\s*['\"]?([0-9][^'\"\s]*)",
                              ci.read_text()))
    if len(versions) == 1:
        expected_flutter = versions.pop()
    elif len(versions) > 1:
        problems.append(
            f"ci.yml pins more than one flutter-version ({sorted(versions)}) — "
            "the jobs must agree before other workflows can be checked against it"
        )

for f in files:
    rel = f.relative_to(root)
    try:
        doc = yaml.safe_load(f.read_text())
    except yaml.YAMLError as e:
        problems.append(f"{rel}: not parseable as YAML: {e}")
        continue
    if not isinstance(doc, dict):
        continue

    # --- rule 5: dependants of secret-scan must not be masked by a red gate --
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        needs = job.get("needs") or []
        needs = [needs] if isinstance(needs, str) else needs
        if "secret-scan" in needs and "always()" not in str(job.get("if", "")):
            problems.append(
                f"{rel}: job '{job_name}' needs secret-scan but its if: lacks "
                "always() — a failing gate would skip it silently"
            )

    # --- rule 1: every job needs an explicit timeout ---------------------
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        # A job that only calls a reusable workflow cannot set a timeout;
        # the limit belongs to the called workflow's own jobs.
        if "uses" in job:
            continue
        if "timeout-minutes" not in job:
            runs_on = job.get("runs-on", "?")
            problems.append(
                f"{rel}: job '{job_name}' (runs-on: {runs_on}) has no "
                "timeout-minutes — it would run until GitHub's 360min default"
            )

    # --- rule 2: flutter-action must pin a version -----------------------
    if expected_flutter:
        for job_name, job in (doc.get("jobs") or {}).items():
            if not isinstance(job, dict):
                continue
            for step in (job.get("steps") or []):
                if not isinstance(step, dict):
                    continue
                uses = str(step.get("uses", ""))
                if not uses.startswith("subosito/flutter-action"):
                    continue
                pin = str((step.get("with") or {}).get("flutter-version", ""))
                if not pin:
                    problems.append(
                        f"{rel}: job '{job_name}' uses subosito/flutter-action "
                        f"without flutter-version — pin it to {expected_flutter} "
                        "(the version ci.yml builds against)"
                    )
                elif pin != expected_flutter:
                    problems.append(
                        f"{rel}: job '{job_name}' pins flutter-version {pin}, "
                        f"but ci.yml builds against {expected_flutter}"
                    )

# --- rule 6: packaging-validate push filter == the script's inputs --------
import subprocess
pv = root / ".github" / "workflows" / "packaging-validate.yml"
pv_script = root / "scripts" / "ci" / "packaging-validate.sh"
if pv.exists() and pv_script.exists():
    inputs = subprocess.run(
        ["bash", str(pv_script), "--inputs"], capture_output=True, text=True,
        check=True,
    ).stdout.split()
    want = {i + "/**" if (root / i).is_dir() else i for i in inputs}
    on = yaml.safe_load(pv.read_text()).get(True) or {}  # YAML 1.1: on -> True
    have = set(((on.get("push") or {}).get("paths")) or [])
    for path in sorted(want - have):
        problems.append(
            f"packaging-validate.yml: push paths lack '{path}' "
            "(an input of scripts/ci/packaging-validate.sh)"
        )
    for path in sorted(have - want):
        problems.append(
            f"packaging-validate.yml: push path '{path}' is not an input of "
            "scripts/ci/packaging-validate.sh (add it to INPUTS there)"
        )

if problems:
    print("")
    print("Workflow hygiene problems:")
    for p in problems:
        print(f"  - {p}")
    print("")
    sys.exit(1)

print(f"  workflow hygiene: clean ({len(files)} workflows, "
      f"flutter pin {expected_flutter or 'n/a'})")
PYEOF
