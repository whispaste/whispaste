## 2025-10-18 - Accessibility on interactive text widgets
**Learning:** Interactive text widgets handled via `GestureDetector` (e.g. click-to-edit text blocks) rely on tooltips for sighted users but do not inherently announce themselves as interactive to screen readers.
**Action:** Always wrap interactive `GestureDetector` regions with `Semantics(button: true, label: ...)` to ensure screen reader users are aware the text area can be interacted with.

## 2026-08-16 - Caveat on the rule above: don't nest interactive children inside the new `Semantics(button: true)`
**Rejected/flagged:** #31, #34, #38, #41, #43, #51, #56, #57, #60, and now #65 all apply the 2025-10-18
rule to a *row* that already contains its own interactive child (an icon button, a `VoiceNoteButton`,
etc.), not a plain text block. Wrapping the whole row in an outer `Semantics(button: true, label: X)`
then nests an unrelated interactive control (and sometimes a second, already-`Semantics(button: true)`
icon button with the *same* label) inside it — screen readers announce "X, button" twice for two
different-looking targets that do the same thing, and switch-control users get a button-inside-a-button.
#60's core idea was correct but its accompanying test-fix commit broke two golden-adjacent tests, so it
was closed rather than merged, and the lesson was manually reapplied by the maintainer in `67cd2008`
instead — that manual fix is the actual reference implementation.
**Corrected action:** only wrap the *smallest* region that (a) has no interactive descendants of its own
and (b) isn't already covered by another explicit `Semantics(button: true)`. If the row already has a
dedicated icon button doing the same action, wrapping the row is redundant — either extend the existing
button's hit area, or remove the now-duplicate inner button, but never both.
## 2026-08-28 - Keyboard focus on custom icon buttons
**Learning:** Custom interactive elements built with `GestureDetector` inside an `AnimatedContainer` lack keyboard focus support. Wrapping them in `InkWell` with a shared `FocusNode` and `WpFocusRing` solves this. To prevent `InkWell`'s default visual feedback from clashing with the existing `AnimatedContainer`'s hover state, set the `InkWell`'s `focusColor`, `hoverColor`, `splashColor`, and `highlightColor` all to `Colors.transparent`.
**Action:** Use `InkWell` with transparent interaction colors and a shared `FocusNode` wrapped in `WpFocusRing` when converting custom `GestureDetector` buttons to support keyboard accessibility without altering their visual hover styles.
