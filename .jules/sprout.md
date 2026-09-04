## 2025-02-23 - Added Copy Button to History Notes
**Learning:** Adding a copy button to a list item using existing helper functions (`copyToClipboardWithToast`) and existing string resources (`L10n.of(context).notesCopy`) is a highly valuable, low-risk product improvement that leverages existing infrastructure. It follows established Flutter UI patterns using `Semantics`, `Tooltip`, and `InkWell`.
**Action:** When acting as Sprout, look for missing common actions (like copy, duplicate, or delete) on existing list items or detail views, and implement them using the same patterns and helpers already present in the codebase.

## 2024-05-27 - Added Copy and Duplicate Actions to Replacements List
**Learning:** Consistently adding standard list item actions (copy, duplicate) where they are missing (e.g. Replacements page lacked actions present on Snippets page) is a safe and obvious Sprout pattern. We can reuse established components like `WpRowAction`, standard localization strings (`actionCopy`, `actionDuplicate`), and shared utilities (`copyToClipboardWithToast`).
**Action:** When working on lists, check if standard actions like Copy, Duplicate, or Delete are available on all similar lists, and port them over if they are missing using existing building blocks.
## 2025-02-18 - Note Copy Action and Telemetry Avoidance
**Learning:** In WhisPaste, note contents are explicitly on a telemetry negative list (unlike history entries). When adding standard actions like copying notes to the clipboard, do not reuse the general `copyToClipboardWithToast` utility because it emits a telemetry event.
**Action:** Sprout should use `Clipboard.setData(ClipboardData(text: content))` followed by `WpToast.show(...)` directly when working with privacy-sensitive content like notes.
## 2024-05-18 - Note Duplication

**Learning:** When implementing actions that duplicate the currently active entry in a live editor (like a note), it's crucial to first flush any pending autosaves and fetch the live content directly from the editor controller rather than the cached `note` object, to ensure unsaved edits aren't lost in the duplicate.

**Action:** Before duplicating an active entry, call `await _autosave.flush()` and determine the content dynamically: `(note.id == _selectedNoteId) ? _editorController.text : note.content`.
