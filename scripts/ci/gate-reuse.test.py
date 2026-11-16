#!/usr/bin/env python3
"""#1403 offline (as internal-repo #646): the inline gate/nas reuse decision of gate.yml against fake API answers;
it must run before the pending status and before any fetch. Run: python3 -I scripts/ci/gate-reuse.test.py"""
import os, sys, textwrap  # noqa: E401
WF = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.internal forge/workflows/gate.yml")).read()
L = WF.splitlines(); a = next(i for i, x in enumerate(L) if '"$EVENT" = push ] && python3 -I' in x)  # noqa: E702
ns = {"__name__": "t"}; exec(textwrap.dedent("\n".join(L[a + 1:L.index("          PY", a)])), ns)  # noqa: E702
R, S, U = "o/r", "a" * 40, "/o/r/actions/runs/7"
st = lambda s="success", u=U, c=None: {"context": "gate/nas", "status": s, "target_url": u, "creator": c}  # noqa: E731
rn = lambda i=7, sha=S, w="gate.yml", s="success": {"index_in_repo": i, "commit_sha": sha, "workflow_id": w, "status": s}  # noqa: E731,E501
cases = [([st()], [rn()], U),                                   # genuine success of another gate.yml run: reuse
         ([st("failure"), st()], [rn()], None),                 # newest gate/nas counts, and it is red
         ([], [rn()], None), ([st("pending")], [rn()], None),   # no status / still running
         ([st(c={"login": "x"})], [rn()], None),                # set by an account, not by Actions
         ([st(u="/e/r/actions/runs/7")], [rn()], None),         # run of another repo
         ([st(u=U[:-1] + "9")], [rn(9)], None),                 # points to this very run
         ([st()], [rn(8)], None), ([st()], [rn(sha="b" * 40)], None),  # no such run / run of another SHA
         ([st()], [rn(w="x.yml")], None), ([st()], [rn(s="failure")], None),  # other workflow / failed run
         ([st()], None, None)]                                  # runs list missing
bad = [i for i, (s, r, want) in enumerate(cases) if ns["reusable"](s, r, R, S, 9)[0] != want]
bad += [] if WF.index('"$EVENT" = push') < min(WF.index("gate-status pending"), WF.index("git fetch")) else ["order"]
bad += [] if "echo green=true" in WF and "needs.nas.outputs.green != 'true'" in WF else ["wiring"]
print(f"{'FAIL ' + str(bad) if bad else 'OK'}: {len(cases)} reuse cases, decision before pending/fetch"); sys.exit(1 if bad else 0)  # noqa: E702
