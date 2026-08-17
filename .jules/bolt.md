## 2024-11-20 - RegExp optimization in list filtering
**Learning:** In Dart tight loops (like `Iterable.where`), `String.toLowerCase()` creates substantial allocation overhead and GC pressure.
**Action:** Compile a case-insensitive `RegExp` (with `RegExp.escape` for safety) once per query, and use `RegExp.hasMatch` on items instead of repeatedly lowercasing them.
