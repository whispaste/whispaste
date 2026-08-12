## 2024-05-18 - Case-insensitive filtering in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart allocates a new String for every item evaluated. In lists of strings like search results or tag lists, this creates massive GC pressure.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead.
## 2025-02-12 - Case-insensitive string search in Dart tight loops
**Learning:** Using `String.toLowerCase()` inside a tight `where` loop in Dart creates massive GC pressure because it allocates a new String for every item evaluated. This was found in `WpSearchableListPage` where it impacted search filtering performance on large lists.
**Action:** Use a precompiled `RegExp` with `caseSensitive: false` before the loop, and use `searchRegex.hasMatch(item)` inside the loop instead. Use `RegExp.escape()` if the search query is literal text.
