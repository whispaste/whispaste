## 2024-08-06 - Missing Semantics in IconButton
**Learning:** In Flutter, `IconButton` and interactive `Tooltip` widgets only provide a Semantics hint, not a true label for screen readers. This leaves icon-only buttons inaccessible.
**Action:** For accessibility, always wrap them in `Semantics(label: ..., button: true)`.
