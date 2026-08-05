## 2024-05-16 - IconButton Semantics

**Learning:** In Flutter, using `IconButton(tooltip: ...)` alone only provides a Semantics hint to screen readers, not a true label. This means the button might be announced incorrectly or just as "button".
**Action:** Always wrap `IconButton` and interactive `Tooltip` widgets in `Semantics(label: ..., button: true)` to ensure proper accessibility labels for screen readers.
