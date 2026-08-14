## 2024-05-18 - RegExp.escape is required for dynamic search inputs
**Learning:** When replacing `toLowerCase()` string filtering with precompiled `RegExp(..., caseSensitive: false)` for performance in tight loops, you must wrap user input in `RegExp.escape(query)` to prevent regex engine crashes when users type special characters (like `*`, `?`, `[`).
**Action:** Always validate and escape dynamic input before passing it to the RegExp constructor.
## 2024-05-18 - Search across test/ when modifying shared widget signatures
**Learning:** When refactoring a callback signature (like changing `searchMatches: (T, String)` to `searchMatches: (T, RegExp)`) for performance in a shared widget, `grep` must be used across the `test/` directory to update mock implementations in UI tests to prevent CI type-checking failures.
**Action:** Always search both `lib/` and `test/` when updating a widget API.
