## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead.
## 2026-08-10 - Pre-compile case-insensitive RegExps for tight loops
**Learning:** Calling `.toLowerCase()` repeatedly inside `where()` clauses in Dart search logic can cause performance hits by allocating a new String for every iteration.
**Action:** Instead of `target.toLowerCase().contains(query)`, pre-compile `RegExp(RegExp.escape(query), caseSensitive: false)` before the loop and use `.hasMatch(target)` inside the loop.
