## 2025-02-23 - Added Copy Button to History Notes
**Learning:** Adding a copy button to a list item using existing helper functions (`copyToClipboardWithToast`) and existing string resources (`L10n.of(context).notesCopy`) is a highly valuable, low-risk product improvement that leverages existing infrastructure. It follows established Flutter UI patterns using `Semantics`, `Tooltip`, and `InkWell`.
**Action:** When acting as Sprout, look for missing common actions (like copy, duplicate, or delete) on existing list items or detail views, and implement them using the same patterns and helpers already present in the codebase.

## 2024-05-27 - Added Copy and Duplicate Actions to Replacements List
**Learning:** Consistently adding standard list item actions (copy, duplicate) where they are missing (e.g. Replacements page lacked actions present on Snippets page) is a safe and obvious Sprout pattern. We can reuse established components like `WpRowAction`, standard localization strings (`actionCopy`, `actionDuplicate`), and shared utilities (`copyToClipboardWithToast`).
**Action:** When working on lists, check if standard actions like Copy, Duplicate, or Delete are available on all similar lists, and port them over if they are missing using existing building blocks.
## 2025-02-18 - Note Copy Action and Telemetry Avoidance
**Learning:** In WhisPaste, note contents are explicitly on a telemetry negative list (unlike history entries). When adding standard actions like copying notes to the clipboard, do not reuse the general `copyToClipboardWithToast` utility because it emits a telemetry event.
**Action:** Sprout should use `Clipboard.setData(ClipboardData(text: content))` followed by `WpToast.show(...)` directly when working with privacy-sensitive content like notes.

## 2025-03-01 - Add Note Duplication action
**Learning:** Extending list item actions by reusing existing infrastructure, such as standard icons (`LucideIcons.files`) and translation strings (`L10n.of(context).actionDuplicate`), is a reliable way to fulfill Sprout tasks across similar view types (e.g. extending features from Snippets to Notes). When manipulating data stored in SQLite, mirroring the existing write operations (like `duplicateEntry` logic from `database.dart`) is essential to preserve data safety.
**Action:** When adding missing actions to a list, carefully verify if underlying database actions exist. If not, safely mirror existing database methods, ensuring complete callback plumbing down through widget trees (`NotesSplitView` -> `NotesListView` -> `NotesListTile` -> `NoteEditorPanel`).
## 2025-03-02 - Add duplicate action to note editor toolbar
**Learning:** Adding a button to the NoteEditorPanel toolbar for an action (like Duplicate) that is already supported and plumbed through the widget tree (via `onDuplicate` callback) is a low-risk, high-value Sprout task. It exposes existing functionality.
**Action:** Always verify if an action already has a callback passed into the widget when considering exposing it in the UI. If it does, implementing it is as simple as adding the UI element. When adding a new required field to a mock class (or discovering an existing one was not mocked everywhere), be sure to update all test usages.

## 2025-03-05 - Notes List Tile Trash View Action Consistency
**Learning:** In WhisPaste, some actions like "Copy" or "Duplicate" on list tiles can be mistakenly hidden in specific modes (like trash view) simply because their layout was isolated inside a conditionally rendered block. This creates a consistency gap with the Detail/Editor panel which successfully shows those actions on trashed items.
**Action:** When working as Sprout to unify UI actions, verify that standard actions are structurally placed *outside* mutually-exclusive layout blocks (e.g., `isTrashView` conditionals) when they apply to all states.

## 2025-03-05 - Notes List Tile Trash View Action Consistency
**Learning:** In WhisPaste, adding missing common actions (like `MoveToTrash`) to list tiles significantly reduces repetitive multi-click workflows. When extending `WpRowActions` on list tiles, it's crucial to correctly scope destructive actions using the existing view states (e.g., placing `MoveToTrash` inside `!widget.isTrashView`), and completely thread the callbacks through intermediate lists down from the main view controller. Also, introducing `required` callbacks means all test constructor calls must be updated across the suite.
**Action:** When implementing new standard actions on list tiles, carefully manage their visibility based on the current view mode (e.g., Trash vs. Normal). Ensure the newly added required callback parameters are threaded through the entire widget subtree and explicitly updated in all related test files to avoid CI failures.
