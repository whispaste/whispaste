## 2024-08-04 - Missing ARIA Labels in Flutter IconButtons
**Learning:** IconButton widgets in Flutter only provide a Semantics hint via their `tooltip` property, not a true Semantics name/label. Similarly, InkWell wrapped in Tooltip also does not announce a reliable label to screen readers.
**Action:** Always wrap `IconButton` or interactive `Tooltip` widgets with `Semantics(label: ..., button: true)` to ensure screen readers properly announce the action to users.
