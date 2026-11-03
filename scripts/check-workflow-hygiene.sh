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
# Fast (pure YAML parse, no network, no runner), so it belongs on the push
# path next to actionlint rather than in CI, where it would cost the very
# minutes it is protecting.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PYEOF'
import sys, pathlib, re

try:
    import yaml
except ImportError:
    print("check-workflow-hygiene: PyYAML not available — skipping "
          "(install with: pip3 install pyyaml)", file=sys.stderr)
    sys.exit(0)

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
