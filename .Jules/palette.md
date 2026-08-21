## 2026-08-21 - Keyboard Accessibility with WpFocusRing
**Learning:** In this application, a bare `GestureDetector` inside a `Semantics(button: true)` is reachable by screen readers but remains inaccessible to keyboard users (no Tab focus or Enter activation).
**Action:** Always replace bare `GestureDetector` interactive elements with an `InkWell` wrapped in a `WpFocusRing`, sharing a `FocusNode` to provide complete keyboard accessibility and visual focus states.
