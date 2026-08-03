## 2024-08-03 - Missing Tooltips on Icon-Only Buttons
**Learning:** Found that custom icon-only interactive elements using `InkWell` or `GestureDetector` in this codebase were missing `Tooltip` wrappers, hindering accessibility and usability for screen reader and mouse users.
**Action:** Always verify that icon-only buttons (`InkWell`, `GestureDetector`, etc.) have `Tooltip` or `Semantics` wrappers, and apply them using localized strings if absent.
