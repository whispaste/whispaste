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
## 2026-08-17 - Precompiled RegExp vs toLowerCase().contains() for short constant strings
**Learning:** For a single, small, constant marker string check across a short text loop (like parsing a handful of `stderr` lines in an error path), precompiling a case-insensitive `RegExp` and calling `hasMatch()` is actually *slower* in Dart than a plain `toLowerCase().contains()`. The theorized GC pressure reduction does not translate to a real-world performance improvement for this scenario. Furthermore, optimizing cold/error paths violates the rule against micro-optimizations that have no user-visible impact.
**Action:** Do not use `RegExp` precompilation to replace `toLowerCase().contains()` for small strings or on cold/error paths. Always benchmark your specific use case first and only submit performance PRs for hot paths where the improvement clears the bar.
