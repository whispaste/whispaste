## 2024-08-08 - [String Allocation Overhead in Tight Loops]
**Learning:** Dart's `String.toLowerCase()` creates new string allocations. Calling it repeatedly on every item in a tight loop (e.g., during live search filtering) causes unnecessary memory allocations, leading to increased Garbage Collection pressure and potential UI stutter during fast typing.
**Action:** Use a precompiled `RegExp(pattern, caseSensitive: false)` instead of repeated `toLowerCase()` for case-insensitive filtering in tight loops to avoid allocation overhead.
