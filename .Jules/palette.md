## 2026-08-13 - Added Tooltip to WpDiscoverabilityHint dismiss button
**Learning:** When using a bare `GestureDetector` as an icon button instead of `IconButton`, you miss out on desktop/web UX essentials like a pointer cursor on hover and a tooltip. Adding `Tooltip` and `MouseRegion` makes it feel like a real button.
**Action:** Always wrap interactive icon-only elements (that aren't natively buttons) in `MouseRegion(cursor: SystemMouseCursors.click)` and `Tooltip` on desktop apps, and ensure they have `Semantics` for screen readers.
