## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead. Note: Do not apply to `WpSearchableListPage._filtered`.

## 2026-08-16 - REJECTED, do not resubmit: RegExp-precompile on `WpSearchableListPage._filtered`
**Rejected 11 times** (#39, #40, #44, #48, #50, #53, #55, #58, #61, #63, #64) — this is the single most
resubmitted PR in this repo's history. The 2024-05-18 entry above is true in general but does **not**
apply to this specific call site, and applying it there anyway is exactly what caused the loop:
`WpSearchableListPage._filtered` runs over Snippets/Replacements lists that are typically a few dozen
items — the maintainer has stated repeatedly (#58, #61) that the claimed win is unbenchmarked and the
regex still gets recompiled once per keystroke either way, so there's no measured improvement to point
to. **Do not propose this again without an actual before/after benchmark number in the PR body** (e.g.
`dart run tool/bench_search_filter.dart` output, or equivalent instrumented timing) — a generic
"reduces GC pressure" claim is not sufficient and will be closed on sight.
**Meta-lesson:** before opening a perf PR that touches search/filter loops, run
`gh pr list --state closed --search "<the widget/file name>"` and read the closing comments — merged
`git log` on `dev` only shows *accepted* changes; it will never show you the 10 times this exact idea
was already rejected, because rejected PRs never touch `dev`.

## 2025-01-20 - GC pressure during vocabulary import review
**Learning:** In Flutter lists doing string matching inside a tight loop over thousands of records (e.g., vocabulary candidates), using `.toLowerCase()` forces O(N) heap allocations for lowercased Strings on every keystroke, leading to high GC pressure.
**Action:** For large lists (10k+ items), precompile a `RegExp` with `caseSensitive: false` and `RegExp.escape(query)` before the loop, and use `regex.hasMatch(item)` instead, turning O(N) allocations into O(1) overhead. (As noted previously, do NOT apply this to small lists like `WpSearchableListPage._filtered`).

## 2026-09-04 - REJECTED: Silencing CI checks for transient errors
**Rejected:** Attempted to fix a transient 503 error from `npm audit` by setting `continue-on-error: true` in `.github/workflows/ci.yml`.
**Learning:** Never artificially make CI checks green by disabling strict failure conditions (e.g., `continue-on-error: true`), as this hides legitimate future failures. If an external service like `registry.npmjs.org` throws 503s intermittently, the correct fix is implementing retry logic with backoff, not bypassing the check.
**Action:** If a CI job fails due to an external/transient issue, implement a retry mechanism or wait for the maintainer to fix it. Do not change CI configuration to ignore failures without explicit instruction.
