## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead.

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

## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead. Note: Do not apply to `WpSearchableListPage._filtered`.

## 2024-05-24 - Precompiled RegExp for Case-Insensitive Matching
**Learning:** For case-insensitive string filtering in Dart tight loops (like `Iterable.where` or `for` comprehensions) targeting large lists (like `SidePanelRow`), `String.toLowerCase()` creates a new string allocation for every iteration on every element inspected, causing significant GC spikes. Note the exception around WpSearchableListPage which operates on very small datasets.
**Action:** Use a precompiled `RegExp(..., caseSensitive: false)` outside the loop to vastly improve memory efficiency and speed by avoiding per-item allocations.
