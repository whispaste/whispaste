## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead.
## 2025-02-18 - String allocations in tight loops
**Learning:** `toLowerCase()` allocates new strings for every item evaluated during search filtering loops, which is wasteful and hurts performance compared to regex.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` outside the loop when doing list filtering, instead of dynamically lowercasing properties inside the loop.
