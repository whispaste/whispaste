## 2024-05-18 - RegExp.escape is required for dynamic search inputs
**Learning:** When replacing `toLowerCase()` string filtering with precompiled `RegExp(..., caseSensitive: false)` for performance in tight loops, you must wrap user input in `RegExp.escape(query)` to prevent regex engine crashes when users type special characters (like `*`, `?`, `[`).
**Action:** Always validate and escape dynamic input before passing it to the RegExp constructor.
